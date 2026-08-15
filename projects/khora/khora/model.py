from __future__ import annotations

import datetime as dt
from dataclasses import dataclass


def week_dates(day: dt.date) -> tuple[dt.date, ...]:
    monday = day - dt.timedelta(days=day.weekday())
    return tuple(monday + dt.timedelta(days=offset) for offset in range(7))


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
