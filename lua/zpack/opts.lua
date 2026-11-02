if jit then jit.off(true, true) end

local utils = require('zpack.utils')

local M = {}

local EMPTY_DICT_MT = getmetatable(vim.empty_dict())

local function is_plain(v)
  if type(v) ~= "table" then
    return false
  end
  local mt = getmetatable(v)
  return mt == nil or mt == EMPTY_DICT_MT
end

---Copy the plain tables in `v`, keeping vim.empty_dict() marked as a dict;
---objects are kept by reference. `seen` maps each source table to its copy,
---so shared and cyclic references stay shared in the copy.
---@param v any
---@param seen table<table, table>
---@return any
local function copy_plain(v, seen)
  if not is_plain(v) then
    return v
  end
  if not seen[v] then
    local copy = setmetatable({}, getmetatable(v))
    seen[v] = copy
    for k, x in pairs(v) do
      copy[k] = copy_plain(x, seen)
    end
  end
  return seen[v]
end

local function has_index_keys(t)
  for k in pairs(t) do
    if type(k) == "number" then
      return true
    end
  end
  return false
end

---Set `t[path]`, shallow-copying the tables on the way so a table that
---vim.tbl_deep_extend took by reference from a spec is never written to.
---Stops without setting when an object sits on the way; the copies made
---up to there equal the originals.
local function key_set(t, path, value)
  for i = 1, #path - 1 do
    local child = t[path[i]]
    if not is_plain(child) then
      return
    end
    local copy = setmetatable({}, getmetatable(child))
    for k, x in pairs(child) do
      copy[k] = x
    end
    t[path[i]] = copy
    t = copy
  end
  t[path[#path]] = value
end

---A list contributes its entries, nil holes dropped. Any other table is
---appended as one entry, so the named keys of a which-key style
---`{ mode = 'x', { ... } }` only apply to its own entries.
---@param tables table[]
---@return any[]
local function concat(tables)
  local list = {}
  for _, t in ipairs(tables) do
    if vim.isarray(t) then
      for i = 1, table.maxn(t) do
        list[#list + 1] = t[i]
      end
    else
      list[#list + 1] = t
    end
  end
  return list
end

---vim.tbl_deep_extend's test for a table it merges into rather than replaces.
local function can_merge(v)
  return type(v) == "table" and (vim.tbl_isempty(v) or not vim.islist(v))
end

---Remove the keys `value` sets to vim.NIL wherever vim.tbl_deep_extend
---merged `value` into `base`, as lazy.nvim's merge does. `result` is that
---merge, so every table written to is one vim.tbl_deep_extend made, never
---a spec's own.
---@param result table
---@param base any
---@param value any
local function clear_nil(result, base, value)
  if not (can_merge(base) and can_merge(value)) then
    return
  end
  for k, v in pairs(value) do
    if rawequal(v, vim.NIL) then
      result[k] = nil
    else
      clear_nil(result[k], rawget(base, k), v)
    end
  end
end

---vim.tbl_deep_extend("force", base, value), then concatenate the lists at
---each `opts_extend` path (lazy.nvim's `opts_extend`). A key set to
---vim.NIL is removed where the merge reaches it. Empty tables count as
---unset, two dicts stay deep-merged, and a path with a scalar or object on
---the incoming side keeps what vim.tbl_deep_extend made of it.
---@param base table
---@param value table
---@param paths string[][]
---@return table
local function merge_opts(base, value, paths)
  local result = vim.tbl_deep_extend("force", base, value)
  clear_nil(result, base, value)
  for _, path in ipairs(paths) do
    local v = vim.tbl_get(value, unpack(path))
    if is_plain(v) then
      local b = vim.tbl_get(base, unpack(path))
      local parts = {}
      if is_plain(b) and next(b) ~= nil then
        parts[#parts + 1] = b
      end
      if next(v) ~= nil then
        parts[#parts + 1] = v
      end
      if #parts == 1 and vim.isarray(parts[1])
          or #parts == 2 and (has_index_keys(parts[1]) or has_index_keys(parts[2])) then
        key_set(result, path, concat(parts))
      end
    end
  end
  return result
end

---Resolve opts through all specs, supporting function-form opts. Throws
---if any function-form opts throws — callers must pcall.
---
---Each opts function and the caller get their own copy of the plain tables,
---so editing opts in place (or setup() doing so) cannot reach a spec's or an
---earlier function's tables and pile up across `:ZPack reload`.
---
---`opts_extend` is the merged spec's: the union over every spec, applied to
---every merge. lazy.nvim reads only the nearest `opts_extend` at or before
---each spec, so lists merged before the first declaring spec replace each
---other; the union is a deliberate divergence so the result does not depend
---on import order.
---@param specs zpack.Spec[]
---@param plugin zpack.Plugin
---@param opts_extend? string|string[]
---@return table
function M.resolve_opts(specs, plugin, opts_extend)
  local accumulated = {}
  local paths = {}
  for _, key in ipairs(opts_extend and utils.to_array(opts_extend) or {}) do
    if type(key) == "string" then
      paths[#paths + 1] = vim.split(key, ".", { plain = true })
    end
  end

  for _, spec in ipairs(specs) do
    local opts = spec.opts
    if type(opts) == "function" then
      local copy = copy_plain(accumulated, {})
      local result = opts(plugin, copy)
      accumulated = type(result) == "table" and result or copy
    elseif type(opts) == "table" then
      accumulated = merge_opts(accumulated, opts, paths)
    end
  end

  return copy_plain(accumulated, {})
end

return M
