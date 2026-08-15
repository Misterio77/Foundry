from __future__ import annotations

import datetime as dt
from pathlib import Path

from khal.cli_utils import build_collection
from khal.settings import get_config

from .model import Calendar, Event


class KhalRepository:
    """Keep khal's internal API behind one deliberately small boundary."""

    def __init__(self, config_path: Path | None = None) -> None:
        self._config = get_config(str(config_path) if config_path else None)
        self._collection = build_collection(self._config, selection=None)

    @property
    def calendars(self) -> tuple[Calendar, ...]:
        return tuple(
            Calendar(
                name=name,
                color=settings.get("color") or None,
                readonly=settings.get("readonly", False),
            )
            for name, settings in self._config["calendars"].items()
            if settings.get("type", "calendar") == "calendar"
        )

    def events_on(self, day: dt.date, visible: set[str] | None = None) -> tuple[Event, ...]:
        return self.events_for_days((day,), visible)[day]

    def events_for_days(
        self,
        days: tuple[dt.date, ...],
        visible: set[str] | None = None,
    ) -> dict[dt.date, tuple[Event, ...]]:
        self._collection.update_db()
        return {
            day: tuple(
                sorted(
                    (
                        self._to_event(event)
                        for event in self._collection.get_events_on(day)
                        if visible is None or event.calendar in visible
                    ),
                    key=self._sort_key,
                )
            )
            for day in days
        }

    @staticmethod
    def _to_event(event) -> Event:
        return Event(
            summary=event.summary or "(untitled)",
            calendar=event.calendar,
            start=event.start_local,
            end=event.end_local,
            all_day=event.allday,
            location=event.location or "",
            color=event.color,
        )

    @staticmethod
    def _sort_key(event: Event) -> tuple[bool, dt.date | dt.datetime, str]:
        return (not event.all_day, event.start, event.summary.casefold())
