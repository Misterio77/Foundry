local data = require("data")

hl.window_rule({ match = { fullscreen_state_internal = 2 }, idle_inhibit = "focus" })
hl.window_rule({
  match = { title = "win[0-9]", class = "com-eteks-sweethome3d-SweetHome3DBootstrap" },
  no_initial_focus = true,
})
hl.window_rule({ match = { class = "steam_app_[0-9]*" }, immediate = true })
hl.window_rule({ match = { class = "explorer.exe" }, workspace = "special silent" })
hl.window_rule({ match = { class = "rsi launcher.exe" }, tile = true })
hl.window_rule({ match = { class = "(?i)^runescape$" }, suppress_event = "activate", render_unfocused = true })
hl.window_rule({ match = { class = "(?i)^(firefox|org\\.qutebrowser\\.qutebrowser)$" }, focus_on_activate = true })
-- RemoteApp requests maximization on every activation.
hl.window_rule({
  match = { class = "(?i)^Microsoft (Excel|Word|PowerPoint|Outlook|OneNote)$" },
  suppress_event = "maximize",
})
hl.window_rule({ match = { title = "Steam Big Picture Mode" }, fullscreen = true })
hl.window_rule({ match = { class = "firefox", title = "Picture-in-Picture" }, float = true, pin = true })
hl.window_rule({ match = { float = true, class = "vlc" }, pin = true })

for host, colors in pairs(data.hosts) do
  local title = "\\[" .. host .. "\\].*"
  hl.window_rule({ match = { title = title, focus = true }, border_color = colors.primary .. "ee" })
  hl.window_rule({ match = { title = title, focus = false }, border_color = colors.primary_container .. "aa" })
end

for _, namespace in ipairs({ "hyprpicker", "selection", "hyprpaper" }) do
  hl.layer_rule({ match = { namespace = namespace }, animation = "fade" })
end
hl.layer_rule({ match = { namespace = "waybar" }, animation = "fade", blur = true, ignore_alpha = 0 })
for _, namespace in ipairs({ "notifications", "wofi" }) do
  hl.layer_rule({ match = { namespace = namespace }, blur = true, ignore_alpha = 0 })
end
hl.layer_rule({ match = { namespace = "wallpaper" }, no_anim = true })
hl.layer_rule({ match = { namespace = "swayosd" }, above_lock = 2 })
