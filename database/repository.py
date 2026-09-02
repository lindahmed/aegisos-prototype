from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


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
                    PRIMARY KEY (student_id, course_name),
                    FOREIGN KEY (student_id) REFERENCES students(student_id)
                );
                CREATE TABLE IF NOT EXISTS semester_calendar (
                    semester TEXT PRIMARY KEY,
                    current_week INTEGER NOT NULL CHECK(current_week >= 1)
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
                """
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
                    connection.execute(
                        "DELETE FROM courses WHERE student_id = ?", (student_id,)
                    )
                    courses = [
                        course.strip()
                        for course in row["courses"].split("|")
                        if course.strip()
                    ]
                    connection.executemany(
                        "INSERT INTO courses (student_id, course_name) VALUES (?, ?)",
                        ((student_id, course) for course in courses),
                    )
            self._seed_prototype_academic_data(connection)
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
                    (f"{course_id}-mid", course_id, "Midterm", "midterm", 25, 6, json.dumps([f"{course_id}-l{number}" for number in range(1, 7)])),
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
                "SELECT course_name FROM courses WHERE student_id = ? ORDER BY rowid",
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

    @staticmethod
    def _seed_portal_gradebook(connection: sqlite3.Connection) -> None:
        if connection.execute("SELECT 1 FROM course_gradebook_entries LIMIT 1").fetchone():
            return

        enrollments = connection.execute(
            """SELECT enrollment.student_id, offering.course_id, offering.semester
               FROM courses enrollment
               JOIN course_offerings offering ON offering.course_name = enrollment.course_name
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
                   LEFT JOIN courses enrollment ON enrollment.course_name = offering.course_name
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
                          'Current' AS enrollment_status,
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

    def get_read_notification_ids(self, student_id: str) -> set[str]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT notification_id FROM portal_notification_reads WHERE student_id = ?",
                (student_id,),
            ).fetchall()
        return {str(row["notification_id"]) for row in rows}

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

    def get_student_progress(self, student_id: str) -> dict[str, Any] | None:
        """Return authoritative academic records for one registered student."""
        student = self.get_student(student_id)
        if student is None:
            return None
        with self._connect() as connection:
            course_rows = connection.execute(
                """SELECT offering.course_id, offering.course_name, offering.semester,
                          calendar.current_week
                   FROM courses enrollment
                   JOIN course_offerings offering ON offering.course_name = enrollment.course_name
                   JOIN semester_calendar calendar ON calendar.semester = offering.semester
                   WHERE enrollment.student_id = ? ORDER BY enrollment.rowid""",
                (student.student_id,),
            ).fetchall()
            courses: list[dict[str, Any]] = []
            for course in course_rows:
                course_id = course["course_id"]
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
                courses.append({**dict(course), "assessments": assessments, "lectures": lectures, "materials": materials})
        return {"student": student.as_dict(), "courses": courses}

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
