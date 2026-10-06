from __future__ import annotations

from typing import Any, Callable


DEFAULT_COURSE_CREDITS = 3
MAX_PROGRAM_SEMESTERS = 8


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


def _build_graduation_route(
    *,
    route_id: str,
    title: str,
    remaining_ids: list[str],
    completed: set[str],
    current: set[str],
    current_semester: int,
    regular_credit_limit: int,
    summer_credit_limit: int,
    summer_after_semester: int | None,
    summer_label: str | None,
    prerequisites: dict[str, list[str]],
    by_id: dict[str, dict[str, Any]],
    decorate: Callable[[str, set[str]], dict[str, Any]],
) -> dict[str, Any]:
    """Build a complete route, using clearly labelled extension terms if needed."""
    achieved = set(completed | current)
    unscheduled = set(remaining_ids)
    terms: list[dict[str, Any]] = []
    regular_semester = current_semester + 1
    last_regular_semester = current_semester
    regular_capacity = max(1, regular_credit_limit // DEFAULT_COURSE_CREDITS)
    summer_capacity = max(0, summer_credit_limit // DEFAULT_COURSE_CREDITS)
    summer_used = False

    def available_ids(capacity: int) -> list[str]:
        available = [
            course_id
            for course_id in unscheduled
            if set(prerequisites.get(course_id, [])) <= achieved
        ]
        available.sort(
            key=lambda course_id: (
                int(by_id[course_id].get("curriculum_semester") or 999),
                -sum(course_id in reqs for reqs in prerequisites.values()),
                str(by_id[course_id].get("course_code") or course_id),
            )
        )
        return available[:capacity]

    def add_term(
        course_ids: list[str],
        *,
        term_type: str,
        label: str,
        semester_number: int | None,
    ) -> None:
        term_courses = [decorate(course_id, achieved) for course_id in course_ids]
        terms.append(
            {
                "sequence": len(terms) + 1,
                "label": label,
                "term_type": term_type,
                "semester_number": semester_number,
                "credit_hours": len(term_courses) * DEFAULT_COURSE_CREDITS,
                "courses": term_courses,
            }
        )
        achieved.update(course_ids)
        unscheduled.difference_update(course_ids)

    # A generous guard supports delayed/half-load students without ever
    # creating an unbounded route when curriculum prerequisites contain a cycle.
    for _ in range(32):
        if not unscheduled:
            break
        made_progress = False
        if (
            summer_capacity
            and not summer_used
            and last_regular_semester == summer_after_semester
        ):
            summer_ids = available_ids(summer_capacity)
            summer_used = True
            if summer_ids:
                add_term(
                    summer_ids,
                    term_type="summer",
                    label=summer_label or f"Summer after semester {last_regular_semester}",
                    semester_number=last_regular_semester,
                )
                made_progress = True
        if not unscheduled:
            break

        regular_ids = available_ids(regular_capacity)
        if regular_ids:
            if regular_semester <= MAX_PROGRAM_SEMESTERS:
                term_type = "regular"
                label = f"Semester {regular_semester}"
                semester_number: int | None = regular_semester
            else:
                term_type = "extension"
                extension_number = regular_semester - MAX_PROGRAM_SEMESTERS
                label = f"Extension term {extension_number}"
                semester_number = None
            add_term(
                regular_ids,
                term_type=term_type,
                label=label,
                semester_number=semester_number,
            )
            last_regular_semester = regular_semester
            regular_semester += 1
            made_progress = True
        if not made_progress:
            break

    regular_terms = [term for term in terms if term["term_type"] != "summer"]
    summer_terms = [term for term in terms if term["term_type"] == "summer"]
    extension_terms = [term for term in terms if term["term_type"] == "extension"]
    standard_semesters = [
        int(term["semester_number"])
        for term in regular_terms
        if term["semester_number"] is not None
    ]
    return {
        "id": route_id,
        "title": title,
        "available": True,
        "maximum_regular_credits": regular_credit_limit,
        "summer_credits": summer_credit_limit,
        "summer_after_semester": summer_after_semester,
        "regular_semesters": len(regular_terms),
        "summer_terms": len(summer_terms),
        "extension_terms": len(extension_terms),
        "total_terms": len(terms),
        "finishes_by_semester": max(standard_semesters, default=current_semester),
        "on_time": not extension_terms,
        "completion_status": "complete" if not unscheduled else "blocked",
        "unscheduled_course_ids": sorted(unscheduled),
        "terms": terms,
    }


def _unavailable_route(route_id: str, title: str, note: str) -> dict[str, Any]:
    return {
        "id": route_id,
        "title": title,
        "available": False,
        "maximum_regular_credits": None,
        "summer_credits": 0,
        "summer_after_semester": None,
        "regular_semesters": 0,
        "summer_terms": 0,
        "extension_terms": 0,
        "total_terms": 0,
        "finishes_by_semester": None,
        "on_time": False,
        "completion_status": "unavailable",
        "unscheduled_course_ids": [],
        "saves_regular_semesters": 0,
        "note": note,
        "terms": [],
    }


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
    recorded_completed = {
        course_id
        for course_id, row in enrollments.items()
        if _course_status(row.get("status")) in {"completed", "passed"}
    }
    current = {
        course_id
        for course_id, row in enrollments.items()
        if _course_status(row.get("status")) in {"current", "in progress", "in_progress"}
    }
    current_semester = min(
        MAX_PROGRAM_SEMESTERS,
        max(1, int(student.get("current_semester") or 1)),
    )
    # The normalized database can contain a partial transcript after an SIS
    # import. Do not send an upper-year student back through first-year courses:
    # unrecorded courses assigned to an earlier curriculum semester are treated
    # as satisfied for planning, while explicit failed/incomplete rows remain.
    inferred_completed = {
        str(course["course_id"])
        for course in courses
        if str(course["course_id"]) not in enrollments
        and int(course.get("curriculum_semester") or MAX_PROGRAM_SEMESTERS + 1)
        < current_semester
    }
    completed = recorded_completed | inferred_completed
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

    next_semester = min(current_semester + 1, MAX_PROGRAM_SEMESTERS)
    available_program_terms = max(0, MAX_PROGRAM_SEMESTERS - current_semester)
    current_gpa = float(student.get("gpa") or 0)
    half_load = current_gpa < 2.0
    effective_max_credits = min(max_credits, 9) if half_load else max_credits

    normal_route = _build_graduation_route(
        route_id="normal",
        title="Normal route" if not half_load else "Half-load route",
        remaining_ids=remaining_ids,
        completed=completed,
        current=current,
        current_semester=current_semester,
        regular_credit_limit=effective_max_credits,
        summer_credit_limit=0,
        summer_after_semester=None,
        summer_label=None,
        prerequisites=prerequisites,
        by_id=by_id,
        decorate=decorated,
    )
    normal_regular_semesters = int(normal_route["regular_semesters"])
    normal_route["saves_regular_semesters"] = 0
    normal_route["note"] = (
        "Because your GPA is below 2.0, this route uses a maximum half-load of 9 credits per regular term. "
        "Extension terms are shown when the remaining courses cannot fit by semester 8."
        if half_load
        else "Uses up to 18 credits in regular semesters and does not assume summer study or overload approval."
    )

    if half_load:
        workload_route = _unavailable_route(
            "increased_workload",
            "Increase regular workload",
            "Unavailable while GPA is below 2.0. Half-load students must follow the reduced-load route.",
        )
        summer_routes = []
        for number, after_semester in enumerate((2, 4, 6, 8), start=1):
            timing = (
                f"between Semester {after_semester} and Semester {after_semester + 1}"
                if after_semester < MAX_PROGRAM_SEMESTERS
                else "after Semester 8"
            )
            summer_route = _unavailable_route(
                f"summer_{number}",
                f"Summer {number}",
                f"Summer {number} is {timing}, but summer acceleration is unavailable while GPA is below 2.0.",
            )
            summer_route["summer_after_semester"] = after_semester
            summer_routes.append(summer_route)
        best_option_id = "normal"
        fastest_option_id = None
    else:
        workload_route = _build_graduation_route(
            route_id="increased_workload",
            title="Increase regular workload",
            remaining_ids=remaining_ids,
            completed=completed,
            current=current,
            current_semester=current_semester,
            regular_credit_limit=24,
            summer_credit_limit=0,
            summer_after_semester=None,
            summer_label=None,
            prerequisites=prerequisites,
            by_id=by_id,
            decorate=decorated,
        )
        workload_route["saves_regular_semesters"] = max(
            0,
            normal_regular_semesters - int(workload_route["regular_semesters"]),
        )
        workload_route["note"] = (
            "Uses up to 24 credits in a regular semester, subject to advisor approval and timetable availability."
            if workload_route["saves_regular_semesters"]
            else "The higher credit ceiling does not shorten this route because prerequisite order is the limiting factor."
        )
        summer_routes = []
        for number, after_semester in enumerate((2, 4, 6, 8), start=1):
            timing = (
                f"between Semester {after_semester} and Semester {after_semester + 1}"
                if after_semester < MAX_PROGRAM_SEMESTERS
                else "after Semester 8"
            )
            if current_semester > after_semester:
                summer_route = _unavailable_route(
                    f"summer_{number}",
                    f"Summer {number}",
                    f"Summer {number} is {timing} and has already passed for this student.",
                )
                summer_route["summer_after_semester"] = after_semester
            else:
                summer_route = _build_graduation_route(
                    route_id=f"summer_{number}",
                    title=f"Summer {number}",
                    remaining_ids=remaining_ids,
                    completed=completed,
                    current=current,
                    current_semester=current_semester,
                    regular_credit_limit=18,
                    summer_credit_limit=6,
                    summer_after_semester=after_semester,
                    summer_label=f"Summer {number}",
                    prerequisites=prerequisites,
                    by_id=by_id,
                    decorate=decorated,
                )
                summer_route["saves_regular_semesters"] = max(
                    0,
                    normal_regular_semesters
                    - int(summer_route["regular_semesters"]),
                )
                summer_route["note"] = (
                    f"Summer {number} is {timing} and allows up to 6 credits."
                    if summer_route["summer_terms"]
                    else f"Summer {number} is {timing}, but no remaining prerequisite-valid course is available for it in this route."
                )
            summer_routes.append(summer_route)
        faster_routes = [
            route
            for route in (workload_route, *summer_routes)
            if route["completion_status"] == "complete"
            and int(route["saves_regular_semesters"]) > 0
        ]
        fastest_option_id = (
            min(
                faster_routes,
                key=lambda route: (
                    int(route["regular_semesters"]),
                    int(route["total_terms"]),
                ),
            )["id"]
            if faster_routes
            else None
        )
        best_option_id = fastest_option_id or "normal"

    # Preserve the original capped regular-semester path for older clients.
    path = [
        term
        for term in normal_route["terms"]
        if term["term_type"] == "regular"
        and term["semester_number"] is not None
        and int(term["semester_number"]) <= MAX_PROGRAM_SEMESTERS
    ]
    scheduled_standard_ids = {
        str(course["course_id"])
        for term in path
        for course in term["courses"]
    }
    unscheduled = set(remaining_ids) - scheduled_standard_ids
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
    projected_gpa = (
        (current_gpa * completed_credits + expected_term_gpa * selected_credits)
        / (completed_credits + selected_credits)
        if completed_credits + selected_credits
        else expected_term_gpa
    )
    schedule_available = bool(source.get("schedule_data_available"))
    conflicts = _find_conflicts(recommended) if schedule_available else []
    remaining_credits = len(remaining_ids) * DEFAULT_COURSE_CREDITS

    standard_path_complete = not unscheduled
    return {
        "student_id": str(student["student_id"]),
        "current_semester": current_semester,
        "next_semester": next_semester,
        "maximum_program_semesters": MAX_PROGRAM_SEMESTERS,
        "program_semesters_remaining": available_program_terms,
        "current_gpa": round(current_gpa, 2),
        "recommended_courses": recommended,
        "candidate_courses": all_candidates,
        "total_credit_hours": selected_credits,
        "maximum_credit_hours": effective_max_credits,
        "credit_policy": {
            "default_course_credits": DEFAULT_COURSE_CREDITS,
            "estimated": True,
            "note": (
                "Half-load is active because GPA is below 2.0: the student may select up to 9 credits, usually three 3-credit courses."
                if half_load
                else "Credit hours are estimated at 3 per course because the planner source has no per-course credit values."
            ),
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
            "recorded_completed_courses": len(recorded_completed),
            "inferred_completed_courses": len(inferred_completed),
            "in_progress_courses": len(current),
            "remaining_courses": len(remaining_ids),
            "remaining_credit_hours": remaining_credits,
            "minimum_semesters_after_current": len(path),
            "planned_semesters": path,
            "unscheduled_course_ids": sorted(unscheduled),
            "fits_standard_program_length": standard_path_complete,
            "note": (
                "This is the normal prerequisite-valid route through semester 8. "
                "Use the separate workload and summer options to compare genuinely accelerated routes."
                if standard_path_complete
                else "The normal route does not finish by semester 8. Extension terms are shown in the graduation options."
            ),
        },
        "graduation_options": {
            "half_load": half_load,
            "accelerated_allowed": not half_load,
            "student_status": (
                "half_load"
                if half_load
                else "on_track"
                if normal_route["on_time"]
                else "late"
            ),
            "fastest_option_id": fastest_option_id,
            "best_option_id": best_option_id,
            "policy_note": (
                "GPA below 2.0 requires a half load. Fast-track options are disabled; the student may need extension terms beyond semester 8."
                if half_load
                else "Compare the normal route, a 24-credit workload, and Summer 1-4. Each summer allows up to 6 credits and requires university approval and course availability."
            ),
            "options": [normal_route, workload_route, *summer_routes],
        },
    }
