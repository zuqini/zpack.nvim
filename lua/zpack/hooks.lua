local util = require('zpack.utils')
local state = require('zpack.state')

local M = {}

---@param src string
---@param hook_name string
---@return boolean
M.try_call_hook = function(src, hook_name)
  local spec = state.src_spec[src].spec
  if not spec then
    util.schedule_notify("expected spec missing for " .. src, vim.log.levels.ERROR)
    return false
  end

  local hook = spec[hook_name] --[[@as fun()]]
  if not hook then
    util.schedule_notify("expected " .. hook_name .. " missing for " .. src, vim.log.levels.ERROR)
    return false
  end

  if type(hook) ~= "function" then
    util.schedule_notify("Hook " .. hook_name .. " is not a function for " .. src, vim.log.levels.ERROR)
    return false
  end

  local success, error_msg = pcall(hook)
  if not success then
    util.schedule_notify(("Failed to run hook for %s: %s"):format(src, error_msg), vim.log.levels.ERROR)
    return false
  end

  return true
end

---@param src string
---@param build string|fun()
local execute_build = function(src, build)
  if not state.src_to_request_build[src] then
    util.schedule_notify("Trying to execute build hook for invalid src " .. src)
    return
  end

  if type(build) == "string" then
    vim.schedule(function()
      vim.cmd(build)
    end)
  elseif type(build) == "function" then
    vim.schedule(function()
      build()
    end)
  end
end

M.setup_build_tracking = function()
  util.autocmd('PackChanged', function(event)
    if event.data.kind == "update" or event.data.kind == "install" then
      state.src_to_request_build[event.data.spec.src] = true
    end
  end, { group = state.startup_group })
end

M.run_build_hooks = function()
  for src, _ in pairs(state.src_to_request_build) do
    local spec = state.src_spec[src].spec
    if spec.build then
      execute_build(src, spec.build)
    end
  end
end

return M
