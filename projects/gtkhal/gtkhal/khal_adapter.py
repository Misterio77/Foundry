from __future__ import annotations

import datetime as dt
from collections import OrderedDict
from pathlib import Path

from khal.cli_utils import build_collection
from khal.settings import get_config

from .model import Calendar, Event


class KhalRepository:
    """Keep khal's internal API behind one deliberately small boundary."""

    def __init__(self, config_path: Path | None = None) -> None:
        self._config = get_config(str(config_path) if config_path else None)
        self._collection = build_collection(self._config, selection=None)
        self._events_by_day: OrderedDict[dt.date, tuple[Event, ...]] = OrderedDict()

    @property
    def calendars(self) -> tuple[Calendar, ...]:
        return tuple(
            Calendar(
                name=name,
                color=settings.get("color") or None,
                readonly=settings.get("readonly", False),
                account=Path(settings["path"]).expanduser().parent.name or "Calendars",
            )
            for name, settings in self._config["calendars"].items()
            if settings.get("type", "calendar") == "calendar"
        )

    @property
    def watch_paths(self) -> tuple[Path, ...]:
        paths = {
            Path(settings["path"]).expanduser()
            for settings in self._config["calendars"].values()
            if settings.get("type", "calendar") == "calendar"
        }
        return tuple(sorted(paths))

    def events_on(self, day: dt.date, visible: set[str] | None = None) -> tuple[Event, ...]:
        return self.events_for_days((day,), visible)[day]

    def events_for_days(
        self,
        days: tuple[dt.date, ...],
        visible: set[str] | None = None,
    ) -> dict[dt.date, tuple[Event, ...]]:
        self._sync()
        result = {}
        for day in days:
            if day not in self._events_by_day:
                self._events_by_day[day] = tuple(
                    sorted(
                        (
                            self._to_event(event)
                            for event in self._collection.get_events_on(day)
                        ),
                        key=self._sort_key,
                    )
                )
            self._events_by_day.move_to_end(day)
            result[day] = tuple(
                event
                for event in self._events_by_day[day]
                if visible is None or event.calendar in visible
            )
            if len(self._events_by_day) > 128:
                self._events_by_day.popitem(last=False)
        return result

    def colors_for_days(
        self,
        days: tuple[dt.date, ...],
        visible: set[str] | None = None,
    ) -> dict[dt.date, tuple[str | None, ...]]:
        self._sync()
        return {
            day: tuple(
                self._config["calendars"][name].get("color") or None
                for name in sorted(self._collection.get_calendars_on(day))
                if visible is None or name in visible
            )
            for day in days
        }

    def _sync(self) -> None:
        if self._collection.needs_update():
            self._events_by_day.clear()
            self._collection.update_db()

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
            uid=str(event.uid or ""),
            description=event.description or "",
            url=event.url or "",
            organizer=event.organizer or "",
            attendees=event.attendees or "",
        )

    @staticmethod
    def _sort_key(event: Event) -> tuple[bool, dt.date | dt.datetime, str]:
        return (not event.all_day, event.start, event.summary.casefold())
