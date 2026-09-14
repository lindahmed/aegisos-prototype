#!/usr/bin/env python3
"""Create the student_semester_grades table in PostgreSQL.

Run this against an existing PostgreSQL/Supabase database to add the table
without dropping any existing data.  The app will also create the table
automatically on startup, but this script is useful for managed databases
where the app user has limited DDL permissions.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))


def migrate() -> None:
    try:
        import psycopg2
    except ImportError as error:
        raise RuntimeError("psycopg2-binary is required. Install backend requirements.") from error

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL environment variable is not set.")

    connection = psycopg2.connect(database_url)
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS student_semester_grades (
                    grade_id BIGSERIAL PRIMARY KEY,
                    student_id TEXT NOT NULL,
                    course_id TEXT NOT NULL,
                    semester TEXT NOT NULL,
                    week_number INTEGER NOT NULL CHECK(week_number BETWEEN 1 AND 16),
                    assignment_grade DOUBLE PRECISION CHECK(assignment_grade BETWEEN 0 AND 100),
                    lab_grade DOUBLE PRECISION CHECK(lab_grade BETWEEN 0 AND 100),
                    exam_grade DOUBLE PRECISION CHECK(exam_grade BETWEEN 0 AND 100),
                    exam_weight DOUBLE PRECISION CHECK(exam_weight IN (30, 20, 40)),
                    coursework_grade DOUBLE PRECISION CHECK(coursework_grade BETWEEN 0 AND 100),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    UNIQUE(student_id, course_id, semester, week_number)
                );
                """
            )
        connection.commit()
        print("student_semester_grades table created (or already exists).")
    finally:
        connection.close()


if __name__ == "__main__":
    migrate()
