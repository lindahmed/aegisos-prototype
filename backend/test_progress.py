from pathlib import Path

from fastapi.testclient import TestClient

import backend.app as app_module
from backend.app import create_app
from backend.progress.models import Intervention
from backend.progress.service import build_student_twin
from backend.progress_agent.graph import build_progress_graph
from database.repository import StudentRepository


def make_repository(tmp_path: Path) -> StudentRepository:
    repository = StudentRepository(tmp_path / "aegisos.db")
    repository.initialize()
    return repository


def fake_recommendation(_course) -> Intervention:
    return Intervention(
        severity="low",
        reason="model placeholder",
        weak_topics=["not used"],
        lectures_to_review=[99],
        recommended_actions=["Review the verified material."],
        message="Use the verified course facts to plan this week's study.",
    )


def test_student_a_healthy_has_no_intervention(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    twin = build_student_twin(repository, "231027906")
    assert twin is not None
    assert all(not course.risks for course in twin.courses)

    graph = build_progress_graph(repository, fake_recommendation)
    result = graph.invoke({"student_id": "231027906"})
    assert result.get("validated_interventions", []) == []
    assert len(repository.get_weekly_snapshots("231027906")) == 3


def test_student_b_low_midterm_is_detected_and_grounded(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    twin = build_student_twin(repository, "231027905")
    assert twin is not None
    ai = next(course for course in twin.courses if course.course_id == "ai")
    assert any(risk.code == "low_midterm" for risk in ai.risks)
    assert any(risk.code == "midterm_coursework_drop" for risk in ai.risks)
    assert ai.risk_level == "high"

    result = build_progress_graph(repository, fake_recommendation).invoke({"student_id": "231027905"})
    intervention = next(item for course, item in result["validated_interventions"] if course.course_id == "ai")
    assert intervention.lectures_to_review == [5, 6]
    assert "48%" in intervention.reason
    assert repository.get_interventions("231027905")


def test_student_c_lecture_backlog_is_detected(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    twin = build_student_twin(repository, "231027907")
    assert twin is not None
    security = next(course for course in twin.courses if course.course_id == "sec")
    assert any(risk.code == "lecture_backlog" for risk in security.risks)
    assert len(security.unstudied_lectures) == 3


def test_student_d_improving_uses_previous_snapshot_without_duplicate_alert(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    repository.save_weekly_snapshot(
        "231027906", "ds", 5,
        {
            "assignment_average": 50, "lab_average": 50, "quiz_average": None,
            "exam_percentage": 50, "weighted_grade": 50, "lecture_completion": 50,
            "assessment_completion": 50, "course_health": 50, "risk_level": "high", "trend": "declining",
        },
    )
    twin = build_student_twin(repository, "231027906")
    assert twin is not None
    structures = next(course for course in twin.courses if course.course_id == "ds")
    assert structures.metrics.trend == "improving"
    assert not structures.risks


def test_real_registered_student_twin_graph_history_and_what_if(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    # The repository seed contains a registered student and the graph runs on
    # SQLite records; the local generator replaces only the networked Gemini call.
    result = build_progress_graph(repository, fake_recommendation).invoke({"student_id": "231027905"})
    assert result["twin"].student.student_id == "231027905"
    assert len(repository.get_weekly_snapshots("231027905")) == 3
    assert repository.get_interventions("231027905")

    # Re-running unchanged data must not create a duplicate intervention.
    again = build_progress_graph(repository, fake_recommendation).invoke({"student_id": "231027905"})
    assert again.get("validated_interventions", []) == []
    assert len(repository.get_interventions("231027905")) == 1


def test_progress_fastapi_endpoints_and_read_only_what_if(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(
        app_module,
        "build_progress_graph",
        lambda repository: build_progress_graph(repository, fake_recommendation),
    )
    client = TestClient(create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students"))
    progress = client.get("/progress/231027905")
    assert progress.status_code == 200
    assert progress.json()["current_week"] == 6

    analysis = client.post("/progress/analyze/231027905")
    assert analysis.status_code == 200
    assert analysis.json()["interventions"]
    weekly = client.get("/progress/231027905/weekly")
    assert weekly.status_code == 200
    assert len(weekly.json()["snapshots"]) == 3

    before = client.get("/progress/231027905").json()
    projection = client.post(
        "/progress/231027905/what-if",
        json={"type": "assessment_grade", "course_id": "ai", "assessment_id": "ai-final", "hypothetical_grade": 80},
    )
    assert projection.status_code == 200
    assert projection.json()["difference"]["weighted_grade"] > 0
    after = client.get("/progress/231027905").json()
    assert before == after


def test_database_url_selects_the_postgres_repository(tmp_path: Path, monkeypatch) -> None:
    class FakePostgresRepository:
        initialized = False

        def __init__(self, dsn: str) -> None:
            assert dsn == "postgresql://real-database"

        def initialize(self) -> None:
            self.initialized = True

        def get_student(self, student_id: str):
            return None

    monkeypatch.setenv("DATABASE_URL", "postgresql://real-database")
    monkeypatch.setattr(app_module, "PostgresStudentRepository", FakePostgresRepository)
    client = TestClient(create_app(workspace_root=tmp_path / "students"))
    response = client.get("/student/real-student")
    assert response.status_code == 404
