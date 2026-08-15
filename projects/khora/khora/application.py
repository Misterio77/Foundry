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
        for key in ("color-scheme", "gtk-theme", "icon-theme"):
            self._interface_settings.connect(f"changed::{key}", self._on_appearance_changed)
        self._apply_appearance()

    def _install_styles(self) -> None:
        provider = Gtk.CssProvider()
        provider.load_from_string(
            """
            .mini-calendar {
              font-size: 0.82em;
            }

            .mini-calendar .day-button {
              min-width: 26px;
              min-height: 30px;
              margin: 0;
              padding: 1px;
              border-radius: 999px;
            }

            .mini-calendar .selected {
              background-color: @accent_bg_color;
              color: @accent_fg_color;
            }

            .mini-calendar .other-month {
              opacity: 0.45;
            }

            .mini-calendar .today .day-number {
              color: @accent_color;
              font-weight: bold;
            }

            .mini-calendar .selected .day-number {
              color: @accent_fg_color;
            }

            .mini-calendar .weekday {
              opacity: 0.65;
              font-size: 0.8em;
            }

            .mini-calendar .event-dots {
              min-height: 8px;
              font-size: 0.55em;
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
            .timed-event,
            .month-event {
              margin: 1px 2px;
              padding: 3px 5px;
              border-radius: 4px;
              background-color: alpha(@accent_bg_color, 0.14);
            }

            .month-weekdays {
              padding: 8px 0;
              border-bottom: 1px solid alpha(@window_fg_color, 0.15);
            }

            .month-cell {
              padding: 3px;
              border-left: 1px solid alpha(@window_fg_color, 0.1);
              border-bottom: 1px solid alpha(@window_fg_color, 0.1);
            }

            .month-cell.other-month {
              opacity: 0.5;
            }

            .month-cell.today .month-day {
              background-color: @accent_bg_color;
              color: @accent_fg_color;
              border-radius: 999px;
            }

            .month-event {
              min-height: 20px;
              padding: 1px 4px;
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
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 1,
            )

    def _on_appearance_changed(self, *_args) -> None:
        self._apply_appearance()

    def _apply_appearance(self) -> None:
        assert self._interface_settings is not None
        gtk_settings = Gtk.Settings.get_default()
        if gtk_settings is not None:
            gtk_settings.set_property(
                "gtk-theme-name",
                self._interface_settings.get_string("gtk-theme"),
            )
            gtk_settings.set_property(
                "gtk-icon-theme-name",
                self._interface_settings.get_string("icon-theme"),
            )

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
