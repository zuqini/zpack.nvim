local util = require('zpack.utils')

local M = {}

M.OVERRIDE = "override"
M.LIST_EXTEND = "list_extend"
M.AND_LOGIC_COND = "and_logic_cond"
M.AND_LOGIC_ENABLED = "and_logic_enabled"

-- `opts` is intentionally absent from this table. It is resolved lazily at
-- load time by `resolve_opts` so that function-form opts (which receive the
-- accumulated opts and may return a replacement) are handled with a single
-- authoritative code path. `merge_specs` skips `opts` entirely; callers that
-- need to know "does any spec contribute opts?" read `entry.has_opts`.
M.field_strategies = {
  name = M.OVERRIDE,
  main = M.OVERRIDE,
  priority = M.OVERRIDE,
  build = M.OVERRIDE,
  version = M.OVERRIDE,
  sem_version = M.OVERRIDE,
  branch = M.OVERRIDE,
  tag = M.OVERRIDE,
  commit = M.OVERRIDE,
  lazy = M.OVERRIDE,
  config = M.OVERRIDE,
  init = M.OVERRIDE,
  pattern = M.OVERRIDE,

  event = M.LIST_EXTEND,
  cmd = M.LIST_EXTEND,
  ft = M.LIST_EXTEND,
  keys = M.LIST_EXTEND,

  cond = M.AND_LOGIC_COND,
  enabled = M.AND_LOGIC_ENABLED,
}

local internal_fields = {
  _import_order = true,
  _is_dependency = true,
}

---Normalize value to array for LIST_EXTEND fields (event, cmd, ft, keys).
---Handles three cases:
---  1. nil -> empty array
---  2. Non-table (string) -> wrap in array: "BufRead" -> {"BufRead"}
---  3. Table:
---     - Already array-like (has [1]) or empty -> return as-is
---     - Dict-like (e.g., EventSpec {event="X", pattern="Y"}) -> wrap in array
---@param val any
---@return any[]
local function to_array(val)
  if val == nil then
    return {}
  end
  if type(val) ~= "table" then
    return { val }
  end
  if val[1] ~= nil or next(val) == nil then
    return val
  end
  return { val }
end

---Identity is (lhs, mode, ft, buffer) so disjoint-scope specs (same lhs
---under different ft/buffer) both survive merge. Format is private — only
---the identity is shared with lazy_trigger/keys.lua's create_key_id.
---@param v any
---@return string
local function get_unique_key(v)
  if type(v) ~= "table" then
    return tostring(v)
  end
  local lhs = v[1] or ""
  local mode = v.mode or "n"
  if type(mode) == "table" then
    local sorted = vim.list_slice(mode)
    table.sort(sorted)
    mode = table.concat(sorted, ",")
  end
  local ft = ""
  local ft_list = util.normalize_ft_scope(v.ft)
  if ft_list then
    local sorted = vim.list_slice(ft_list)
    table.sort(sorted)
    ft = ":ft=" .. table.concat(sorted, ",")
  end
  local buf = ""
  if v.buffer ~= nil then
    -- lazy.nvim parity: `buffer = true` and `buffer = 0` both mean "current
    -- buffer" — coerce so they share a key.
    local b = v.buffer == true and 0 or v.buffer
    buf = ":buf=" .. tostring(b)
  end
  return lhs .. ":" .. mode .. ft .. buf
end

---Extend list with unique values
---@param base any[]
---@param incoming any[]
---@return any[]
local function extend_unique(base, incoming)
  local seen = {}
  local result = {}

  for _, v in ipairs(base) do
    local key = get_unique_key(v)
    if not seen[key] then
      seen[key] = true
      table.insert(result, v)
    end
  end

  for _, v in ipairs(incoming) do
    local key = get_unique_key(v)
    if not seen[key] then
      seen[key] = true
      table.insert(result, v)
    end
  end

  return result
end

---@alias zpack.CondValue boolean|fun(plugin: zpack.Plugin):boolean
---@alias zpack.EnabledValue boolean|fun():boolean

---Merge cond AND logic: both must be truthy. Functions receive the plugin arg.
---@param base zpack.CondValue?
---@param incoming zpack.CondValue?
---@return zpack.CondValue?
local function merge_and_cond(base, incoming)
  if base == nil then
    return incoming
  end
  if incoming == nil then
    return base
  end

  if type(base) == "function" or type(incoming) == "function" then
    return function(plugin)
      local base_result = base
      if type(base) == "function" then
        base_result = base(plugin)
      end
      local incoming_result = incoming
      if type(incoming) == "function" then
        incoming_result = incoming(plugin)
      end
      -- Each result is a function's boolean return or the operand's own
      -- value; a non-function `cond` is already a boolean, so the `and`
      -- yields a boolean. The cast states what the analyzer cannot narrow.
      return base_result and incoming_result --[[@as boolean]]
    end
  end

  return base and incoming
end

---Merge enabled AND logic: both must be truthy. Functions are called with no arguments.
---@param base zpack.EnabledValue?
---@param incoming zpack.EnabledValue?
---@return zpack.EnabledValue?
local function merge_and_enabled(base, incoming)
  if base == nil then
    return incoming
  end
  if incoming == nil then
    return base
  end

  if type(base) == "function" or type(incoming) == "function" then
    return function()
      local base_result = base
      if type(base) == "function" then
        base_result = base()
      end
      local incoming_result = incoming
      if type(incoming) == "function" then
        incoming_result = incoming()
      end
      -- Each result is a function's boolean return or the operand's own
      -- value; a non-function `enabled` is already a boolean, so the `and`
      -- yields a boolean. The cast states what the analyzer cannot narrow.
      return base_result and incoming_result --[[@as boolean]]
    end
  end

  return base and incoming
end

---Merge two specs according to field strategies
---@param base zpack.Spec
---@param incoming zpack.Spec
---@return zpack.Spec
function M.merge_specs(base, incoming)
  local result = {}

  local all_keys = {}
  for k in pairs(base) do all_keys[k] = true end
  for k in pairs(incoming) do all_keys[k] = true end

  for key in pairs(all_keys) do
    -- 'opts' is intentionally not merged here: it is resolved lazily via
    -- resolve_opts at load time (see the comment above M.field_strategies).
    if key ~= "opts" then
      if internal_fields[key] then
        result[key] = incoming[key] ~= nil and incoming[key] or base[key]
      else
        local strategy = M.field_strategies[key] or M.OVERRIDE
        local base_val = base[key]
        local incoming_val = incoming[key]

        if incoming_val == nil then
          result[key] = base_val
        elseif base_val == nil then
          result[key] = incoming_val
        elseif strategy == M.OVERRIDE then
          result[key] = incoming_val
        elseif strategy == M.LIST_EXTEND then
          result[key] = extend_unique(to_array(base_val), to_array(incoming_val))
        elseif strategy == M.AND_LOGIC_COND then
          result[key] = merge_and_cond(base_val, incoming_val)
        elseif strategy == M.AND_LOGIC_ENABLED then
          result[key] = merge_and_enabled(base_val, incoming_val)
        end
      end
    end
  end

  return result
end

---Sort specs: dependencies first, then standalone (so standalone wins on conflict)
---@param specs zpack.Spec[]
---@return zpack.Spec[]
function M.sort_specs(specs)
  if not specs or #specs == 0 then
    return {}
  end
  local sorted = vim.list_slice(specs)
  table.sort(sorted, function(a, b)
    local a_dep = a._is_dependency and 1 or 0
    local b_dep = b._is_dependency and 1 or 0
    if a_dep ~= b_dep then
      return a_dep > b_dep
    end
    return (a._import_order or 0) < (b._import_order or 0)
  end)
  return sorted
end

---Merge an array of specs in order (lowest priority first).
---Always returns a fresh table (never a reference to any input spec), and
---`opts` is always absent from the result — it is resolved at load time via
---`resolve_opts` so function-form opts are handled consistently.
---@param specs zpack.Spec[]
---@return zpack.Spec
function M.merge_spec_array(specs)
  local result = {}
  for i = 1, #specs do
    result = M.merge_specs(result, specs[i])
  end
  return result
end

---Resolve opts through all specs, supporting function-form opts. Throws
---if any function-form opts throws — callers must pcall.
---@param specs zpack.Spec[]
---@param plugin zpack.Plugin
---@return table
function M.resolve_opts(specs, plugin)
  local accumulated = {}

  for _, spec in ipairs(specs) do
    local opts = spec.opts
    if opts ~= nil then
      if type(opts) == "function" then
        local result = opts(plugin, accumulated)
        if type(result) == "table" then
          accumulated = result
        end
      elseif type(opts) == "table" then
        accumulated = vim.tbl_deep_extend("force", accumulated, opts)
      end
    end
  end

  return accumulated
end

local function entry_is_dep_only(entry)
  for _, spec in ipairs(entry.specs) do
    if not spec._is_dependency then
      return false
    end
  end
  return true
end

local function strip_outgoing_edges(state, src)
  local outgoing = state.dependency_graph[src]
  if not outgoing then
    return {}
  end
  local newly_orphaned = {}
  for dep_src in pairs(outgoing) do
    local rdeps = state.reverse_dependency_graph[dep_src]
    if rdeps then
      rdeps[src] = nil
      if next(rdeps) == nil then
        state.reverse_dependency_graph[dep_src] = nil
        table.insert(newly_orphaned, dep_src)
      end
    end
  end
  state.dependency_graph[src] = nil
  return newly_orphaned
end

---Propagate enabled=false backward through reverse_dependency_graph.
---A plugin whose required dependency is disabled cannot function, so it is
---disabled too. Emits one warning per propagation step so the user learns
---which dep caused the cascade. Runs before prune_disabled so the pruner
---picks up the newly-disabled parents.
local function propagate_enabled_disable(state, utils)
  local worklist = {}
  for src, entry in pairs(state.spec_registry) do
    if entry.enabled_result == false then
      table.insert(worklist, src)
    end
  end

  while #worklist > 0 do
    local disabled_src = table.remove(worklist)
    local parents = state.reverse_dependency_graph[disabled_src]
    if parents then
      for parent_src in pairs(parents) do
        local parent_entry = state.spec_registry[parent_src]
        if parent_entry and parent_entry.enabled_result ~= false then
          parent_entry.enabled_result = false
          utils.schedule_notify(
            ("%s disabled because its dependency %s has enabled=false"):format(parent_src, disabled_src),
            vim.log.levels.WARN
          )
          table.insert(worklist, parent_src)
        end
      end
    end
  end
end

---Remove every enabled=false entry from the registry, plus any dep-only
---plugins that become orphaned as a side effect. After this runs, every
---remaining entry is guaranteed to reach vim.pack.add, which means the
---public API can rely on entry.plugin being populated by the load callback.
local function prune_disabled(state)
  local worklist = {}
  for src, entry in pairs(state.spec_registry) do
    if entry.enabled_result == false then
      table.insert(worklist, src)
    end
  end

  while #worklist > 0 do
    local src = table.remove(worklist)
    local orphaned = strip_outgoing_edges(state, src)
    state.spec_registry[src] = nil
    for _, dep_src in ipairs(orphaned) do
      local dep_entry = state.spec_registry[dep_src]
      if dep_entry and entry_is_dep_only(dep_entry) then
        table.insert(worklist, dep_src)
      end
    end
  end
end

---Pre-compute merged_spec for all entries in the registry
---Creates pack_specs with merged data and returns sorted vim_packs array
---@return vim.pack.Spec[]
function M.resolve_all()
  local state = require('zpack.state')
  local utils = require('zpack.utils')
  local lazy = require('zpack.lazy')

  for src, entry in pairs(state.spec_registry) do
    if entry.specs and #entry.specs > 0 then
      entry.sorted_specs = M.sort_specs(entry.specs)
      entry.merged_spec = M.merge_spec_array(entry.sorted_specs)
      entry.enabled_result = utils.check_enabled(entry.merged_spec, src)
      -- `opts` is deliberately not stored on merged_spec; compute a boolean
      -- summary once here so existence checks in plugin_loader / startup can
      -- answer "does any spec contribute opts?" without re-scanning.
      entry.has_opts = false
      for _, s in ipairs(entry.sorted_specs) do
        if s.opts ~= nil then
          entry.has_opts = true
          break
        end
      end
      -- cond_result is intentionally left nil here. It is written later by
      -- registration.register_all's vim.pack.add load callback (which needs
      -- the live plugin arg for function-form conds). Readers must treat
      -- nil as "not yet evaluated" and only act on an explicit `== false`.
      -- Do not read cond_result between resolve_all and register_all.
    end
  end

  propagate_enabled_disable(state, utils)
  prune_disabled(state)

  -- Pre-compute is_lazy_resolved and name_to_src from merged_spec alone so the
  -- public API can report a stable `lazy` flag and resolve `get_plugin(name)`
  -- for entries still mid-install (whose vim.pack.add load callback has not
  -- fired yet). The registration load callback re-computes is_lazy_resolved
  -- with the live plugin arg for accuracy with function-form triggers — both
  -- calls flow through lazy.is_lazy so the answers stay consistent.
  -- derive_name_from_src must match vim.pack.add's own derivation rule so
  -- this pre-seed agrees with the registration callback's rewrite. If they
  -- ever diverge, a stale derived-name key survives in name_to_src — harmless
  -- (bounded, non-crashing, cleared on re-setup), but worth knowing.
  for src, entry in pairs(state.spec_registry) do
    if entry.merged_spec then
      entry.is_lazy_resolved = lazy.is_lazy(entry.merged_spec, nil, src)
      local name = entry.merged_spec.name or utils.derive_name_from_src(src)
      state.name_to_src[name] = src
    end
  end
  -- Drop the pre-load lazy-parent cache so the registration callback
  -- recomputes has_lazy_parent with populated `parent_entry.plugin`.
  state.lazy_parent_cache = {}

  local vim_packs = {}
  for src, entry in pairs(state.spec_registry) do
    if not entry.merged_spec then
      utils.schedule_notify(
        ("zpack: skipping %s — no merged_spec (empty specs list?)"):format(src),
        vim.log.levels.WARN
      )
      state.spec_registry[src] = nil
    else
      assert(entry.enabled_result ~= false, ("internal: registry entry for %s survived prune_disabled with enabled_result=false"):format(src))
      local pack_spec = {
        src = src,
        version = utils.normalize_version(entry.merged_spec),
        name = entry.merged_spec.name,
      }
      table.insert(vim_packs, pack_spec)
      state.src_to_pack_spec[src] = pack_spec
    end
  end

  table.sort(vim_packs, utils.compare_priority)
  return vim_packs
end

return M
