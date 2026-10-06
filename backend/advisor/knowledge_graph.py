from __future__ import annotations

import os
import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


@dataclass
class CourseInfo:
    code: str
    title: str
    credits: int = 3


@dataclass
class PrerequisiteRule:
    course_code: str
    prerequisite_code: str
    is_strict: bool = True
    note: str = ""


@dataclass
class ProgrammeInfo:
    programme_id: str
    name: str
    total_credits_required: int
    required_course_codes: set[str] = field(default_factory=set)
    elective_credits: int = 0


class AcademicKnowledgeGraph(ABC):
    """Abstract store for relationship-heavy academic rules.

    Implementations may be backed by Neo4j in production or by an in-memory
    graph for development and tests.
    """

    @abstractmethod
    def get_course_eligibility(
        self, student_id: str, course_code: str
    ) -> dict[str, Any] | None:
        """Return whether the student can take a course and why/why not."""

    @abstractmethod
    def get_programme_progress(
        self, student_id: str
    ) -> dict[str, Any] | None:
        """Return programme-level progress (credits, remaining requirements)."""

    @abstractmethod
    def get_prerequisites(self, course_code: str) -> list[dict[str, Any]]:
        """Return the prerequisites for a course."""

    @abstractmethod
    def get_recommended_next_courses(
        self, student_id: str
    ) -> list[dict[str, Any]]:
        """Return courses the student is eligible to take next."""

    def extract_course_code(self, message: str) -> str | None:
        """Crude extraction of a course code from free text.

        Looks for explicit codes like CS301 or "Machine Learning".
        Override or replace with an LLM extractor for production.
        """
        # Explicit codes first.
        match = re.search(r"\b([A-Z]{2,4}\s?\d{3,4})\b", message.upper())
        if match:
            return match.group(1).replace(" ", "")
        # Known title mapping (limited in-memory fallback).
        title_map = {
            "machine learning": "CS301",
            "deep learning": "CS302",
            "data structures": "CS201",
            "algorithms": "CS202",
            "object oriented programming": "CS102",
            "object-oriented programming": "CS102",
            "introduction to programming": "CS101",
            "linear algebra": "MATH201",
            "probability": "MATH202",
            "digital logic": "CS210",
            "networks": "CS220",
            "database": "CS230",
        }
        lower = message.lower()
        for title, code in title_map.items():
            if title in lower:
                return code
        return None


class InMemoryAcademicGraph(AcademicKnowledgeGraph):
    """Lightweight in-memory academic graph for development and tests.

    Seeds the same Computer Science programme data that the Neo4j backend
    would hold, so the advisor can answer prerequisite questions without a
    running graph database.
    """

    def __init__(self) -> None:
        self.programmes: dict[str, ProgrammeInfo] = {}
        self.courses: dict[str, CourseInfo] = {}
        self.prerequisites: list[PrerequisiteRule] = []
        self.corequisites: list[tuple[str, str]] = []
        self.equivalencies: list[set[str]] = []
        self.student_programmes: dict[str, str] = {}
        self.student_completed: dict[str, set[str]] = {}
        self.student_registered: dict[str, set[str]] = {}
        self._seed()

    def _seed(self) -> None:
        cs = ProgrammeInfo(
            programme_id="cs",
            name="Bachelor of Computer Science",
            total_credits_required=120,
            elective_credits=24,
        )
        self.programmes[cs.programme_id] = cs

        courses = [
            CourseInfo("CS101", "Introduction to Programming", 3),
            CourseInfo("CS102", "Object-Oriented Programming", 3),
            CourseInfo("CS201", "Data Structures", 3),
            CourseInfo("CS202", "Algorithms", 3),
            CourseInfo("CS301", "Machine Learning", 3),
            CourseInfo("CS302", "Deep Learning", 3),
            CourseInfo("MATH101", "Calculus I", 3),
            CourseInfo("MATH201", "Linear Algebra", 3),
            CourseInfo("MATH202", "Probability and Statistics", 3),
            CourseInfo("CS210", "Digital Logic Design", 3),
            CourseInfo("CS220", "Introduction to Networks", 3),
            CourseInfo("CS230", "Database Systems", 3),
        ]
        for course in courses:
            self.courses[course.code] = course
            cs.required_course_codes.add(course.code)

        self.prerequisites = [
            PrerequisiteRule("CS102", "CS101"),
            PrerequisiteRule("CS201", "CS101"),
            PrerequisiteRule("CS201", "CS102"),
            PrerequisiteRule("CS202", "CS201"),
            PrerequisiteRule("CS301", "CS201"),
            PrerequisiteRule("CS301", "CS102"),
            PrerequisiteRule("CS301", "MATH201"),
            PrerequisiteRule("CS301", "MATH202"),
            PrerequisiteRule("CS302", "CS301"),
            PrerequisiteRule("CS230", "CS102"),
        ]
        self.corequisites = [("CS202", "MATH202")]
        self.equivalencies = [{"CS101", "CS110"}]

    def enroll_student(
        self,
        student_id: str,
        programme_id: str,
        completed: set[str] | None = None,
        registered: set[str] | None = None,
    ) -> None:
        self.student_programmes[student_id] = programme_id
        self.student_completed[student_id] = set(completed or [])
        self.student_registered[student_id] = set(registered or [])

    def get_prerequisites(self, course_code: str) -> list[dict[str, Any]]:
        return [
            {
                "course_code": rule.prerequisite_code,
                "title": self.courses.get(rule.prerequisite_code, CourseInfo(rule.prerequisite_code, "")).title,
                "is_strict": rule.is_strict,
                "note": rule.note,
            }
            for rule in self.prerequisites
            if rule.course_code == course_code.upper()
        ]

    def get_course_eligibility(
        self, student_id: str, course_code: str
    ) -> dict[str, Any] | None:
        code = course_code.upper()
        if code not in self.courses:
            return None

        completed = self.student_completed.get(student_id, set())
        registered = self.student_registered.get(student_id, set())
        required = self.get_prerequisites(code)

        missing = [
            req for req in required
            if req["course_code"] not in completed and req["course_code"] not in registered
        ]
        in_progress = [
            req for req in required
            if req["course_code"] not in completed and req["course_code"] in registered
        ]
        satisfied = [req for req in required if req["course_code"] in completed]

        if missing:
            reason = f"Missing prerequisites: {', '.join(r['course_code'] for r in missing)}."
        elif in_progress:
            codes = ', '.join(p['course_code'] for p in in_progress)
            reason = f"All prerequisites are satisfied or in progress; assuming you pass {codes}, you will be fully eligible."
        else:
            reason = "All prerequisites are satisfied."

        return {
            "course_code": code,
            "course_title": self.courses[code].title,
            "eligible": not missing,
            "reason": reason,
            "prerequisites": required,
            "satisfied_prerequisites": satisfied,
            "in_progress_prerequisites": in_progress,
            "missing_prerequisites": missing,
            "currently_registered": code in registered,
            "already_completed": code in completed,
        }

    def get_programme_progress(self, student_id: str) -> dict[str, Any] | None:
        programme_id = self.student_programmes.get(student_id)
        if programme_id is None:
            return None
        programme = self.programmes[programme_id]
        completed = self.student_completed.get(student_id, set())
        registered = self.student_registered.get(student_id, set())
        completed_credits = sum(
            self.courses[c].credits for c in completed if c in self.courses
        )
        remaining = programme.required_course_codes - completed
        return {
            "programme_id": programme_id,
            "programme_name": programme.name,
            "total_credits_required": programme.total_credits_required,
            "completed_credits": completed_credits,
            "completed_courses": sorted(completed),
            "registered_courses": sorted(registered),
            "remaining_required_courses": sorted(remaining),
            "elective_credits": programme.elective_credits,
        }

    def get_recommended_next_courses(self, student_id: str) -> list[dict[str, Any]]:
        programme_id = self.student_programmes.get(student_id)
        if programme_id is None:
            return []
        completed = self.student_completed.get(student_id, set())
        registered = self.student_registered.get(student_id, set())
        recommendations = []
        for code in self.programmes[programme_id].required_course_codes:
            if code in completed or code in registered:
                continue
            eligibility = self.get_course_eligibility(student_id, code)
            if eligibility and eligibility["eligible"]:
                recommendations.append(eligibility)
        return recommendations


class Neo4jAcademicGraph(AcademicKnowledgeGraph):
    """Neo4j-backed implementation for production use.

    Falls back to a disabled state if the Neo4j driver is not installed or
    the connection is not configured, allowing the rest of the app to start.
    """

    def __init__(self, uri: str | None = None, user: str | None = None, password: str | None = None) -> None:
        self._uri = uri or os.getenv("NEO4J_URI", "bolt://localhost:7687")
        self._user = user or os.getenv("NEO4J_USER", "neo4j")
        self._password = password or os.getenv("NEO4J_PASSWORD", "password")
        self._driver: Any = None
        self._available = False
        self._connect()

    def _connect(self) -> None:
        try:
            from neo4j import GraphDatabase
        except ImportError as error:
            raise RuntimeError(
                "Neo4j support requires the 'neo4j' package. Install backend requirements."
            ) from error

        try:
            self._driver = GraphDatabase.driver(
                self._uri, auth=(self._user, self._password)
            )
            self._driver.verify_connectivity()
            self._available = True
        except Exception as error:
            self._driver = None
            self._available = False
            raise RuntimeError(f"Could not connect to Neo4j at {self._uri}: {error}") from error

    @property
    def available(self) -> bool:
        return self._available

    def _run(self, query: str, parameters: dict[str, Any] | None = None) -> list[dict[str, Any]]:
        if not self._driver:
            return []
        with self._driver.session() as session:
            result = session.run(query, parameters or {})
            return [dict(record) for record in result]

    def get_prerequisites(self, course_code: str) -> list[dict[str, Any]]:
        return self._run(
            """
            MATCH (c:Course {code: $code})<-[:PREREQUISITE_FOR]-(p:Course)
            RETURN p.code AS course_code, p.title AS title, p.credits AS credits
            ORDER BY p.code
            """,
            {"code": course_code.upper()},
        )

    def extract_course_code(self, message: str) -> str | None:
        """Resolve codes and titles from the synchronized course catalogue."""
        match = re.search(r"\b([A-Z]{2,4}\s?\d{3,4})\b", message.upper())
        if match:
            return match.group(1).replace(" ", "")
        rows = self._run(
            """
            MATCH (course:Course)
            WHERE trim(course.title) <> ''
              AND toLower($message) CONTAINS toLower(course.title)
            RETURN course.code AS course_code
            ORDER BY size(course.title) DESC
            LIMIT 1
            """,
            {"message": message},
        )
        return rows[0]["course_code"] if rows else None

    def get_course_eligibility(
        self, student_id: str, course_code: str
    ) -> dict[str, Any] | None:
        course_code = course_code.upper()
        rows = self._run(
            """
            MATCH (c:Course {code: $code})
            OPTIONAL MATCH (c)<-[:PREREQUISITE_FOR]-(p:Course)
            OPTIONAL MATCH (s:Student {student_id: $student_id})
            WITH c, p, s,
                 CASE WHEN p IS NULL THEN null
                      WHEN EXISTS((s)-[:COMPLETED]->(p)) THEN 'completed'
                      WHEN EXISTS((s)-[:REGISTERED]->(p)) THEN 'in_progress'
                      ELSE 'missing' END AS status
            RETURN c.code AS course_code, c.title AS course_title,
                   collect({course_code: p.code, title: p.title, status: status}) AS prerequisites
            """,
            {"code": course_code, "student_id": student_id},
        )
        if not rows:
            return None
        record = rows[0]
        required = [p for p in record["prerequisites"] if p["course_code"]]
        missing = [p for p in required if p["status"] == "missing"]
        in_progress = [p for p in required if p["status"] == "in_progress"]
        satisfied = [p for p in required if p["status"] == "completed"]
        registered_rows = self._run(
            """
            MATCH (s:Student {student_id: $student_id})-[:REGISTERED]->(c:Course {code: $code})
            RETURN count(c) AS cnt
            """,
            {"student_id": student_id, "code": course_code},
        )
        completed_rows = self._run(
            """
            MATCH (s:Student {student_id: $student_id})-[:COMPLETED]->(c:Course {code: $code})
            RETURN count(c) AS cnt
            """,
            {"student_id": student_id, "code": course_code},
        )
        return {
            "course_code": record["course_code"],
            "course_title": record["course_title"],
            "eligible": not missing,
            "reason": (
                "All prerequisites are satisfied."
                if not missing
                else f"Missing prerequisites: {', '.join(p['course_code'] for p in missing)}."
            ),
            "prerequisites": required,
            "satisfied_prerequisites": satisfied,
            "in_progress_prerequisites": in_progress,
            "missing_prerequisites": missing,
            "currently_registered": (registered_rows[0]["cnt"] if registered_rows else 0) > 0,
            "already_completed": (completed_rows[0]["cnt"] if completed_rows else 0) > 0,
        }

    def get_programme_progress(self, student_id: str) -> dict[str, Any] | None:
        rows = self._run(
            """
            MATCH (s:Student {student_id: $student_id})-[:ENROLLED_IN]->(p:Programme)
            OPTIONAL MATCH (s)-[:COMPLETED]->(c:Course)
            WITH s, p, collect(DISTINCT c) AS completed
            OPTIONAL MATCH (s)-[:REGISTERED]->(r:Course)
            WITH s, p, completed, collect(DISTINCT r) AS registered
            OPTIONAL MATCH (p)-[:REQUIRES]->(req:Course)
            WITH p, completed, registered, collect(DISTINCT req) AS required
            RETURN p.programme_id AS programme_id, p.name AS programme_name,
                   p.total_credits_required AS total_credits_required,
                   p.elective_credits AS elective_credits,
                   reduce(total = 0, course IN completed |
                          total + coalesce(course.credits, 0)) AS completed_credits,
                   [course IN completed | course.code] AS completed_courses,
                   [course IN registered | course.code] AS registered_courses,
                   [course IN required | course.code] AS required_courses
            """,
            {"student_id": student_id},
        )
        if not rows:
            return None
        record = rows[0]
        completed = set(record["completed_courses"] or [])
        required = set(record["required_courses"] or [])
        return {
            "programme_id": record["programme_id"],
            "programme_name": record["programme_name"],
            "total_credits_required": record["total_credits_required"],
            "completed_credits": record["completed_credits"] or 0,
            "completed_courses": sorted(completed),
            "registered_courses": sorted(record["registered_courses"] or []),
            "remaining_required_courses": sorted(required - completed),
            "elective_credits": record["elective_credits"],
        }

    def get_recommended_next_courses(self, student_id: str) -> list[dict[str, Any]]:
        rows = self._run(
            """
            MATCH (s:Student {student_id: $student_id})-[:ENROLLED_IN]->(p:Programme)-[:REQUIRES]->(c:Course)
            WHERE NOT EXISTS((s)-[:COMPLETED]->(c))
              AND NOT EXISTS((s)-[:REGISTERED]->(c))
            OPTIONAL MATCH (c)<-[:PREREQUISITE_FOR]-(pr:Course)
            WITH c, collect(pr) AS prereqs
            WHERE ALL(pr IN prereqs WHERE EXISTS((s)-[:COMPLETED]->(pr)))
            RETURN c.code AS course_code, c.title AS title, c.credits AS credits
            ORDER BY c.code
            """,
            {"student_id": student_id},
        )
        return [dict(row) for row in rows]


def create_knowledge_graph() -> AcademicKnowledgeGraph:
    """Factory: use Neo4j if configured, otherwise the in-memory graph."""
    if os.getenv("NEO4J_URI"):
        try:
            return Neo4jAcademicGraph()
        except Exception:
            # In production you may want to fail loudly; for the prototype
            # falling back keeps the advisor usable during setup.
            pass
    return InMemoryAcademicGraph()
