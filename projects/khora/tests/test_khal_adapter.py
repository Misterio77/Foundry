from khora.khal_adapter import KhalRepository


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
