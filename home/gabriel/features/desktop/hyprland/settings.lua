local data = require("data")
local c = data.colors

hl.config({
  general = {
    gaps_in = 15,
    -- Leave room for the top bar without reserving space in fullscreen.
    gaps_out = { top = 70, right = 20, bottom = 20, left = 20 },
    border_size = 2,
    col = {
      active_border = c.primary .. "ee",
      inactive_border = c.surface .. "aa",
    },
  },
  cursor = { inactive_timeout = 4 },
  group = {
    col = { border_active = c.primary .. "ee", border_inactive = c.surface .. "aa" },
    groupbar = { font_size = 11 },
  },
  binds = { movefocus_cycles_fullscreen = false },
  input = {
    kb_layout = "us_intl",
    touchpad = { disable_while_typing = false, natural_scroll = true },
  },
  dwindle = { split_width_multiplier = 1.35 },
  misc = {
    -- Activation requests are usually rude; browsers opt back in via rules.
    focus_on_activate = false,
    on_focus_under_fullscreen = 2,
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    disable_hyprland_guiutils_check = true,
  },
  decoration = {
    inactive_opacity = 0.85,
    rounding = 10,
    rounding_power = 4,
    blur = { enabled = false },
    shadow = { enabled = false },
  },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.curve("easeout", { type = "bezier", points = { { 0.5, 1 }, { 0.9, 1 } } })
hl.curve("easeoutback", { type = "bezier", points = { { 0.34, 1.22 }, { 0.65, 1 } } })

for _, leaf in ipairs({ "fadeIn", "fadeLayersIn", "fadeOut", "fadeLayersOut", "fadeDim" }) do
  hl.animation({ leaf = leaf, enabled = true, speed = 3, bezier = "easeout" })
end
for _, leaf in ipairs({ "fadeSwitch", "fadeShadow", "border" }) do
  hl.animation({ leaf = leaf, enabled = true, speed = 2, bezier = "easeout" })
end
for _, leaf in ipairs({ "layersIn", "layersOut", "windowsIn" }) do
  hl.animation({ leaf = leaf, enabled = true, speed = 3, bezier = "easeoutback", style = "slide" })
end
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "easeout", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3, bezier = "easeoutback" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "easeoutback", style = "slidefade" })

for _, monitor in ipairs(data.monitors) do
  hl.monitor({
    output = monitor.name,
    disabled = not monitor.enabled,
    mode = string.format("%dx%d@%s", monitor.width, monitor.height, monitor.refreshRate),
    position = monitor.position,
    scale = monitor.scale,
  })
  if monitor.enabled and monitor.workspace then
    hl.workspace_rule({ workspace = tostring(monitor.workspace), monitor = monitor.name })
  end
end
