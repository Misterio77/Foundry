import datetime as dt
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
