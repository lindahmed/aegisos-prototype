from datetime import datetime

import pytest

import database.academic_calendar as academic_calendar


@pytest.fixture(autouse=True)
def fixed_academic_date(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keep academic-week tests stable as the real semester advances."""

    class FixedDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 9, 18, 12, 0, tzinfo=tz)

    monkeypatch.setattr(academic_calendar, "datetime", FixedDateTime)
