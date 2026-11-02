if jit then jit.off(true, true) end

local fields = require('zpack.merge_fields')
local pack = require('zpack.pack')
local state = require('zpack.state')

local M = {}

---Whether some spec names a repo, rather than only referring to the plugin by
---name (see zpack.SpecGraph).
function M.has_source(graph, entry)
  for _, s in ipairs(entry.specs) do
    if graph.source_kinds[s] ~= 'reference' then
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
local function fold_rank(graph, entry)
  local explicit, top, dep, reference = -1, -1, -1, -1
  for _, spec in ipairs(entry.specs) do
    local order = spec._import_order or 0
    local kind = graph.source_kinds[spec]
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
function M.fold_winner(graph, srcs, entries)
  local winner, winner_tier, winner_order
  for _, src in ipairs(srcs) do
    local tier, order = fold_rank(graph, entries[src])
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
      repos[pack.expand_src(spec[1])] = true
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
---(get_import_order reads it) and re-merged. Returns the src each moved spec
---came from, and the folds to warn about once pruning has run.
function M.coalesce_same_name(graph)
  local folded_from, warnings = {}, {}
  local groups = {}
  for src, entry in pairs(state.spec_registry) do
    local name = pack.resolve_plugin_name(entry.merged_spec, src)
    groups[name] = groups[name] or {}
    table.insert(groups[name], src)
  end
  for name, srcs in pairs(groups) do
    if #srcs > 1 then
      local winner = M.fold_winner(graph, srcs, state.spec_registry)
      local winner_entry = state.spec_registry[winner]
      local winner_repos = named_repos(winner_entry, winner)
      local winner_specs = vim.list_slice(winner_entry.specs)
      for _, src in ipairs(srcs) do
        if src ~= winner then
          local loser = state.spec_registry[src]
          if M.has_source(graph, loser) and not share_a_repo(winner_repos, named_repos(loser, src)) then
            warnings[#warnings + 1] = {
              msg = ("zpack: %s: %s and %s resolve to the same plugin; merged into %s"):format(name, src, winner, winner),
              loser_specs = loser.specs,
              winner_specs = winner_specs,
            }
          end
          for _, spec in ipairs(loser.specs) do
            folded_from[spec] = src
            graph.spec_src[spec] = winner
            table.insert(winner_entry.specs, spec)
          end
          state.spec_registry[src] = nil
        end
      end
      table.sort(winner_entry.specs, function(a, b)
        return (a._import_order or 0) < (b._import_order or 0)
      end)
      fields.merge_entry(winner_entry)
    end
  end
  return folded_from, warnings
end

---@param specs zpack.Spec[]
---@param set { [zpack.Spec]: true }
---@param member boolean Look for a spec in the set, or one outside it
local function any_spec(specs, set, member)
  for _, spec in ipairs(specs) do
    if (set[spec] == true) == member then
      return true
    end
  end
  return false
end

---A fold is worth a warning if both sides stay, or if it explains why a plugin
---is gone: `enabled = false` on one side disabled the other. Specs dropped for
---any other reason no longer say anything about the plugin.
function M.warn_folds(warnings, dead, disabling, notify)
  for _, warning in ipairs(warnings) do
    local loser_live, winner_live = any_spec(warning.loser_specs, dead, false), any_spec(warning.winner_specs, dead, false)
    if (loser_live and winner_live) or (not loser_live and not winner_live
          and (any_spec(warning.loser_specs, disabling, true) or any_spec(warning.winner_specs, disabling, true))) then
      notify(warning.msg, vim.log.levels.WARN)
    end
  end
end

return M
