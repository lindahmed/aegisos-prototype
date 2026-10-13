from __future__ import annotations

from backend.progress.config import THRESHOLDS
from backend.progress.models import CourseTwin


InterventionOutcome = str  # "improved" | "stable" | "worsened" | "no_data"


def evaluate_intervention_outcome(
    intervention: dict[str, object], course: CourseTwin
) -> InterventionOutcome:
    """Compare current course health to the health recorded when the intervention was created.

    The outcome is a fact derived from snapshots, not a model guess.
    """
    creation_health = intervention.get("course_health_at_creation")
    current_health = course.metrics.course_health
    if current_health is None or creation_health is None:
        return "no_data"

    creation_health = float(creation_health)
    if current_health - creation_health >= THRESHOLDS.intervention_improvement_threshold:
        return "improved"
    if creation_health - current_health >= THRESHOLDS.intervention_decline_threshold:
        return "worsened"
    return "stable"


def build_feedback_message(
    intervention: dict[str, object], course: CourseTwin
) -> str | None:
    """Generate a grounded acknowledgment when a prior warning led to improvement."""
    outcome = evaluate_intervention_outcome(intervention, course)
    if outcome != "improved":
        return None

    creation_health = float(intervention.get("course_health_at_creation", 0))
    current_health = course.metrics.course_health
    if current_health is None:
        return None

    course_name = course.course_name
    return (
        f"Your work on {course_name} is paying off: course health moved from "
        f"{creation_health:.0f} to {current_health:.0f} since the previous alert. "
        "Keep the same approach."
    )
