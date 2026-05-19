local util = require('zpack.utils')
local state = require('zpack.state')

local M = {}

---@param src string
---@param hook_name string
---@return boolean
M.try_call_hook = function(src, hook_name)
  local registry_entry = state.spec_registry[src]
  -- merged_spec is always populated post-resolve_all, when hooks run.
  local spec = registry_entry.merged_spec --[[@as zpack.Spec]]

  local hook = spec[hook_name] --[[@as fun(plugin: zpack.Plugin)]]
  if not hook then
    util.schedule_notify("expected " .. hook_name .. " missing for " .. src, vim.log.levels.ERROR)
    return false
  end

  if type(hook) ~= "function" then
    util.schedule_notify("Hook " .. hook_name .. " is not a function for " .. src, vim.log.levels.ERROR)
    return false
  end

  local success, error_msg = pcall(hook, registry_entry.plugin)
  if not success then
    util.schedule_notify(("Failed to run hook for %s: %s"):format(src, error_msg), vim.log.levels.ERROR)
    return false
  end

  return true
end

---@param build string|fun(plugin: zpack.Plugin?)
---@param plugin zpack.Plugin?
M.execute_build = function(build, plugin)
  if type(build) == "string" then
    vim.schedule(function()
      vim.cmd(build)
    end)
  elseif type(build) == "function" then
    vim.schedule(function()
      build(plugin)
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

-- Drop a plugin from zpack's in-session state whenever vim.pack removes it,
-- regardless of how the removal was triggered: :ZPack delete, the built-in
-- :packdel, or a direct vim.pack.del() call. Reacting to PackChanged keeps
-- state correct without coupling cleanup to zpack's own command handler.
M.setup_delete_tracking = function()
  util.autocmd('PackChanged', function(event)
    if event.data.kind ~= "delete" then
      return
    end
    local spec = event.data.spec
    -- PackChanged fires for every vim.pack removal, including plugins zpack
    -- never registered. The spec_registry check keeps this a no-op for those:
    -- remove_plugin filters the name-keyed lists by name, so an unmanaged
    -- plugin sharing a name with a managed one would otherwise desync state.
    if spec and spec.name and spec.src and state.spec_registry[spec.src] then
      state.remove_plugin(spec.name, spec.src)
    end
  end, { group = state.delete_group })
end

M.setup_lazy_build_tracking = function()
  util.autocmd('PackChanged', function(event)
    if event.data.kind == "update" or event.data.kind == "install" then
      local src = event.data.spec.src
      local registry_entry = state.spec_registry[src]
      local spec = registry_entry and registry_entry.merged_spec
      if spec and spec.build then
        local pack_spec = state.src_to_pack_spec[src]
        if pack_spec then
          require('zpack.plugin_loader').process_spec(pack_spec, { bang = true })
        end
        M.execute_build(spec.build, registry_entry.plugin)
      end
    end
  end, { group = state.lazy_build_group })
end

M.run_pending_builds_on_startup = function(ctx)
  if next(state.src_with_pending_build) == nil then
    return
  end

  local loader = require('zpack.plugin_loader')

  for src in pairs(state.src_with_pending_build) do
    local entry = state.spec_registry[src]
    local spec = entry and entry.merged_spec
    if spec and spec.build then
      local pack_spec = state.src_to_pack_spec[src]
      if pack_spec then
        loader.process_spec(pack_spec, { bang = not ctx.load })
      end
      M.execute_build(spec.build, entry.plugin)
    end
  end

  state.src_with_pending_build = {}
end

M.run_all_builds = function()
  local loader = require('zpack.plugin_loader')
  local count = 0

  for src, entry in pairs(state.spec_registry) do
    local spec = entry.merged_spec
    if spec and spec.build then
      local pack_spec = state.src_to_pack_spec[src]
      if pack_spec then
        loader.process_spec(pack_spec, { bang = true })
      end
      M.execute_build(spec.build, entry.plugin)
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
