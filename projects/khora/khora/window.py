from __future__ import annotations

import datetime as dt

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gio, GLib, Gtk, Pango

from .colors import display_color
from .khal_adapter import KhalRepository
from .model import Event, event_slot_range, week_dates


class KhoraWindow(Adw.ApplicationWindow):
    def __init__(
        self,
        application: Adw.Application,
        repository: KhalRepository | None,
        error: str | None = None,
    ) -> None:
        super().__init__(application=application, title="Khora")
        self.set_default_size(1280, 800)
        self._repository = repository
        self._visible_calendars: set[str] = set()
        self._view_mode = "week"

        self._toolbar = Adw.ToolbarView()
        self.set_content(self._toolbar)
        self._toolbar.add_top_bar(self._build_header())

        if error is not None:
            self._toolbar.set_content(self._error_page(error))
            return

        assert repository is not None
        self._visible_calendars = {calendar.name for calendar in repository.calendars}
        self._view_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._empty = Adw.StatusPage(
            icon_name="x-office-calendar-symbolic",
            title="No events",
            description="A suspiciously peaceful day.",
        )

        split = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL, position=260)
        split.set_start_child(self._build_sidebar())
        split.set_end_child(self._build_calendar_view())
        split.set_resize_start_child(False)
        split.set_shrink_start_child(False)
        self._toolbar.set_content(split)
        self._refresh()

    def _build_header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        header.pack_start(Gtk.Button(label="Today", action_name="win.today"))

        menu = Gio.Menu()
        for mode in ("day", "week", "month", "agenda"):
            menu.append(mode.title(), f"win.view::{mode}")
        self._view_button = Gtk.MenuButton(label="Week", menu_model=menu)
        header.set_title_widget(self._view_button)
        header.pack_end(Gtk.Button(icon_name="view-refresh-symbolic", action_name="win.refresh"))

        self._install_action("today", self._on_today)
        self._install_action("refresh", lambda *_: self._refresh())
        view_action = Gio.SimpleAction.new("view", GLib.VariantType.new("s"))
        view_action.connect("activate", self._on_view_selected)
        self.add_action(view_action)
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

    def _build_calendar_view(self) -> Gtk.Widget:
        overlay = Gtk.Overlay()
        scroller = Gtk.ScrolledWindow(
            child=self._view_content,
            hscrollbar_policy=Gtk.PolicyType.NEVER,
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
        if self._repository is None or not hasattr(self, "_view_content"):
            return

        self._clear_view()
        self._empty.set_visible(False)
        if self._view_mode == "month":
            self._view_content.append(
                Adw.StatusPage(
                    icon_name="x-office-calendar-symbolic",
                    title="Month view",
                    description="Coming next.",
                    vexpand=True,
                )
            )
            return

        days = self._visible_days()
        try:
            events_by_day = self._repository.events_for_days(days, self._visible_calendars)
        except Exception as error:  # khal exposes several backend-specific errors
            self._show_toast(str(error))
            return

        if self._view_mode == "agenda":
            self._render_agenda(days[0], events_by_day[days[0]])
        else:
            self._view_content.append(self._time_grid(days, events_by_day))

    def _visible_days(self) -> tuple[dt.date, ...]:
        if self._view_mode == "week":
            return week_dates(self._selected_day())
        return (self._selected_day(),)

    def _clear_view(self) -> None:
        while child := self._view_content.get_first_child():
            self._view_content.remove(child)

    def _render_agenda(self, day: dt.date, events: tuple[Event, ...]) -> None:
        if not events:
            self._empty.set_visible(True)
            return

        group = Adw.PreferencesGroup(
            title=f"{day:%A, %B} {day.day}",
            margin_top=24,
            margin_bottom=24,
            margin_start=24,
            margin_end=24,
        )
        for event in events:
            group.add(self._event_row(event))
        self._view_content.append(group)

    def _time_grid(
        self,
        days: tuple[dt.date, ...],
        events_by_day: dict[dt.date, tuple[Event, ...]],
    ) -> Gtk.Widget:
        view = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        view.append(self._day_headers(days, events_by_day))

        timeline = Gtk.Box()
        timeline.append(self._time_gutter())
        columns = Gtk.Box(homogeneous=True, hexpand=True)
        for day in days:
            timed = tuple(event for event in events_by_day[day] if not event.all_day)
            columns.append(self._day_column(day, timed))
        timeline.append(columns)
        view.append(timeline)
        return view

    def _day_headers(
        self,
        days: tuple[dt.date, ...],
        events_by_day: dict[dt.date, tuple[Event, ...]],
    ) -> Gtk.Widget:
        row = Gtk.Box(css_classes=["calendar-grid-header"])
        row.append(Gtk.Box(width_request=64))
        headers = Gtk.Box(homogeneous=True, hexpand=True)
        today = dt.date.today()
        for day in days:
            box = Gtk.Box(
                orientation=Gtk.Orientation.VERTICAL,
                spacing=4,
                css_classes=["day-header"],
            )
            label = Gtk.Label(label=f"{day:%a}  {day.day}")
            if day == today:
                label.add_css_class("accent")
            box.append(label)
            all_day = tuple(event for event in events_by_day[day] if event.all_day)
            for event in all_day:
                event_label = Gtk.Label(
                    label=event.summary,
                    xalign=0,
                    ellipsize=Pango.EllipsizeMode.END,
                    tooltip_text=event.summary,
                    css_classes=["all-day-event"],
                )
                box.append(event_label)
            headers.append(box)
        row.append(headers)
        return row

    @staticmethod
    def _time_gutter() -> Gtk.Widget:
        gutter = Gtk.Grid(row_homogeneous=True, width_request=64)
        for slot in range(48):
            label = Gtk.Label(
                label=f"{slot // 2:02}:00" if slot % 2 == 0 else "",
                xalign=1,
                yalign=0,
                margin_end=8,
                css_classes=["time-label"],
            )
            label.set_size_request(-1, 24)
            gutter.attach(label, 0, slot, 1, 1)
        return gutter

    @staticmethod
    def _day_column(day: dt.date, events: tuple[Event, ...]) -> Gtk.Widget:
        column = Gtk.Grid(row_homogeneous=True, hexpand=True, css_classes=["day-column"])
        for slot in range(48):
            line = Gtk.Box(css_classes=["hour-line" if slot % 2 == 0 else "half-hour-line"])
            line.set_size_request(-1, 24)
            column.attach(line, 0, slot, 1, 1)

        for event in events:
            start, end = event_slot_range(event, day)
            label = Gtk.Label(
                xalign=0,
                yalign=0,
                wrap=True,
                lines=2,
                ellipsize=Pango.EllipsizeMode.END,
                tooltip_text=f"{event.time_label} · {event.summary}",
                css_classes=["timed-event"],
            )
            summary = GLib.markup_escape_text(event.summary)
            color = display_color(event.color)
            label.set_markup(
                f'<span foreground="{color}">▌</span> '
                f"<b>{summary}</b>\n<small>{event.time_label}</small>"
            )
            column.attach(label, 0, start, 1, end - start)
        return column

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

    def _on_view_selected(self, _action: Gio.SimpleAction, parameter: GLib.Variant) -> None:
        self._view_mode = parameter.get_string()
        self._view_button.set_label(self._view_mode.title())
        self._refresh()

    def _install_action(self, name: str, callback) -> None:
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", callback)
        self.add_action(action)

    def _show_toast(self, message: str) -> None:
        dialog = Adw.AlertDialog(heading="Calendar error", body=message)
        dialog.add_response("close", "Close")
        dialog.present(self)
