from __future__ import annotations

import datetime as dt

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gio, GLib, Gtk

from .colors import display_color
from .khal_adapter import KhalRepository
from .model import Event, week_dates


class KhoraWindow(Adw.ApplicationWindow):
    def __init__(
        self,
        application: Adw.Application,
        repository: KhalRepository | None,
        error: str | None = None,
    ) -> None:
        super().__init__(application=application, title="Khora")
        self.set_default_size(960, 680)
        self._repository = repository
        self._visible_calendars: set[str] = set()
        self._view_mode = "day"

        self._toolbar = Adw.ToolbarView()
        self.set_content(self._toolbar)
        self._toolbar.add_top_bar(self._build_header())

        if error is not None:
            self._toolbar.set_content(self._error_page(error))
            return

        assert repository is not None
        self._visible_calendars = {calendar.name for calendar in repository.calendars}
        self._agenda_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self._empty = Adw.StatusPage(
            icon_name="x-office-calendar-symbolic",
            title="No events",
            description="A suspiciously peaceful day.",
        )

        split = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL, position=280)
        split.set_start_child(self._build_sidebar())
        split.set_end_child(self._build_agenda())
        split.set_resize_start_child(False)
        split.set_shrink_start_child(False)
        self._toolbar.set_content(split)
        self._refresh()

    def _build_header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()

        today = Gtk.Button(label="Today", action_name="win.today")
        header.pack_start(today)

        view_switcher = Gtk.Box(css_classes=["linked"])
        day = Gtk.ToggleButton(label="Day", active=True)
        week = Gtk.ToggleButton(label="Week", group=day)
        day.connect("toggled", self._on_view_toggled, "day")
        week.connect("toggled", self._on_view_toggled, "week")
        view_switcher.append(day)
        view_switcher.append(week)
        header.set_title_widget(view_switcher)
        header.pack_end(Gtk.Button(icon_name="view-refresh-symbolic", action_name="win.refresh"))

        self._install_action("today", self._on_today)
        self._install_action("refresh", lambda *_: self._refresh())
        return header

    def _build_sidebar(self) -> Gtk.Widget:
        box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=18,
            margin_top=18,
            margin_bottom=18,
            margin_start=18,
            margin_end=18,
        )
        self._calendar = Gtk.Calendar(show_day_names=True, show_heading=True)
        self._calendar.connect("day-selected", lambda *_: self._refresh())
        box.append(self._calendar)
        box.append(Gtk.Label(label="Calendars", xalign=0, css_classes=["heading"]))

        calendars = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        calendars.add_css_class("boxed-list")
        assert self._repository is not None
        for calendar in self._repository.calendars:
            toggle = Gtk.Switch(active=True, valign=Gtk.Align.CENTER)
            toggle.connect("notify::active", self._on_calendar_toggled, calendar.name)
            row = Adw.ActionRow(title=calendar.name, activatable=True)
            row.add_prefix(self._color_dot(calendar.color))
            row.add_suffix(toggle)
            row.set_activatable_widget(toggle)
            calendars.append(row)
        box.append(calendars)
        return box

    def _build_agenda(self) -> Gtk.Widget:
        overlay = Gtk.Overlay()
        scroller = Gtk.ScrolledWindow(
            child=self._agenda_content,
            hscrollbar_policy=Gtk.PolicyType.NEVER,
            margin_top=24,
            margin_bottom=24,
            margin_start=24,
            margin_end=24,
        )
        overlay.set_child(scroller)
        overlay.add_overlay(self._empty)
        return overlay

    def _error_page(self, error: str) -> Adw.StatusPage:
        return Adw.StatusPage(
            icon_name="dialog-error-symbolic",
            title="Could not open khal",
            description=error,
        )

    def _selected_day(self) -> dt.date:
        selected: GLib.DateTime = self._calendar.get_date()
        return dt.date(selected.get_year(), selected.get_month(), selected.get_day_of_month())

    def _refresh(self) -> None:
        if self._repository is None or not hasattr(self, "_agenda_content"):
            return

        days = (
            week_dates(self._selected_day())
            if self._view_mode == "week"
            else (self._selected_day(),)
        )
        try:
            events_by_day = self._repository.events_for_days(days, self._visible_calendars)
        except Exception as error:  # khal exposes several backend-specific errors
            self._show_toast(str(error))
            return

        while child := self._agenda_content.get_first_child():
            self._agenda_content.remove(child)

        has_events = any(events_by_day.values())
        if self._view_mode == "week":
            for day in days:
                self._agenda_content.append(self._day_group(day, events_by_day[day]))
        elif has_events:
            event_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
            event_list.add_css_class("boxed-list")
            for event in events_by_day[days[0]]:
                event_list.append(self._event_row(event))
            self._agenda_content.append(event_list)

        self._empty.set_visible(not has_events and self._view_mode == "day")
        self._agenda_content.set_visible(has_events or self._view_mode == "week")

    @staticmethod
    def _day_group(day: dt.date, events: tuple[Event, ...]) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title=f"{day:%A, %B} {day.day}")
        if events:
            for event in events:
                group.add(KhoraWindow._event_row(event))
        else:
            group.set_description("No events")
        return group

    @staticmethod
    def _event_row(event: Event) -> Adw.ActionRow:
        details = f"{event.time_label} · {event.calendar}"
        if event.location:
            details += f" · {event.location}"
        row = Adw.ActionRow(title=event.summary, subtitle=details)
        row.add_prefix(KhoraWindow._color_dot(event.color))
        return row

    @staticmethod
    def _color_dot(color: str | None) -> Gtk.Label:
        dot = Gtk.Label(valign=Gtk.Align.CENTER)
        dot.set_markup(f'<span foreground="{display_color(color)}" size="18000">●</span>')
        return dot

    def _on_calendar_toggled(self, button: Gtk.Switch, _property, name: str) -> None:
        if button.get_active():
            self._visible_calendars.add(name)
        else:
            self._visible_calendars.discard(name)
        self._refresh()

    def _on_today(self, *_args) -> None:
        self._calendar.select_day(GLib.DateTime.new_now_local())
        self._refresh()

    def _on_view_toggled(self, button: Gtk.ToggleButton, mode: str) -> None:
        if button.get_active():
            self._view_mode = mode
            self._refresh()

    def _install_action(self, name: str, callback) -> None:
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", callback)
        self.add_action(action)

    def _show_toast(self, message: str) -> None:
        dialog = Adw.AlertDialog(heading="Calendar error", body=message)
        dialog.add_response("close", "Close")
        dialog.present(self)
