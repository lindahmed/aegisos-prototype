from pathlib import Path

from fastapi.testclient import TestClient

from backend.app import create_app


def make_client(tmp_path: Path, launcher=None) -> TestClient:
    app = create_app(
        db_path=tmp_path / "aegisos.db",
        workspace_root=tmp_path / "students",
        launcher=launcher,
    )
    return TestClient(app)


def test_health(tmp_path: Path) -> None:
    response = make_client(tmp_path).get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_valid_student_comes_from_sqlite_seed(tmp_path: Path) -> None:
    response = make_client(tmp_path).get("/student/231027905")
    assert response.status_code == 200
    assert response.json() == {
        "student_id": "231027905",
        "name": "Yasmin Wael",
        "major": "Computer Science",
        "year": 3,
        "gpa": 3.85,
        "courses": [
            "Artificial Intelligence",
            "Operating Systems",
            "Software Engineering",
        ],
    }


def test_unknown_student_is_rejected(tmp_path: Path) -> None:
    response = make_client(tmp_path).get("/student/not-a-student")
    assert response.status_code == 404


def test_workspace_is_created_for_enrolled_course(tmp_path: Path) -> None:
    response = make_client(tmp_path).post(
        "/workspace/create",
        json={"student_id": "231027905", "course": "Artificial Intelligence"},
    )
    assert response.status_code == 200
    workspace_path = Path(response.json()["path"])
    assert workspace_path.is_dir()
    assert (workspace_path / "assignments").is_dir()
    assert (workspace_path / "labs").is_dir()
    assert "Artificial Intelligence" in (workspace_path / "README.md").read_text()


def test_unenrolled_course_is_rejected(tmp_path: Path) -> None:
    response = make_client(tmp_path).post(
        "/workspace/create",
        json={"student_id": "231027905", "course": "Compiler Design"},
    )
    assert response.status_code == 400


def test_vscode_action_uses_approved_launcher(tmp_path: Path) -> None:
    launched: list[Path] = []
    client = make_client(tmp_path, launcher=launched.append)
    response = client.post(
        "/workspace/vscode",
        json={"student_id": "231027906", "course": "Data Structures"},
    )
    assert response.status_code == 200
    assert response.json()["opened"] is True
    assert launched == [Path(response.json()["path"])]
