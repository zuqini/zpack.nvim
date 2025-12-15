local state = require('zpack.state')

local M = {}

M.schedule_notify = function(msg, level)
  vim.schedule(function()
    vim.notify(msg, level)
  end)
end

---Get priority for a plugin source (default: 50)
---@param src string
---@return number
M.get_priority = function(src)
  local spec = state.src_spec[src]
  if not spec then
    return 50
  end
  return spec.priority or 50
end

---Comparison function for sorting items by priority (descending)
---Works with both source strings and vim.pack.Spec objects
---@param a string|vim.pack.Spec
---@param b string|vim.pack.Spec
---@return boolean
M.compare_priority = function(a, b)
  local src_a = type(a) == "string" and a or a.src
  local src_b = type(b) == "string" and b or b.src
  return M.get_priority(src_a) > M.get_priority(src_b)
end

return M
