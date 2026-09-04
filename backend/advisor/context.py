from __future__ import annotations
#test

from backend.advisor.knowledge_graph import AcademicKnowledgeGraph, InMemoryAcademicGraph
from backend.progress.models import CourseTwin, StudentTwin
from backend.progress.service import build_student_twin
from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository


RepositoryType = StudentRepository | PostgresStudentRepository


def fetch_student_context(
    repository: RepositoryType,
    student_id: str,
    message: str = "",
    knowledge_graph: AcademicKnowledgeGraph | None = None,
) -> dict[str, object]:
    """Load the full academic context the advisor needs to answer without sending
    the student elsewhere.

    Returns the student twin when available, plus active intervention history
    and relationship-heavy knowledge graph facts (prerequisites, programme
    progress, course eligibility). The advisor graph can then use this context
    instead of asking the student to look up facts from a portal or third party.
    """
    twin = build_student_twin(repository, student_id)
    if twin is None:
        return {"student_id": student_id, "twin": None}

    graph = knowledge_graph or InMemoryAcademicGraph()

    programme_progress = graph.get_programme_progress(student_id)
    recommended = graph.get_recommended_next_courses(student_id)
    eligibility = None
    mentioned_course = graph.extract_course_code(message)
    if mentioned_course:
        eligibility = graph.get_course_eligibility(student_id, mentioned_course)

    return {
        "student_id": student_id,
        "student": twin.student.model_dump(),
        "semester": twin.semester,
        "current_week": twin.current_week,
        "overall_academic_health": twin.overall_academic_health,
        "courses": [_format_course(course) for course in twin.courses],
        "weekly_history": twin.weekly_history,
        "recent_interventions": twin.recent_interventions,
        "programme_progress": programme_progress,
        "recommended_next_courses": recommended,
        "course_eligibility": eligibility,
        "mentioned_course_code": mentioned_course,
    }


def _format_course(course: CourseTwin) -> dict[str, object]:
    return {
        "course_id": course.course_id,
        "course_name": course.course_name,
        "current_week": course.current_week,
        "metrics": course.metrics.model_dump(),
        "risk_level": course.risk_level,
        "risks": [risk.model_dump() for risk in course.risks],
        "completed_lectures": [lecture.lecture_number for lecture in course.completed_lectures],
        "unstudied_lectures": [lecture.lecture_number for lecture in course.unstudied_lectures],
        "assessments": [
            {
                "name": assessment.name,
                "type": assessment.assessment_type,
                "weight": assessment.weight,
                "due_week": assessment.due_week,
                "percentage": assessment.percentage,
            }
            for assessment in course.assessments
        ],
    }
