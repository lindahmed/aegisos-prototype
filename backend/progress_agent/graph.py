from __future__ import annotations

from typing import Callable, TypedDict

from langgraph.graph import END, START, StateGraph

from backend.advisor.llm import ask_gemini_structured
from backend.progress.config import THRESHOLDS
from backend.progress.feedback import build_feedback_message, evaluate_intervention_outcome
from backend.progress.metrics import metrics_as_snapshot
from backend.progress.models import CourseTwin, Intervention, StudentTwin
from backend.progress.service import build_student_twin, course_fingerprint
from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository

from .prompts import intervention_prompt, risk_action_templates


class StudentNotFoundError(LookupError):
    pass


RepositoryType = StudentRepository | PostgresStudentRepository
RecommendationGenerator = Callable[[CourseTwin], Intervention]


class ProgressState(TypedDict, total=False):
    student_id: str
    twin: StudentTwin
    intervention_courses: list[CourseTwin]
    generated_interventions: list[tuple[CourseTwin, Intervention]]
    validated_interventions: list[tuple[CourseTwin, Intervention]]
    course_feedback: dict[str, str]


def generate_gemini_intervention(course: CourseTwin) -> Intervention:
    related_ids = {lecture_id for risk in course.risks for lecture_id in risk.related_lecture_ids}
    relevant = [lecture for lecture in course.unstudied_lectures if lecture.lecture_id in related_ids]
    if not relevant:
        relevant = course.unstudied_lectures
    lecture_labels = [f"Lecture {lecture.lecture_number}: {lecture.title}" for lecture in relevant]
    return ask_gemini_structured(intervention_prompt(course, course.risks, lecture_labels), Intervention)


def _validate_intervention(
    course: CourseTwin,
    generated: Intervention,
    feedback_message: str | None = None,
) -> Intervention:
    """Keep model output in the recommendation lane, never the facts lane."""
    severity = course.risk_level or "low"
    reason = " ".join(risk.message for risk in course.risks)
    related_ids = {lecture_id for risk in course.risks for lecture_id in risk.related_lecture_ids}
    lecture_candidates = [lecture for lecture in course.unstudied_lectures if lecture.lecture_id in related_ids]
    if not lecture_candidates:
        lecture_candidates = course.unstudied_lectures
    lecture_candidates = lecture_candidates[:4]
    actions = [action.strip() for action in generated.recommended_actions if action.strip()][:5]
    if not actions:
        actions = risk_action_templates({risk.code for risk in course.risks})[:5]
    message = generated.message.strip()
    if not message:
        message = f"{course.course_name} needs attention this week. {reason}"
    if feedback_message:
        message = f"{feedback_message} {message}"
    return Intervention(
        severity=severity,
        reason=reason,
        weak_topics=[lecture.title for lecture in lecture_candidates],
        lectures_to_review=[lecture.lecture_number for lecture in lecture_candidates],
        recommended_actions=actions,
        message=message,
    )


def build_progress_graph(
    repository: RepositoryType,
    recommendation_generator: RecommendationGenerator = generate_gemini_intervention,
):
    """Build an independent graph; the existing Advisor graph remains untouched."""
    def load_student_twin(state: ProgressState) -> ProgressState:
        twin = build_student_twin(repository, state["student_id"])
        if twin is None:
            raise StudentNotFoundError("Student not found")
        return {"twin": twin}

    def calculate_progress(state: ProgressState) -> ProgressState:
        # Metrics, prior-snapshot comparison, and risks were calculated before
        # orchestration in build_student_twin; this node keeps the graph's
        # deterministic calculation boundary explicit.
        return {}

    def update_past_interventions(state: ProgressState) -> ProgressState:
        """Resolve or escalate active interventions based on current course health."""
        twin = state["twin"]
        course_feedback: dict[str, str] = {}
        for intervention in repository.get_active_interventions(twin.student.student_id):
            course = next(
                (item for item in twin.courses if item.course_id == intervention["course_id"]),
                None,
            )
            if course is None:
                continue

            outcome = evaluate_intervention_outcome(intervention, course)
            if outcome == "improved":
                repository.update_intervention_status(
                    intervention["intervention_id"], "resolved",
                    twin.current_week, "improved",
                )
                feedback = build_feedback_message(intervention, course)
                if feedback:
                    course_feedback[course.course_id] = feedback
            elif outcome == "worsened":
                repository.update_intervention_status(
                    intervention["intervention_id"], "escalated",
                    twin.current_week, "worsened",
                )
            elif twin.current_week - intervention["week_number"] >= THRESHOLDS.intervention_max_active_weeks:
                # Expire stale active interventions so the issue can be
                # re-evaluated cleanly without duplicate suppression blocking it.
                repository.update_intervention_status(
                    intervention["intervention_id"], "expired",
                    twin.current_week, "no_data",
                )
        return {"course_feedback": course_feedback}

    def detect_intervention_need(state: ProgressState) -> ProgressState:
        twin = state["twin"]
        courses = [
            course for course in twin.courses
            if course.risks and not repository.has_active_intervention(
                twin.student.student_id, course.course_id, course_fingerprint(course)
            )
        ]
        return {"intervention_courses": courses}

    def route_intervention(state: ProgressState) -> str:
        return "intervene" if state.get("intervention_courses") else "save"

    def retrieve_course_information(state: ProgressState) -> ProgressState:
        # Portal materials are already part of the twin. This is the clean
        # extension point for future RAG without making it a core dependency.
        return {}

    def generate_intervention(state: ProgressState) -> ProgressState:
        return {"generated_interventions": [
            (course, recommendation_generator(course)) for course in state["intervention_courses"]
        ]}

    def validate_recommendation(state: ProgressState) -> ProgressState:
        course_feedback = state.get("course_feedback", {})
        return {"validated_interventions": [
            (
                course,
                _validate_intervention(
                    course,
                    intervention,
                    feedback_message=course_feedback.get(course.course_id),
                ),
            )
            for course, intervention in state.get("generated_interventions", [])
        ]}

    def save_interventions(state: ProgressState) -> ProgressState:
        twin = state["twin"]
        for course, intervention in state.get("validated_interventions", []):
            repository.save_intervention(
                twin.student.student_id, course.course_id, twin.current_week,
                intervention.model_dump(), course_fingerprint(course),
                course_health_at_creation=course.metrics.course_health,
            )
        return {}

    def save_snapshot(state: ProgressState) -> ProgressState:
        twin = state["twin"]
        for course in twin.courses:
            if course.metrics.course_health is None:
                continue
            repository.save_weekly_snapshot(
                twin.student.student_id, course.course_id, twin.current_week,
                metrics_as_snapshot(course.metrics, course.risk_level or "none"),
            )
        return {}

    graph = StateGraph(ProgressState)
    graph.add_node("load_student_twin", load_student_twin)
    graph.add_node("calculate_progress", calculate_progress)
    graph.add_node("update_past_interventions", update_past_interventions)
    graph.add_node("detect_intervention_need", detect_intervention_need)
    graph.add_node("retrieve_course_information", retrieve_course_information)
    graph.add_node("generate_intervention", generate_intervention)
    graph.add_node("validate_recommendation", validate_recommendation)
    graph.add_node("save_interventions", save_interventions)
    graph.add_node("save_snapshot", save_snapshot)
    graph.add_edge(START, "load_student_twin")
    graph.add_edge("load_student_twin", "calculate_progress")
    graph.add_edge("calculate_progress", "update_past_interventions")
    graph.add_edge("update_past_interventions", "detect_intervention_need")
    graph.add_conditional_edges("detect_intervention_need", route_intervention, {"intervene": "retrieve_course_information", "save": "save_snapshot"})
    graph.add_edge("retrieve_course_information", "generate_intervention")
    graph.add_edge("generate_intervention", "validate_recommendation")
    graph.add_edge("validate_recommendation", "save_interventions")
    graph.add_edge("save_interventions", "save_snapshot")
    graph.add_edge("save_snapshot", END)
    return graph.compile()
