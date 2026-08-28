from dataclasses import dataclass


@dataclass(frozen=True)
class ProgressThresholds:
    """Prototype policy, centralized until official academic policy is imported."""

    passing_percentage: float = 60.0
    low_health: float = 60.0
    medium_health: float = 70.0
    lecture_backlog_percentage: float = 70.0
    significant_weekly_change: float = 8.0
    assessment_performance_drop: float = 15.0
    upcoming_assessment_weeks: int = 1
    repeated_poor_count: int = 2


THRESHOLDS = ProgressThresholds()
