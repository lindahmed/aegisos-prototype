"""Reconnect preserved STU001-STU008 gradebook rows after the course-code migration.

The original prototype gradebook stored numeric course IDs as text. The normalized
curriculum now uses course codes, which left those unchanged marks disconnected from
their enrollments. This migration changes only the identifier and inserts a current
enrollment when the preserved gradebook proves that one existed.

Run without ``--apply`` for a read-only preview.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from dotenv import load_dotenv
import psycopg2
import psycopg2.extras


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SAMPLE_STUDENT_IDS = tuple(f"STU{number:03d}" for number in range(1, 9))
LEGACY_COURSE_CODES = {
    "13": "CCS2102",  # Digital Logic Design
    "14": "CCS2103",  # Introduction to Computer Architecture
    "17": "CCS2304",  # Advanced Programming Applications
}


def repair(*, apply: bool) -> dict[str, int]:
    load_dotenv(PROJECT_ROOT / ".env", override=False)
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is not configured.")

    with psycopg2.connect(database_url) as connection:
        with connection.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cursor:
            cursor.execute(
                """SELECT student_id, course_id, semester,
                          coursework_mark, week7_exam_mark,
                          week12_exam_mark, final_exam_mark
                   FROM course_gradebook_entries
                   WHERE student_id = ANY(%s) AND course_id = ANY(%s)
                   ORDER BY student_id, course_id""",
                (list(SAMPLE_STUDENT_IDS), list(LEGACY_COURSE_CODES)),
            )
            preserved_rows = cursor.fetchall()
            if not apply:
                connection.rollback()
                return {
                    "preserved_grade_rows": len(preserved_rows),
                    "grade_rows_relinked": 0,
                    "enrollments_inserted": 0,
                }

            relinked = 0
            for legacy_id, course_code in LEGACY_COURSE_CODES.items():
                cursor.execute(
                    """UPDATE course_gradebook_entries
                       SET course_id = %s
                       WHERE student_id = ANY(%s) AND course_id = %s""",
                    (course_code, list(SAMPLE_STUDENT_IDS), legacy_id),
                )
                relinked += cursor.rowcount

            cursor.execute(
                "SELECT id FROM semesters WHERE is_current IS TRUE ORDER BY start_date DESC LIMIT 1"
            )
            semester = cursor.fetchone()
            if semester is None:
                raise RuntimeError("The database has no current semester.")

            cursor.execute(
                """INSERT INTO student_courses
                       (student_id, course_code, semester_id, status, grade)
                   SELECT gradebook.student_id, gradebook.course_id, %s, 'Current', NULL
                   FROM course_gradebook_entries gradebook
                   JOIN courses course ON course.course_code = gradebook.course_id
                   WHERE gradebook.student_id = ANY(%s)
                   ON CONFLICT (student_id, course_code, semester_id) DO NOTHING""",
                (semester["id"], list(SAMPLE_STUDENT_IDS)),
            )
            inserted = cursor.rowcount
        connection.commit()
    return {
        "preserved_grade_rows": len(preserved_rows),
        "grade_rows_relinked": relinked,
        "enrollments_inserted": inserted,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="commit the identifier and enrollment repair",
    )
    arguments = parser.parse_args()
    print(repair(apply=arguments.apply))
