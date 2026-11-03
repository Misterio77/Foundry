-- Plugin loading happens after the first parse and triggers a config reload.
if not hl.plugin.hyprbars then
  return
end

local data = require("data")
local c = data.colors

hl.config({
  plugin = {
    hyprbars = {
      bar_color = c.surface .. "dd",
      col = { text = c.primary },
      bar_height = 25,
      bar_text_font = data.font.name,
      bar_text_size = math.floor(data.font.size * 1.4),
      bar_part_of_window = false,
      bar_precedence_over_border = false,
    },
  },
})

-- Hyprbars buttons take commands, not callbacks; eval reuses our Lua actions.
for _, button in ipairs({
  { c.red, "hyprctl dispatch 'hl.dsp.window.close()'" },
  { c.yellow, [[hyprctl eval 'require("bindings").minimize()']] },
  { c.green, [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })']] },
}) do
  hl.plugin.hyprbars.add_button({ bg_color = button[1], fg_color = c.on_primary, size = 12, icon = "", action = button[2] })
end

hl.window_rule({ match = { float = true, pin = true }, ["hyprbars:no_bar"] = true })
hl.window_rule({
  match = { focus = false },
  ["hyprbars:bar_color"] = c.surface .. "dd",
  ["hyprbars:title_color"] = c.primary,
})
hl.window_rule({
  match = { focus = true },
  ["hyprbars:bar_color"] = c.primary .. "ee",
  ["hyprbars:title_color"] = c.on_primary,
})

for host, colors in pairs(data.hosts) do
  local title = "\\[" .. host .. "\\].*"
  hl.window_rule({
    match = { title = title, focus = false },
    ["hyprbars:bar_color"] = colors.primary_container .. "dd",
    ["hyprbars:title_color"] = colors.on_primary_container,
  })
  hl.window_rule({
    match = { title = title, focus = true },
    ["hyprbars:bar_color"] = colors.primary .. "ee",
    ["hyprbars:title_color"] = colors.on_primary,
  })
end
