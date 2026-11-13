import datetime as dt
from collections import OrderedDict
from pathlib import Path
from types import SimpleNamespace

from gtkhal.khal_adapter import KhalRepository


def test_calendar_accounts_come_from_their_parent_directory() -> None:
    repository = KhalRepository.__new__(KhalRepository)
    repository._config = {
        "calendars": {
            "Personal": {
                "path": "/home/example/Calendars/personal/default",
                "type": "calendar",
                "color": "dark blue",
                "readonly": False,
            },
            "University": {
                "path": "/home/example/Calendars/university/classes",
                "type": "calendar",
                "readonly": True,
            },
        }
    }

    calendars = repository.calendars

    assert tuple(calendar.account for calendar in calendars) == ("personal", "university")
    assert repository.watch_paths == (
        Path("/home/example/Calendars/personal/default"),
        Path("/home/example/Calendars/university/classes"),
    )


def test_day_cache_tracks_changes_and_filters_without_reloading() -> None:
    repository = KhalRepository.__new__(KhalRepository)
    repository._events_by_day = OrderedDict()
    changed = False
    loads = []
    updates = []
    day = dt.date(2026, 8, 15)
    event = SimpleNamespace(calendar="Work")
    repository._to_event = lambda value: value
    repository._sort_key = lambda value: value.calendar
    repository._collection = SimpleNamespace(
        needs_update=lambda: changed,
        update_db=lambda: updates.append(True),
        get_events_on=lambda date: loads.append(date) or [event],
    )

    assert repository.events_on(day) == (event,)
    assert repository.events_on(day, set()) == ()
    assert repository.events_on(day, {"Work"}) == (event,)
    assert loads == [day]
    changed = True
    repository.events_on(day)
    assert loads == [day, day]
    assert updates == [True]


def test_day_cache_is_bounded() -> None:
    repository = KhalRepository.__new__(KhalRepository)
    repository._events_by_day = OrderedDict()
    repository._collection = SimpleNamespace(
        needs_update=lambda: False,
        get_events_on=lambda date: (),
    )
    days = tuple(dt.date(2026, 1, 1) + dt.timedelta(days=i) for i in range(150))
    assert len(repository.events_for_days(days)) == 150
    assert len(repository._events_by_day) == 128
    assert days[0] not in repository._events_by_day


def test_mini_calendar_uses_calendar_presence_not_event_parsing() -> None:
    repository = KhalRepository.__new__(KhalRepository)
    repository._config = {"calendars": {"Work": {"color": "blue"}, "Home": {}}}
    repository._collection = SimpleNamespace(
        needs_update=lambda: False,
        get_calendars_on=lambda day: ["Work", "Home"],
    )
    day = dt.date(2026, 8, 15)
    assert repository.colors_for_days((day,)) == {day: (None, "blue")}
    assert repository.colors_for_days((day,), {"Work"}) == {day: ("blue",)}
    assert repository.colors_for_days((day,), set()) == {day: ()}


def test_event_details_cross_the_khal_boundary() -> None:
    event = KhalRepository._to_event(
        SimpleNamespace(
            summary="Standup",
            calendar="Work",
            start_local=dt.datetime(2026, 8, 15, 9, 0),
            end_local=dt.datetime(2026, 8, 15, 9, 30),
            allday=False,
            location="Meeting room",
            color="#3584e4",
            uid="event-id",
            description="Discuss the calendar mines",
            url="https://example.com/meeting",
            organizer="organizer@example.com",
            attendees="one@example.com,two@example.com",
        )
    )

    assert event.uid == "event-id"
    assert event.description == "Discuss the calendar mines"
    assert event.url == "https://example.com/meeting"
    assert event.organizer == "organizer@example.com"
    assert event.attendees == "one@example.com,two@example.com"
