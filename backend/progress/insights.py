"""Keeps each student's Advisor AI behaviour suggestions up to date.

Nothing has to call an endpoint by hand: whenever a student opens UniTrack
(workspace, app or website) the notification feed asks this runner to refresh
that student.  The work happens in a background thread and at most once per
hour per student, so a poll never waits for it; new suggestions appear on the
next poll.  Suggestions are de-duplicated in the database, so repeated runs
never notify twice.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository

from .behavior import EVENT_TYPES, SOURCES, generate_behavior_suggestions

logger = logging.getLogger("aegisos.progress.insights")
Repository = StudentRepository | PostgresStudentRepository

DUPLICATE_EVENT_SECONDS = 60


def client_source(user_agent: str | None, explicit: str | None = None) -> str:
    """Which UniTrack client sent a request: workspace, app, website or unknown."""
    if explicit and explicit.strip().lower() in SOURCES:
        return explicit.strip().lower()
    agent = (user_agent or "").lower()
    if "electron" in agent:
        return "workspace"
    if "dart" in agent or "okhttp" in agent or "cfnetwork" in agent:
        return "app"
    if "mozilla" in agent:
        return "website"
    return "unknown"


class InsightsRunner:
    def __init__(
        self, repository: Repository, *, enabled: bool = True, run_inline: bool = False,
        min_interval_seconds: float = 3600,
    ) -> None:
        self.repository = repository
        self.enabled = enabled
        self.run_inline = run_inline
        self.min_interval_seconds = min_interval_seconds
        self._lock = threading.Lock()
        self._last_run: dict[str, float] = {}
        self._running: set[str] = set()
        self._last_event: dict[tuple[str, str, str, str], float] = {}

    # ------------------------------------------------------------------ activity
    def record(
        self, student_id: str, source: str, event_type: str,
        course_ref: str | None = None, detail: str | None = None,
    ) -> bool:
        """Log one activity event; never raises, ignores unknown types and rapid repeats."""
        if event_type not in EVENT_TYPES or source not in SOURCES:
            return False
        key = (student_id, source, event_type, (course_ref or "").casefold())
        now = time.monotonic()
        with self._lock:
            if now - self._last_event.get(key, -1e9) < DUPLICATE_EVENT_SECONDS:
                return False
            self._last_event[key] = now
            if len(self._last_event) > 20000:  # keep the memory bounded
                cutoff = now - DUPLICATE_EVENT_SECONDS
                self._last_event = {k: v for k, v in self._last_event.items() if v >= cutoff}
        try:
            self.repository.record_activity(
                student_id, source, event_type,
                (course_ref or None) and course_ref[:120],
                (detail or None) and detail[:200],
            )
        except Exception:  # logging must never break a student's request
            logger.exception("Could not record activity for %s", student_id)
            return False
        return True

    # ------------------------------------------------------------------ insights
    def run_now(self, student_id: str) -> dict[str, Any]:
        """Refresh the behaviour suggestions for one student."""
        behavior = generate_behavior_suggestions(self.repository, student_id) or []
        return {"behavior_suggestions": len(behavior)}

    def is_due(self, student_id: str) -> bool:
        if not self.enabled:
            return False
        with self._lock:
            return (student_id not in self._running
                    and time.monotonic() - self._last_run.get(student_id, -1e9) >= self.min_interval_seconds)

    def trigger(self, student_id: str) -> bool:
        """Request a refresh; returns True if one was started."""
        if not self.enabled:
            return False
        now = time.monotonic()
        with self._lock:
            if student_id in self._running:
                return False
            if now - self._last_run.get(student_id, -1e9) < self.min_interval_seconds:
                return False
            self._running.add(student_id)
            self._last_run[student_id] = now
        if self.run_inline:
            self._safe_run(student_id)
        else:
            threading.Thread(target=self._safe_run, args=(student_id,), daemon=True).start()
        return True

    def _safe_run(self, student_id: str) -> None:
        try:
            self.run_now(student_id)
        except Exception:
            logger.exception("Insights refresh failed for %s", student_id)
        finally:
            with self._lock:
                self._running.discard(student_id)
