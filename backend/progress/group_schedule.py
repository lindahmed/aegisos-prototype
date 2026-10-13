from __future__ import annotations
 
import hashlib
import os
from collections import Counter
from typing import Any
 
from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository
from database.schedule_groups import clean_slots_lenient
 
Repository = StudentRepository | PostgresStudentRepository
 
DEFAULT_GROUP_SIZE = 25
 
# Provisional layout: 90-minute blocks, two meetings per course on different days.
PROVISIONAL_BLOCKS = ((540, 630), (645, 735), (750, 840), (855, 945))
PROVISIONAL_DAY_PAIRS = (
    ("Saturday", "Tuesday"), ("Sunday", "Wednesday"), ("Monday", "Thursday"),
)
 
 
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
 
 
def provisional_slots(course_ids: list[str], occupied: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Conflict-free placeholder times for courses that have none in the database."""
    taken = list(occupied)
    placed: list[dict[str, Any]] = []
    for course_id in course_ids:
        chosen: list[tuple[str, int, int]] = []
        for start, end in PROVISIONAL_BLOCKS:
            for first, second in PROVISIONAL_DAY_PAIRS:
                if not _overlaps(taken, first, start, end) and not _overlaps(taken, second, start, end):
                    chosen = [(first, start, end), (second, start, end)]
                    break
            if chosen:
                break
        if not chosen:  # no free pair left: settle for a single meeting
            for start, end in PROVISIONAL_BLOCKS:
                for first, second in PROVISIONAL_DAY_PAIRS:
                    for day in (first, second):
                        if not _overlaps(taken, day, start, end):
                            chosen = [(day, start, end)]
                            break
                    if chosen:
                        break
                if chosen:
                    break
        for day, start, end in chosen:
            slot = {"course_id": course_id, "day_of_week": day, "start_minute": start,
                    "end_minute": end, "location": None}
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
        provisional = provisional_slots(missing, real)
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
    group_id = group_id_for(cohort["key"], number)
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
 
 
def student_schedule_view(
    repository: Repository, student_id: str, semester: str, size: int | None = None
) -> dict[str, Any]:
    """Everything the workspace needs: group, common schedule, classmate names."""
    schedule_id = ensure_student_group(repository, student_id, semester, size)
    base: dict[str, Any] = {"student_id": student_id, "semester": semester,
                            "group": None, "schedule": None, "classmates": [], "group_size": None}
    if schedule_id is None:
        return base
    schedule = repository.get_schedule(schedule_id)
    if schedule is None:
        return base
    info = repository.get_group_info(schedule_id)
    details = info["details"] if info else {}
    names = {c["course_id"]: c["course_name"] for c in details.get("courses", [])}
    if not names:
        names = {str(c["course_id"]): c["course_name"] for c in repository.list_portal_courses()}
    provisional = set(details.get("provisional_courses", []))
    slots = [
        {**slot, "course_name": names.get(slot["course_id"], slot["course_id"]),
         "provisional": slot["course_id"] in provisional}
        for slot in schedule["slots"]
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
    members = repository.get_schedule_group(schedule_id)
    classmates = sorted(
        ({"name": m["name"]} for m in members if str(m["student_id"]) != student_id.strip()),
        key=lambda m: str(m["name"]).casefold(),
    )
    base.update({
        "group": {
            "id": schedule_id,
            "label": schedule["name"],
            "major": info["major"] if info else None,
            "level_label": info["level_label"] if info else None,
            "number": info["group_number"] if info else None,
            "size": len(members),
            "capacity": size or group_size() if info else None,
            "automatic": info is not None,
        },
        "schedule": {
            "schedule_id": schedule_id, "name": schedule["name"],
            "semester": schedule["semester"], "slots": slots,
            "unscheduled_courses": unscheduled, "times_source": times_source,
            "courses": details.get("courses", []),
        },
        "classmates": classmates,
        "group_size": len(members),
    })
    return base
