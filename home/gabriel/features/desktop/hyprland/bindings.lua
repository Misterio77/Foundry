local data = require("data")
local cmd = data.commands
local dsp = hl.dsp
local M = {}

local function quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.rename_workspace(id, name)
  if not hl.get_workspace(id) then
    return
  end
  local label = tostring(id)
  if name ~= "" and name ~= label then
    label = label .. " - " .. name
  end
  hl.dispatch(dsp.workspace.rename({ workspace = id, name = label }))
end

function M.minimize()
  local window = hl.get_active_window()
  local workspace = hl.get_active_workspace()
  if window and workspace then
    hl.dispatch(dsp.window.move({
      window = window,
      workspace = window.workspace.special and workspace or "special",
      follow = false,
    }))
  end
end

hl.bind("SUPER + r", function()
  local workspace = hl.get_active_workspace()
  if not workspace or not workspace.id then
    return
  end
  local name = workspace.name:gsub("^" .. workspace.id .. " %- ", "")
  hl.exec_cmd(cmd.renameWorkspace .. " " .. workspace.id .. " " .. quote(name))
end)

hl.bind("SUPER + mouse:272", dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", dsp.window.resize(), { mouse = true })
hl.bind("SUPER + SHIFT + q", dsp.window.close())
hl.bind("SUPER + SHIFT + e", dsp.exit())
hl.bind("SUPER + s", dsp.layout("togglesplit"))
hl.bind("SUPER + f", dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + SHIFT + f", dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + SHIFT + space", dsp.window.float())
hl.bind("SUPER + minus", dsp.layout("splitratio -0.25"))
hl.bind("SUPER + SHIFT + minus", dsp.layout("splitratio -0.3333333"))
hl.bind("SUPER + equal", dsp.layout("splitratio 0.25"))
hl.bind("SUPER + SHIFT + equal", dsp.layout("splitratio 0.3333333"))
hl.bind("SUPER + g", dsp.group.toggle())
hl.bind("SUPER + t", dsp.group.lock())
hl.bind("SUPER + Tab", dsp.group.next())
hl.bind("SUPER + SHIFT + Tab", dsp.group.prev())
hl.bind("SUPER + u", dsp.workspace.toggle_special(""))
hl.bind("SUPER + SHIFT + u", dsp.window.move({ workspace = "special", follow = false }))
hl.bind("SUPER + y", dsp.window.toggle_swallow())
hl.bind("SUPER + i", function()
  hl.dispatch(dsp.window.pin())
  hl.dispatch(dsp.window.fullscreen_state({ internal = 0, client = 3 }))
end)

for _, key in ipairs({ "apostrophe", "dead_grave" }) do
  hl.bind("SUPER + " .. key, dsp.focus({ workspace = "previous" }))
  hl.bind("SUPER + SHIFT + " .. key, dsp.focus({ workspace = "next" }))
end
for workspace = 1, 10 do
  local key = workspace % 10
  hl.bind("SUPER + " .. key, dsp.focus({ workspace = workspace }))
  hl.bind("SUPER + SHIFT + " .. key, dsp.window.move({ workspace = workspace, follow = false }))
end
for key, direction in pairs({
  left = "left",
  h = "left",
  right = "right",
  l = "right",
  up = "up",
  k = "up",
  down = "down",
  j = "down",
}) do
  hl.bind("SUPER + " .. key, dsp.focus({ direction = direction }))
  hl.bind("SUPER + SHIFT + " .. key, dsp.window.swap({ direction = direction }))
  hl.bind("SUPER + CTRL + " .. key, dsp.window.move({ direction = direction }))
  hl.bind("SUPER + ALT + " .. key, dsp.focus({ monitor = direction }))
  hl.bind("SUPER + ALT + SHIFT + " .. key, dsp.workspace.move({ monitor = direction }))
end

hl.bind("SUPER + Escape", dsp.submap("passthrough"))
hl.define_submap("passthrough", function()
  hl.bind("SUPER + Escape", dsp.submap("reset"))
end)

for key, mime in pairs({ Return = "x-scheme-handler/terminal", e = "text/plain", b = "x-scheme-handler/https" }) do
  local command = cmd.handlr .. " launch " .. mime
  hl.bind("SUPER + " .. key, dsp.exec_cmd(command))
  hl.bind("SUPER + ALT + " .. key, dsp.exec_cmd("remote-launch handlr launch " .. mime))
end
hl.bind("Print", dsp.exec_cmd(cmd.grimblast .. " --freeze copy area"))
hl.bind("SHIFT + Print", dsp.exec_cmd(cmd.grimblast .. " --freeze copy output"))
hl.bind("SUPER + BackSpace", dsp.exec_cmd(cmd.hyprlock))
hl.bind("SUPER + XF86Calculator", dsp.exec_cmd(cmd.hyprlock))

if cmd.makoctl then
  hl.bind("SUPER + w", dsp.exec_cmd(cmd.makoctl .. " dismiss"))
  hl.bind("SUPER + SHIFT + w", dsp.exec_cmd(cmd.makoctl .. " restore"))
end
if cmd.wofi then
  local menu = cmd.wofi .. " -S drun -x 10 -y 10 -W 25% -H 60%"
  hl.bind("SUPER + x", dsp.exec_cmd(menu))
  hl.bind("SUPER + d", dsp.exec_cmd(cmd.wofi .. " -S run"))
  hl.bind("SUPER + SHIFT + s", dsp.exec_cmd("specialisation $(specialisation | " .. cmd.wofi .. " -S dmenu)"))
  hl.bind("SUPER + space", dsp.exec_cmd("tmux-picker"))
  hl.bind("SUPER + ALT + x", dsp.exec_cmd("remote-launch wofi -S drun -x 10 -y 10 -W 25% -H 60%"))
  hl.bind("SUPER + ALT + d", dsp.exec_cmd("remote-launch wofi -S run"))
end
if cmd.pass then
  hl.bind("XF86Calculator", dsp.exec_cmd(cmd.pass))
  hl.bind("SHIFT + XF86Calculator", dsp.exec_cmd(cmd.pass .. " fill"))
  hl.bind("SUPER + semicolon", dsp.exec_cmd(cmd.pass))
  hl.bind("SUPER + SHIFT + semicolon", dsp.exec_cmd(cmd.pass .. " fill"))
end
if cmd.cliphist and cmd.wofi then
  hl.bind(
    "SUPER + c",
    dsp.exec_cmd(
      "selected=$("
        .. cmd.cliphist
        .. " list | "
        .. cmd.wofi
        .. " -S dmenu) && printf '%s\\n' \"$selected\" | "
        .. cmd.cliphist
        .. " decode | wl-copy"
    )
  )
end
if cmd.shareClipboard then
  hl.bind("SUPER + v", dsp.exec_cmd(cmd.shareClipboard))
end

local repeating = { locked = true, repeating = true }
hl.bind("XF86MonBrightnessUp", dsp.exec_cmd("brightnessctl s +10%; swayosd-client --brightness +0"), repeating)
hl.bind("XF86MonBrightnessDown", dsp.exec_cmd("brightnessctl s 10%-; swayosd-client --brightness +0"), repeating)
for _, entry in ipairs({
  { "", "sink", "output" },
  { "SHIFT + ", "source", "input" },
}) do
  local prefix, device, osd = table.unpack(entry)
  local target = " @DEFAULT_" .. device:upper() .. "@ "
  hl.bind(
    prefix .. "XF86AudioRaiseVolume",
    dsp.exec_cmd(
      cmd.pactl .. " set-" .. device .. "-volume" .. target .. "+5%; swayosd-client --" .. osd .. "-volume +0"
    ),
    repeating
  )
  hl.bind(
    prefix .. "XF86AudioLowerVolume",
    dsp.exec_cmd(
      cmd.pactl .. " set-" .. device .. "-volume" .. target .. "-5%; swayosd-client --" .. osd .. "-volume +0"
    ),
    repeating
  )
  hl.bind(
    prefix .. "XF86AudioMute",
    dsp.exec_cmd(
      cmd.pactl .. " set-" .. device .. "-mute" .. target .. "toggle; swayosd-client --" .. osd .. "-volume +0"
    ),
    { locked = true }
  )
end
hl.bind(
  "XF86AudioMicMute",
  dsp.exec_cmd(cmd.pactl .. " set-source-mute @DEFAULT_SOURCE@ toggle; swayosd-client --input-volume +0"),
  { locked = true }
)
hl.bind("Caps_Lock", dsp.exec_cmd("sleep 0.2; swayosd-client --caps-lock"), { locked = true })
if cmd.playerctl then
  for key, action in pairs({
    XF86AudioNext = "next",
    XF86AudioPrev = "previous",
    XF86AudioPlay = "play-pause",
    XF86AudioStop = "stop",
  }) do
    hl.bind(key, dsp.exec_cmd(cmd.playerctl .. " " .. action), { locked = true })
  end
  hl.bind("SHIFT + XF86AudioNext", dsp.exec_cmd(cmd.playerctld .. " shift"), { locked = true })
  hl.bind("SHIFT + XF86AudioPrev", dsp.exec_cmd(cmd.playerctld .. " unshift"), { locked = true })
  hl.bind("SHIFT + XF86AudioPlay", dsp.exec_cmd("systemctl --user restart playerctld"), { locked = true })
end

return M
