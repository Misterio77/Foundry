from gtkhal.state import StateStore, UiState


def test_round_trips_ui_state(tmp_path) -> None:
    store = StateStore(tmp_path / "state.json")
    state = UiState(
        view="agenda",
        slot_height=32,
        sidebar_width=300,
        visible_calendars=("Personal", "Work"),
        collapsed_accounts=("university",),
    )

    assert store.save(state)
    assert store.load() == state


def test_missing_or_malformed_state_uses_defaults(tmp_path) -> None:
    store = StateStore(tmp_path / "state.json")
    assert store.load() == UiState()

    store.path.write_text("calendar goblins")
    assert store.load() == UiState()
