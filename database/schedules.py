"""Schedule validation and the signature that defines a student group."""

from __future__ import annotations

import hashlib
import json
from typing import Any, Iterable

DAYS = ("Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday")
_DAY_LOOKUP = {day.lower(): day for day in DAYS}


def normalize_slots(slots: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Validate slots and return them in canonical order.

    Raises ValueError for unknown days, invalid times, empty schedules,
    or two slots that overlap on the same day.
    """
    normalized: list[dict[str, Any]] = []
    for raw in slots:
        course_id = str(raw.get("course_id") or "").strip()
        if not course_id:
            raise ValueError("Every slot needs a course_id")
        day = _DAY_LOOKUP.get(str(raw.get("day_of_week") or "").strip().lower())
        if day is None:
            raise ValueError(f"Unknown day of week: {raw.get('day_of_week')!r}")
        try:
            start = int(raw["start_minute"])
            end = int(raw["end_minute"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError("Slots need integer start_minute and end_minute") from error
        if not 0 <= start <= 1439 or not 1 <= end <= 1440 or end <= start:
            raise ValueError(
                f"Invalid time range for {course_id} on {day}: {start}-{end} "
                "(minutes after midnight, end must be after start)"
            )
        location = str(raw.get("location") or "").strip() or None
        normalized.append({
            "course_id": course_id, "day_of_week": day,
            "start_minute": start, "end_minute": end, "location": location,
        })
    if not normalized:
        raise ValueError("A schedule needs at least one slot")

    normalized.sort(key=lambda s: (DAYS.index(s["day_of_week"]), s["start_minute"],
                                   s["end_minute"], s["course_id"], s["location"] or ""))
    for previous, current in zip(normalized, normalized[1:]):
        if previous["day_of_week"] != current["day_of_week"]:
            continue
        if current["start_minute"] < previous["end_minute"]:
            raise ValueError(
                f"{previous['course_id']} and {current['course_id']} overlap on "
                f"{current['day_of_week']}"
            )
    return normalized


def schedule_signature(normalized_slots: list[dict[str, Any]]) -> str:
    """Stable hash of a canonical slot list; equal schedules hash equally."""
    canonical = [
        [s["course_id"], s["day_of_week"], s["start_minute"], s["end_minute"],
         (s["location"] or "").lower()]
        for s in normalized_slots
    ]
    payload = json.dumps(canonical, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def schedule_id_for(signature: str) -> str:
    return f"sch-{signature[:12]}"
