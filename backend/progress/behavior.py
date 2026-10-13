"""Advisor AI suggestions based on how a student actually uses UniTrack.

Activity is logged from the three places a student works: the desktop
*workspace*, the mobile *app*, and the *website* portal.  Each rule below looks
only at logged events (plus the progress data the app already has) and states
what it saw, so a suggestion never claims something the data does not show.
Rules are deterministic; nothing here is written by a language model.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from typing import Any

from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository

from .models import CourseTwin, StudentTwin
from .service import build_student_twin

Repository = StudentRepository | PostgresStudentRepository

EVENT_TYPES = frozenset({
    "login", "workspace_create", "workspace_vscode", "advisor_question",
    "material_view", "grades_view", "plan_update", "schedule_view",
    "notification_read", "screen_view",
})
SOURCES = ("workspace", "app", "website")

HISTORY_DAYS = 14          # events loaded for analysis
WINDOW_DAYS = 7            # "this week" for the rules
BREAK_DAYS = 3             # a gap this long counts as a break
CONSISTENT_DAYS = 5
ADVISOR_REPEAT = 3
MAX_BEHAVIOR_SUGGESTIONS = 3
_PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2}


@dataclass
class BehaviorSummary:
    active_days: int = 0
    total_events: int = 0
    by_source: dict[str, int] = field(default_factory=dict)
    workspace_actions: int = 0
    course_activity: dict[str, int] = field(default_factory=dict)
    advisor_questions: int = 0
    top_advisor_topic: tuple[str, int] | None = None
    plan_updates: int = 0
    break_days: int | None = None   # days away before today's return, if any


def _active_dates(events: list[dict[str, Any]]) -> set[date]:
    return {event["occurred_at"].astimezone(UTC).date() for event in events}


def summarize_behavior(events: list[dict[str, Any]], now: datetime) -> BehaviorSummary:
    window_start = now - timedelta(days=WINDOW_DAYS)
    recent = [e for e in events if e["occurred_at"] >= window_start]
    summary = BehaviorSummary(total_events=len(recent), active_days=len(_active_dates(recent)))
    by_source: Counter[str] = Counter(e["source"] for e in recent)
    summary.by_source = {name: by_source[name] for name in SOURCES if by_source[name]}
    course_activity: Counter[str] = Counter()
    topics: Counter[str] = Counter()
    for event in recent:
        kind = event["event_type"]
        if kind in {"workspace_create", "workspace_vscode"}:
            summary.workspace_actions += 1
        if kind in {"workspace_create", "workspace_vscode", "material_view"} and event.get("course_ref"):
            course_activity[str(event["course_ref"]).casefold()] += 1
        if kind == "advisor_question":
            summary.advisor_questions += 1
            if event.get("detail"):
                topics[str(event["detail"])] += 1
        if kind == "plan_update":
            summary.plan_updates += 1
    summary.course_activity = dict(course_activity)
    if topics:
        topic, count = topics.most_common(1)[0]
        summary.top_advisor_topic = (topic, count)

    # A "break" is a gap of BREAK_DAYS+ between today's activity and the last day before it.
    dates = sorted(_active_dates(events))
    today = now.astimezone(UTC).date()
    if dates and dates[-1] == today and len(dates) >= 2:
        gap = (today - dates[-2]).days
        if gap >= BREAK_DAYS:
            summary.break_days = gap
    return summary


def _course_count(summary: BehaviorSummary, course: CourseTwin) -> int:
    return (summary.course_activity.get(course.course_id.casefold(), 0)
            + summary.course_activity.get(course.course_name.casefold(), 0))


def _next_step(course: CourseTwin) -> str:
    if course.unstudied_lectures:
        lecture = course.unstudied_lectures[0]
        return f"Start with Lecture {lecture.lecture_number}: {lecture.title}."
    return "Review its latest material."


def _where(summary: BehaviorSummary) -> str:
    return ", ".join(f"{name} {count}" for name, count in summary.by_source.items())


def _suggestion(code: str, priority: str, title: str, body: str, course_id: str = "") -> dict[str, Any]:
    return {"code": code, "priority": priority, "title": title, "body": body, "course_id": course_id}


def build_behavior_suggestions(
    summary: BehaviorSummary, twin: StudentTwin, plan_items: list[dict[str, Any]], now: datetime,
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    flagged = sorted(
        (c for c in twin.courses if c.risk_level in {"high", "medium"}),
        key=lambda c: (_PRIORITY_ORDER[c.risk_level or "low"], c.course_name),
    )
    pending = [item for item in plan_items if item.get("status") == "pending"]

    if summary.break_days is not None:
        if flagged:
            focus = f"{flagged[0].course_name} needs attention first. {_next_step(flagged[0])}"
        elif pending:
            focus = f"You have {len(pending)} weekly plan task(s) waiting."
        else:
            focus = "Pick up where you left off."
        items.append(_suggestion(
            "behavior_return", "medium", "Welcome back",
            f"You were away from UniTrack for {summary.break_days} days. {focus}",
        ))

    if summary.active_days >= 2:
        for course in flagged[:2]:
            if _course_count(summary, course) == 0:
                items.append(_suggestion(
                    "behavior_neglected", "high" if course.risk_level == "high" else "medium",
                    f"No recent activity in {course.course_name}",
                    f"You were active on {summary.active_days} of the last {WINDOW_DAYS} days "
                    f"({_where(summary)}), but nothing for {course.course_name}, which is flagged "
                    f"{course.risk_level} risk. {_next_step(course)}",
                    course.course_id,
                ))

    if summary.active_days >= 3 and summary.workspace_actions == 0 and twin.courses:
        target = (flagged or list(twin.courses))[0]
        items.append(_suggestion(
            "behavior_workspace_unused", "low", "Try a course workspace",
            f"You were active on {summary.active_days} days this week but have not opened a "
            f"course workspace. A workspace gives you a place to practise {target.course_name}.",
            target.course_id,
        ))

    if summary.top_advisor_topic and summary.top_advisor_topic[1] >= ADVISOR_REPEAT:
        topic, count = summary.top_advisor_topic
        label = topic.replace("_", " ")
        items.append(_suggestion(
            "behavior_advisor_repeat", "medium", f"Repeated questions about {label}",
            f"You asked Advisor AI about {label} {count} times this week. Review the related "
            "course material, or bring the question to your instructor.",
        ))

    days_into_week = (now.astimezone(UTC).weekday() - 5) % 7  # the academic week starts Saturday
    if (len(pending) >= 3 and not any(i.get("status") == "completed" for i in plan_items)
            and summary.plan_updates == 0 and days_into_week >= 3):
        items.append(_suggestion(
            "behavior_plan_stalled", "medium", "Your weekly plan has not started",
            f"None of your {len(plan_items)} weekly plan tasks is marked done yet. "
            f"Start with: {pending[0]['title']}.",
        ))

    if summary.active_days >= CONSISTENT_DAYS:
        items.append(_suggestion(
            "behavior_consistent", "low", "Strong study consistency",
            f"You were active on {summary.active_days} of the last {WINDOW_DAYS} days "
            f"({_where(summary)}). Keep this routine going.",
        ))

    items.sort(key=lambda item: (_PRIORITY_ORDER[item["priority"]], item["code"], item["course_id"]))
    return items[:MAX_BEHAVIOR_SUGGESTIONS]


def generate_behavior_suggestions(
    repository: Repository, student_id: str, twin: StudentTwin | None = None,
    now: datetime | None = None,
) -> list[dict[str, Any]] | None:
    """Analyse recent activity and store new suggestions; returns only the new ones.

    Returns None for an unknown student and [] when there is no activity yet
    (no behaviour has been observed, so there is nothing to advise on).
    """
    twin = twin or build_student_twin(repository, student_id)
    if twin is None:
        return None
    now = now or datetime.now(UTC)
    events = repository.get_recent_activity(student_id, now - timedelta(days=HISTORY_DAYS))
    if not events:
        return []
    summary = summarize_behavior(events, now)
    plan_items = repository.get_weekly_plan_items(student_id, twin.semester, twin.current_week)
    suggestions = build_behavior_suggestions(summary, twin, plan_items, now)
    return repository.save_suggestions(student_id, twin.semester, twin.current_week, suggestions)
