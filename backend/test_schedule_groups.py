"""Schedule groups (25 students per group) and behaviour-based Advisor AI suggestions."""

from __future__ import annotations

import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

from backend.progress.behavior import (
    build_behavior_suggestions,
    summarize_behavior,
)
from backend.progress.insights import InsightsRunner, client_source
from backend.schedule_groups import (
    build_all_groups,
    plan_new_assignments,
    student_schedule_view,
)
from database.repository import StudentRepository

SEMESTER = "Fall 2026"

import backend.schedule_groups as _groups

_groups.BACKGROUND_REFRESH = False   # refresh inline so tests are deterministic
COURSES = ("Artificial Intelligence", "Operating Systems", "Software Engineering")


def make_repository(tmp_path: Path, extra_students: int = 60) -> StudentRepository:
    repository = StudentRepository(tmp_path / "groups.db")
    repository.initialize()
    with sqlite3.connect(repository.database_path) as connection:
        for number in range(extra_students):
            student_id = f"2310{number:05d}"
            connection.execute(
                "INSERT INTO students (student_id, name, major, year, gpa) VALUES (?, ?, 'Computer Science', 3, 3.0)",
                (student_id, f"Student {number:02d}"),
            )
            connection.executemany(
                "INSERT INTO courses (student_id, course_name, status) VALUES (?, ?, 'Current')",
                [(student_id, name) for name in COURSES],
            )
        # Real class times exist for two of the three courses only.
        connection.executemany(
            """INSERT INTO course_schedule_slots (course_id, day_of_week, start_minute, end_minute, location)
               VALUES (?, ?, ?, ?, ?)""",
            [("ai", "Saturday", 540, 630, "Hall A"), ("ai", "Tuesday", 540, 630, "Hall A"),
             ("os", "Sunday", 645, 735, "Lab 2")],
        )
    return repository


def test_plan_new_assignments_blocks_of_25_and_stable() -> None:
    members = [{"student_id": f"{n:03d}"} for n in range(60)]
    first = plan_new_assignments(members, {}, 25)
    sizes = [list(first.values()).count(n) for n in (1, 2, 3)]
    assert sizes == [25, 25, 10]
    # a late student joins the first group with room; nobody already placed moves
    later = plan_new_assignments(members + [{"student_id": "999"}], first, 25)
    assert later == {"999": 3}


def test_every_25_students_of_a_major_share_one_schedule(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    summary = build_all_groups(repository, SEMESTER)
    cs = next(c for c in summary["cohorts"] if c["cohort"].startswith("Computer Science · Year 3"))
    assert cs["students"] == 61                       # 60 added + Yasmin from students.csv
    assert cs["group_sizes"] == [25, 25, 11]
    assert cs["courses_with_real_times"] == 2 and cs["courses_without_times"] == 1

    # ids are sorted, so 231000000-231000024 form group 1 and Yasmin (231027905) closes group 3
    view = student_schedule_view(repository, "231000000", SEMESTER)
    assert view["group"]["number"] == 1 and view["group"]["size"] == 25
    assert view["group"]["automatic"] is True
    assert len(view["classmates"]) == 24
    assert all(set(c) == {"name"} for c in view["classmates"])
    # only database times are shown, and the course without times is "not announced"
    assert {s["course_name"] for s in view["schedule"]["slots"]} == {"Artificial Intelligence", "Operating Systems"}
    assert [c["course_name"] for c in view["schedule"]["unscheduled_courses"]] == ["Software Engineering"]
    assert view["schedule"]["times_source"] == "partial"

    # a classmate sees the same group and the same schedule; a student in another group does not
    mate = student_schedule_view(repository, "231000024", SEMESTER)
    assert mate["group"]["id"] == view["group"]["id"] and mate["schedule"]["slots"] == view["schedule"]["slots"]
    last = student_schedule_view(repository, "231027905", SEMESTER)
    assert last["group"]["number"] == 3 and last["group"]["size"] == 11
    assert last["schedule"]["slots"] == view["schedule"]["slots"]   # same common college schedule


def test_schedule_view_builds_the_group_on_demand_and_is_stable(tmp_path: Path) -> None:
    repository = make_repository(tmp_path, extra_students=5)
    first = student_schedule_view(repository, "231027905", SEMESTER)
    assert first["group"]["number"] == 1 and first["group_size"] == 6
    again = student_schedule_view(repository, "231027905", SEMESTER)
    assert again["group"]["id"] == first["group"]["id"]
    assert student_schedule_view(repository, "does-not-exist", SEMESTER)["group"] is None


def test_activity_and_suggestions_are_stored_and_deduplicated(tmp_path: Path) -> None:
    repository = make_repository(tmp_path, extra_students=0)
    runner = InsightsRunner(repository, run_inline=True)
    assert runner.record("231027905", "workspace", "workspace_create", "Artificial Intelligence")
    assert not runner.record("231027905", "workspace", "workspace_create", "Artificial Intelligence")  # repeat
    assert not runner.record("231027905", "workspace", "not_an_event")
    events = repository.get_recent_activity("231027905", datetime.now(UTC) - timedelta(days=1))
    assert len(events) == 1 and events[0]["occurred_at"].tzinfo is not None

    item = {"code": "behavior_consistent", "priority": "low", "title": "t", "body": "b", "course_id": ""}
    assert len(repository.save_suggestions("231027905", SEMESTER, 6, [item])) == 1
    assert repository.save_suggestions("231027905", SEMESTER, 6, [item]) == []      # no second notification
    assert len(repository.get_advisor_suggestions("231027905")) == 1


def _course(course_id: str, name: str, risk: str | None) -> SimpleNamespace:
    lecture = SimpleNamespace(lecture_number=3, title="Scheduling")
    return SimpleNamespace(course_id=course_id, course_name=name, risk_level=risk,
                           unstudied_lectures=[lecture])


def test_behavior_rules_only_state_what_the_data_shows() -> None:
    now = datetime(2026, 10, 6, 12, tzinfo=UTC)
    events = [
        {"occurred_at": now - timedelta(days=d), "source": s, "event_type": "login",
         "course_ref": None, "detail": None}
        for d, s in ((0, "workspace"), (1, "app"), (2, "website"))
    ]
    summary = summarize_behavior(events, now)
    assert summary.active_days == 3 and summary.by_source == {"workspace": 1, "app": 1, "website": 1}
    twin = SimpleNamespace(courses=[_course("os", "Operating Systems", "high")])
    codes = {s["code"] for s in build_behavior_suggestions(summary, twin, [], now)}
    assert "behavior_neglected" in codes            # flagged course with no activity
    assert "behavior_workspace_unused" in codes     # 3 active days, no workspace opened
    assert "behavior_consistent" not in codes       # needs 5 active days


def test_client_source_detects_workspace_app_and_website() -> None:
    assert client_source("Mozilla/5.0 Electron/30 UniTrack") == "workspace"
    assert client_source("Dart/3.4 (dart:io)") == "app"
    assert client_source("Mozilla/5.0 Chrome/126") == "website"
    assert client_source("curl/8", explicit="app") == "app"


# --- HTTP endpoints (need the backend requirements: fastapi + httpx) -------------------------
def test_schedule_endpoint_returns_group_schedule_and_classmates(tmp_path: Path) -> None:
    from fastapi.testclient import TestClient

    from backend.app import create_app

    client = TestClient(create_app(db_path=tmp_path / "api.db", workspace_root=tmp_path / "students"))
    body = client.get("/portal/students/231027905/schedule").json()
    assert body["group"]["number"] == 1 and body["group"]["automatic"] is True
    assert body["schedule"]["semester"] == "Fall 2026"
    assert isinstance(body["classmates"], list)
    assert client.get("/portal/students/not-a-student/schedule").status_code == 404


def test_activity_endpoint_and_advisor_notification(tmp_path: Path) -> None:
    from fastapi.testclient import TestClient

    from backend.app import create_app

    db_path = tmp_path / "api.db"
    client = TestClient(create_app(db_path=db_path, workspace_root=tmp_path / "students"))
    response = client.post(
        "/portal/students/231027905/activity",
        json={"event_type": "screen_view", "source": "app"},
    )
    assert response.json() == {"recorded": True}
    StudentRepository(db_path).save_suggestions(
        "231027905", SEMESTER, 6,
        [{"code": "behavior_consistent", "priority": "low", "title": "Strong study consistency",
          "body": "You were active on 5 of the last 7 days.", "course_id": ""}],
    )
    notifications = client.get("/portal/students/231027905/notifications").json()["notifications"]
    advisor = [n for n in notifications if n["type"] == "advisor"]
    assert [n["category"] for n in advisor] == ["Advisor AI"]


def test_provisional_times_fill_missing_courses_and_real_times_replace_them(tmp_path: Path) -> None:
    import os
    import backend.schedule_groups as groups

    repository = make_repository(tmp_path, extra_students=30)
    os.environ["AEGIS_PROVISIONAL_TIMETABLE"] = "1"
    groups.REFRESH_SECONDS = 0
    try:
        view = student_schedule_view(repository, "231000000", SEMESTER)
        by_course: dict[str, list] = {}
        for slot in view["schedule"]["slots"]:
            by_course.setdefault(slot["course_name"], []).append(slot)
        assert view["schedule"]["times_source"] == "provisional"
        assert view["schedule"]["unscheduled_courses"] == []
        assert all(s["provisional"] for s in by_course["Software Engineering"])
        # a lecture and a section on different days, each with a room
        kinds = sorted((s["session_type"], s["location"] is not None) for s in by_course["Software Engineering"])
        assert kinds == [("Lecture", True), ("Section", True)]
        assert len({s["day_of_week"] for s in by_course["Software Engineering"]}) == 2
        assert not any(s["provisional"] for s in by_course["Artificial Intelligence"])
        # no two classes overlap
        slots = view["schedule"]["slots"]
        for i, a in enumerate(slots):
            for b in slots[i + 1:]:
                assert not (a["day_of_week"] == b["day_of_week"]
                            and a["start_minute"] < b["end_minute"] and b["start_minute"] < a["end_minute"])
        # the second group of the cohort gets the same common times
        other = student_schedule_view(repository, "231000029", SEMESTER)
        assert other["group"]["number"] == 2 and other["schedule"]["slots"] == view["schedule"]["slots"]
        # when real times are announced they replace the placeholders automatically
        with sqlite3.connect(repository.database_path) as connection:
            connection.execute(
                "INSERT INTO course_schedule_slots (course_id, day_of_week, start_minute, end_minute, location) "
                "SELECT course_id, 'Monday', 840, 930, 'Hall C' FROM course_offerings WHERE course_name = 'Software Engineering'"
            )
        updated = student_schedule_view(repository, "231000000", SEMESTER)
        se = [s for s in updated["schedule"]["slots"] if s["course_name"] == "Software Engineering"]
        assert se and not any(s["provisional"] for s in se) and se[0]["location"] == "Hall C"
    finally:
        os.environ.pop("AEGIS_PROVISIONAL_TIMETABLE", None)
        groups.REFRESH_SECONDS = 60


def test_project_courses_get_a_single_slot_and_days_stay_free() -> None:
    from backend.schedule_groups import provisional_slots

    courses = [{"course_id": "nlp", "course_name": "Natural Language Processing"},
               {"course_id": "dip", "course_name": "Digital Image Processing"},
               {"course_id": "prj", "course_name": "Project I"}]
    slots = provisional_slots(courses, [])
    assert [s["course_id"] for s in slots].count("prj") == 1
    assert {s["session_type"] for s in slots if s["course_id"] == "nlp"} == {"Lecture", "Section"}
    assert len({s["day_of_week"] for s in slots}) <= 2               # sessions are packed: days off
    assert max([s["day_of_week"] for s in slots].count(d) for d in {s["day_of_week"] for s in slots}) >= 3
    for i, a in enumerate(slots):
        for b in slots[i + 1:]:
            assert not (a["day_of_week"] == b["day_of_week"]
                        and a["start_minute"] < b["end_minute"] and b["start_minute"] < a["end_minute"])


def test_every_member_sees_all_members_including_themselves(tmp_path: Path) -> None:
    repository = make_repository(tmp_path, extra_students=30)
    view = student_schedule_view(repository, "231000003", SEMESTER)
    assert len(view["members"]) == 25 and sum(m["is_you"] for m in view["members"]) == 1
    assert [m["name"] for m in view["members"]] == sorted((m["name"] for m in view["members"]), key=str.casefold)
    assert len(view["classmates"]) == 24
    # a member of the other group sees a different member list
    other = student_schedule_view(repository, "231000027", SEMESTER)
    assert other["group"]["number"] == 2 and len(other["members"]) == 6
    assert {m["name"] for m in other["members"]}.isdisjoint({m["name"] for m in view["members"]})
