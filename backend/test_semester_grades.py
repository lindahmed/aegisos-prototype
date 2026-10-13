from pathlib import Path

from database.repository import StudentRepository


def make_repository(tmp_path: Path) -> StudentRepository:
    repository = StudentRepository(tmp_path / "aegisos.db")
    repository.initialize()
    return repository


def test_save_and_retrieve_weekly_grades(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    repository.save_semester_grade(
        "231027905", "ai", "Fall 2026", 3,
        assignment_grade=85.0, lab_grade=78.0,
    )
    grades = repository.get_semester_grades("231027905", "ai", "Fall 2026")
    assert len(grades) == 1
    assert grades[0]["week_number"] == 3
    assert grades[0]["assignment_grade"] == 85.0
    assert grades[0]["lab_grade"] == 78.0


def test_exam_grades_with_weights(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    repository.save_semester_grade("231027905", "ai", "Fall 2026", 7, exam_grade=80.0, exam_weight=30.0)
    repository.save_semester_grade("231027905", "ai", "Fall 2026", 12, exam_grade=75.0, exam_weight=20.0)
    repository.save_semester_grade(
        "231027905", "ai", "Fall 2026", 16,
        exam_grade=90.0, exam_weight=40.0, coursework_grade=88.0,
    )

    summary = repository.get_semester_grade_summary("231027905", "ai", "Fall 2026")
    assert summary is not None
    assert summary["exam_contribution"] == round(80.0 * 0.3 + 75.0 * 0.2 + 90.0 * 0.4, 2)
    assert summary["coursework_contribution"] == round(88.0 * 0.1, 2)
    assert summary["current_total"] == round(summary["exam_contribution"] + summary["coursework_contribution"], 2)
    assert summary["remaining"] == round(100.0 - summary["current_total"], 2)


def test_grade_upsert_updates_existing_week(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    repository.save_semester_grade("231027905", "ai", "Fall 2026", 1, assignment_grade=70.0)
    repository.save_semester_grade("231027905", "ai", "Fall 2026", 1, assignment_grade=90.0)
    grades = repository.get_semester_grades("231027905", "ai", "Fall 2026")
    assert len(grades) == 1
    assert grades[0]["assignment_grade"] == 90.0


def test_semester_grade_summary_returns_none_when_empty(tmp_path: Path) -> None:
    repository = make_repository(tmp_path)
    summary = repository.get_semester_grade_summary("231027905", "ai", "Fall 2026")
    assert summary is None
