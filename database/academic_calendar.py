"""Shared academic-calendar rules for every repository backend."""

from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo


# Week 1 begins on Saturday, 8 August 2026, so week 6 begins on Saturday,
# 12 September. Keeping one anchor makes the week identical for every student.
FALL_2026_START_DATE = date(2026, 8, 8)
ACADEMIC_TIME_ZONE = ZoneInfo("Africa/Cairo")


def academic_week(start_date: date, on_date: date | None = None) -> int:
    """Return the one-based teaching week for a real calendar date."""
    today = on_date or datetime.now(ACADEMIC_TIME_ZONE).date()
    return max(1, ((today - start_date).days // 7) + 1)
