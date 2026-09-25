from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

from .academic_calendar import FALL_2026_START_DATE, academic_week


DATASET_PATH = Path(__file__).with_name("students.csv")


@dataclass(frozen=True)
class Student:
    student_id: str
    name: str
    major: str
    year: int
    gpa: float | None
    courses: tuple[str, ...]

    def as_dict(self) -> dict[str, object]:
        return {
            "student_id": self.student_id,
            "name": self.name,
            "major": self.major,
            "year": self.year,
            "gpa": self.gpa,
            "courses": list(self.courses),
        }


class StudentRepository:
    def __init__(self, database_path: Path, dataset_path: Path = DATASET_PATH) -> None:
        self.database_path = Path(database_path)
        self.dataset_path = Path(dataset_path)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path)
        connection.row_factory = sqlite3.Row
        return connection

    def initialize(self) -> None:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS students (
                    student_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    major TEXT NOT NULL,
                    year INTEGER NOT NULL,
                    gpa REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS courses (
                    student_id TEXT NOT NULL,
                    course_name TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'Current'
                        CHECK(status IN ('Current', 'Completed', 'Withdrawn', 'Failed')),
                    PRIMARY KEY (student_id, course_name),
                    FOREIGN KEY (student_id) REFERENCES students(student_id)
                );
                CREATE TABLE IF NOT EXISTS semester_calendar (
                    semester TEXT PRIMARY KEY,
                    current_week INTEGER NOT NULL CHECK(current_week >= 1),
                    start_date TEXT,
                    end_date TEXT
                );
                CREATE TABLE IF NOT EXISTS course_offerings (
                    course_id TEXT PRIMARY KEY,
                    course_name TEXT NOT NULL UNIQUE,
                    semester TEXT NOT NULL,
                    FOREIGN KEY (semester) REFERENCES semester_calendar(semester)
                );
                CREATE TABLE IF NOT EXISTS assessments (
                    assessment_id TEXT PRIMARY KEY,
                    course_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    assessment_type TEXT NOT NULL CHECK(assessment_type IN ('assignment', 'lab', 'quiz', 'midterm', 'final', 'exam')),
                    weight REAL NOT NULL CHECK(weight >= 0 AND weight <= 100),
                    due_week INTEGER NOT NULL CHECK(due_week >= 1),
                    covered_lecture_ids TEXT NOT NULL DEFAULT '[]',
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                CREATE TABLE IF NOT EXISTS student_assessment_grades (
                    student_id TEXT NOT NULL,
                    assessment_id TEXT NOT NULL,
                    percentage REAL NOT NULL CHECK(percentage >= 0 AND percentage <= 100),
                    graded_at TEXT,
                    PRIMARY KEY (student_id, assessment_id),
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (assessment_id) REFERENCES assessments(assessment_id)
                );
                CREATE TABLE IF NOT EXISTS lectures (
                    lecture_id TEXT PRIMARY KEY,
                    course_id TEXT NOT NULL,
                    lecture_number INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    available_week INTEGER NOT NULL CHECK(available_week >= 1),
                    UNIQUE(course_id, lecture_number),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                CREATE TABLE IF NOT EXISTS student_lecture_progress (
                    student_id TEXT NOT NULL,
                    lecture_id TEXT NOT NULL,
                    completed_week INTEGER NOT NULL CHECK(completed_week >= 1),
                    PRIMARY KEY (student_id, lecture_id),
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (lecture_id) REFERENCES lectures(lecture_id)
                );
                CREATE TABLE IF NOT EXISTS course_materials (
                    material_id TEXT PRIMARY KEY,
                    course_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    material_type TEXT NOT NULL,
                    lecture_id TEXT,
                    source_url TEXT,
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id),
                    FOREIGN KEY (lecture_id) REFERENCES lectures(lecture_id)
                );
                CREATE TABLE IF NOT EXISTS material_documents (
                    document_id TEXT PRIMARY KEY,
                    course_id TEXT NOT NULL,
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
                    size_bytes INTEGER NOT NULL,
                    page_count INTEGER,
                    visibility TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(course_id, checksum)
                );
                CREATE TABLE IF NOT EXISTS material_chunks (
                    chunk_id TEXT PRIMARY KEY,
                    document_id TEXT NOT NULL,
                    chunk_index INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    page_start INTEGER,
                    page_end INTEGER,
                    token_count INTEGER NOT NULL,
                    embedding_json TEXT NOT NULL,
                    FOREIGN KEY (document_id) REFERENCES material_documents(document_id)
                        ON DELETE CASCADE,
                    UNIQUE(document_id, chunk_index)
                );
                CREATE TABLE IF NOT EXISTS material_summaries (
                    document_id TEXT PRIMARY KEY,
                    summary TEXT NOT NULL,
                    learning_objectives_json TEXT NOT NULL,
                    keywords_json TEXT NOT NULL,
                    generator TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY (document_id) REFERENCES material_documents(document_id)
                        ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS material_ingestion_jobs (
                    job_id TEXT PRIMARY KEY,
                    source TEXT NOT NULL,
                    status TEXT NOT NULL,
                    report_json TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    finished_at TEXT
                );
                CREATE INDEX IF NOT EXISTS idx_material_documents_scope
                    ON material_documents(major_code, program_semester, course_id, category);
                CREATE INDEX IF NOT EXISTS idx_material_chunks_document
                    ON material_chunks(document_id, chunk_index);
                CREATE VIRTUAL TABLE IF NOT EXISTS material_chunks_fts USING fts5(
                    chunk_id UNINDEXED,
                    content,
                    title,
                    course_name,
                    tokenize='unicode61'
                );
                CREATE TABLE IF NOT EXISTS weekly_progress_snapshots (
                    snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    student_id TEXT NOT NULL,
                    course_id TEXT NOT NULL,
                    week_number INTEGER NOT NULL,
                    assignment_average REAL,
                    lab_average REAL,
                    quiz_average REAL,
                    exam_percentage REAL,
                    weighted_grade REAL,
                    lecture_completion REAL NOT NULL,
                    assessment_completion REAL NOT NULL,
                    course_health REAL NOT NULL,
                    risk_level TEXT NOT NULL,
                    trend TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    UNIQUE(student_id, course_id, week_number),
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                CREATE TABLE IF NOT EXISTS progress_interventions (
                    intervention_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    student_id TEXT NOT NULL,
                    course_id TEXT NOT NULL,
                    week_number INTEGER NOT NULL,
                    severity TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    weak_topics_json TEXT NOT NULL,
                    lecture_ids_json TEXT NOT NULL,
                    recommended_actions_json TEXT NOT NULL,
                    message TEXT NOT NULL,
                    issue_fingerprint TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'active',
                    course_health_at_creation REAL,
                    resolved_week INTEGER,
                    resolution_outcome TEXT CHECK(resolution_outcome IN ('improved', 'stable', 'worsened', 'no_data')),
                    follow_up_week INTEGER,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                CREATE TABLE IF NOT EXISTS student_semester_grades (
                    grade_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    student_id TEXT NOT NULL,
                    course_id TEXT NOT NULL,
                    semester TEXT NOT NULL,
                    week_number INTEGER NOT NULL CHECK(week_number BETWEEN 1 AND 16),
                    assignment_grade REAL CHECK(assignment_grade BETWEEN 0 AND 100),
                    lab_grade REAL CHECK(lab_grade BETWEEN 0 AND 100),
                    exam_grade REAL CHECK(exam_grade BETWEEN 0 AND 100),
                    exam_weight REAL CHECK(exam_weight IN (30, 20, 40)),
                    coursework_grade REAL CHECK(coursework_grade BETWEEN 0 AND 100),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(student_id, course_id, semester, week_number),
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                CREATE TABLE IF NOT EXISTS course_gradebook_entries (
                    student_id TEXT NOT NULL,
                    course_id TEXT NOT NULL,
                    semester TEXT NOT NULL,
                    assignment_score REAL NOT NULL DEFAULT 0 CHECK(assignment_score BETWEEN 0 AND 100),
                    midterm_score REAL NOT NULL DEFAULT 0 CHECK(midterm_score BETWEEN 0 AND 100),
                    final_score REAL NOT NULL DEFAULT 0 CHECK(final_score BETWEEN 0 AND 100),
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    PRIMARY KEY (student_id, course_id, semester),
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                CREATE TABLE IF NOT EXISTS portal_notification_reads (
                    student_id TEXT NOT NULL,
                    notification_id TEXT NOT NULL,
                    read_at TEXT NOT NULL,
                    PRIMARY KEY (student_id, notification_id),
                    FOREIGN KEY (student_id) REFERENCES students(student_id)
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
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    completed_at TEXT,
                    UNIQUE(student_id, semester, week_number, task_id),
                    FOREIGN KEY (student_id) REFERENCES students(student_id)
                );
                CREATE INDEX IF NOT EXISTS idx_weekly_plan_student_week
                    ON weekly_plan_items(student_id, semester, week_number, position);
                CREATE TABLE IF NOT EXISTS attendance (
                    attendance_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    student_id TEXT NOT NULL,
                    course_code TEXT NOT NULL,
                    semester_id TEXT NOT NULL,
                    week_number INTEGER NOT NULL CHECK(week_number BETWEEN 1 AND 16),
                    session_date TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('Present', 'Absent', 'Excused', 'Late')),
                    created_at TEXT NOT NULL,
                    UNIQUE(student_id, course_code, semester_id, week_number),
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (course_code) REFERENCES course_offerings(course_id),
                    FOREIGN KEY (semester_id) REFERENCES semester_calendar(semester)
                );
                CREATE TABLE IF NOT EXISTS attendance_auto_drops (
                    student_id TEXT NOT NULL,
                    course_code TEXT NOT NULL,
                    semester_id TEXT NOT NULL,
                    dropped_at TEXT NOT NULL,
                    PRIMARY KEY (student_id, course_code, semester_id)
                );
                CREATE TABLE IF NOT EXISTS course_schedule_slots (
                    schedule_slot_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    course_id TEXT NOT NULL,
                    day_of_week TEXT NOT NULL,
                    start_minute INTEGER NOT NULL CHECK(start_minute BETWEEN 0 AND 1439),
                    end_minute INTEGER NOT NULL CHECK(end_minute BETWEEN 1 AND 1440),
                    location TEXT,
                    CHECK(end_minute > start_minute),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                """
            )
            course_columns = {
                row[1] for row in connection.execute("PRAGMA table_info(courses)")
            }
            if "status" not in course_columns:
                connection.execute(
                    "ALTER TABLE courses ADD COLUMN status TEXT NOT NULL DEFAULT 'Current'"
                )
            semester_columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(semester_calendar)")
            }
            for name in ("start_date", "end_date"):
                if name not in semester_columns:
                    connection.execute(
                        f"ALTER TABLE semester_calendar ADD COLUMN {name} TEXT"
                    )
            gradebook_columns = {row[1] for row in connection.execute("PRAGMA table_info(course_gradebook_entries)")}
            for name, definition in {
                "coursework_mark": "REAL CHECK(coursework_mark BETWEEN 0 AND 10)",
                "week7_exam_mark": "REAL CHECK(week7_exam_mark BETWEEN 0 AND 30)",
                "week12_exam_mark": "REAL CHECK(week12_exam_mark BETWEEN 0 AND 20)",
                "final_exam_mark": "REAL CHECK(final_exam_mark BETWEEN 0 AND 40)",
            }.items():
                if name not in gradebook_columns:
                    connection.execute(f"ALTER TABLE course_gradebook_entries ADD COLUMN {name} {definition}")
            connection.execute("""UPDATE course_gradebook_entries SET
                coursework_mark=COALESCE(coursework_mark, assignment_score * 0.10),
                week7_exam_mark=COALESCE(week7_exam_mark, midterm_score * 0.30),
                week12_exam_mark=COALESCE(week12_exam_mark, 0),
                final_exam_mark=COALESCE(final_exam_mark, final_score * 0.40)""")
            with self.dataset_path.open(newline="", encoding="utf-8") as dataset:
                for row in csv.DictReader(dataset):
                    student_id = row["student_id"].strip()
                    connection.execute(
                        """
                        INSERT INTO students (student_id, name, major, year, gpa)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(student_id) DO UPDATE SET
                            name=excluded.name,
                            major=excluded.major,
                            year=excluded.year,
                            gpa=excluded.gpa
                        """,
                        (
                            student_id,
                            row["name"].strip(),
                            row["major"].strip(),
                            int(row["year"]),
                            float(row["gpa"]),
                        ),
                    )
                    courses = [
                        course.strip()
                        for course in row["courses"].split("|")
                        if course.strip()
                    ]
                    connection.executemany(
                        """INSERT INTO courses (student_id, course_name)
                           VALUES (?, ?)
                           ON CONFLICT(student_id, course_name) DO NOTHING""",
                        ((student_id, course) for course in courses),
                    )
            self._seed_prototype_academic_data(connection)
            current_week = academic_week(FALL_2026_START_DATE)
            connection.execute(
                """UPDATE semester_calendar
                   SET current_week=?,
                       start_date=?,
                       end_date=COALESCE(end_date, '2027-01-31')
                   WHERE semester='Fall 2026'""",
                (current_week, FALL_2026_START_DATE.isoformat()),
            )
            connection.execute(
                """UPDATE assessments
                   SET name='Week 7 exam', weight=30, due_week=7
                   WHERE assessment_id LIKE '%-mid'"""
            )
            self._seed_portal_gradebook(connection)

    @staticmethod
    def _seed_prototype_academic_data(connection: sqlite3.Connection) -> None:
        """Seed only the prototype's missing academic records.

        The initial repository shipped with real prototype registrations but no
        assessments, lectures, or portal materials.  These rows make that same
        SQLite database usable end-to-end until Task 1 supplies imports from a
        production student-information system.
        """
        if connection.execute("SELECT 1 FROM course_offerings LIMIT 1").fetchone():
            return

        semester = "Fall 2026"
        connection.execute(
            "INSERT INTO semester_calendar (semester, current_week) VALUES (?, ?)",
            (semester, 6),
        )
        offerings = [
            ("ai", "Artificial Intelligence"),
            ("os", "Operating Systems"),
            ("se", "Software Engineering"),
            ("ds", "Data Structures"),
            ("oop", "C++ OOP"),
            ("dm", "Discrete Mathematics"),
            ("sec", "Software Security"),
            ("net", "Network Security"),
            ("df", "Digital Forensics"),
        ]
        connection.executemany(
            "INSERT INTO course_offerings (course_id, course_name, semester) VALUES (?, ?, ?)",
            ((course_id, course_name, semester) for course_id, course_name in offerings),
        )

        assessments: list[tuple[str, str, str, str, float, int, str]] = []
        lectures: list[tuple[str, str, int, str, int]] = []
        materials: list[tuple[str, str, str, str, str, str]] = []
        for course_id, course_name in offerings:
            for number in range(1, 7):
                lecture_id = f"{course_id}-l{number}"
                lectures.append((lecture_id, course_id, number, f"{course_name} Lecture {number}", number))
                materials.append((f"{lecture_id}-slides", course_id, f"{course_name} Lecture {number} slides", "slides", lecture_id, None))
            assessments.extend(
                [
                    (f"{course_id}-a1", course_id, "Assignment 1", "assignment", 15, 3, "[\"%s-l1\", \"%s-l2\"]" % (course_id, course_id)),
                    (f"{course_id}-a2", course_id, "Assignment 2", "assignment", 15, 5, "[\"%s-l3\", \"%s-l4\"]" % (course_id, course_id)),
                    (f"{course_id}-lab1", course_id, "Lab 1", "lab", 10, 4, "[\"%s-l2\", \"%s-l3\"]" % (course_id, course_id)),
                    (f"{course_id}-mid", course_id, "Week 7 exam", "midterm", 30, 7, json.dumps([f"{course_id}-l{number}" for number in range(1, 7)])),
                    (f"{course_id}-final", course_id, "Final", "final", 35, 12, json.dumps([f"{course_id}-l{number}" for number in range(1, 7)])),
                ]
            )
        connection.executemany(
            """INSERT INTO lectures (lecture_id, course_id, lecture_number, title, available_week)
               VALUES (?, ?, ?, ?, ?)""",
            lectures,
        )
        connection.executemany(
            """INSERT INTO assessments (assessment_id, course_id, name, assessment_type, weight, due_week, covered_lecture_ids)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            assessments,
        )
        connection.executemany(
            """INSERT INTO course_materials (material_id, course_id, title, material_type, lecture_id, source_url)
               VALUES (?, ?, ?, ?, ?, ?)""",
            materials,
        )

        grades = {
            "231027905": {"ai": (88, 80, 78, 48), "os": (90, 92, 88, 86), "se": (82, 79, 84, 76)},
            "231027906": {"ds": (87, 84, 82, 85), "oop": (89, 86, 90, 88), "dm": (81, 83, 78, 80)},
            "231027907": {"sec": (72, 68, 70, 62), "net": (76, 74, 72, 69), "df": (80, 77, 75, 73)},
        }
        grade_rows = []
        for student_id, courses in grades.items():
            for course_id, values in courses.items():
                for suffix, percentage in zip(("a1", "a2", "lab1", "mid"), values, strict=True):
                    grade_rows.append((student_id, f"{course_id}-{suffix}", percentage, datetime.now(UTC).isoformat()))
        connection.executemany(
            """INSERT INTO student_assessment_grades (student_id, assessment_id, percentage, graded_at)
               VALUES (?, ?, ?, ?)""",
            grade_rows,
        )
        completed_counts = {"231027905": {"ai": 4, "os": 6, "se": 5}, "231027906": {"ds": 6, "oop": 6, "dm": 5}, "231027907": {"sec": 3, "net": 4, "df": 5}}
        progress_rows = []
        for student_id, courses in completed_counts.items():
            for course_id, count in courses.items():
                progress_rows.extend((student_id, f"{course_id}-l{number}", min(number, 6)) for number in range(1, count + 1))
        connection.executemany(
            "INSERT INTO student_lecture_progress (student_id, lecture_id, completed_week) VALUES (?, ?, ?)",
            progress_rows,
        )

    def get_student(self, student_id: str) -> Student | None:
        normalized_id = student_id.strip()
        with self._connect() as connection:
            row = connection.execute(
                "SELECT student_id, name, major, year, gpa FROM students WHERE student_id = ?",
                (normalized_id,),
            ).fetchone()
            if row is None:
                return None
            course_rows = connection.execute(
                """SELECT course_name FROM courses
                   WHERE student_id = ? AND status = 'Current' ORDER BY rowid""",
                (normalized_id,),
            ).fetchall()
        return Student(
            student_id=row["student_id"],
            name=row["name"],
            major=row["major"],
            year=row["year"],
            gpa=row["gpa"],
            courses=tuple(course["course_name"] for course in course_rows),
        )

    def get_registered_students(self) -> list[Student]:
        with self._connect() as connection:
            student_ids = [row["student_id"] for row in connection.execute("SELECT student_id FROM students ORDER BY student_id")]
        return [student for student_id in student_ids if (student := self.get_student(student_id)) is not None]

    def get_semester_planner_source(self, student_id: str) -> dict[str, Any] | None:
        """Provide a data-limited planner source for the local SQLite prototype."""
        student = self.get_student(student_id)
        if student is None:
            return None
        with self._connect() as connection:
            current = connection.execute(
                """SELECT offering.course_id, offering.course_name
                   FROM courses enrollment
                   JOIN course_offerings offering ON offering.course_name = enrollment.course_name
                   WHERE enrollment.student_id = ? AND enrollment.status = 'Current'
                   ORDER BY enrollment.rowid""",
                (student_id,),
            ).fetchall()
            schedules = connection.execute(
                """SELECT course_id, day_of_week, start_minute, end_minute, location
                   FROM course_schedule_slots"""
            ).fetchall()
        courses = [
            {
                "course_id": row["course_id"],
                "course_code": row["course_id"],
                "course_name": row["course_name"],
                "curriculum_semester": student.year * 2,
                "course_type": "Current",
            }
            for row in current
        ]
        return {
            "student": {
                "student_id": student.student_id,
                "current_semester": max(1, student.year * 2 - 1),
                "gpa": student.gpa,
            },
            "courses": courses,
            "enrollments": [
                {"course_id": row["course_id"], "status": "Current"}
                for row in current
            ],
            "prerequisites": [],
            "schedules": [dict(row) for row in schedules],
            "schedule_data_available": bool(schedules),
        }

    def get_student_current_courses(self, student_id: str) -> dict[str, Any] | None:
        student = self.get_student(student_id)
        if student is None:
            return None
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT offering.course_id AS course_code,
                          offering.course_name, 'Current' AS status,
                          offering.semester, slot.day_of_week,
                          slot.start_minute, slot.end_minute, slot.location
                   FROM courses enrollment
                   JOIN course_offerings offering
                     ON offering.course_name = enrollment.course_name
                   LEFT JOIN course_schedule_slots slot
                     ON slot.course_id = offering.course_id
                   WHERE enrollment.student_id = ? AND enrollment.status = 'Current'
                   ORDER BY offering.course_name, slot.day_of_week,
                            slot.start_minute""",
                (student.student_id,),
            ).fetchall()
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
        with self._connect() as connection:
            connection.execute(
                f"""INSERT INTO material_documents ({', '.join(fields)})
                    VALUES ({', '.join('?' for _ in fields)})
                    ON CONFLICT(document_id) DO UPDATE SET
                      course_id=excluded.course_id,
                      course_name=excluded.course_name,
                      major_code=excluded.major_code,
                      program_semester=excluded.program_semester,
                      title=excluded.title,
                      category=excluded.category,
                      week_number=excluded.week_number,
                      original_filename=excluded.original_filename,
                      source_archive_path=excluded.source_archive_path,
                      storage_provider=excluded.storage_provider,
                      storage_path=excluded.storage_path,
                      mime_type=excluded.mime_type,
                      checksum=excluded.checksum,
                      size_bytes=excluded.size_bytes,
                      page_count=excluded.page_count,
                      visibility=excluded.visibility,
                      status=excluded.status,
                      updated_at=excluded.updated_at""",
                tuple(document.get(field) for field in fields),
            )

    def replace_material_chunks(
        self, document_id: str, chunks: list[dict[str, Any]]
    ) -> None:
        with self._connect() as connection:
            old_ids = [
                row["chunk_id"]
                for row in connection.execute(
                    "SELECT chunk_id FROM material_chunks WHERE document_id = ?",
                    (document_id,),
                )
            ]
            connection.executemany(
                "DELETE FROM material_chunks_fts WHERE chunk_id = ?",
                ((chunk_id,) for chunk_id in old_ids),
            )
            connection.execute(
                "DELETE FROM material_chunks WHERE document_id = ?", (document_id,)
            )
            document = connection.execute(
                "SELECT title, course_name FROM material_documents WHERE document_id = ?",
                (document_id,),
            ).fetchone()
            if document is None:
                raise ValueError(f"Unknown material document: {document_id}")
            connection.executemany(
                """INSERT INTO material_chunks
                   (chunk_id, document_id, chunk_index, content, page_start,
                    page_end, token_count, embedding_json)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    (
                        chunk["chunk_id"], document_id, chunk["chunk_index"],
                        chunk["content"], chunk.get("page_start"),
                        chunk.get("page_end"), chunk["token_count"],
                        json.dumps(chunk["embedding"], separators=(",", ":")),
                    )
                    for chunk in chunks
                ),
            )
            connection.executemany(
                """INSERT INTO material_chunks_fts
                   (chunk_id, content, title, course_name) VALUES (?, ?, ?, ?)""",
                (
                    (
                        chunk["chunk_id"], chunk["content"],
                        document["title"], document["course_name"],
                    )
                    for chunk in chunks
                ),
            )

    def upsert_material_summary(
        self, document_id: str, summary: dict[str, Any]
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """INSERT INTO material_summaries
                   (document_id, summary, learning_objectives_json,
                    keywords_json, generator, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?)
                   ON CONFLICT(document_id) DO UPDATE SET
                     summary=excluded.summary,
                     learning_objectives_json=excluded.learning_objectives_json,
                     keywords_json=excluded.keywords_json,
                     generator=excluded.generator,
                     updated_at=excluded.updated_at""",
                (
                    document_id,
                    summary.get("summary", ""),
                    json.dumps(summary.get("learning_objectives", [])),
                    json.dumps(summary.get("keywords", [])),
                    summary.get("generator", "unknown"),
                    datetime.now(UTC).isoformat(),
                ),
            )

    def save_material_ingestion_job(self, job: dict[str, Any]) -> None:
        with self._connect() as connection:
            connection.execute(
                """INSERT INTO material_ingestion_jobs
                   (job_id, source, status, report_json, started_at, finished_at)
                   VALUES (?, ?, ?, ?, ?, ?)
                   ON CONFLICT(job_id) DO UPDATE SET
                     status=excluded.status,
                     report_json=excluded.report_json,
                     finished_at=excluded.finished_at""",
                (
                    job["job_id"], job["source"], job["status"],
                    json.dumps(job, ensure_ascii=False), job["started_at"],
                    job.get("finished_at"),
                ),
            )

    def list_student_materials(
        self, student_id: str, course_id: str | None = None
    ) -> list[dict[str, Any]]:
        student = self.get_student(student_id)
        if student is None:
            return []
        current_semester = max(1, student.year * 2 - 1)
        parameters: list[Any] = [student.major.casefold(), current_semester]
        course_filter = ""
        if course_id:
            course_filter = " AND document.course_id = ?"
            parameters.append(course_id)
        with self._connect() as connection:
            rows = connection.execute(
                f"""SELECT document.*, summary.summary,
                           summary.learning_objectives_json,
                           summary.keywords_json
                    FROM material_documents document
                    LEFT JOIN material_summaries summary
                      ON summary.document_id = document.document_id
                    WHERE lower(document.major_code) IN ('cs', 'computer science')
                      AND ? IN ('computer science', 'cs')
                      AND document.program_semester = ?
                      AND document.visibility IN ('student', 'student_practice')
                      {course_filter}
                    ORDER BY document.course_name, document.week_number,
                             document.category, document.title""",
                parameters,
            ).fetchall()
        return [dict(row) for row in rows]

    def search_student_materials(
        self,
        student_id: str,
        query: str,
        *,
        course_id: str | None = None,
        limit: int = 8,
    ) -> list[dict[str, Any]]:
        from backend.materials.retrieval import (
            cosine_similarity,
            embed_text,
            requested_week,
            search_terms,
        )

        documents = self.list_student_materials(student_id, course_id)
        if not documents:
            return []
        week_number = requested_week(query)
        if week_number is not None:
            exact_week_documents = [
                document
                for document in documents
                if document.get("week_number") == week_number
            ]
            if exact_week_documents:
                documents = exact_week_documents
        document_ids = {str(document["document_id"]) for document in documents}
        metadata = {str(document["document_id"]): document for document in documents}
        placeholders = ", ".join("?" for _ in document_ids)
        with self._connect() as connection:
            rows = connection.execute(
                f"""SELECT * FROM material_chunks
                    WHERE document_id IN ({placeholders})""",
                tuple(document_ids),
            ).fetchall()
        query_terms = set(search_terms(query))
        query_embedding = embed_text(query)
        ranked: list[tuple[float, dict[str, Any]]] = []
        for row in rows:
            item = dict(row)
            document = metadata[str(item["document_id"])]
            content_terms = set(
                search_terms(
                    f"{document['title']} {document['course_name']} {item['content']}"
                )
            )
            lexical = len(query_terms & content_terms) / max(1, len(query_terms))
            semantic = cosine_similarity(
                query_embedding, json.loads(str(item["embedding_json"]))
            )
            score = lexical * 0.65 + max(0.0, semantic) * 0.35
            ranked.append(
                (
                    score,
                    {
                        "chunk_id": item["chunk_id"],
                        "document_id": item["document_id"],
                        "course_id": document["course_id"],
                        "course_name": document["course_name"],
                        "title": document["title"],
                        "category": document["category"],
                        "week_number": document["week_number"],
                        "page_start": item["page_start"],
                        "page_end": item["page_end"],
                        "content": item["content"],
                        "storage_path": document["storage_path"],
                        "score": round(score, 6),
                    },
                )
            )
        ranked.sort(key=lambda value: (-value[0], value[1]["course_name"], value[1]["title"]))
        return [item for score, item in ranked[:limit] if score > 0]

    @staticmethod
    def _seed_portal_gradebook(connection: sqlite3.Connection) -> None:
        if connection.execute("SELECT 1 FROM course_gradebook_entries LIMIT 1").fetchone():
            return

        enrollments = connection.execute(
            """SELECT enrollment.student_id, offering.course_id, offering.semester
               FROM courses enrollment
               JOIN course_offerings offering ON offering.course_name = enrollment.course_name
               WHERE enrollment.status = 'Current'
               ORDER BY enrollment.student_id, offering.course_name"""
        ).fetchall()
        now = datetime.now(UTC).isoformat()
        rows: list[tuple[str, str, str, float, float, float, str, str]] = []
        for enrollment in enrollments:
            assessment_rows = connection.execute(
                """SELECT assessment.assessment_type, grade.percentage
                   FROM assessments assessment
                   LEFT JOIN student_assessment_grades grade
                     ON grade.assessment_id = assessment.assessment_id
                    AND grade.student_id = ?
                   WHERE assessment.course_id = ?""",
                (enrollment["student_id"], enrollment["course_id"]),
            ).fetchall()
            assignment_scores = [
                float(row["percentage"])
                for row in assessment_rows
                if row["assessment_type"] in {"assignment", "lab"} and row["percentage"] is not None
            ]
            assignment_score = round(sum(assignment_scores) / len(assignment_scores), 2) if assignment_scores else 0.0
            midterm_score = next(
                (float(row["percentage"]) for row in assessment_rows if row["assessment_type"] in {"midterm", "exam"} and row["percentage"] is not None),
                0.0,
            )
            final_score = next(
                (float(row["percentage"]) for row in assessment_rows if row["assessment_type"] == "final" and row["percentage"] is not None),
                0.0,
            )
            rows.append(
                (
                    enrollment["student_id"],
                    enrollment["course_id"],
                    enrollment["semester"],
                    assignment_score,
                    midterm_score,
                    final_score,
                    now,
                    now,
                )
            )
        connection.executemany(
            """INSERT INTO course_gradebook_entries
               (student_id, course_id, semester, assignment_score, midterm_score, final_score, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(student_id, course_id, semester) DO NOTHING""",
            rows,
        )

    def list_portal_courses(self) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT offering.course_id, offering.course_name, offering.semester,
                          COUNT(enrollment.student_id) AS student_count
                   FROM course_offerings offering
                   LEFT JOIN courses enrollment
                     ON enrollment.course_name = offering.course_name
                    AND enrollment.status = 'Current'
                   GROUP BY offering.course_id, offering.course_name, offering.semester
                   ORDER BY offering.semester DESC, offering.course_name"""
            ).fetchall()
        return [dict(row) for row in rows]

    def get_portal_course_gradebook(
        self, course_id: str, semester: str | None = None
    ) -> dict[str, Any] | None:
        with self._connect() as connection:
            if semester is None:
                course = connection.execute(
                    """SELECT course_id, course_name, semester
                       FROM course_offerings
                       WHERE course_id = ?
                       ORDER BY semester DESC
                       LIMIT 1""",
                    (course_id,),
                ).fetchone()
            else:
                course = connection.execute(
                    """SELECT course_id, course_name, semester
                       FROM course_offerings
                       WHERE course_id = ? AND semester = ?""",
                    (course_id, semester),
                ).fetchone()
            if course is None:
                return None

            rows = connection.execute(
                """SELECT student.student_id, student.name AS student_name,
                          COALESCE(grade.coursework_mark, 0) AS coursework_mark,
                          COALESCE(grade.week7_exam_mark, 0) AS week7_exam_mark,
                          COALESCE(grade.week12_exam_mark, 0) AS week12_exam_mark,
                          COALESCE(grade.final_exam_mark, 0) AS final_exam_mark
                   FROM courses enrollment
                   JOIN students student ON student.student_id = enrollment.student_id
                   JOIN course_offerings offering ON offering.course_name = enrollment.course_name
                   LEFT JOIN course_gradebook_entries grade
                     ON grade.student_id = student.student_id
                    AND grade.course_id = offering.course_id
                    AND grade.semester = offering.semester
                   WHERE offering.course_id = ? AND offering.semester = ?
                     AND enrollment.status = 'Current'
                   ORDER BY student.name""",
                (course["course_id"], course["semester"]),
            ).fetchall()
        return {**dict(course), "rows": [dict(row) for row in rows]}

    def save_portal_course_gradebook(
        self, course_id: str, semester: str, rows: list[dict[str, Any]]
    ) -> None:
        now = datetime.now(UTC).isoformat()
        values = [
            (row["student_id"], course_id, semester,
             row["coursework_mark"] * 10, row["week7_exam_mark"] * (100/30), row["final_exam_mark"] * 2.5,
             row["coursework_mark"], row["week7_exam_mark"], row["week12_exam_mark"], row["final_exam_mark"], now, now)
            for row in rows
        ]
        grade_values = []
        for row in rows:
            assignment_score = row["coursework_mark"] * 10
            midterm_score = row["week7_exam_mark"] * (100/30)
            final_score = row["final_exam_mark"] * 2.5
            grade_values.extend(
                [
                    (row["student_id"], f"{course_id}-a1", assignment_score, now),
                    (row["student_id"], f"{course_id}-a2", assignment_score, now),
                    (row["student_id"], f"{course_id}-lab1", assignment_score, now),
                    (row["student_id"], f"{course_id}-mid", midterm_score, now),
                    (row["student_id"], f"{course_id}-final", final_score, now),
                ]
            )
        with self._connect() as connection:
            connection.executemany(
                """INSERT INTO course_gradebook_entries
                   (student_id, course_id, semester, assignment_score, midterm_score, final_score, coursework_mark, week7_exam_mark, week12_exam_mark, final_exam_mark, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(student_id, course_id, semester) DO UPDATE SET
                     assignment_score=excluded.assignment_score,
                     midterm_score=excluded.midterm_score,
                     final_score=excluded.final_score,
                     coursework_mark=excluded.coursework_mark, week7_exam_mark=excluded.week7_exam_mark,
                     week12_exam_mark=excluded.week12_exam_mark, final_exam_mark=excluded.final_exam_mark,
                     updated_at=excluded.updated_at""",
                values,
            )
            connection.executemany(
                """INSERT INTO student_assessment_grades (student_id, assessment_id, percentage, graded_at)
                   VALUES (?, ?, ?, ?)
                   ON CONFLICT(student_id, assessment_id) DO UPDATE SET
                     percentage=excluded.percentage,
                     graded_at=excluded.graded_at""",
                grade_values,
            )

    def get_student_portal_grade_report(self, student_id: str) -> dict[str, Any] | None:
        student = self.get_student(student_id)
        if student is None:
            return None
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT offering.course_id, offering.course_id AS course_code,
                          offering.course_name, offering.semester,
                          enrollment.status AS enrollment_status,
                          NULL AS stored_letter_grade,
                          CASE WHEN grade.student_id IS NULL THEN 'none' ELSE 'gradebook' END AS grade_source,
                          grade.coursework_mark,
                          grade.week7_exam_mark,
                          grade.week12_exam_mark,
                          grade.final_exam_mark,
                          grade.updated_at AS grade_updated_at
                   FROM courses enrollment
                   JOIN course_offerings offering ON offering.course_name = enrollment.course_name
                   LEFT JOIN course_gradebook_entries grade
                     ON grade.student_id = enrollment.student_id
                    AND grade.course_id = offering.course_id
                    AND grade.semester = offering.semester
                   WHERE enrollment.student_id = ?
                   ORDER BY offering.semester DESC, offering.course_name""",
                (student_id,),
            ).fetchall()
        return {"student": student.as_dict(), "records": [dict(row) for row in rows]}

    def get_portal_course_attendance(
        self, course_id: str, session_date: date
    ) -> dict[str, Any] | None:
        with self._connect() as connection:
            course = connection.execute(
                """SELECT offering.course_id, offering.course_name,
                          offering.semester, calendar.current_week,
                          calendar.start_date, calendar.end_date
                   FROM course_offerings offering
                   JOIN semester_calendar calendar
                     ON calendar.semester = offering.semester
                   WHERE offering.course_id = ?""",
                (course_id,),
            ).fetchone()
            if course is None:
                return None

            if course["start_date"]:
                start_date = date.fromisoformat(str(course["start_date"]))
                week_number = ((session_date - start_date).days // 7) + 1
            else:
                week_number = int(course["current_week"])
            if week_number < 1 or week_number > 16:
                raise ValueError("Attendance date must fall within the 16 teaching weeks")

            rows = connection.execute(
                """SELECT student.student_id, student.name AS student_name,
                          COALESCE(record.status, 'Present') AS status,
                          enrollment.status AS enrollment_status,
                          (
                            SELECT COUNT(*) FROM attendance history
                            WHERE history.student_id = student.student_id
                              AND history.course_code = offering.course_id
                              AND history.semester_id = offering.semester
                              AND history.status = 'Absent'
                          ) AS absence_count
                   FROM courses enrollment
                   JOIN students student ON student.student_id = enrollment.student_id
                   JOIN course_offerings offering
                     ON offering.course_name = enrollment.course_name
                   LEFT JOIN attendance record
                     ON record.student_id = student.student_id
                    AND record.course_code = offering.course_id
                    AND record.semester_id = offering.semester
                    AND record.week_number = ?
                   WHERE offering.course_id = ?
                     AND (enrollment.status = 'Current' OR record.attendance_id IS NOT NULL)
                   ORDER BY student.name""",
                (week_number, course_id),
            ).fetchall()

        return {
            "course": {
                "course_id": course["course_id"],
                "course_name": course["course_name"],
                "semester": course["semester"],
            },
            "session_date": session_date.isoformat(),
            "week_number": week_number,
            "rows": [dict(row) for row in rows],
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

        semester = str(attendance["course"]["semester"])
        week_number = int(attendance["week_number"])
        now = datetime.now(UTC).isoformat()
        dropped_student_ids: list[str] = []
        restored_student_ids: list[str] = []
        with self._connect() as connection:
            connection.executemany(
                """INSERT INTO attendance
                   (student_id, course_code, semester_id, week_number,
                    session_date, status, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(student_id, course_code, semester_id, week_number)
                   DO UPDATE SET session_date=excluded.session_date,
                                 status=excluded.status""",
                (
                    (
                        str(row["student_id"]), course_id, semester, week_number,
                        session_date.isoformat(), str(row["status"]), now,
                    )
                    for row in rows
                ),
            )
            course_name = str(attendance["course"]["course_name"])
            for row in rows:
                student_id = str(row["student_id"])
                absence_count = int(
                    connection.execute(
                        """SELECT COUNT(*) FROM attendance
                           WHERE student_id = ? AND course_code = ?
                             AND semester_id = ? AND status = 'Absent'""",
                        (student_id, course_id, semester),
                    ).fetchone()[0]
                )
                tracked = connection.execute(
                    """SELECT 1 FROM attendance_auto_drops
                       WHERE student_id = ? AND course_code = ? AND semester_id = ?""",
                    (student_id, course_id, semester),
                ).fetchone()
                if absence_count >= 4:
                    connection.execute(
                        """INSERT INTO attendance_auto_drops
                           (student_id, course_code, semester_id, dropped_at)
                           VALUES (?, ?, ?, ?)
                           ON CONFLICT(student_id, course_code, semester_id) DO NOTHING""",
                        (student_id, course_id, semester, now),
                    )
                    changed = connection.execute(
                        """UPDATE courses SET status = 'Withdrawn'
                           WHERE student_id = ? AND course_name = ? AND status = 'Current'""",
                        (student_id, course_name),
                    ).rowcount
                    if changed:
                        dropped_student_ids.append(student_id)
                elif tracked is not None:
                    connection.execute(
                        """DELETE FROM attendance_auto_drops
                           WHERE student_id = ? AND course_code = ? AND semester_id = ?""",
                        (student_id, course_id, semester),
                    )
                    changed = connection.execute(
                        """UPDATE courses SET status = 'Current'
                           WHERE student_id = ? AND course_name = ? AND status = 'Withdrawn'""",
                        (student_id, course_name),
                    ).rowcount
                    if changed:
                        restored_student_ids.append(student_id)

        refreshed = self.get_portal_course_attendance(course_id, session_date)
        assert refreshed is not None
        return {
            **refreshed,
            "dropped_student_ids": dropped_student_ids,
            "restored_student_ids": restored_student_ids,
        }

    def get_attendance_alerts(self, student_id: str) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT record.course_code AS course_id,
                          offering.course_name, record.semester_id AS semester,
                          COUNT(*) AS absence_count,
                          CASE WHEN auto_drop.student_id IS NULL THEN 0 ELSE 1 END
                            AS automatically_dropped
                   FROM attendance record
                   JOIN course_offerings offering
                     ON offering.course_id = record.course_code
                   LEFT JOIN attendance_auto_drops auto_drop
                     ON auto_drop.student_id = record.student_id
                    AND auto_drop.course_code = record.course_code
                    AND auto_drop.semester_id = record.semester_id
                   WHERE record.student_id = ? AND record.status = 'Absent'
                   GROUP BY record.course_code, offering.course_name,
                            record.semester_id, auto_drop.student_id
                   HAVING COUNT(*) >= 3
                   ORDER BY record.semester_id DESC, offering.course_name""",
                (student_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_read_notification_ids(self, student_id: str) -> set[str]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT notification_id FROM portal_notification_reads WHERE student_id = ?",
                (student_id,),
            ).fetchall()
        return {str(row["notification_id"]) for row in rows}

    def get_stored_notifications(self, student_id: str) -> list[dict[str, Any]]:
        """Return persisted notifications supported by the production backend.

        SQLite is the local/test backend and does not persist source-system
        notifications, so it exposes the shared repository interface with an
        empty result.
        """
        return []

    def set_notifications_read(
        self, student_id: str, notification_ids: list[str], read: bool
    ) -> None:
        if not notification_ids:
            return
        with self._connect() as connection:
            if read:
                read_at = datetime.now(UTC).isoformat()
                connection.executemany(
                    """INSERT INTO portal_notification_reads
                       (student_id, notification_id, read_at) VALUES (?, ?, ?)
                       ON CONFLICT(student_id, notification_id) DO UPDATE SET
                         read_at=excluded.read_at""",
                    ((student_id, notification_id, read_at) for notification_id in notification_ids),
                )
            else:
                placeholders = ", ".join("?" for _ in notification_ids)
                connection.execute(
                    f"""DELETE FROM portal_notification_reads
                        WHERE student_id = ? AND notification_id IN ({placeholders})""",
                    (student_id, *notification_ids),
                )

    def get_weekly_plan_items(
        self, student_id: str, semester: str, week_number: int
    ) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT task_id, course_id, course_name, title, detail,
                          task_type, status, position, completed_at
                   FROM weekly_plan_items
                   WHERE student_id = ? AND semester = ? AND week_number = ?
                   ORDER BY position, created_at, task_id""",
                (student_id, semester, week_number),
            ).fetchall()
        return [dict(row) for row in rows]

    def upsert_weekly_plan_items(
        self,
        student_id: str,
        semester: str,
        week_number: int,
        items: list[dict[str, Any]],
    ) -> None:
        if not items:
            return
        timestamp = datetime.now(UTC).isoformat()
        with self._connect() as connection:
            connection.executemany(
                """INSERT INTO weekly_plan_items
                   (task_id, student_id, semester, week_number, course_id,
                    course_name, title, detail, task_type, status, position,
                    created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
                   ON CONFLICT(task_id) DO UPDATE SET
                     course_name=excluded.course_name,
                     title=excluded.title,
                     detail=excluded.detail,
                     position=excluded.position""",
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
                        timestamp,
                        timestamp,
                    )
                    for item in items
                ),
            )

    def set_weekly_plan_item_status(
        self, student_id: str, task_id: str, status: str
    ) -> dict[str, Any] | None:
        if status not in {"pending", "completed"}:
            raise ValueError("Weekly plan status must be pending or completed")
        timestamp = datetime.now(UTC).isoformat()
        completed_at = timestamp if status == "completed" else None
        with self._connect() as connection:
            connection.execute(
                """UPDATE weekly_plan_items
                   SET status = ?, completed_at = ?, updated_at = ?
                   WHERE student_id = ? AND task_id = ?""",
                (status, completed_at, timestamp, student_id, task_id),
            )
            row = connection.execute(
                """SELECT task_id, course_id, course_name, title, detail,
                          task_type, status, position, completed_at
                   FROM weekly_plan_items
                   WHERE student_id = ? AND task_id = ?""",
                (student_id, task_id),
            ).fetchone()
        return dict(row) if row is not None else None

    def get_student_progress(self, student_id: str) -> dict[str, Any] | None:
        """Return authoritative academic records for one registered student."""
        student = self.get_student(student_id)
        if student is None:
            return None
        with self._connect() as connection:
            course_rows = connection.execute(
                """SELECT offering.course_id, offering.course_name, offering.semester,
                          calendar.current_week, calendar.start_date
                   FROM courses enrollment
                   JOIN course_offerings offering ON offering.course_name = enrollment.course_name
                   JOIN semester_calendar calendar ON calendar.semester = offering.semester
                   WHERE enrollment.student_id = ? AND enrollment.status = 'Current'
                   ORDER BY enrollment.rowid""",
                (student.student_id,),
            ).fetchall()
            courses: list[dict[str, Any]] = []
            for course in course_rows:
                course_id = course["course_id"]
                current_week = (
                    academic_week(date.fromisoformat(str(course["start_date"])))
                    if course["start_date"]
                    else int(course["current_week"])
                )
                assessments = [dict(row) for row in connection.execute(
                    """SELECT assessment.assessment_id, assessment.name, assessment.assessment_type,
                              assessment.weight, assessment.due_week, assessment.covered_lecture_ids,
                              grade.percentage
                       FROM assessments assessment
                       LEFT JOIN student_assessment_grades grade
                         ON grade.assessment_id = assessment.assessment_id AND grade.student_id = ?
                       WHERE assessment.course_id = ? ORDER BY assessment.due_week, assessment.assessment_id""",
                    (student.student_id, course_id),
                )]
                lectures = [dict(row) for row in connection.execute(
                    """SELECT lecture.lecture_id, lecture.lecture_number, lecture.title, lecture.available_week,
                              CASE WHEN progress.lecture_id IS NULL THEN 0 ELSE 1 END AS completed
                       FROM lectures lecture
                       LEFT JOIN student_lecture_progress progress
                         ON progress.lecture_id = lecture.lecture_id AND progress.student_id = ?
                       WHERE lecture.course_id = ? ORDER BY lecture.lecture_number""",
                    (student.student_id, course_id),
                )]
                materials = [dict(row) for row in connection.execute(
                    "SELECT material_id, title, material_type, lecture_id, source_url FROM course_materials WHERE course_id = ? ORDER BY title",
                    (course_id,),
                )]
                course_record = dict(course)
                course_record.pop("start_date", None)
                course_record["current_week"] = current_week
                courses.append({**course_record, "assessments": assessments, "lectures": lectures, "materials": materials})
        return {
            "student": student.as_dict(),
            "semester": "Fall 2026",
            "current_week": academic_week(FALL_2026_START_DATE),
            "courses": courses,
        }

    def get_previous_course_snapshot(self, student_id: str, course_id: str, week_number: int) -> dict[str, Any] | None:
        with self._connect() as connection:
            row = connection.execute(
                """SELECT * FROM weekly_progress_snapshots
                   WHERE student_id = ? AND course_id = ? AND week_number < ?
                   ORDER BY week_number DESC LIMIT 1""",
                (student_id, course_id, week_number),
            ).fetchone()
        return dict(row) if row else None

    def get_weekly_snapshots(self, student_id: str) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT snapshot.*, offering.course_name FROM weekly_progress_snapshots snapshot
                   JOIN course_offerings offering ON offering.course_id = snapshot.course_id
                   WHERE snapshot.student_id = ? ORDER BY snapshot.week_number, offering.course_name""",
                (student_id,),
            ).fetchall()
        return [dict(row) for row in rows]

    def save_weekly_snapshot(self, student_id: str, course_id: str, week_number: int, metrics: dict[str, Any]) -> None:
        values = (
            student_id, course_id, week_number, metrics.get("assignment_average"), metrics.get("lab_average"),
            metrics.get("quiz_average"), metrics.get("exam_percentage"), metrics.get("weighted_grade"),
            metrics["lecture_completion"], metrics["assessment_completion"], metrics["course_health"],
            metrics["risk_level"], metrics["trend"], datetime.now(UTC).isoformat(),
        )
        with self._connect() as connection:
            connection.execute(
                """INSERT INTO weekly_progress_snapshots
                   (student_id, course_id, week_number, assignment_average, lab_average, quiz_average,
                    exam_percentage, weighted_grade, lecture_completion, assessment_completion,
                    course_health, risk_level, trend, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(student_id, course_id, week_number) DO UPDATE SET
                     assignment_average=excluded.assignment_average, lab_average=excluded.lab_average,
                     quiz_average=excluded.quiz_average, exam_percentage=excluded.exam_percentage,
                     weighted_grade=excluded.weighted_grade, lecture_completion=excluded.lecture_completion,
                     assessment_completion=excluded.assessment_completion, course_health=excluded.course_health,
                     risk_level=excluded.risk_level, trend=excluded.trend, created_at=excluded.created_at""",
                values,
            )

    def has_active_intervention(self, student_id: str, course_id: str, fingerprint: str) -> bool:
        with self._connect() as connection:
            return connection.execute(
                """SELECT 1 FROM progress_interventions
                   WHERE student_id = ? AND course_id = ? AND issue_fingerprint = ? AND status = 'active'
                   LIMIT 1""",
                (student_id, course_id, fingerprint),
            ).fetchone() is not None

    def save_intervention(
        self, student_id: str, course_id: str, week_number: int,
        intervention: dict[str, Any], fingerprint: str,
        course_health_at_creation: float | None = None,
    ) -> int:
        with self._connect() as connection:
            cursor = connection.execute(
                """INSERT INTO progress_interventions
                   (student_id, course_id, week_number, severity, reason, weak_topics_json, lecture_ids_json,
                    recommended_actions_json, message, issue_fingerprint, status, course_health_at_creation,
                    created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (student_id, course_id, week_number, intervention["severity"], intervention["reason"],
                 json.dumps(intervention.get("weak_topics", [])), json.dumps(intervention.get("lectures_to_review", [])),
                 json.dumps(intervention.get("recommended_actions", [])), intervention["message"], fingerprint,
                 intervention.get("status", "active"), course_health_at_creation,
                 datetime.now(UTC).isoformat()),
            )
        return int(cursor.lastrowid)

    def get_active_interventions(
        self, student_id: str, course_id: str | None = None
    ) -> list[dict[str, Any]]:
        query = """SELECT intervention.*, offering.course_name FROM progress_interventions intervention
                   JOIN course_offerings offering ON offering.course_id = intervention.course_id
                   WHERE intervention.student_id = ? AND intervention.status = 'active'"""
        parameters: list[Any] = [student_id]
        if course_id is not None:
            query += " AND intervention.course_id = ?"
            parameters.append(course_id)
        query += " ORDER BY intervention.created_at DESC"
        with self._connect() as connection:
            rows = connection.execute(query, parameters).fetchall()
        return self._decode_intervention_rows(rows)

    def update_intervention_status(
        self,
        intervention_id: int,
        status: str,
        resolved_week: int | None = None,
        resolution_outcome: str | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """UPDATE progress_interventions
                   SET status = ?, resolved_week = ?, resolution_outcome = ?
                   WHERE intervention_id = ?""",
                (status, resolved_week, resolution_outcome, intervention_id),
            )

    def get_interventions(self, student_id: str) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT intervention.*, offering.course_name FROM progress_interventions intervention
                   JOIN course_offerings offering ON offering.course_id = intervention.course_id
                   WHERE intervention.student_id = ? ORDER BY intervention.created_at DESC""",
                (student_id,),
            ).fetchall()
        return self._decode_intervention_rows(rows)

    @staticmethod
    def _decode_intervention_rows(rows: list[sqlite3.Row]) -> list[dict[str, Any]]:
        results = []
        for row in rows:
            record = dict(row)
            record["weak_topics"] = json.loads(record.pop("weak_topics_json"))
            record["lectures_to_review"] = json.loads(record.pop("lecture_ids_json"))
            record["recommended_actions"] = json.loads(record.pop("recommended_actions_json"))
            results.append(record)
        return results

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
        now = datetime.now(UTC).isoformat()
        with self._connect() as connection:
            connection.execute(
                """INSERT INTO student_semester_grades
                   (student_id, course_id, semester, week_number, assignment_grade,
                    lab_grade, exam_grade, exam_weight, coursework_grade, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(student_id, course_id, semester, week_number) DO UPDATE SET
                     assignment_grade=excluded.assignment_grade,
                     lab_grade=excluded.lab_grade,
                     exam_grade=excluded.exam_grade,
                     exam_weight=excluded.exam_weight,
                     coursework_grade=excluded.coursework_grade,
                     updated_at=excluded.updated_at""",
                (
                    student_id, course_id, semester, week_number,
                    assignment_grade, lab_grade, exam_grade, exam_weight, coursework_grade,
                    now, now,
                ),
            )

    def get_semester_grades(
        self, student_id: str, course_id: str, semester: str
    ) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT * FROM student_semester_grades
                   WHERE student_id = ? AND course_id = ? AND semester = ?
                   ORDER BY week_number""",
                (student_id, course_id, semester),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_semester_grade_summary(
        self, student_id: str, course_id: str, semester: str
    ) -> dict[str, Any] | None:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT week_number, exam_grade, exam_weight, coursework_grade
                   FROM student_semester_grades
                   WHERE student_id = ? AND course_id = ? AND semester = ?
                     AND (exam_grade IS NOT NULL OR coursework_grade IS NOT NULL)""",
                (student_id, course_id, semester),
            ).fetchall()
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
