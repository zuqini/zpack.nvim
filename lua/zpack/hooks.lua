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

---@param build string|fun()
M.execute_build = function(build)
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
      M.execute_build(spec.build)
    end
  end
end

M.run_all_build_hooks = function()
  local loader = require('zpack.loader')
  local count = 0

  local installed = vim.pack.get()
  for _, pack in ipairs(installed) do
    local src_spec_entry = state.src_spec[pack.spec.src]
    if src_spec_entry and src_spec_entry.spec.build then
      loader.process_spec(pack.spec)
      state.src_to_request_build[pack.spec.src] = true
      M.execute_build(src_spec_entry.spec.build)
      count = count + 1
    end
  end

  if count > 0 then
    util.schedule_notify(('Running build hooks for %d plugin(s)'):format(count), vim.log.levels.INFO)
  else
    util.schedule_notify('No plugins with build hooks found', vim.log.levels.INFO)
  end
end

return M
