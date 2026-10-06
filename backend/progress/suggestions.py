"""Suggestion notifications generated from a student's weekly report."""

from __future__ import annotations

from typing import Any

from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository

from .config import THRESHOLDS
from .models import StudentTwin
from .service import build_student_twin
from .weekly_report import build_weekly_report

Repository = StudentRepository | PostgresStudentRepository

MAX_SUGGESTIONS_PER_WEEK = 5
GROUP_GAP_POINTS = 10.0
_PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2}


def _suggestion(code: str, priority: str, title: str, body: str, course_id: str = "") -> dict[str, Any]:
    return {"code": code, "priority": priority, "title": title, "body": body, "course_id": course_id}


def build_suggestions(report: dict[str, Any], twin: StudentTwin) -> list[dict[str, Any]]:
    """Return up to MAX_SUGGESTIONS_PER_WEEK suggestions, most urgent first."""
    items: list[dict[str, Any]] = []
    twin_courses = {course.course_id: course for course in twin.courses}

    for course_report in report["courses"]:
        course_id = course_report["course_id"]
        name = course_report["course_name"]
        course = twin_courses[course_id]
        next_lecture = course.unstudied_lectures[0] if course.unstudied_lectures else None
        next_step = (f" Start with Lecture {next_lecture.lecture_number}: {next_lecture.title}."
                     if next_lecture else "")

        if course_report["risk_level"] == "high":
            top = next((r for r in course_report["risks"] if r["severity"] == "high"), None)
            items.append(_suggestion(
                "focus_course", "high", f"Make {name} your priority this week",
                f"{top['message'] if top else 'This course has high-severity risk signals.'}{next_step}",
                course_id,
            ))

        change = course_report["change"]
        if change is not None and change <= -THRESHOLDS.significant_weekly_change:
            items.append(_suggestion(
                "health_drop", "high" if course_report["risk_level"] == "high" else "medium",
                f"{name} dropped {abs(change):.0f} points",
                f"Course health fell from {course_report['previous_health']:.0f} to "
                f"{course_report['health']:.0f}. Review what changed since last week.{next_step}",
                course_id,
            ))

        upcoming_exam = next((
            a for a in sorted(course.assessments, key=lambda a: a.due_week)
            if a.assessment_type in {"midterm", "final", "exam"} and a.percentage is None
            and 0 <= a.due_week - twin.current_week <= THRESHOLDS.upcoming_assessment_weeks
        ), None)
        if upcoming_exam is not None:
            pending = [lecture for lecture in course.unstudied_lectures
                       if lecture.lecture_id in upcoming_exam.covered_lecture_ids]
            if pending:
                weeks = upcoming_exam.due_week - twin.current_week
                when = "this week" if weeks == 0 else f"in {weeks} week{'s' if weeks != 1 else ''}"
                items.append(_suggestion(
                    "exam_prep", "high" if weeks <= 1 else "medium",
                    f"Prepare for {upcoming_exam.name}",
                    f"{upcoming_exam.name} is {when} and {len(pending)} covered lecture(s) are not "
                    f"complete. Next: Lecture {pending[0].lecture_number}, {pending[0].title}.",
                    course_id,
                ))

        if (course_report["lecture_completion"] < THRESHOLDS.lecture_backlog_percentage
                and course_report["risk_level"] != "high" and next_lecture is not None):
            items.append(_suggestion(
                "lecture_catchup", "medium", f"Catch up on {name} lectures",
                f"{len(course.unstudied_lectures)} available lecture(s) are not marked complete "
                f"({course_report['lecture_completion']:.0f}% done).{next_step}",
                course_id,
            ))

        if course_report["course_id"] in report["activity"]["attendance"]["absent_course_ids"]:
            items.append(_suggestion(
                "missed_session", "medium", f"You missed a {name} session",
                "Review the lecture material for the session you missed and ask your instructor "
                "about anything you cannot cover alone.",
                course_id,
            ))

        if change is not None and change >= 5 and not course_report["risks"]:
            items.append(_suggestion(
                "keep_going", "low", f"{name} is improving",
                f"Course health rose from {course_report['previous_health']:.0f} to "
                f"{course_report['health']:.0f}. Keep the study routine that produced this.",
                course_id,
            ))

    group = report.get("group")
    if group and group["difference_from_group"] is not None \
            and group["difference_from_group"] <= -GROUP_GAP_POINTS:
        items.append(_suggestion(
            "group_gap", "medium", "You are behind your schedule group",
            f"Your overall health is {abs(group['difference_from_group']):.0f} points below the "
            f"average for students on your schedule ({group['name']}). Consider reviewing "
            "the material your group has covered.",
        ))

    items.sort(key=lambda item: (_PRIORITY_ORDER[item["priority"]], item["code"], item["course_id"]))
    return items[:MAX_SUGGESTIONS_PER_WEEK]


def generate_suggestions(
    repository: Repository, student_id: str, report: dict[str, Any] | None = None,
    twin: StudentTwin | None = None,
) -> list[dict[str, Any]] | None:
    """Create and store this week's suggestions; return only the new ones.

    Returns None when the student does not exist.
    """
    twin = twin or build_student_twin(repository, student_id)
    if twin is None:
        return None
    report = report or build_weekly_report(repository, student_id, twin)
    if report is None:
        return None
    return repository.save_suggestions(
        student_id, twin.semester, twin.current_week, build_suggestions(report, twin)
    )
