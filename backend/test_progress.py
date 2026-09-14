from pathlib import Path

from fastapi.testclient import TestClient

import backend.app as app_module
from backend.app import create_app
from backend.progress.feedback import build_feedback_message, evaluate_intervention_outcome
from backend.progress.models import Assessment, CourseMetrics, CourseTwin, Intervention, Lecture, Risk
from backend.progress.risks import detect_risks
from backend.progress.scheduler import ProgressScheduler, run_analysis_cycle
from backend.progress.service import build_student_twin, course_fingerprint
from backend.progress_agent.graph import build_progress_graph
from backend.progress_agent.prompts import risk_action_templates
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


def test_student_twin_reuses_one_snapshot_query(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    original = repository.get_weekly_snapshots
    calls = 0

    def counted_snapshots(student_id: str):
        nonlocal calls
        calls += 1
        return original(student_id)

    repository.get_weekly_snapshots = counted_snapshots  # type: ignore[method-assign]
    repository.get_previous_course_snapshot = (  # type: ignore[method-assign]
        lambda *_: (_ for _ in ()).throw(AssertionError("unexpected N+1 snapshot query"))
    )

    twin = build_student_twin(repository, "231027906")

    assert twin is not None
    assert calls == 1


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


def test_detect_risks_steady_decline_from_history() -> None:
    assessments: list[Assessment] = []
    lectures = [Lecture(lecture_id="c1-l1", lecture_number=1, title="L1", available_week=1, completed=True)]
    metrics = CourseMetrics(
        lecture_completion=100.0,
        assessment_completion=100.0,
        course_health=70.0,
        previous_course_health=80.0,
        trend="declining",
    )
    recent_snapshots = [
        {"course_health": 90.0},
        {"course_health": 80.0},
    ]
    risks = detect_risks(assessments, lectures, metrics, current_week=3, recent_snapshots=recent_snapshots)
    assert any(risk.code == "steady_decline" and risk.severity == "high" for risk in risks)


def test_detect_risks_lecture_pace_slowdown() -> None:
    assessments: list[Assessment] = []
    lectures = [Lecture(lecture_id="c1-l1", lecture_number=1, title="L1", available_week=1, completed=True)]
    metrics = CourseMetrics(
        lecture_completion=50.0,
        assessment_completion=100.0,
        course_health=50.0,
        previous_course_health=55.0,
        trend="declining",
    )
    recent_snapshots = [
        {"course_health": 40.0, "lecture_completion": 20.0},
        {"course_health": 45.0, "lecture_completion": 45.0},
    ]
    risks = detect_risks(assessments, lectures, metrics, current_week=3, recent_snapshots=recent_snapshots)
    assert any(risk.code == "lecture_pace_slowdown" and risk.severity == "low" for risk in risks)


def test_detect_risks_missing_coursework_window() -> None:
    assessments = [
        Assessment(
            assessment_id="c1-a3",
            name="Assignment 3",
            assessment_type="assignment",
            weight=15.0,
            due_week=3,
            covered_lecture_ids=["c1-l2", "c1-l3"],
            percentage=None,
        ),
    ]
    lectures = [
        Lecture(lecture_id="c1-l1", lecture_number=1, title="L1", available_week=1, completed=True),
        Lecture(lecture_id="c1-l2", lecture_number=2, title="L2", available_week=2, completed=False),
        Lecture(lecture_id="c1-l3", lecture_number=3, title="L3", available_week=2, completed=False),
    ]
    metrics = CourseMetrics(
        lecture_completion=33.33,
        assessment_completion=0.0,
        course_health=40.0,
        trend="new",
    )
    risks = detect_risks(assessments, lectures, metrics, current_week=2)
    assert any(
        risk.code == "missing_coursework_window"
        and risk.severity == "low"
        and "c1-l2" in risk.related_lecture_ids
        for risk in risks
    )


def test_course_fingerprint_includes_severity_and_week_bucket() -> None:
    course = CourseTwin(
        course_id="c1",
        course_name="Course One",
        semester="Fall 2026",
        current_week=6,
        assessments=[],
        lectures=[Lecture(lecture_id="c1-l5", lecture_number=5, title="L5", available_week=6, completed=False)],
        materials=[],
        completed_lectures=[],
        unstudied_lectures=[Lecture(lecture_id="c1-l5", lecture_number=5, title="L5", available_week=6, completed=False)],
        metrics=CourseMetrics(lecture_completion=0.0, assessment_completion=0.0, course_health=50.0, trend="stable"),
        risks=[Risk(code="lecture_backlog", severity="medium", message="backlog", related_lecture_ids=["c1-l5"])],
        risk_level="medium",
    )
    fingerprint = course_fingerprint(course)
    assert "lecture_backlog:medium" in fingerprint
    assert '"week_bucket":' in fingerprint


def test_risk_action_templates_returns_grounded_actions() -> None:
    templates = risk_action_templates({"low_midterm", "lecture_backlog"})
    assert any("midterm" in action.lower() for action in templates)
    assert any("lecture" in action.lower() for action in templates)

    default = risk_action_templates({"unknown_risk_code"})
    assert default == ["Review the verified course material and complete the next study step."]


def test_validate_intervention_falls_back_to_action_templates(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)

    def empty_recommendation(_course) -> Intervention:
        return Intervention(
            severity="low",
            reason="ignored",
            weak_topics=["ignored"],
            lectures_to_review=[99],
            recommended_actions=[],
            message="Placeholder",
        )

    result = build_progress_graph(repository, empty_recommendation).invoke({"student_id": "231027905"})
    intervention = next(item for course, item in result["validated_interventions"] if course.course_id == "ai")
    assert intervention.recommended_actions
    assert any("week 7 exam" in action.lower() for action in intervention.recommended_actions)


def test_detect_risks_deadline_cluster() -> None:
    assessments = [
        Assessment(assessment_id="c1-a3", name="A3", assessment_type="assignment", weight=15.0, due_week=3, covered_lecture_ids=["c1-l3"], percentage=None),
        Assessment(assessment_id="c1-lab2", name="Lab 2", assessment_type="lab", weight=10.0, due_week=3, covered_lecture_ids=["c1-l3"], percentage=None),
        Assessment(assessment_id="c1-final", name="Final", assessment_type="final", weight=35.0, due_week=12, covered_lecture_ids=["c1-l1"], percentage=None),
    ]
    lectures = [Lecture(lecture_id="c1-l1", lecture_number=1, title="L1", available_week=1, completed=True)]
    metrics = CourseMetrics(lecture_completion=100.0, assessment_completion=0.0, course_health=50.0, trend="new")
    risks = detect_risks(assessments, lectures, metrics, current_week=2)
    cluster = next(risk for risk in risks if risk.code == "deadline_cluster")
    assert cluster.severity == "medium"
    assert len(cluster.related_assessment_ids) == 2


def test_progress_narrative_endpoint(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(
        app_module,
        "build_progress_graph",
        lambda repository: build_progress_graph(repository, fake_recommendation),
    )
    client = TestClient(create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students"))
    response = client.get("/progress/231027905/narrative")
    assert response.status_code == 200
    data = response.json()
    assert data["student_id"] == "231027905"
    assert data["narrative"]
    assert "week" in data["narrative"].lower()


def test_progress_narrative_endpoint_rejects_unknown_student(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(
        app_module,
        "build_progress_graph",
        lambda repository: build_progress_graph(repository, fake_recommendation),
    )
    client = TestClient(create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students"))
    response = client.get("/progress/unknown/narrative")
    assert response.status_code == 404


def test_scheduler_run_analyzes_all_students(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    scheduler = ProgressScheduler(repository, recommendation_generator=fake_recommendation)
    result = scheduler.run_once()
    assert result.students_analyzed == len(repository.get_registered_students())
    # At least one student in the seed should generate an intervention.
    assert result.interventions_created > 0
    assert not result.errors


def test_scheduler_run_endpoint_requires_token(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("AEGIS_SCHEDULER_TOKEN", "secret-token")
    monkeypatch.setattr(
        app_module,
        "build_progress_graph",
        lambda repository: build_progress_graph(repository, fake_recommendation),
    )
    client = TestClient(create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students"))
    response = client.post("/progress/scheduler/run")
    assert response.status_code == 403


def test_scheduler_run_endpoint_with_token(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("AEGIS_SCHEDULER_TOKEN", "secret-token")
    monkeypatch.setattr(
        app_module,
        "build_progress_graph",
        lambda repository: build_progress_graph(repository, fake_recommendation),
    )
    client = TestClient(create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students"))
    response = client.post("/progress/scheduler/run", headers={"X-Scheduler-Token": "secret-token"})
    assert response.status_code == 200
    data = response.json()
    assert data["students_analyzed"] > 0
    assert "summary" in data


def test_evaluate_intervention_outcome() -> None:
    course = CourseTwin(
        course_id="c1",
        course_name="Course One",
        semester="Fall 2026",
        current_week=6,
        assessments=[],
        lectures=[],
        materials=[],
        completed_lectures=[],
        unstudied_lectures=[],
        metrics=CourseMetrics(
            lecture_completion=100.0,
            assessment_completion=100.0,
            course_health=75.0,
            trend="improving",
        ),
        risks=[],
    )
    assert evaluate_intervention_outcome({"course_health_at_creation": 60.0}, course) == "improved"
    assert evaluate_intervention_outcome({"course_health_at_creation": 85.0}, course) == "worsened"
    assert evaluate_intervention_outcome({"course_health_at_creation": 76.0}, course) == "stable"
    assert evaluate_intervention_outcome({"course_health_at_creation": None}, course) == "no_data"


def test_build_feedback_message_only_for_improvement() -> None:
    course = CourseTwin(
        course_id="c1",
        course_name="Algorithms",
        semester="Fall 2026",
        current_week=6,
        assessments=[],
        lectures=[],
        materials=[],
        completed_lectures=[],
        unstudied_lectures=[],
        metrics=CourseMetrics(
            lecture_completion=100.0,
            assessment_completion=100.0,
            course_health=75.0,
            trend="improving",
        ),
        risks=[],
    )
    message = build_feedback_message({"course_health_at_creation": 60.0}, course)
    assert message is not None
    assert "Algorithms" in message
    assert "60" in message
    assert "75" in message

    stable = build_feedback_message({"course_health_at_creation": 76.0}, course)
    assert stable is None


def test_intervention_resolved_when_health_improves(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    # Seed an active intervention with a low recorded health.
    repository.save_intervention(
        "231027905", "ai", 4,
        {
            "severity": "high",
            "reason": "previous alert",
            "weak_topics": ["Lecture 5"],
            "lectures_to_review": [5],
            "recommended_actions": ["Review"],
            "message": "Previous warning",
        },
        "old-fingerprint",
        course_health_at_creation=45.0,
    )
    graph = build_progress_graph(repository, fake_recommendation)
    graph.invoke({"student_id": "231027905"})

    interventions = repository.get_interventions("231027905")
    resolved = next(i for i in interventions if i["issue_fingerprint"] == "old-fingerprint")
    assert resolved["status"] == "resolved"
    assert resolved["resolution_outcome"] == "improved"
    assert resolved["resolved_week"] == 6


def test_feedback_appears_in_next_intervention_message(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    # Seed an active intervention with a low recorded health so improvement is detected.
    repository.save_intervention(
        "231027905", "ai", 4,
        {
            "severity": "high",
            "reason": "previous alert",
            "weak_topics": ["Lecture 5"],
            "lectures_to_review": [5],
            "recommended_actions": ["Review"],
            "message": "Previous warning",
        },
        "old-fingerprint",
        course_health_at_creation=45.0,
    )
    graph = build_progress_graph(repository, fake_recommendation)
    result = graph.invoke({"student_id": "231027905"})

    intervention = next(
        item for course, item in result["validated_interventions"]
        if course.course_id == "ai"
    )
    assert "paying off" in intervention.message
    assert "48%" in intervention.reason


def test_intervention_escalated_when_health_declines(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    # Seed an active intervention with a high recorded health; current health is lower.
    repository.save_intervention(
        "231027905", "ai", 4,
        {
            "severity": "medium",
            "reason": "previous alert",
            "weak_topics": ["Lecture 5"],
            "lectures_to_review": [5],
            "recommended_actions": ["Review"],
            "message": "Previous warning",
        },
        "old-fingerprint",
        course_health_at_creation=95.0,
    )
    graph = build_progress_graph(repository, fake_recommendation)
    graph.invoke({"student_id": "231027905"})

    interventions = repository.get_interventions("231027905")
    escalated = next(i for i in interventions if i["issue_fingerprint"] == "old-fingerprint")
    assert escalated["status"] == "escalated"
    assert escalated["resolution_outcome"] == "worsened"
