from __future__ import annotations

import json
from typing import Any

from database.repository import StudentRepository

from .config import THRESHOLDS
from .metrics import build_metrics
from .models import Assessment, CourseMaterial, CourseTwin, Lecture, Risk, StudentProfile, StudentTwin
from .risks import detect_risks, highest_risk_level


def build_student_twin(repository: StudentRepository, student_id: str) -> StudentTwin | None:
    raw = repository.get_student_progress(student_id)
    if raw is None:
        return None
    all_snapshots = repository.get_weekly_snapshots(student_id)
    course_twins: list[CourseTwin] = []
    for raw_course in raw["courses"]:
        assessments = [
            Assessment(**{
                **assessment,
                "covered_lecture_ids": json.loads(assessment["covered_lecture_ids"]),
                "mark": (assessment["percentage"] * assessment["weight"] / 100) if assessment["percentage"] is not None else None,
                "max_marks": assessment["weight"],
            })
            for assessment in raw_course["assessments"]
        ]
        lectures = [Lecture(**lecture) for lecture in raw_course["lectures"]]
        materials = [CourseMaterial(**material) for material in raw_course["materials"]]
        previous = repository.get_previous_course_snapshot(
            student_id, raw_course["course_id"], raw_course["current_week"]
        )
        previous_health = previous["course_health"] if previous else None
        metrics = build_metrics(assessments, lectures, raw_course["current_week"], previous_health)
        course_snapshots = [
            snapshot for snapshot in all_snapshots
            if snapshot["course_id"] == raw_course["course_id"]
        ]
        risks = detect_risks(assessments, lectures, metrics, raw_course["current_week"], course_snapshots)
        course_twins.append(CourseTwin(
            course_id=raw_course["course_id"],
            course_name=raw_course["course_name"],
            semester=raw_course["semester"],
            current_week=raw_course["current_week"],
            assessments=assessments,
            lectures=lectures,
            materials=materials,
            completed_lectures=[lecture for lecture in lectures if lecture.completed],
            unstudied_lectures=[lecture for lecture in lectures if lecture.available_week <= raw_course["current_week"] and not lecture.completed],
            metrics=metrics,
            risks=risks,
            risk_level=highest_risk_level(risks),
        ))
    semester = course_twins[0].semester if course_twins else "Unknown"
    current_week = course_twins[0].current_week if course_twins else 1
    twin = StudentTwin(
        student=StudentProfile(**raw["student"]),
        semester=semester,
        current_week=current_week,
        courses=course_twins,
        overall_academic_health=(
            round(sum(health_scores) / len(health_scores), 2)
            if (health_scores := [course.metrics.course_health for course in course_twins if course.metrics.course_health is not None])
            else None
        ),
        active_risks=[risk for course in course_twins for risk in course.risks],
        weekly_history=repository.get_weekly_snapshots(student_id),
        recent_interventions=repository.get_interventions(student_id),
    )
    twin.current_recommendation = build_current_recommendation(twin.courses, twin.current_week)
    return twin



def build_current_recommendation(courses: list[CourseTwin], current_week: int) -> str | None:
    """Build a current, fact-specific recommendation without using stale interventions."""
    available = [course for course in courses if course.metrics.course_health is not None]
    if not available:
        return None
    course = max(
        available,
        key=lambda item: (
            1 if item.risks else 0,
            {"high": 3, "medium": 2, "low": 1, None: 0}[item.risk_level],
            -(item.metrics.course_health or 0),
        ),
    )
    parts: list[str] = []
    if course.metrics.trend == "improving" and course.metrics.previous_course_health is not None:
        parts.append(
            f"{course.course_name} improved from {course.metrics.previous_course_health:.0f}% "
            f"to {course.metrics.course_health:.0f}% academic health; keep the study pattern that produced this recovery."
        )
    elif course.risks:
        parts.append(f"Prioritize {course.course_name} this week because it has {len(course.risks)} active risk signal(s).")
    else:
        parts.append(f"{course.course_name} is currently safe at {course.metrics.course_health:.0f}% academic health; maintain the current pace.")

    posted = [assessment for assessment in course.assessments if assessment.mark is not None]
    if posted:
        weakest = min(posted, key=lambda item: (item.mark or 0) / item.max_marks if item.max_marks else 1)
        parts.append(f"Use the feedback from {weakest.name}, recorded at {weakest.mark:.1f}/{weakest.max_marks:.0f} marks, to choose the first topic to review.")

    upcoming = sorted(
        [assessment for assessment in course.assessments if assessment.mark is None and assessment.due_week > current_week],
        key=lambda item: (item.due_week, -item.max_marks),
    )
    if upcoming:
        next_item = upcoming[0]
        weeks = next_item.due_week - current_week
        parts.append(
            f"Start preparing for {next_item.name}, worth {next_item.max_marks:.0f} marks and due in week "
            f"{next_item.due_week} ({weeks} week{'s' if weeks != 1 else ''} away)."
        )
    if course.unstudied_lectures:
        lecture = course.unstudied_lectures[0]
        parts.append(f"Complete Lecture {lecture.lecture_number}, {lecture.title}, as the next recorded study step.")
    return " ".join(parts)


def course_fingerprint(course: CourseTwin) -> str:
    """Stable but specific signature for an intervention issue.

    Includes severity so a worsening issue triggers a fresh intervention, and a
    week bucket so a long-standing issue can be re-alerted after a configurable
    interval without opening duplicates every run.
    """
    seen_assessment_ids: set[str] = set()
    primary_assessment_ids: list[str] = []
    for risk in course.risks:
        for assessment_id in risk.related_assessment_ids:
            if assessment_id not in seen_assessment_ids:
                primary_assessment_ids.append(assessment_id)
                seen_assessment_ids.add(assessment_id)
                break

    payload: dict[str, Any] = {
        "risk_signatures": sorted(f"{risk.code}:{risk.severity}" for risk in course.risks),
        "primary_assessment_ids": sorted(primary_assessment_ids),
        "unstudied_lecture_ids": sorted(lecture.lecture_id for lecture in course.unstudied_lectures),
        "week_bucket": course.current_week // THRESHOLDS.re_alert_interval_weeks,
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))
