if jit then jit.off(true, true) end

local state = require('zpack.state')

local M = {}

local lsdir_cache = {}
local normalized_name_cache = {}

---@class zpack.DirEntry
---@field name string
---@field type string

---Scan a directory and cache the results (uses vim.uv.fs_scandir)
---@param path string
---@return zpack.DirEntry[]
M.lsdir = function(path)
  if lsdir_cache[path] then
    return lsdir_cache[path]
  end

  local entries = {}
  local handle = vim.uv.fs_scandir(path)
  if handle then
    while true do
      local name, entry_type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      -- HACK: type is not always returned due to a bug in luv
      if not entry_type then
        local stat = vim.uv.fs_stat(path .. "/" .. name)
        entry_type = stat and stat.type or "file"
      end
      entries[#entries + 1] = { name = name, type = entry_type }
    end
  end

  lsdir_cache[path] = entries
  return entries
end

M.reset_lsdir_cache = function()
  lsdir_cache = {}
end

---The top-level module an entry of a plugin's lua/ provides.
---@param entry zpack.DirEntry
---@return string?
M.top_module = function(entry)
  return entry.name:match("^(.+)%.lua$") or ((entry.type == "directory" or entry.type == "link") and entry.name or nil)
end

---vim.notify's default handler echoes every level, so a debug note waits for
---'verbose'.
M.notify = function(msg, level)
  if level == vim.log.levels.DEBUG and vim.o.verbose == 0 then
    return
  end
  vim.notify('[zpack.nvim] ' .. msg, level)
end

---@param msg string
---@param level integer
M.schedule_notify = function(msg, level)
  vim.schedule(function()
    M.notify(msg, level)
  end)
end

---A plugin's dependencies in the order it lists them, as vim.pack and lazy.nvim
---would see them; `dependency_graph` alone is a set.
---@param src string
---@return string[]
M.sorted_dependencies = function(src)
  local deps = vim.tbl_keys(state.dependency_graph[src] or {})
  local order = state.dependency_order[src] or {}
  table.sort(deps, function(a, b)
    local order_a, order_b = order[a] or math.huge, order[b] or math.huge
    if order_a ~= order_b then
      return order_a < order_b
    end
    return a < b
  end)
  return deps
end

---Get priority for a plugin source (default: 50)
---@param src string
---@return number
M.get_priority = function(src)
  local entry = state.spec_registry[src]
  if not entry then
    return 50
  end
  local priority = entry.merged_spec and entry.merged_spec.priority
  -- A non-number priority survives import as an advisory-only error; coerce
  -- it away here so compare_priority's `>` cannot throw on a string/etc.
  return type(priority) == 'number' and priority or 50
end

---Get import order for a plugin source (used as tiebreaker)
---@param src string
---@return number
M.get_import_order = function(src)
  local entry = state.spec_registry[src]
  if not entry or not entry.specs or not entry.specs[1] then
    return math.huge
  end
  return entry.specs[1]._import_order or math.huge
end

---Comparison function for sorting items by priority (descending)
---Uses import order as tiebreaker for deterministic sorting
---Works with both source strings and vim.pack.Spec objects
---@param a string|vim.pack.Spec
---@param b string|vim.pack.Spec
---@return boolean
M.compare_priority = function(a, b)
  local src_a = type(a) == "string" and a or a.src
  local src_b = type(b) == "string" and b or b.src
  local priority_a = M.get_priority(src_a)
  local priority_b = M.get_priority(src_b)
  if priority_a ~= priority_b then
    return priority_a > priority_b
  end
  return M.get_import_order(src_a) < M.get_import_order(src_b)
end

---Normalize value to array for list fields (event, cmd, ft, keys, opts_extend).
---Handles three cases:
---  1. nil -> empty array
---  2. Non-table (string) -> wrap in array: "BufRead" -> {"BufRead"}
---  3. Table:
---     - Already array-like (has [1]) or empty -> return as-is
---     - Dict-like (e.g., EventSpec {event="X", pattern="Y"}) -> wrap in array
---@param val any
---@return any[]
M.to_array = function(val)
  if val == nil then
    return {}
  end
  if type(val) ~= "table" then
    return { val }
  end
  if val[1] ~= nil or next(val) == nil then
    return val
  end
  return { val }
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

---Wrap a callback so the second (and subsequent) calls no-op. The latch is
---permanent (no per-tick reset). Autocmd call sites use it to guard against
---nvim#25526 (https://github.com/neovim/neovim/issues/25526) — a `once = true`
---autocmd that nested-fires in the same tick is dispatched twice before the
---autocmd-deletion takes effect. ft.lua uses it per plugin, so a plugin that
---failed to load on one filetype doesn't retry and re-source plugin/ on the next.
---@param callback function
---@return function
M.latch_first_call = function(callback)
  local done = false
  return function(...)
    if done then
      return
    end
    done = true
    return callback(...)
  end
end

---Resolve a function-form spec field; a throw becomes a structured notify
---and a nil return instead of aborting the caller.
---@param field any
---@param plugin zpack.Plugin?
---@param src? string Identifier for the failure notify
---@param field_name? string Which field is being resolved (for the notify)
---@param on_throw? fun() Told of a throw, instead of the notify
---@return any
M.try_resolve_field = function(field, plugin, src, field_name, on_throw)
  if type(field) ~= "function" then
    return field
  end
  local list = {}
  local ok, result = pcall(field, plugin, list)
  if not ok then
    if on_throw then
      on_throw()
    else
      M.schedule_notify(
        ("Failed to resolve %s for %s: %s"):format(field_name or 'field', src or 'plugin', tostring(result)),
        vim.log.levels.ERROR
      )
    end
    return nil
  end
  if result == nil and next(list) ~= nil then
    return list
  end
  return result
end

---A trigger's value through its handler's `parse`. A static value is parsed once. A
---function-form one runs each time, since it can answer differently by then: a
---keys function may need the modules of a plugin that has since loaded.
---@param entry { merged_spec: zpack.Spec, triggers?: table }
---@param field 'event'|'cmd'|'ft'|'keys'
---@param parse fun(value: any, spec: zpack.Spec): any
---@param plugin zpack.Plugin?
---@param label? string Identifier for the failure notify
---@param on_throw? fun() Told of a function's throw, instead of the notify
---@return any
M.read_trigger = function(entry, field, parse, plugin, label, on_throw)
  local spec = entry.merged_spec
  local value = spec[field]
  if type(value) == "function" then
    return parse(M.try_resolve_field(value, plugin, label, field, on_throw), spec)
  end
  entry.triggers = entry.triggers or {}
  local parsed = entry.triggers[field]
  if parsed == nil then
    parsed = parse(value, spec)
    entry.triggers[field] = parsed
  end
  return parsed
end

---Run one plugin's trigger setup so a malformed value reports that plugin
---instead of aborting setup() for every plugin after it.
---@param label string
---@param field_name string
---@param setup fun()
M.try_trigger_setup = function(label, field_name, setup)
  local ok, err = pcall(setup)
  if not ok then
    M.schedule_notify(
      ("Failed to set up %s for %s: %s"):format(field_name, label, tostring(err)),
      vim.log.levels.ERROR
    )
  end
end

---@param msg string
local function notify_error(msg)
  M.schedule_notify(msg, vim.log.levels.ERROR)
end

---Coerce a boolean-or-function spec field to a bool; a function that throws
---counts as `false`, and `report` is told.
---@param value any
---@param field_name string
---@param src? string Identifier for the failure message
---@param report fun(msg: string)
---@param ... any Arguments for a function-form value
---@return boolean
local function check_field(value, field_name, src, report, ...)
  if type(value) ~= "function" then
    return value ~= false
  end
  local ok, result = pcall(value, ...)
  if not ok then
    report(("Failed to evaluate %s for %s: %s"):format(field_name, src or 'plugin', tostring(result)))
    return false
  end
  return result and true or false
end

---`spec.enabled`, evaluated once per spec for a setup() run. A spec that throws
---is dropped as disabled.
---@param spec zpack.Spec
---@param src? string Identifier for the failure notify
---@param results { [zpack.Spec]: boolean } The answers so far
---@return boolean
M.spec_enabled = function(spec, src, results)
  local result = results[spec]
  if result == nil then
    result = check_field(spec.enabled, 'enabled', src, notify_error)
    results[spec] = result
  end
  return result
end

---`spec.cond`, or `default_cond` when nil.
---@param spec zpack.Spec
---@param plugin zpack.Plugin?
---@param default_cond? boolean|(fun(plugin: zpack.Plugin):boolean)
---@param src? string Identifier for the failure notify
---@param report? fun(msg: string) Told of a throw. Default: notify
---@return boolean
M.check_cond = function(spec, plugin, default_cond, src, report)
  local cond = spec.cond
  if cond == nil then
    cond = default_cond
  end
  return check_field(cond, 'cond', src, report or notify_error, plugin)
end

---Inspired by lazy.nvim's Util.normname()
---@param name string
---@return string
M.normalize_name = function(name)
  local cached = normalized_name_cache[name]
  if cached then
    return cached
  end
  local norm = (name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", ""))
  normalized_name_cache[name] = norm
  return norm
end

---Resolve the main module for a plugin (for auto-setup)
---Inspired by lazy.nvim's loader.get_main()
---Results are cached in plugin.main (for found modules) and state.resolve_main_not_found (for not-found)
---@param plugin zpack.Plugin
---@param spec zpack.Spec
---@return string? main_module The main module name, or nil if not found
M.resolve_main = function(plugin, spec)
  if plugin.main ~= nil then
    return plugin.main
  end

  local cache_key = plugin.spec.src
  if state.resolve_main_not_found[cache_key] then
    return nil
  end

  if spec.main then
    plugin.main = spec.main
    return spec.main
  end

  local name = plugin.spec.name
  if not name then
    state.resolve_main_not_found[cache_key] = true
    return nil
  end

  if name:match("^mini%.") and name ~= "mini.nvim" then
    plugin.main = name
    return name
  end

  local norm_name = M.normalize_name(name)
  local lua_dir = plugin.path .. "/lua"

  for _, dir_entry in ipairs(M.lsdir(lua_dir)) do
    local mod = M.top_module(dir_entry)
    if mod and M.normalize_name(mod) == norm_name then
      plugin.main = mod
      return mod
    end
  end

  state.resolve_main_not_found[cache_key] = true
  return nil
end

return M
