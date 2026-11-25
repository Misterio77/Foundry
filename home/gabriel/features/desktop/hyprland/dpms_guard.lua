local M = {}
local guard = "KVM-KEEPALIVE"
local asleep = false
local outputs = {}
local generation = 0

hl.workspace_rule({ workspace = "99", monitor = guard, default = true })

local function blank()
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name ~= guard then
      hl.dispatch(hl.dsp.dpms({ action = "disable", monitor = monitor.name }))
    end
  end
end

local function ready()
  if asleep or #outputs == 0 or not hl.get_monitor(guard) then return false end
  for _, name in ipairs(outputs) do
    local monitor = hl.get_monitor(name)
    if not monitor or not monitor.enabled or not monitor.dpms_status then return false end
  end
  return true
end

local function schedule_cleanup()
  generation = generation + 1
  if not ready() then return end
  -- A KVM may briefly report every output back before dropping the links again.
  local snapshot = generation
  hl.timer(function()
    if snapshot == generation and ready() then hl.exec_cmd("hyprctl output remove " .. guard) end
  end, { type = "oneshot", timeout = 5000 })
end

function M.disable()
  if asleep then return end
  generation = generation + 1
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
  schedule_cleanup()
end

hl.on("monitor.added", function(monitor)
  if asleep and monitor.name == guard then
    blank()
  else
    schedule_cleanup()
  end
end)
hl.on("monitor.removed", schedule_cleanup)

return M
