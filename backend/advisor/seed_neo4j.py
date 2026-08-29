from __future__ import annotations

import os
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT))


def seed_academic_graph(uri: str | None = None, user: str | None = None, password: str | None = None) -> None:
    """Populate Neo4j with a Computer Science programme, courses, rules, and sample students."""
    try:
        from neo4j import GraphDatabase
    except ImportError as error:
        raise RuntimeError("Neo4j driver not installed. Run: pip install neo4j") from error

    uri = uri or os.getenv("NEO4J_URI", "bolt://localhost:7687")
    user = user or os.getenv("NEO4J_USER", "neo4j")
    password = password or os.getenv("NEO4J_PASSWORD", "password")

    driver = GraphDatabase.driver(uri, auth=(user, password))

    programme = {
        "programme_id": "cs",
        "name": "Bachelor of Computer Science",
        "total_credits_required": 120,
        "elective_credits": 24,
    }

    courses = [
        {"code": "CS101", "title": "Introduction to Programming", "credits": 3},
        {"code": "CS102", "title": "Object-Oriented Programming", "credits": 3},
        {"code": "CS201", "title": "Data Structures", "credits": 3},
        {"code": "CS202", "title": "Algorithms", "credits": 3},
        {"code": "CS301", "title": "Machine Learning", "credits": 3},
        {"code": "CS302", "title": "Deep Learning", "credits": 3},
        {"code": "MATH101", "title": "Calculus I", "credits": 3},
        {"code": "MATH201", "title": "Linear Algebra", "credits": 3},
        {"code": "MATH202", "title": "Probability and Statistics", "credits": 3},
        {"code": "CS210", "title": "Digital Logic Design", "credits": 3},
        {"code": "CS220", "title": "Introduction to Networks", "credits": 3},
        {"code": "CS230", "title": "Database Systems", "credits": 3},
    ]

    prerequisites = [
        ("CS101", "CS102"),
        ("CS101", "CS201"),
        ("CS102", "CS201"),
        ("CS201", "CS202"),
        ("CS201", "CS301"),
        ("CS102", "CS301"),
        ("MATH201", "CS301"),
        ("MATH202", "CS301"),
        ("CS301", "CS302"),
        ("CS102", "CS230"),
    ]

    corequisites = [
        ("MATH202", "CS202"),
    ]

    equivalencies = [
        ("CS101", "CS110"),
    ]

    # Sample academic records. Each student is enrolled in the CS programme,
    # has completed some courses, and is registered for the current semester.
    students = [
        {
            "student_id": "231027905",
            "name": "Mohamed Ali",
            "completed": {"CS101", "CS102", "CS201", "MATH101", "MATH201"},
            "registered": {"CS210", "CS220", "MATH202"},
        },
        {
            "student_id": "231027906",
            "name": "Sara Khan",
            "completed": {"CS101", "CS102", "MATH101", "MATH201"},
            "registered": {"CS201", "CS210", "MATH202"},
        },
        {
            "student_id": "231027907",
            "name": "Omar Hassan",
            "completed": {"CS101", "MATH101"},
            "registered": {"CS102", "MATH201"},
        },
    ]

    with driver.session() as session:
        # Clear previous academic graph data.
        session.run("MATCH (n:Programme|Course|Student) DETACH DELETE n")

        # Create programme.
        session.run(
            """
            CREATE (p:Programme {
                programme_id: $programme_id,
                name: $name,
                total_credits_required: $total_credits_required,
                elective_credits: $elective_credits
            })
            """,
            programme,
        )

        # Create courses.
        for course in courses:
            session.run(
                """
                CREATE (c:Course {code: $code, title: $title, credits: $credits})
                """,
                course,
            )

        # Programme requires courses.
        for course in courses:
            session.run(
                """
                MATCH (p:Programme {programme_id: $programme_id})
                MATCH (c:Course {code: $code})
                CREATE (p)-[:REQUIRES]->(c)
                """,
                {"programme_id": programme["programme_id"], "code": course["code"]},
            )

        # Prerequisites.
        for prereq, target in prerequisites:
            session.run(
                """
                MATCH (pr:Course {code: $prereq})
                MATCH (c:Course {code: $target})
                CREATE (pr)-[:PREREQUISITE_FOR]->(c)
                """,
                {"prereq": prereq, "target": target},
            )

        # Corequisites.
        for a, b in corequisites:
            session.run(
                """
                MATCH (a:Course {code: $a}), (b:Course {code: $b})
                CREATE (a)-[:COREQUISITE_WITH]->(b)
                """,
                {"a": a, "b": b},
            )

        # Equivalencies.
        for a, b in equivalencies:
            session.run(
                """
                MATCH (a:Course {code: $a}), (b:Course {code: $b})
                CREATE (a)-[:EQUIVALENT_TO]->(b)
                """,
                {"a": a, "b": b},
            )

        # Students.
        for student in students:
            session.run(
                """
                CREATE (s:Student {student_id: $student_id, name: $name})
                """,
                {"student_id": student["student_id"], "name": student["name"]},
            )
            session.run(
                """
                MATCH (s:Student {student_id: $student_id})
                MATCH (p:Programme {programme_id: $programme_id})
                CREATE (s)-[:ENROLLED_IN]->(p)
                """,
                {"student_id": student["student_id"], "programme_id": programme["programme_id"]},
            )
            for code in student["completed"]:
                session.run(
                    """
                    MATCH (s:Student {student_id: $student_id})
                    MATCH (c:Course {code: $code})
                    CREATE (s)-[:COMPLETED]->(c)
                    """,
                    {"student_id": student["student_id"], "code": code},
                )
            for code in student["registered"]:
                session.run(
                    """
                    MATCH (s:Student {student_id: $student_id})
                    MATCH (c:Course {code: $code})
                    CREATE (s)-[:REGISTERED]->(c)
                    """,
                    {"student_id": student["student_id"], "code": code},
                )

    driver.close()
    print(f"Seeded academic knowledge graph at {uri}")


if __name__ == "__main__":
    seed_academic_graph()
