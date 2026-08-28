from __future__ import annotations

from copy import deepcopy

from backend.advisor.llm import AdvisorConfigurationError, ask_gemini
from backend.progress.metrics import build_metrics
from backend.progress.models import WhatIfRequest, WhatIfResponse
from backend.progress.service import build_student_twin
from database.repository import StudentRepository


def run_assessment_grade_scenario(repository: StudentRepository, student_id: str, scenario: WhatIfRequest) -> WhatIfResponse | None:
    """Project an assessment grade in memory; no repository write is performed."""
    twin = build_student_twin(repository, student_id)
    if twin is None:
        return None
    course = next((item for item in twin.courses if item.course_id == scenario.course_id), None)
    if course is None:
        raise ValueError("Course is not enrolled for this student")
    assessment = next((item for item in course.assessments if item.assessment_id == scenario.assessment_id), None)
    if assessment is None:
        raise ValueError("Assessment does not belong to this course")
    if assessment.assessment_type not in {"assignment", "lab", "quiz", "midterm", "final", "exam"}:
        raise ValueError("This assessment type is not supported by the simulator")

    projected_assessments = deepcopy(course.assessments)
    next(item for item in projected_assessments if item.assessment_id == scenario.assessment_id).percentage = scenario.hypothetical_grade
    after_metrics = build_metrics(projected_assessments, course.lectures, course.current_week, course.metrics.previous_course_health)
    before = course.metrics.model_dump()
    after = after_metrics.model_dump()
    difference = {
        "weighted_grade": _difference(after_metrics.weighted_grade, course.metrics.weighted_grade),
        "course_health": _difference(after_metrics.course_health, course.metrics.course_health),
        "assessment_completion": _difference(after_metrics.assessment_completion, course.metrics.assessment_completion),
    }
    deterministic_explanation = (
        f"If {assessment.name} is recorded as {scenario.hypothetical_grade:.0f}%, "
        f"the calculated current weighted grade changes from {_format(course.metrics.weighted_grade)} "
        f"to {_format(after_metrics.weighted_grade)} and course health changes from "
        f"{course.metrics.course_health:.1f} to {after_metrics.course_health:.1f}. "
        "This is a read-only projection, not an official grade update."
    )
    return WhatIfResponse(
        before=before,
        after=after,
        difference=difference,
        explanation=_explain_projection(deterministic_explanation),
    )


def _difference(after: float | None, before: float | None) -> float | None:
    if after is None or before is None:
        return None
    return round(after - before, 2)


def _format(value: float | None) -> str:
    return "not yet available" if value is None else f"{value:.1f}%"


def _explain_projection(deterministic_explanation: str) -> str:
    """Gemini may rephrase verified projection facts, never calculate them."""
    prompt = f"""
Rewrite the verified academic projection below as one concise, encouraging paragraph.
Use only these facts. Do not calculate anything, add university rules, or promise an outcome.

Verified projection:
{deterministic_explanation}
"""
    try:
        return ask_gemini(prompt)
    except AdvisorConfigurationError:
        # A local deterministic explanation keeps the read-only simulator useful
        # before Gemini credentials are configured.
        return deterministic_explanation
