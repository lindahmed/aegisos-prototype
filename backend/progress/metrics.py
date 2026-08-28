from __future__ import annotations

from statistics import fmean
from typing import Any

from .models import Assessment, CourseMetrics, Lecture


def _average(values: list[float]) -> float | None:
    return round(fmean(values), 2) if values else None


def build_metrics(
    assessments: list[Assessment],
    lectures: list[Lecture],
    current_week: int,
    previous_course_health: float | None = None,
) -> CourseMetrics:
    """Calculate score and completion facts from authoritative records only."""
    category_averages = {
        category: _average([
            assessment.percentage for assessment in assessments
            if assessment.assessment_type == category and assessment.percentage is not None
        ])
        for category in ("assignment", "lab", "quiz")
    }
    exam_scores = [
        assessment.percentage for assessment in assessments
        if assessment.assessment_type in {"midterm", "final", "exam"} and assessment.percentage is not None
    ]
    exam_percentage = _average(exam_scores)

    graded = [assessment for assessment in assessments if assessment.percentage is not None]
    posted_weight = sum(assessment.weight for assessment in graded)
    weighted_grade = (
        round(sum(assessment.percentage * assessment.weight for assessment in graded) / posted_weight, 2)
        if posted_weight else None
    )
    expected_lectures = [lecture for lecture in lectures if lecture.available_week <= current_week]
    completed_expected = [lecture for lecture in expected_lectures if lecture.completed]
    lecture_completion = round(100 * len(completed_expected) / len(expected_lectures), 2) if expected_lectures else 100.0
    expected_assessments = [assessment for assessment in assessments if assessment.due_week <= current_week]
    assessment_completion = round(100 * len([assessment for assessment in expected_assessments if assessment.percentage is not None]) / len(expected_assessments), 2) if expected_assessments else 100.0

    # Health is a transparent readiness indicator, not an official grade.  Each
    # available component is reweighted so missing future grades do not look like zeros.
    health_components: list[tuple[float, float]] = [(lecture_completion, 0.25), (assessment_completion, 0.20)]
    if weighted_grade is not None:
        health_components.append((weighted_grade, 0.55))
    weight_sum = sum(weight for _, weight in health_components)
    course_health = round(sum(value * weight for value, weight in health_components) / weight_sum, 2)

    if previous_course_health is None:
        trend = "new"
    elif course_health - previous_course_health >= 5:
        trend = "improving"
    elif previous_course_health - course_health >= 5:
        trend = "declining"
    else:
        trend = "stable"
    return CourseMetrics(
        assignment_average=category_averages["assignment"],
        lab_average=category_averages["lab"],
        quiz_average=category_averages["quiz"],
        exam_percentage=exam_percentage,
        weighted_grade=weighted_grade,
        lecture_completion=lecture_completion,
        assessment_completion=assessment_completion,
        course_health=course_health,
        trend=trend,
        previous_course_health=previous_course_health,
    )


def metrics_as_snapshot(metrics: CourseMetrics, risk_level: str) -> dict[str, Any]:
    return {**metrics.model_dump(), "risk_level": risk_level, "trend": metrics.trend}

