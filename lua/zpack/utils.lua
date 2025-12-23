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
  local entry = state.spec_registry[src]
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
  -- Normalize to always be an array
  local key_list = (type(keys) == "string" or (keys[1] and type(keys[1]) == "string"))
      and { keys }
      or keys --[[@as string[]|KeySpec[] ]]

  local result = {}
  for _, key in ipairs(key_list) do
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

---Create an autocmd with callback
---@param event string|string[]
---@param callback function
---@param opts? table Optional opts (group, once, pattern, buffer, etc.)
---@return number Autocmd ID
M.autocmd = function(event, callback, opts)
  opts = opts or {}
  return vim.api.nvim_create_autocmd(event, vim.tbl_extend('force', {
    callback = callback,
  }, opts))
end

---Check if spec.cond passes
---@param spec Spec
---@return boolean
M.check_cond = function(spec)
  if spec.cond == false or (type(spec.cond) == "function" and not spec.cond()) then
    return false
  end
  return true
end

return M
