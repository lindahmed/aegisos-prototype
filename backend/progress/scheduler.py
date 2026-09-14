from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from backend.progress_agent.graph import (
    RecommendationGenerator,
    build_progress_graph,
)
from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository


logger = logging.getLogger("aegisos.progress.scheduler")


RepositoryType = StudentRepository | PostgresStudentRepository


@dataclass
class SchedulerRunResult:
    students_analyzed: int = 0
    interventions_created: int = 0
    errors: list[str] = field(default_factory=list)

    def summary(self) -> str:
        return (
            f"Analyzed {self.students_analyzed} students, "
            f"created {self.interventions_created} interventions, "
            f"{len(self.errors)} errors."
        )


def run_analysis_cycle(
    repository: RepositoryType,
    recommendation_generator: RecommendationGenerator | None = None,
) -> SchedulerRunResult:
    """Run the Progress Agent once for every registered student.

    This is the scheduled entry point: it loads students, invokes the same
    LangGraph used by the API, and records how many new interventions were
    generated.  No manual per-student trigger is required.
    """
    result = SchedulerRunResult()
    graph = (
        build_progress_graph(repository, recommendation_generator)
        if recommendation_generator is not None
        else build_progress_graph(repository)
    )
    for student in repository.get_registered_students():
        try:
            state = graph.invoke({"student_id": student.student_id})
            result.students_analyzed += 1
            result.interventions_created += len(
                state.get("validated_interventions", [])
            )
        except Exception as error:  # pragma: no cover - defensive logging
            message = f"Failed to analyze {student.student_id}: {error}"
            logger.exception(message)
            result.errors.append(message)
    return result


class ProgressScheduler:
    """Lightweight scheduler that can run once or loop with a fixed interval.

    For the prototype this is intentionally simple: no extra dependencies,
    no background threads inside the web server, and easy to wire to cron or
    a management command.
    """

    def __init__(
        self,
        repository: RepositoryType,
        recommendation_generator: RecommendationGenerator | None = None,
        interval_seconds: int = 86400,
    ) -> None:
        self.repository = repository
        self.recommendation_generator = recommendation_generator
        self.interval_seconds = interval_seconds
        self._stop = False

    def run_once(self) -> SchedulerRunResult:
        return run_analysis_cycle(self.repository, self.recommendation_generator)

    def run_forever(self) -> None:
        """Blocking loop for use in a dedicated worker process."""
        while not self._stop:
            result = self.run_once()
            logger.info(result.summary())
            time.sleep(self.interval_seconds)

    def stop(self) -> None:
        self._stop = True


def _create_repository_from_env() -> RepositoryType:
    database_url = __import__("os").getenv("DATABASE_URL")
    if database_url:
        repository: RepositoryType = PostgresStudentRepository(database_url)
    else:
        project_root = Path(__file__).resolve().parents[2]
        database_path = Path(
            __import__("os").getenv("AEGIS_DB_PATH", project_root / "database" / "aegisos.db")
        )
        repository = StudentRepository(database_path)
    repository.initialize()
    return repository


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    logging.basicConfig(level=logging.INFO)
    repo = _create_repository_from_env()
    result = run_analysis_cycle(repo)
    print(result.summary())
