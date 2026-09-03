from backend.planner.service import build_semester_plan


def _source() -> dict:
    return {
        "student": {"student_id": "STU001", "current_semester": 3, "gpa": 3.55},
        "courses": [
            {"course_id": "1", "course_code": "CS101", "course_name": "Intro", "curriculum_semester": 1},
            {"course_id": "2", "course_code": "CS201", "course_name": "Data Structures", "curriculum_semester": 4},
            {"course_id": "3", "course_code": "CS202", "course_name": "Algorithms", "curriculum_semester": 5},
            {"course_id": "4", "course_code": "CS210", "course_name": "Networks", "curriculum_semester": 4},
        ],
        "enrollments": [
            {"course_id": "1", "status": "Completed"},
            {"course_id": "2", "status": "Current"},
        ],
        "prerequisites": [
            {"course_id": "2", "prerequisite_course_id": "1"},
            {"course_id": "3", "prerequisite_course_id": "2"},
        ],
        "schedules": [
            {"course_id": "3", "day_of_week": "Sunday", "start_minute": 600, "end_minute": 660},
            {"course_id": "4", "day_of_week": "Sunday", "start_minute": 630, "end_minute": 690},
        ],
        "schedule_data_available": True,
    }


def test_planner_checks_prerequisites_conflicts_credits_and_gpa() -> None:
    plan = build_semester_plan(_source(), max_credits=18, expected_term_gpa=4.0)

    assert [course["course_code"] for course in plan["recommended_courses"]] == ["CS210", "CS202"]
    algorithms = next(course for course in plan["recommended_courses"] if course["course_code"] == "CS202")
    assert algorithms["eligibility"] == "conditional"
    assert algorithms["prerequisites"][0]["status"] == "in_progress"
    assert plan["total_credit_hours"] == 6
    assert len(plan["conflict_check"]["conflicts"]) == 1
    assert plan["gpa_projection"]["projected_cumulative_gpa"] == 3.85
    assert plan["graduation_path"]["minimum_semesters_after_current"] == 1


def test_planner_does_not_claim_conflict_free_without_schedule_data() -> None:
    source = _source()
    source["schedules"] = []
    source["schedule_data_available"] = False

    plan = build_semester_plan(source)

    assert plan["conflict_check"]["status"] == "unavailable"
    assert "no conflict-free claim" in plan["conflict_check"]["note"]
