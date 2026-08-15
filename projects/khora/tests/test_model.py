import datetime as dt

from khora.model import Event, week_dates


def test_timed_event_label_uses_24_hour_time() -> None:
    event = Event(
        summary="Write a calendar",
        calendar="Personal",
        start=dt.datetime(2026, 8, 15, 13, 30),
        end=dt.datetime(2026, 8, 15, 15, 0),
    )

    assert event.time_label == "13:30–15:00"


def test_week_dates_runs_from_monday_through_sunday() -> None:
    assert week_dates(dt.date(2026, 8, 15)) == (
        dt.date(2026, 8, 10),
        dt.date(2026, 8, 11),
        dt.date(2026, 8, 12),
        dt.date(2026, 8, 13),
        dt.date(2026, 8, 14),
        dt.date(2026, 8, 15),
        dt.date(2026, 8, 16),
    )


def test_all_day_event_label() -> None:
    event = Event(
        summary="Escape the calendar mines",
        calendar="Personal",
        start=dt.date(2026, 8, 15),
        end=dt.date(2026, 8, 15),
        all_day=True,
    )

    assert event.time_label == "All day"
