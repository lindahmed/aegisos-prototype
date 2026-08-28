from __future__ import annotations

from typing import Callable, TypedDict

from langgraph.graph import END, START, StateGraph

from backend.advisor.llm import ask_gemini_structured
from backend.progress.metrics import metrics_as_snapshot
from backend.progress.models import CourseTwin, Intervention, StudentTwin
from backend.progress.service import build_student_twin, course_fingerprint
from database.repository import StudentRepository

from .prompts import intervention_prompt


class StudentNotFoundError(LookupError):
    pass


RecommendationGenerator = Callable[[CourseTwin], Intervention]


class ProgressState(TypedDict, total=False):
    student_id: str
    twin: StudentTwin
    intervention_courses: list[CourseTwin]
    generated_interventions: list[tuple[CourseTwin, Intervention]]
    validated_interventions: list[tuple[CourseTwin, Intervention]]


def generate_gemini_intervention(course: CourseTwin) -> Intervention:
    related_ids = {lecture_id for risk in course.risks for lecture_id in risk.related_lecture_ids}
    relevant = [lecture for lecture in course.unstudied_lectures if lecture.lecture_id in related_ids]
    if not relevant:
        relevant = course.unstudied_lectures
    lecture_labels = [f"Lecture {lecture.lecture_number}: {lecture.title}" for lecture in relevant]
    return ask_gemini_structured(intervention_prompt(course, course.risks, lecture_labels), Intervention)


def _validate_intervention(course: CourseTwin, generated: Intervention) -> Intervention:
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
        actions = ["Review the listed course material and complete the next study step."]
    message = generated.message.strip()
    if not message:
        message = f"{course.course_name} needs attention this week. {reason}"
    return Intervention(
        severity=severity,
        reason=reason,
        weak_topics=[lecture.title for lecture in lecture_candidates],
        lectures_to_review=[lecture.lecture_number for lecture in lecture_candidates],
        recommended_actions=actions,
        message=message,
    )


def build_progress_graph(
    repository: StudentRepository,
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
        return {"validated_interventions": [
            (course, _validate_intervention(course, intervention))
            for course, intervention in state.get("generated_interventions", [])
        ]}

    def save_interventions(state: ProgressState) -> ProgressState:
        twin = state["twin"]
        for course, intervention in state.get("validated_interventions", []):
            repository.save_intervention(
                twin.student.student_id, course.course_id, twin.current_week,
                intervention.model_dump(), course_fingerprint(course),
            )
        return {}

    def save_snapshot(state: ProgressState) -> ProgressState:
        twin = state["twin"]
        for course in twin.courses:
            repository.save_weekly_snapshot(
                twin.student.student_id, course.course_id, twin.current_week,
                metrics_as_snapshot(course.metrics, course.risk_level or "none"),
            )
        return {}

    graph = StateGraph(ProgressState)
    graph.add_node("load_student_twin", load_student_twin)
    graph.add_node("calculate_progress", calculate_progress)
    graph.add_node("detect_intervention_need", detect_intervention_need)
    graph.add_node("retrieve_course_information", retrieve_course_information)
    graph.add_node("generate_intervention", generate_intervention)
    graph.add_node("validate_recommendation", validate_recommendation)
    graph.add_node("save_interventions", save_interventions)
    graph.add_node("save_snapshot", save_snapshot)
    graph.add_edge(START, "load_student_twin")
    graph.add_edge("load_student_twin", "calculate_progress")
    graph.add_edge("calculate_progress", "detect_intervention_need")
    graph.add_conditional_edges("detect_intervention_need", route_intervention, {"intervene": "retrieve_course_information", "save": "save_snapshot"})
    graph.add_edge("retrieve_course_information", "generate_intervention")
    graph.add_edge("generate_intervention", "validate_recommendation")
    graph.add_edge("validate_recommendation", "save_interventions")
    graph.add_edge("save_interventions", "save_snapshot")
    graph.add_edge("save_snapshot", END)
    return graph.compile()

