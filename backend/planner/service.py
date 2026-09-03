from __future__ import annotations

from typing import Any


DEFAULT_COURSE_CREDITS = 3


def _course_status(value: object) -> str:
    return str(value or "").strip().casefold()


def _slot_conflicts(first: dict[str, Any], second: dict[str, Any]) -> bool:
    return (
        str(first.get("day_of_week", "")).casefold()
        == str(second.get("day_of_week", "")).casefold()
        and int(first.get("start_minute", 0)) < int(second.get("end_minute", 0))
        and int(second.get("start_minute", 0)) < int(first.get("end_minute", 0))
    )


def _find_conflicts(courses: list[dict[str, Any]]) -> list[dict[str, Any]]:
    conflicts: list[dict[str, Any]] = []
    for index, first in enumerate(courses):
        for second in courses[index + 1 :]:
            for first_slot in first.get("schedule", []):
                for second_slot in second.get("schedule", []):
                    if _slot_conflicts(first_slot, second_slot):
                        conflicts.append(
                            {
                                "course_codes": [first["course_code"], second["course_code"]],
                                "day_of_week": first_slot["day_of_week"],
                                "first": first_slot,
                                "second": second_slot,
                            }
                        )
    return conflicts


def build_semester_plan(
    source: dict[str, Any], *, max_credits: int = 18, expected_term_gpa: float = 3.3
) -> dict[str, Any]:
    """Build a prerequisite-valid plan from normalized curriculum records.

    The current source schema has no credit-hour column, so the response labels
    the three-credit fallback everywhere it is used. Schedule conflicts are
    authoritative only when schedule rows exist in the database.
    """
    max_credits = min(24, max(3, max_credits))
    expected_term_gpa = min(4.0, max(0.0, expected_term_gpa))
    student = source["student"]
    courses = [dict(course) for course in source.get("courses", [])]
    enrollments = {
        str(row["course_id"]): row for row in source.get("enrollments", [])
    }
    prerequisites: dict[str, list[str]] = {}
    for row in source.get("prerequisites", []):
        prerequisites.setdefault(str(row["course_id"]), []).append(
            str(row["prerequisite_course_id"])
        )
    schedules: dict[str, list[dict[str, Any]]] = {}
    for row in source.get("schedules", []):
        schedule = dict(row)
        course_id = str(schedule.pop("course_id"))
        schedules.setdefault(course_id, []).append(schedule)

    by_id = {str(course["course_id"]): course for course in courses}
    completed = {
        course_id
        for course_id, row in enrollments.items()
        if _course_status(row.get("status")) in {"completed", "passed"}
    }
    current = {
        course_id
        for course_id, row in enrollments.items()
        if _course_status(row.get("status")) in {"current", "in progress", "in_progress"}
    }
    remaining_ids = [
        str(course["course_id"])
        for course in courses
        if str(course["course_id"]) not in completed | current
    ]

    def decorated(course_id: str, achieved: set[str]) -> dict[str, Any]:
        course = by_id[course_id]
        requirement_rows = []
        missing = False
        conditional = False
        for requirement_id in prerequisites.get(course_id, []):
            requirement = by_id.get(requirement_id, {})
            if requirement_id in completed or requirement_id in achieved - current:
                status = "completed"
            elif requirement_id in current:
                status = "in_progress"
                conditional = True
            else:
                status = "missing"
                missing = True
            requirement_rows.append(
                {
                    "course_id": requirement_id,
                    "course_code": requirement.get("course_code", requirement_id),
                    "course_name": requirement.get("course_name", "Prerequisite course"),
                    "status": status,
                }
            )
        eligibility = "blocked" if missing else "conditional" if conditional else "eligible"
        return {
            "course_id": course_id,
            "course_code": course.get("course_code") or course_id,
            "course_name": course.get("course_name") or "Course",
            "curriculum_semester": course.get("curriculum_semester"),
            "course_type": course.get("course_type") or "Required",
            "credit_hours": DEFAULT_COURSE_CREDITS,
            "credits_estimated": True,
            "eligibility": eligibility,
            "eligible": not missing,
            "prerequisites": requirement_rows,
            "schedule": schedules.get(course_id, []),
        }

    # Build the fastest prerequisite-valid sequence under the selected load.
    capacity = max(1, max_credits // DEFAULT_COURSE_CREDITS)
    achieved = set(completed | current)
    unscheduled = set(remaining_ids)
    path: list[dict[str, Any]] = []
    next_semester = int(student.get("current_semester") or 0) + 1
    while unscheduled:
        available = [
            course_id
            for course_id in unscheduled
            if set(prerequisites.get(course_id, [])) <= achieved
        ]
        if not available:
            break
        available.sort(
            key=lambda course_id: (
                int(by_id[course_id].get("curriculum_semester") or 999),
                -sum(course_id in reqs for reqs in prerequisites.values()),
                str(by_id[course_id].get("course_code") or course_id),
            )
        )
        term_ids = available[:capacity]
        term_courses = [decorated(course_id, achieved) for course_id in term_ids]
        path.append(
            {
                "semester_number": next_semester + len(path),
                "credit_hours": len(term_courses) * DEFAULT_COURSE_CREDITS,
                "courses": term_courses,
            }
        )
        achieved.update(term_ids)
        unscheduled.difference_update(term_ids)

    recommended = path[0]["courses"] if path else []
    all_candidates = [decorated(course_id, completed | current) for course_id in remaining_ids]
    all_candidates.sort(
        key=lambda course: (
            {"eligible": 0, "conditional": 1, "blocked": 2}[course["eligibility"]],
            int(course.get("curriculum_semester") or 999),
            str(course["course_code"]),
        )
    )
    selected_credits = sum(int(course["credit_hours"]) for course in recommended)
    completed_credits = len(completed) * DEFAULT_COURSE_CREDITS
    current_gpa = float(student.get("gpa") or 0)
    projected_gpa = (
        (current_gpa * completed_credits + expected_term_gpa * selected_credits)
        / (completed_credits + selected_credits)
        if completed_credits + selected_credits
        else expected_term_gpa
    )
    schedule_available = bool(source.get("schedule_data_available"))
    conflicts = _find_conflicts(recommended) if schedule_available else []
    remaining_credits = len(remaining_ids) * DEFAULT_COURSE_CREDITS

    return {
        "student_id": str(student["student_id"]),
        "current_semester": int(student.get("current_semester") or 0),
        "next_semester": next_semester,
        "current_gpa": round(current_gpa, 2),
        "recommended_courses": recommended,
        "candidate_courses": all_candidates,
        "total_credit_hours": selected_credits,
        "maximum_credit_hours": max_credits,
        "credit_policy": {
            "default_course_credits": DEFAULT_COURSE_CREDITS,
            "estimated": True,
            "note": "Credit hours are estimated at 3 per course because the source database has no credit-hours column.",
        },
        "conflict_check": {
            "status": "checked" if schedule_available else "unavailable",
            "conflicts": conflicts,
            "note": (
                "Conflicts are calculated from database timetable slots."
                if schedule_available
                else "Timetable slots are not available in the source database yet; no conflict-free claim is made."
            ),
        },
        "gpa_projection": {
            "current_gpa": round(current_gpa, 2),
            "expected_term_gpa": round(expected_term_gpa, 2),
            "projected_cumulative_gpa": round(projected_gpa, 2),
            "completed_credit_hours": completed_credits,
            "planned_credit_hours": selected_credits,
            "estimated": True,
        },
        "graduation_path": {
            "completed_courses": len(completed),
            "in_progress_courses": len(current),
            "remaining_courses": len(remaining_ids),
            "remaining_credit_hours": remaining_credits,
            "minimum_semesters_after_current": len(path),
            "planned_semesters": path,
            "unscheduled_course_ids": sorted(unscheduled),
            "note": "Fastest prerequisite-valid path assumes current courses are passed and all curriculum courses are offered when planned.",
        },
    }
