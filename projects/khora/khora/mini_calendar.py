from __future__ import annotations

import datetime as dt

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GObject, Gtk

from .colors import display_color
from .model import month_grid_dates, shifted_date


class MiniCalendar(Gtk.Box):
    __gsignals__ = {
        "day-selected": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "month-changed": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self, selected_day: dt.date | None = None) -> None:
        super().__init__(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=4,
            css_classes=["mini-calendar"],
        )
        self.selected_day = selected_day or dt.date.today()
        self._display_month = self.selected_day.replace(day=1)
        self._event_colors: dict[dt.date, tuple[str | None, ...]] = {}
        self._render()

    @property
    def visible_days(self) -> tuple[dt.date, ...]:
        return month_grid_dates(self._display_month)

    def select_day(self, day: dt.date) -> None:
        month_changed = (day.year, day.month) != (
            self._display_month.year,
            self._display_month.month,
        )
        self.selected_day = day
        self._display_month = day.replace(day=1)
        self._render()
        if month_changed:
            self.emit("month-changed")
        self.emit("day-selected")

    def set_event_colors(
        self,
        colors: dict[dt.date, tuple[str | None, ...]],
    ) -> None:
        self._event_colors = colors
        self._render()

    def _render(self) -> None:
        while child := self.get_first_child():
            self.remove(child)

        header = Gtk.Box()
        previous = Gtk.Button(icon_name="go-previous-symbolic", css_classes=["flat"])
        previous.connect("clicked", lambda *_: self._move_month(-1))
        following = Gtk.Button(icon_name="go-next-symbolic", css_classes=["flat"])
        following.connect("clicked", lambda *_: self._move_month(1))
        header.append(previous)
        header.append(
            Gtk.Label(
                label=f"{self._display_month:%B} {self._display_month.year}",
                hexpand=True,
                css_classes=["heading"],
            )
        )
        header.append(following)
        self.append(header)

        grid = Gtk.Grid(column_homogeneous=True, row_spacing=2, column_spacing=2)
        monday = dt.date(2024, 1, 1)
        for column in range(7):
            grid.attach(
                Gtk.Label(
                    label=f"{monday + dt.timedelta(days=column):%a}",
                    css_classes=["weekday"],
                ),
                column,
                0,
                1,
                1,
            )

        today = dt.date.today()
        for index, day in enumerate(self.visible_days):
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
            content.append(Gtk.Label(label=str(day.day), css_classes=["day-number"]))
            dots = self._event_colors.get(day, ())
            dot = Gtk.Label(css_classes=["event-dots"])
            dot.set_markup(
                "".join(
                    f'<span foreground="{display_color(color)}">●</span>'
                    for color in tuple(dict.fromkeys(dots))[:3]
                )
                or " "
            )
            content.append(dot)

            classes = ["flat", "day-button"]
            if day.month != self._display_month.month:
                classes.append("other-month")
            if day == today:
                classes.append("today")
            if day == self.selected_day:
                classes.append("selected")
            button = Gtk.Button(child=content, css_classes=classes)
            button.connect("clicked", lambda _button, selected=day: self.select_day(selected))
            row, column = divmod(index, 7)
            grid.attach(button, column, row + 1, 1, 1)
        self.append(grid)

    def _move_month(self, direction: int) -> None:
        self._display_month = shifted_date(self._display_month, "month", direction).replace(day=1)
        self._render()
        self.emit("month-changed")
