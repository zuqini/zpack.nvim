if jit then jit.off(true, true) end

local fields = require('zpack.merge_fields')
local fold = require('zpack.fold')
local pack = require('zpack.pack')
local prune = require('zpack.prune')
local state = require('zpack.state')
local utils = require('zpack.utils')

local M = {}

---Edges run from each plugin to the plugins its remaining specs list under
---`dependencies`.
local function build_dependency_graph(graph, dead)
  for parent, children in pairs(graph.spec_children) do
    local src = graph.spec_src[parent]
    if not dead[parent] and state.spec_registry[src] then
      for child, is_dep in pairs(children) do
        local dep_src = graph.spec_src[child]
        if is_dep and dep_src ~= src and state.spec_registry[dep_src] then
          state.dependency_graph[src] = state.dependency_graph[src] or {}
          state.dependency_graph[src][dep_src] = true
          state.dependency_order[src] = state.dependency_order[src] or {}
          local order = child._import_order or 0
          state.dependency_order[src][dep_src] = math.min(state.dependency_order[src][dep_src] or order, order)
          state.reverse_dependency_graph[dep_src] = state.reverse_dependency_graph[dep_src] or {}
          state.reverse_dependency_graph[dep_src][src] = true
        end
      end
    end
  end
end

---Pre-compute merged_spec for all entries in the registry
---Creates pack_specs with merged data and returns sorted vim_packs array
---@param graph zpack.SpecGraph What the import found
---@param enabled_results { [zpack.Spec]: boolean } See zpack.Imported
---@param notify? fun(msg: string, level: integer) For what's decided here. Default: utils.schedule_notify
---@return vim.pack.Spec[]
function M.resolve_all(graph, enabled_results, notify)
  notify = notify or utils.schedule_notify
  for _, entry in pairs(state.spec_registry) do
    fields.merge_entry(entry)
  end

  local folded_from, fold_warnings = fold.coalesce_same_name(graph)

  for src, entry in pairs(state.spec_registry) do
    fields.resolve_enabled(enabled_results, entry, src)
    -- cond_result is intentionally left nil here. It is written later by
    -- registration.register_all's vim.pack.add load callback (which needs
    -- the live plugin arg for function-form conds). Readers must treat
    -- nil as "not yet evaluated" and only act on an explicit `== false`.
    -- Do not read cond_result between resolve_all and register_all.
  end

  local dead, disabling = prune.prune_disabled(graph, folded_from, enabled_results, notify)
  fold.warn_folds(fold_warnings, dead, disabling, notify)
  build_dependency_graph(graph, dead)

  local vim_packs = {}
  for src, entry in pairs(state.spec_registry) do
    assert(entry.enabled_result ~= false, ("internal: registry entry for %s survived prune_disabled with enabled_result=false"):format(src))
    local version, is_soft = pack.normalize_version(entry.merged_spec)
    entry.soft_version = is_soft and version --[[@as vim.VersionRange]] or nil
    local pack_spec = {
      src = src,
      version = version,
      name = pack.resolve_plugin_name(entry.merged_spec, src),
    }
    -- Now, so `get_plugin(name)` finds entries still mid-install, whose
    -- vim.pack.add load callback has not fired yet.
    state.name_to_src[pack_spec.name] = src
    table.insert(vim_packs, pack_spec)
    state.src_to_pack_spec[src] = pack_spec
  end

  table.sort(vim_packs, utils.compare_priority)
  return vim_packs
end

return M
