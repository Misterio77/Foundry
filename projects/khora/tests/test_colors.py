from khora.colors import display_color


def test_preserves_html_colors() -> None:
    assert display_color("#c01c28") == "#c01c28"


def test_converts_khal_named_colors() -> None:
    assert display_color("light blue") == "#62a0ea"


def test_converts_xterm_color_cube() -> None:
    assert display_color("196") == "#ff0000"


def test_unknown_colors_use_accent_fallback() -> None:
    assert display_color("auto") == "#3584e4"
    assert display_color("chartreuse, probably") == "#3584e4"
