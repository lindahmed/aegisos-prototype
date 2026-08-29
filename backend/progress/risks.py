from __future__ import annotations

from .config import THRESHOLDS
from .models import Assessment, CourseMetrics, Lecture, Risk, RiskSeverity


_RANK: dict[RiskSeverity, int] = {"low": 1, "medium": 2, "high": 3}


def highest_risk_level(risks: list[Risk]) -> RiskSeverity | None:
    return max((risk.severity for risk in risks), key=lambda severity: _RANK[severity], default=None)


def detect_risks(
    assessments: list[Assessment],
    lectures: list[Lecture],
    metrics: CourseMetrics,
    current_week: int,
    recent_snapshots: list[dict[str, object]] | None = None,
) -> list[Risk]:
    """Calculate authoritative risks from records and recent history.

    recent_snapshots must be course-specific rows ordered by week_number, oldest
    first.  They are used for velocity triggers such as steady decline.
    """
    risks: list[Risk] = []
    by_type = lambda kind: [item for item in assessments if item.assessment_type == kind and item.percentage is not None]
    midterms = by_type("midterm")
    if midterms and midterms[-1].percentage < THRESHOLDS.passing_percentage:
        midterm = midterms[-1]
        risks.append(Risk(
            code="low_midterm", severity="high",
            message=f"{midterm.name} is {midterm.percentage:.0f}%, below the configured {THRESHOLDS.passing_percentage:.0f}% threshold.",
            related_lecture_ids=midterm.covered_lecture_ids, related_assessment_ids=[midterm.assessment_id],
        ))
    coursework_scores = [
        assessment.percentage for assessment in assessments
        if assessment.assessment_type in {"assignment", "lab", "quiz"} and assessment.percentage is not None
    ]
    if midterms and coursework_scores:
        midterm = midterms[-1]
        coursework_average = sum(coursework_scores) / len(coursework_scores)
        difference = coursework_average - midterm.percentage
        if difference >= THRESHOLDS.assessment_performance_drop:
            risks.append(Risk(
                code="midterm_coursework_drop",
                severity="high" if midterm.percentage < THRESHOLDS.passing_percentage else "medium",
                message=(
                    f"{midterm.name} is {difference:.0f} percentage points below the "
                    f"recorded coursework average of {coursework_average:.0f}%."
                ),
                related_lecture_ids=midterm.covered_lecture_ids,
                related_assessment_ids=[midterm.assessment_id],
            ))
    for kind, label, average in (("assignment", "assignment", metrics.assignment_average), ("lab", "lab", metrics.lab_average)):
        if average is not None and average < THRESHOLDS.passing_percentage:
            risks.append(Risk(code=f"low_{kind}_average", severity="medium", message=f"{label.capitalize()} average is {average:.0f}%, below the configured {THRESHOLDS.passing_percentage:.0f}% threshold.", related_assessment_ids=[item.assessment_id for item in by_type(kind)]))
    expected_lectures = [lecture for lecture in lectures if lecture.available_week <= current_week]
    unstudied = [lecture for lecture in expected_lectures if not lecture.completed]
    if expected_lectures and metrics.lecture_completion < THRESHOLDS.lecture_backlog_percentage:
        risks.append(Risk(code="lecture_backlog", severity="medium", message=f"{len(unstudied)} of {len(expected_lectures)} available lectures are not marked complete.", related_lecture_ids=[lecture.lecture_id for lecture in unstudied]))
    missed = [assessment for assessment in assessments if assessment.due_week <= current_week and assessment.percentage is None]
    if missed:
        risks.append(Risk(code="missed_assessment", severity="high", message=f"{len(missed)} due assessment(s) do not have a recorded grade.", related_assessment_ids=[assessment.assessment_id for assessment in missed]))
    poor = [assessment for assessment in assessments if assessment.percentage is not None and assessment.percentage < THRESHOLDS.passing_percentage]
    if len(poor) >= THRESHOLDS.repeated_poor_count:
        risks.append(Risk(code="repeated_poor_assessments", severity="medium", message=f"{len(poor)} recorded assessments are below {THRESHOLDS.passing_percentage:.0f}%.", related_assessment_ids=[assessment.assessment_id for assessment in poor]))
    if metrics.course_health is not None and metrics.previous_course_health is not None and metrics.previous_course_health - metrics.course_health >= THRESHOLDS.significant_weekly_change:
        risks.append(Risk(code="significant_decline", severity="high", message=f"Course health decreased from {metrics.previous_course_health:.0f} to {metrics.course_health:.0f} since the previous snapshot."))

    upcoming_exams = [assessment for assessment in assessments if assessment.assessment_type in {"midterm", "final", "exam"} and assessment.percentage is None and 0 <= assessment.due_week - current_week <= THRESHOLDS.upcoming_assessment_weeks]
    for exam in upcoming_exams:
        unstudied_coverage = [lecture_id for lecture_id in exam.covered_lecture_ids if any(lecture.lecture_id == lecture_id and not lecture.completed for lecture in lectures)]
        if unstudied_coverage:
            risks.append(Risk(code="incomplete_exam_coverage", severity="high", message=f"{exam.name} is due in week {exam.due_week}; {len(unstudied_coverage)} covered lecture(s) are not complete.", related_lecture_ids=unstudied_coverage, related_assessment_ids=[exam.assessment_id]))

    risks.extend(_detect_missing_coursework_window(assessments, lectures, current_week))
    risks.extend(_detect_deadline_cluster(assessments, current_week))
    risks.extend(_detect_velocity_risks(metrics, recent_snapshots or []))
    return risks


def _detect_missing_coursework_window(
    assessments: list[Assessment], lectures: list[Lecture], current_week: int
) -> list[Risk]:
    """Warn when an upcoming coursework assessment is due soon but its covered material is not complete."""
    risks: list[Risk] = []
    upcoming_coursework = [
        assessment for assessment in assessments
        if assessment.assessment_type in {"assignment", "lab", "quiz"}
        and assessment.percentage is None
        and 0 < assessment.due_week - current_week <= THRESHOLDS.coursework_warning_weeks
    ]
    for assessment in upcoming_coursework:
        unstudied_coverage = [
            lecture_id for lecture_id in assessment.covered_lecture_ids
            if any(lecture.lecture_id == lecture_id and not lecture.completed for lecture in lectures)
        ]
        if unstudied_coverage:
            risks.append(Risk(
                code="missing_coursework_window",
                severity="low",
                message=(
                    f"{assessment.name} is due in week {assessment.due_week} and "
                    f"{len(unstudied_coverage)} covered lecture(s) are not complete."
                ),
                related_lecture_ids=unstudied_coverage,
                related_assessment_ids=[assessment.assessment_id],
            ))
    return risks


def _detect_deadline_cluster(
    assessments: list[Assessment], current_week: int
) -> list[Risk]:
    """Flag weeks where multiple ungraded assessments are due at once."""
    risks: list[Risk] = []
    upcoming = [
        assessment for assessment in assessments
        if assessment.percentage is None and assessment.due_week > current_week
    ]
    by_week: dict[int, list[Assessment]] = {}
    for assessment in upcoming:
        by_week.setdefault(assessment.due_week, []).append(assessment)
    for due_week, items in by_week.items():
        if len(items) >= 2:
            risks.append(Risk(
                code="deadline_cluster",
                severity="medium",
                message=(
                    f"{len(items)} assessments are due in week {due_week}; "
                    "plan study time across them."
                ),
                related_assessment_ids=[assessment.assessment_id for assessment in items],
            ))
    return risks


def _detect_velocity_risks(
    metrics: CourseMetrics, recent_snapshots: list[dict[str, object]]
) -> list[Risk]:
    """Detect multi-week decline and lecture-completion slowdown from snapshot history."""
    risks: list[Risk] = []
    if metrics.course_health is None or len(recent_snapshots) < 2:
        return risks

    health_history = [
        float(recent_snapshots[-2]["course_health"]),
        float(recent_snapshots[-1]["course_health"]),
        metrics.course_health,
    ]
    if (
        health_history[0] - health_history[1] >= THRESHOLDS.steady_decline_threshold
        and health_history[1] - health_history[2] >= THRESHOLDS.steady_decline_threshold
    ):
        risks.append(Risk(
            code="steady_decline",
            severity="high",
            message=(
                f"Course health has declined for {THRESHOLDS.steady_decline_weeks} consecutive snapshots "
                f"from {health_history[0]:.0f} to {health_history[2]:.0f}."
            ),
        ))

    if (
        len(recent_snapshots) >= 2
        and metrics.lecture_completion is not None
        and "lecture_completion" in recent_snapshots[-2]
        and "lecture_completion" in recent_snapshots[-1]
    ):
        older_completion = float(recent_snapshots[-2]["lecture_completion"])
        newer_completion = float(recent_snapshots[-1]["lecture_completion"])
        previous_growth = newer_completion - older_completion
        recent_growth = metrics.lecture_completion - newer_completion
        if (
            previous_growth > 0
            and (previous_growth - recent_growth) >= THRESHOLDS.lecture_pace_slowdown_threshold
        ):
            risks.append(Risk(
                code="lecture_pace_slowdown",
                severity="low",
                message=(
                    "Lecture completion growth has slowed. "
                    f"Previous growth was {previous_growth:.0f} percentage points; "
                    f"recent growth is {recent_growth:.0f} percentage points."
                ),
            ))
    return risks
