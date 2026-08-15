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
            .view-tab {
              border-radius: 0;
              border-bottom: 2px solid transparent;
              padding: 8px 14px 6px;
            }

            .view-tab:checked {
              background: transparent;
              border-bottom-color: @accent_color;
              box-shadow: none;
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
