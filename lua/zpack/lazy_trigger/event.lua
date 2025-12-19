local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.loader')

local M = {}

---@param value any
---@return boolean
local is_event_spec = function(value)
  return type(value) == "table" and value.event ~= nil
end

---@param spec Spec
---@return NormalizedEvent[]
local normalize_and_apply_fallback_pattern = function(spec)
  local result = {}
  local fallback_pattern = spec.pattern or '*'

  if not spec.event then
    return result
  end

  local event_list = (type(spec.event) == "string" or is_event_spec(spec.event))
      and { spec.event }
      or spec.event --[[@as string[]|EventSpec[] ]]

  for _, event in ipairs(event_list) do
    if type(event) == "string" then
      -- Parse "EventName pattern" format (e.g., "BufEnter *.lua")
      local event_name, pattern = event:match("^(%w+)%s+(.*)$")
      if event_name then
        table.insert(result, {
          events = { event_name },
          pattern = pattern
        })
      else
        table.insert(result, {
          events = { event },
          pattern = fallback_pattern
        })
      end
    elseif is_event_spec(event) then
      table.insert(result, {
        events = util.normalize_string_list(event.event),
        pattern = event.pattern or fallback_pattern
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
---@param spec Spec
M.setup = function(pack_spec, spec)
  local normalized_events = normalize_and_apply_fallback_pattern(spec)

  for _, normalized_event in ipairs(normalized_events) do
    local has_very_lazy, other_events = split_very_lazy(normalized_event.events)

    if has_very_lazy then
      util.autocmd("UIEnter", function()
        vim.schedule(function()
          loader.process_spec(pack_spec)
        end)
      end, { group = state.lazy_group, once = true })
    end

    if #other_events > 0 then
      util.autocmd(other_events, function()
        loader.process_spec(pack_spec)
      end, { group = state.lazy_group, once = true, pattern = normalized_event.pattern })
    end
  end
end

return M
