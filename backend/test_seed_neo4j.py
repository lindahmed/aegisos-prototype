from typing import Any

import pytest

from backend.advisor.seed_neo4j import (
    AcademicGraphSnapshot,
    _replace_academic_graph,
)


def _snapshot() -> AcademicGraphSnapshot:
    return AcademicGraphSnapshot(
        courses=[
            {
                "code": "CAI3002",
                "title": "Mathematical Foundations for AI",
                "credits": 3,
                "is_placeholder": False,
                "min_credit_hours": None,
            },
            {
                "code": "EBA2204",
                "title": "Linear algebra",
                "credits": 3,
                "is_placeholder": False,
                "min_credit_hours": None,
            },
        ],
        prerequisites=[
            {"course_code": "CAI3002", "prerequisite_code": "EBA2204"}
        ],
    )


def test_snapshot_accepts_database_prerequisite_direction() -> None:
    _snapshot().validate()


def test_snapshot_rejects_unknown_prerequisite_course() -> None:
    snapshot = _snapshot()
    snapshot.prerequisites[0]["prerequisite_code"] = "MISSING"

    with pytest.raises(ValueError, match="MISSING"):
        snapshot.validate()


class _ConsumedResult:
    def consume(self) -> None:
        return None


class _RecordingTransaction:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []

    def run(self, query: str, **parameters: Any) -> _ConsumedResult:
        self.calls.append((query, parameters))
        return _ConsumedResult()


def test_rebuild_creates_prerequisite_to_target_relationship() -> None:
    transaction = _RecordingTransaction()
    snapshot = _snapshot()

    _replace_academic_graph(transaction, snapshot)

    relationship_query, parameters = transaction.calls[3]
    assert "(prerequisite)-[:PREREQUISITE_FOR]->(course)" in relationship_query
    assert parameters["rows"] == snapshot.prerequisites
