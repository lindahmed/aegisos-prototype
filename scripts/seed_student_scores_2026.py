"""Seed Fall 2026 scoring activity for the 23100 student cohort.

Run without --apply to preview. Repeating --apply does not overwrite existing
gradebook results or duplicate lecture completions.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import date
from pathlib import Path

import psycopg2
from dotenv import dotenv_values
from psycopg2.extras import RealDictCursor, execute_values

from database.academic_calendar import academic_week


ROOT = Path(__file__).resolve().parents[1]
SEMESTER = "Fall 2026"
SOURCE = "demo_2026_week8"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write the previewed records")
    args = parser.parse_args()
    config = dotenv_values(ROOT / ".env")
    database_url = config.get("DATABASE_URL")
    if not database_url:
        raise SystemExit("DATABASE_URL is not configured")
    current_week = academic_week(date.fromisoformat(config.get("AEGIS_SEMESTER_START_DATE") or "2026-08-08"))
    if not 7 <= current_week < 12:
        raise SystemExit(f"Expected a week from 7 to 11; found week {current_week}")

    with psycopg2.connect(database_url, connect_timeout=10) as connection:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                """SELECT enrollment.student_id::text AS student_id, enrollment.course_code,
                          course.course_title
                   FROM student_courses enrollment
                   JOIN courses course ON course.course_code = enrollment.course_code
                   WHERE enrollment.student_id::text LIKE '23100%'
                     AND length(enrollment.student_id::text) = 9
                     AND enrollment.status = 'Current'
                   ORDER BY enrollment.student_id, course.course_title"""
            )
            courses_by_student: dict[str, list[str]] = defaultdict(list)
            for row in cursor.fetchall():
                if not row["course_title"].casefold().startswith("project"):
                    courses_by_student[row["student_id"]].append(row["course_code"])
            cursor.execute(
                "SELECT student_id::text AS student_id FROM students WHERE student_id::text LIKE '23100%' AND length(student_id::text) = 9 ORDER BY student_id"
            )
            student_ids = [row["student_id"] for row in cursor.fetchall()]
            missing = [student_id for student_id in student_ids if not courses_by_student[student_id]]
            if missing:
                raise SystemExit(f"{len(missing)} students have no current non-project course")

            lecture_rows = []
            grade_rows = []
            lecture_students = exam_students = 0
            for student_id in student_ids:
                suffix = int(student_id[-3:])
                courses = courses_by_student[student_id]
                if int(student_id[-1]) % 2 == 0:
                    lecture_students += 1
                    for number in range(1, 3 + suffix % 5):
                        lecture_rows.append((student_id, courses[0], SEMESTER, number, number, SOURCE))
                else:
                    exam_students += 1
                    for index, course_id in enumerate(courses[:1 + suffix % 2]):
                        week7_mark = 23.0 + (suffix + index) % 7
                        coursework_mark = 7.0 + 0.5 * ((suffix + index) % 6)
                        grade_rows.append((
                            student_id, course_id, SEMESTER,
                            coursework_mark * 10, week7_mark * (100 / 30),
                            coursework_mark, week7_mark,
                        ))

            print({"cohort_students": len(student_ids), "lecture_students": lecture_students,
                   "exam_students": exam_students, "planned_lecture_completions": len(lecture_rows),
                   "planned_exam_and_assignment_rows": len(grade_rows), "week": current_week,
                   "apply": args.apply})
            if not args.apply:
                connection.rollback()
                return

            cursor.execute(
                """CREATE TABLE IF NOT EXISTS student_score_lectures (
                     student_id TEXT NOT NULL, course_id TEXT NOT NULL, semester TEXT NOT NULL,
                     lecture_number INTEGER NOT NULL CHECK(lecture_number >= 1),
                     completed_week INTEGER NOT NULL CHECK(completed_week >= 1),
                     source TEXT NOT NULL DEFAULT 'verified',
                     PRIMARY KEY (student_id, course_id, semester, lecture_number)
                   )"""
            )
            execute_values(
                cursor,
                """INSERT INTO student_score_lectures
                     (student_id, course_id, semester, lecture_number, completed_week, source)
                   VALUES %s ON CONFLICT DO NOTHING""",
                lecture_rows,
            )
            execute_values(
                cursor,
                """INSERT INTO course_gradebook_entries
                     (student_id, course_id, semester, assignment_score, midterm_score,
                      coursework_mark, week7_exam_mark, week12_exam_mark, final_exam_mark)
                   VALUES %s ON CONFLICT DO NOTHING""",
                [(*row, None, None) for row in grade_rows],
            )
            cursor.execute(
                """WITH lecture_students AS (
                     SELECT DISTINCT student_id FROM student_score_lectures
                     WHERE semester = %s AND source = %s AND completed_week <= %s
                   ), exam_students AS (
                     SELECT DISTINCT student_id FROM course_gradebook_entries
                     WHERE semester = %s AND week7_exam_mark >= 21
                   )
                   SELECT COUNT(*) AS students_with_points FROM students s
                   WHERE s.student_id::text LIKE '23100%%' AND length(s.student_id::text) = 9
                     AND (EXISTS (SELECT 1 FROM lecture_students l WHERE l.student_id = s.student_id::text)
                          OR EXISTS (SELECT 1 FROM exam_students e WHERE e.student_id = s.student_id::text))""",
                (SEMESTER, SOURCE, current_week, SEMESTER),
            )
            scored_students = cursor.fetchone()["students_with_points"]
            if scored_students != len(student_ids):
                raise RuntimeError(f"Only {scored_students} of {len(student_ids)} students have points; rolling back")
            print({"students_with_points": scored_students, "committing": True})


if __name__ == "__main__":
    main()
