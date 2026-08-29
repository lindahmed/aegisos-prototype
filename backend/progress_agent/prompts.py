from __future__ import annotations

from backend.progress.models import CourseTwin, Risk


_ACTION_TEMPLATES: dict[str, list[str]] = {
    "low_midterm": [
        "Review the recorded lectures covered by the midterm before attempting similar problems.",
        "Re-solve past exam questions for the unstudied lectures in the midterm coverage.",
    ],
    "midterm_coursework_drop": [
        "Compare your coursework solutions to the midterm questions to identify where the approach differed.",
        "Schedule office hours to review the midterm feedback before the next assessment.",
    ],
    "low_assignment_average": [
        "Re-work the lowest-scoring assignment problems before the next assignment.",
        "Complete the linked lecture material for the weakest assignment before the due date.",
    ],
    "low_lab_average": [
        "Re-run the lowest-scoring lab steps and verify the expected outputs.",
        "Review the lab notebook for the weakest lab before the next lab session.",
    ],
    "lecture_backlog": [
        "Complete the oldest unstudied lecture before starting this week's new material.",
        "Watch the slides for the next unstudied lecture and mark it complete.",
    ],
    "missed_assessment": [
        "Contact the instructor about the missing grade and confirm the submission status.",
    ],
    "repeated_poor_assessments": [
        "Identify the common topics across the low assessments and review those lectures first.",
        "Schedule a focused review session for the weakest topic before the next assessment.",
    ],
    "significant_decline": [
        "Review the study routine from the previous healthy week and restore what worked.",
        "Reduce new commitments this week to stabilize the course trajectory.",
    ],
    "steady_decline": [
        "Meet with the course instructor or academic advisor this week.",
        "Temporarily prioritize this course over lower-risk courses until health stabilizes.",
    ],
    "incomplete_exam_coverage": [
        "Finish the unstudied lectures listed in the exam coverage before the exam date.",
        "Solve at least one practice problem from each unstudied lecture in the exam coverage.",
    ],
    "missing_coursework_window": [
        "Complete the unstudied lectures covered by the upcoming assessment before starting it.",
    ],
    "lecture_pace_slowdown": [
        "Block a fixed study time this week to return to the previous lecture completion pace.",
    ],
}


def risk_action_templates(risk_codes: set[str]) -> list[str]:
    """Return deterministic action templates for the detected risk codes.

    Gemini may adapt the phrasing, but the underlying task is grounded in the
    authoritative risk codes calculated by the progress layer.
    """
    templates: list[str] = []
    for code in sorted(risk_codes):
        templates.extend(_ACTION_TEMPLATES.get(code, []))
    return templates or ["Review the verified course material and complete the next study step."]


def intervention_prompt(course: CourseTwin, risks: list[Risk], lectures_to_review: list[str]) -> str:
    assessment_facts = "\n".join(
        f"- {assessment.name} ({assessment.assessment_type}): "
        f"{assessment.percentage:.0f}%" if assessment.percentage is not None else
        f"- {assessment.name} ({assessment.assessment_type}): no recorded grade"
        for assessment in course.assessments
    )
    risk_facts = "\n".join(f"- {risk.message}" for risk in risks)
    lecture_facts = "\n".join(f"- {lecture}" for lecture in lectures_to_review) or "- None"
    suggested_actions = "\n".join(
        f"- {action}" for action in risk_action_templates({risk.code for risk in risks})
    )
    return f"""
You write a concise academic intervention for AegisOS. Return JSON only with this shape:
{{"severity":"low|medium|high","reason":"...","weak_topics":["..."],"lectures_to_review":[1],"recommended_actions":["..."],"message":"..."}}

Use only the verified facts below. Do not invent grades, lecture titles, assignments,
university policies, causes, or missing data. Do not say an incomplete lecture caused
a low score. You may say that it is included in assessment coverage and remains incomplete.
Recommended actions may be practical study actions, but must not assert unknown facts.
Prefer the suggested actions below when they match the detected facts; rephrase them
in the student's context rather than inventing unrelated tasks.

Course: {course.course_name}
Current week: {course.current_week}
Assignment average: {course.metrics.assignment_average}
Lab average: {course.metrics.lab_average}
Quiz average: {course.metrics.quiz_average}
Exam percentage: {course.metrics.exam_percentage}
Current weighted grade from posted assessments: {course.metrics.weighted_grade}
Previous course health: {course.metrics.previous_course_health}
Current course health: {course.metrics.course_health}
Trend: {course.metrics.trend}

Recorded assessments:
{assessment_facts}

Detected facts:
{risk_facts}

Unstudied relevant lectures:
{lecture_facts}

Suggested actions based on detected facts:
{suggested_actions}
""".strip()
