from __future__ import annotations

from backend.advisor.llm import AdvisorConfigurationError, ask_gemini
from backend.progress.models import CourseTwin, RiskSeverity, StudentTwin


def _format_health(health: float | None) -> str:
    if health is None:
        return "not yet available"
    if health >= 80:
        return f"strong ({health:.0f}/100)"
    if health >= 60:
        return f"stable ({health:.0f}/100)"
    return f"needs attention ({health:.0f}/100)"


def _rank(severity: RiskSeverity) -> int:
    return {"low": 1, "medium": 2, "high": 3}[severity]


def build_narrative_facts(twin: StudentTwin) -> str:
    """Assemble verified facts into a concise draft narrative.

    This deterministic text is always grounded in the twin.  Gemini may later
    rephrase it for tone, but the facts themselves come from Python.
    """
    student_name = twin.student.name.split()[0] if twin.student.name else "Student"
    lines: list[str] = [
        f"Week {twin.current_week} update for {student_name}.",
        f"Overall academic health is {_format_health(twin.overall_academic_health)}.",
    ]

    improving = [
        course for course in twin.courses
        if course.metrics.trend == "improving" and not course.risks
    ]
    if improving:
        names = ", ".join(course.course_name for course in improving)
        lines.append(f"{names} improved from last week.")

    at_risk = sorted(
        [course for course in twin.courses if course.risks],
        key=lambda course: _rank(course.risk_level or "low"),
        reverse=True,
    )
    if at_risk:
        top = at_risk[:2]
        risk_lines: list[str] = []
        for course in top:
            risk_names = ", ".join(sorted({risk.code for risk in course.risks}))
            risk_lines.append(f"{course.course_name} ({risk_names})")
        lines.append(f"Courses needing attention: {'; '.join(risk_lines)}.")

    if not at_risk and not improving:
        lines.append("No active concerns this week; continue the current pace.")

    return " ".join(lines)


def generate_weekly_narrative(twin: StudentTwin) -> str:
    """Return a short, grounded weekly narrative for the dashboard.

    Gemini may polish the tone, but the underlying facts are generated
    deterministically from the twin so the model cannot invent grades or trends.
    """
    facts = build_narrative_facts(twin)
    prompt = f"""
Rewrite the verified weekly academic update below as one concise, friendly paragraph.
Use ONLY the facts provided. Do not invent grades, courses, causes, or missing data.
Do not claim that one event caused another unless the text explicitly says so.
Keep the result under 80 words.

Verified update:
{facts}
""".strip()
    try:
        return ask_gemini(prompt)
    except AdvisorConfigurationError:
        # Deterministic fallback keeps the endpoint useful before Gemini
        # credentials are configured or when the service is unavailable.
        return facts
