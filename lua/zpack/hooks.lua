local util = require('zpack.utils')
local state = require('zpack.state')

local M = {}

---@param src string
---@param hook_name string
---@return boolean
M.try_call_hook = function(src, hook_name)
  local spec = state.spec_registry[src].spec
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
      state.src_with_pending_build[event.data.spec.src] = true
    end
  end, { group = state.startup_group })
end

M.setup_lazy_build_tracking = function()
  util.autocmd('PackChanged', function(event)
    if event.data.kind == "update" or event.data.kind == "install" then
      local src = event.data.spec.src
      local registry_entry = state.spec_registry[src]
      if registry_entry and registry_entry.spec.build then
        M.load_all_unloaded_plugins()
        M.execute_build(registry_entry.spec.build)
      end
    end
  end, { group = state.lazy_build_group })
end

M.load_all_unloaded_plugins = function(opts)
  opts = opts or {}
  local loader = require('zpack.loader')

  for _, pack_spec in ipairs(state.registered_plugins) do
    local entry = state.spec_registry[pack_spec.src]
    if entry and not entry.loaded then
      loader.process_spec(pack_spec, opts)
    end
  end
end

M.run_pending_builds_on_startup = function(ctx)
  if next(state.src_with_pending_build) == nil then
    return
  end

  M.load_all_unloaded_plugins({ bang = not ctx.load })

  for src in pairs(state.src_with_pending_build) do
    local entry = state.spec_registry[src]
    if entry and entry.spec.build then
      M.execute_build(entry.spec.build)
    end
  end

  state.src_with_pending_build = {}
end

M.run_all_builds = function()
  M.load_all_unloaded_plugins()

  local count = 0
  for _, entry in pairs(state.spec_registry) do
    if entry.spec.build then
      M.execute_build(entry.spec.build)
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
