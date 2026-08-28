from __future__ import annotations

import json
from typing import Any

from database.repository import StudentRepository

from .metrics import build_metrics
from .models import Assessment, CourseMaterial, CourseTwin, Lecture, Risk, StudentProfile, StudentTwin
from .risks import detect_risks, highest_risk_level


def build_student_twin(repository: StudentRepository, student_id: str) -> StudentTwin | None:
    raw = repository.get_student_progress(student_id)
    if raw is None:
        return None
    course_twins: list[CourseTwin] = []
    for raw_course in raw["courses"]:
        assessments = [
            Assessment(
                **{
                    **assessment,
                    "covered_lecture_ids": json.loads(assessment["covered_lecture_ids"]),
                }
            )
            for assessment in raw_course["assessments"]
        ]
        lectures = [Lecture(**lecture) for lecture in raw_course["lectures"]]
        materials = [CourseMaterial(**material) for material in raw_course["materials"]]
        previous = repository.get_previous_course_snapshot(
            student_id, raw_course["course_id"], raw_course["current_week"]
        )
        previous_health = previous["course_health"] if previous else None
        metrics = build_metrics(assessments, lectures, raw_course["current_week"], previous_health)
        risks = detect_risks(assessments, lectures, metrics, raw_course["current_week"])
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
    return StudentTwin(
        student=StudentProfile(**raw["student"]),
        semester=semester,
        current_week=current_week,
        courses=course_twins,
        overall_academic_health=round(sum(course.metrics.course_health for course in course_twins) / len(course_twins), 2) if course_twins else 0.0,
        active_risks=[risk for course in course_twins for risk in course.risks],
        weekly_history=repository.get_weekly_snapshots(student_id),
        recent_interventions=repository.get_interventions(student_id),
    )


def course_fingerprint(course: CourseTwin) -> str:
    payload: dict[str, Any] = {
        "risk_codes": sorted(risk.code for risk in course.risks),
        "unstudied_lecture_ids": sorted(lecture.lecture_id for lecture in course.unstudied_lectures),
        "low_assessment_ids": sorted(
            assessment.assessment_id for assessment in course.assessments
            if assessment.percentage is not None and assessment.percentage < 60
        ),
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))

