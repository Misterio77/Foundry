from __future__ import annotations

import datetime as dt
from dataclasses import dataclass


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
