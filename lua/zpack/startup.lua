local state = require('zpack.state')
local hooks = require('zpack.hooks')
local keymap = require('zpack.keymap')
local util = require('zpack.utils')
local loader = require('zpack.plugin_loader')

local M = {}

---Topological sort for startup plugins respecting dependencies
---Returns sorted packs and a set of lazy dependency srcs that need loading
---@param packs vim.pack.Spec[]
---@return vim.pack.Spec[] sorted_packs
---@return { [string]: string[] } lazy_deps_map (startup_src -> list of lazy dep srcs)
local function toposort_startup_packs(packs)
  local src_to_pack = {}
  for _, pack in ipairs(packs) do
    src_to_pack[pack.src] = pack
  end

  local in_progress = {}
  local done = {}
  local result = {}
  local lazy_deps_map = {}

  local function visit(pack)
    if done[pack.src] then return end

    if in_progress[pack.src] then
      util.schedule_notify(
        ("Circular dependency detected in startup plugins involving: %s"):format(pack.src),
        vim.log.levels.WARN
      )
      return
    end

    in_progress[pack.src] = true

    local deps = state.dependency_graph[pack.src]
    if deps then
      for dep_src in pairs(deps) do
        local dep_pack = src_to_pack[dep_src]
        if dep_pack then
          visit(dep_pack)
        elseif state.src_to_pack_spec[dep_src] then
          local dep_entry = state.spec_registry[dep_src]
          if dep_entry and dep_entry.cond_result == false then
            util.schedule_notify(
              ("%s has cond=false but is a dependency of %s and will be loaded anyway"):format(dep_src, pack.src),
              vim.log.levels.WARN
            )
          end
          lazy_deps_map[pack.src] = lazy_deps_map[pack.src] or {}
          table.insert(lazy_deps_map[pack.src], dep_src)
        end
      end
    end

    in_progress[pack.src] = nil
    done[pack.src] = true
    result[#result + 1] = pack
  end

  table.sort(packs, util.compare_priority)

  for _, pack in ipairs(packs) do
    visit(pack)
  end

  return result, lazy_deps_map
end

---@param ctx zpack.ProcessContext
M.process_all = function(ctx)
  table.sort(ctx.src_with_init, util.compare_priority)

  for _, src in ipairs(ctx.src_with_init) do
    hooks.try_call_hook(src, 'init')
  end

  local sorted_packs, lazy_deps_map = toposort_startup_packs(ctx.registered_startup_packs)

  -- pcall packadd per plugin so one broken plugin doesn't strand every
  -- later one. Track failures so later loops (run_config, apply_keys,
  -- finalization) skip them — otherwise the failed plugin would be marked
  -- loaded and hidden from :ZPack load / :checkhealth.
  local failed_packs = {}
  for _, pack_spec in ipairs(sorted_packs) do
    local ok, err = pcall(vim.cmd.packadd, { pack_spec.name, bang = not ctx.load })
    if not ok then
      failed_packs[pack_spec.src] = true
      util.schedule_notify(("Failed to packadd %s: %s"):format(pack_spec.name or pack_spec.src, tostring(err)), vim.log.levels.ERROR)
    elseif ctx.load then
      local entry = state.spec_registry[pack_spec.src]
      if entry and entry.plugin and entry.plugin.path then
        util.source_after_plugin_files(entry.plugin.path)
      end
    end
  end

  for _, pack_spec in ipairs(sorted_packs) do
    if not failed_packs[pack_spec.src] then
      local lazy_deps = lazy_deps_map[pack_spec.src]
      if lazy_deps then
        for _, dep_src in ipairs(lazy_deps) do
          local dep_pack = state.src_to_pack_spec[dep_src]
          if dep_pack then
            loader.try_process_spec(dep_pack, { bang = not ctx.load })
          end
        end
      end

      local entry = state.spec_registry[pack_spec.src]
      local spec = entry.merged_spec --[[@as zpack.Spec]]
      if spec.config or entry.has_opts then
        -- pcall: run_config executes user function-form opts raw via
        -- merge.resolve_opts; a throw would strand later plugins.
        local ok, err = pcall(loader.run_config, pack_spec.src, entry.plugin, spec)
        if not ok then
          failed_packs[pack_spec.src] = true
          util.schedule_notify(("Failed to run config for %s: %s"):format(pack_spec.name or pack_spec.src, tostring(err)), vim.log.levels.ERROR)
        end
      end
    end
  end

  -- pcall apply_keys per plugin so a malformed key spec doesn't strand
  -- later plugins. NOT added to failed_packs: packadd + run_config already
  -- succeeded, so the plugin should still finalize as "loaded" — mirrors
  -- the plugin_loader.process_spec ordering.
  for _, pack_spec in ipairs(sorted_packs) do
    if not failed_packs[pack_spec.src] then
      local entry = state.spec_registry[pack_spec.src]
      local spec = entry.merged_spec --[[@as zpack.Spec]]
      local label = pack_spec.name or pack_spec.src
      local keys = util.try_resolve_field(spec.keys, entry.plugin, label, 'keys')
      if keys then
        local ok, err = pcall(keymap.apply_keys, keys, label)
        if not ok then
          util.schedule_notify(
            ("Failed to apply keys for %s: %s"):format(label, tostring(err)),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  for _, pack_spec in ipairs(sorted_packs) do
    if not failed_packs[pack_spec.src] then
      state.spec_registry[pack_spec.src].load_status = "loaded"
      state.unloaded_plugin_names[pack_spec.name] = nil
    end
  end
end

return M
