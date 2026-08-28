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
    gpa: float
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
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (student_id) REFERENCES students(student_id),
                    FOREIGN KEY (course_id) REFERENCES course_offerings(course_id)
                );
                """
            )
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

    def save_intervention(self, student_id: str, course_id: str, week_number: int, intervention: dict[str, Any], fingerprint: str) -> int:
        with self._connect() as connection:
            cursor = connection.execute(
                """INSERT INTO progress_interventions
                   (student_id, course_id, week_number, severity, reason, weak_topics_json, lecture_ids_json,
                    recommended_actions_json, message, issue_fingerprint, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (student_id, course_id, week_number, intervention["severity"], intervention["reason"],
                 json.dumps(intervention.get("weak_topics", [])), json.dumps(intervention.get("lectures_to_review", [])),
                 json.dumps(intervention.get("recommended_actions", [])), intervention["message"], fingerprint,
                 datetime.now(UTC).isoformat()),
            )
        return int(cursor.lastrowid)

    def get_interventions(self, student_id: str) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                """SELECT intervention.*, offering.course_name FROM progress_interventions intervention
                   JOIN course_offerings offering ON offering.course_id = intervention.course_id
                   WHERE intervention.student_id = ? ORDER BY intervention.created_at DESC""",
                (student_id,),
            ).fetchall()
        results = []
        for row in rows:
            record = dict(row)
            record["weak_topics"] = json.loads(record.pop("weak_topics_json"))
            record["lectures_to_review"] = json.loads(record.pop("lecture_ids_json"))
            record["recommended_actions"] = json.loads(record.pop("recommended_actions_json"))
            results.append(record)
        return results
