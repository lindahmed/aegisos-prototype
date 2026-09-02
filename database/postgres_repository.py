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
            self.current_week = max(1, int(os.getenv("AEGIS_CURRENT_WEEK", "5")))
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
                        course_health_at_creation DOUBLE PRECISION,
                        resolved_week INTEGER,
                        resolution_outcome TEXT CHECK(resolution_outcome IN ('improved', 'stable', 'worsened', 'no_data')),
                        follow_up_week INTEGER,
                        created_at TIMESTAMPTZ NOT NULL
                    );
                    DO $$
                    BEGIN
                        IF NOT EXISTS (
                            SELECT 1 FROM information_schema.columns
                            WHERE table_name = 'progress_interventions' AND column_name = 'course_health_at_creation'
                        ) THEN
                            ALTER TABLE progress_interventions ADD COLUMN course_health_at_creation DOUBLE PRECISION;
                        END IF;
                        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'progress_interventions' AND column_name = 'resolved_week') THEN
                            ALTER TABLE progress_interventions ADD COLUMN resolved_week INTEGER;
                        END IF;
                        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'progress_interventions' AND column_name = 'resolution_outcome') THEN
                            ALTER TABLE progress_interventions ADD COLUMN resolution_outcome TEXT;
                        END IF;
                        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'progress_interventions' AND column_name = 'follow_up_week') THEN
                            ALTER TABLE progress_interventions ADD COLUMN follow_up_week INTEGER;
                        END IF;
                    END $$;
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
                    CREATE TABLE IF NOT EXISTS course_gradebook_entries (
                        student_id TEXT NOT NULL,
                        course_id TEXT NOT NULL,
                        semester TEXT NOT NULL,
                        assignment_score DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK(assignment_score BETWEEN 0 AND 100),
                        midterm_score DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK(midterm_score BETWEEN 0 AND 100),
                        final_score DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK(final_score BETWEEN 0 AND 100),
                        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        PRIMARY KEY (student_id, course_id, semester)
                    );
                    CREATE TABLE IF NOT EXISTS portal_notification_reads (
                        student_id TEXT NOT NULL,
                        notification_id TEXT NOT NULL,
                        read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        PRIMARY KEY (student_id, notification_id)
                    );
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS coursework_mark DOUBLE PRECISION CHECK(coursework_mark BETWEEN 0 AND 10);
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS week7_exam_mark DOUBLE PRECISION CHECK(week7_exam_mark BETWEEN 0 AND 30);
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS week12_exam_mark DOUBLE PRECISION CHECK(week12_exam_mark BETWEEN 0 AND 20);
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS final_exam_mark DOUBLE PRECISION CHECK(final_exam_mark BETWEEN 0 AND 40);
                    UPDATE course_gradebook_entries SET coursework_mark=COALESCE(coursework_mark, assignment_score * 0.10), week7_exam_mark=COALESCE(week7_exam_mark, midterm_score * 0.30), week12_exam_mark=COALESCE(week12_exam_mark, 0), final_exam_mark=COALESCE(final_exam_mark, final_score * 0.40);
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

    def list_portal_courses(self) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT c.course_id::text AS course_id, c.course_title AS course_name,
                      %s AS semester, COUNT(sc.student_id) AS student_count
               FROM courses c
               JOIN student_courses sc ON sc.course_id = c.course_id
               WHERE sc.status = 'Current'
               GROUP BY c.course_id, c.course_title
               ORDER BY c.course_title""",
            (self.semester,),
        )

    def get_portal_course_gradebook(
        self, course_id: str, semester: str | None = None
    ) -> dict[str, Any] | None:
        selected_semester = semester or self.semester
        course = self._fetch_one(
            """SELECT c.course_id::text AS course_id, c.course_title AS course_name, %s AS semester
               FROM courses c
               WHERE c.course_id::text = %s""",
            (selected_semester, course_id),
        )
        if course is None:
            return None
        rows = self._fetch_all(
            """SELECT s.student_id::text AS student_id, s.full_name AS student_name,
                      COALESCE(g.coursework_mark, 0) AS coursework_mark,
                      COALESCE(g.week7_exam_mark, 0) AS week7_exam_mark,
                      COALESCE(g.week12_exam_mark, 0) AS week12_exam_mark,
                      COALESCE(g.final_exam_mark, 0) AS final_exam_mark
               FROM student_courses sc
               JOIN students s ON s.student_id = sc.student_id
               LEFT JOIN course_gradebook_entries g
                 ON g.student_id = s.student_id::text
                AND g.course_id = sc.course_id::text
                AND g.semester = %s
               WHERE sc.course_id::text = %s AND sc.status = 'Current'
               ORDER BY s.full_name""",
            (selected_semester, course_id),
        )
        return {**course, "rows": rows}

    def save_portal_course_gradebook(
        self, course_id: str, semester: str, rows: list[dict[str, Any]]
    ) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                psycopg2.extras.execute_batch(
                    cursor,
                    """INSERT INTO course_gradebook_entries
                       (student_id, course_id, semester, coursework_mark, week7_exam_mark, week12_exam_mark, final_exam_mark, created_at, updated_at)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, NOW(), NOW())
                       ON CONFLICT (student_id, course_id, semester)
                       DO UPDATE SET
                         coursework_mark=EXCLUDED.coursework_mark,
                         week7_exam_mark=EXCLUDED.week7_exam_mark,
                         week12_exam_mark=EXCLUDED.week12_exam_mark,
                         final_exam_mark=EXCLUDED.final_exam_mark,
                         updated_at=NOW()""",
                    [
                        (
                            row["student_id"],
                            course_id,
                            semester,
                            row["coursework_mark"], row["week7_exam_mark"],
                            row["week12_exam_mark"], row["final_exam_mark"],
                        )
                        for row in rows
                    ],
                )

    def get_student_portal_grade_report(self, student_id: str) -> dict[str, Any] | None:
        student = self.get_student(student_id)
        if student is None:
            return None
        records = self._fetch_all(
            """SELECT c.course_id::text AS course_id, c.course_title AS course_name, %s AS semester,
                      COALESCE(g.coursework_mark, 0) AS coursework_mark,
                      COALESCE(g.week7_exam_mark, 0) AS week7_exam_mark,
                      COALESCE(g.week12_exam_mark, 0) AS week12_exam_mark,
                      COALESCE(g.final_exam_mark, 0) AS final_exam_mark
               FROM student_courses sc
               JOIN courses c ON c.course_id = sc.course_id
               LEFT JOIN course_gradebook_entries g
                 ON g.student_id = sc.student_id::text
                AND g.course_id = c.course_id::text
                AND g.semester = %s
               WHERE sc.student_id::text = %s AND sc.status = 'Current'
               ORDER BY c.course_title""",
            (self.semester, self.semester, student_id),
        )
        return {"student": student.as_dict(), "records": records}

    def get_read_notification_ids(self, student_id: str) -> set[str]:
        rows = self._fetch_all(
            "SELECT notification_id FROM portal_notification_reads WHERE student_id = %s",
            (student_id,),
        )
        return {str(row["notification_id"]) for row in rows}

    def set_notifications_read(
        self, student_id: str, notification_ids: list[str], read: bool
    ) -> None:
        if not notification_ids:
            return
        with self._connect() as connection:
            with connection.cursor() as cursor:
                if read:
                    psycopg2.extras.execute_batch(
                        cursor,
                        """INSERT INTO portal_notification_reads
                           (student_id, notification_id, read_at) VALUES (%s, %s, NOW())
                           ON CONFLICT (student_id, notification_id) DO UPDATE SET
                             read_at=EXCLUDED.read_at""",
                        ((student_id, notification_id) for notification_id in notification_ids),
                    )
                else:
                    cursor.execute(
                        """DELETE FROM portal_notification_reads
                           WHERE student_id = %s AND notification_id = ANY(%s)""",
                        (student_id, notification_ids),
                    )

    def get_student_progress(self, student_id: str) -> dict[str, Any] | None:
        """Return verified source records from the normalized schema.

        Where the portal has saved grades in course_gradebook_entries, those
        assessments are synthesised so the Progress Agent can detect risks even
        when the external SIS does not yet supply detailed assessment rows.
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
                cursor.execute(
                    """
                    SELECT g.course_id::text AS course_id,
                           COALESCE(g.coursework_mark, 0) AS coursework_mark,
                      COALESCE(g.week7_exam_mark, 0) AS week7_exam_mark,
                      COALESCE(g.week12_exam_mark, 0) AS week12_exam_mark,
                      COALESCE(g.final_exam_mark, 0) AS final_exam_mark
                    FROM course_gradebook_entries g
                    WHERE g.student_id = %s AND g.semester = %s
                    """,
                    (student.student_id, self.semester),
                )
                gradebook_rows = {row["course_id"]: row for row in cursor.fetchall()}
        courses = []
        for row in course_rows:
            course_id = row["course_id"]
            grades = gradebook_rows.get(course_id)
            assessments: list[dict[str, Any]] = []
            if grades is not None:
                assessments = [
                    {"assessment_id": f"{course_id}-coursework", "name": "Coursework", "assessment_type": "assignment", "weight": 10.0, "due_week": 5, "covered_lecture_ids": "[]", "percentage": grades["coursework_mark"] * 10},
                    {"assessment_id": f"{course_id}-week7", "name": "Week 7 exam", "assessment_type": "midterm", "weight": 30.0, "due_week": 7, "covered_lecture_ids": "[]", "percentage": grades["week7_exam_mark"] * (100/30) if self.current_week >= 7 else None},
                    {"assessment_id": f"{course_id}-week12", "name": "Week 12 exam", "assessment_type": "midterm", "weight": 20.0, "due_week": 12, "covered_lecture_ids": "[]", "percentage": grades["week12_exam_mark"] * 5 if self.current_week >= 12 else None},
                    {"assessment_id": f"{course_id}-final", "name": "Final exam", "assessment_type": "final", "weight": 40.0, "due_week": 16, "covered_lecture_ids": "[]", "percentage": grades["final_exam_mark"] * 2.5 if self.current_week >= 16 else None},
                ]
            courses.append({
                "course_id": course_id,
                "course_name": row["course_name"],
                "semester": self.semester,
                "current_week": self.current_week,
                "assessments": assessments,
                "lectures": [],
                "materials": [],
            })
        return {"student": student.as_dict(), "courses": courses}

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

    def save_intervention(
        self, student_id: str, course_id: str, week_number: int,
        intervention: dict[str, Any], fingerprint: str,
        course_health_at_creation: float | None = None,
    ) -> int:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO progress_interventions
                       (student_id, course_id, week_number, severity, reason, weak_topics_json, lecture_ids_json,
                        recommended_actions_json, message, issue_fingerprint, status, course_health_at_creation, created_at)
                       VALUES (%s, %s, %s, %s, %s, %s::jsonb, %s::jsonb, %s::jsonb, %s, %s, %s, %s, %s)
                       RETURNING intervention_id""",
                    (
                        student_id, course_id, week_number, intervention["severity"], intervention["reason"],
                        json.dumps(intervention.get("weak_topics", [])), json.dumps(intervention.get("lectures_to_review", [])),
                        json.dumps(intervention.get("recommended_actions", [])), intervention["message"], fingerprint,
                        intervention.get("status", "active"), course_health_at_creation,
                        datetime.now(UTC),
                    ),
                )
                return int(cursor.fetchone()["intervention_id"])

    def get_active_interventions(
        self, student_id: str, course_id: str | None = None
    ) -> list[dict[str, Any]]:
        query = """SELECT intervention.*, course.course_title AS course_name
                   FROM progress_interventions intervention
                   LEFT JOIN courses course ON course.course_id::text = intervention.course_id
                   WHERE intervention.student_id = %s AND intervention.status = 'active'"""
        parameters: list[Any] = [student_id]
        if course_id is not None:
            query += " AND intervention.course_id = %s"
            parameters.append(course_id)
        query += " ORDER BY intervention.created_at DESC"
        return self._decode_intervention_rows(self._fetch_all(query, tuple(parameters)))

    def update_intervention_status(
        self,
        intervention_id: int,
        status: str,
        resolved_week: int | None = None,
        resolution_outcome: str | None = None,
    ) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """UPDATE progress_interventions
                       SET status = %s, resolved_week = %s, resolution_outcome = %s
                       WHERE intervention_id = %s""",
                    (status, resolved_week, resolution_outcome, intervention_id),
                )

    def get_interventions(self, student_id: str) -> list[dict[str, Any]]:
        records = self._fetch_all(
            "SELECT * FROM progress_interventions WHERE student_id = %s ORDER BY created_at DESC",
            (student_id,),
        )
        return self._decode_intervention_rows(records)

    def _decode_intervention_rows(self, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        records = []
        for record in rows:
            record = dict(record)
            record["weak_topics"] = self._json_value(record.pop("weak_topics_json"))
            record["lectures_to_review"] = self._json_value(record.pop("lecture_ids_json"))
            record["recommended_actions"] = self._json_value(record.pop("recommended_actions_json"))
            records.append(record)
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

    def save_semester_grade(
        self,
        student_id: str,
        course_id: str,
        semester: str,
        week_number: int,
        assignment_grade: float | None = None,
        lab_grade: float | None = None,
        exam_grade: float | None = None,
        exam_weight: float | None = None,
        coursework_grade: float | None = None,
    ) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO student_semester_grades
                       (student_id, course_id, semester, week_number, assignment_grade,
                        lab_grade, exam_grade, exam_weight, coursework_grade, created_at, updated_at)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW())
                       ON CONFLICT (student_id, course_id, semester, week_number)
                       DO UPDATE SET
                         assignment_grade=EXCLUDED.assignment_grade,
                         lab_grade=EXCLUDED.lab_grade,
                         exam_grade=EXCLUDED.exam_grade,
                         exam_weight=EXCLUDED.exam_weight,
                         coursework_grade=EXCLUDED.coursework_grade,
                         updated_at=NOW()""",
                    (
                        student_id, course_id, semester, week_number,
                        assignment_grade, lab_grade, exam_grade, exam_weight, coursework_grade,
                    ),
                )

    def get_semester_grades(
        self, student_id: str, course_id: str, semester: str
    ) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT * FROM student_semester_grades
               WHERE student_id = %s AND course_id = %s AND semester = %s
               ORDER BY week_number""",
            (student_id, course_id, semester),
        )

    def get_semester_grade_summary(
        self, student_id: str, course_id: str, semester: str
    ) -> dict[str, Any] | None:
        rows = self._fetch_all(
            """SELECT week_number, exam_grade, exam_weight, coursework_grade
               FROM student_semester_grades
               WHERE student_id = %s AND course_id = %s AND semester = %s
                 AND (exam_grade IS NOT NULL OR coursework_grade IS NOT NULL)""",
            (student_id, course_id, semester),
        )
        if not rows:
            return None

        exam_total = 0.0
        coursework = 0.0
        for row in rows:
            if row["exam_grade"] is not None and row["exam_weight"] is not None:
                exam_total += row["exam_grade"] * (row["exam_weight"] / 100.0)
            if row["coursework_grade"] is not None:
                coursework = max(coursework, row["coursework_grade"] * 0.1)

        current_total = exam_total + coursework
        return {
            "student_id": student_id,
            "course_id": course_id,
            "semester": semester,
            "exam_contribution": round(exam_total, 2),
            "coursework_contribution": round(coursework, 2),
            "current_total": round(current_total, 2),
            "remaining": round(100.0 - current_total, 2),
        }
