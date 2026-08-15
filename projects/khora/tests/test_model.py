import datetime as dt

from khora.model import Event


def test_timed_event_label_uses_24_hour_time() -> None:
    event = Event(
        summary="Write a calendar",
        calendar="Personal",
        start=dt.datetime(2026, 8, 15, 13, 30),
        end=dt.datetime(2026, 8, 15, 15, 0),
    )

    assert event.time_label == "13:30–15:00"


def test_all_day_event_label() -> None:
    event = Event(
        summary="Escape the calendar mines",
        calendar="Personal",
        start=dt.date(2026, 8, 15),
        end=dt.date(2026, 8, 15),
        all_day=True,
    )

    assert event.time_label == "All day"
