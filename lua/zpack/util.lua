local state = require('zpack.state')

local M = {}

M.schedule_notify = function(msg, level)
  vim.schedule(function()
    vim.notify(msg, level)
  end)
end

M.dump_table = function(o)
  if type(o) == 'table' then
    local s = '{ '
    for k, v in pairs(o) do
      if type(k) ~= 'number' then k = '"' .. k .. '"' end
      s = s .. '[' .. k .. '] = ' .. M.dump_table(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end

---Get priority for a plugin source (default: 50)
---@param src string
---@return number
M.get_priority = function(src)
  local entry = state.src_spec[src]
  if not entry then
    return 50
  end
  return entry.spec.priority or 50
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

---Normalize keys to a consistent format
---@param keys KeySpec|KeySpec[]|string|string[]
---@return KeySpec[]
M.normalize_keys = function(keys)
  if type(keys) == "string" then
    return { { keys } }
  elseif keys[1] and type(keys[1]) == "string" then
    return { keys }
  end

  -- Handle mixed arrays with KeySpec tables and plain strings
  local result = {}
  for _, key in ipairs(keys) do
    if type(key) == "string" then
      table.insert(result, { key })
    else
      table.insert(result, key)
    end
  end
  return result
end

---@param val string|string[]
---@return string[]
M.normalize_string_list = function(val)
  return type(val) == "string" and { val } or val --[[@as string[] ]]
end

return M
