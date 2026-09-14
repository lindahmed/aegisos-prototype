"""Synchronize the Neo4j academic graph from the PostgreSQL source of truth.

The PostgreSQL ``courses`` and ``course_prerequisites`` tables are authoritative.
This module deliberately does not contain a second, hand-maintained curriculum.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))


@dataclass
class AcademicGraphSnapshot:
    courses: list[dict[str, Any]]
    prerequisites: list[dict[str, Any]]
    programmes: list[dict[str, Any]] = field(default_factory=list)
    programme_courses: list[dict[str, Any]] = field(default_factory=list)
    electives: list[dict[str, Any]] = field(default_factory=list)
    students: list[dict[str, Any]] = field(default_factory=list)

    def validate(self) -> None:
        """Refuse a destructive replacement when source references are invalid."""
        course_codes = {row["code"] for row in self.courses}
        if len(course_codes) != len(self.courses):
            raise ValueError("The courses table contains duplicate course codes.")

        prerequisite_pairs = {
            (row["course_code"], row["prerequisite_code"])
            for row in self.prerequisites
        }
        if len(prerequisite_pairs) != len(self.prerequisites):
            raise ValueError("The course_prerequisites table contains duplicate rows.")

        referenced_courses = {
            code
            for row in self.prerequisites
            for code in (row["course_code"], row["prerequisite_code"])
        }
        referenced_courses.update(row["course_code"] for row in self.programme_courses)
        referenced_courses.update(row["course_code"] for row in self.electives)
        missing_courses = sorted(referenced_courses - course_codes)
        if missing_courses:
            raise ValueError(
                "Academic relationships reference unknown course codes: "
                + ", ".join(missing_courses)
            )

        programme_codes = {row["code"] for row in self.programmes}
        referenced_programmes = {
            row["programme_code"]
            for row in [*self.programme_courses, *self.electives]
        }
        missing_programmes = sorted(referenced_programmes - programme_codes)
        if missing_programmes:
            raise ValueError(
                "Curriculum rows reference unknown programme codes: "
                + ", ".join(missing_programmes)
            )


def _load_environment() -> None:
    try:
        from dotenv import load_dotenv
    except ImportError:
        return
    load_dotenv(PROJECT_ROOT / ".env")


def _fetch_all(
    cursor: Any, query: str, parameters: tuple[Any, ...] = ()
) -> list[dict[str, Any]]:
    cursor.execute(query, parameters)
    return [dict(row) for row in cursor.fetchall()]


def _table_names(cursor: Any) -> set[str]:
    rows = _fetch_all(
        cursor,
        """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = current_schema() AND table_type = 'BASE TABLE'
        """,
    )
    return {row["table_name"] for row in rows}


def load_academic_snapshot(database_url: str) -> AcademicGraphSnapshot:
    """Read a consistent academic snapshot from PostgreSQL/Supabase."""
    try:
        import psycopg2
        import psycopg2.extras
    except ImportError as error:
        raise RuntimeError(
            "PostgreSQL synchronization requires psycopg2-binary."
        ) from error

    with psycopg2.connect(
        database_url, cursor_factory=psycopg2.extras.RealDictCursor
    ) as connection:
        # Prevent a mixed snapshot if the source changes during synchronization.
        connection.set_session(readonly=True, isolation_level="REPEATABLE READ")
        with connection.cursor() as cursor:
            tables = _table_names(cursor)
            required_tables = {"courses", "course_prerequisites"}
            missing_tables = sorted(required_tables - tables)
            if missing_tables:
                raise RuntimeError(
                    "The academic database is missing required tables: "
                    + ", ".join(missing_tables)
                )

            courses = _fetch_all(
                cursor,
                """
                SELECT course_code AS code, course_title AS title,
                       credit_hours AS credits, is_placeholder
                FROM courses
                ORDER BY course_code
                """,
            )
            for course in courses:
                course["min_credit_hours"] = None
            prerequisites = _fetch_all(
                cursor,
                """
                SELECT course_code, prerequisite_code
                FROM course_prerequisites
                ORDER BY course_code, prerequisite_code
                """,
            )

            programmes: list[dict[str, Any]] = []
            if "programs" in tables:
                programmes = _fetch_all(
                    cursor,
                    """
                    SELECT program_id::text AS programme_id,
                           program_code AS code, program_name AS name
                    FROM programs
                    ORDER BY program_code
                    """,
                )
                for programme in programmes:
                    programme["total_credits_required"] = None

            programme_courses: list[dict[str, Any]] = []
            if "department_plan_courses" in tables and programmes:
                programme_courses = _fetch_all(
                    cursor,
                    """
                    SELECT plan.major_code AS programme_code, plan.course_code,
                           plan.program_semester AS semester
                    FROM department_plan_courses plan
                    JOIN programs programme
                      ON programme.program_code = plan.major_code
                    ORDER BY plan.major_code, plan.program_semester, plan.course_code
                    """,
                )
                credits_by_code = {
                    course["code"]: course["credits"] for course in courses
                }
                plan_codes_by_programme: dict[str, set[str]] = {}
                for row in programme_courses:
                    plan_codes_by_programme.setdefault(
                        row["programme_code"], set()
                    ).add(row["course_code"])
                for programme in programmes:
                    programme["total_credits_required"] = sum(
                        credits_by_code[code]
                        for code in plan_codes_by_programme.get(
                            programme["code"], set()
                        )
                    )

            electives: list[dict[str, Any]] = []
            if "major_electives" in tables and programmes:
                electives = _fetch_all(
                    cursor,
                    """
                    SELECT elective.major_code AS programme_code,
                           elective.course_code
                    FROM major_electives elective
                    JOIN programs programme
                      ON programme.program_code = elective.major_code
                    ORDER BY elective.major_code, elective.course_code
                    """,
                )

            if "course_credit_prerequisites" in tables:
                credit_requirements = _fetch_all(
                    cursor,
                    """
                    SELECT course_code, min_credit_hours
                    FROM course_credit_prerequisites
                    ORDER BY course_code
                    """,
                )
                requirements_by_code = {
                    row["course_code"]: row["min_credit_hours"]
                    for row in credit_requirements
                }
                for course in courses:
                    course["min_credit_hours"] = requirements_by_code.get(
                        course["code"]
                    )

            students: list[dict[str, Any]] = []
            if "students" in tables and programmes:
                students = _fetch_all(
                    cursor,
                    """
                    SELECT student.student_id::text AS student_id,
                           student.full_name AS name,
                           student.program_id::text AS programme_id,
                           student.academic_level, student.current_semester,
                           student.status, student.gpa::float AS gpa
                    FROM students student
                    JOIN programs programme
                      ON programme.program_id = student.program_id
                    ORDER BY student.student_id
                    """,
                )

    snapshot = AcademicGraphSnapshot(
        courses=courses,
        prerequisites=prerequisites,
        programmes=programmes,
        programme_courses=programme_courses,
        electives=electives,
        students=students,
    )
    snapshot.validate()
    return snapshot


def _replace_academic_graph(transaction: Any, snapshot: AcademicGraphSnapshot) -> None:
    # A failed statement rolls back the replacement instead of exposing a
    # partially rebuilt curriculum.
    transaction.run(
        "MATCH (n) WHERE n:Course OR n:Programme OR n:Student DETACH DELETE n"
    ).consume()
    transaction.run(
        """
        UNWIND $rows AS row
        CREATE (course:Course {
            code: row.code,
            title: row.title,
            credits: row.credits,
            is_placeholder: row.is_placeholder,
            min_credit_hours: row.min_credit_hours,
            source: 'postgres'
        })
        """,
        rows=snapshot.courses,
    ).consume()
    transaction.run(
        """
        UNWIND $rows AS row
        CREATE (programme:Programme {
            programme_id: row.programme_id,
            code: row.code,
            name: row.name,
            total_credits_required: row.total_credits_required,
            source: 'postgres'
        })
        """,
        rows=snapshot.programmes,
    ).consume()
    transaction.run(
        """
        UNWIND $rows AS row
        MATCH (prerequisite:Course {code: row.prerequisite_code})
        MATCH (course:Course {code: row.course_code})
        CREATE (prerequisite)-[:PREREQUISITE_FOR]->(course)
        """,
        rows=snapshot.prerequisites,
    ).consume()
    transaction.run(
        """
        UNWIND $rows AS row
        MATCH (programme:Programme {code: row.programme_code})
        MATCH (course:Course {code: row.course_code})
        CREATE (programme)-[:REQUIRES {semester: row.semester}]->(course)
        """,
        rows=snapshot.programme_courses,
    ).consume()
    transaction.run(
        """
        UNWIND $rows AS row
        MATCH (programme:Programme {code: row.programme_code})
        MATCH (course:Course {code: row.course_code})
        CREATE (programme)-[:OFFERS_ELECTIVE]->(course)
        """,
        rows=snapshot.electives,
    ).consume()
    transaction.run(
        """
        UNWIND $rows AS row
        CREATE (student:Student {
            student_id: row.student_id,
            name: row.name,
            academic_level: row.academic_level,
            current_semester: row.current_semester,
            status: row.status,
            gpa: row.gpa,
            source: 'postgres'
        })
        WITH student, row
        MATCH (programme:Programme {programme_id: row.programme_id})
        CREATE (student)-[:ENROLLED_IN]->(programme)
        """,
        rows=snapshot.students,
    ).consume()


def seed_academic_graph(
    uri: str | None = None,
    user: str | None = None,
    password: str | None = None,
    database_url: str | None = None,
    *,
    dry_run: bool = False,
) -> dict[str, int]:
    """Replace Neo4j academic data with a validated PostgreSQL snapshot."""
    _load_environment()
    database_url = database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required to synchronize the academic graph.")

    snapshot = load_academic_snapshot(database_url)
    summary = {
        "courses": len(snapshot.courses),
        "prerequisites": len(snapshot.prerequisites),
        "programmes": len(snapshot.programmes),
        "programme_courses": len(snapshot.programme_courses),
        "electives": len(snapshot.electives),
        "students": len(snapshot.students),
    }
    if dry_run:
        return summary

    try:
        from neo4j import GraphDatabase
    except ImportError as error:
        raise RuntimeError("Neo4j synchronization requires the neo4j package.") from error

    uri = uri or os.getenv("NEO4J_URI", "bolt://localhost:7687")
    user = user or os.getenv("NEO4J_USER", "neo4j")
    password = password or os.getenv("NEO4J_PASSWORD", "password")

    with GraphDatabase.driver(uri, auth=(user, password)) as driver:
        driver.verify_connectivity()
        with driver.session() as session:
            session.execute_write(_replace_academic_graph, snapshot)
            session.run(
                "CREATE CONSTRAINT course_code_unique IF NOT EXISTS "
                "FOR (course:Course) REQUIRE course.code IS UNIQUE"
            ).consume()
            session.run(
                "CREATE CONSTRAINT programme_id_unique IF NOT EXISTS "
                "FOR (programme:Programme) REQUIRE programme.programme_id IS UNIQUE"
            ).consume()
            session.run(
                "CREATE CONSTRAINT programme_code_unique IF NOT EXISTS "
                "FOR (programme:Programme) REQUIRE programme.code IS UNIQUE"
            ).consume()
            session.run(
                "CREATE CONSTRAINT student_id_unique IF NOT EXISTS "
                "FOR (student:Student) REQUIRE student.student_id IS UNIQUE"
            ).consume()

    return summary


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Synchronize Neo4j from the authoritative PostgreSQL curriculum."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate PostgreSQL and print counts without changing Neo4j",
    )
    args = parser.parse_args()
    summary = seed_academic_graph(dry_run=args.dry_run)
    action = "Validated" if args.dry_run else "Synchronized"
    counts = ", ".join(f"{name}={count}" for name, count in summary.items())
    print(f"{action} academic graph: {counts}")


if __name__ == "__main__":
    main()
