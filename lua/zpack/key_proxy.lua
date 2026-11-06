if jit then jit.off(true, true) end

local state = require('zpack.state')
local util = require('zpack.utils')
local keymap = require('zpack.keymap')

local M = {}

---The live proxy of each key, by key id.
---@type { [string]: table }
local proxy_of = {}
---The proxy keys of each lazy plugin, by source.
---@type { [string]: table[] }
local proxies_of = {}

---@param key_info table
---@return boolean
M.pending = function(key_info)
  for _, pack_spec in ipairs(key_info.pack_specs) do
    local entry = state.spec_registry[pack_spec.src]
    if entry and entry.load_status == 'pending' then
      return true
    end
  end
  return false
end

---Record a key's proxy, for the plugins it loads.
---@param key_id string
---@param key_info table
M.claim = function(key_id, key_info)
  proxy_of[key_id] = key_info
  for _, pack_spec in ipairs(key_info.pack_specs) do
    proxies_of[pack_spec.src] = proxies_of[pack_spec.src] or {}
    table.insert(proxies_of[pack_spec.src], key_info)
  end
end

---@param key_id string
M.drop = function(key_id)
  proxy_of[key_id] = nil
end

---@param key_info table
local function delete_proxy(key_info)
  local lhs, mode = key_info.key_spec[1], key_info.split_mode
  if key_info.global then
    local map = mode:sub(-1) == 'a' and vim.fn.maparg(lhs, mode:sub(1, -2), true, true)
        or vim.fn.maparg(lhs, mode, false, true)
    if map.callback == key_info.proxy and map.buffer == 0 then
      pcall(vim.keymap.del, mode, lhs)
    end
  end
  for buf in pairs(key_info.bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
        if map.callback == key_info.proxy then
          pcall(vim.keymap.del, mode, lhs, { buffer = buf })
        end
      end
    end
  end
end

---lazy.nvim's Handler.disable: drop the key proxies only `src` still waits on,
---before its scripts run, so a plugin that maps a key only when it's free gets
---it. Another pending plugin keeps its trigger, and a mapping that replaced the
---proxy stays.
---@param src string
M.release = function(src)
  for _, key_info in ipairs(proxies_of[src] or {}) do
    if not M.pending(key_info) then
      pcall(delete_proxy, key_info)
    end
  end
  proxies_of[src] = nil
end

---@param key zpack.KeySpec
---@return string[]? modes nil when no pending plugin's proxy holds any of them
local function free_modes(key)
  local modes = util.normalize_string_list(key.mode or 'n') --[[@as string[] ]]
  local free = {}
  for _, mode in ipairs(modes) do
    local key_info = proxy_of[keymap.key_id(key[1], mode, key.ft, key.buffer)]
    if not (key_info and M.pending(key_info)) then
      free[#free + 1] = mode
    end
  end
  return #free < #modes and free or nil
end

---lazy.nvim keeps one handler for a key until every plugin claiming it has
---loaded, so a plugin's keys leave out the modes a pending plugin's proxy holds.
---@param keys zpack.KeySpec[]
---@return zpack.KeySpec[]
M.unclaimed = function(keys)
  if next(proxy_of) == nil then
    return keys
  end
  local result = {}
  for _, key in ipairs(keys) do
    local ok, modes = pcall(free_modes, key)
    if not ok or not modes then
      result[#result + 1] = key
    elseif #modes > 0 then
      result[#result + 1] = vim.tbl_extend('force', {}, key, { mode = modes })
    end
  end
  return result
end

return M
