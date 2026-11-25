local M = {}
local guard = "KVM-KEEPALIVE"
local asleep = false
local outputs = {}

hl.workspace_rule({ workspace = "99", monitor = guard, default = true })

local function blank()
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name ~= guard then
      hl.dispatch(hl.dsp.dpms({ action = "disable", monitor = monitor.name }))
    end
  end
end

local function cleanup()
  if asleep or #outputs == 0 or not hl.get_monitor(guard) then return end
  for _, name in ipairs(outputs) do
    local monitor = hl.get_monitor(name)
    if not monitor or not monitor.enabled or not monitor.dpms_status then return end
  end
  hl.exec_cmd("hyprctl output remove " .. guard)
end

function M.disable()
  if asleep then return end
  outputs = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name ~= guard then outputs[#outputs + 1] = monitor.name end
  end
  if #outputs == 0 then return end

  asleep = true
  local monitor = hl.get_monitor(guard)
  if monitor and monitor.enabled and monitor.dpms_status then
    blank()
  else
    -- Wait for monitor.added rather than racing headless output creation.
    hl.exec_cmd("hyprctl output create headless " .. guard)
  end
end

function M.enable()
  asleep = false
  hl.dispatch(hl.dsp.dpms({ action = "enable" }))
  cleanup()
end

hl.on("monitor.added", function(monitor)
  if asleep and monitor.name == guard then
    blank()
  else
    cleanup()
  end
end)

return M
