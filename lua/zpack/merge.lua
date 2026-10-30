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
  opts_extend = M.LIST_EXTEND,

  cond = M.AND_LOGIC_COND,
  enabled = M.AND_LOGIC_ENABLED,
}

local internal_fields = {
  _import_order = true,
  _is_dependency = true,
  _parent_specs = true,
}

---Normalize value to array for LIST_EXTEND fields (event, cmd, ft, keys,
---opts_extend).
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
  if result.opts_extend ~= nil then
    result.opts_extend = to_array(result.opts_extend)
  end
  return result
end

local EMPTY_DICT_MT = getmetatable(vim.empty_dict())

local function is_plain(v)
  if type(v) ~= "table" then
    return false
  end
  local mt = getmetatable(v)
  return mt == nil or mt == EMPTY_DICT_MT
end

---Copy the plain tables in `v`, keeping vim.empty_dict() marked as a dict;
---objects are kept by reference. `seen` maps each source table to its copy,
---so shared and cyclic references stay shared in the copy.
---@param v any
---@param seen table<table, table>
---@return any
local function copy_plain(v, seen)
  if not is_plain(v) then
    return v
  end
  if not seen[v] then
    local copy = setmetatable({}, getmetatable(v))
    seen[v] = copy
    for k, x in pairs(v) do
      copy[k] = copy_plain(x, seen)
    end
  end
  return seen[v]
end

local function has_index_keys(t)
  for k in pairs(t) do
    if type(k) == "number" then
      return true
    end
  end
  return false
end

---Set `t[path]`, shallow-copying the tables on the way so a table that
---vim.tbl_deep_extend took by reference from a spec is never written to.
---Stops without setting when an object sits on the way; the copies made
---up to there equal the originals.
local function key_set(t, path, value)
  for i = 1, #path - 1 do
    local child = t[path[i]]
    if not is_plain(child) then
      return
    end
    local copy = setmetatable({}, getmetatable(child))
    for k, x in pairs(child) do
      copy[k] = x
    end
    t[path[i]] = copy
    t = copy
  end
  t[path[#path]] = value
end

---A list contributes its entries, nil holes dropped. Any other table is
---appended as one entry, so the named keys of a which-key style
---`{ mode = 'x', { ... } }` only apply to its own entries.
---@param tables table[]
---@return any[]
local function concat(tables)
  local list = {}
  for _, t in ipairs(tables) do
    if vim.isarray(t) then
      for i = 1, table.maxn(t) do
        list[#list + 1] = t[i]
      end
    else
      list[#list + 1] = t
    end
  end
  return list
end

---vim.tbl_deep_extend("force", base, value), then concatenate the lists at
---each `opts_extend` path (lazy.nvim's `opts_extend`). Empty tables count
---as unset, two dicts stay deep-merged, and a path with a scalar or object
---on the incoming side keeps what vim.tbl_deep_extend made of it.
---@param base table
---@param value table
---@param paths string[][]
---@return table
local function merge_opts(base, value, paths)
  local result = vim.tbl_deep_extend("force", base, value)
  for _, path in ipairs(paths) do
    local v = vim.tbl_get(value, unpack(path))
    if is_plain(v) then
      local b = vim.tbl_get(base, unpack(path))
      local parts = {}
      if is_plain(b) and next(b) ~= nil then
        parts[#parts + 1] = b
      end
      if next(v) ~= nil then
        parts[#parts + 1] = v
      end
      if #parts == 1 and vim.isarray(parts[1])
          or #parts == 2 and (has_index_keys(parts[1]) or has_index_keys(parts[2])) then
        key_set(result, path, concat(parts))
      end
    end
  end
  return result
end

---Resolve opts through all specs, supporting function-form opts. Throws
---if any function-form opts throws — callers must pcall.
---
---Each opts function and the caller get their own copy of the plain tables,
---so editing opts in place (or setup() doing so) cannot reach a spec's or an
---earlier function's tables and pile up across `:ZPack reload`.
---
---`opts_extend` is the merged spec's: the union over every spec, applied to
---every merge. lazy.nvim reads only the nearest `opts_extend` at or before
---each spec, so lists merged before the first declaring spec replace each
---other; the union is a deliberate divergence so the result does not depend
---on import order.
---@param specs zpack.Spec[]
---@param plugin zpack.Plugin
---@param opts_extend? string|string[]
---@return table
function M.resolve_opts(specs, plugin, opts_extend)
  local accumulated = {}
  local paths = {}
  for _, key in ipairs(opts_extend and to_array(opts_extend) or {}) do
    if type(key) == "string" then
      paths[#paths + 1] = vim.split(key, ".", { plain = true })
    end
  end

  for _, spec in ipairs(specs) do
    local opts = spec.opts
    if type(opts) == "function" then
      local copy = copy_plain(accumulated, {})
      local result = opts(plugin, copy)
      accumulated = type(result) == "table" and result or copy
    elseif type(opts) == "table" then
      accumulated = merge_opts(accumulated, opts, paths)
    end
  end

  return copy_plain(accumulated, {})
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

local function merge_entry(entry)
  entry.sorted_specs = M.sort_specs(entry.specs)
  entry.merged_spec = M.merge_spec_array(entry.sorted_specs)
end

---`opts` is deliberately not stored on merged_spec; this boolean lets
---plugin_loader / startup answer "does any spec contribute opts?" without
---re-scanning.
local function contributes_opts(entry)
  for _, s in ipairs(entry.sorted_specs) do
    if s.opts ~= nil then
      return true
    end
  end
  return false
end

---lazy.nvim spec parity (`optional = true`): a plugin is included only if
---referenced non-optionally somewhere. A dep declaration
---(`_is_dependency = true`) defeats `optional` — naming a plugin as a dep IS
---a non-optional reference. Without that, a table-form dep
---`{ 'foo/x', optional = true }` would prune `x` and cascade-disable its
---parent.
local function has_required_spec(entry)
  for _, s in ipairs(entry.specs) do
    if not s.optional or s._is_dependency then
      return true
    end
  end
  return false
end

---A dependency spec goes with its parents only once every spec that declared
---it is gone; one table listed under two plugins' `dependencies` stays while
---either remains.
local function declared_only_by(removed, spec)
  if not spec._parent_specs then
    return false
  end
  for parent in pairs(spec._parent_specs) do
    if not removed[parent] then
      return false
    end
  end
  return true
end

---Remove every enabled=false entry from the registry, plus what lazy.nvim
---deletes along with a plugin: the specs its specs declared under
---`dependencies` (recursively), even where they configure a plugin that
---stays, and any dep-only plugin left orphaned. A plugin left with no specs,
---or only optional ones, is removed too; one that keeps others is re-merged
---without them. After this runs, every remaining entry is guaranteed to
---reach vim.pack.add, which means the public API can rely on entry.plugin
---being populated by the load callback.
local function prune_disabled(state)
  local worklist = {}
  for src, entry in pairs(state.spec_registry) do
    if entry.enabled_result == false then
      table.insert(worklist, src)
    end
  end

  local removed = {}
  while #worklist > 0 do
    while #worklist > 0 do
      local src = table.remove(worklist)
      local entry = state.spec_registry[src]
      if entry then
        for _, spec in ipairs(entry.specs) do
          removed[spec] = true
        end
        for parent_src in pairs(state.reverse_dependency_graph[src] or {}) do
          local deps = state.dependency_graph[parent_src]
          if deps then
            deps[src] = nil
          end
        end
        state.reverse_dependency_graph[src] = nil
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

    local trimmed = {}
    local changed = true
    while changed do
      changed = false
      for src, entry in pairs(state.spec_registry) do
        local kept = {}
        for _, spec in ipairs(entry.specs) do
          if removed[spec] or declared_only_by(removed, spec) then
            removed[spec] = true
            changed = true
          else
            kept[#kept + 1] = spec
          end
        end
        if #kept < #entry.specs then
          entry.specs = kept
          trimmed[src] = entry
        end
      end
    end
    for src, entry in pairs(trimmed) do
      if #entry.specs == 0 or not has_required_spec(entry) then
        table.insert(worklist, src)
      else
        merge_entry(entry)
        entry.has_opts = contributes_opts(entry)
      end
    end
  end
end

---Move every dependency-graph edge touching old_src onto new_src, in both
---directions. Edges that would become self-loops (old ↔ new) are dropped.
local function rekey_graph_edges(state, old_src, new_src)
  local outgoing = state.dependency_graph[old_src]
  if outgoing then
    local target = state.dependency_graph[new_src] or {}
    for dep_src in pairs(outgoing) do
      local rdeps = state.reverse_dependency_graph[dep_src]
      if rdeps then
        rdeps[old_src] = nil
      end
      if dep_src ~= new_src then
        target[dep_src] = true
        if rdeps then
          rdeps[new_src] = true
        end
      elseif rdeps and next(rdeps) == nil then
        -- Dropping the old→new self-loop can empty new_src's reverse set;
        -- clear it to preserve the no-empty-sets invariant below.
        state.reverse_dependency_graph[dep_src] = nil
      end
    end
    state.dependency_graph[new_src] = target
    state.dependency_graph[old_src] = nil
  end
  local incoming = state.reverse_dependency_graph[old_src]
  if incoming then
    local target = state.reverse_dependency_graph[new_src] or {}
    for parent_src in pairs(incoming) do
      local deps = state.dependency_graph[parent_src]
      if deps then
        deps[old_src] = nil
      end
      if parent_src ~= new_src then
        target[parent_src] = true
        if deps then
          deps[new_src] = true
        end
      end
    end
    -- The reverse graph must hold no empty sets: strip_outgoing_edges reads a
    -- set emptying as its "newly orphaned" signal. The forward graph tolerates
    -- empty sets (import pre-creates them), hence no guard on the write above.
    if next(target) ~= nil then
      state.reverse_dependency_graph[new_src] = target
    end
    state.reverse_dependency_graph[old_src] = nil
  end
end

---Rank an entry for the coalesce fold as a (tier, import order) pair; compare
---tier first, then order. A `dev = true` fragment that did not fall back to
---its own `[1]` wins outright — dev outranks the whole explicit
---chain in normalize_source, independent of import order. Below that, an
---explicit-source fragment beats a bare one, and among bare entries a
---top-level fragment beats a dependency-only one — the same
---standalone-over-dep rule sort_specs applies to field merging. Within a
---tier the latest-imported wins. lazy.nvim itself is pure
---later-fragment-wins; the tiers are a deliberate divergence so the winner
---does not depend on the order lua/plugins/*.lua files are imported.
local function fold_rank(entry, src)
  local explicit, top, dep = -1, -1, -1
  for _, spec in ipairs(entry.specs) do
    local order = spec._import_order or 0
    if spec.dev == true and (type(spec[1]) ~= 'string' or src ~= util.expand_src(spec[1])) then
      return 3, order
    end
    if type(spec.src) == 'string' or type(spec.url) == 'string'
        or type(spec.dir) == 'string' then
      explicit = math.max(explicit, order)
    elseif spec._is_dependency then
      dep = math.max(dep, order)
    else
      top = math.max(top, order)
    end
  end
  if explicit >= 0 then
    return 2, explicit
  end
  if top >= 0 then
    return 1, top
  end
  return 0, dep
end

---The repos an entry names: its registry src plus the URL of every `[1]` its
---fragments carry. Two entries naming a repo in common are the user spelling
---one repo two ways (lazy.nvim's fork-override idiom, or `{ url = X }` next
---to `{ 'user/repo', url = fork }`); a fold joining entries with no repo in
---common is an inference zpack made for them, so the caller warns.
local function named_repos(entry, src)
  local repos = { [src] = true }
  for _, spec in ipairs(entry.specs) do
    if type(spec[1]) == 'string' then
      repos[util.expand_src(spec[1])] = true
    end
  end
  return repos
end

local function share_a_repo(a, b)
  for repo in pairs(a) do
    if b[repo] then
      return true
    end
  end
  return false
end

---lazy.nvim parity: plugins are keyed by derived name, so `{ 'user/repo' }`
---and `{ 'user/repo', url = fork }` — or `{ 'old-owner/repo' }` and
---`{ 'new-owner/repo' }` after a GitHub rename — are fragments of the SAME
---plugin even though they normalize to different sources. Without this fold
---they would reach vim.pack.add as separate entries deriving the same pack
---name and abort setup() with a conflicting-src error. Group entries by the
---name their merged_spec resolves to — the exact name handed to vim.pack, so
---the fold set is the conflict set and nothing more (grouping by every `[1]`
---a fragment carries over-folds: `{ 'user/repo', name = 'alias' }` would
---swallow an unrelated `other/repo`) — and fold each group into its
---highest-ranked entry (see fold_rank): losers concat their specs into the
---winner, which is re-sorted so specs[1] stays the earliest-imported fragment
---(get_import_order reads it) and re-merged. Graph edges built on the losers'
---srcs at import time are rekeyed.
local function coalesce_same_name(state, utils)
  local groups = {}
  for src, entry in pairs(state.spec_registry) do
    if entry.merged_spec then
      local name = utils.resolve_plugin_name(entry.merged_spec, src)
      groups[name] = groups[name] or {}
      table.insert(groups[name], src)
    end
  end
  for name, srcs in pairs(groups) do
    if #srcs > 1 then
      local winner = srcs[1]
      local winner_tier, winner_order = fold_rank(state.spec_registry[winner], winner)
      for i = 2, #srcs do
        local tier, order = fold_rank(state.spec_registry[srcs[i]], srcs[i])
        if tier > winner_tier or (tier == winner_tier and order > winner_order) then
          winner, winner_tier, winner_order = srcs[i], tier, order
        end
      end
      local winner_entry = state.spec_registry[winner]
      local winner_repos = named_repos(winner_entry, winner)
      for _, src in ipairs(srcs) do
        if src ~= winner then
          local loser = state.spec_registry[src]
          if not share_a_repo(winner_repos, named_repos(loser, src)) then
            utils.schedule_notify(
              ("zpack: %s: %s and %s resolve to the same plugin; merged into %s"):format(name, src, winner, winner),
              vim.log.levels.WARN
            )
          end
          vim.list_extend(winner_entry.specs, loser.specs)
          rekey_graph_edges(state, src, winner)
          state.spec_registry[src] = nil
        end
      end
      table.sort(winner_entry.specs, function(a, b)
        return (a._import_order or 0) < (b._import_order or 0)
      end)
      merge_entry(winner_entry)
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

  for _, entry in pairs(state.spec_registry) do
    if entry.specs and #entry.specs > 0 then
      merge_entry(entry)
    end
  end

  coalesce_same_name(state, utils)

  for src, entry in pairs(state.spec_registry) do
    if entry.specs and #entry.specs > 0 then
      entry.enabled_result = utils.check_enabled(entry.merged_spec, src)
      entry.has_opts = contributes_opts(entry)
      -- cond_result is intentionally left nil here. It is written later by
      -- registration.register_all's vim.pack.add load callback (which needs
      -- the live plugin arg for function-form conds). Readers must treat
      -- nil as "not yet evaluated" and only act on an explicit `== false`.
      -- Do not read cond_result between resolve_all and register_all.
    end
  end

  for src, entry in pairs(state.spec_registry) do
    if entry.specs and #entry.specs > 0 and entry.enabled_result ~= false then
      if not has_required_spec(entry) then
        entry.enabled_result = false
        utils.schedule_notify(
          ("%s skipped: declared `optional = true` and never referenced elsewhere"):format(src),
          vim.log.levels.DEBUG
        )
      end
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
  -- resolve_plugin_name here and in the pack_spec below are the same call,
  -- so this pre-seed agrees with the registration callback's rewrite (which
  -- reads pack_spec.name) by construction.
  for src, entry in pairs(state.spec_registry) do
    if entry.merged_spec then
      entry.is_lazy_resolved = lazy.is_lazy(entry.merged_spec, nil, src)
      state.name_to_src[utils.resolve_plugin_name(entry.merged_spec, src)] = src
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
        name = utils.resolve_plugin_name(entry.merged_spec, src),
      }
      table.insert(vim_packs, pack_spec)
      state.src_to_pack_spec[src] = pack_spec
    end
  end

  table.sort(vim_packs, utils.compare_priority)
  return vim_packs
end

return M
