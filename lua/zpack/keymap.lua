local util = require('zpack.util')

local M = {}

---@param mapping string
---@param rhs string|fun()
---@param remap? boolean
---@param desc? string
---@param mode? string|string[]
---@param nowait? boolean
M.map = function(mapping, rhs, remap, desc, mode, nowait)
  if remap == nil then remap = false end
  desc = desc or ""
  mode = mode or { 'n' }
  if nowait == nil then nowait = false end
  vim.keymap.set(mode, mapping, rhs, { desc = desc, remap = remap, nowait = nowait })
end

---@param keys KeySpec|KeySpec[]|string
M.apply_keys = function(keys)
  local key_list = util.normalize_keys(keys) --[[@as KeySpec[] ]]

  for _, key in ipairs(key_list) do
    if key[2] ~= nil then
      M.map(key[1], key[2], key.remap, key.desc, key.mode, key.nowait)
    end
  end
end

return M
