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

---Dispatch a single string build step. Strings starting with ':' run via
---`vim.cmd`; otherwise they spawn as shell commands inside the plugin
---directory. Mirrors lazy.nvim's manage/task/plugin.lua dispatch.
---`on_done` fires when the step finishes (success or failure) so array
---steps can chain serially.
---@param build string
---@param plugin zpack.Plugin?
---@param notify_failure fun(err: any)
---@param on_done fun()
local function execute_build_string(build, plugin, notify_failure, on_done)
  if build:sub(1, 1) == ':' then
    local ex_cmd = build:sub(2)
    vim.schedule(function()
      local ok, err = pcall(function() vim.cmd(ex_cmd) end)
      if not ok then
        notify_failure(err)
      end
      on_done()
    end)
    return
  end

  local cwd = plugin and plugin.path
  if not cwd or cwd == '' then
    notify_failure("shell build requires a known plugin path")
    on_done()
    return
  end

  vim.schedule(function()
    -- Hard-code `sh -c` / `cmd.exe /c` rather than `$SHELL` / `&shell`:
    -- those commonly carry args (e.g. `bash --login`) which vim.system
    -- treats as a literal argv[0] and fails with ENOENT.
    local argv = vim.fn.has('win32') == 1
        and { 'cmd.exe', '/c', build }
        or { 'sh', '-c', build }
    local ok, sys_err = pcall(vim.system, argv, { cwd = cwd, text = true }, function(res)
      if res.code ~= 0 then
        local detail = (res.stderr and res.stderr ~= '' and res.stderr)
            or (res.stdout and res.stdout ~= '' and res.stdout)
            or ''
        vim.schedule(function()
          notify_failure(("shell command exited %d: %s"):format(res.code, detail))
          on_done()
        end)
      else
        vim.schedule(on_done)
      end
    end)
    if not ok then
      notify_failure(sys_err)
      on_done()
    end
  end)
end

---@param build false|string|table|boolean|fun(plugin: zpack.Plugin?)
---@param plugin zpack.Plugin?
---@param src string Plugin identifier for the failure notify
---@param on_done? fun() Optional callback fired when build completes
M.execute_build = function(build, plugin, src, on_done)
  on_done = on_done or function() end
  local function notify_failure(err)
    util.schedule_notify(("Failed to run build for %s: %s"):format(src, tostring(err)), vim.log.levels.ERROR)
  end

  -- Lazy.nvim spec parity: `build = false` opts out of build for this plugin
  -- even when a default builder would otherwise apply.
  if build == false or build == nil then
    on_done()
    return
  end

  -- Validator accepts boolean for explicit `false` opt-out; surface `true`
  -- so it doesn't silently fall through with no matching branch.
  if build == true then
    notify_failure("build = true is not a supported value (use string, function, or table)")
    on_done()
    return
  end

  if type(build) == "table" then
    -- Chain via on_done so shell steps don't interleave (e.g.
    -- `{ 'git submodule update --init', 'make' }` must run serially).
    local i = 0
    local function run_next()
      i = i + 1
      if i > #build then
        on_done()
        return
      end
      M.execute_build(build[i], plugin, src, run_next)
    end
    run_next()
  elseif type(build) == "string" then
    execute_build_string(build, plugin, notify_failure, on_done)
  elseif type(build) == "function" then
    vim.schedule(function()
      local ok, err = pcall(build, plugin)
      if not ok then
        notify_failure(err)
      end
      on_done()
    end)
  else
    on_done()
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
        if pack_spec and not require('zpack.plugin_loader').try_process_spec(pack_spec, { bang = true }) then
          return
        end
        M.execute_build(spec.build, registry_entry.plugin, src)
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
      local load_ok = pack_spec == nil or loader.try_process_spec(pack_spec, { bang = not ctx.load })
      if load_ok then
        M.execute_build(spec.build, entry.plugin, src)
      end
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
      local load_ok = pack_spec == nil or loader.try_process_spec(pack_spec, { bang = true })
      if load_ok then
        M.execute_build(spec.build, entry.plugin, src)
        count = count + 1
      end
    end
  end

  if count > 0 then
    util.schedule_notify(('Running build hooks for %d plugin(s)'):format(count), vim.log.levels.INFO)
  else
    util.schedule_notify('No plugins with build hooks found', vim.log.levels.INFO)
  end
end

return M
