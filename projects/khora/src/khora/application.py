from __future__ import annotations

import sys

import gi

gi.require_version("Adw", "1")
from gi.repository import Adw, Gio

from .khal_adapter import KhalRepository
from .window import KhoraWindow


class KhoraApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id="rs.m7.Khora", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self) -> None:
        window = self.get_active_window()
        if window is None:
            try:
                repository = KhalRepository()
                error = None
            except Exception as caught:
                repository = None
                error = str(caught)
            window = KhoraWindow(self, repository, error)
        window.present()


def main() -> int:
    return KhoraApplication().run(sys.argv)
