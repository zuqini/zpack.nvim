if jit then jit.off(true, true) end

local fields = require('zpack.merge_fields')
local fold = require('zpack.fold')
local pack = require('zpack.pack')
local state = require('zpack.state')

local M = {}

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

local EMPTY = {}

---A spec declared in a parent's `dependencies` or `specs` lives while a
---chain of parent specs still leads to the top level: one listed under two
---plugins stays while either remains, and tables listing each other go
---together once nothing above them is left.
local function is_live(graph, dead, spec, seen)
  if graph.top_specs[spec] then
    return true
  end
  for parent in pairs(graph.spec_parents[spec] or EMPTY) do
    if not dead[parent] and not (seen and seen[parent]) then
      if graph.top_specs[parent] then
        return true
      end
      seen = seen or {}
      seen[spec] = true
      if is_live(graph, dead, parent, seen) then
        return true
      end
    end
  end
  return false
end

---A table listed in several places is a dependency only if every listing
---left is one.
local function relist(graph, dead, spec)
  local is_dep = true
  for parent in pairs(graph.spec_parents[spec]) do
    if not dead[parent] and not graph.spec_children[parent][spec] then
      is_dep = false
      break
    end
  end
  spec._is_dependency = is_dep
end

---Re-merge an entry whose specs changed. It keeps the name the fold gave it
---(lazy.nvim fixes a plugin's name when a fragment is added), so dropping a
---spec that set `name` never renames an install or collides with another
---plugin.
local function refresh_entry(prune, src, entry)
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
    local name = pack.resolve_plugin_name(entry.merged_spec, src)
    fields.merge_entry(entry)
    entry.merged_spec.name = name
    fields.resolve_enabled(prune.enabled_results, entry, src)
  end
end

---Remove src's entry and every spec declared under its specs, and queue the
---entries that lose specs to be re-merged and looked at again.
local function remove_entry(graph, prune, src)
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
      for child in pairs(graph.spec_children[spec] or EMPTY) do
        if not prune.dead[child] then
          if is_live(graph, prune.dead, child) then
            relisted[#relisted + 1] = child
          else
            table.insert(stack, child)
          end
          touched[graph.spec_src[child]] = true
        end
      end
    end
  end
  for _, spec in ipairs(relisted) do
    if not graph.top_specs[spec] then
      relist(graph, prune.dead, spec)
    end
  end
  for child_src in pairs(touched) do
    if state.spec_registry[child_src] then
      prune.stale[child_src] = true
    end
  end
end

---Remove an entry nothing gave a source to. Its specs only referred to a
---plugin by name, so what they declare stays, as in lazy.nvim.
local function remove_reference(graph, prune, src)
  local removed = state.spec_registry[src]
  state.spec_registry[src] = nil
  for _, spec in ipairs(removed.specs) do
    prune.dead[spec] = true
    for child in pairs(graph.spec_children[spec] or EMPTY) do
      graph.top_specs[child] = true
    end
  end
end

---Which removals to act on now: those no other removal can undo, because what
---each rests on stays whichever of the other plugins go. When every one waits on
---another they form a cycle, which has no order-free answer: the one resting on the
---earliest spec goes, since a parent imports before the specs declared under it.
---@return { src: string, spec: zpack.Spec? }[]
local function next_removals(graph, prune, removals)
  local doomed = setmetatable({}, { __index = prune.dead })
  for _, item in ipairs(removals) do
    for _, spec in ipairs(state.spec_registry[item.src].specs) do
      doomed[spec] = true
    end
  end
  local settled, earliest = {}, nil
  for _, item in ipairs(removals) do
    local own_specs = state.spec_registry[item.src].specs
    for _, spec in ipairs(own_specs) do
      doomed[spec] = nil
    end
    if not item.spec or is_live(graph, doomed, item.spec) then
      settled[#settled + 1] = item
    elseif not earliest or (item.spec._import_order or 0) < (earliest.spec._import_order or 0) then
      earliest = item
    end
    for _, spec in ipairs(own_specs) do
      doomed[spec] = true
    end
  end
  return #settled > 0 and settled or { earliest }
end

---lazy.nvim's fix_disabled and fix_optional, to a fixed point. Each round
---re-merges what lost specs and acts on the first tier with anything in it:
---removals (see next_removals); then plugins whose specs are all `optional`, as in
---lazy.nvim; then plugins nothing gives a source to.
local function drop_unused(graph, prune)
  while true do
    for src in pairs(prune.stale) do
      if state.spec_registry[src] then
        refresh_entry(prune, src, state.spec_registry[src])
      end
    end
    prune.stale = {}

    local removals, optional, references = {}, {}, {}
    for src, entry in pairs(state.spec_registry) do
      if #entry.specs == 0 then
        removals[#removals + 1] = { src = src }
      elseif entry.enabled_result == false then
        removals[#removals + 1] = { src = src, spec = fields.deciding_spec(entry) }
      elseif not has_required_spec(entry) then
        optional[#optional + 1] = src
      elseif not fold.has_source(graph, entry) then
        references[#references + 1] = src
      end
    end

    if #removals > 0 then
      for _, item in ipairs(next_removals(graph, prune, removals)) do
        if item.spec then
          prune.disabling[item.spec] = true
        end
        remove_entry(graph, prune, item.src)
      end
    elseif #optional > 0 then
      -- Before references: one promotes what it declares to the top level, which
      -- would save a plugin an optional parent's drop takes.
      for _, src in ipairs(optional) do
        prune.notify(("%s skipped: declared `optional = true` and never referenced elsewhere"):format(src), vim.log.levels.DEBUG)
        remove_entry(graph, prune, src)
      end
    elseif #references > 0 then
      for _, src in ipairs(references) do
        prune.notify(
          ("zpack: %s skipped: a name without an owner refers to a plugin another spec defines, and none does")
            :format(pack.resolve_plugin_name(state.spec_registry[src].merged_spec, src)),
          vim.log.levels.WARN
        )
        remove_reference(graph, prune, src)
      end
    else
      return
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
local function rederive_src(graph, folded_from, entry, src)
  local groups = {}
  for _, spec in ipairs(entry.specs) do
    local spec_src = folded_from[spec] or src
    if spec_src == src then
      return
    end
    groups[spec_src] = groups[spec_src] or { specs = {} }
    table.insert(groups[spec_src].specs, spec)
  end
  local best = fold.fold_winner(graph, vim.tbl_keys(groups), groups)
  if best ~= src then
    state.spec_registry[src] = nil
    state.spec_registry[best] = entry
    for _, spec in ipairs(entry.specs) do
      graph.spec_src[spec] = best
    end
  end
end

---Remove disabled and optional-only plugins along with every spec declared
---under their `dependencies` and `specs`, even where those specs configure a
---plugin that stays, and re-merge what is left. Every remaining entry goes to
---vim.pack.add, though one whose install is declined never gets an entry.plugin.
function M.prune_disabled(graph, folded_from, enabled_results, notify)
  local prune = { dead = {}, disabling = {}, stale = {}, trimmed = {}, enabled_results = enabled_results, notify = notify }
  drop_unused(graph, prune)
  for src in pairs(prune.trimmed) do
    local entry = state.spec_registry[src]
    if entry then
      rederive_src(graph, folded_from, entry, src)
    end
  end
  return prune.dead, prune.disabling
end

return M
