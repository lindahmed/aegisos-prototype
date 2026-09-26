"""PostgreSQL/Supabase repository for the normalized Database-branch schema.

The source schema supplies student identity, programmes, course catalogues, and
current enrollments.  It currently does not include assessment, lecture, or
material records, so progress responses remain explicitly data-limited until
those portal tables are added to the same database.
"""

from __future__ import annotations

import json
import os
import threading
from contextlib import contextmanager
from datetime import UTC, date, datetime
from typing import Any

try:
    import psycopg2
    import psycopg2.extras
    from psycopg2.pool import ThreadedConnectionPool
except ImportError:  # permits SQLite-only development and test runs
    psycopg2 = None
    ThreadedConnectionPool = None

from .academic_calendar import FALL_2026_START_DATE, academic_week
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
        self.semester = os.getenv("AEGIS_CURRENT_SEMESTER", "Fall 2026")
        start_date_value = os.getenv(
            "AEGIS_SEMESTER_START_DATE", FALL_2026_START_DATE.isoformat()
        )
        try:
            self.semester_start_date = date.fromisoformat(start_date_value)
        except ValueError as error:
            raise ValueError(
                "AEGIS_SEMESTER_START_DATE must use YYYY-MM-DD format"
            ) from error
        try:
            self._pool_size = max(1, int(os.getenv("AEGIS_DB_POOL_SIZE", "8")))
        except ValueError as error:
            raise ValueError("AEGIS_DB_POOL_SIZE must be a positive integer") from error
        self._pool = None
        self._pool_lock = threading.Lock()
        self._pool_slots = threading.BoundedSemaphore(self._pool_size)

    @property
    def current_week(self) -> int:
        """One shared week number that advances with the real calendar."""
        return academic_week(self.semester_start_date)

    def _connection_pool(self):
        if psycopg2 is None or ThreadedConnectionPool is None:
            raise RuntimeError(
                "PostgreSQL support requires psycopg2-binary. Install backend requirements."
            )
        if self._pool is None:
            with self._pool_lock:
                if self._pool is None:
                    self._pool = ThreadedConnectionPool(
                        1,
                        self._pool_size,
                        self.dsn,
                        cursor_factory=psycopg2.extras.RealDictCursor,
                        connect_timeout=10,
                        application_name="aegisos-api",
                    )
        return self._pool

    @staticmethod
    def _checkout_connection(pool):
        """Return a live pooled connection, replacing sockets closed while idle."""
        connection = pool.getconn()
        if connection.closed:
            pool.putconn(connection, close=True)
            return pool.getconn()

        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
            connection.rollback()
        except Exception:
            pool.putconn(connection, close=True)
            connection = pool.getconn()
        return connection

    @contextmanager
    def _connect(self):
        """Borrow a verified connection and evict it if the socket breaks."""
        pool = self._connection_pool()
        self._pool_slots.acquire()
        connection = None
        discard_connection = False
        try:
            connection = self._checkout_connection(pool)
            yield connection
            connection.commit()
        except Exception:
            if connection is not None:
                discard_connection = bool(connection.closed)
                if not discard_connection:
                    try:
                        connection.rollback()
                    except Exception:
                        discard_connection = True
            raise
        finally:
            if connection is not None:
                pool.putconn(
                    connection,
                    close=discard_connection or bool(connection.closed),
                )
            self._pool_slots.release()

    def close(self) -> None:
        """Close pooled connections during application shutdown."""
        with self._pool_lock:
            if self._pool is not None:
                self._pool.closeall()
                self._pool = None

    def initialize(self) -> None:
        """Create only progress-agent history tables; academic source tables are external."""
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    CREATE EXTENSION IF NOT EXISTS vector;
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
                    CREATE TABLE IF NOT EXISTS student_score_achievements (
                        student_id TEXT NOT NULL,
                        achievement_id TEXT NOT NULL,
                        kind TEXT NOT NULL CHECK(kind IN ('project', 'award')),
                        title TEXT NOT NULL,
                        week_number INTEGER NOT NULL CHECK(week_number >= 1),
                        PRIMARY KEY (student_id, achievement_id)
                    );
                    CREATE TABLE IF NOT EXISTS student_score_lectures (
                        student_id TEXT NOT NULL,
                        course_id TEXT NOT NULL,
                        semester TEXT NOT NULL,
                        lecture_number INTEGER NOT NULL CHECK(lecture_number >= 1),
                        completed_week INTEGER NOT NULL CHECK(completed_week >= 1),
                        source TEXT NOT NULL DEFAULT 'verified',
                        PRIMARY KEY (student_id, course_id, semester, lecture_number)
                    );
                    CREATE TABLE IF NOT EXISTS weekly_plan_items (
                        task_id TEXT PRIMARY KEY,
                        student_id TEXT NOT NULL,
                        semester TEXT NOT NULL,
                        week_number INTEGER NOT NULL CHECK(week_number >= 1),
                        course_id TEXT NOT NULL,
                        course_name TEXT NOT NULL,
                        title TEXT NOT NULL,
                        detail TEXT NOT NULL,
                        task_type TEXT NOT NULL CHECK(task_type IN ('risk', 'assessment')),
                        status TEXT NOT NULL DEFAULT 'pending'
                            CHECK(status IN ('pending', 'completed')),
                        position INTEGER NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        completed_at TIMESTAMPTZ,
                        UNIQUE(student_id, semester, week_number, task_id)
                    );
                    CREATE INDEX IF NOT EXISTS idx_weekly_plan_student_week
                        ON weekly_plan_items(student_id, semester, week_number, position);
                    CREATE TABLE IF NOT EXISTS attendance_auto_drops (
                        student_id TEXT NOT NULL,
                        course_code TEXT NOT NULL,
                        semester_id INTEGER NOT NULL,
                        dropped_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        PRIMARY KEY (student_id, course_code, semester_id)
                    );
                    CREATE TABLE IF NOT EXISTS course_schedule_slots (
                        schedule_slot_id BIGSERIAL PRIMARY KEY,
                        course_id TEXT NOT NULL REFERENCES courses(course_code),
                        day_of_week TEXT NOT NULL,
                        start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
                        end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440),
                        location TEXT,
                        CHECK(end_minute > start_minute)
                    );
                    CREATE TABLE IF NOT EXISTS portal_messages (
                        message_id TEXT PRIMARY KEY,
                        sender_type TEXT NOT NULL CHECK(sender_type IN ('student', 'staff')),
                        sender_id TEXT NOT NULL,
                        recipient_type TEXT CHECK(recipient_type IN ('student', 'staff')),
                        recipient_id TEXT,
                        is_broadcast BOOLEAN NOT NULL DEFAULT FALSE,
                        body TEXT NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        CHECK(
                            (is_broadcast AND sender_type = 'staff' AND recipient_id IS NULL)
                            OR
                            (NOT is_broadcast AND recipient_type IS NOT NULL AND recipient_id IS NOT NULL)
                        )
                    );
                    CREATE TABLE IF NOT EXISTS portal_message_reads (
                        message_id TEXT NOT NULL REFERENCES portal_messages(message_id)
                            ON DELETE CASCADE,
                        reader_type TEXT NOT NULL CHECK(reader_type IN ('student', 'staff')),
                        reader_id TEXT NOT NULL,
                        read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                        PRIMARY KEY (message_id, reader_type, reader_id)
                    );
                    CREATE INDEX IF NOT EXISTS idx_portal_messages_sender
                        ON portal_messages(sender_type, sender_id, created_at);
                    CREATE INDEX IF NOT EXISTS idx_portal_messages_recipient
                        ON portal_messages(recipient_type, recipient_id, created_at);
                    CREATE TABLE IF NOT EXISTS material_documents (
                        document_id TEXT PRIMARY KEY,
                        course_id TEXT NOT NULL REFERENCES courses(course_code),
                        course_name TEXT NOT NULL,
                        major_code TEXT NOT NULL,
                        program_semester INTEGER NOT NULL,
                        title TEXT NOT NULL,
                        category TEXT NOT NULL,
                        week_number INTEGER,
                        original_filename TEXT NOT NULL,
                        source_archive_path TEXT NOT NULL,
                        storage_provider TEXT NOT NULL,
                        storage_path TEXT NOT NULL,
                        mime_type TEXT NOT NULL,
                        checksum TEXT NOT NULL,
                        size_bytes BIGINT NOT NULL,
                        page_count INTEGER,
                        visibility TEXT NOT NULL,
                        status TEXT NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL,
                        updated_at TIMESTAMPTZ NOT NULL,
                        UNIQUE(course_id, checksum)
                    );
                    CREATE TABLE IF NOT EXISTS material_chunks (
                        chunk_id TEXT PRIMARY KEY,
                        document_id TEXT NOT NULL REFERENCES material_documents(document_id)
                            ON DELETE CASCADE,
                        chunk_index INTEGER NOT NULL,
                        content TEXT NOT NULL,
                        page_start INTEGER,
                        page_end INTEGER,
                        token_count INTEGER NOT NULL,
                        embedding vector(768) NOT NULL,
                        search_document TSVECTOR GENERATED ALWAYS AS (
                            to_tsvector('english', content)
                        ) STORED,
                        UNIQUE(document_id, chunk_index)
                    );
                    CREATE TABLE IF NOT EXISTS material_summaries (
                        document_id TEXT PRIMARY KEY REFERENCES material_documents(document_id)
                            ON DELETE CASCADE,
                        summary TEXT NOT NULL,
                        learning_objectives_json JSONB NOT NULL,
                        keywords_json JSONB NOT NULL,
                        generator TEXT NOT NULL,
                        updated_at TIMESTAMPTZ NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS material_ingestion_jobs (
                        job_id TEXT PRIMARY KEY,
                        source TEXT NOT NULL,
                        status TEXT NOT NULL,
                        report_json JSONB NOT NULL,
                        started_at TIMESTAMPTZ NOT NULL,
                        finished_at TIMESTAMPTZ
                    );
                    CREATE INDEX IF NOT EXISTS idx_material_documents_scope
                        ON material_documents(major_code, program_semester, course_id, category);
                    CREATE INDEX IF NOT EXISTS idx_material_chunks_document
                        ON material_chunks(document_id, chunk_index);
                    CREATE INDEX IF NOT EXISTS idx_material_chunks_search
                        ON material_chunks USING GIN(search_document);
                    CREATE INDEX IF NOT EXISTS idx_material_chunks_embedding
                        ON material_chunks USING hnsw (embedding vector_cosine_ops);
                    DO $$
                    BEGIN
                        IF EXISTS (
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_schema = 'public'
                              AND table_name = 'course_schedule_slots'
                              AND column_name = 'course_id'
                              AND data_type <> 'text'
                        ) THEN
                            ALTER TABLE course_schedule_slots
                            ALTER COLUMN course_id TYPE TEXT USING course_id::text;
                        END IF;
                    END $$;
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS coursework_mark DOUBLE PRECISION CHECK(coursework_mark BETWEEN 0 AND 10);
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS week7_exam_mark DOUBLE PRECISION CHECK(week7_exam_mark BETWEEN 0 AND 30);
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS week12_exam_mark DOUBLE PRECISION CHECK(week12_exam_mark BETWEEN 0 AND 20);
                    ALTER TABLE course_gradebook_entries ADD COLUMN IF NOT EXISTS final_exam_mark DOUBLE PRECISION CHECK(final_exam_mark BETWEEN 0 AND 40);
                    UPDATE course_gradebook_entries SET coursework_mark=COALESCE(coursework_mark, assignment_score * 0.10), week7_exam_mark=COALESCE(week7_exam_mark, midterm_score * 0.30), week12_exam_mark=COALESCE(week12_exam_mark, 0), final_exam_mark=COALESCE(final_exam_mark, final_score * 0.40)
                    WHERE coursework_mark IS NULL AND week7_exam_mark IS NULL
                      AND week12_exam_mark IS NULL AND final_exam_mark IS NULL;
                    """
                )

    def get_student(self, student_id: str) -> Student | None:
        normalized_id = student_id.strip()
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT s.student_id::text AS student_id, s.full_name,
                           s.academic_level, s.gpa, p.major_name,
                           (
                               SELECT ARRAY_AGG(sc.grade)
                               FROM student_courses sc
                               WHERE sc.student_id = s.student_id
                                 AND sc.status = 'Completed'
                                 AND sc.grade IS NOT NULL
                           ) AS completed_grades,
                           (
                               SELECT ARRAY_AGG(c.course_title ORDER BY c.course_title)
                               FROM student_courses sc
                               JOIN courses c ON c.course_code = sc.course_code
                               WHERE sc.student_id = s.student_id
                                 AND sc.status = 'Current'
                           ) AS enrolled_courses,
                           (
                               SELECT ARRAY_AGG(c.course_title ORDER BY c.course_title)
                               FROM department_plan_courses plan
                               JOIN courses c ON c.course_code = plan.course_code
                               WHERE upper(plan.major_code) = upper(p.major_code)
                                 AND plan.program_semester = s.current_semester
                           ) AS planned_courses
                    FROM students s
                    JOIN majors p ON p.program_id = s.program_id
                    WHERE s.student_id::text = %s
                    """,
                    (normalized_id,),
                )
                student_row = cursor.fetchone()
                if student_row is None:
                    return None
        completed_rows = [
            {"grade": grade} for grade in (student_row["completed_grades"] or [])
        ]
        return Student(
            student_id=student_row["student_id"],
            name=student_row["full_name"],
            major=student_row["major_name"],
            year=student_row["academic_level"],
            gpa=float(student_row["gpa"]) if student_row["gpa"] is not None else self._compute_gpa(completed_rows),
            courses=tuple(
                student_row["enrolled_courses"]
                or student_row["planned_courses"]
                or []
            ),
        )

    def get_registered_students(self) -> list[Student]:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT student_id::text AS student_id FROM students ORDER BY student_id")
                ids = [row["student_id"] for row in cursor.fetchall()]
        return [student for student_id in ids if (student := self.get_student(student_id))]

    def create_portal_message(self, message: dict[str, Any]) -> dict[str, Any]:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO portal_messages (
                           message_id, sender_type, sender_id, recipient_type,
                           recipient_id, is_broadcast, body, created_at
                       ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                    (
                        message["message_id"],
                        message["sender_type"],
                        message["sender_id"],
                        message.get("recipient_type"),
                        message.get("recipient_id"),
                        bool(message.get("is_broadcast")),
                        message["body"],
                        message["created_at"],
                    ),
                )
        return dict(message)

    def list_portal_messages(
        self, actor_type: str, actor_id: str
    ) -> list[dict[str, Any]]:
        rows = self._fetch_all(
            """SELECT m.*,
                      CASE WHEN r.message_id IS NULL THEN FALSE ELSE TRUE END AS was_read
               FROM portal_messages AS m
               LEFT JOIN portal_message_reads AS r
                 ON r.message_id = m.message_id
                AND r.reader_type = %s AND r.reader_id = %s
               WHERE (m.sender_type = %s AND m.sender_id = %s)
                  OR (m.recipient_type = %s AND m.recipient_id = %s)
                  OR (%s = 'student' AND m.is_broadcast = TRUE)
               ORDER BY m.created_at, m.message_id""",
            (
                actor_type,
                actor_id,
                actor_type,
                actor_id,
                actor_type,
                actor_id,
                actor_type,
            ),
        )
        for message in rows:
            created_at = message.get("created_at")
            if hasattr(created_at, "isoformat"):
                message["created_at"] = created_at.isoformat()
            message["is_broadcast"] = bool(message["is_broadcast"])
            message["read"] = (
                message["sender_type"] == actor_type
                and message["sender_id"] == actor_id
            ) or bool(message.pop("was_read"))
        return rows

    def mark_portal_messages_read(
        self, actor_type: str, actor_id: str, message_ids: list[str]
    ) -> None:
        if not message_ids:
            return
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.executemany(
                    """INSERT INTO portal_message_reads (
                           message_id, reader_type, reader_id, read_at
                       ) VALUES (%s, %s, %s, NOW())
                       ON CONFLICT(message_id, reader_type, reader_id)
                       DO UPDATE SET read_at=EXCLUDED.read_at""",
                    (
                        (message_id, actor_type, actor_id)
                        for message_id in message_ids
                    ),
                )

    def get_semester_planner_source(self, student_id: str) -> dict[str, Any] | None:
        """Return normalized curriculum facts used by the semester planner."""
        student = self._fetch_one(
            """SELECT s.student_id::text AS student_id, s.program_id,
                      s.current_semester, s.gpa, p.major_name
               FROM students s
               JOIN majors p ON p.program_id = s.program_id
               WHERE s.student_id::text = %s""",
            (student_id.strip(),),
        )
        if student is None:
            return None
        courses = self._fetch_all(
            """SELECT c.course_code AS course_id,
                      c.course_code,
                      c.course_title AS course_name,
                      dpc.program_semester AS curriculum_semester,
                      NULL AS course_type
               FROM department_plan_courses dpc
               JOIN courses c ON c.course_code = dpc.course_code
               JOIN majors m ON m.major_code = dpc.major_code
               WHERE m.program_id = %s
               ORDER BY dpc.program_semester, c.course_code, c.course_title""",
            (student["program_id"],),
        )
        enrollments = self._fetch_all(
            """SELECT sc.course_code AS course_id, sem.name AS semester,
                      sc.status, sc.grade
               FROM student_courses sc
               LEFT JOIN semesters sem ON sem.id = sc.semester_id
               WHERE sc.student_id::text = %s""",
            (student_id.strip(),),
        )
        prerequisites = self._fetch_all(
            """SELECT pre.course_code AS course_id,
                      pre.prerequisite_code AS prerequisite_course_id
               FROM course_prerequisites pre
               JOIN department_plan_courses dpc ON dpc.course_code = pre.course_code
               JOIN majors m ON m.major_code = dpc.major_code
               WHERE m.program_id = %s""",
            (student["program_id"],),
        )
        schedules = self._fetch_all(
            """SELECT c.course_code AS course_id, slot.day_of_week,
                      slot.start_minute, slot.end_minute, slot.location
               FROM course_schedule_slots slot
               JOIN courses c ON c.course_code = slot.course_id
               ORDER BY slot.day_of_week, slot.start_minute""",
            (),
        )
        return {
            "student": student,
            "courses": courses,
            "enrollments": enrollments,
            "prerequisites": prerequisites,
            "schedules": schedules,
            "schedule_data_available": bool(schedules),
        }

    def get_student_current_courses(self, student_id: str) -> dict[str, Any] | None:
        student = self.get_student(student_id)
        if student is None:
            return None
        rows = self._fetch_all(
            """WITH current_enrollments AS (
                 SELECT sc.course_code, sc.status, sc.semester_id
                 FROM student_courses sc
                 WHERE sc.student_id::text = %s AND sc.status = 'Current'
               ),
               selected_courses AS (
                 SELECT course_code, status, semester_id
                 FROM current_enrollments
                 UNION ALL
                 SELECT plan.course_code, 'Current' AS status, NULL::integer
                 FROM students selected_student
                 JOIN majors selected_major
                   ON selected_major.program_id = selected_student.program_id
                 JOIN department_plan_courses plan
                   ON upper(plan.major_code) = upper(selected_major.major_code)
                  AND plan.program_semester = selected_student.current_semester
                 WHERE selected_student.student_id::text = %s
                   AND NOT EXISTS (SELECT 1 FROM current_enrollments)
               )
               SELECT c.course_code, c.course_title AS course_name,
                      selected.status, COALESCE(sem.name, %s) AS semester,
                      slot.day_of_week, slot.start_minute,
                      slot.end_minute, slot.location
               FROM selected_courses selected
               JOIN courses c ON c.course_code = selected.course_code
               LEFT JOIN semesters sem ON sem.id = selected.semester_id
               LEFT JOIN course_schedule_slots slot ON slot.course_id = c.course_code
               ORDER BY c.course_title, slot.day_of_week, slot.start_minute""",
            (student.student_id, student.student_id, self.semester),
        )
        courses: dict[str, dict[str, Any]] = {}
        for row in rows:
            course_code = str(row["course_code"])
            course = courses.setdefault(
                course_code,
                {
                    "course_code": course_code,
                    "course_name": row["course_name"],
                    "status": row["status"],
                    "semester": row["semester"],
                    "schedule": [],
                },
            )
            if row["day_of_week"] is not None:
                course["schedule"].append(
                    {
                        "day_of_week": row["day_of_week"],
                        "start_minute": row["start_minute"],
                        "end_minute": row["end_minute"],
                        "location": row["location"],
                    }
                )
        return {
            "student": student.as_dict(),
            "course_count": len(courses),
            "schedule_published": any(
                course["schedule"] for course in courses.values()
            ),
            "courses": list(courses.values()),
        }



    def upsert_material_document(self, document: dict[str, Any]) -> None:
        fields = (
            "document_id", "course_id", "course_name", "major_code",
            "program_semester", "title", "category", "week_number",
            "original_filename", "source_archive_path", "storage_provider",
            "storage_path", "mime_type", "checksum", "size_bytes",
            "page_count", "visibility", "status", "created_at", "updated_at",
        )
        values = tuple(document.get(field) for field in fields)
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    f"""INSERT INTO material_documents ({', '.join(fields)})
                        VALUES ({', '.join('%s' for _ in fields)})
                        ON CONFLICT(document_id) DO UPDATE SET
                          course_id=EXCLUDED.course_id,
                          course_name=EXCLUDED.course_name,
                          major_code=EXCLUDED.major_code,
                          program_semester=EXCLUDED.program_semester,
                          title=EXCLUDED.title,
                          category=EXCLUDED.category,
                          week_number=EXCLUDED.week_number,
                          original_filename=EXCLUDED.original_filename,
                          source_archive_path=EXCLUDED.source_archive_path,
                          storage_provider=EXCLUDED.storage_provider,
                          storage_path=EXCLUDED.storage_path,
                          mime_type=EXCLUDED.mime_type,
                          checksum=EXCLUDED.checksum,
                          size_bytes=EXCLUDED.size_bytes,
                          page_count=EXCLUDED.page_count,
                          visibility=EXCLUDED.visibility,
                          status=EXCLUDED.status,
                          updated_at=EXCLUDED.updated_at""",
                    values,
                )
                cursor.execute(
                    """INSERT INTO notifications (student_id, message, type)
                       SELECT sc.student_id, %s, 'material'
                       FROM student_courses sc
                       WHERE sc.course_code = %s AND sc.status = 'Current'""",
                    (
                        f"New lecture uploaded: {document.get('title')} ({document.get('course_name')})",
                        document.get("course_id"),
                    ),
                )

    @staticmethod
    def _vector_literal(values: list[float]) -> str:
        return "[" + ",".join(f"{value:.9g}" for value in values) + "]"

    def replace_material_chunks(
        self, document_id: str, chunks: list[dict[str, Any]]
    ) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "DELETE FROM material_chunks WHERE document_id = %s",
                    (document_id,),
                )
                psycopg2.extras.execute_batch(
                    cursor,
                    """INSERT INTO material_chunks
                       (chunk_id, document_id, chunk_index, content, page_start,
                        page_end, token_count, embedding)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s::vector)""",
                    (
                        (
                            chunk["chunk_id"], document_id, chunk["chunk_index"],
                            chunk["content"], chunk.get("page_start"),
                            chunk.get("page_end"), chunk["token_count"],
                            self._vector_literal(chunk["embedding"]),
                        )
                        for chunk in chunks
                    ),
                    page_size=100,
                )

    def upsert_material_summary(
        self, document_id: str, summary: dict[str, Any]
    ) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO material_summaries
                       (document_id, summary, learning_objectives_json,
                        keywords_json, generator, updated_at)
                       VALUES (%s, %s, %s::jsonb, %s::jsonb, %s, NOW())
                       ON CONFLICT(document_id) DO UPDATE SET
                         summary=EXCLUDED.summary,
                         learning_objectives_json=EXCLUDED.learning_objectives_json,
                         keywords_json=EXCLUDED.keywords_json,
                         generator=EXCLUDED.generator,
                         updated_at=EXCLUDED.updated_at""",
                    (
                        document_id,
                        summary.get("summary", ""),
                        json.dumps(summary.get("learning_objectives", [])),
                        json.dumps(summary.get("keywords", [])),
                        summary.get("generator", "unknown"),
                    ),
                )

    def save_material_ingestion_job(self, job: dict[str, Any]) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO material_ingestion_jobs
                       (job_id, source, status, report_json, started_at, finished_at)
                       VALUES (%s, %s, %s, %s::jsonb, %s, %s)
                       ON CONFLICT(job_id) DO UPDATE SET
                         status=EXCLUDED.status,
                         report_json=EXCLUDED.report_json,
                         finished_at=EXCLUDED.finished_at""",
                    (
                        job["job_id"], job["source"], job["status"],
                        json.dumps(job, ensure_ascii=False), job["started_at"],
                        job.get("finished_at"),
                    ),
                )

    def list_student_materials(
        self, student_id: str, course_id: str | None = None
    ) -> list[dict[str, Any]]:
        course_clause = ""
        parameters: list[Any] = [student_id]
        if course_id:
            course_clause = " AND document.course_id = %s"
            parameters.append(course_id)
        return self._fetch_all(
            f"""SELECT document.*, summary.summary,
                       summary.learning_objectives_json,
                       summary.keywords_json
                FROM material_documents document
                JOIN students student ON student.student_id::text = %s
                JOIN majors major ON major.program_id = student.program_id
                LEFT JOIN material_summaries summary
                  ON summary.document_id = document.document_id
                WHERE upper(document.major_code) = upper(major.major_code)
                  AND document.program_semester = student.current_semester
                  AND document.visibility IN ('student', 'student_practice')
                  {course_clause}
                ORDER BY document.course_name, document.week_number,
                         document.category, document.title""",
            tuple(parameters),
        )

    def search_student_materials(
        self,
        student_id: str,
        query: str,
        *,
        course_id: str | None = None,
        limit: int = 8,
    ) -> list[dict[str, Any]]:
        from backend.materials.retrieval import embed_text, requested_week

        vector = self._vector_literal(embed_text(query))
        course_clause = ""
        parameters: list[Any] = [query, vector, student_id]
        if course_id:
            course_clause = " AND document.course_id = %s"
            parameters.append(course_id)
        week_clause = ""
        week_number = requested_week(query)
        if week_number is not None:
            week_clause = " AND document.week_number = %s"
            parameters.append(week_number)
        parameters.append(max(1, min(limit, 20)))
        return self._fetch_all(
            f"""SELECT chunk.chunk_id, chunk.document_id,
                       document.course_id, document.course_name, document.title,
                       document.category, document.week_number,
                       chunk.page_start, chunk.page_end, chunk.content,
                       document.storage_path,
                       ROUND((
                         ts_rank_cd(
                           to_tsvector(
                             'english',
                             document.title || ' ' || document.course_name || ' ' || chunk.content
                           ),
                           plainto_tsquery('english', %s)
                         ) * 0.65
                         + GREATEST(0, 1 - (chunk.embedding <=> %s::vector)) * 0.35
                       )::numeric, 6)::double precision AS score
                FROM material_chunks chunk
                JOIN material_documents document
                  ON document.document_id = chunk.document_id
                JOIN students student ON student.student_id::text = %s
                JOIN majors major ON major.program_id = student.program_id
                WHERE upper(document.major_code) = upper(major.major_code)
                  AND document.program_semester = student.current_semester
                  AND document.visibility IN ('student', 'student_practice')
                  {course_clause}
                  {week_clause}
                ORDER BY score DESC, document.course_name, document.title
                LIMIT %s""",
            tuple(parameters),
        )

    def list_portal_courses(self) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT c.course_code AS course_id, c.course_title AS course_name,
                      %s AS semester, COUNT(sc.student_id) AS student_count
               FROM courses c
               JOIN student_courses sc ON sc.course_code = c.course_code
               WHERE sc.status = 'Current'
               GROUP BY c.course_code, c.course_title
               ORDER BY c.course_title""",
            (self.semester,),
        )

    def get_portal_course_gradebook(
        self, course_id: str, semester: str | None = None
    ) -> dict[str, Any] | None:
        selected_semester = semester or self.semester
        course = self._fetch_one(
            """SELECT c.course_code AS course_id, c.course_title AS course_name, %s AS semester
               FROM courses c
               WHERE c.course_code = %s""",
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
               LEFT JOIN LATERAL (
                 SELECT entry.*
                 FROM course_gradebook_entries entry
                 WHERE entry.student_id = s.student_id::text
                   AND entry.course_id = sc.course_code
                 ORDER BY CASE
                   WHEN entry.semester = %s THEN 0
                   WHEN entry.semester = 'Current semester' THEN 1
                   ELSE 2
                 END, entry.updated_at DESC
                 LIMIT 1
               ) g ON TRUE
               WHERE sc.course_code = %s AND sc.status = 'Current'
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
            """SELECT c.course_code AS course_id,
                      c.course_code,
                      c.course_title AS course_name,
                      CASE WHEN sc.status = 'Current' THEN %s
                           ELSE sem.name END AS semester,
                      sc.status AS enrollment_status,
                      sc.grade AS stored_letter_grade,
                      CASE WHEN g.student_id IS NOT NULL THEN 'gradebook'
                           WHEN sc.status = 'Completed' AND sc.grade IS NOT NULL THEN 'transcript'
                           ELSE 'none' END AS grade_source,
                      g.coursework_mark,
                      g.week7_exam_mark,
                      g.week12_exam_mark,
                      g.final_exam_mark,
                      g.updated_at AS grade_updated_at
               FROM student_courses sc
               JOIN courses c ON c.course_code = sc.course_code
               LEFT JOIN semesters sem ON sem.id = sc.semester_id
               LEFT JOIN LATERAL (
                 SELECT entry.*
                 FROM course_gradebook_entries entry
                 WHERE entry.student_id = sc.student_id::text
                   AND entry.course_id = c.course_code
                 ORDER BY CASE
                   WHEN entry.semester = %s THEN 0
                   WHEN entry.semester = 'Current semester' THEN 1
                   ELSE 2
                 END, entry.updated_at DESC
                 LIMIT 1
               ) g ON TRUE
               WHERE sc.student_id::text = %s
               ORDER BY CASE WHEN sc.status = 'Current' THEN 0 ELSE 1 END,
                        sc.semester_id DESC, c.course_title""",
            (self.semester, self.semester, student_id),
        )
        return {"student": student.as_dict(), "records": records}

    def get_portal_course_attendance(
        self, course_id: str, session_date: date
    ) -> dict[str, Any] | None:
        course = self._fetch_one(
            """SELECT c.course_code AS course_id, c.course_title AS course_name,
                      sem.id AS semester_id, sem.name AS semester,
                      sem.start_date, sem.end_date
               FROM courses c
               JOIN semesters sem ON %s BETWEEN sem.start_date AND sem.end_date
               WHERE c.course_code = %s
               ORDER BY sem.is_current DESC, sem.start_date DESC
               LIMIT 1""",
            (session_date, course_id),
        )
        if course is None:
            return None
        week_number = ((session_date - course["start_date"]).days // 7) + 1
        if week_number < 1 or week_number > 16:
            raise ValueError("Attendance date must fall within the 16 teaching weeks")

        rows = self._fetch_all(
            """SELECT s.student_id::text AS student_id,
                      s.full_name AS student_name,
                      COALESCE(record.status, 'Present') AS status,
                      sc.status AS enrollment_status,
                      (
                        SELECT COUNT(*) FROM attendance history
                        WHERE history.student_id = s.student_id::text
                          AND history.course_code = sc.course_code
                          AND history.semester_id = sc.semester_id
                          AND history.status = 'Absent'
                      ) AS absence_count
               FROM student_courses sc
               JOIN students s ON s.student_id = sc.student_id
               LEFT JOIN attendance record
                 ON record.student_id = s.student_id::text
                AND record.course_code = sc.course_code
                AND record.semester_id = sc.semester_id
                AND record.week_number = %s
               WHERE sc.course_code = %s AND sc.semester_id = %s
                 AND (sc.status = 'Current' OR record.attendance_id IS NOT NULL)
               ORDER BY s.full_name""",
            (week_number, course_id, course["semester_id"]),
        )
        return {
            "course": {
                "course_id": course["course_id"],
                "course_name": course["course_name"],
                "semester": course["semester"],
            },
            "session_date": session_date.isoformat(),
            "week_number": week_number,
            "rows": rows,
        }

    def save_portal_course_attendance(
        self, course_id: str, session_date: date, rows: list[dict[str, Any]]
    ) -> dict[str, Any] | None:
        attendance = self.get_portal_course_attendance(course_id, session_date)
        if attendance is None:
            return None
        valid_student_ids = {str(row["student_id"]) for row in attendance["rows"]}
        unknown = sorted(
            str(row["student_id"])
            for row in rows
            if str(row["student_id"]) not in valid_student_ids
        )
        if unknown:
            raise ValueError(f"Unknown or unenrolled students: {', '.join(unknown)}")

        semester = self._fetch_one(
            """SELECT id FROM semesters
               WHERE name = %s AND %s BETWEEN start_date AND end_date""",
            (attendance["course"]["semester"], session_date),
        )
        assert semester is not None
        semester_id = int(semester["id"])
        week_number = int(attendance["week_number"])
        dropped_student_ids: list[str] = []
        restored_student_ids: list[str] = []
        with self._connect() as connection:
            with connection.cursor() as cursor:
                # Serialize attendance updates for these enrollments so two
                # simultaneous session saves cannot both miss the threshold.
                cursor.execute(
                    """SELECT student_course_id FROM student_courses
                       WHERE course_code = %s AND semester_id = %s
                         AND student_id::text = ANY(%s)
                       FOR UPDATE""",
                    (
                        course_id,
                        semester_id,
                        [str(row["student_id"]) for row in rows],
                    ),
                )
                psycopg2.extras.execute_batch(
                    cursor,
                    """INSERT INTO attendance
                       (student_id, course_code, semester_id, week_number,
                        session_date, status)
                       VALUES (%s, %s, %s, %s, %s, %s)
                       ON CONFLICT (student_id, course_code, semester_id, week_number)
                       DO UPDATE SET session_date=EXCLUDED.session_date,
                                     status=EXCLUDED.status""",
                    (
                        (
                            str(row["student_id"]), course_id, semester_id,
                            week_number, session_date, str(row["status"]),
                        )
                        for row in rows
                    ),
                )
                for row in rows:
                    student_id = str(row["student_id"])
                    cursor.execute(
                        """SELECT COUNT(*) AS absence_count FROM attendance
                           WHERE student_id = %s AND course_code = %s
                             AND semester_id = %s AND status = 'Absent'""",
                        (student_id, course_id, semester_id),
                    )
                    absence_count = int(cursor.fetchone()["absence_count"])
                    cursor.execute(
                        """SELECT 1 FROM attendance_auto_drops
                           WHERE student_id = %s AND course_code = %s
                             AND semester_id = %s""",
                        (student_id, course_id, semester_id),
                    )
                    tracked = cursor.fetchone() is not None
                    if absence_count >= 4:
                        cursor.execute(
                            """INSERT INTO attendance_auto_drops
                               (student_id, course_code, semester_id)
                               VALUES (%s, %s, %s)
                               ON CONFLICT (student_id, course_code, semester_id)
                               DO NOTHING""",
                            (student_id, course_id, semester_id),
                        )
                        cursor.execute(
                            """UPDATE student_courses SET status = 'Withdrawn'
                               WHERE student_id::text = %s AND course_code = %s
                                 AND semester_id = %s AND status = 'Current'""",
                            (student_id, course_id, semester_id),
                        )
                        if cursor.rowcount:
                            dropped_student_ids.append(student_id)
                    elif tracked:
                        cursor.execute(
                            """DELETE FROM attendance_auto_drops
                               WHERE student_id = %s AND course_code = %s
                                 AND semester_id = %s""",
                            (student_id, course_id, semester_id),
                        )
                        cursor.execute(
                            """UPDATE student_courses SET status = 'Current'
                               WHERE student_id::text = %s AND course_code = %s
                                 AND semester_id = %s AND status = 'Withdrawn'""",
                            (student_id, course_id, semester_id),
                        )
                        if cursor.rowcount:
                            restored_student_ids.append(student_id)

        refreshed = self.get_portal_course_attendance(course_id, session_date)
        assert refreshed is not None
        return {
            **refreshed,
            "dropped_student_ids": dropped_student_ids,
            "restored_student_ids": restored_student_ids,
        }

    def get_attendance_alerts(self, student_id: str) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT record.course_code AS course_id,
                      course.course_title AS course_name,
                      semester.name AS semester,
                      COUNT(*) AS absence_count,
                      (auto_drop.student_id IS NOT NULL) AS automatically_dropped
               FROM attendance record
               JOIN courses course ON course.course_code = record.course_code
               JOIN semesters semester ON semester.id = record.semester_id
               LEFT JOIN attendance_auto_drops auto_drop
                 ON auto_drop.student_id = record.student_id
                AND auto_drop.course_code = record.course_code
                AND auto_drop.semester_id = record.semester_id
               WHERE record.student_id = %s AND record.status = 'Absent'
               GROUP BY record.course_code, course.course_title,
                        record.semester_id, semester.name, auto_drop.student_id
               HAVING COUNT(*) >= 3
               ORDER BY record.semester_id DESC, course.course_title""",
            (student_id,),
        )

    def get_read_notification_ids(self, student_id: str) -> set[str]:
        rows = self._fetch_all(
            "SELECT notification_id FROM portal_notification_reads WHERE student_id = %s",
            (student_id,),
        )
        return {str(row["notification_id"]) for row in rows}



    def get_stored_notifications(self, student_id: str) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT notification_id, message, type, is_read, created_at
               FROM notifications
               WHERE student_id = %s
               ORDER BY created_at DESC""",
            (student_id,),
        )



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

    def get_weekly_plan_items(
        self, student_id: str, semester: str, week_number: int
    ) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT task_id, course_id, course_name, title, detail,
                      task_type, status, position, completed_at
               FROM weekly_plan_items
               WHERE student_id = %s AND semester = %s AND week_number = %s
               ORDER BY position, created_at, task_id""",
            (student_id, semester, week_number),
        )

    def upsert_weekly_plan_items(
        self,
        student_id: str,
        semester: str,
        week_number: int,
        items: list[dict[str, Any]],
    ) -> None:
        if not items:
            return
        with self._connect() as connection:
            with connection.cursor() as cursor:
                psycopg2.extras.execute_batch(
                    cursor,
                    """INSERT INTO weekly_plan_items
                       (task_id, student_id, semester, week_number, course_id,
                        course_name, title, detail, task_type, status, position)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending', %s)
                       ON CONFLICT (task_id) DO UPDATE SET
                         course_name=EXCLUDED.course_name,
                         title=EXCLUDED.title,
                         detail=EXCLUDED.detail,
                         position=EXCLUDED.position""",
                    (
                        (
                            item["task_id"],
                            student_id,
                            semester,
                            week_number,
                            item["course_id"],
                            item["course_name"],
                            item["title"],
                            item["detail"],
                            item["task_type"],
                            item["position"],
                        )
                        for item in items
                    ),
                )

    def set_weekly_plan_item_status(
        self, student_id: str, task_id: str, status: str
    ) -> dict[str, Any] | None:
        if status not in {"pending", "completed"}:
            raise ValueError("Weekly plan status must be pending or completed")
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """UPDATE weekly_plan_items
                       SET status = %s,
                           completed_at = CASE WHEN %s = 'completed' THEN NOW() ELSE NULL END,
                           updated_at = NOW()
                       WHERE student_id = %s AND task_id = %s
                       RETURNING task_id, course_id, course_name, title, detail,
                                 task_type, status, position, completed_at""",
                    (status, status, student_id, task_id),
                )
                row = cursor.fetchone()
        return dict(row) if row is not None else None

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
                    WITH current_enrollments AS (
                      SELECT sc.course_code
                      FROM student_courses sc
                      WHERE sc.student_id::text = %s AND sc.status = 'Current'
                    ),
                    selected_courses AS (
                      SELECT course_code FROM current_enrollments
                      UNION
                      SELECT plan.course_code
                      FROM students selected_student
                      JOIN majors selected_major
                        ON selected_major.program_id = selected_student.program_id
                      JOIN department_plan_courses plan
                        ON upper(plan.major_code) = upper(selected_major.major_code)
                       AND plan.program_semester = selected_student.current_semester
                      WHERE selected_student.student_id::text = %s
                        AND NOT EXISTS (SELECT 1 FROM current_enrollments)
                    )
                    SELECT c.course_code AS course_id,
                           c.course_title AS course_name,
                           g.student_id AS gradebook_student_id,
                           g.coursework_mark,
                           g.week7_exam_mark,
                           g.week12_exam_mark,
                           g.final_exam_mark
                    FROM selected_courses selected
                    JOIN courses c ON c.course_code = selected.course_code
                    LEFT JOIN LATERAL (
                      SELECT entry.*
                      FROM course_gradebook_entries entry
                      WHERE entry.student_id = %s
                        AND entry.course_id = selected.course_code
                        AND entry.semester IN (%s, 'Current semester')
                      ORDER BY CASE
                        WHEN entry.semester = %s THEN 0
                        WHEN entry.semester = 'Current semester' THEN 1
                      END, entry.updated_at DESC
                      LIMIT 1
                    ) g ON TRUE
                    ORDER BY c.course_title
                    """,
                    (
                        student.student_id,
                        student.student_id,
                        student.student_id,
                        self.semester,
                        self.semester,
                    ),
                )
                course_rows = cursor.fetchall()
        courses = []
        for row in course_rows:
            course_id = row["course_id"]
            grades = row if row["gradebook_student_id"] is not None else None
            coursework_mark = grades["coursework_mark"] if grades is not None else None
            week7_mark = grades["week7_exam_mark"] if grades is not None else None
            week12_mark = grades["week12_exam_mark"] if grades is not None else None
            final_mark = grades["final_exam_mark"] if grades is not None else None
            assessments: list[dict[str, Any]] = [
                {"assessment_id": f"{course_id}-coursework", "name": "Coursework", "assessment_type": "assignment", "weight": 10.0, "due_week": 5, "covered_lecture_ids": "[]", "percentage": coursework_mark * 10 if coursework_mark is not None else None},
                {"assessment_id": f"{course_id}-week7", "name": "Week 7 exam", "assessment_type": "midterm", "weight": 30.0, "due_week": 7, "covered_lecture_ids": "[]", "percentage": week7_mark * (100/30) if week7_mark is not None and self.current_week >= 7 else None},
                {"assessment_id": f"{course_id}-week12", "name": "Week 12 exam", "assessment_type": "midterm", "weight": 20.0, "due_week": 12, "covered_lecture_ids": "[]", "percentage": week12_mark * 5 if week12_mark is not None and self.current_week >= 12 else None},
                {"assessment_id": f"{course_id}-final", "name": "Final exam", "assessment_type": "final", "weight": 40.0, "due_week": 16, "covered_lecture_ids": "[]", "percentage": final_mark * 2.5 if final_mark is not None and self.current_week >= 16 else None},
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
        return {
            "student": student.as_dict(),
            "semester": self.semester,
            "current_week": self.current_week,
            "courses": courses,
        }

    def get_score_achievements(self, student_id: str) -> list[dict[str, Any]]:
        return self._fetch_all(
            "SELECT achievement_id, kind, title, week_number FROM student_score_achievements WHERE student_id = %s ORDER BY week_number, achievement_id",
            (student_id,),
        )

    def get_score_lectures(self, student_id: str) -> list[dict[str, Any]]:
        return self._fetch_all(
            """SELECT course_id, lecture_number, completed_week
               FROM student_score_lectures
               WHERE student_id = %s AND semester = %s
               ORDER BY completed_week, course_id, lecture_number""",
            (student_id, self.semester),
        )

    def get_scoreboard_activity(self) -> list[dict[str, Any]]:
        """Load leaderboard counts in batches, avoiding a query per student."""
        profiles = self._fetch_all(
            "SELECT student_id::text AS student_id, full_name AS name FROM students", ()
        )
        by_id = {
            row["student_id"]: {**row, "lectures": 0, "good_exams": 0,
                                "projects": 0, "awards": 0}
            for row in profiles
        }
        for row in self._fetch_all(
            """SELECT student_id, COUNT(*) AS lectures
               FROM student_score_lectures
               WHERE semester = %s AND completed_week <= %s
               GROUP BY student_id""",
            (self.semester, self.current_week),
        ):
            if row["student_id"] in by_id:
                by_id[row["student_id"]]["lectures"] = int(row["lectures"])
        for row in self._fetch_all(
            """SELECT enrollment.student_id::text AS student_id,
                      COUNT(*) FILTER (WHERE grade.week7_exam_mark >= 21) AS week7,
                      COUNT(*) FILTER (WHERE grade.week12_exam_mark >= 14) AS week12,
                      COUNT(*) FILTER (WHERE grade.final_exam_mark >= 28) AS final
               FROM student_courses enrollment
               JOIN LATERAL (
                   SELECT entry.week7_exam_mark, entry.week12_exam_mark, entry.final_exam_mark
                   FROM course_gradebook_entries entry
                   WHERE entry.student_id = enrollment.student_id::text
                     AND entry.course_id = enrollment.course_code
                     AND entry.semester IN (%s, 'Current semester')
                   ORDER BY CASE WHEN entry.semester = %s THEN 0 ELSE 1 END,
                            entry.updated_at DESC
                   LIMIT 1
               ) grade ON TRUE
               WHERE enrollment.status = 'Current'
               GROUP BY enrollment.student_id""",
            (self.semester, self.semester),
        ):
            if row["student_id"] in by_id:
                by_id[row["student_id"]]["good_exams"] = (
                    (int(row["week7"]) if self.current_week >= 7 else 0)
                    + (int(row["week12"]) if self.current_week >= 12 else 0)
                    + (int(row["final"]) if self.current_week >= 16 else 0)
                )
        for row in self._fetch_all(
            """SELECT student_id, kind, COUNT(*) AS count
               FROM student_score_achievements
               WHERE week_number <= %s
               GROUP BY student_id, kind""",
            (self.current_week,),
        ):
            if row["student_id"] in by_id:
                by_id[row["student_id"]]["projects" if row["kind"] == "project" else "awards"] = int(row["count"])
        return list(by_id.values())

    def save_score_achievement(self, student_id: str, achievement_id: str, kind: str, title: str, week_number: int) -> None:
        with self._connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO student_score_achievements (student_id, achievement_id, kind, title, week_number)
                       VALUES (%s, %s, %s, %s, %s)
                       ON CONFLICT(student_id, achievement_id) DO UPDATE SET
                       kind = excluded.kind, title = excluded.title, week_number = excluded.week_number""",
                    (student_id, achievement_id, kind, title, week_number),
                )

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
               LEFT JOIN courses course ON course.course_code = snapshot.course_id
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
                   LEFT JOIN courses course ON course.course_code = intervention.course_id
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
