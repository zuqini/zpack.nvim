local util = require('zpack.utils')
local spec_state = require('zpack.state')

local M = {}

M.OVERRIDE = "override"
M.LIST_EXTEND = "list_extend"

-- `enabled` is absent too and skipped by `merge_specs`: the last spec setting it
-- decides (see deciding_spec), and only that spec's function ever runs.
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

  cond = M.OVERRIDE,
}

local internal_fields = {
  _import_order = true,
  _is_dependency = true,
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

---Identity of a list value when specs merge. Two EventSpecs are the same only
---if their events and pattern are.
---@param v any
---@return string
local function get_unique_key(v)
  return type(v) == "table" and vim.inspect(v) or tostring(v)
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

---Concatenate key lists; the later spec wins, and a key it disables stays in
---the list until util.resolve_keys so the plugin still counts as lazy (as in
---lazy.nvim, where any `keys` makes a plugin lazy).
---@param base zpack.KeySpec[]
---@param incoming zpack.KeySpec[]
---@return zpack.KeySpec[]
local function extend_keys(base, incoming)
  return util.dedupe_keys(vim.list_extend(vim.list_slice(base), incoming))
end

---@param field string
---@param values any
---@return any[]
local function field_list(field, values)
  return field == "keys" and util.normalize_keys(values) or to_array(values)
end

---Merge a LIST_EXTEND field. A function-form value receives the plugin and a
---copy of the list so far and returns a replacement, or edits the list in place
---(lazy.nvim's Plugin.values), so the merge of a function is a function too.
---The copy keeps those edits from reaching spec tables and piling up when the
---field is resolved again. `false` clears what came before it, as in lazy.nvim.
---@param field string
---@param base any
---@param incoming any
---@return any
local function merge_list_field(field, base, incoming)
  if incoming == false or base == false then
    return incoming
  end
  local extend = field == "keys" and extend_keys or extend_unique
  local function apply(value, plugin, list)
    if type(value) == "function" then
      local own = vim.deepcopy(list)
      return field_list(field, value(plugin, own) or own)
    end
    return extend(list, field_list(field, value))
  end
  if type(base) == "function" or type(incoming) == "function" then
    return function(plugin, list)
      return apply(incoming, plugin, apply(base, plugin, list or {}))
    end
  end
  return extend(field_list(field, base), field_list(field, incoming))
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
    if key ~= "opts" and key ~= "enabled" then
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
          result[key] = merge_list_field(key, base_val, incoming_val)
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

---vim.tbl_deep_extend's test for a table it merges into rather than replaces.
local function can_merge(v)
  return type(v) == "table" and (vim.tbl_isempty(v) or not vim.islist(v))
end

---Remove the keys `value` sets to vim.NIL wherever vim.tbl_deep_extend
---merged `value` into `base`, as lazy.nvim's merge does. `result` is that
---merge, so every table written to is one vim.tbl_deep_extend made, never
---a spec's own.
---@param result table
---@param base any
---@param value any
local function clear_nil(result, base, value)
  if not (can_merge(base) and can_merge(value)) then
    return
  end
  for k, v in pairs(value) do
    if rawequal(v, vim.NIL) then
      result[k] = nil
    else
      clear_nil(result[k], rawget(base, k), v)
    end
  end
end

---vim.tbl_deep_extend("force", base, value), then concatenate the lists at
---each `opts_extend` path (lazy.nvim's `opts_extend`). A key set to
---vim.NIL is removed where the merge reaches it. Empty tables count as
---unset, two dicts stay deep-merged, and a path with a scalar or object on
---the incoming side keeps what vim.tbl_deep_extend made of it.
---@param base table
---@param value table
---@param paths string[][]
---@return table
local function merge_opts(base, value, paths)
  local result = vim.tbl_deep_extend("force", base, value)
  clear_nil(result, base, value)
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
---some spec for it, dependency or not, is non-optional. Skipping an optional
---plugin does not disable the plugins depending on it.
local function has_required_spec(entry)
  for _, s in ipairs(entry.specs) do
    if not s.optional then
      return true
    end
  end
  return false
end

---Whether some spec names a repo, rather than only referring to the plugin by
---name (see state.source_kinds).
local function has_source(entry)
  for _, s in ipairs(entry.specs) do
    if spec_state.source_kinds[s] ~= 'reference' then
      return true
    end
  end
  return false
end

---Rank an entry for the coalesce fold as a (tier, import order) pair; compare
---tier first, then order. A `dev = true` fragment that did not fall back to
---its own `[1]` wins outright — dev outranks the whole explicit
---chain in normalize_source, independent of import order. Below that, an
---explicit-source fragment beats a bare one, and among bare entries a
---top-level fragment beats a dependency-only one — the same
---standalone-over-dep rule sort_specs applies to field merging. A name
---reference names no repo, so it ranks below all of them. Within a
---tier the latest-imported wins. lazy.nvim itself is pure
---later-fragment-wins; the tiers are a deliberate divergence so the winner
---does not depend on the order lua/plugins/*.lua files are imported.
local function fold_rank(entry)
  local explicit, top, dep, reference = -1, -1, -1, -1
  for _, spec in ipairs(entry.specs) do
    local order = spec._import_order or 0
    local kind = spec_state.source_kinds[spec]
    if kind == 'dev' then
      return 3, order
    end
    if kind == 'explicit' then
      explicit = math.max(explicit, order)
    elseif kind == 'reference' then
      reference = math.max(reference, order)
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
  if dep >= 0 then
    return 0, dep
  end
  return -1, reference
end

---The highest-ranked of `srcs`, whose entries are `entries[src]`.
local function fold_winner(srcs, entries)
  local winner, winner_tier, winner_order
  for _, src in ipairs(srcs) do
    local tier, order = fold_rank(entries[src])
    if not winner or tier > winner_tier or (tier == winner_tier and order > winner_order) then
      winner, winner_tier, winner_order = src, tier, order
    end
  end
  return winner
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

local EMPTY = {}

---A spec declared in a parent's `dependencies` or `specs` lives while a
---chain of parent specs still leads to the top level: one listed under two
---plugins stays while either remains, and tables listing each other go
---together once nothing above them is left.
local function is_live(state, dead, spec, seen)
  if state.top_specs[spec] then
    return true
  end
  for parent in pairs(state.spec_parents[spec] or EMPTY) do
    if not dead[parent] and not (seen and seen[parent]) then
      if state.top_specs[parent] then
        return true
      end
      seen = seen or {}
      seen[spec] = true
      if is_live(state, dead, parent, seen) then
        return true
      end
    end
  end
  return false
end

---A table listed in several places is a dependency only if every listing
---left is one.
local function relist(state, dead, spec)
  local is_dep = true
  for parent in pairs(state.spec_parents[spec]) do
    if not dead[parent] and not state.spec_children[parent][spec] then
      is_dep = false
      break
    end
  end
  spec._is_dependency = is_dep
end

---lazy.nvim parity: the last spec to set `enabled`, in merge order, decides, so
---a later `enabled = true` undoes an earlier `enabled = false`.
local function deciding_spec(entry)
  for i = #entry.sorted_specs, 1, -1 do
    if entry.sorted_specs[i].enabled ~= nil then
      return entry.sorted_specs[i]
    end
  end
end

local function resolve_enabled(utils, entry, src)
  local spec = deciding_spec(entry)
  entry.enabled_result = spec == nil or utils.spec_enabled(spec, src)
end

---Re-merge an entry whose specs changed. It keeps the name the fold gave it
---(lazy.nvim fixes a plugin's name when a fragment is added), so dropping a
---spec that set `name` never renames an install or collides with another
---plugin.
local function refresh_entry(utils, prune, src, entry)
  prune.stale[src] = nil
  local kept = {}
  for _, spec in ipairs(entry.specs) do
    if not prune.dead[spec] then
      kept[#kept + 1] = spec
    end
  end
  if #kept < #entry.specs then
    prune.trimmed[src] = true
  end
  entry.specs = kept
  if #kept > 0 then
    local name = utils.resolve_plugin_name(entry.merged_spec, src)
    merge_entry(entry)
    entry.merged_spec.name = name
    resolve_enabled(utils, entry, src)
    entry.has_opts = contributes_opts(entry)
  end
end

---Remove src's entry and every spec declared under its specs, and queue the
---entries that lose specs to be re-merged and looked at again.
local function remove_entry(state, prune, src)
  local removed = state.spec_registry[src]
  state.spec_registry[src] = nil
  local stack, relisted, touched = {}, {}, {}
  for i, spec in ipairs(removed.specs) do
    stack[i] = spec
  end
  while #stack > 0 do
    local spec = table.remove(stack)
    if not prune.dead[spec] then
      prune.dead[spec] = true
      for child in pairs(state.spec_children[spec] or EMPTY) do
        if not prune.dead[child] then
          if is_live(state, prune.dead, child) then
            relisted[#relisted + 1] = child
          else
            table.insert(stack, child)
          end
          touched[state.spec_src[child]] = true
        end
      end
    end
  end
  for _, spec in ipairs(relisted) do
    if not state.top_specs[spec] then
      relist(state, prune.dead, spec)
    end
  end
  for child_src in pairs(touched) do
    if state.spec_registry[child_src] then
      prune.stale[child_src] = true
      prune.dirty[child_src] = true
    end
  end
end

---Why an entry has to go, if it does, and every spec that reason rests on:
---it has no specs left or it is disabled.
local function removal_reason(entry)
  if #entry.specs == 0 then
    return 'empty', {}
  end
  if entry.enabled_result == false then
    local spec = deciding_spec(entry)
    -- `optional = true, enabled = false` means "turn this off if it's used", as
    -- when one snippet engine replaces another, so dependents get no warning.
    return spec.optional and 'optional_disabled' or 'disabled', { spec }
  end
end

---The import order of the earliest spec a removal rests on, or nil when one
---of them is top-level: those are never dropped, so the removal is settled.
local function removal_order(state, specs)
  local order = math.huge
  for _, spec in ipairs(specs) do
    if state.top_specs[spec] then
      return nil
    end
    order = math.min(order, spec._import_order or 0)
  end
  return #specs > 0 and order or nil
end

---Remove an entry nothing gave a source to. Its specs only referred to a
---plugin by name, so what they declare stays, as in lazy.nvim.
local function remove_reference(state, prune, src)
  local removed = state.spec_registry[src]
  state.spec_registry[src] = nil
  for _, spec in ipairs(removed.specs) do
    prune.dead[spec] = true
    for child in pairs(state.spec_children[spec] or EMPTY) do
      state.top_specs[child] = true
    end
  end
end

local function drop(state, utils, prune, src, reason, specs)
  if reason == 'disabled' or reason == 'optional_disabled' then
    prune.disabling[specs[1]] = true
  end
  if reason == 'disabled' then
    prune.disabled[src] = specs[1]
  elseif reason == 'optional' or reason == 'optional_disabled' then
    utils.schedule_notify(
      (reason == 'optional' and "%s skipped: declared `optional = true` and never referenced elsewhere"
        or "%s skipped: disabled by a spec with `optional = true`"):format(src),
      vim.log.levels.DEBUG
    )
  elseif reason == 'no_source' then
    utils.schedule_notify(
      ("zpack: %s skipped: a name without an owner refers to a plugin another spec defines, and none does")
        :format(utils.resolve_plugin_name(state.spec_registry[src].merged_spec, src)),
      vim.log.levels.WARN
    )
    remove_reference(state, prune, src)
    return
  end
  remove_entry(state, prune, src)
end

---lazy.nvim's fix_disabled and fix_optional. Settled removals go first,
---then the others one at a time by the import order of the specs they rest
---on, since a parent imports before the specs declared under it and may take
---them away. Plugins whose specs are all `optional` go together once nothing
---else is left, as in lazy.nvim, and so do plugins nothing gives a source to.
local function drop_unused(state, utils, prune)
  while next(prune.dirty) do
    local batch = prune.dirty
    prune.dirty = {}
    local optional, nested = {}, {}
    for src in pairs(batch) do
      local entry = state.spec_registry[src]
      if entry and prune.stale[src] then
        refresh_entry(utils, prune, src, entry)
      end
      if entry then
        local reason, specs = removal_reason(entry)
        local order = reason and removal_order(state, specs)
        if reason and not order then
          drop(state, utils, prune, src, reason, specs)
        elseif reason then
          nested[#nested + 1] = { src = src, reason = reason, specs = specs, order = order }
        elseif not (has_required_spec(entry) and has_source(entry)) then
          optional[#optional + 1] = src
        end
      end
    end
    if next(prune.dirty) then
      for _, src in ipairs(optional) do
        prune.dirty[src] = true
      end
      for _, item in ipairs(nested) do
        prune.dirty[item.src] = true
      end
    elseif #nested > 0 then
      table.sort(nested, function(a, b)
        return a.order < b.order
      end)
      drop(state, utils, prune, nested[1].src, nested[1].reason, nested[1].specs)
      for i = 2, #nested do
        prune.dirty[nested[i].src] = true
      end
      for _, src in ipairs(optional) do
        prune.dirty[src] = true
      end
    else
      -- Optional drops first: a reference promotes what it declares to the top
      -- level, which would save a plugin an optional parent's drop takes.
      local references = {}
      for _, src in ipairs(optional) do
        if has_required_spec(state.spec_registry[src]) then
          references[#references + 1] = src
        else
          drop(state, utils, prune, src, 'optional')
        end
      end
      for _, src in ipairs(references) do
        if #references < #optional then
          prune.dirty[src] = true
        else
          drop(state, utils, prune, src, 'no_source')
        end
      end
    end
  end
end

---Keep the source the fold picked while a spec giving it remains; otherwise
---re-run the fold's choice over the specs left, as lazy.nvim re-derives a
---plugin's url from its remaining fragments, so a fork `url` declared only
---under a removed plugin no longer decides where the plugin installs from.
---`folded_from` maps each spec the fold moved to the src it came from; the
---new src is free in the registry, since the fold moved every spec with that
---source into this entry.
local function rederive_src(state, folded_from, entry, src)
  local groups = {}
  for _, spec in ipairs(entry.specs) do
    local spec_src = folded_from[spec] or src
    if spec_src == src then
      return
    end
    groups[spec_src] = groups[spec_src] or { specs = {} }
    table.insert(groups[spec_src].specs, spec)
  end
  local best = fold_winner(vim.tbl_keys(groups), groups)
  if best ~= src then
    state.spec_registry[src] = nil
    state.spec_registry[best] = entry
    for _, spec in ipairs(entry.specs) do
      state.spec_src[spec] = best
    end
  end
end

---Whether any of an entry's specs lists `listed` under `dependencies`.
local function lists_spec(state, entry, listed)
  for _, spec in ipairs(entry.specs) do
    if (state.spec_children[spec] or EMPTY)[listed] then
      return true
    end
  end
  return false
end

---lazy.nvim keeps a plugin whose dependency is disabled, silently. Turning off a
---distro's plugin is routine, so this is only a debug note, for a dependency
---something else turned off; a plugin writing
---`dependencies = { { 'x', enabled = cond } }` chose that itself.
local function note_disabled_dependencies(state, utils, prune)
  local messages = {}
  for src, entry in pairs(state.spec_registry) do
    for _, spec in ipairs(entry.specs) do
      for child, is_dep in pairs(state.spec_children[spec] or EMPTY) do
        local dep_src = state.spec_src[child]
        local disabling = is_dep and not prune.dead[spec] and prune.disabled[dep_src]
        if disabling and not lists_spec(state, entry, disabling) then
          messages[("%s may not work: its dependency %s has enabled=false"):format(src, dep_src)] = true
        end
      end
    end
  end
  local sorted = vim.tbl_keys(messages)
  table.sort(sorted)
  for _, message in ipairs(sorted) do
    utils.schedule_notify(message, vim.log.levels.DEBUG)
  end
end

---Remove disabled and optional-only plugins along with every spec declared
---under their `dependencies` and `specs`, even where those specs configure a
---plugin that stays, and re-merge what is left. After this runs, every
---remaining entry is guaranteed to reach vim.pack.add, which means the
---public API can rely on entry.plugin being populated by the load callback.
local function prune_disabled(state, utils, folded_from)
  local prune = { dead = {}, disabled = {}, disabling = {}, dirty = {}, stale = {}, trimmed = {} }
  for src, entry in pairs(state.spec_registry) do
    if entry.enabled_result == false or not (has_required_spec(entry) and has_source(entry)) then
      prune.dirty[src] = true
    end
  end
  drop_unused(state, utils, prune)
  note_disabled_dependencies(state, utils, prune)
  for src in pairs(prune.trimmed) do
    local entry = state.spec_registry[src]
    if entry then
      rederive_src(state, folded_from, entry, src)
    end
  end
  return prune.dead, prune.disabling
end

---Edges run from each plugin to the plugins its remaining specs list under
---`dependencies`.
local function build_dependency_graph(state, dead)
  for parent, children in pairs(state.spec_children) do
    local src = state.spec_src[parent]
    if not dead[parent] and state.spec_registry[src] then
      for child, is_dep in pairs(children) do
        local dep_src = state.spec_src[child]
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
---(get_import_order reads it) and re-merged. Returns the src each moved spec
---came from, and the folds to warn about once pruning has run.
local function coalesce_same_name(state)
  local folded_from, warnings = {}, {}
  local groups = {}
  for src, entry in pairs(state.spec_registry) do
    local name = util.resolve_plugin_name(entry.merged_spec, src)
    groups[name] = groups[name] or {}
    table.insert(groups[name], src)
  end
  for name, srcs in pairs(groups) do
    if #srcs > 1 then
      local winner = fold_winner(srcs, state.spec_registry)
      local winner_entry = state.spec_registry[winner]
      local winner_repos = named_repos(winner_entry, winner)
      local winner_specs = vim.list_slice(winner_entry.specs)
      for _, src in ipairs(srcs) do
        if src ~= winner then
          local loser = state.spec_registry[src]
          if has_source(loser) and not share_a_repo(winner_repos, named_repos(loser, src)) then
            warnings[#warnings + 1] = {
              msg = ("zpack: %s: %s and %s resolve to the same plugin; merged into %s"):format(name, src, winner, winner),
              loser_specs = loser.specs,
              winner_specs = winner_specs,
            }
          end
          for _, spec in ipairs(loser.specs) do
            folded_from[spec] = src
            state.spec_src[spec] = winner
            table.insert(winner_entry.specs, spec)
          end
          state.spec_registry[src] = nil
        end
      end
      table.sort(winner_entry.specs, function(a, b)
        return (a._import_order or 0) < (b._import_order or 0)
      end)
      merge_entry(winner_entry)
    end
  end
  return folded_from, warnings
end

local function any_live(specs, dead)
  for _, spec in ipairs(specs) do
    if not dead[spec] then
      return true
    end
  end
  return false
end

local function any_in(specs, set)
  for _, spec in ipairs(specs) do
    if set[spec] then
      return true
    end
  end
  return false
end

---A fold is worth a warning if both sides stay, or if it explains why a plugin
---is gone: `enabled = false` on one side disabled the other. Specs dropped for
---any other reason no longer say anything about the plugin.
local function warn_folds(utils, warnings, dead, disabling)
  for _, warning in ipairs(warnings) do
    local loser_live, winner_live = any_live(warning.loser_specs, dead), any_live(warning.winner_specs, dead)
    if (loser_live and winner_live) or (not loser_live and not winner_live
          and (any_in(warning.loser_specs, disabling) or any_in(warning.winner_specs, disabling))) then
      utils.schedule_notify(warning.msg, vim.log.levels.WARN)
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
    merge_entry(entry)
  end

  local folded_from, fold_warnings = coalesce_same_name(state)

  for src, entry in pairs(state.spec_registry) do
    resolve_enabled(utils, entry, src)
    entry.has_opts = contributes_opts(entry)
    -- cond_result is intentionally left nil here. It is written later by
    -- registration.register_all's vim.pack.add load callback (which needs
    -- the live plugin arg for function-form conds). Readers must treat
    -- nil as "not yet evaluated" and only act on an explicit `== false`.
    -- Do not read cond_result between resolve_all and register_all.
  end

  local dead, disabling = prune_disabled(state, utils, folded_from)
  warn_folds(utils, fold_warnings, dead, disabling)
  build_dependency_graph(state, dead)
  state.top_specs, state.spec_parents, state.spec_children, state.spec_src = {}, {}, {}, {}
  state.source_kinds, state.enabled_results, state.validated_specs = {}, {}, {}

  -- Pre-compute is_lazy_resolved and name_to_src from merged_spec alone so the
  -- public API can report a stable `lazy` flag and resolve `get_plugin(name)`
  -- for entries still mid-install (whose vim.pack.add load callback has not
  -- fired yet). Registration re-computes is_lazy_resolved
  -- with the live plugin arg for accuracy with function-form triggers — both
  -- calls flow through lazy.is_lazy so the answers stay consistent.
  -- resolve_plugin_name here and in the pack_spec below are the same call,
  -- so this pre-seed agrees with the registration callback's rewrite (which
  -- reads pack_spec.name) by construction.
  for src, entry in pairs(state.spec_registry) do
    entry.is_lazy_resolved = lazy.is_lazy(entry.merged_spec, nil, src)
    state.name_to_src[utils.resolve_plugin_name(entry.merged_spec, src)] = src
  end
  -- Drop the pre-load lazy-parent cache so the registration callback
  -- recomputes has_lazy_parent with populated `parent_entry.plugin`.
  state.lazy_parent_cache = {}

  local vim_packs = {}
  for src, entry in pairs(state.spec_registry) do
    assert(entry.enabled_result ~= false, ("internal: registry entry for %s survived prune_disabled with enabled_result=false"):format(src))
    local version, is_soft = utils.normalize_version(entry.merged_spec)
    state.soft_versions[src] = is_soft or nil
    local pack_spec = {
      src = src,
      version = version,
      name = utils.resolve_plugin_name(entry.merged_spec, src),
    }
    table.insert(vim_packs, pack_spec)
    state.src_to_pack_spec[src] = pack_spec
  end

  table.sort(vim_packs, utils.compare_priority)
  return vim_packs
end

return M
