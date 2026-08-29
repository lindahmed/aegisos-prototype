"""PostgreSQL/Supabase repository for the normalized Database-branch schema.

The source schema supplies student identity, programmes, course catalogues, and
current enrollments.  It currently does not include assessment, lecture, or
material records, so progress responses remain explicitly data-limited until
those portal tables are added to the same database.
"""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from typing import Any

try:
    import psycopg2
    import psycopg2.extras
except ImportError:  # permits SQLite-only development and test runs
    psycopg2 = None

from .repository import Student


GRADE_POINTS: dict[str, float] = {
    "A+": 4.0, "A": 4.0, "A-": 3.7,
    "B+": 3.3, "B": 3.0, "B-": 2.7,
    "C+": 2.3, "C": 2.0, "C-": 1.7,
    "D+": 1.3, "D": 1.0, "D-": 0.7, "F": 0.0,
}


class PostgresStudentRepository:
    """Repository implementation for the Database branch's PostgreSQL schema."""

    def __init__(self, dsn: str) -> None:
        self.dsn = dsn
        self.semester = os.getenv("AEGIS_CURRENT_SEMESTER", "Current semester")
        try:
            self.current_week = max(1, int(os.getenv("AEGIS_CURRENT_WEEK", "1")))
        except ValueError as error:
            raise ValueError("AEGIS_CURRENT_WEEK must be a positive integer") from error

    def _connect(self):
        if psycopg2 is None:
            raise RuntimeError(
                "PostgreSQL support requires psycopg2-binary. Install backend requirements."
            )
        return psycopg2.connect(
            self.dsn, cursor_factory=psycopg2.extras.RealDictCursor
        )

    def initialize(self) -> None:
        """Create only progress-agent history tables; academic source tables are external."""
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    CREATE TABLE IF NOT EXISTS weekly_progress_snapshots (
                        snapshot_id BIGSERIAL PRIMARY KEY,
                        student_id TEXT NOT NULL,
                        course_id TEXT NOT NULL,
                        week_number INTEGER NOT NULL,
                        assignment_average DOUBLE PRECISION,
                        lab_average DOUBLE PRECISION,
                        quiz_average DOUBLE PRECISION,
                        exam_percentage DOUBLE PRECISION,
                        weighted_grade DOUBLE PRECISION,
                        lecture_completion DOUBLE PRECISION NOT NULL,
                        assessment_completion DOUBLE PRECISION NOT NULL,
                        course_health DOUBLE PRECISION NOT NULL,
                        risk_level TEXT NOT NULL,
                        trend TEXT NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL,
                        UNIQUE(student_id, course_id, week_number)
                    );
                    CREATE TABLE IF NOT EXISTS progress_interventions (
                        intervention_id BIGSERIAL PRIMARY KEY,
                        student_id TEXT NOT NULL,
                        course_id TEXT NOT NULL,
                        week_number INTEGER NOT NULL,
                        severity TEXT NOT NULL,
                        reason TEXT NOT NULL,
                        weak_topics_json JSONB NOT NULL,
                        lecture_ids_json JSONB NOT NULL,
                        recommended_actions_json JSONB NOT NULL,
                        message TEXT NOT NULL,
                        issue_fingerprint TEXT NOT NULL,
                        status TEXT NOT NULL DEFAULT 'active',
                        created_at TIMESTAMPTZ NOT NULL
                    );
                    """
                )

    def get_student(self, student_id: str) -> Student | None:
        normalized_id = student_id.strip()
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT s.student_id::text AS student_id, s.full_name,
                           s.academic_level, p.program_name
                    FROM students s
                    JOIN programs p ON p.program_id = s.program_id
                    WHERE s.student_id::text = %s
                    """,
                    (normalized_id,),
                )
                student_row = cursor.fetchone()
                if student_row is None:
                    return None
                cursor.execute(
                    """
                    SELECT sc.grade
                    FROM student_courses sc
                    WHERE sc.student_id::text = %s
                      AND sc.status = 'Completed' AND sc.grade IS NOT NULL
                    """,
                    (normalized_id,),
                )
                completed_rows = cursor.fetchall()
                cursor.execute(
                    """
                    SELECT c.course_title
                    FROM student_courses sc
                    JOIN courses c ON c.course_id = sc.course_id
                    WHERE sc.student_id::text = %s AND sc.status = 'Current'
                    ORDER BY c.course_title
                    """,
                    (normalized_id,),
                )
                current_rows = cursor.fetchall()
        return Student(
            student_id=student_row["student_id"],
            name=student_row["full_name"],
            major=student_row["program_name"],
            year=student_row["academic_level"],
            gpa=self._compute_gpa(completed_rows),
            courses=tuple(row["course_title"] for row in current_rows),
        )

    def get_registered_students(self) -> list[Student]:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT student_id::text AS student_id FROM students ORDER BY student_id")
                ids = [row["student_id"] for row in cursor.fetchall()]
        return [student for student_id in ids if (student := self.get_student(student_id))]

    def get_student_progress(self, student_id: str) -> dict[str, Any] | None:
        """Return only verified source records from the normalized schema.

        The current database branch does not expose progress-specific tables,
        so its courses deliberately have empty assessment/lecture/material lists.
        The Digital Twin reports unavailable health instead of using SQLite seeds.
        """
        student = self.get_student(student_id)
        if student is None:
            return None
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT c.course_id::text AS course_id, c.course_title AS course_name
                    FROM student_courses sc
                    JOIN courses c ON c.course_id = sc.course_id
                    WHERE sc.student_id::text = %s AND sc.status = 'Current'
                    ORDER BY c.course_title
                    """,
                    (student.student_id,),
                )
                course_rows = cursor.fetchall()
        return {
            "student": student.as_dict(),
            "courses": [
                {
                    "course_id": row["course_id"],
                    "course_name": row["course_name"],
                    "semester": self.semester,
                    "current_week": self.current_week,
                    "assessments": [],
                    "lectures": [],
                    "materials": [],
                }
                for row in course_rows
            ],
        }

    def get_previous_course_snapshot(self, student_id: str, course_id: str, week_number: int) -> dict[str, Any] | None:
        return self._fetch_one(
            """SELECT * FROM weekly_progress_snapshots
               WHERE student_id = %s AND course_id = %s AND week_number < %s
               ORDER BY week_number DESC LIMIT 1""",
            (student_id, course_id, week_number),
        )

    def get_weekly_snapshots(self, student_id: str) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT snapshot.*, course.course_title AS course_name
               FROM weekly_progress_snapshots snapshot
               LEFT JOIN courses course ON course.course_id::text = snapshot.course_id
               WHERE snapshot.student_id = %s
               ORDER BY snapshot.week_number, snapshot.course_id""",
            (student_id,),
        )

    def save_weekly_snapshot(self, student_id: str, course_id: str, week_number: int, metrics: dict[str, Any]) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO weekly_progress_snapshots
                       (student_id, course_id, week_number, assignment_average, lab_average, quiz_average,
                        exam_percentage, weighted_grade, lecture_completion, assessment_completion,
                        course_health, risk_level, trend, created_at)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                       ON CONFLICT (student_id, course_id, week_number) DO UPDATE SET
                         assignment_average=EXCLUDED.assignment_average, lab_average=EXCLUDED.lab_average,
                         quiz_average=EXCLUDED.quiz_average, exam_percentage=EXCLUDED.exam_percentage,
                         weighted_grade=EXCLUDED.weighted_grade, lecture_completion=EXCLUDED.lecture_completion,
                         assessment_completion=EXCLUDED.assessment_completion, course_health=EXCLUDED.course_health,
                         risk_level=EXCLUDED.risk_level, trend=EXCLUDED.trend, created_at=EXCLUDED.created_at""",
                    self._snapshot_values(student_id, course_id, week_number, metrics),
                )

    def has_active_intervention(self, student_id: str, course_id: str, fingerprint: str) -> bool:
        return self._fetch_one(
            """SELECT 1 AS present FROM progress_interventions
               WHERE student_id = %s AND course_id = %s AND issue_fingerprint = %s AND status = 'active'
               LIMIT 1""",
            (student_id, course_id, fingerprint),
        ) is not None

    def save_intervention(self, student_id: str, course_id: str, week_number: int, intervention: dict[str, Any], fingerprint: str) -> int:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO progress_interventions
                       (student_id, course_id, week_number, severity, reason, weak_topics_json, lecture_ids_json,
                        recommended_actions_json, message, issue_fingerprint, created_at)
                       VALUES (%s, %s, %s, %s, %s, %s::jsonb, %s::jsonb, %s::jsonb, %s, %s, %s)
                       RETURNING intervention_id""",
                    (
                        student_id, course_id, week_number, intervention["severity"], intervention["reason"],
                        json.dumps(intervention.get("weak_topics", [])), json.dumps(intervention.get("lectures_to_review", [])),
                        json.dumps(intervention.get("recommended_actions", [])), intervention["message"], fingerprint,
                        datetime.now(UTC),
                    ),
                )
                return int(cursor.fetchone()["intervention_id"])

    def get_interventions(self, student_id: str) -> list[dict[str, Any]]:
        records = self._fetch_all(
            "SELECT * FROM progress_interventions WHERE student_id = %s ORDER BY created_at DESC",
            (student_id,),
        )
        for record in records:
            record["weak_topics"] = self._json_value(record.pop("weak_topics_json"))
            record["lectures_to_review"] = self._json_value(record.pop("lecture_ids_json"))
            record["recommended_actions"] = self._json_value(record.pop("recommended_actions_json"))
        return records

    def _fetch_one(self, query: str, parameters: tuple[Any, ...]) -> dict[str, Any] | None:
        rows = self._fetch_all(query, parameters)
        return rows[0] if rows else None

    def _fetch_all(self, query: str, parameters: tuple[Any, ...]) -> list[dict[str, Any]]:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, parameters)
                return [dict(row) for row in cursor.fetchall()]

    @staticmethod
    def _snapshot_values(student_id: str, course_id: str, week_number: int, metrics: dict[str, Any]) -> tuple[Any, ...]:
        return (
            student_id, course_id, week_number, metrics.get("assignment_average"), metrics.get("lab_average"),
            metrics.get("quiz_average"), metrics.get("exam_percentage"), metrics.get("weighted_grade"),
            metrics["lecture_completion"], metrics["assessment_completion"], metrics["course_health"],
            metrics["risk_level"], metrics["trend"], datetime.now(UTC),
        )

    @staticmethod
    def _compute_gpa(completed_rows: list[dict[str, Any]]) -> float | None:
        points = [GRADE_POINTS[row["grade"]] for row in completed_rows if row["grade"] in GRADE_POINTS]
        return round(sum(points) / len(points), 2) if points else None

    @staticmethod
    def _json_value(value: Any) -> list[Any]:
        return json.loads(value) if isinstance(value, str) else value
