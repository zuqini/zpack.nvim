local state = require('zpack.state')
local util = require('zpack.utils')
local hooks = require('zpack.hooks')

local M = {}

local validate_name = function(name)
  if type(name) ~= 'string' or name == '' then
    return false
  end
  if not name:match('^%u[%a%d]*$') then
    return false
  end
  return true
end

local filter_completions = function(list, prefix)
  if prefix == '' then return list end
  local lower_prefix = prefix:lower()
  return vim.tbl_filter(function(name)
    return name:lower():find(lower_prefix, 1, true) == 1
  end, list)
end

local is_registered_or_notify = function(plugin_name)
  if not vim.tbl_contains(state.registered_plugin_names, plugin_name) then
    util.schedule_notify(('Plugin "%s" not found in spec'):format(plugin_name), vim.log.levels.ERROR)
    return false
  end
  return true
end

---Build the explicit name list for `vim.pack.update` when any plugin is
---pinned. Seeded from vim.pack.get so pinning one plugin doesn't narrow
---the universe past zpack-managed plugins. Returns nil when nothing is
---pinned so callers take vim.pack.update's default "everything" path.
---@return string[]? names nil when nothing is pinned
local function names_for_bulk_update()
  local pinned_names = {}
  local zpack_pinned_by_user = false
  local has_pin = false
  for _, entry in pairs(state.spec_registry) do
    if entry.merged_spec and entry.merged_spec.pin == true then
      has_pin = true
      local name = entry.merged_spec.name
          or (entry.plugin and entry.plugin.spec and entry.plugin.spec.name)
      if name then
        pinned_names[name] = true
        if name == 'zpack.nvim' then
          zpack_pinned_by_user = true
        end
      end
    end
  end
  if not has_pin then
    return nil
  end

  local names = {}
  local seen = {}
  if not zpack_pinned_by_user then
    table.insert(names, 'zpack.nvim')
    seen['zpack.nvim'] = true
  end
  local installed_ok, installed = pcall(vim.pack.get, nil, { info = false })
  if installed_ok and installed then
    for _, pack in ipairs(installed) do
      local name = pack.spec and pack.spec.name
      if name and not pinned_names[name] and not seen[name] then
        table.insert(names, name)
        seen[name] = true
      end
    end
  end
  return names
end

-- Branches avoid passing trailing nils because vim.pack.update uses
-- select('#', ...) to distinguish "no args" from "nil args".
local run_pack_update = function(plugin_name, update_opts, error_prefix)
  local names
  if plugin_name ~= '' then
    if not is_registered_or_notify(plugin_name) then return end
    names = { plugin_name }
  else
    -- lazy.nvim spec parity (`pin = true`): bulk update honors pin by
    -- filtering pinned plugins out of the explicit name list. When nothing
    -- is pinned, `names_for_bulk_update` returns nil and we fall back to
    -- vim.pack.update's default "everything" path.
    names = names_for_bulk_update()
  end
  local ok, err
  if names and update_opts then
    ok, err = pcall(vim.pack.update, names, update_opts)
  elseif names then
    ok, err = pcall(vim.pack.update, names)
  elseif update_opts then
    ok, err = pcall(vim.pack.update, nil, update_opts)
  else
    ok, err = pcall(vim.pack.update)
  end
  if not ok then
    util.schedule_notify(('%s: %s'):format(error_prefix, err), vim.log.levels.ERROR)
  end
end

local get_installed_or_notify = function(plugin_name)
  local ok, result = pcall(vim.pack.get, { plugin_name }, { info = false })
  if not ok or not result or not result[1] then
    util.schedule_notify(('Plugin "%s" not installed'):format(plugin_name), vim.log.levels.ERROR)
    return nil
  end
  return result[1]
end

M.clean_unused = function()
  local to_delete = {}
  local installed = vim.pack.get(nil, { info = false }) or {}

  for _, pack in ipairs(installed) do
    local src = pack.spec.src
    if not state.spec_registry[src] and not string.find(src, 'zpack') then
      table.insert(to_delete, pack.spec.name)
    end
  end

  if #to_delete == 0 then
    util.schedule_notify("No unused plugins to clean", vim.log.levels.INFO)
    return
  end

  util.schedule_notify(("Deleting %d unused plugin(s)..."):format(#to_delete), vim.log.levels.INFO)

  vim.pack.del(to_delete)
end

---------------------------------------------------------------------
-- Subcommand handlers
---------------------------------------------------------------------

local Sub = {}

Sub.update = {
  bang = true,
  takes_arg = true,
  run = function(ctx)
    local opts
    -- `!` skips vim.pack's confirmation buffer via the `force` option.
    if ctx.bang then opts = { force = true } end
    run_pack_update(ctx.arg, opts, 'Update failed')
  end,
  complete = function(arg_lead)
    return filter_completions(state.registered_plugin_names, arg_lead)
  end,
}

Sub.restore = {
  bang = true,
  takes_arg = true,
  run = function(ctx)
    local opts = { target = 'lockfile' }
    -- `!` skips vim.pack's confirmation buffer via the `force` option.
    if ctx.bang then opts.force = true end
    run_pack_update(ctx.arg, opts, ('Restore failed (have you run :%s update?)'):format(ctx.cmd_name))
  end,
  complete = function(arg_lead)
    return filter_completions(state.registered_plugin_names, arg_lead)
  end,
}

Sub.clean = {
  run = function()
    M.clean_unused()
  end,
}

Sub.build = {
  bang = true,
  takes_arg = true,
  run = function(ctx)
    local plugin_name = ctx.arg
    if plugin_name == '' then
      if not ctx.bang then
        util.schedule_notify(('Use :%s! build to run build hooks for all plugins'):format(ctx.cmd_name), vim.log.levels.WARN)
        return
      end
      hooks.run_all_builds()
      return
    end

    local pack = get_installed_or_notify(plugin_name)
    if not pack then
      return
    end

    local registry_entry = state.spec_registry[pack.spec.src]
    local spec = registry_entry and registry_entry.merged_spec
    if not spec or not spec.build then
      util.schedule_notify(('Plugin "%s" has no build hook'):format(plugin_name), vim.log.levels.WARN)
      return
    end

    local pack_spec = state.src_to_pack_spec[pack.spec.src]
    if pack_spec and not require('zpack.plugin_loader').try_process_spec(pack_spec, { bang = true }) then
      return
    end
    hooks.execute_build(spec.build, registry_entry.plugin, pack.spec.src)
    util.schedule_notify(('Running build hook for %s'):format(plugin_name), vim.log.levels.INFO)
  end,
  complete = function(arg_lead)
    return filter_completions(state.plugin_names_with_build, arg_lead)
  end,
}

Sub.load = {
  bang = true,
  takes_arg = true,
  run = function(ctx)
    local plugin_name = ctx.arg
    if plugin_name == '' then
      if not ctx.bang then
        util.schedule_notify(('Use :%s! load to load all unloaded plugins'):format(ctx.cmd_name), vim.log.levels.WARN)
        return
      end
      if vim.tbl_count(state.unloaded_plugin_names) == 0 then
        util.schedule_notify('All plugins are already loaded', vim.log.levels.INFO)
        return
      end
      local loader = require('zpack.plugin_loader')
      local loaded = 0
      for _, pack_spec in ipairs(state.registered_plugins) do
        local entry = state.spec_registry[pack_spec.src]
        if entry and entry.load_status ~= "loaded" then
          -- Post-check load_status rather than try_process_spec's ok return:
          -- process_spec returns true for non-load early exits (circular dep,
          -- plugin == nil) which must not inflate the "Loaded N" message.
          loader.try_process_spec(pack_spec)
          if entry.load_status == "loaded" then
            loaded = loaded + 1
          end
        end
      end
      if loaded > 0 then
        util.schedule_notify(('Loaded %d plugin(s)'):format(loaded), vim.log.levels.INFO)
      end
      return
    end

    local pack = get_installed_or_notify(plugin_name)
    if not pack then
      return
    end

    local registry_entry = state.spec_registry[pack.spec.src]
    if not registry_entry then
      util.schedule_notify(('Plugin "%s" not found in registry'):format(plugin_name), vim.log.levels.ERROR)
      return
    end

    if registry_entry.load_status == "loaded" then
      util.schedule_notify(('Plugin "%s" is already loaded'):format(plugin_name), vim.log.levels.INFO)
      return
    end

    local loader = require('zpack.plugin_loader')
    loader.try_process_spec(pack.spec, {})
    if registry_entry.load_status == "loaded" then
      util.schedule_notify(('Loaded %s'):format(plugin_name), vim.log.levels.INFO)
    end
  end,
  complete = function(arg_lead)
    local names = vim.tbl_keys(state.unloaded_plugin_names)
    -- sorted on each invocation; negligible for typical plugin counts
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return filter_completions(names, arg_lead)
  end,
}

Sub.delete = {
  bang = true,
  takes_arg = true,
  run = function(ctx)
    local plugin_name = ctx.arg
    if plugin_name == '' then
      if not ctx.bang then
        util.schedule_notify(('Use :%s! delete to confirm deletion of all installed plugin(s)'):format(ctx.cmd_name), vim.log.levels.WARN)
        return
      end
      -- Source names from vim.pack.get, not registered_plugins: the latter
      -- omits plugins absent from registered_plugins (e.g. cond-disabled
      -- ones), leaving their zpack state behind after the wipe.
      local names = {}
      for _, pack in ipairs(vim.pack.get(nil, { info = false })) do
        if state.spec_registry[pack.spec.src] then
          table.insert(names, pack.spec.name)
        end
      end
      table.insert(names, 'zpack.nvim')

      util.schedule_notify(("Deleting all %d installed plugin(s)..."):format(#names), vim.log.levels.INFO)
      vim.pack.del(names, { force = true })
      util.schedule_notify(
        "All plugins deleted. This can result in errors in your current session. Restart Neovim to re-install them or remove them from your spec.",
        vim.log.levels.WARN)
      return
    end

    local pack = get_installed_or_notify(plugin_name)
    if not pack then
      return
    end

    -- pack.spec.name is canonical (case-insensitive FS safety).
    vim.pack.del({ pack.spec.name }, { force = true })
    util.schedule_notify(
      ('%s deleted. This can result in errors in your current session. Restart Neovim to re-install it or remove it from your spec.')
      :format(plugin_name),
      vim.log.levels.WARN
    )
  end,
  complete = function(arg_lead)
    return filter_completions(state.registered_plugin_names, arg_lead)
  end,
}

-- Always force-applies: vim.pack.update's confirm buffer returns immediately,
-- so a no-force form would race clean_unused ahead of the user's response.
-- For a preview, use `:ZPack update` (no bang) first.
Sub.sync = {
  run = function()
    run_pack_update('', { force = true }, 'Sync update failed')
    M.clean_unused()
  end,
}

-- lazy.nvim parity: `:ZPack reload <plugin>` runs the plugin's
-- `deactivate` hook (if defined), drops its `package.loaded` modules so
-- next require triggers a fresh load, resets the registry's load_status
-- to 'pending', and re-runs process_spec. Pair with the deactivate hook
-- which is now an accepted spec field.
Sub.reload = {
  takes_arg = true,
  run = function(ctx)
    local plugin_name = ctx.arg
    if plugin_name == '' then
      util.schedule_notify(('Usage: :%s reload <plugin>'):format(ctx.cmd_name), vim.log.levels.WARN)
      return
    end
    local pack = get_installed_or_notify(plugin_name)
    if not pack then return end

    local registry_entry = state.spec_registry[pack.spec.src]
    if not registry_entry or not registry_entry.merged_spec then
      util.schedule_notify(('Plugin "%s" not in zpack registry'):format(plugin_name), vim.log.levels.ERROR)
      return
    end

    -- Mid-load reload would slip past process_spec's circular-dep guard.
    if registry_entry.load_status == 'loading' then
      util.schedule_notify(
        ('Cannot reload %s: plugin is currently loading'):format(plugin_name),
        vim.log.levels.WARN
      )
      return
    end

    local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
    local plugin = registry_entry.plugin

    -- Skip deactivate when plugin is nil (never-loaded / install-failed):
    -- deactivate(nil) would force user code to nil-guard. A throw is caught
    -- and surfaced so a broken deactivate doesn't strand the reload.
    if plugin and type(spec.deactivate) == 'function' then
      local ok, err = pcall(spec.deactivate, plugin)
      if not ok then
        util.schedule_notify(
          ('Failed to run deactivate hook for %s: %s'):format(plugin_name, tostring(err)),
          vim.log.levels.WARN
        )
      end
    end

    -- Drop modules whose file lives under THIS plugin's lua/. The fs_stat
    -- is the sibling-plugin disambiguator (e.g. telescope-fzf-native's
    -- `telescope.extensions.fzf`); the `main` prefix is an optimization,
    -- skipped when utils.resolve_main caches a not-found result.
    local lua_dir = plugin and plugin.path and (plugin.path .. '/lua') or nil
    if lua_dir then
      local main = plugin and require('zpack.utils').resolve_main(plugin, spec) or nil
      local prefix = main and main ~= '' and (main .. '.') or nil
      for key in pairs(package.loaded) do
        if type(key) == 'string' then
          local in_namespace = prefix == nil
              or key == main
              or key:sub(1, #prefix) == prefix
          if in_namespace then
            local rel = key:gsub('%.', '/')
            if vim.uv.fs_stat(lua_dir .. '/' .. rel .. '.lua')
                or vim.uv.fs_stat(lua_dir .. '/' .. rel .. '/init.lua') then
              package.loaded[key] = nil
            end
          end
        end
      end
    end

    -- init runs once at startup; reload re-runs it (fresh-load contract).
    -- Type-guard: try_call_hook ERRORs on a missing hook, and startup's
    -- caller pre-filters via ctx.src_with_init.
    if type(spec.init) == 'function' then
      hooks.try_call_hook(pack.spec.src, 'init')
    end

    -- Prefer src_to_pack_spec over pack.spec: process_spec keys on the
    -- former (the merged form), and pack.spec is the minimal vim.pack form.
    registry_entry.load_status = 'pending'
    state.unloaded_plugin_names[pack.spec.name] = true
    local pack_spec = state.src_to_pack_spec[pack.spec.src] or pack.spec
    require('zpack.plugin_loader').try_process_spec(pack_spec, {})
    if registry_entry.load_status == 'loaded' then
      util.schedule_notify(('Reloaded %s'):format(plugin_name), vim.log.levels.INFO)
    end
  end,
  complete = function(arg_lead)
    return filter_completions(state.registered_plugin_names, arg_lead)
  end,
}

-- Ordered list used for completion and usage messages.
local SUB_ORDER = { 'update', 'restore', 'clean', 'build', 'load', 'delete', 'sync', 'reload' }

-- Guard against SUB_ORDER drifting out of sync with the Sub table.
do
  local listed = {}
  for _, name in ipairs(SUB_ORDER) do
    assert(Sub[name], 'SUB_ORDER lists unknown subcommand: ' .. name)
    listed[name] = true
  end
  for name in pairs(Sub) do
    assert(listed[name], 'Sub defines a subcommand missing from SUB_ORDER: ' .. name)
  end
end

---@param cmd_name string
---@return function
local make_dispatcher = function(cmd_name)
  return function(opts)
    local fargs = opts.fargs or {}
    local subname = fargs[1]
    if not subname or subname == '' then
      util.schedule_notify(('Usage: :%s {%s} [args]'):format(cmd_name, table.concat(SUB_ORDER, '|')), vim.log.levels.WARN)
      return
    end

    local sub = Sub[subname]
    if not sub then
      util.schedule_notify(('Unknown subcommand "%s". Available: %s'):format(subname, table.concat(SUB_ORDER, ', ')), vim.log.levels.ERROR)
      return
    end

    if opts.bang and not sub.bang then
      util.schedule_notify(('Subcommand "%s" does not accept "!"'):format(subname), vim.log.levels.WARN)
      return
    end

    local max_args = sub.takes_arg and 1 or 0
    if #fargs - 1 > max_args then
      util.schedule_notify(
        ('Subcommand "%s" accepts %s'):format(
          subname, max_args == 0 and 'no arguments' or 'at most one argument'),
        vim.log.levels.WARN
      )
      return
    end

    sub.run({
      arg = fargs[2] or '',
      bang = opts.bang,
      cmd_name = cmd_name,
    })
  end
end

---@return string[]
local complete_command = function(arg_lead, cmd_line, _cursor_pos)
  -- Strip the leading command word and optional bang so the remainder is
  -- "<subcommand> [args]". The command word runs up to the first whitespace
  -- or bang; "[^%s!]" rather than "%S" stops ":ZPack!load" from eating "load".
  local after_cmd = (cmd_line:gsub('^%s*[^%s!]*!?%s*', '', 1))
  local parts = vim.split(after_cmd, '%s+', { trimempty = false })

  -- Completing the subcommand itself
  if #parts <= 1 then
    return filter_completions(SUB_ORDER, arg_lead)
  end

  local subname = parts[1]
  local sub = Sub[subname]
  if not sub or not sub.complete then
    return {}
  end
  return sub.complete(arg_lead)
end

---@param cmd_name string
M.setup = function(cmd_name)
  if not validate_name(cmd_name) then
    util.schedule_notify(('Invalid cmd_name "%s": must start with uppercase letter and contain only letters/digits'):format(tostring(cmd_name)), vim.log.levels.ERROR)
    return
  end

  local ok, err = pcall(vim.api.nvim_create_user_command, cmd_name, make_dispatcher(cmd_name), {
    nargs = '*',
    bang = true,
    desc = 'zpack: ' .. table.concat(SUB_ORDER, '|'),
    complete = complete_command,
  })
  if not ok then
    util.schedule_notify(('Failed to create command %s: %s'):format(cmd_name, err), vim.log.levels.ERROR)
  end
end

---------------------------------------------------------------------
-- Legacy commands
---------------------------------------------------------------------

-- Command suffixes frozen from the pre-:ZPack era; new subcommands
-- intentionally do not get legacy aliases. Each legacy command delegates
-- to the :<cmd_name> dispatcher, so bang/argument validation cannot drift
-- from it.
local LEGACY_SUFFIXES = { 'Update', 'Restore', 'Clean', 'Build', 'Load', 'Delete' }

---@param prefix string Prefix to register legacy commands under (e.g. 'Z'). Empty string registers bare :Update/:Clean/etc.
---@param cmd_name string Resolved primary command name, referenced in deprecation messages.
M.setup_legacy = function(prefix, cmd_name)
  local deprecation = require('zpack.deprecation')

  -- Empty prefix is a valid back-compat case; otherwise enforce the same rules as cmd_name.
  if prefix ~= '' and not validate_name(prefix) then
    deprecation.notify_cmd_prefix_deprecated(cmd_name)
    util.schedule_notify(
      ('Invalid cmd_prefix "%s": must start with uppercase letter and contain only letters/digits. Legacy commands not registered.')
        :format(tostring(prefix)),
      vim.log.levels.ERROR
    )
    return
  end

  local dispatch = make_dispatcher(cmd_name)

  for _, suffix in ipairs(LEGACY_SUFFIXES) do
    local legacy_name = prefix .. suffix
    local sub_name = suffix:lower()
    local sub = Sub[sub_name]
    -- Registered permissively (nargs '*', bang) so any misuse reaches the
    -- dispatcher and gets its validation rather than a raw Vim parse error.
    local cmd_opts = {
      nargs = '*',
      bang = true,
      desc = ('[deprecated] use :%s %s instead'):format(cmd_name, sub_name),
    }

    if sub.complete then
      cmd_opts.complete = function(arg_lead) return sub.complete(arg_lead) end
    end

    pcall(vim.api.nvim_create_user_command, legacy_name, function(opts)
      deprecation.notify_legacy_command(legacy_name, cmd_name, sub_name)
      local dispatch_args = { sub_name }
      vim.list_extend(dispatch_args, opts.fargs)
      dispatch({ fargs = dispatch_args, bang = opts.bang })
    end, cmd_opts)
  end
end

return M
