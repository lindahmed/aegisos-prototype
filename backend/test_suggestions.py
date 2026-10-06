from pathlib import Path

from fastapi.testclient import TestClient

from backend.app import create_app
from backend.progress.models import (
    Assessment,
    CourseMetrics,
    CourseTwin,
    Lecture,
    StudentProfile,
    StudentTwin,
)
from backend.progress.suggestions import build_study_suggestion


def make_client(tmp_path: Path) -> TestClient:
    return TestClient(
        create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students")
    )


def lecture(course: str, number: int, week: int, done: bool = False) -> Lecture:
    return Lecture(
        lecture_id=f"{course}-l{number}",
        lecture_number=number,
        title=f"Topic {number}",
        available_week=week,
        completed=done,
    )


def course_twin(
    course_id: str,
    name: str,
    lectures: list[Lecture],
    week: int,
    assessments: list[Assessment] | None = None,
    risk_level: str | None = None,
    health: float | None = 80.0,
) -> CourseTwin:
    return CourseTwin(
        course_id=course_id,
        course_name=name,
        semester="Fall 2026",
        current_week=week,
        assessments=assessments or [],
        lectures=lectures,
        materials=[],
        completed_lectures=[item for item in lectures if item.completed],
        unstudied_lectures=[
            item for item in lectures if item.available_week <= week and not item.completed
        ],
        metrics=CourseMetrics(
            lecture_completion=50,
            assessment_completion=0,
            course_health=health,
            trend="stable",
        ),
        risk_level=risk_level,
    )


def twin_of(courses: list[CourseTwin], week: int = 5) -> StudentTwin:
    return StudentTwin(
        student=StudentProfile(student_id="1", name="Sam", major="CS", year=2),
        semester="Fall 2026",
        current_week=week,
        courses=courses,
    )


def test_suggests_earliest_available_unstudied_lecture() -> None:
    logic = course_twin(
        "dl",
        "Digital Logic",
        [lecture("dl", 1, 1, True), lecture("dl", 2, 2, True), lecture("dl", 3, 3), lecture("dl", 4, 4)],
        week=5,
    )
    suggestion = build_study_suggestion(twin_of([logic]))
    assert suggestion["title"] == "Let's study Lecture 3 in Digital Logic"
    assert suggestion["lecture_id"] == "dl-l3"
    assert "Lecture 3 in Digital Logic" in suggestion["chat_prompt"]
    assert suggestion["completed_lectures"] == 2
    assert suggestion["available_lectures"] == 4


def test_never_suggests_a_lecture_that_is_not_available_yet() -> None:
    course = course_twin("dl", "Digital Logic", [lecture("dl", 1, 1, True), lecture("dl", 2, 9)], week=5)
    assert build_study_suggestion(twin_of([course])) is None


def test_prefers_lecture_covered_by_nearest_assessment_then_risk() -> None:
    quiet = course_twin("a", "Algebra", [lecture("a", 1, 1)], week=5)
    exam = Assessment(
        assessment_id="m1",
        name="Midterm",
        assessment_type="midterm",
        weight=30,
        due_week=6,
        covered_lecture_ids=["b-l1"],
    )
    urgent = course_twin("b", "Biology", [lecture("b", 1, 1)], week=5, assessments=[exam])
    risky = course_twin("c", "Chemistry", [lecture("c", 1, 1)], week=5, risk_level="high", health=40)

    assert build_study_suggestion(twin_of([quiet, risky, urgent]))["course_name"] == "Biology"
    assert build_study_suggestion(twin_of([quiet, risky]))["course_name"] == "Chemistry"


def test_skipped_lecture_moves_to_the_next_one() -> None:
    course = course_twin("dl", "Digital Logic", [lecture("dl", 1, 1), lecture("dl", 2, 2)], week=5)
    twin = twin_of([course])
    assert build_study_suggestion(twin)["lecture_number"] == 1
    assert build_study_suggestion(twin, {"dl-l1"})["lecture_number"] == 2
    assert build_study_suggestion(twin, {"dl-l1", "dl-l2"}) is None


def test_suggestion_endpoint_uses_the_students_own_courses(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    student = client.get("/student/231027905").json()
    response = client.get("/progress/231027905/suggestion")
    assert response.status_code == 200
    suggestion = response.json()["suggestion"]
    assert suggestion["course_name"] in student["courses"]
    assert suggestion["title"].startswith(f"Let's study Lecture {suggestion['lecture_number']} in ")

    skipped = client.get(
        "/progress/231027905/suggestion", params={"skip": suggestion["lecture_id"]}
    ).json()["suggestion"]
    assert skipped["lecture_id"] != suggestion["lecture_id"]


def test_suggestion_endpoint_returns_404_for_unknown_student(tmp_path: Path) -> None:
    assert make_client(tmp_path).get("/progress/000/suggestion").status_code == 404
