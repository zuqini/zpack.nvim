if jit then jit.off(true, true) end

local state = require('zpack.state')
local keymap = require('zpack.keymap')
local runtime = require('zpack.runtime')
local utils = require('zpack.utils')
local spec_opts = require('zpack.opts')
local cmd_proxy = require('zpack.cmd_proxy')
local key_proxy = require('zpack.key_proxy')

local M = {}

---Run auto-setup: require(main).setup(opts)
---@param label string Plugin identifier for failure notifies (name or src)
---@param main string
---@param resolved_opts table
---@return boolean success
local function run_auto_setup(label, main, resolved_opts)
  local ok, mod_or_err = pcall(require, main)
  if not ok then
    utils.schedule_notify(("Failed to require '%s' for %s: %s"):format(main, label, tostring(mod_or_err)), vim.log.levels.ERROR)
    return false
  end
  if type(mod_or_err) ~= "table" or type(mod_or_err.setup) ~= "function" then
    utils.schedule_notify(("Module '%s' for %s has no setup() function"):format(main, label), vim.log.levels.WARN)
    return false
  end
  local mod = mod_or_err

  local success, err = pcall(mod.setup, resolved_opts)
  if not success then
    utils.schedule_notify(("Failed to run setup for %s: %s"):format(label, tostring(err)), vim.log.levels.ERROR)
    return false
  end

  return true
end

---Run config/setup for a plugin
---@param src string
---@param plugin zpack.Plugin
function M.run_config(src, plugin)
  local registry_entry = state.spec_registry[src]
  local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
  local label = (plugin and plugin.spec and plugin.spec.name) or src
  -- resolve_opts is the single authoritative path for opts; it walks
  -- sorted_specs fresh so function-form opts compose correctly.
  local opts_ok, resolved_opts = pcall(
    spec_opts.resolve_opts,
    registry_entry.sorted_specs or {},
    plugin,
    spec.opts_extend
  )
  if not opts_ok then
    utils.schedule_notify(("Failed to run config for %s: %s"):format(label, tostring(resolved_opts)), vim.log.levels.ERROR)
    return
  end
  local main = utils.resolve_main(plugin, spec)

  if type(spec.config) == "function" then
    local config_fn = spec.config --[[@as fun(plugin: zpack.Plugin, opts: table)]]
    local ok, err = pcall(config_fn, plugin, resolved_opts)
    if not ok then
      utils.schedule_notify(("Failed to run config for %s: %s"):format(label, tostring(err)), vim.log.levels.ERROR)
    end
  elseif spec.config == true or registry_entry.has_opts then
    if not main then
      utils.schedule_notify(
        ("Could not determine main module for %s. Please set `main` explicitly or use `config = function() ... end`.")
        :format(label),
        vim.log.levels.WARN
      )
    else
      run_auto_setup(label, main, resolved_opts)
    end
  end
end

---@param dep_src string
---@param parent_src string
M.warn_if_cond_false = function(dep_src, parent_src)
  local dep_entry = state.spec_registry[dep_src]
  if dep_entry and dep_entry.cond_result == false then
    utils.schedule_notify(
      ("%s has cond=false but is a dependency of %s and will be loaded anyway"):format(dep_src, parent_src),
      vim.log.levels.WARN
    )
  end
end

---One bad key spec doesn't stop the plugins after it, and the plugin stays loaded.
---@param registry_entry zpack.RegistryEntry
---@param label string
M.bind_keys = function(registry_entry, label)
  local parsed = utils.read_trigger(registry_entry, 'keys', keymap.parse, registry_entry.plugin, label)
  if parsed then
    local ok, err = pcall(keymap.apply_keys, key_proxy.unclaimed(parsed.keys), label)
    if not ok then
      utils.schedule_notify(
        ("Failed to apply keys for %s: %s"):format(label, tostring(err)),
        vim.log.levels.ERROR
      )
    end
  end
end

---@param pack_spec vim.pack.Spec
---@param opts? table
M.process_spec = function(pack_spec, opts)
  opts = opts or {}
  local registry_entry = state.spec_registry[pack_spec.src]

  -- A lazy trigger (cmd/keys/event/ft) can fire after its plugin was removed
  -- (e.g. :packdel). The trigger tears itself down on fire regardless; this
  -- guard keeps the resulting call a safe no-op instead of a nil index.
  if not registry_entry then
    return
  end

  if registry_entry.load_status == "loaded" then
    return
  end

  if registry_entry.load_status == "loading" then
    utils.schedule_notify(
      ("Circular dependency detected: %s is already being loaded"):format(pack_spec.src),
      vim.log.levels.ERROR
    )
    return
  end

  -- merged_spec is always populated post-resolve_all, when plugins load.
  local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
  local plugin = registry_entry.plugin

  if not plugin then
    utils.schedule_notify(("Cannot load %s: plugin not registered"):format(pack_spec.src), vim.log.levels.ERROR)
    return
  end

  -- vim.pack.add's load callback has populated spec.name by this point.
  local name = plugin.spec.name --[[@as string]]
  -- `bang` asks to leave sourcing to native startup, which only does it for what
  -- reaches 'runtimepath' before v:vim_did_init.
  local bang = opts.bang and vim.v.vim_did_init == 0
  local sourced = registry_entry.load_status == "sourced"

  registry_entry.load_status = "loading"
  -- lazy.nvim parity: a plugin's own `:command Foo` fails while a proxy holds the name.
  cmd_proxy.release(pack_spec.src)
  key_proxy.release(pack_spec.src)

  -- On throw, reset load_status to "pending" so a retry doesn't hit the
  -- "Circular dependency" branch above; re-raise to preserve the existing
  -- throw-propagation contract for non-try callers. apply_keys runs OUTSIDE
  -- this pcall — once run_config has succeeded, a key-spec throw must not
  -- roll back into a retry that double-runs run_config.
  local ok, err = pcall(function()
    local deps = utils.sorted_dependencies(pack_spec.src)
    -- Native startup sources ftdetect/ only for what's on 'runtimepath' as filetype detection comes on.
    -- What's on it already got its ftdetect/ then, or from startup's eager pass.
    local ftdetect = bang and vim.g.did_load_filetypes and plugin.path
        and not (',' .. vim.o.runtimepath .. ','):find(',' .. plugin.path .. ',', 1, true)

    -- lazy.nvim parity: on 'runtimepath' first, since a dependency's scripts can
    -- require its parent, but sourced after its dependencies.
    if bang or #deps > 0 then
      vim.cmd.packadd({ name, bang = true })
    end
    if ftdetect then
      runtime.source_ftdetect_files(plugin.path)
    end

    for _, dep_src in ipairs(deps) do
      local dep_entry = state.spec_registry[dep_src]
      if dep_entry and dep_entry.load_status ~= "loaded" then
        M.warn_if_cond_false(dep_src, pack_spec.src)
        local dep_pack_spec = state.src_to_pack_spec[dep_src]
        if dep_pack_spec then
          -- lazy.nvim parity: a dependency that fails doesn't stop its parent.
          M.try_process_spec(dep_pack_spec, opts)
        else
          utils.schedule_notify(
            ("Dependency %s not found for %s"):format(dep_src, pack_spec.src),
            vim.log.levels.WARN
          )
        end
      end
    end

    if not bang and not sourced then
      runtime.packadd_sourcing(name, plugin.path)
    end

    if spec.config or registry_entry.has_opts then
      M.run_config(pack_spec.src, plugin)
    end
  end)

  if not ok then
    registry_entry.load_status = "pending"
    error(err, 0)
  end

  -- Commit load_status before apply_keys so a key-spec throw can't roll
  -- back into a retry that would double-run run_config.
  registry_entry.load_status = "loaded"
  M.bind_keys(registry_entry, name)
end

---pcall + structured-notify wrapper for `process_spec`. Used at every lazy
---trigger entry point so a broken plugin can't throw past the autocmd /
---user-command boundary.
---@param pack_spec vim.pack.Spec
---@param opts? table
---@return boolean ok
M.try_process_spec = function(pack_spec, opts)
  local ok, err = pcall(M.process_spec, pack_spec, opts)
  if not ok then
    utils.schedule_notify(
      ("Failed to load %s: %s"):format(pack_spec.name or pack_spec.src, tostring(err)),
      vim.log.levels.ERROR
    )
  end
  return ok
end

return M
