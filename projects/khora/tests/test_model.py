import datetime as dt

from khora.model import (
    Event,
    event_slot_range,
    layout_event_lanes,
    month_grid_dates,
    period_label,
    shifted_date,
    week_dates,
)


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


def test_month_grid_contains_six_complete_weeks() -> None:
    days = month_grid_dates(dt.date(2026, 8, 15))

    assert len(days) == 42
    assert days[0] == dt.date(2026, 7, 27)
    assert days[-1] == dt.date(2026, 9, 6)


def test_period_labels_follow_the_active_view() -> None:
    day = dt.date(2026, 8, 15)

    assert period_label(day, "day") == "Saturday, August 15, 2026"
    assert period_label(day, "week") == "August 10–16, 2026"
    assert period_label(day, "month") == "August 2026"
    assert period_label(day, "agenda") == "Saturday, August 15, 2026"


def test_week_label_handles_month_boundaries() -> None:
    assert period_label(dt.date(2026, 9, 1), "week") == "August 31 – September 6, 2026"


def test_shifted_date_uses_the_active_view_interval() -> None:
    day = dt.date(2026, 8, 15)

    assert shifted_date(day, "day", 1) == dt.date(2026, 8, 16)
    assert shifted_date(day, "week", -1) == dt.date(2026, 8, 8)
    assert shifted_date(dt.date(2026, 1, 31), "month", 1) == dt.date(2026, 2, 28)


def test_overlapping_events_are_assigned_adjacent_lanes() -> None:
    day = dt.date(2026, 8, 15)
    first = Event(
        "First",
        "Work",
        dt.datetime(2026, 8, 15, 9, 0),
        dt.datetime(2026, 8, 15, 10, 0),
    )
    second = Event(
        "Second",
        "Work",
        dt.datetime(2026, 8, 15, 9, 30),
        dt.datetime(2026, 8, 15, 10, 30),
    )
    later = Event(
        "Later",
        "Work",
        dt.datetime(2026, 8, 15, 11, 0),
        dt.datetime(2026, 8, 15, 12, 0),
    )

    placements = layout_event_lanes((first, second, later), day)

    assert [(item.event, item.lane, item.lane_count) for item in placements] == [
        (first, 0, 2),
        (second, 1, 2),
        (later, 0, 1),
    ]


def test_event_slot_range_rounds_to_half_hours() -> None:
    event = Event(
        summary="Oddly timed meeting",
        calendar="Work",
        start=dt.datetime(2026, 8, 15, 9, 10),
        end=dt.datetime(2026, 8, 15, 10, 40),
    )

    assert event_slot_range(event, dt.date(2026, 8, 15)) == (18, 22)


def test_event_slot_range_clamps_events_to_the_day() -> None:
    event = Event(
        summary="Long ordeal",
        calendar="Work",
        start=dt.datetime(2026, 8, 14, 23, 0),
        end=dt.datetime(2026, 8, 16, 1, 0),
    )

    assert event_slot_range(event, dt.date(2026, 8, 15)) == (0, 48)


def test_event_when_label_includes_its_date() -> None:
    event = Event(
        summary="Write a calendar",
        calendar="Personal",
        start=dt.datetime(2026, 8, 15, 13, 30),
        end=dt.datetime(2026, 8, 15, 15, 0),
    )

    assert event.when_label == "Saturday, August 15, 2026 · 13:30–15:00"


def test_multiday_all_day_event_when_label_uses_inclusive_last_day() -> None:
    event = Event(
        summary="Conference",
        calendar="Work",
        start=dt.date(2026, 8, 15),
        end=dt.date(2026, 8, 18),
        all_day=True,
    )

    assert event.when_label == "August 15 – August 17, 2026 · All day"


def test_all_day_event_label() -> None:
    event = Event(
        summary="Escape the calendar mines",
        calendar="Personal",
        start=dt.date(2026, 8, 15),
        end=dt.date(2026, 8, 15),
        all_day=True,
    )

    assert event.time_label == "All day"
