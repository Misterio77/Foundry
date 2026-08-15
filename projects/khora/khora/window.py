from __future__ import annotations

import datetime as dt

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango

from .colors import contrasting_foreground, display_color
from .khal_adapter import KhalRepository
from .mini_calendar import MiniCalendar
from .model import (
    Calendar,
    Event,
    EventPlacement,
    layout_event_lanes,
    month_grid_dates,
    period_label,
    shifted_date,
    week_dates,
)
from .state import StateStore, UiState


SIDEBAR_WIDTH = 280
DEFAULT_SLOT_HEIGHT = 24
MIN_SLOT_HEIGHT = 12
MAX_SLOT_HEIGHT = 64
ZOOM_STEP = 4
AGENDA_CHUNK_DAYS = 14
MAX_EMPTY_AGENDA_CHUNKS = 6


class EventLayer(Gtk.Fixed):
    def __init__(self, slot_height: int) -> None:
        super().__init__(hexpand=True, vexpand=True)
        self._slot_height = slot_height
        self._events: list[tuple[Gtk.Widget, EventPlacement]] = []
        self._last_width = -1
        self.add_tick_callback(self._layout_events)

    def add_event(self, widget: Gtk.Widget, placement: EventPlacement) -> None:
        self._events.append((widget, placement))
        widget.set_size_request(
            -1,
            (placement.end_slot - placement.start_slot) * self._slot_height,
        )
        self.put(widget, 0, placement.start_slot * self._slot_height)

    def _layout_events(self, _widget: Gtk.Widget, _frame_clock: Gdk.FrameClock) -> bool:
        width = self.get_width()
        if width <= 0 or width == self._last_width:
            return GLib.SOURCE_CONTINUE
        self._last_width = width
        for widget, placement in self._events:
            left = round(width * placement.lane / placement.lane_count)
            right = round(width * (placement.lane + 1) / placement.lane_count)
            widget.set_size_request(
                max(1, right - left),
                (placement.end_slot - placement.start_slot) * self._slot_height,
            )
            self.move(widget, left, placement.start_slot * self._slot_height)
        return GLib.SOURCE_CONTINUE


class KhoraWindow(Adw.ApplicationWindow):
    def __init__(
        self,
        application: Adw.Application,
        repository: KhalRepository | None,
        error: str | None = None,
        state_store: StateStore | None = None,
    ) -> None:
        super().__init__(application=application, title="Khora")
        self.set_default_size(1280, 800)
        self._repository = repository
        self._state_store = state_store or StateStore()
        self._state = self._state_store.load()
        self._save_source = 0
        self._refresh_source = 0
        self._file_monitors: list[Gio.FileMonitor] = []
        self._visible_calendars: set[str] = set()
        self._collapsed_accounts = set(self._state.collapsed_accounts)
        self._view_mode = (
            self._state.view
            if self._state.view in {"day", "week", "month", "agenda"}
            else "week"
        )

        self._toolbar = Adw.ToolbarView()
        self.set_content(self._toolbar)
        self._toolbar.add_top_bar(self._build_header())
        self._install_accelerators(application)

        if error is not None:
            self._toolbar.set_content(self._error_page(error))
            return

        assert repository is not None
        calendar_names = {calendar.name for calendar in repository.calendars}
        self._visible_calendars = (
            calendar_names
            if self._state.visible_calendars is None
            else calendar_names & set(self._state.visible_calendars)
        )
        self._event_color_providers: dict[str, Gtk.CssProvider] = {}
        self._view_content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._slot_height = max(
            MIN_SLOT_HEIGHT,
            min(MAX_SLOT_HEIGHT, self._state.slot_height),
        )
        self._zoom_scroll_accumulator = 0.0
        self._displayed_days: tuple[dt.date, ...] = ()
        self._displayed_events: dict[dt.date, tuple[Event, ...]] = {}
        self._agenda_next_day = dt.date.today()
        self._agenda_loading = False
        self._agenda_empty_chunks = 0
        self._agenda_load_more: Gtk.Button | None = None
        self._time_indicator: Gtk.Widget | None = None
        self._rendered_today = dt.date.today()
        self._empty = Adw.StatusPage(
            icon_name="x-office-calendar-symbolic",
            title="No events",
            description="A suspiciously peaceful day.",
        )

        self._split = Gtk.Paned(
            orientation=Gtk.Orientation.HORIZONTAL,
            position=max(280, min(600, self._state.sidebar_width)),
        )
        self._split.set_start_child(self._build_sidebar())
        self._split.set_end_child(self._build_calendar_view())
        self._split.set_resize_start_child(False)
        self._split.set_shrink_start_child(False)
        self._split.connect("notify::position", lambda *_: self._schedule_state_save())
        self._toolbar.set_content(self._split)
        self._refresh()
        self._refresh_mini_calendar()
        self._install_file_monitors()
        self._clock_source = GLib.timeout_add_seconds(30, self._on_clock_tick)
        self.connect("close-request", self._on_close_request)

    def _build_header(self) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        header.set_title_widget(Gtk.Box())

        header.pack_start(Gtk.Box(width_request=SIDEBAR_WIDTH - 12))
        header.pack_start(Gtk.Button(label="Today", action_name="win.today"))

        navigation = Gtk.Box()
        previous = Gtk.Button(
            icon_name="go-previous-symbolic",
            action_name="win.previous",
            css_classes=["flat"],
            tooltip_text="Previous period",
        )
        following = Gtk.Button(
            icon_name="go-next-symbolic",
            action_name="win.next",
            css_classes=["flat"],
            tooltip_text="Next period",
        )
        navigation.append(previous)
        navigation.append(following)
        header.pack_start(navigation)

        self._period_label = Gtk.Label(css_classes=["title"], margin_start=6)
        header.pack_start(self._period_label)

        menu = Gio.Menu()
        for mode in ("day", "week", "month", "agenda"):
            menu.append(mode.title(), f"win.view::{mode}")
        self._view_button = Gtk.MenuButton(label=self._view_mode.title(), menu_model=menu)

        controls = Gtk.Box(spacing=6)
        controls.append(
            Gtk.Button(
                icon_name="view-refresh-symbolic",
                action_name="win.refresh",
                tooltip_text="Refresh calendars",
            )
        )
        controls.append(self._view_button)
        header.pack_end(controls)

        self._install_action("today", self._on_today)
        self._install_action("previous", lambda *_: self._navigate(-1))
        self._install_action("next", lambda *_: self._navigate(1))
        self._install_action("refresh", lambda *_: self._refresh_all())
        self._install_action("zoom-in", lambda *_: self._zoom_time_grid(1))
        self._install_action("zoom-out", lambda *_: self._zoom_time_grid(-1))
        self._install_action("zoom-reset", lambda *_: self._set_time_grid_zoom(DEFAULT_SLOT_HEIGHT))
        view_action = Gio.SimpleAction.new("view", GLib.VariantType.new("s"))
        view_action.connect("activate", self._on_view_selected)
        self.add_action(view_action)
        return header

    def _build_sidebar(self) -> Gtk.Widget:
        box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=14,
            margin_top=12,
            margin_bottom=12,
            margin_start=10,
            margin_end=10,
            css_classes=["sidebar"],
        )
        self._calendar = MiniCalendar()
        self._calendar.connect("day-selected", lambda *_: self._refresh())
        self._calendar.connect("month-changed", lambda *_: self._refresh_mini_calendar())
        box.append(self._calendar)
        box.append(Gtk.Label(label="Calendars", xalign=0, css_classes=["heading"]))

        groups = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=18,
            margin_bottom=6,
        )
        assert self._repository is not None
        calendars_by_account: dict[str, list[Calendar]] = {}
        for calendar in self._repository.calendars:
            calendars_by_account.setdefault(calendar.account, []).append(calendar)

        for account, calendars in calendars_by_account.items():
            account_list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
            account_list.add_css_class("boxed-list")
            account_row = Adw.ExpanderRow(
                title=self._account_label(account),
                expanded=account not in self._collapsed_accounts,
            )
            account_row.connect("notify::expanded", self._on_account_expanded, account)
            for calendar in calendars:
                toggle = Gtk.Switch(
                    active=calendar.name in self._visible_calendars,
                    valign=Gtk.Align.CENTER,
                )
                toggle.connect("notify::active", self._on_calendar_toggled, calendar.name)
                row = Adw.ActionRow(title=calendar.name, activatable=True)
                row.add_prefix(self._color_dot(calendar.color))
                row.add_suffix(toggle)
                row.set_activatable_widget(toggle)
                account_row.add_row(row)
            account_list.append(account_row)
            groups.append(account_list)

        box.append(
            Gtk.ScrolledWindow(
                child=groups,
                hscrollbar_policy=Gtk.PolicyType.NEVER,
                vexpand=True,
            )
        )
        return box

    @staticmethod
    def _account_label(account: str) -> str:
        return account.replace("-", " ").replace("_", " ").title()

    def _build_calendar_view(self) -> Gtk.Widget:
        overlay = Gtk.Overlay()
        self._calendar_scroller = Gtk.ScrolledWindow(
            child=self._view_content,
            hscrollbar_policy=Gtk.PolicyType.NEVER,
        )
        zoom_controller = Gtk.EventControllerScroll(
            flags=Gtk.EventControllerScrollFlags.VERTICAL,
        )
        zoom_controller.connect("scroll", self._on_time_grid_scroll)
        self._calendar_scroller.add_controller(zoom_controller)
        self._calendar_scroller.get_vadjustment().connect(
            "value-changed",
            self._on_calendar_scroll,
        )
        overlay.set_child(self._calendar_scroller)
        overlay.add_overlay(self._empty)
        return overlay

    def _install_file_monitors(self) -> None:
        assert self._repository is not None
        for path in getattr(self._repository, "watch_paths", ()):
            try:
                monitor = Gio.File.new_for_path(str(path)).monitor_directory(
                    Gio.FileMonitorFlags.WATCH_MOVES,
                    None,
                )
            except GLib.Error:
                continue
            monitor.connect("changed", self._on_vdir_changed)
            self._file_monitors.append(monitor)

    def _on_vdir_changed(self, *_args) -> None:
        if self._refresh_source:
            GLib.source_remove(self._refresh_source)
        self._refresh_source = GLib.timeout_add(500, self._refresh_after_vdir_change)

    def _refresh_after_vdir_change(self) -> bool:
        self._refresh_source = 0
        self._refresh_all()
        return GLib.SOURCE_REMOVE

    def _error_page(self, error: str) -> Adw.StatusPage:
        return Adw.StatusPage(
            icon_name="dialog-error-symbolic",
            title="Could not open khal",
            description=error,
        )

    def _selected_day(self) -> dt.date:
        return self._calendar.selected_day

    def _refresh_all(self) -> None:
        self._refresh()
        self._refresh_mini_calendar()

    def _refresh_mini_calendar(self) -> None:
        if self._repository is None or not hasattr(self, "_calendar"):
            return
        days = self._calendar.visible_days
        try:
            events_by_day = self._repository.events_for_days(days, self._visible_calendars)
        except Exception as error:  # khal exposes several backend-specific errors
            self._show_toast(str(error))
            return
        self._calendar.set_event_colors(
            {
                day: tuple(event.color for event in events_by_day[day])
                for day in days
                if events_by_day[day]
            }
        )

    def _refresh(self) -> None:
        if self._repository is None or not hasattr(self, "_view_content"):
            return

        self._rendered_today = dt.date.today()
        self._period_label.set_label(period_label(self._selected_day(), self._view_mode))
        self._clear_view()
        self._empty.set_visible(False)
        if self._view_mode == "agenda":
            self._start_agenda()
            return

        days = self._visible_days()
        try:
            events_by_day = self._repository.events_for_days(days, self._visible_calendars)
        except Exception as error:  # khal exposes several backend-specific errors
            self._show_toast(str(error))
            return

        self._displayed_days = days
        self._displayed_events = events_by_day
        if self._view_mode == "month":
            self._view_content.append(self._month_grid(days, events_by_day))
        else:
            self._view_content.append(self._time_grid(days, events_by_day))

    def _visible_days(self) -> tuple[dt.date, ...]:
        if self._view_mode == "week":
            return week_dates(self._selected_day())
        if self._view_mode == "month":
            return month_grid_dates(self._selected_day())
        return (self._selected_day(),)

    def _clear_view(self) -> None:
        self._time_indicator = None
        while child := self._view_content.get_first_child():
            self._view_content.remove(child)

    def _start_agenda(self) -> None:
        self._agenda_next_day = self._selected_day()
        self._agenda_empty_chunks = 0
        self._agenda_load_more = None
        self._load_more_agenda()

    def _load_more_agenda(self, *_args) -> None:
        if self._agenda_loading or self._repository is None or self._view_mode != "agenda":
            return
        self._agenda_loading = True
        if (
            self._agenda_load_more is not None
            and self._agenda_load_more.get_parent() is self._view_content
        ):
            self._view_content.remove(self._agenda_load_more)

        days = tuple(
            self._agenda_next_day + dt.timedelta(days=offset)
            for offset in range(AGENDA_CHUNK_DAYS)
        )
        try:
            events_by_day = self._repository.events_for_days(days, self._visible_calendars)
        except Exception as error:  # khal exposes several backend-specific errors
            self._show_toast(str(error))
            self._agenda_loading = False
            return

        found_events = False
        for day in days:
            events = events_by_day[day]
            if not events:
                continue
            found_events = True
            group = Adw.PreferencesGroup(
                title=f"{day:%A, %B} {day.day}",
                margin_top=24,
                margin_start=24,
                margin_end=24,
            )
            for event in events:
                group.add(self._event_row(event))
            self._view_content.append(group)

        self._agenda_next_day = days[-1] + dt.timedelta(days=1)
        self._agenda_load_more = Gtk.Button(
            label="Load more",
            halign=Gtk.Align.CENTER,
            margin_top=12,
            margin_bottom=24,
        )
        self._agenda_load_more.connect("clicked", self._load_more_agenda)
        self._view_content.append(self._agenda_load_more)
        self._agenda_loading = False

        if found_events:
            self._agenda_empty_chunks = 0
        else:
            self._agenda_empty_chunks += 1
            if self._agenda_empty_chunks < MAX_EMPTY_AGENDA_CHUNKS:
                GLib.idle_add(self._load_next_empty_agenda_chunk)

    def _load_next_empty_agenda_chunk(self) -> bool:
        self._load_more_agenda()
        return GLib.SOURCE_REMOVE

    def _on_calendar_scroll(self, adjustment: Gtk.Adjustment) -> None:
        if self._view_mode != "agenda" or self._agenda_loading:
            return
        if (
            adjustment.get_value() + adjustment.get_page_size()
            >= adjustment.get_upper() - 240
        ):
            self._load_more_agenda()

    def _month_grid(
        self,
        days: tuple[dt.date, ...],
        events_by_day: dict[dt.date, tuple[Event, ...]],
    ) -> Gtk.Widget:
        view = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        weekdays = Gtk.Box(homogeneous=True, css_classes=["month-weekdays"])
        monday = dt.date(2024, 1, 1)
        for offset in range(7):
            weekdays.append(
                Gtk.Label(
                    label=f"{monday + dt.timedelta(days=offset):%A}",
                    css_classes=["heading"],
                )
            )
        view.append(weekdays)

        grid = Gtk.Grid(
            column_homogeneous=True,
            row_homogeneous=True,
            hexpand=True,
            vexpand=True,
        )
        selected_month = self._selected_day().month
        today = dt.date.today()
        for index, day in enumerate(days):
            classes = ["month-cell"]
            if day.month != selected_month:
                classes.append("other-month")
            if day == today:
                classes.append("today")
            cell = Gtk.Box(
                orientation=Gtk.Orientation.VERTICAL,
                spacing=2,
                height_request=108,
                css_classes=classes,
            )
            day_button = Gtk.Button(
                label=str(day.day),
                halign=Gtk.Align.END,
                css_classes=["flat", "month-day"],
                tooltip_text=f"Open {day:%A, %B} {day.day}",
            )
            day_button.connect(
                "clicked",
                lambda _button, selected=day: self._open_date(selected, "day"),
            )
            cell.append(day_button)

            events = events_by_day[day]
            for event in events[:3]:
                prefix = "" if event.all_day else f"{event.start:%H:%M} "
                label = Gtk.Label(
                    label=f"{prefix}{event.summary}",
                    xalign=0,
                    ellipsize=Pango.EllipsizeMode.END,
                )
                event_button = Gtk.Button(
                    child=label,
                    tooltip_text=f"{event.time_label} · {event.summary}",
                    css_classes=[
                        "flat",
                        "month-event",
                        self._event_color_class(event.color),
                    ],
                )
                event_button.connect(
                    "clicked",
                    lambda _button, item=event: self._show_event(item),
                )
                cell.append(event_button)
            if len(events) > 3:
                overflow = Gtk.Button(
                    label=f"+{len(events) - 3} more",
                    halign=Gtk.Align.START,
                    css_classes=["flat", "caption"],
                )
                overflow.connect(
                    "clicked",
                    lambda _button, selected=day: self._open_date(selected, "agenda"),
                )
                cell.append(overflow)

            row, column = divmod(index, 7)
            grid.attach(cell, column, row, 1, 1)
        view.append(grid)
        return view

    def _open_date(self, day: dt.date, view: str) -> None:
        self._view_mode = view
        self._view_button.set_label(view.title())
        self._schedule_state_save()
        self._calendar.select_day(day)

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
                )
                event_button = Gtk.Button(
                    child=event_label,
                    tooltip_text=event.summary,
                    css_classes=[
                        "flat",
                        "all-day-event",
                        self._event_color_class(event.color),
                    ],
                )
                event_button.connect("clicked", lambda _button, item=event: self._show_event(item))
                box.append(event_button)
            headers.append(box)
        row.append(headers)
        return row

    def _time_gutter(self) -> Gtk.Widget:
        gutter = Gtk.Grid(row_homogeneous=True, width_request=64)
        for slot in range(48):
            label = Gtk.Label(
                label=f"{slot // 2:02}:00" if slot % 2 == 0 else "",
                xalign=1,
                yalign=0,
                margin_end=8,
                css_classes=["time-label"],
            )
            label.set_size_request(-1, self._slot_height)
            gutter.attach(label, 0, slot, 1, 1)
        return gutter

    def _day_column(self, day: dt.date, events: tuple[Event, ...]) -> Gtk.Widget:
        column = Gtk.Grid(row_homogeneous=True, hexpand=True, css_classes=["day-column"])
        for slot in range(48):
            line = Gtk.Box(css_classes=["hour-line" if slot % 2 == 0 else "half-hour-line"])
            line.set_size_request(-1, self._slot_height)
            column.attach(line, 0, slot, 1, 1)

        overlay = Gtk.Overlay(child=column)
        placements = layout_event_lanes(events, day)
        if placements:
            event_layer = EventLayer(self._slot_height)
            for placement in placements:
                event_layer.add_event(
                    self._timed_event_button(
                        placement.event,
                        (placement.end_slot - placement.start_slot) * self._slot_height,
                    ),
                    placement,
                )
            overlay.add_overlay(event_layer)
            overlay.set_measure_overlay(event_layer, False)
            overlay.set_clip_overlay(event_layer, True)

        if day == dt.date.today():
            indicator = self._current_time_indicator()
            overlay.add_overlay(indicator)
            overlay.set_measure_overlay(indicator, False)
            overlay.set_clip_overlay(indicator, False)
        return overlay

    def _timed_event_button(self, event: Event, event_height: int) -> Gtk.Button:
        label = Gtk.Label(
            xalign=0,
            yalign=0,
            wrap=event_height >= 40,
            lines=2 if event_height >= 40 else 1,
            ellipsize=Pango.EllipsizeMode.END,
        )
        summary = GLib.markup_escape_text(event.summary)
        if event_height >= 40:
            label.set_markup(f"<b>{summary}</b>\n<small>{event.time_label}</small>")
        elif event_height >= 22:
            label.set_markup(f"<b>{summary}</b>")
        button = Gtk.Button(
            child=label,
            tooltip_text=f"{event.time_label} · {event.summary}",
            css_classes=[
                "flat",
                "timed-event",
                self._event_color_class(event.color),
            ],
        )
        button.connect("clicked", lambda _button: self._show_event(event))
        return button

    def _current_time_indicator(self) -> Gtk.Widget:
        indicator = Gtk.Box(
            valign=Gtk.Align.START,
            can_target=False,
            css_classes=["current-time-indicator"],
        )
        indicator.append(
            Gtk.Box(
                width_request=8,
                height_request=8,
                valign=Gtk.Align.CENTER,
                css_classes=["current-time-dot"],
            )
        )
        indicator.append(
            Gtk.Box(
                height_request=2,
                hexpand=True,
                valign=Gtk.Align.CENTER,
                css_classes=["current-time-line"],
            )
        )
        self._time_indicator = indicator
        self._position_time_indicator()
        return indicator

    def _position_time_indicator(self) -> None:
        if self._time_indicator is None:
            return
        now = dt.datetime.now()
        elapsed_minutes = now.hour * 60 + now.minute + now.second / 60
        offset = round(elapsed_minutes / (24 * 60) * (48 * self._slot_height))
        self._time_indicator.set_margin_top(max(0, offset - 4))

    def _event_color_class(self, value: str | None) -> str:
        color = display_color(value)
        class_name = f"event-color-{color.lstrip('#').lower()}"
        if class_name not in self._event_color_providers:
            provider = Gtk.CssProvider()
            foreground = contrasting_foreground(value)
            provider.load_from_string(
                f"""
                .timed-event.{class_name},
                .all-day-event.{class_name},
                .month-event.{class_name} {{
                  background: {color};
                  color: {foreground};
                }}
                """
            )
            Gtk.StyleContext.add_provider_for_display(
                self.get_display(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 1,
            )
            self._event_color_providers[class_name] = provider
        return class_name

    def _event_row(self, event: Event) -> Adw.ActionRow:
        details = f"{event.time_label} · {event.calendar}"
        if event.location:
            details += f" · {event.location}"
        row = Adw.ActionRow(title=event.summary, subtitle=details, activatable=True)
        row.add_prefix(self._color_dot(event.color))
        row.connect("activated", lambda _row: self._show_event(event))
        return row

    def _show_event(self, event: Event) -> None:
        details = Adw.PreferencesGroup()
        calendar = Adw.ActionRow(title="Calendar", subtitle=event.calendar)
        calendar.add_prefix(self._color_dot(event.color))
        details.add(calendar)

        for title, value in (
            ("Location", event.location),
            ("Organizer", event.organizer),
            ("Attendees", event.attendees),
            ("Description", event.description),
        ):
            if value:
                details.add(
                    Adw.ActionRow(
                        title=title,
                        subtitle=value,
                        subtitle_lines=0,
                        subtitle_selectable=True,
                    )
                )

        if event.url:
            website = Adw.ActionRow(title="Website")
            website.add_suffix(Gtk.LinkButton(uri=event.url, label="Open link"))
            details.add(website)

        dialog = Adw.AlertDialog(
            heading=event.summary,
            body=event.when_label,
            extra_child=details,
            content_width=520,
        )
        dialog.add_response("close", "Close")
        dialog.present(self)

    @staticmethod
    def _color_dot(color: str | None) -> Gtk.Label:
        dot = Gtk.Label(valign=Gtk.Align.CENTER)
        dot.set_markup(f'<span foreground="{display_color(color)}" size="18000">●</span>')
        return dot

    def _on_account_expanded(
        self,
        row: Adw.ExpanderRow,
        _property,
        account: str,
    ) -> None:
        if row.get_expanded():
            self._collapsed_accounts.discard(account)
        else:
            self._collapsed_accounts.add(account)
        self._schedule_state_save()

    def _on_calendar_toggled(self, button: Gtk.Switch, _property, name: str) -> None:
        if button.get_active():
            self._visible_calendars.add(name)
        else:
            self._visible_calendars.discard(name)
        self._schedule_state_save()
        self._refresh_all()

    def _on_today(self, *_args) -> None:
        self._calendar.select_day(dt.date.today())

    def _navigate(self, direction: int) -> None:
        target = shifted_date(self._selected_day(), self._view_mode, direction)
        self._calendar.select_day(target)

    def _on_view_selected(self, _action: Gio.SimpleAction, parameter: GLib.Variant) -> None:
        self._view_mode = parameter.get_string()
        self._view_button.set_label(self._view_mode.title())
        self._schedule_state_save()
        self._refresh()

    def _on_time_grid_scroll(
        self,
        controller: Gtk.EventControllerScroll,
        _dx: float,
        dy: float,
    ) -> bool:
        modifiers = controller.get_current_event_state()
        if self._view_mode not in {"day", "week"} or not (
            modifiers & Gdk.ModifierType.CONTROL_MASK
        ):
            return False

        self._zoom_scroll_accumulator += dy
        if abs(self._zoom_scroll_accumulator) < 0.5:
            return True

        direction = -1 if self._zoom_scroll_accumulator > 0 else 1
        self._zoom_scroll_accumulator = 0.0
        self._zoom_time_grid(direction)
        return True

    def _zoom_time_grid(self, direction: int) -> None:
        self._set_time_grid_zoom(self._slot_height + direction * ZOOM_STEP)

    def _set_time_grid_zoom(self, slot_height: int) -> None:
        slot_height = max(MIN_SLOT_HEIGHT, min(MAX_SLOT_HEIGHT, slot_height))
        if (
            self._view_mode not in {"day", "week"}
            or slot_height == self._slot_height
            or not self._displayed_days
        ):
            return

        adjustment = self._calendar_scroller.get_vadjustment()
        focus = (adjustment.get_value() + adjustment.get_page_size() / 2) / max(
            adjustment.get_upper(),
            1,
        )
        self._slot_height = slot_height
        self._schedule_state_save()
        self._clear_view()
        self._view_content.append(self._time_grid(self._displayed_days, self._displayed_events))
        GLib.idle_add(self._restore_zoom_position, focus)

    def _restore_zoom_position(self, focus: float) -> bool:
        adjustment = self._calendar_scroller.get_vadjustment()
        value = focus * adjustment.get_upper() - adjustment.get_page_size() / 2
        upper = max(adjustment.get_lower(), adjustment.get_upper() - adjustment.get_page_size())
        adjustment.set_value(max(adjustment.get_lower(), min(value, upper)))
        return GLib.SOURCE_REMOVE

    def _on_clock_tick(self) -> bool:
        today = dt.date.today()
        if self._view_mode in {"day", "week"} and today != self._rendered_today:
            self._rendered_today = today
            self._refresh_all()
        else:
            self._position_time_indicator()
        return GLib.SOURCE_CONTINUE

    def _on_close_request(self, *_args) -> bool:
        if self._clock_source:
            GLib.source_remove(self._clock_source)
            self._clock_source = 0
        if self._save_source:
            GLib.source_remove(self._save_source)
            self._save_source = 0
        if self._refresh_source:
            GLib.source_remove(self._refresh_source)
            self._refresh_source = 0
        for monitor in self._file_monitors:
            monitor.cancel()
        self._file_monitors.clear()
        self._save_state()
        return False

    def _schedule_state_save(self) -> None:
        if self._save_source:
            GLib.source_remove(self._save_source)
        self._save_source = GLib.timeout_add(500, self._save_state)

    def _save_state(self) -> bool:
        self._save_source = 0
        self._state_store.save(
            UiState(
                view=self._view_mode,
                slot_height=self._slot_height,
                sidebar_width=self._split.get_position(),
                visible_calendars=tuple(sorted(self._visible_calendars)),
                collapsed_accounts=tuple(sorted(self._collapsed_accounts)),
            )
        )
        return GLib.SOURCE_REMOVE

    @staticmethod
    def _install_accelerators(application: Adw.Application) -> None:
        shortcuts = {
            "win.today": ("t",),
            "win.previous": ("k", "p", "Page_Up", "<Alt>Left"),
            "win.next": ("j", "n", "Page_Down", "<Alt>Right"),
            "win.refresh": ("r", "<Primary>r"),
            "win.view::day": ("d",),
            "win.view::week": ("w",),
            "win.view::month": ("m",),
            "win.view::agenda": ("a",),
            "win.zoom-in": ("<Primary>plus", "<Primary>equal"),
            "win.zoom-out": ("<Primary>minus",),
            "win.zoom-reset": ("<Primary>0",),
        }
        for action, accelerators in shortcuts.items():
            application.set_accels_for_action(action, accelerators)

    def _install_action(self, name: str, callback) -> None:
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", callback)
        self.add_action(action)

    def _show_toast(self, message: str) -> None:
        dialog = Adw.AlertDialog(heading="Calendar error", body=message)
        dialog.add_response("close", "Close")
        dialog.present(self)
