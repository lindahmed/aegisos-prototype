from __future__ import annotations

import csv
import sqlite3
from dataclasses import dataclass
from pathlib import Path


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
