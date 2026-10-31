local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.plugin_loader')
local refire = require('zpack.lazy_trigger.refire')

local M = {}

---@param value any
---@return boolean
local is_event_spec = function(value)
  return type(value) == "table" and value.event ~= nil
end

---@param spec zpack.Spec
---@param event zpack.EventValue
---@return zpack.NormalizedEvent[]
local function normalize_and_apply_fallback_pattern(spec, event)
  local result = {}
  local fallback_pattern = spec.pattern or '*'

  local event_list = (type(event) == "string" or is_event_spec(event))
      and { event }
      or event --[[@as string[]|zpack.EventSpec[] ]]

  for _, ev in ipairs(event_list) do
    if type(ev) == "string" then
      -- Parse "EventName pattern" format (e.g., "BufEnter *.lua")
      local event_name, pattern = ev:match("^(%w+)%s+(.*)$")
      if event_name then
        table.insert(result, {
          events = { event_name },
          pattern = pattern
        })
      else
        table.insert(result, {
          events = { ev },
          pattern = fallback_pattern
        })
      end
    elseif is_event_spec(ev) then
      table.insert(result, {
        events = type(ev.event) == "table" and ev.event or { ev.event },
        pattern = ev.pattern or fallback_pattern
      })
    elseif type(ev) == "table" then
      vim.list_extend(result, normalize_and_apply_fallback_pattern(spec, ev))
    end
  end

  return result
end

---@param pattern any
---@return boolean
local function is_usable_pattern(pattern)
  if type(pattern) == "table" then
    return #pattern > 0 and vim.iter(pattern):all(function(p) return type(p) == "string" end)
  end
  return type(pattern) == "string"
end

---@param name string
---@return boolean
local function is_event_name(name)
  -- exists() also answers 1 for a comma list, which an autocmd rejects.
  return name:find("^%w+$") ~= nil and vim.fn.exists("##" .. name) == 1
end

---Split the names in `event` into those an autocmd can use and the rest.
---@param event any
---@param spec? zpack.Spec Gives the fallback pattern
---@return string[] known, string[] unknown
local function classify_names(event, spec)
  local known, unknown = {}, {}
  if type(event) ~= "string" and type(event) ~= "table" then
    return known, unknown
  end
  for _, normalized in ipairs(normalize_and_apply_fallback_pattern(spec or {}, event)) do
    for _, name in ipairs(normalized.events) do
      if type(name) == "string" and name ~= "" then
        if name == "VeryLazy" or (is_event_name(name) and is_usable_pattern(normalized.pattern)) then
          known[#known + 1] = name
        else
          unknown[#unknown + 1] = name
        end
      end
    end
  end
  return known, unknown
end

---@param event any
---@param spec? zpack.Spec
---@return boolean
M.has_events = function(event, spec)
  return #classify_names(event, spec) > 0
end

---@param event any
---@param spec? zpack.Spec
---@return string[]
M.unknown_events = function(event, spec)
  local _, unknown = classify_names(event, spec)
  return unknown
end

---@param events string[]
---@return boolean, string[]
local split_very_lazy = function(events)
  local has_very_lazy = false
  local other_events = {}

  for _, event in ipairs(events) do
    if event == "VeryLazy" then
      has_very_lazy = true
    else
      table.insert(other_events, event)
    end
  end

  return has_very_lazy, other_events
end

---Schedule `cb` on the next tick (if vim has entered) or on the next
---UIEnter (latched against nvim#25526). Shared by the per-plugin VeryLazy
---load and the `User VeryLazy` emit so the latch lives in one place.
---@param cb function
local function on_ui_enter_or_now(cb)
  if vim.v.vim_did_enter == 1 then
    vim.schedule(cb)
  else
    vim.api.nvim_create_autocmd('UIEnter', {
      group = state.lazy_group,
      once = true,
      callback = util.latch_first_call(function()
        vim.schedule(cb)
      end),
    })
  end
end

---Fire `User VeryLazy` once on UIEnter (or immediately if vim has already
---entered). Matches lazy.nvim's contract so user autocmds keyed on
---`User VeryLazy` work in configs ported from lazy.nvim. Called from
---lazy.process_all AFTER per-plugin UIEnter handlers register so VeryLazy
---plugins are loaded by the time User VeryLazy fires.
M.fire_very_lazy = function()
  on_ui_enter_or_now(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy', modeline = false })
  end)
end

---@param pack_spec vim.pack.Spec
---@param spec zpack.Spec
---@param event zpack.EventValue
M.setup = function(pack_spec, spec, event)
  local normalized_events = normalize_and_apply_fallback_pattern(spec, event)
  local label = pack_spec.name or pack_spec.src

  for _, normalized_event in ipairs(normalized_events) do
    local has_very_lazy, other_events = split_very_lazy(normalized_event.events)

    if has_very_lazy then
      -- VeryLazy is synthetic (UIEnter-only); no real event to re-fire.
      -- When setup() runs after UIEnter (`:luafile`, config reload), the
      -- UIEnter autocmd would never fire — schedule the load directly so
      -- the plugin still loads before lazy.fire_very_lazy's User VeryLazy
      -- emit (which also fast-paths on vim_did_enter).
      on_ui_enter_or_now(function()
        loader.try_process_spec(pack_spec)
      end)
    end

    if #other_events > 0 then
      -- latch_first_call gates before the load_status check so a second
      -- nested fire in the same tick bails before refire.exec can double-fire
      -- user autocmds. The load_status gate handles other races (sibling
      -- event/ft already loaded, plugin/ files re-entering synchronously).
      local callback = util.latch_first_call(function(ev)
        local entry = state.spec_registry[pack_spec.src]
        if entry and entry.load_status ~= "pending" then
          return
        end
        local snap = refire.snapshot(ev.event)
        if not loader.try_process_spec(pack_spec) then
          return
        end
        refire.exec(ev, snap)
      end)
      -- One autocmd per name, so an invalid name loses only itself.
      for _, name in ipairs(other_events) do
        util.try_trigger_setup(label, 'event', function()
          util.autocmd(name, callback, { group = state.lazy_group, once = true, pattern = normalized_event.pattern })
        end)
      end
    end
  end
end

return M
