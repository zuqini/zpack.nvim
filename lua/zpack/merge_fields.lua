if jit then jit.off(true, true) end

local keymap = require('zpack.keymap')
local utils = require('zpack.utils')

local M = {}

local LIST_FIELDS = { event = true, cmd = true, ft = true, keys = true, opts_extend = true }

---Identity of a list value when specs merge. Two EventSpecs are the same only
---if their events and pattern are.
---@param v any
---@return string
local function get_unique_key(v)
  return type(v) == "table" and vim.inspect(v) or tostring(v)
end

---Extend list with unique values
---@param base any[]
---@param incoming any[]
---@return any[]
local function extend_unique(base, incoming)
  local seen = {}
  local result = {}

  for _, v in ipairs(base) do
    local key = get_unique_key(v)
    if not seen[key] then
      seen[key] = true
      table.insert(result, v)
    end
  end

  for _, v in ipairs(incoming) do
    local key = get_unique_key(v)
    if not seen[key] then
      seen[key] = true
      table.insert(result, v)
    end
  end

  return result
end

---Concatenate key lists; the later spec wins, and a key it disables stays in
---the list until keymap.parse so the plugin still counts as lazy (as in
---lazy.nvim, where any `keys` makes a plugin lazy).
---@param base zpack.KeySpec[]
---@param incoming zpack.KeySpec[]
---@return zpack.KeySpec[]
local function extend_keys(base, incoming)
  return keymap.dedupe_keys(vim.list_extend(vim.list_slice(base), incoming))
end

---@param field string
---@param values any
---@return any[]
local function field_list(field, values)
  return field == "keys" and keymap.normalize_keys(values) or utils.to_array(values)
end

---Merge one of LIST_FIELDS. A function-form value receives the plugin and a
---copy of the list so far and returns a replacement, or edits the list in place
---(lazy.nvim's Plugin.values), so the merge of a function is a function too.
---The copy keeps those edits from reaching spec tables and piling up when the
---field is resolved again. `false` clears what came before it, as in lazy.nvim.
---@param field string
---@param base any
---@param incoming any
---@return any
local function merge_list_field(field, base, incoming)
  if incoming == false or base == false then
    return incoming
  end
  local extend = field == "keys" and extend_keys or extend_unique
  local function apply(value, plugin, list)
    if type(value) == "function" then
      local own = vim.deepcopy(list)
      return field_list(field, value(plugin, own) or own)
    end
    return extend(list, field_list(field, value))
  end
  if type(base) == "function" or type(incoming) == "function" then
    return function(plugin, list)
      return apply(incoming, plugin, apply(base, plugin, list or {}))
    end
  end
  return extend(field_list(field, base), field_list(field, incoming))
end

---Merge two specs: the later value wins, except that LIST_FIELDS extend.
---`enabled` is skipped: the last spec setting it decides (see deciding_spec), and
---only that spec's function ever runs. `opts` is skipped too: it is resolved
---lazily at load time by opts.resolve_opts, so that function-form opts (which
---receive the accumulated opts and may return a replacement) are handled with a
---single authoritative code path. Callers that need to know "does any spec
---contribute opts?" read `entry.has_opts`.
---@param base zpack.Spec
---@param incoming zpack.Spec
---@return zpack.Spec
function M.merge_specs(base, incoming)
  local result = {}

  local all_keys = {}
  for k in pairs(base) do all_keys[k] = true end
  for k in pairs(incoming) do all_keys[k] = true end

  for key in pairs(all_keys) do
    if key ~= "opts" and key ~= "enabled" then
      local base_val = base[key]
      local incoming_val = incoming[key]

      if incoming_val == nil then
        result[key] = base_val
      elseif base_val ~= nil and LIST_FIELDS[key] then
        result[key] = merge_list_field(key, base_val, incoming_val)
      else
        result[key] = incoming_val
      end
    end
  end

  return result
end

---Sort specs: dependencies first, then standalone (so standalone wins on conflict)
---@param specs zpack.Spec[]
---@return zpack.Spec[]
function M.sort_specs(specs)
  if not specs or #specs == 0 then
    return {}
  end
  local sorted = vim.list_slice(specs)
  table.sort(sorted, function(a, b)
    local a_dep = a._is_dependency and 1 or 0
    local b_dep = b._is_dependency and 1 or 0
    if a_dep ~= b_dep then
      return a_dep > b_dep
    end
    return (a._import_order or 0) < (b._import_order or 0)
  end)
  return sorted
end

---Merge an array of specs in order (lowest priority first).
---Always returns a fresh table (never a reference to any input spec), and
---`opts` is always absent from the result — it is resolved at load time via
---opts.resolve_opts so function-form opts are handled consistently.
---@param specs zpack.Spec[]
---@return zpack.Spec
function M.merge_spec_array(specs)
  local result = {}
  for i = 1, #specs do
    result = M.merge_specs(result, specs[i])
  end
  if result.opts_extend ~= nil then
    result.opts_extend = utils.to_array(result.opts_extend)
  end
  return result
end

function M.merge_entry(entry)
  entry.sorted_specs = M.sort_specs(entry.specs)
  entry.merged_spec = M.merge_spec_array(entry.sorted_specs)
end

---`opts` is deliberately not stored on merged_spec; this boolean lets
---plugin_loader / startup answer "does any spec contribute opts?" without
---re-scanning.
function M.contributes_opts(entry)
  for _, s in ipairs(entry.sorted_specs) do
    if s.opts ~= nil then
      return true
    end
  end
  return false
end

---lazy.nvim parity: the last spec to set `enabled`, in merge order, decides, so
---a later `enabled = true` undoes an earlier `enabled = false`.
---@param entry zpack.RegistryEntry
function M.deciding_spec(entry)
  for i = #entry.sorted_specs, 1, -1 do
    if entry.sorted_specs[i].enabled ~= nil then
      return entry.sorted_specs[i]
    end
  end
end

function M.resolve_enabled(enabled_results, entry, src)
  local spec = M.deciding_spec(entry)
  entry.enabled_result = spec == nil or utils.spec_enabled(spec, src, enabled_results)
end

return M
