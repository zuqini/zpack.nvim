-- inspired by https://www.reddit.com/r/neovim/comments/1mx71rc/how_i_vastly_improved_my_lazy_loading_experience/
local state = require('zpack.state')
local utils = require('zpack.utils')
local event_handler = require('zpack.lazy_trigger.event')
local ft_handler = require('zpack.lazy_trigger.ft')
local cmd_handler = require('zpack.lazy_trigger.cmd')
local keys_handler = require('zpack.lazy_trigger.keys')

local M = {}

---Check if a plugin is only defined as a dependency (no standalone specs)
---@param src string
---@return boolean
local function is_dependency_only(src)
  local registry_entry = state.spec_registry[src]
  if not registry_entry then
    return false
  end
  for _, spec in ipairs(registry_entry.specs) do
    if not spec._is_dependency then
      return false
    end
  end
  return true
end

---Check if any parent of a dependency is lazy (cached)
---@param dep_src string
---@return boolean
local function has_lazy_parent(dep_src)
  local cached = state.lazy_parent_cache[dep_src]
  if cached ~= nil then
    return cached
  end

  local parents = state.reverse_dependency_graph[dep_src]
  if not parents then
    state.lazy_parent_cache[dep_src] = false
    return false
  end

  for parent_src in pairs(parents) do
    local parent_entry = state.spec_registry[parent_src]
    if parent_entry and parent_entry.merged_spec then
      local parent_spec = parent_entry.merged_spec --[[@as zpack.Spec]]
      if parent_spec.lazy == true then
        state.lazy_parent_cache[dep_src] = true
        return true
      end
      if parent_spec.lazy == nil then
        local event = utils.try_resolve_field(parent_spec.event, parent_entry.plugin, parent_src, 'event')
        local cmd = utils.try_resolve_field(parent_spec.cmd, parent_entry.plugin, parent_src, 'cmd')
        local ft = utils.try_resolve_field(parent_spec.ft, parent_entry.plugin, parent_src, 'ft')
        local keys = utils.try_resolve_field(parent_spec.keys, parent_entry.plugin, parent_src, 'keys')
        if event or cmd or ft or (keys and #keys > 0) then
          state.lazy_parent_cache[dep_src] = true
          return true
        end
      end
    end
  end

  state.lazy_parent_cache[dep_src] = false
  return false
end

---@param spec zpack.Spec
---@param plugin zpack.Plugin?
---@param src? string
---@return boolean
M.is_lazy = function(spec, plugin, src)
  if spec.lazy ~= nil then
    return spec.lazy
  end

  local event = utils.try_resolve_field(spec.event, plugin, src, 'event')
  local cmd = utils.try_resolve_field(spec.cmd, plugin, src, 'cmd')
  local ft = utils.try_resolve_field(spec.ft, plugin, src, 'ft')
  local keys = utils.try_resolve_field(spec.keys, plugin, src, 'keys')

  if event or cmd or ft or (keys and #keys > 0) then
    return true
  end

  if src and is_dependency_only(src) and has_lazy_parent(src) then
    return true
  end

  return false
end

---@param ctx zpack.ProcessContext
M.process_all = function(ctx)
  if next(state.src_with_pending_build) ~= nil then
    return
  end

  for _, pack_spec in ipairs(ctx.registered_lazy_packs) do
    local registry_entry = state.spec_registry[pack_spec.src]
    if registry_entry and registry_entry.merged_spec then
      local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
      local plugin = registry_entry.plugin

      local label = pack_spec.name or pack_spec.src
      local event = utils.try_resolve_field(spec.event, plugin, label, 'event')
      local ft = utils.try_resolve_field(spec.ft, plugin, label, 'ft')

      if event then
        event_handler.setup(pack_spec, spec, event)
      end
      if ft then
        ft_handler.setup(pack_spec, ft)
      end
    end
  end
  cmd_handler.setup(ctx.registered_lazy_packs)
  keys_handler.setup(ctx.registered_lazy_packs)
  -- Producer of the User VeryLazy emit lives next to its per-plugin VeryLazy
  -- consumer (event_handler) so the synthetic-event protocol stays in one file.
  event_handler.fire_very_lazy()
end

return M
