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
            "language": state.get("language", "english"),
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
        "language": "english",
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


def test_advisor_endpoint_passes_context_and_language(tmp_path: Path, monkeypatch) -> None:
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
            "message": "كيف حالي الدراسي",
            "language": "arabic",
            "history": [],
        },
    )

    assert response.status_code == 200
    assert response.json()["language"] == "arabic"
    assert fake_graph.state["language"] == "arabic"
    assert fake_graph.state["context"] is not None
    assert fake_graph.state["context"]["student_id"] == "231027905"


def test_advisor_voice_endpoint_flow(tmp_path: Path, monkeypatch) -> None:
    fake_graph = FakeAdvisorGraph()
    monkeypatch.setattr(app_module, "advisor_graph", fake_graph)

    def fake_transcribe(audio_bytes: bytes, language: str = "english") -> str:
        assert language == "english"
        return "How am I doing?"

    def fake_speak(text: str, language: str = "english") -> bytes:
        assert text == "Test advisor response"
        return b"fake-audio-bytes"

    monkeypatch.setattr(app_module, "transcribe_audio", fake_transcribe)
    monkeypatch.setattr(app_module, "synthesize_speech", fake_speak)

    api = create_app(
        db_path=tmp_path / "aegisos.db",
        workspace_root=tmp_path / "students",
    )
    client = TestClient(api)

    response = client.post(
        "/advisor/voice",
        data={"student_id": "231027905", "language": "english"},
        files={"audio": ("test.wav", b"dummy-audio", "audio/wav")},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["student_id"] == "231027905"
    assert data["transcript"] == "How am I doing?"
    assert data["response"] == "Test advisor response"
    assert data["language"] == "english"
    assert data["audio_base64"]


def test_advisor_transcribe_endpoint(tmp_path: Path, monkeypatch) -> None:
    def fake_transcribe(audio_bytes: bytes, language: str = "arabic") -> str:
        return "مرحبا"

    monkeypatch.setattr(app_module, "transcribe_audio", fake_transcribe)

    api = create_app(
        db_path=tmp_path / "aegisos.db",
        workspace_root=tmp_path / "students",
    )
    client = TestClient(api)

    response = client.post(
        "/advisor/transcribe",
        data={"language": "arabic"},
        files={"audio": ("test.wav", b"dummy-audio", "audio/wav")},
    )

    assert response.status_code == 200
    assert response.json()["transcript"] == "مرحبا"
    assert response.json()["language"] == "arabic"


def test_advisor_speak_endpoint(tmp_path: Path, monkeypatch) -> None:
    def fake_speak(text: str, language: str = "english") -> bytes:
        return b"audio-data"

    monkeypatch.setattr(app_module, "synthesize_speech", fake_speak)

    api = create_app(
        db_path=tmp_path / "aegisos.db",
        workspace_root=tmp_path / "students",
    )
    client = TestClient(api)

    response = client.post(
        "/advisor/speak?text=Hello&language=english",
    )

    assert response.status_code == 200
    assert response.json()["language"] == "english"
    assert response.json()["audio_base64"]
