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


def test_year_four_plan_never_creates_a_semester_after_eight() -> None:
    source = _source()
    source["student"]["current_semester"] = 7
    source["courses"] = [
        {
            "course_id": str(number),
            "course_code": f"CS{number:03d}",
            "course_name": f"Course {number}",
            "curriculum_semester": semester,
        }
        for number, semester in enumerate([1, 2, 3, 4, 5, 6, 7, 7, 8, 8, 8, 8], start=1)
    ]
    source["enrollments"] = []
    source["prerequisites"] = []

    plan = build_semester_plan(source, max_credits=18)

    assert plan["current_semester"] == 7
    assert plan["maximum_program_semesters"] == 8
    assert plan["program_semesters_remaining"] == 1
    assert all(
        term["semester_number"] <= 8
        for term in plan["graduation_path"]["planned_semesters"]
    )
    assert plan["graduation_path"]["inferred_completed_courses"] == 6
    assert plan["graduation_path"]["minimum_semesters_after_current"] <= 1


def test_semester_eight_student_is_not_offered_semester_nine() -> None:
    source = _source()
    source["student"]["current_semester"] = 8
    source["enrollments"] = []

    plan = build_semester_plan(source)

    assert plan["next_semester"] == 8
    assert plan["program_semesters_remaining"] == 0
    assert plan["recommended_courses"] == []
    assert plan["graduation_path"]["planned_semesters"] == []


def test_accelerated_routes_are_real_alternatives_to_normal_route() -> None:
    source = {
        "student": {"student_id": "STU001", "current_semester": 2, "gpa": 3.2},
        "courses": [
            {
                "course_id": str(number),
                "course_code": f"CS{number:03d}",
                "course_name": f"Course {number}",
                "curriculum_semester": 3,
            }
            for number in range(1, 15)
        ],
        "enrollments": [],
        "prerequisites": [],
        "schedules": [],
        "schedule_data_available": False,
    }

    plan = build_semester_plan(source)
    options = {item["id"]: item for item in plan["graduation_options"]["options"]}

    assert plan["graduation_options"]["accelerated_allowed"] is True
    assert options["normal"]["regular_semesters"] == 3
    assert options["increased_workload"]["regular_semesters"] == 2
    assert options["increased_workload"]["saves_regular_semesters"] == 1
    assert set(options) == {
        "normal",
        "increased_workload",
        "summer_1",
        "summer_2",
        "summer_3",
        "summer_4",
    }
    assert options["summer_1"]["summer_after_semester"] == 2
    assert options["summer_1"]["summer_terms"] == 1
    assert options["summer_1"]["terms"][0]["label"] == "Summer 1"
    assert options["summer_1"]["terms"][1]["label"] == "Semester 3"
    assert options["summer_1"]["regular_semesters"] < options["normal"]["regular_semesters"]
    assert plan["graduation_options"]["best_option_id"] in {
        "increased_workload",
        "summer_1",
        "summer_2",
    }


def test_half_load_student_cannot_select_fast_graduation() -> None:
    source = {
        "student": {"student_id": "STU009", "current_semester": 6, "gpa": 1.8},
        "courses": [
            {
                "course_id": str(number),
                "course_code": f"CS{number:03d}",
                "course_name": f"Course {number}",
                "curriculum_semester": 7,
            }
            for number in range(1, 11)
        ],
        "enrollments": [],
        "prerequisites": [],
        "schedules": [],
        "schedule_data_available": False,
    }

    plan = build_semester_plan(source)
    graduation = plan["graduation_options"]
    options = {item["id"]: item for item in graduation["options"]}

    assert plan["maximum_credit_hours"] == 9
    assert plan["total_credit_hours"] <= 9
    assert "GPA is below 2.0" in plan["credit_policy"]["note"]
    assert graduation["half_load"] is True
    assert graduation["accelerated_allowed"] is False
    assert graduation["best_option_id"] == "normal"
    assert graduation["fastest_option_id"] is None
    assert options["normal"]["available"] is True
    assert options["normal"]["extension_terms"] > 0
    assert options["increased_workload"]["available"] is False
    assert all(options[f"summer_{number}"]["available"] is False for number in range(1, 5))


def test_summer_numbers_use_the_four_requested_degree_boundaries() -> None:
    source = {
        "student": {"student_id": "STU005", "current_semester": 5, "gpa": 3.4},
        "courses": [
            {
                "course_id": str(number),
                "course_code": f"CS{number:03d}",
                "course_name": f"Course {number}",
                "curriculum_semester": 6,
            }
            for number in range(1, 21)
        ],
        "enrollments": [],
        "prerequisites": [],
        "schedules": [],
        "schedule_data_available": False,
    }

    plan = build_semester_plan(source)
    options = {item["id"]: item for item in plan["graduation_options"]["options"]}

    assert options["summer_1"]["available"] is False
    assert options["summer_1"]["summer_after_semester"] == 2
    assert options["summer_2"]["available"] is False
    assert options["summer_2"]["summer_after_semester"] == 4
    assert options["summer_3"]["available"] is True
    assert options["summer_3"]["summer_after_semester"] == 6
    assert any(term["label"] == "Summer 3" for term in options["summer_3"]["terms"])
    assert options["summer_4"]["available"] is True
    assert options["summer_4"]["summer_after_semester"] == 8
    assert options["summer_4"]["terms"][-1]["label"] == "Summer 4"
