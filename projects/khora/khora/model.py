from __future__ import annotations

import datetime as dt
from dataclasses import dataclass


def week_dates(day: dt.date) -> tuple[dt.date, ...]:
    monday = day - dt.timedelta(days=day.weekday())
    return tuple(monday + dt.timedelta(days=offset) for offset in range(7))


def event_slot_range(event: Event, day: dt.date) -> tuple[int, int]:
    """Return the half-hour rows occupied by a timed event on one day."""
    assert isinstance(event.start, dt.datetime)
    assert isinstance(event.end, dt.datetime)

    if event.start.date() < day:
        start = 0
    else:
        start = event.start.hour * 2 + event.start.minute // 30

    if event.end.date() > day:
        end = 48
    else:
        minutes = event.end.hour * 60 + event.end.minute
        end = (minutes + 29) // 30

    return max(0, start), min(48, max(start + 1, end))


@dataclass(frozen=True)
class Calendar:
    name: str
    color: str | None = None
    readonly: bool = False


@dataclass(frozen=True)
class Event:
    summary: str
    calendar: str
    start: dt.date | dt.datetime
    end: dt.date | dt.datetime
    all_day: bool = False
    location: str = ""
    color: str | None = None

    @property
    def time_label(self) -> str:
        if self.all_day:
            return "All day"

        assert isinstance(self.start, dt.datetime)
        assert isinstance(self.end, dt.datetime)
        return f"{self.start:%H:%M}–{self.end:%H:%M}"
