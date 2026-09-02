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


def test_portal_courses_are_available_for_gradebook(tmp_path: Path) -> None:
    response = make_client(tmp_path).get("/portal/courses")
    assert response.status_code == 200
    courses = response.json()["courses"]
    ai_course = next(course for course in courses if course["course_id"] == "ai")
    assert ai_course["course_name"] == "Artificial Intelligence"
    assert ai_course["semester"] == "Fall 2026"
    assert ai_course["student_count"] == 1


def test_staff_grade_save_is_visible_to_student_portal(tmp_path: Path) -> None:
    client = make_client(tmp_path)

    response = client.put(
        "/portal/courses/ai/grades",
        json={
            "semester": "Fall 2026",
            "rows": [
                {
                    "student_id": "231027905",
                    "coursework_mark": 9.1,
                    "week7_exam_mark": 25.2,
                    "week12_exam_mark": 16.8,
                    "final_exam_mark": 35.2,
                }
            ],
        },
    )

    assert response.status_code == 200
    saved_row = response.json()["rows"][0]
    assert saved_row["coursework_mark"] == 9.1
    assert saved_row["week7_exam_mark"] == 25.2
    assert saved_row["week12_exam_mark"] == 16.8
    assert saved_row["final_exam_mark"] == 35.2
    assert saved_row["total_score"] == 86.3
    assert saved_row["letter_grade"] == "B"

    student_response = client.get("/portal/students/231027905/grades")
    assert student_response.status_code == 200
    records = student_response.json()["records"]
    ai_record = next(record for record in records if record["course_id"] == "ai")
    assert ai_record["coursework_mark"] == 9.1
    assert ai_record["week7_exam_mark"] == 25.2
    assert ai_record["week12_exam_mark"] == 16.8
    assert ai_record["final_exam_mark"] == 35.2
    assert ai_record["total_score"] == 86.3
    assert ai_record["letter_grade"] == "B"


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


def test_portal_student_validation_by_id(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    response = client.get("/student/231027905")
    assert response.status_code == 200
    assert response.json()["student_id"] == "231027905"


def test_portal_student_validation_rejects_unknown_id(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    response = client.get("/student/STU001")
    assert response.status_code == 404


def test_portal_staff_validation_by_id(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    response = client.get("/portal/staff/104217")
    assert response.status_code == 200
    assert response.json()["valid"] is True


def test_portal_staff_validation_rejects_unknown_id(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    response = client.get("/portal/staff/999999")
    assert response.status_code == 404


def test_portal_student_academics_returns_courses_and_grades(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    response = client.get("/portal/students/231027905/academics")
    assert response.status_code == 200
    data = response.json()
    assert data["student"]["student_id"] == "231027905"
    assert len(data["courses"]) == 3
    course_ids = {course["course_id"] for course in data["courses"]}
    assert "ai" in course_ids
    assert "grades" in data
    assert "records" in data["grades"]


def test_portal_notifications_use_live_academic_data(tmp_path: Path) -> None:
    client = make_client(tmp_path)

    response = client.get("/portal/students/231027905/notifications")

    assert response.status_code == 200
    notifications = response.json()["notifications"]
    assert notifications
    assert all(notification["read"] is False for notification in notifications)
    assert any(
        notification["type"] == "grade"
        and notification["category"] == "Grades"
        and "Artificial Intelligence" in notification["title"]
        for notification in notifications
    )


def test_notification_read_state_is_shared_and_reversible(tmp_path: Path) -> None:
    client = make_client(tmp_path)
    notifications = client.get(
        "/portal/students/231027905/notifications"
    ).json()["notifications"]
    notification_id = notifications[0]["id"]

    marked = client.put(
        "/portal/students/231027905/notifications/read",
        json={"notification_ids": [notification_id], "read": True},
    )
    assert marked.status_code == 200
    assert next(
        notification
        for notification in marked.json()["notifications"]
        if notification["id"] == notification_id
    )["read"] is True
    assert next(
        notification
        for notification in client.get(
            "/portal/students/231027905/notifications"
        ).json()["notifications"]
        if notification["id"] == notification_id
    )["read"] is True

    unmarked = client.put(
        "/portal/students/231027905/notifications/read",
        json={"notification_ids": [notification_id], "read": False},
    )
    assert unmarked.status_code == 200
    assert next(
        notification
        for notification in unmarked.json()["notifications"]
        if notification["id"] == notification_id
    )["read"] is False


def test_portal_grade_save_feeds_progress_agent(tmp_path: Path) -> None:
    client = make_client(tmp_path)

    response = client.put(
        "/portal/courses/ai/grades",
        json={
            "semester": "Fall 2026",
            "rows": [
                {
                    "student_id": "231027905",
                    "coursework_mark": 4,
                    "week7_exam_mark": 10.5,
                    "week12_exam_mark": 7,
                    "final_exam_mark": 12,
                }
            ],
        },
    )
    assert response.status_code == 200

    progress_response = client.get("/progress/231027905")
    assert progress_response.status_code == 200
    twin = progress_response.json()
    ai = next(course for course in twin["courses"] if course["course_id"] == "ai")
    assert ai["metrics"]["exam_percentage"] is not None
    assert ai["metrics"]["weighted_grade"] is not None
