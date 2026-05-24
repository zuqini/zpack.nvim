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

---@param pack_spec vim.pack.Spec
---@param spec zpack.Spec
---@param event zpack.EventValue
M.setup = function(pack_spec, spec, event)
  local normalized_events = normalize_and_apply_fallback_pattern(spec, event)

  for _, normalized_event in ipairs(normalized_events) do
    local has_very_lazy, other_events = split_very_lazy(normalized_event.events)

    if has_very_lazy then
      -- VeryLazy is synthetic (UIEnter-only); no real event to re-fire.
      -- `done` guards against the same `once = true` autocmd firing twice
      -- in the same tick (https://github.com/neovim/neovim/issues/25526).
      local done = false
      util.autocmd("UIEnter", function()
        if done then
          return
        end
        done = true
        vim.schedule(function()
          loader.try_process_spec(pack_spec)
        end)
      end, { group = state.lazy_group, once = true })
    end

    if #other_events > 0 then
      local done = false
      util.autocmd(other_events, function(ev)
        -- `done` guards against nvim#25526 (same `once = true` autocmd
        -- firing twice in the same tick). Set before any further work so
        -- the second fire bails before refire.exec can double-fire user
        -- autocmds. The load_status gate below handles other races (sibling
        -- event/ft already loaded, plugin/ files re-entering synchronously).
        if done then
          return
        end
        done = true
        local entry = state.spec_registry[pack_spec.src]
        if entry and entry.load_status ~= "pending" then
          return
        end
        local snap = refire.snapshot(ev.event)
        if not loader.try_process_spec(pack_spec) then
          return
        end
        refire.exec(ev, snap)
      end, { group = state.lazy_group, once = true, pattern = normalized_event.pattern })
    end
  end
end

return M
