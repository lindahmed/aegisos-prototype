from pathlib import Path

from fastapi.testclient import TestClient

import backend.app as app_module
from backend.app import create_app


class FakeAdvisorGraph:
    def __init__(self) -> None:
        self.state = None

    def invoke(self, state):
        self.state = state
        return {
            "intent": "semester_planning",
            "response": "Test advisor response",
        }


def test_advisor_endpoint_uses_logged_in_student(tmp_path: Path, monkeypatch) -> None:
    fake_graph = FakeAdvisorGraph()
    monkeypatch.setattr(app_module, "advisor_graph", fake_graph)

    api = create_app(
        db_path=tmp_path / "aegisos.db",
        workspace_root=tmp_path / "students",
    )
    client = TestClient(api)

    response = client.post(
        "/advisor",
        json={
            "student_id": "231027905",
            "message": "Help me plan next semester",
            "history": [],
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "intent": "semester_planning",
        "response": "Test advisor response",
    }
    assert fake_graph.state["student"]["student_id"] == "231027905"
    assert fake_graph.state["message"] == "Help me plan next semester"


def test_advisor_rejects_unknown_student(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(app_module, "advisor_graph", FakeAdvisorGraph())

    api = create_app(
        db_path=tmp_path / "aegisos.db",
        workspace_root=tmp_path / "students",
    )
    client = TestClient(api)

    response = client.post(
        "/advisor",
        json={
            "student_id": "does-not-exist",
            "message": "Hello",
            "history": [],
        },
    )

    assert response.status_code == 404
    assert response.json()["detail"] == "Student not found"
