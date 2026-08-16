from __future__ import annotations

import re

_DEFAULT = "#3584e4"
_ANSI = (
    "#241f31",
    "#c01c28",
    "#26a269",
    "#a2734c",
    "#1c71d8",
    "#a347ba",
    "#2aa1b3",
    "#deddda",
    "#5e5c64",
    "#ed333b",
    "#57e389",
    "#f8e45c",
    "#62a0ea",
    "#c061cb",
    "#5bc8d7",
    "#ffffff",
)
_NAMED = dict(
    zip(
        (
            "black",
            "dark red",
            "dark green",
            "brown",
            "dark blue",
            "dark magenta",
            "dark cyan",
            "white",
            "dark gray",
            "light red",
            "light green",
            "yellow",
            "light blue",
            "light magenta",
            "light cyan",
            "light gray",
        ),
        _ANSI,
        strict=True,
    )
)
_HEX_COLOR = re.compile(r"#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?(?:[0-9a-fA-F]{2})?")


def display_color(value: str | None) -> str:
    """Turn khal's terminal-oriented color values into GTK-friendly hex."""
    if not value or value == "auto":
        return _DEFAULT
    if _HEX_COLOR.fullmatch(value):
        return value
    if value in _NAMED:
        return _NAMED[value]
    if value.isdigit() and 0 <= (index := int(value)) <= 255:
        return _xterm_color(index)
    return _DEFAULT


def contrasting_foreground(value: str | None) -> str:
    """Choose black or white for readable text over a calendar color."""
    color = display_color(value).lstrip("#")
    if len(color) == 3:
        color = "".join(channel * 2 for channel in color)
    red, green, blue = (int(color[index : index + 2], 16) / 255 for index in (0, 2, 4))

    def linear(channel: float) -> float:
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4

    luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    return "#000000" if luminance > 0.179 else "#ffffff"


def _xterm_color(index: int) -> str:
    if index < 16:
        return _ANSI[index]
    if index < 232:
        index -= 16
        levels = (0, 95, 135, 175, 215, 255)
        red, remainder = divmod(index, 36)
        green, blue = divmod(remainder, 6)
        return f"#{levels[red]:02x}{levels[green]:02x}{levels[blue]:02x}"
    gray = 8 + (index - 232) * 10
    return f"#{gray:02x}{gray:02x}{gray:02x}"
