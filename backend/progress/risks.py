from __future__ import annotations

from .config import THRESHOLDS
from .models import Assessment, CourseMetrics, Lecture, Risk, RiskSeverity


_RANK: dict[RiskSeverity, int] = {"low": 1, "medium": 2, "high": 3}


def highest_risk_level(risks: list[Risk]) -> RiskSeverity | None:
    return max((risk.severity for risk in risks), key=lambda severity: _RANK[severity], default=None)


def detect_risks(
    assessments: list[Assessment], lectures: list[Lecture], metrics: CourseMetrics, current_week: int
) -> list[Risk]:
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
    return risks
