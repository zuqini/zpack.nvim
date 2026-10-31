local state = require('zpack.state')
local lazy = require('zpack.lazy')
local utils = require('zpack.utils')

local M = {}

---Decide whether a plugin is lazy and whether its cond lets it load at all.
---@param plugin zpack.Plugin
---@param ctx zpack.ProcessContext
local function classify(plugin, ctx)
  local pack_spec = plugin.spec
  local registry_entry = state.spec_registry[pack_spec.src]
  local spec = registry_entry.merged_spec --[[@as zpack.Spec]]

  registry_entry.is_lazy_resolved = lazy.is_lazy(spec, plugin, pack_spec.src)

  registry_entry.cond_result = utils.check_cond(spec, plugin, ctx.defaults.cond, pack_spec.src)
  if not registry_entry.cond_result then
    return
  end

  table.insert(state.registered_plugin_names, pack_spec.name)
  state.unloaded_plugin_names[pack_spec.name] = true

  if spec.build then
    table.insert(state.plugin_names_with_build, pack_spec.name)
  end

  if spec.init then
    table.insert(ctx.src_with_init, pack_spec.src)
  end

  if registry_entry.is_lazy_resolved then
    table.insert(ctx.registered_lazy_packs, pack_spec)
  else
    table.insert(ctx.registered_startup_packs, pack_spec)
    lazy.warn_unusable_triggers(spec, plugin, pack_spec.name)
  end
end

---@param ctx zpack.ProcessContext
M.register_all = function(ctx)
  local added = {}
  local function on_load(plugin)
    ---@cast plugin zpack.Plugin
    local pack_spec = plugin.spec
    ctx.early_plugins[pack_spec.name] = nil

    local registry_entry = state.spec_registry[pack_spec.src]

    if not registry_entry or not registry_entry.merged_spec then
      return
    end

    registry_entry.plugin = plugin
    state.src_to_pack_spec[pack_spec.src] = pack_spec
    if pack_spec.name then
      state.name_to_src[pack_spec.name] = pack_spec.src
    end

    -- lazy.nvim spec parity: callbacks (init/config/opts/cond/build/deactivate)
    -- receive a plugin object whose introspection fields (`name`, `dir`,
    -- `dependencies`) match LazyPlugin's shape. zpack's existing `spec` /
    -- `path` fields are preserved; the new fields are additive aliases.
    -- `dependencies` is a sorted list of resolved dependency names so the
    -- value is stable across runs even though dependency_graph is a set.
    plugin.name = pack_spec.name
    plugin.dir = plugin.path
    local dep_set = state.dependency_graph[pack_spec.src]
    if dep_set then
      local dep_names = {}
      for dep_src in pairs(dep_set) do
        table.insert(dep_names, utils.resolve_plugin_name(state.spec_registry[dep_src].merged_spec, dep_src))
      end
      table.sort(dep_names)
      plugin.dependencies = dep_names
    else
      plugin.dependencies = {}
    end

    table.insert(added, plugin)
  end

  local err = require('zpack.pack').add(ctx.vim_packs, { confirm = ctx.confirm, load = on_load })
  local ok = err == nil

  if not ok then
    local semver_like_specs = {}
    for _, pack_spec in ipairs(ctx.vim_packs) do
      if pack_spec.version and utils.is_semver_like(pack_spec.version) then
        table.insert(semver_like_specs, pack_spec)
      end
    end
    if #semver_like_specs > 0 then
      utils.notify('`vim.pack.add` failed.', vim.log.levels.WARN)
      for _, pack_spec in ipairs(semver_like_specs) do
        utils.notify(
          ('Is `version = "%s"` for %s meant to be a semver range?\n'
            .. 'Consider using `sem_version = "%s"` or `version = vim.version.range("%s")` instead.')
            :format(pack_spec.version, pack_spec.src, pack_spec.version, pack_spec.version),
          vim.log.levels.WARN
        )
      end
    end
    utils.notify(err, vim.log.levels.ERROR)
  end

  for _, pack_spec in ipairs(ctx.vim_packs) do
    local early = ctx.early_plugins[pack_spec.name]
    if early then
      on_load({ spec = pack_spec, path = early.path })
    end
    -- vim.pack adds the plugins it can before raising; the rest are gone for this
    -- session, and nothing after this should try to load them.
    local registry_entry = state.spec_registry[pack_spec.src]
    if not ok and registry_entry and not registry_entry.plugin then
      state.remove_plugin(pack_spec.name, pack_spec.src)
    end
  end

  -- A dependency's lazy flag can call its parent's function-form trigger, which
  -- needs the parent's plugin, so this waits until vim.pack has returned them all.
  for _, plugin in ipairs(added) do
    classify(plugin, ctx)
  end

  table.sort(ctx.registered_startup_packs, utils.compare_priority)
  table.sort(ctx.registered_lazy_packs, utils.compare_priority)
  table.sort(state.registered_plugin_names, function(a, b) return a:lower() < b:lower() end)
  table.sort(state.plugin_names_with_build, function(a, b) return a:lower() < b:lower() end)

  vim.list_extend(state.registered_plugins, ctx.registered_startup_packs)
  vim.list_extend(state.registered_plugins, ctx.registered_lazy_packs)
end

return M
