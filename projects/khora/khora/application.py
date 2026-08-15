from __future__ import annotations

import sys

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gdk, Gio, Gtk

from .khal_adapter import KhalRepository
from .window import KhoraWindow


class KhoraApplication(Adw.Application):
    def __init__(self) -> None:
        super().__init__(application_id="rs.m7.Khora", flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self._interface_settings: Gio.Settings | None = None

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        self._install_styles()
        self._interface_settings = Gio.Settings.new("org.gnome.desktop.interface")
        self._interface_settings.connect("changed::color-scheme", self._on_color_scheme_changed)
        self._apply_color_scheme()

    def _install_styles(self) -> None:
        provider = Gtk.CssProvider()
        provider.load_from_string(
            """
            .mini-calendar {
              font-size: 0.82em;
            }

            .mini-calendar label {
              min-width: 20px;
              min-height: 20px;
              margin: 0;
              padding: 1px;
            }

            .calendar-grid-header {
              background-color: @headerbar_bg_color;
              border-bottom: 1px solid alpha(@window_fg_color, 0.15);
            }

            .day-header {
              min-height: 42px;
              padding: 8px 4px;
              border-left: 1px solid alpha(@window_fg_color, 0.1);
            }

            .all-day-event,
            .timed-event {
              margin: 1px 2px;
              padding: 3px 5px;
              border-radius: 4px;
              background-color: alpha(@accent_bg_color, 0.14);
            }

            .time-label {
              color: alpha(@window_fg_color, 0.6);
              font-size: 0.75em;
            }

            .day-column {
              border-left: 1px solid alpha(@window_fg_color, 0.1);
            }

            .hour-line {
              border-top: 1px solid alpha(@window_fg_color, 0.13);
            }

            .half-hour-line {
              border-top: 1px solid alpha(@window_fg_color, 0.05);
            }

            .current-time-dot,
            .current-time-line {
              background-color: @error_color;
            }

            .current-time-dot {
              border-radius: 999px;
            }
            """
        )
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.add_provider_for_display(
                display,
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )

    def _on_color_scheme_changed(self, *_args) -> None:
        self._apply_color_scheme()

    def _apply_color_scheme(self) -> None:
        assert self._interface_settings is not None
        scheme = self._interface_settings.get_string("color-scheme")
        color_scheme = {
            "prefer-dark": Adw.ColorScheme.FORCE_DARK,
            "prefer-light": Adw.ColorScheme.FORCE_LIGHT,
        }.get(scheme, Adw.ColorScheme.DEFAULT)
        Adw.StyleManager.get_default().set_color_scheme(color_scheme)

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
