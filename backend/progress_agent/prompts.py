from __future__ import annotations

from backend.progress.models import CourseTwin, Risk


def intervention_prompt(course: CourseTwin, risks: list[Risk], lectures_to_review: list[str]) -> str:
    assessment_facts = "\n".join(
        f"- {assessment.name} ({assessment.assessment_type}): "
        f"{assessment.percentage:.0f}%" if assessment.percentage is not None else
        f"- {assessment.name} ({assessment.assessment_type}): no recorded grade"
        for assessment in course.assessments
    )
    risk_facts = "\n".join(f"- {risk.message}" for risk in risks)
    lecture_facts = "\n".join(f"- {lecture}" for lecture in lectures_to_review) or "- None"
    return f"""
You write a concise academic intervention for AegisOS. Return JSON only with this shape:
{{"severity":"low|medium|high","reason":"...","weak_topics":["..."],"lectures_to_review":[1],"recommended_actions":["..."],"message":"..."}}

Use only the verified facts below. Do not invent grades, lecture titles, assignments,
university policies, causes, or missing data. Do not say an incomplete lecture caused
a low score. You may say that it is included in assessment coverage and remains incomplete.
Recommended actions may be practical study actions, but must not assert unknown facts.

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
""".strip()

