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
local normalize_and_apply_fallback_pattern = function(spec, event)
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
        events = util.normalize_string_list(ev.event),
        pattern = ev.pattern or fallback_pattern
      })
    end
  end

  return result
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
      util.autocmd(other_events, util.latch_first_call(function(ev)
        local entry = state.spec_registry[pack_spec.src]
        if entry and entry.load_status ~= "pending" then
          return
        end
        local snap = refire.snapshot(ev.event)
        if not loader.try_process_spec(pack_spec) then
          return
        end
        refire.exec(ev, snap)
      end), { group = state.lazy_group, once = true, pattern = normalized_event.pattern })
    end
  end
end

return M
