"""Week-by-week performance reports, built only from recorded data."""

from __future__ import annotations

from statistics import fmean
from typing import Any

from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository

from .config import THRESHOLDS
from .metrics import metrics_as_snapshot
from .models import StudentTwin
from .scoring import student_score
from .service import build_student_twin

Repository = StudentRepository | PostgresStudentRepository

TREND_STEP = 5.0


def _change(current: float | None, previous: float | None) -> float | None:
    if current is None or previous is None:
        return None
    return round(current - previous, 2)


def _trend(change: float | None) -> str:
    if change is None:
        return "new"
    if change >= TREND_STEP:
        return "improving"
    if change <= -TREND_STEP:
        return "declining"
    return "stable"


def _round(value: float | None) -> float | None:
    return None if value is None else round(value, 2)


def _attendance_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    counts = {"Present": 0, "Absent": 0, "Late": 0, "Excused": 0}
    for row in rows:
        status = str(row.get("status"))
        if status in counts:
            counts[status] += 1
    return {
        "sessions": sum(counts.values()),
        "present": counts["Present"], "absent": counts["Absent"],
        "late": counts["Late"], "excused": counts["Excused"],
        "absent_course_ids": sorted({str(r["course_id"]) for r in rows if r.get("status") == "Absent"}),
    }


def _group_context(
    repository: Repository, student_id: str, semester: str, week: int, overall_health: float | None
) -> dict[str, Any] | None:
    """Compare the student with everyone else on the same schedule."""
    schedule = repository.get_student_schedule(student_id, semester)
    if schedule is None:
        return None
    members = [m for m in repository.get_schedule_group(schedule["schedule_id"])
               if m["student_id"] != student_id]
    member_healths: list[float] = []
    for member in members:
        week_rows = [row["course_health"] for row in repository.get_weekly_snapshots(member["student_id"])
                     if row["week_number"] == week]
        if week_rows:
            member_healths.append(float(fmean(week_rows)))
    group_average = _round(fmean(member_healths)) if member_healths else None
    return {
        "schedule_id": schedule["schedule_id"], "name": schedule["name"],
        "size": schedule["member_count"],
        "peers_with_data": len(member_healths),
        "group_average_health": group_average,
        "difference_from_group": _change(overall_health, group_average),
    }


def build_weekly_report(
    repository: Repository, student_id: str, twin: StudentTwin | None = None
) -> dict[str, Any] | None:
    """Assemble the report for the student's current academic week."""
    twin = twin or build_student_twin(repository, student_id)
    if twin is None:
        return None
    raw = repository.get_student_progress(student_id) or {"courses": []}
    raw_by_course = {course["course_id"]: course for course in raw["courses"]}
    week = twin.current_week

    courses: list[dict[str, Any]] = []
    for course in twin.courses:
        raw_course = raw_by_course.get(course.course_id, {"lectures": [], "assessments": []})
        lectures_this_week = [
            lecture for lecture in raw_course["lectures"]
            if lecture["completed"] and int(lecture.get("completed_week") or 0) == week
        ]
        graded_this_week = [
            {"name": a["name"], "type": a["assessment_type"], "percentage": a["percentage"]}
            for a in raw_course["assessments"]
            if int(a["due_week"]) == week and a["percentage"] is not None
        ]
        due_not_graded = [
            a["name"] for a in raw_course["assessments"]
            if int(a["due_week"]) <= week and a["percentage"] is None
        ]
        metrics = course.metrics
        change = _change(metrics.course_health, metrics.previous_course_health)
        courses.append({
            "course_id": course.course_id, "course_name": course.course_name,
            "health": metrics.course_health,
            "previous_health": metrics.previous_course_health,
            "change": change,
            "trend": _trend(change) if change is not None else metrics.trend,
            "weighted_grade": metrics.weighted_grade,
            "lecture_completion": metrics.lecture_completion,
            "assessment_completion": metrics.assessment_completion,
            "lectures_completed_this_week": len(lectures_this_week),
            "assessments_graded_this_week": graded_this_week,
            "assessments_missing_grade": due_not_graded,
            "risk_level": course.risk_level,
            "risks": [{"code": r.code, "severity": r.severity, "message": r.message}
                      for r in course.risks],
        })

    healths = [c["health"] for c in courses if c["health"] is not None]
    previous = [c["previous_health"] for c in courses if c["previous_health"] is not None]
    overall = twin.overall_academic_health
    previous_overall = _round(fmean(previous)) if previous else None
    overall_change = _change(overall, previous_overall) if healths else None

    score = student_score(repository, student_id) or {"weekly": [], "score": 0}
    week_points = next((row for row in score["weekly"] if row["week"] == week), None)
    attendance = _attendance_summary(
        repository.get_student_week_attendance(student_id, twin.semester, week)
    )

    highlights: list[str] = []
    concerns: list[str] = []
    for course in courses:
        name = course["course_name"]
        if course["change"] is not None and course["change"] >= TREND_STEP and not course["risks"]:
            highlights.append(f"{name} improved by {course['change']:.0f} points to {course['health']:.0f}.")
        if course["change"] is not None and course["change"] <= -THRESHOLDS.significant_weekly_change:
            concerns.append(f"{name} dropped by {abs(course['change']):.0f} points to {course['health']:.0f}.")
        for graded in course["assessments_graded_this_week"]:
            if graded["percentage"] >= 85:
                highlights.append(f"Scored {graded['percentage']:.0f}% on {graded['name']} ({name}).")
        top_risk = next((risk for risk in course["risks"] if risk["severity"] == "high"), None)
        if top_risk is not None:  # one headline concern per course keeps the report readable
            concerns.append(f"{name}: {top_risk['message']}")
    if attendance["absent"]:
        concerns.append(f"Missed {attendance['absent']} session(s) this week.")
    if week_points and week_points["lectures"]:
        highlights.append(f"Completed {week_points['lectures']} lecture(s) this week.")

    group = _group_context(repository, student_id, twin.semester, week, overall)
    if group and group["difference_from_group"] is not None:
        diff = group["difference_from_group"]
        if diff <= -10:
            concerns.append(f"Overall health is {abs(diff):.0f} points below the average of your schedule group.")
        elif diff >= 10:
            highlights.append(f"Overall health is {diff:.0f} points above the average of your schedule group.")

    report: dict[str, Any] = {
        "student": {"student_id": twin.student.student_id, "name": twin.student.name},
        "semester": twin.semester,
        "week": week,
        "overall": {
            "health": overall, "previous_health": previous_overall,
            "change": overall_change, "trend": _trend(overall_change),
        },
        "courses": courses,
        "activity": {
            "lectures_completed": sum(c["lectures_completed_this_week"] for c in courses),
            "attendance": attendance,
            "points_this_week": week_points["points"] if week_points else 0,
            "total_points": score["score"],
        },
        "group": group,
        "highlights": highlights,
        "concerns": concerns,
    }
    report["summary"] = build_report_summary(report)
    return report


def build_report_summary(report: dict[str, Any]) -> str:
    """Short plain-language summary derived only from the report's own facts."""
    first_name = (report["student"]["name"] or "Student").split()[0]
    overall = report["overall"]
    parts = [f"Week {report['week']} report for {first_name}."]
    if overall["health"] is None:
        parts.append("There is not enough recorded work yet to calculate academic health.")
    else:
        parts.append(f"Overall academic health is {overall['health']:.0f}/100.")
        if overall["change"] is not None:
            direction = "up" if overall["change"] > 0 else "down" if overall["change"] < 0 else "unchanged"
            if direction == "unchanged":
                parts.append("That is unchanged from last week.")
            else:
                parts.append(f"That is {direction} {abs(overall['change']):.0f} points from last week.")
        else:
            parts.append("This is the first week with a comparison baseline.")
    if report["highlights"]:
        parts.append("Highlights: " + " ".join(report["highlights"][:3]))
    if report["concerns"]:
        parts.append("Needs attention: " + " ".join(report["concerns"][:3]))
    if not report["highlights"] and not report["concerns"] and overall["health"] is not None:
        parts.append("No notable changes this week; keep the current pace.")
    return " ".join(parts)


def generate_weekly_report(
    repository: Repository, student_id: str, save_snapshots: bool = True
) -> dict[str, Any] | None:
    """Build, store, and return the current week's report."""
    twin = build_student_twin(repository, student_id)
    if twin is None:
        return None
    if save_snapshots:
        for course in twin.courses:
            if course.metrics.course_health is None:
                continue
            repository.save_weekly_snapshot(
                student_id, course.course_id, twin.current_week,
                metrics_as_snapshot(course.metrics, course.risk_level or "none"),
            )
    report = build_weekly_report(repository, student_id, twin)
    if report is None:
        return None
    repository.save_weekly_report(
        student_id, twin.semester, twin.current_week, report, report["summary"]
    )
    return report


def weekly_tracking(repository: Repository, student_id: str) -> list[dict[str, Any]]:
    """One row per week for charts: overall health, change, points, risk count."""
    rows: list[dict[str, Any]] = []
    for stored in repository.list_weekly_reports(student_id):
        report = stored["report"]
        rows.append({
            "semester": stored["semester"], "week": stored["week_number"],
            "overall_health": report["overall"]["health"],
            "change": report["overall"]["change"],
            "trend": report["overall"]["trend"],
            "lectures_completed": report["activity"]["lectures_completed"],
            "points_this_week": report["activity"]["points_this_week"],
            "absences": report["activity"]["attendance"]["absent"],
            "high_risks": sum(1 for c in report["courses"] for r in c["risks"] if r["severity"] == "high"),
        })
    return rows


def group_weekly_summary(
    repository: Repository, schedule_id: str, semester: str, week: int
) -> dict[str, Any] | None:
    """Staff view: how a whole schedule group did in a given week."""
    schedule = repository.get_schedule(schedule_id)
    if schedule is None:
        return None
    members = repository.get_schedule_group(schedule_id)
    entries: list[dict[str, Any]] = []
    for member in members:
        stored = repository.get_weekly_report(member["student_id"], semester, week)
        report = stored["report"] if stored else None
        entries.append({
            "student_id": member["student_id"], "name": member["name"],
            "has_report": report is not None,
            "overall_health": report["overall"]["health"] if report else None,
            "change": report["overall"]["change"] if report else None,
            "high_risks": sum(1 for c in report["courses"] for r in c["risks"] if r["severity"] == "high") if report else 0,
            "absences": report["activity"]["attendance"]["absent"] if report else 0,
        })
    scored = [e["overall_health"] for e in entries if e["overall_health"] is not None]
    return {
        "schedule": {"schedule_id": schedule["schedule_id"], "name": schedule["name"],
                     "semester": schedule["semester"]},
        "week": week,
        "members": len(members),
        "reports_available": len(scored),
        "average_health": _round(fmean(scored)) if scored else None,
        "at_risk": [e for e in entries if e["high_risks"] > 0 or (
            e["overall_health"] is not None and e["overall_health"] < THRESHOLDS.low_health)],
        "students": entries,
    }
