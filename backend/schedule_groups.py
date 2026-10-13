"""Automatic schedule groups: every 25 students of the same major share one schedule.

What comes from the database (nothing is hard-coded):
  * who the students are, their major and current semester,
  * which courses the cohort is enrolled in,
  * when those courses meet (``course_schedule_slots``).

A *cohort* is every student of one major in one semester/year.  Cohort members
are sorted by student id and split into groups of 25 (the last group may be
smaller).  All groups of a cohort take the same courses, so they share the same
class times; each group still has its own identity and classmate list.

If the database has no class times for a course, the course is listed as
"not announced yet".  Nothing is invented unless the operator explicitly sets
``AEGIS_PROVISIONAL_TIMETABLE=1``, in which case a clearly-labelled provisional
layout is produced for the courses that have no times.
"""

from __future__ import annotations

import hashlib
import logging
import os
import re
import threading
import time
from collections import Counter
from typing import Any

from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository
from database.schedule_groups import clean_slots_lenient

Repository = StudentRepository | PostgresStudentRepository

DEFAULT_GROUP_SIZE = 25

# A group's schedule is re-read from the database at most this often per group, so new class
# times (e.g. announced by doctors) show up within a minute.  The refresh runs in the background:
# a student always gets an immediate answer from the stored schedule.
REFRESH_SECONDS = 60
BACKGROUND_REFRESH = True
_last_refresh: dict[tuple[int, str], float] = {}
_refreshing: set[tuple[int, str, str]] = set()
_refresh_lock = threading.Lock()
logger = logging.getLogger("aegisos.schedule_groups")

# Provisional layout.  Sessions are 100 minutes with a 20-minute break (8:30-10:10, 10:30-12:10,
# 12:30-2:10, 2:30-4:10) and are packed into as few days as possible, so students get days off.
# A day can hold several lectures and sections.  Lectures and sections both use ordinary rooms.
PROVISIONAL_BLOCKS = ((510, 610), (630, 730), (750, 850), (870, 970))
PROVISIONAL_DAYS = ("Saturday", "Sunday", "Monday", "Tuesday", "Wednesday")
ROOMS = tuple(f"Room {number}" for number in (103, 104, 105, 201, 202, 203, 204, 205))
# Courses like these meet once a week (a single slot); every other course gets a lecture + a section.
SINGLE_SESSION_COURSE = re.compile(r"project|thesis|graduation|internship|training", re.IGNORECASE)


def group_size() -> int:
    try:
        return max(1, int(os.getenv("AEGIS_GROUP_SIZE", DEFAULT_GROUP_SIZE)))
    except ValueError:
        return DEFAULT_GROUP_SIZE


def provisional_enabled() -> bool:
    return os.getenv("AEGIS_PROVISIONAL_TIMETABLE", "0").strip().lower() in {"1", "true", "yes", "on"}


def group_id_for(cohort_key: str, number: int) -> str:
    digest = hashlib.sha1(cohort_key.encode("utf-8")).hexdigest()[:8]
    return f"grp-{digest}-{number:02d}"


def group_label(cohort: dict[str, Any], number: int) -> str:
    return f"{cohort['major']} · {cohort['level_label']} · Group {number}"


def plan_new_assignments(
    members: list[dict[str, Any]], assigned: dict[str, int], size: int
) -> dict[str, int]:
    """Place unassigned students into the lowest-numbered group that has room.

    Students already in a group never move, so a student's classmates stay
    stable when new students are added later.  On a first build the members are
    sorted by id, which produces clean consecutive blocks of ``size``.
    """
    counts: Counter[int] = Counter(assigned.values())
    result: dict[str, int] = {}
    for member in members:
        student_id = str(member["student_id"])
        if student_id in assigned:
            continue
        number = 1
        while counts[number] >= size:
            number += 1
        counts[number] += 1
        result[student_id] = number
    return result


def _overlaps(taken: list[dict[str, Any]], day: str, start: int, end: int) -> bool:
    return any(t["day_of_week"] == day and t["start_minute"] < end and start < t["end_minute"]
               for t in taken)


def _pick_room(rooms: tuple[str, ...], seed: str, taken: list[dict[str, Any]],
               day: str, start: int, end: int) -> str:
    """A room that is free at that time; the starting choice is stable for a given course."""
    offset = int(hashlib.sha1(seed.encode("utf-8")).hexdigest()[:4], 16)
    busy = {t.get("location") for t in taken
            if t["day_of_week"] == day and t["start_minute"] < end and start < t["end_minute"]}
    for step in range(len(rooms)):
        room = rooms[(offset + step) % len(rooms)]
        if room not in busy:
            return room
    return rooms[offset % len(rooms)]


def provisional_slots(
    courses: list[dict[str, Any]], occupied: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Conflict-free placeholder sessions (with rooms) for courses that have no times.

    Every course gets a lecture and a section on different days, except single-session courses
    such as a project, which get one slot.  Sessions fill the earliest free block of the earliest
    day, so several sessions share a day and the remaining days stay free.
    """
    plan: list[tuple[str, str]] = [(str(c["course_id"]), "Lecture") for c in courses]
    plan += [(str(c["course_id"]), "Section") for c in courses
             if not SINGLE_SESSION_COURSE.search(str(c.get("course_name", "")))]
    taken = list(occupied)
    placed: list[dict[str, Any]] = []
    for course_id, kind in plan:
        days_used = {s["day_of_week"] for s in taken if s["course_id"] == course_id}
        spot: tuple[str, int, int] | None = None
        for avoid_same_day in (True, False):
            for day in PROVISIONAL_DAYS:
                if avoid_same_day and day in days_used:
                    continue
                for start, end in PROVISIONAL_BLOCKS:
                    if not _overlaps(taken, day, start, end):
                        spot = (day, start, end)
                        break
                if spot:
                    break
            if spot:
                break
        if spot is None:
            continue
        day, start, end = spot
        slot = {"course_id": course_id, "day_of_week": day, "start_minute": start,
                "end_minute": end, "session_type": kind,
                "location": _pick_room(ROOMS, f"{course_id}|{kind}", taken, day, start, end)}
        placed.append(slot)
        taken.append(slot)
    return placed


def build_group_content(
    repository: Repository, cohort: dict[str, Any]
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """The common schedule of a cohort: (slots, details) straight from the database."""
    courses = repository.get_cohort_courses(cohort["key"])
    course_ids = [str(course["course_id"]) for course in courses]
    real = clean_slots_lenient(repository.get_course_slots(course_ids))
    scheduled = {slot["course_id"] for slot in real}
    missing = [course_id for course_id in course_ids if course_id not in scheduled]
    provisional: list[dict[str, Any]] = []
    if missing and provisional_enabled():
        provisional = provisional_slots(
            [c for c in courses if str(c["course_id"]) in missing], real
        )
    provisional_ids = sorted({slot["course_id"] for slot in provisional})
    details = {
        "courses": [{"course_id": str(c["course_id"]), "course_name": c["course_name"]} for c in courses],
        "provisional_courses": provisional_ids,
        "unscheduled_courses": [course_id for course_id in missing if course_id not in provisional_ids],
    }
    return real + provisional, details


def _write_group(
    repository: Repository, semester: str, cohort: dict[str, Any], number: int,
    slots: list[dict[str, Any]], details: dict[str, Any],
) -> str:
    # The semester is part of the id so a new term never overwrites the old term's groups.
    group_id = group_id_for(f"{semester}|{cohort['key']}", number)
    repository.save_group_schedule(
        group_id, group_label(cohort, number), semester, cohort, number, details, slots
    )
    return group_id


def build_cohort_groups(
    repository: Repository, semester: str, cohort: dict[str, Any], size: int | None = None
) -> dict[str, str]:
    """Place every unplaced student of the cohort into a group and refresh schedules.

    Returns {student_id: schedule_id} for the students that were newly placed.
    Students whom staff assigned to a hand-made schedule are left alone.
    """
    size = size or group_size()
    members = repository.get_cohort_members(cohort["key"])
    assigned = repository.get_group_assignments(cohort["key"], semester)
    manual = repository.get_manually_scheduled_students(semester)
    eligible = [m for m in members if str(m["student_id"]) not in manual]
    new_numbers = plan_new_assignments(eligible, assigned, size)

    slots, details = build_group_content(repository, cohort)
    group_ids = {
        number: _write_group(repository, semester, cohort, number, slots, details)
        for number in sorted(set(new_numbers.values()) | set(assigned.values()))
    }
    placements = {student_id: group_ids[number] for student_id, number in new_numbers.items()}
    repository.bulk_assign_students(semester, list(placements.items()))
    return placements


def ensure_student_group(
    repository: Repository, student_id: str, semester: str, size: int | None = None
) -> str | None:
    """Return the student's schedule id, building their group first if needed."""
    cohort = repository.get_student_cohort(student_id)
    if cohort is None:
        return None
    current = repository.get_student_schedule(student_id, semester)
    info = repository.get_group_info(current["schedule_id"]) if current else None
    if current and info is None:  # staff placed this student on a hand-made schedule
        return str(current["schedule_id"])
    if current and info and info["cohort_key"] == cohort["key"]:
        slots, details = build_group_content(repository, cohort)
        _write_group(repository, semester, cohort, int(info["group_number"]), slots, details)
        return str(current["schedule_id"])
    placements = build_cohort_groups(repository, semester, cohort, size)
    if student_id.strip() in placements:
        return placements[student_id.strip()]
    again = repository.get_student_schedule(student_id, semester)
    return str(again["schedule_id"]) if again else None


def build_all_groups(repository: Repository, semester: str, size: int | None = None) -> dict[str, Any]:
    """Operator command: build or top up the groups of every cohort."""
    summary: dict[str, Any] = {"cohorts": [], "students_placed": 0}
    for cohort in repository.list_cohorts():
        placements = build_cohort_groups(repository, semester, cohort, size)
        members = repository.get_cohort_members(cohort["key"])
        assigned = repository.get_group_assignments(cohort["key"], semester)
        groups = Counter(assigned.values())
        slots, details = build_group_content(repository, cohort)
        summary["cohorts"].append({
            "cohort": f"{cohort['major']} · {cohort['level_label']}",
            "students": len(members), "groups": len(groups),
            "group_sizes": [groups[n] for n in sorted(groups)],
            "courses": len(details["courses"]),
            "courses_with_real_times": len(details["courses"]) - len(details["unscheduled_courses"])
                                       - len(details["provisional_courses"]),
            "courses_without_times": len(details["unscheduled_courses"]),
            "provisional_courses": len(details["provisional_courses"]),
            "slots": len(slots),
        })
        summary["students_placed"] += len(placements)
    return summary


def _refresh_group(repository: Repository, student_id: str, semester: str, size: int | None) -> None:
    key = (id(repository), student_id.strip(), semester)
    try:
        ensure_student_group(repository, student_id, semester, size)
    except Exception:  # a failed refresh must never break the page; the old schedule stays
        logger.exception("Schedule refresh failed for %s", student_id)
    finally:
        with _refresh_lock:
            _refreshing.discard(key)


def _refresh_due(repository: Repository, schedule_id: str) -> bool:
    marker = (id(repository), schedule_id)
    with _refresh_lock:
        if time.monotonic() - _last_refresh.get(marker, -1e9) < REFRESH_SECONDS:
            return False
        _last_refresh[marker] = time.monotonic()
        return True


def student_schedule_view(
    repository: Repository, student_id: str, semester: str, size: int | None = None
) -> dict[str, Any]:
    """Everything the workspace needs: group, common schedule and the names of the group's members.

    Normal views read the stored group in a single database connection.  The group is rebuilt from
    the database (new class times, new students) at most once a minute, in the background.
    """
    student_id = student_id.strip()
    base: dict[str, Any] = {"student_id": student_id, "semester": semester, "group": None,
                            "schedule": None, "members": [], "classmates": [], "group_size": None}
    bundle = repository.get_student_group_bundle(student_id, semester)
    if bundle is None:  # first visit: build the group now
        ensure_student_group(repository, student_id, semester, size)
        bundle = repository.get_student_group_bundle(student_id, semester)
        if bundle is not None:
            _refresh_due(repository, bundle["schedule_id"])
    elif _refresh_due(repository, bundle["schedule_id"]):
        key = (id(repository), student_id, semester)
        with _refresh_lock:
            already = key in _refreshing
            _refreshing.add(key)
        if not already:
            if BACKGROUND_REFRESH:
                threading.Thread(target=_refresh_group, args=(repository, student_id, semester, size),
                                 daemon=True).start()
            else:
                _refresh_group(repository, student_id, semester, size)
                bundle = repository.get_student_group_bundle(student_id, semester) or bundle
    if bundle is None:
        return base

    details = bundle["details"]
    names = {c["course_id"]: c["course_name"] for c in details.get("courses", [])}
    if not names:
        names = {str(c["course_id"]): c["course_name"] for c in repository.list_portal_courses()}
    provisional = set(details.get("provisional_courses", []))
    slots = [
        {**slot, "course_name": names.get(slot["course_id"], slot["course_id"]),
         "provisional": slot["course_id"] in provisional}
        for slot in bundle["slots"]
    ]
    unscheduled = [
        {"course_id": course_id, "course_name": names.get(course_id, course_id)}
        for course_id in details.get("unscheduled_courses", [])
    ]
    if provisional:
        times_source = "provisional"
    elif not slots:
        times_source = "none"
    elif unscheduled:
        times_source = "partial"
    else:
        times_source = "database"
    members = sorted(
        ({"name": m["name"], "is_you": str(m["student_id"]) == student_id} for m in bundle["members"]),
        key=lambda m: str(m["name"]).casefold(),
    )
    base.update({
        "group": {
            "id": bundle["schedule_id"], "label": bundle["name"], "major": bundle["major"],
            "level_label": bundle["level_label"], "number": bundle["group_number"],
            "size": len(members), "capacity": size or group_size(), "automatic": True,
        },
        "schedule": {
            "schedule_id": bundle["schedule_id"], "name": bundle["name"],
            "semester": bundle["semester"], "slots": slots,
            "unscheduled_courses": unscheduled, "times_source": times_source,
            "courses": details.get("courses", []),
        },
        "members": members,                                  # everyone in the group, you included
        "classmates": [{"name": m["name"]} for m in members if not m["is_you"]],
        "group_size": len(members),
    })
    return base
