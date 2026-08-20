---Public introspection API for zpack.
---
---This module is the supported surface for third-party tooling that needs to
---enumerate or look up plugins managed by zpack (e.g. UIs like zshow.nvim).
---Internal state in `zpack.state` and every other module under `zpack.*`
---(anything not under `zpack.api.*`) is NOT a public API and may change
---without notice; always go through this module instead.
---
---Stability: the intent is for functions and the |zpack.PluginInfo| shape
---declared here to remain stable, and |zpack.api.VERSION| will be bumped
---whenever the contract changes in a consumer-observable way. A formal
---deprecation policy is not yet in place — it will be introduced the first
---time an existing field needs to be retired, rather than promised in
---advance. Consumers can gate behavior on |zpack.api.VERSION|.

---@class zpack.api
local M = {}

---API contract version. Bumped whenever the contract changes in a
---consumer-observable way (field added, |zpack.PluginStatus| value added,
---etc.).
---@type integer
M.VERSION = 1

---@param entry zpack.RegistryEntry
---@return zpack.PluginStatus
local function derive_status(entry)
  if not entry.plugin then
    return 'installing'
  end
  -- load_status wins over cond_result: a cond=false plugin can still end up
  -- loaded if it is pulled in as a required dependency or force-loaded via
  -- `:ZPack! load`. Reporting "disabled" for an actually-loaded plugin would
  -- break UIs that key off status.
  if entry.load_status == 'loaded' or entry.load_status == 'loading' then
    return entry.load_status
  end
  if entry.cond_result == false then
    return 'disabled'
  end
  return entry.load_status or 'pending'
end

---Project a registry entry onto the public PluginInfo shape, or nil if the
---entry is not reportable. Post-setup, `merged_spec` and `is_lazy_resolved`
---are populated on every surviving entry (resolve_all prunes the rest), so
---a nil here means an internal invariant was broken — drop the entry
---silently rather than crashing a read-only getter. `entry.plugin` is set
---inside `vim.pack.add`'s load callback, which has not fired yet for
---entries mid-install; those surface as `status = "installing"` with a nil
---`path` so UIs can render "downloading" instead of having the plugin
---vanish.
---@param src string
---@param entry zpack.RegistryEntry
---@return zpack.PluginInfo?
local function entry_to_info(src, entry)
  if not entry.merged_spec then
    return nil
  end
  local plugin = entry.plugin
  local lazy_flag = entry.is_lazy_resolved == true
  if not plugin then
    local utils = require('zpack.utils')
    return {
      name = utils.resolve_plugin_name(entry.merged_spec, src),
      src = src,
      status = 'installing',
      lazy = lazy_flag,
      path = nil,
    }
  end
  return {
    name = plugin.spec.name,
    src = src,
    status = derive_status(entry),
    lazy = lazy_flag,
    path = plugin.path,
  }
end

---Return a snapshot of every plugin zpack knows about, sorted by name.
---Plugins disabled by `enabled = false` (and any dep-only plugins that become
---unreferenced as a result) are pruned during setup and will NOT appear here;
---use `enabled` for hard disables that should vanish from the registry, and
---`cond` for runtime conditions that should remain visible with
---`status = "disabled"`. zpack itself is not listed — it bootstraps via
---`vim.pack.add` outside this API, and consumers that need it can query
---`vim.pack.get` directly. Install-state queries like the checked-out git
---revision are intentionally not part of this API; use
---`vim.pack.get({ name }, { info = false })` for those. The returned table
---is freshly allocated on each call; entries must be treated as read-only.
---@return zpack.PluginInfo[]
function M.get_plugins()
  local state = require('zpack.state')

  local result = {}
  for src, entry in pairs(state.spec_registry) do
    local info = entry_to_info(src, entry)
    if info then
      table.insert(result, info)
    end
  end

  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

---Look up a single plugin by its resolved name. Returns the plugin
---registered under `name`, or nil when none is registered; never throws.
---Mid-install entries are findable — their resolved name is computed from
---the spec during setup so `get_plugin` stays symmetric with `get_plugins`
---across the installing → pending → loaded lifecycle. `vim.pack.add`
---rejects name collisions within a single `setup()`, so at most one entry
---can ever match.
---@param name string
---@return zpack.PluginInfo?
function M.get_plugin(name)
  if type(name) ~= 'string' or name == '' then
    return nil
  end
  local state = require('zpack.state')
  local src = state.name_to_src[name]
  if not src then
    return nil
  end
  local entry = state.spec_registry[src]
  if not entry then
    return nil
  end
  return entry_to_info(src, entry)
end

return M
