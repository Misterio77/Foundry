from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class UiState:
    view: str = "week"
    slot_height: int = 24
    sidebar_width: int = 280
    visible_calendars: tuple[str, ...] | None = None
    collapsed_accounts: tuple[str, ...] = ()


class StateStore:
    def __init__(self, path: Path | None = None) -> None:
        state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        self.path = path or state_home / "khora" / "state.json"

    def load(self) -> UiState:
        try:
            data = json.loads(self.path.read_text())
            return UiState(
                view=data.get("view", "week"),
                slot_height=int(data.get("slot_height", 24)),
                sidebar_width=int(data.get("sidebar_width", 280)),
                visible_calendars=self._strings_or_none(data.get("visible_calendars")),
                collapsed_accounts=self._strings(data.get("collapsed_accounts", ())),
            )
        except (OSError, TypeError, ValueError, json.JSONDecodeError):
            return UiState()

    def save(self, state: UiState) -> bool:
        temporary = self.path.with_suffix(".tmp")
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary.write_text(json.dumps(asdict(state), indent=2, sort_keys=True) + "\n")
            temporary.replace(self.path)
            return True
        except OSError:
            temporary.unlink(missing_ok=True)
            return False

    @staticmethod
    def _strings(value: object) -> tuple[str, ...]:
        if not isinstance(value, (list, tuple)):
            return ()
        return tuple(item for item in value if isinstance(item, str))

    @classmethod
    def _strings_or_none(cls, value: object) -> tuple[str, ...] | None:
        return None if value is None else cls._strings(value)
