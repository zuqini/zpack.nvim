if jit then jit.off(true, true) end

-- inspired by https://www.reddit.com/r/neovim/comments/1mx71rc/how_i_vastly_improved_my_lazy_loading_experience/
local state = require('zpack.state')
local utils = require('zpack.utils')
local keymap = require('zpack.keymap')
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

---Whether a trigger could load the plugin: lazy with nothing to load it, it
---would never load. A function-form trigger is taken to be set until the plugin
---exists to call it with, so it is never called with nil where the docs promise
---a plugin, and if it throws, since this runs before the module loader is in and
---it may be requiring the plugin's own modules. Setting up the triggers calls it
---again, which loads the plugin or reports the error.
---@param entry zpack.RegistryEntry
---@param plugin zpack.Plugin?
---@param src? string
---@return boolean
local function has_lazy_triggers(entry, plugin, src)
  local spec = entry.merged_spec --[[@as zpack.Spec]]
  if not plugin and (type(spec.event) == 'function' or type(spec.cmd) == 'function'
        or type(spec.ft) == 'function' or type(spec.keys) == 'function') then
    return true
  end
  local threw = false
  local function on_throw() threw = true end
  local event = utils.read_trigger(entry, 'event', event_handler.parse, plugin, src, on_throw)
  local cmd = utils.read_trigger(entry, 'cmd', cmd_handler.parse, plugin, src, on_throw)
  local ft = utils.read_trigger(entry, 'ft', ft_handler.parse, plugin, src, on_throw)
  local keys = utils.read_trigger(entry, 'keys', keymap.parse, plugin, src, on_throw)

  return threw or (event and event.usable) or (cmd and cmd.usable) or (ft and ft.usable) or (keys and keys.usable) or false
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
            and (has_lazy_triggers(parent_entry, parent_entry.plugin, parent_src)
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

---@param entry zpack.RegistryEntry
---@param plugin zpack.Plugin?
---@param src? string
---@return boolean
M.is_lazy = function(entry, plugin, src)
  local spec = entry.merged_spec --[[@as zpack.Spec]]
  if spec.lazy ~= nil then
    return spec.lazy
  end

  if default_lazy() then
    return true
  end

  if has_lazy_triggers(entry, plugin, src) then
    return true
  end

  if src and is_dependency_only(src) and has_lazy_parent(src) then
    return true
  end

  return false
end

---An eager plugin never reaches the triggers, which would report these. Nothing
---uses them, so one that needs the plugin's modules isn't worth an error.
---@param registry_entry zpack.RegistryEntry
---@param label string
M.warn_unusable_triggers = function(registry_entry, label)
  local plugin = registry_entry.plugin
  local function ignore() end
  local event = utils.read_trigger(registry_entry, 'event', event_handler.parse, plugin, label, ignore)
  if event and #event.unknown > 0 then
    utils.schedule_notify(
      ('zpack: %s loads at startup: no such event: %s'):format(label, table.concat(event.unknown, ', ')),
      vim.log.levels.WARN
    )
  end
  local cmd = utils.read_trigger(registry_entry, 'cmd', cmd_handler.parse, plugin, label, ignore)
  if cmd and #cmd.invalid > 0 then
    utils.schedule_notify(
      ('zpack: %s loads at startup: invalid command name: %s'):format(label, table.concat(cmd.invalid, ', ')),
      vim.log.levels.WARN
    )
  end
end

---@param ctx zpack.ProcessContext
M.setup_triggers = function(ctx)
  for _, pack_spec in ipairs(ctx.registered_lazy_packs) do
    local registry_entry = state.spec_registry[pack_spec.src]
    if registry_entry and registry_entry.merged_spec then
      local plugin = registry_entry.plugin
      local label = pack_spec.name or pack_spec.src
      local event = utils.read_trigger(registry_entry, 'event', event_handler.parse, plugin, label)
      local ft = utils.read_trigger(registry_entry, 'ft', ft_handler.parse, plugin, label)

      utils.try_trigger_setup(label, 'event', function()
        if event then
          event_handler.setup(pack_spec, event)
        end
      end)
      utils.try_trigger_setup(label, 'ft', function()
        if ft then
          ft_handler.setup(pack_spec, ft)
        end
      end)
    end
  end
  cmd_handler.setup(ctx.registered_lazy_packs)
  keys_handler.setup(ctx.registered_lazy_packs)
end

return M
