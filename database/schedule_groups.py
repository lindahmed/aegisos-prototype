"""Storage shared by the SQLite and PostgreSQL repositories for:

* automatic schedule groups (every 25 students of one major share a schedule),
* student activity events (workspace / app / website),
* Advisor AI behaviour suggestions.

Everything here is written with ``?`` placeholders.  Each repository supplies
two tiny hooks (``_sg_all`` and ``_sg_write``) that run the SQL on its own
database, so the logic exists exactly once.  The cohort-specific queries (who
is in a cohort, which courses it takes) differ per schema and live in each
repository.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

DAY_ORDER = ("Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
_DAY_ALIASES = {
    "sat": "Saturday", "sun": "Sunday", "mon": "Monday", "tue": "Tuesday",
    "tues": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "thur": "Thursday",
    "thurs": "Thursday", "fri": "Friday",
}

SCHEMA_STATEMENTS = (
    """CREATE TABLE IF NOT EXISTS schedule_groups (
        schedule_id TEXT PRIMARY KEY,
        semester TEXT NOT NULL,
        name TEXT NOT NULL,
        cohort_key TEXT NOT NULL,
        major TEXT NOT NULL,
        level_label TEXT NOT NULL,
        group_number INTEGER NOT NULL,
        details_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
    )""",
    """CREATE TABLE IF NOT EXISTS schedule_group_slots (
        schedule_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        day_of_week TEXT NOT NULL,
        start_minute INTEGER NOT NULL,
        end_minute INTEGER NOT NULL,
        location TEXT,
        session_type TEXT
    )""",
    "CREATE INDEX IF NOT EXISTS idx_schedule_group_slots ON schedule_group_slots(schedule_id)",
    """CREATE TABLE IF NOT EXISTS schedule_group_members (
        student_id TEXT NOT NULL,
        semester TEXT NOT NULL,
        schedule_id TEXT NOT NULL,
        cohort_key TEXT NOT NULL,
        PRIMARY KEY (student_id, semester)
    )""",
    "CREATE INDEX IF NOT EXISTS idx_schedule_group_members ON schedule_group_members(schedule_id)",
    """CREATE TABLE IF NOT EXISTS advisor_suggestions (
        suggestion_id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        semester TEXT NOT NULL,
        week_number INTEGER NOT NULL,
        code TEXT NOT NULL,
        priority TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        course_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        UNIQUE (student_id, semester, week_number, code, course_id)
    )""",
)
# Only the auto-increment column differs between the two databases.
ACTIVITY_TABLE_SQLITE = """CREATE TABLE IF NOT EXISTS student_activity_events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    student_id TEXT NOT NULL, source TEXT NOT NULL, event_type TEXT NOT NULL,
    course_ref TEXT, detail TEXT, occurred_at TEXT NOT NULL)"""
ACTIVITY_TABLE_POSTGRES = """CREATE TABLE IF NOT EXISTS student_activity_events (
    event_id BIGSERIAL PRIMARY KEY,
    student_id TEXT NOT NULL, source TEXT NOT NULL, event_type TEXT NOT NULL,
    course_ref TEXT, detail TEXT, occurred_at TEXT NOT NULL)"""
# Databases created before session types existed need this column added.
MIGRATIONS_POSTGRES = (
    "ALTER TABLE schedule_group_slots ADD COLUMN IF NOT EXISTS session_type TEXT",
)
MIGRATIONS_SQLITE_COLUMNS = (
    ("schedule_group_slots", "session_type", "TEXT"),
    ("course_schedule_slots", "session_type", "TEXT"),
)
ACTIVITY_INDEX = (
    "CREATE INDEX IF NOT EXISTS idx_student_activity ON student_activity_events(student_id, occurred_at)"
)


def _normal_day(value: Any) -> str:
    text = str(value or "").strip()
    return _DAY_ALIASES.get(text.casefold(), text.title())


_TYPE_ALIASES = {
    "lecture": "Lecture", "lec": "Lecture", "lect": "Lecture", "l": "Lecture",
    "section": "Section", "sec": "Section", "tutorial": "Section", "tut": "Section",
    "lab": "Lab", "laboratory": "Lab",
}
_TYPE_COLUMNS = ("session_type", "slot_type", "class_type", "component", "kind", "type")


def normalize_session_type(value: Any) -> str | None:
    text = str(value or "").strip()
    if not text:
        return None
    return _TYPE_ALIASES.get(text.casefold(), text.title())


def slot_from_row(row: dict[str, Any]) -> dict[str, Any]:
    """A course_schedule_slots row in the standard shape, picking up the session type
    (lecture / section / lab) from whichever column the database uses for it, if any."""
    lowered = {str(key).casefold(): value for key, value in row.items()}
    session = next((lowered[c] for c in _TYPE_COLUMNS if lowered.get(c)), None)
    return {
        "course_id": str(row.get("course_id") or ""), "day_of_week": row.get("day_of_week"),
        "start_minute": row.get("start_minute"), "end_minute": row.get("end_minute"),
        "location": row.get("location"), "session_type": normalize_session_type(session),
    }


def clean_slots_lenient(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Normalise class-time rows from the database; drop only the unusable ones.

    Keeps a row when it names a course and has integer minutes with
    ``0 <= start < end <= 1440``.  Day names such as "sat" become "Saturday".
    Exact duplicates are removed and the result is ordered Saturday-first.
    """
    seen: set[tuple[str, str, int, int, str | None]] = set()
    cleaned: list[dict[str, Any]] = []
    for row in rows or []:
        try:
            start, end = int(row["start_minute"]), int(row["end_minute"])
        except (KeyError, TypeError, ValueError):
            continue
        course_id = str(row.get("course_id") or "").strip()
        day = _normal_day(row.get("day_of_week"))
        if not course_id or not day or not 0 <= start < end <= 1440:
            continue
        session_type = normalize_session_type(row.get("session_type"))
        key = (course_id, day, start, end, session_type)
        if key in seen:
            continue
        seen.add(key)
        cleaned.append({
            "course_id": course_id, "day_of_week": day, "start_minute": start,
            "end_minute": end, "location": row.get("location") or None,
            "session_type": session_type,
        })
    order = {name: index for index, name in enumerate(DAY_ORDER)}
    cleaned.sort(key=lambda s: (order.get(s["day_of_week"], 99), s["start_minute"], s["course_id"]))
    return cleaned


def _now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


class ScheduleGroupStoreMixin:
    """Repository methods that are identical for SQLite and PostgreSQL."""

    # hooks supplied by each repository --------------------------------
    def _sg_all(self, sql: str, params: tuple = ()) -> list[dict[str, Any]]:
        raise NotImplementedError

    def _sg_write(self, statements: list[tuple[str, tuple]]) -> list[int]:
        raise NotImplementedError

    def _sg_batch(self, reads: list[tuple[str, tuple]]) -> list[list[dict[str, Any]]]:
        """Several SELECTs over ONE connection (each extra connection costs round trips)."""
        raise NotImplementedError

    # SELECT of (student_id, name) for every member of the schedule group the student is in;
    # takes (student_id, semester).  Written by each repository for its own students table.
    _SG_MEMBERS_SQL = ""

    # schedule groups ---------------------------------------------------
    def save_group_schedule(
        self, group_id: str, label: str, semester: str, cohort: dict[str, Any],
        number: int, details: dict[str, Any], slots: list[dict[str, Any]],
    ) -> None:
        statements: list[tuple[str, tuple]] = [
            ("""INSERT INTO schedule_groups
                (schedule_id, semester, name, cohort_key, major, level_label,
                 group_number, details_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (schedule_id) DO UPDATE SET
                  name = excluded.name, details_json = excluded.details_json,
                  major = excluded.major, level_label = excluded.level_label,
                  updated_at = excluded.updated_at""",
             (group_id, semester, label, cohort["key"], cohort["major"],
              cohort["level_label"], number, json.dumps(details), _now_iso())),
            ("DELETE FROM schedule_group_slots WHERE schedule_id = ?", (group_id,)),
        ]
        for start in range(0, len(slots), 50):  # one statement per 50 slots, not one per slot
            chunk = slots[start:start + 50]
            marks = ", ".join("(?, ?, ?, ?, ?, ?, ?)" for _ in chunk)
            params: list[Any] = []
            for slot in chunk:
                params += [group_id, slot["course_id"], slot["day_of_week"], slot["start_minute"],
                           slot["end_minute"], slot.get("location"), slot.get("session_type")]
            statements.append((
                f"""INSERT INTO schedule_group_slots
                    (schedule_id, course_id, day_of_week, start_minute, end_minute, location, session_type)
                    VALUES {marks}""", tuple(params)))
        self._sg_write(statements)

    def get_group_assignments(self, cohort_key: str, semester: str) -> dict[str, int]:
        rows = self._sg_all(
            """SELECT m.student_id, g.group_number
               FROM schedule_group_members m
               JOIN schedule_groups g ON g.schedule_id = m.schedule_id
               WHERE m.cohort_key = ? AND m.semester = ?""",
            (cohort_key, semester),
        )
        return {str(r["student_id"]): int(r["group_number"]) for r in rows}

    def bulk_assign_students(self, semester: str, placements: list[tuple[str, str]]) -> None:
        if not placements:
            return
        ids = sorted({schedule_id for _, schedule_id in placements})
        rows = self._sg_all(
            f"SELECT schedule_id, cohort_key FROM schedule_groups WHERE schedule_id IN ({', '.join('?' for _ in ids)})",
            tuple(ids),
        )
        cohort_of = {r["schedule_id"]: r["cohort_key"] for r in rows}
        known = [(sid, gid) for sid, gid in placements if gid in cohort_of]
        statements: list[tuple[str, tuple]] = []
        for start in range(0, len(known), 100):
            chunk = known[start:start + 100]
            marks = ", ".join("(?, ?, ?, ?)" for _ in chunk)
            params: list[Any] = []
            for student_id, schedule_id in chunk:
                params += [student_id, semester, schedule_id, cohort_of[schedule_id]]
            statements.append((
                f"""INSERT INTO schedule_group_members (student_id, semester, schedule_id, cohort_key)
                    VALUES {marks}
                    ON CONFLICT (student_id, semester) DO UPDATE SET
                      schedule_id = excluded.schedule_id, cohort_key = excluded.cohort_key""",
                tuple(params)))
        self._sg_write(statements)

    def get_manually_scheduled_students(self, semester: str) -> set[str]:
        """Staff-made schedules are not stored in this schema, so nobody is excluded."""
        return set()

    def get_student_schedule(self, student_id: str, semester: str) -> dict[str, Any] | None:
        rows = self._sg_all(
            "SELECT schedule_id FROM schedule_group_members WHERE student_id = ? AND semester = ?",
            (student_id.strip(), semester),
        )
        return rows[0] if rows else None

    def get_group_info(self, schedule_id: str) -> dict[str, Any] | None:
        rows = self._sg_all(
            """SELECT cohort_key, major, level_label, group_number, details_json
               FROM schedule_groups WHERE schedule_id = ?""",
            (schedule_id,),
        )
        if not rows:
            return None
        row = rows[0]
        return {
            "cohort_key": row["cohort_key"], "major": row["major"],
            "level_label": row["level_label"], "group_number": int(row["group_number"]),
            "details": json.loads(row["details_json"] or "{}"),
        }

    def get_schedule(self, schedule_id: str) -> dict[str, Any] | None:
        head = self._sg_all(
            "SELECT schedule_id, name, semester FROM schedule_groups WHERE schedule_id = ?",
            (schedule_id,),
        )
        if not head:
            return None
        slots = self._sg_all(
            """SELECT course_id, day_of_week, start_minute, end_minute, location, session_type
               FROM schedule_group_slots WHERE schedule_id = ?""",
            (schedule_id,),
        )
        return {**head[0], "slots": clean_slots_lenient(slots)}

    def get_student_group_bundle(self, student_id: str, semester: str) -> dict[str, Any] | None:
        """Group, class times and member names for a student in ONE database connection."""
        student_id = student_id.strip()
        group, slots, members = self._sg_batch([
            ("""SELECT g.schedule_id, g.name, g.semester, g.cohort_key, g.major, g.level_label,
                       g.group_number, g.details_json
                FROM schedule_group_members m JOIN schedule_groups g ON g.schedule_id = m.schedule_id
                WHERE m.student_id = ? AND m.semester = ?""", (student_id, semester)),
            ("""SELECT course_id, day_of_week, start_minute, end_minute, location, session_type
                FROM schedule_group_slots
                WHERE schedule_id = (SELECT schedule_id FROM schedule_group_members
                                     WHERE student_id = ? AND semester = ?)""", (student_id, semester)),
            (self._SG_MEMBERS_SQL, (student_id, semester)),
        ])
        if not group:
            return None
        row = group[0]
        return {
            "schedule_id": row["schedule_id"], "name": row["name"], "semester": row["semester"],
            "cohort_key": row["cohort_key"], "major": row["major"],
            "level_label": row["level_label"], "group_number": int(row["group_number"]),
            "details": json.loads(row["details_json"] or "{}"),
            "slots": clean_slots_lenient(slots), "members": members,
        }

    # activity ------------------------------------------------------------
    def record_activity(
        self, student_id: str, source: str, event_type: str,
        course_ref: str | None = None, detail: str | None = None,
    ) -> None:
        self._sg_write([(
            """INSERT INTO student_activity_events
               (student_id, source, event_type, course_ref, detail, occurred_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (student_id, source, event_type, course_ref, detail, _now_iso()),
        )])

    def get_recent_activity(self, student_id: str, since: datetime) -> list[dict[str, Any]]:
        rows = self._sg_all(
            """SELECT source, event_type, course_ref, detail, occurred_at
               FROM student_activity_events
               WHERE student_id = ? AND occurred_at >= ? ORDER BY occurred_at""",
            (student_id, since.astimezone(UTC).isoformat(timespec="microseconds")),
        )
        events = []
        for row in rows:
            stamp = datetime.fromisoformat(str(row["occurred_at"]))
            if stamp.tzinfo is None:
                stamp = stamp.replace(tzinfo=UTC)
            events.append({**row, "occurred_at": stamp})
        return events

    # advisor suggestions -------------------------------------------------
    def save_suggestions(
        self, student_id: str, semester: str, week_number: int, suggestions: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Insert suggestions; returns only the ones that were not already stored."""
        created: list[dict[str, Any]] = []
        for item in suggestions:
            suggestion_id = uuid4().hex
            counts = self._sg_write([(
                """INSERT INTO advisor_suggestions
                   (suggestion_id, student_id, semester, week_number, code, priority,
                    title, body, course_id, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT (student_id, semester, week_number, code, course_id) DO NOTHING""",
                (suggestion_id, student_id, semester, week_number, item["code"],
                 item["priority"], item["title"], item["body"],
                 item.get("course_id") or "", _now_iso()),
            )])
            if counts and counts[0] > 0:
                created.append({**item, "suggestion_id": suggestion_id})
        return created

    def get_advisor_suggestions(self, student_id: str, limit: int = 20) -> list[dict[str, Any]]:
        return self._sg_all(
            """SELECT suggestion_id, week_number, code, priority, title, body, course_id, created_at
               FROM advisor_suggestions WHERE student_id = ?
               ORDER BY created_at DESC LIMIT ?""",
            (student_id, limit),
        )
