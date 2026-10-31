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

---@return boolean
local function default_lazy()
  return (state.config and state.config.defaults and state.config.defaults.lazy) == true
end

---@param value any
---@return boolean
local function has_string(value)
  if type(value) ~= 'table' then
    return type(value) == 'string' and value ~= ''
  end
  for _, item in ipairs(value) do
    if type(item) == 'string' and item ~= '' then
      return true
    end
  end
  return false
end

---`''` is a real map-mode: normal, visual and operator-pending.
---@param mode any
---@return boolean
local function has_mode(mode)
  if type(mode) ~= 'table' then
    return mode == nil or type(mode) == 'string'
  end
  for _, item in ipairs(mode) do
    if type(item) == 'string' then
      return true
    end
  end
  return false
end

---Disabled keys count, so a spec can turn off a plugin's keys and leave it lazy.
---@param keys any
---@return boolean
local function has_key(keys)
  for _, key in ipairs(utils.normalize_keys(keys)) do
    if has_string(key[1]) and has_mode(key.mode) then
      return true
    end
  end
  return false
end

---Whether a trigger could load the plugin: lazy with nothing to load it, it
---would never load. A function-form trigger is taken to be set until the plugin
---exists to call it with, so it is never called with nil where the docs promise
---a plugin.
---@param spec zpack.Spec
---@param plugin zpack.Plugin?
---@param src? string
---@return boolean
local function has_lazy_triggers(spec, plugin, src)
  if not plugin and (type(spec.event) == 'function' or type(spec.cmd) == 'function'
        or type(spec.ft) == 'function' or type(spec.keys) == 'function') then
    return true
  end
  local event = utils.try_resolve_field(spec.event, plugin, src, 'event')
  local cmd = utils.try_resolve_field(spec.cmd, plugin, src, 'cmd')
  local ft = utils.try_resolve_field(spec.ft, plugin, src, 'ft')
  local keys = utils.try_resolve_field(spec.keys, plugin, src, 'keys')

  return event_handler.has_events(event, spec) or cmd_handler.has_commands(cmd) or has_string(ft) or has_key(keys)
end

---Check if any parent of a dependency is lazy, by its own triggers or because
---it is a dependency of a lazy plugin itself. `seen` guards dependency cycles;
---only the outermost call may cache a negative answer.
---@param dep_src string
---@param seen? { [string]: true }
---@return boolean
local function has_lazy_parent(dep_src, seen)
  local cached = state.lazy_parent_cache[dep_src]
  if cached ~= nil then
    return cached
  end

  local visiting = seen or {}
  visiting[dep_src] = true
  for parent_src in pairs(state.reverse_dependency_graph[dep_src] or {}) do
    local parent_entry = state.spec_registry[parent_src]
    if parent_entry and parent_entry.merged_spec and not visiting[parent_src] then
      local parent_spec = parent_entry.merged_spec --[[@as zpack.Spec]]
      if parent_spec.lazy == true
          or (parent_spec.lazy == nil
            and (has_lazy_triggers(parent_spec, parent_entry.plugin, parent_src)
              or (is_dependency_only(parent_src) and has_lazy_parent(parent_src, visiting))))
      then
        state.lazy_parent_cache[dep_src] = true
        return true
      end
    end
  end

  if not seen then
    state.lazy_parent_cache[dep_src] = false
  end
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

  if default_lazy() then
    return true
  end

  if has_lazy_triggers(spec, plugin, src) then
    return true
  end

  if src and is_dependency_only(src) and has_lazy_parent(src) then
    return true
  end

  return false
end

---An eager plugin never reaches the triggers, which would report these.
---@param spec zpack.Spec
---@param plugin zpack.Plugin
---@param label string
M.warn_unusable_triggers = function(spec, plugin, label)
  local unknown = event_handler.unknown_events(utils.try_resolve_field(spec.event, plugin, label, 'event'), spec)
  if #unknown > 0 then
    utils.schedule_notify(
      ('zpack: %s loads at startup: no such event: %s'):format(label, table.concat(unknown, ', ')),
      vim.log.levels.WARN
    )
  end
  local invalid = cmd_handler.invalid_commands(utils.try_resolve_field(spec.cmd, plugin, label, 'cmd'))
  if #invalid > 0 then
    utils.schedule_notify(
      ('zpack: %s loads at startup: invalid command name: %s'):format(label, table.concat(invalid, ', ')),
      vim.log.levels.WARN
    )
  end
end

---@param ctx zpack.ProcessContext
M.process_all = function(ctx)
  local pending = vim.tbl_filter(function(pack_spec)
    local registry_entry = state.spec_registry[pack_spec.src]
    return registry_entry ~= nil and registry_entry.load_status ~= 'loaded'
  end, ctx.registered_lazy_packs)
  for _, pack_spec in ipairs(pending) do
    local registry_entry = state.spec_registry[pack_spec.src]
    if registry_entry and registry_entry.merged_spec then
      local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
      local plugin = registry_entry.plugin

      local label = pack_spec.name or pack_spec.src
      local event = utils.try_resolve_field(spec.event, plugin, label, 'event')
      local ft = utils.try_resolve_field(spec.ft, plugin, label, 'ft')

      utils.try_trigger_setup(label, 'event', function()
        if event then
          event_handler.setup(pack_spec, spec, event)
        end
      end)
      utils.try_trigger_setup(label, 'ft', function()
        if ft then
          ft_handler.setup(pack_spec, ft)
        end
      end)
    end
  end
  cmd_handler.setup(pending)
  keys_handler.setup(pending)
  -- Producer of the User VeryLazy emit lives next to its per-plugin VeryLazy
  -- consumer (event_handler) so the synthetic-event protocol stays in one file.
  event_handler.fire_very_lazy()
end

return M
