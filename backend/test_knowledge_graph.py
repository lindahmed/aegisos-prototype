from pathlib import Path

from backend.advisor.context import fetch_student_context
from backend.advisor.knowledge_graph import InMemoryAcademicGraph
from database.repository import StudentRepository


def make_repository(tmp_path: Path) -> StudentRepository:
    repository = StudentRepository(tmp_path / "aegisos.db")
    repository.initialize()
    return repository


def test_ml_eligibility_when_all_prerequisites_satisfied() -> None:
    graph = InMemoryAcademicGraph()
    graph.enroll_student(
        "231027905", "cs",
        completed={"CS101", "CS102", "CS201", "MATH101", "MATH201", "MATH202"},
    )
    eligibility = graph.get_course_eligibility("231027905", "CS301")
    assert eligibility is not None
    assert eligibility["eligible"] is True
    assert eligibility["course_title"] == "Machine Learning"
    assert not eligibility["missing_prerequisites"]


def test_ml_eligibility_when_prerequisites_missing() -> None:
    graph = InMemoryAcademicGraph()
    graph.enroll_student(
        "231027907", "cs",
        completed={"CS101"},
        registered={"CS102", "MATH201"},
    )
    eligibility = graph.get_course_eligibility("231027907", "CS301")
    assert eligibility is not None
    assert eligibility["eligible"] is False
    missing_codes = {p["course_code"] for p in eligibility["missing_prerequisites"]}
    assert "CS201" in missing_codes
    assert "MATH202" in missing_codes


def test_in_progress_prerequisites_are_not_missing() -> None:
    graph = InMemoryAcademicGraph()
    graph.enroll_student(
        "231027905", "cs",
        completed={"CS101", "CS102", "CS201", "MATH201"},
        registered={"MATH202"},
    )
    eligibility = graph.get_course_eligibility("231027905", "CS301")
    assert eligibility is not None
    # A prerequisite that is currently being taken is not treated as a blocker
    # for the next semester.
    assert eligibility["eligible"] is True
    in_progress_codes = {p["course_code"] for p in eligibility["in_progress_prerequisites"]}
    assert "MATH202" in in_progress_codes
    assert "assuming you pass" in eligibility["reason"].lower() or "satisfied" in eligibility["reason"].lower()


def test_programme_progress() -> None:
    graph = InMemoryAcademicGraph()
    graph.enroll_student(
        "231027905", "cs",
        completed={"CS101", "CS102"},
        registered={"CS201"},
    )
    progress = graph.get_programme_progress("231027905")
    assert progress is not None
    assert progress["programme_id"] == "cs"
    assert progress["completed_credits"] == 6
    assert "CS101" in progress["completed_courses"]
    assert "CS201" in progress["registered_courses"]
    assert "CS301" in progress["remaining_required_courses"]


def test_recommended_next_courses() -> None:
    graph = InMemoryAcademicGraph()
    graph.enroll_student(
        "231027905", "cs",
        completed={"CS101", "CS102", "CS201", "MATH201", "MATH202"},
    )
    recommended = graph.get_recommended_next_courses("231027905")
    codes = {r["course_code"] for r in recommended}
    assert "CS301" in codes
    assert "CS202" in codes
    assert "CS302" not in codes  # requires CS301 first


def test_extract_course_code_from_message() -> None:
    graph = InMemoryAcademicGraph()
    assert graph.extract_course_code("Can I take CS301?") == "CS301"
    assert graph.extract_course_code("I want to study Machine Learning") == "CS301"
    assert graph.extract_course_code("How is my overall progress?") is None


def test_fetch_student_context_includes_eligibility(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    graph = InMemoryAcademicGraph()
    graph.enroll_student(
        "231027905", "cs",
        completed={"CS101", "CS102", "CS201", "MATH201"},
        registered={"MATH202"},
    )
    context = fetch_student_context(
        repository, "231027905",
        message="Can I take Machine Learning?",
        knowledge_graph=graph,
    )
    assert context["mentioned_course_code"] == "CS301"
    assert context["course_eligibility"] is not None
    assert context["course_eligibility"]["course_title"] == "Machine Learning"
    assert context["programme_progress"] is not None
