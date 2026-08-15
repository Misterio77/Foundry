from __future__ import annotations

import calendar
import datetime as dt
from dataclasses import dataclass


def week_dates(day: dt.date) -> tuple[dt.date, ...]:
    monday = day - dt.timedelta(days=day.weekday())
    return tuple(monday + dt.timedelta(days=offset) for offset in range(7))


def month_grid_dates(day: dt.date) -> tuple[dt.date, ...]:
    first = day.replace(day=1)
    start = first - dt.timedelta(days=first.weekday())
    return tuple(start + dt.timedelta(days=offset) for offset in range(42))


def period_label(day: dt.date, mode: str) -> str:
    if mode == "month":
        return f"{day:%B} {day.year}"
    if mode != "week":
        return f"{day:%A, %B} {day.day}, {day.year}"

    start, *_, end = week_dates(day)
    if start.year != end.year:
        return f"{start:%B} {start.day}, {start.year} – {end:%B} {end.day}, {end.year}"
    if start.month != end.month:
        return f"{start:%B} {start.day} – {end:%B} {end.day}, {start.year}"
    return f"{start:%B} {start.day}–{end.day}, {start.year}"


def shifted_date(day: dt.date, mode: str, direction: int) -> dt.date:
    if mode != "month":
        step = 7 if mode == "week" else 1
        return day + dt.timedelta(days=step * direction)

    month_index = day.year * 12 + day.month - 1 + direction
    year, zero_based_month = divmod(month_index, 12)
    month = zero_based_month + 1
    return dt.date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


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
    account: str = "Calendars"


@dataclass(frozen=True)
class Event:
    summary: str
    calendar: str
    start: dt.date | dt.datetime
    end: dt.date | dt.datetime
    all_day: bool = False
    location: str = ""
    color: str | None = None
    uid: str = ""
    description: str = ""
    url: str = ""
    organizer: str = ""
    attendees: str = ""

    @property
    def time_label(self) -> str:
        if self.all_day:
            return "All day"

        assert isinstance(self.start, dt.datetime)
        assert isinstance(self.end, dt.datetime)
        return f"{self.start:%H:%M}–{self.end:%H:%M}"

    @property
    def when_label(self) -> str:
        if self.all_day:
            assert isinstance(self.start, dt.date)
            assert isinstance(self.end, dt.date)
            if self.end <= self.start + dt.timedelta(days=1):
                return f"{self.start:%A, %B} {self.start.day}, {self.start.year} · All day"
            last_day = self.end - dt.timedelta(days=1)
            return (
                f"{self.start:%B} {self.start.day} – "
                f"{last_day:%B} {last_day.day}, {last_day.year} · All day"
            )

        assert isinstance(self.start, dt.datetime)
        assert isinstance(self.end, dt.datetime)
        if self.start.date() == self.end.date():
            return (
                f"{self.start:%A, %B} {self.start.day}, {self.start.year} · "
                f"{self.time_label}"
            )
        return (
            f"{self.start:%B} {self.start.day}, {self.start:%H:%M} – "
            f"{self.end:%B} {self.end.day}, {self.end:%H:%M}, {self.end.year}"
        )


@dataclass(frozen=True)
class EventPlacement:
    event: Event
    start_slot: int
    end_slot: int
    lane: int
    lane_count: int


def layout_event_lanes(events: tuple[Event, ...], day: dt.date) -> tuple[EventPlacement, ...]:
    intervals = sorted(
        ((event, *event_slot_range(event, day)) for event in events),
        key=lambda item: (item[1], item[2], item[0].summary.casefold()),
    )
    groups: list[list[tuple[Event, int, int]]] = []
    for interval in intervals:
        if not groups or interval[1] >= max(item[2] for item in groups[-1]):
            groups.append([interval])
        else:
            groups[-1].append(interval)

    placements: list[EventPlacement] = []
    for group in groups:
        active: list[tuple[int, int]] = []
        assigned: list[tuple[Event, int, int, int]] = []
        lane_count = 0
        for event, start, end in group:
            active = [(active_end, lane) for active_end, lane in active if active_end > start]
            occupied = {lane for _active_end, lane in active}
            lane = next(candidate for candidate in range(len(occupied) + 1) if candidate not in occupied)
            active.append((end, lane))
            lane_count = max(lane_count, lane + 1)
            assigned.append((event, start, end, lane))
        placements.extend(
            EventPlacement(event, start, end, lane, lane_count)
            for event, start, end, lane in assigned
        )
    return tuple(placements)
