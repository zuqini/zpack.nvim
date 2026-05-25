local state = require('zpack.state')
local lazy = require('zpack.lazy')
local utils = require('zpack.utils')

local M = {}

---@param ctx zpack.ProcessContext
M.register_all = function(ctx)
  local ok, err = pcall(vim.pack.add, ctx.vim_packs, {
    confirm = ctx.confirm,
    load = function(plugin)
      ---@cast plugin zpack.Plugin
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
          -- Skip deps that prune_disabled dropped (e.g. `optional = true`
          -- with no required reference) so the user doesn't see a name
          -- they can never load.
          local dep_entry = state.spec_registry[dep_src]
          if dep_entry and dep_entry.merged_spec then
            table.insert(dep_names, dep_entry.merged_spec.name
              or utils.derive_name_from_src(dep_src))
          end
        end
        table.sort(dep_names)
        plugin.dependencies = dep_names
      else
        plugin.dependencies = {}
      end

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
      end
    end
  })

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
