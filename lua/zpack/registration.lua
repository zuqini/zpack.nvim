local state = require('zpack.state')
local lazy = require('zpack.lazy')
local utils = require('zpack.utils')

local M = {}

---Process a single plugin registration — shared by both the vim.pack.add load
---callback (remote plugins) and the direct local-path registration path.
---@param plugin zpack.Plugin
---@param ctx zpack.ProcessContext
local function register_plugin(plugin, ctx)
  local pack_spec = plugin.spec
  local registry_entry = state.spec_registry[pack_spec.src]

  if not registry_entry or not registry_entry.merged_spec then
    return
  end

  local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
  registry_entry.plugin = plugin
  state.src_to_pack_spec[pack_spec.src] = pack_spec
  if pack_spec.name then
    state.name_to_src[pack_spec.name] = pack_spec.src
  end

  registry_entry.is_lazy_resolved = lazy.is_lazy(spec, plugin, pack_spec.src)

  registry_entry.cond_result = utils.check_cond(spec, plugin, ctx.defaults.cond)
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
  end
end

---@param ctx zpack.ProcessContext
M.register_all = function(ctx)
  local remote_packs = {}
  local local_packs = {}

  for _, pack_spec in ipairs(ctx.vim_packs) do
    if utils.is_local_src(pack_spec.src) then
      table.insert(local_packs, pack_spec)
    else
      table.insert(remote_packs, pack_spec)
    end
  end

  -- Local-path plugins: vim.pack.add is designed for remote git repos and may
  -- not call the load callback for local directories. Register them directly
  -- with a synthetic plugin object so the rest of the pipeline (startup,
  -- lazy triggers, config hooks) works normally.
  for _, pack_spec in ipairs(local_packs) do
    if not pack_spec.name then
      pack_spec.name = utils.derive_name_from_src(pack_spec.src)
    end
    local plugin = {
      spec = pack_spec,
      path = pack_spec.src,
    }
    register_plugin(plugin, ctx)
  end

  local ok, err = pcall(vim.pack.add, remote_packs, {
    confirm = ctx.confirm,
    load = function(plugin)
      register_plugin(plugin, ctx)
    end
  })

  if not ok then
    local semver_like_specs = {}
    for _, pack_spec in ipairs(remote_packs) do
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
    error(err)
  end

  table.sort(ctx.registered_startup_packs, utils.compare_priority)
  table.sort(ctx.registered_lazy_packs, utils.compare_priority)
  table.sort(state.registered_plugin_names, function(a, b) return a:lower() < b:lower() end)
  table.sort(state.plugin_names_with_build, function(a, b) return a:lower() < b:lower() end)

  vim.list_extend(state.registered_plugins, ctx.registered_startup_packs)
  vim.list_extend(state.registered_plugins, ctx.registered_lazy_packs)
end

return M
