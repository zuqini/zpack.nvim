local state = require('zpack.state')
local keymap = require('zpack.keymap')
local utils = require('zpack.utils')
local merge = require('zpack.merge')

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
---@param spec zpack.Spec
function M.run_config(src, plugin, spec)
  local registry_entry = state.spec_registry[src]
  -- resolve_opts is the single authoritative path for opts; it walks
  -- sorted_specs fresh so function-form opts compose correctly.
  local resolved_opts = merge.resolve_opts(registry_entry.sorted_specs or {}, plugin)
  local main = utils.resolve_main(plugin, spec)
  local label = (plugin and plugin.spec and plugin.spec.name) or src

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

---Find pack_spec by source URL
---@param src string
---@return vim.pack.Spec?
local function find_pack_spec_by_src(src)
  return state.src_to_pack_spec[src]
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

  registry_entry.load_status = "loading"

  -- On throw, reset load_status to "pending" so a retry doesn't hit the
  -- "Circular dependency" branch above; re-raise to preserve the existing
  -- throw-propagation contract for non-try callers. apply_keys runs OUTSIDE
  -- this pcall — once run_config has succeeded, a key-spec throw must not
  -- roll back into a retry that double-runs run_config.
  local ok, err = pcall(function()
    vim.cmd.packadd({ name, bang = opts.bang })

    -- :packadd sources plugin/ but never after/plugin/. Source them explicitly.
    if not opts.bang and plugin.path then
      utils.source_after_plugin_files(plugin.path)
    end

    local deps = state.dependency_graph[pack_spec.src]
    if deps then
      for dep_src in pairs(deps) do
        local dep_entry = state.spec_registry[dep_src]
        if dep_entry and dep_entry.load_status ~= "loaded" then
          if dep_entry.cond_result == false then
            utils.schedule_notify(
              ("%s has cond=false but is a dependency of %s and will be loaded anyway"):format(dep_src, pack_spec.src),
              vim.log.levels.WARN
            )
          end
          local dep_pack_spec = find_pack_spec_by_src(dep_src)
          if dep_pack_spec then
            M.process_spec(dep_pack_spec, opts)
          else
            utils.schedule_notify(
              ("Dependency %s not found for %s"):format(dep_src, pack_spec.src),
              vim.log.levels.WARN
            )
          end
        end
      end
    end

    if spec.config or registry_entry.has_opts then
      M.run_config(pack_spec.src, plugin, spec)
    end
  end)

  if not ok then
    registry_entry.load_status = "pending"
    error(err, 0)
  end

  -- Commit load_status before apply_keys so a key-spec throw can't roll
  -- back into a retry that would double-run run_config.
  registry_entry.load_status = "loaded"
  state.unloaded_plugin_names[name] = nil

  local keys = utils.try_resolve_field(spec.keys, plugin, name, 'keys')
  if keys then
    local keys_ok, keys_err = pcall(keymap.apply_keys, keys, name)
    if not keys_ok then
      utils.schedule_notify(
        ("Failed to apply keys for %s: %s"):format(name, tostring(keys_err)),
        vim.log.levels.ERROR
      )
    end
  end
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
