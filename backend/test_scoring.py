from __future__ import annotations

import sqlite3
from pathlib import Path

from fastapi.testclient import TestClient

from backend.app import create_app


def client_for(tmp_path: Path) -> TestClient:
    return TestClient(create_app(db_path=tmp_path / "aegisos.db", workspace_root=tmp_path / "students"))


def test_scores_are_repeatable_and_show_only_top_five_and_neighbors(tmp_path: Path) -> None:
    client = client_for(tmp_path)
    first = client.get("/scores/231027905")
    assert first.status_code == 200
    data = first.json()
    assert data == client.get("/scores/231027905").json()
    assert data["me"]["score"] == sum(week["points"] for week in data["me"]["weekly"])
    assert data["me"]["score"] == (
        data["me"]["totals"]["lectures"] * 10
        + data["me"]["totals"]["good_exams"] * 25
    )
    assert all("weekly" not in student for student in data["nearby"] + data["top_five"])
    assert client.get("/scores/unknown").status_code == 404


def test_verified_achievements_are_idempotent_and_count_in_their_week(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("AEGIS_SCHEDULER_TOKEN", "staff-secret")
    client = client_for(tmp_path)
    before = client.get("/scores/231027905").json()["me"]["score"]
    achievement = {"achievement_id": "capstone-2026", "kind": "project", "title": "Capstone", "week_number": 5}
    url = "/scores/231027905/achievements"
    assert client.put(url, json=achievement).status_code == 403
    for _ in range(2):
        assert client.put(url, json=achievement, headers={"X-Scheduler-Token": "staff-secret"}).status_code == 200
    after = client.get("/scores/231027905").json()["me"]
    assert after["score"] == before + 40
    assert after["totals"]["projects"] == 1
    assert next(week for week in after["weekly"] if week["week"] == 5)["projects"] == 1
    award = {"achievement_id": "honor-2026", "kind": "award", "title": "Honor", "week_number": 6}
    assert client.put(url, json=award, headers={"X-Scheduler-Token": "staff-secret"}).status_code == 200
    assert client.get("/scores/231027905").json()["me"]["score"] == before + 90
    future = {"achievement_id": "future-prize", "kind": "award", "title": "Future prize", "week_number": 12}
    assert client.put(url, json=future, headers={"X-Scheduler-Token": "staff-secret"}).status_code == 200
    assert client.get("/scores/231027905").json()["me"]["score"] == before + 90


def test_exams_require_good_mark_and_future_work_is_excluded(tmp_path: Path) -> None:
    client = client_for(tmp_path)
    db = tmp_path / "aegisos.db"
    before = client.get("/scores/231027905").json()["me"]
    with sqlite3.connect(db) as connection:
        assessment = connection.execute(
            """SELECT a.assessment_id, a.due_week FROM assessments a
               JOIN course_offerings o ON o.course_id = a.course_id
               JOIN courses c ON c.course_name = o.course_name
               WHERE c.student_id = ? AND a.assessment_type IN ('quiz', 'midterm', 'final', 'exam')
               AND NOT EXISTS (
                 SELECT 1 FROM student_assessment_grades g WHERE g.student_id = c.student_id AND g.assessment_id = a.assessment_id)
               ORDER BY a.due_week LIMIT 1""", ("231027905",)
        ).fetchone()
        assert assessment is not None
        connection.execute("UPDATE assessments SET due_week = 6 WHERE assessment_id = ?", (assessment[0],))
        connection.execute(
            "INSERT INTO student_assessment_grades (student_id, assessment_id, percentage) VALUES (?, ?, ?)",
            ("231027905", assessment[0], 69),
        )
    low = client.get("/scores/231027905").json()["me"]
    assert low["score"] == before["score"]
    assert low["totals"]["exams_taken"] == before["totals"]["exams_taken"] + 1
    with sqlite3.connect(db) as connection:
        connection.execute("UPDATE student_assessment_grades SET percentage = 70 WHERE student_id = ? AND assessment_id = ?",
                           ("231027905", assessment[0]))
    assert client.get("/scores/231027905").json()["me"]["score"] == before["score"] + 25
