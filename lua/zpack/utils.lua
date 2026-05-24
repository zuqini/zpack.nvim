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

M.notify = function(msg, level)
  vim.notify('[zpack.nvim] ' .. msg, level)
end

M.schedule_notify = function(msg, level)
  vim.schedule(function()
    M.notify(msg, level)
  end)
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

---Normalize keys to a consistent format
---@param keys zpack.KeySpec|zpack.KeySpec[]|string|string[]
---@return zpack.KeySpec[]
M.normalize_keys = function(keys)
  -- Normalize to always be an array
  local key_list = (type(keys) == "string" or (keys[1] and type(keys[1]) == "string"))
      and { keys }
      or keys --[[@as string[]|zpack.KeySpec[] ]]

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

---Returns the normalized pattern list (nil when unscoped) for a KeySpec's
---`ft`. Shared by keys.lua's proxy install + keymap.lua's apply_ft_scoped.
---@param ft any
---@return string[]? patterns nil when `ft` is not an effective scope
M.normalize_ft_scope = function(ft)
  if type(ft) == 'string' and ft ~= '' then
    return { ft }
  end
  if type(ft) == 'table' and next(ft) ~= nil then
    return ft
  end
  return nil
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

---Wrap a callback so the second (and subsequent) calls no-op. Used to guard
---an autocmd against nvim#25526 (https://github.com/neovim/neovim/issues/25526)
---— a `once = true` autocmd that nested-fires in the same tick is dispatched
---twice before the autocmd-deletion takes effect. The latch is permanent (no
---per-tick reset); call sites combine this with `once = true` so the wrapping
---autocmd self-deletes after the first dispatch.
---@param callback function
---@return function
M.latch_first_call = function(callback)
  local done = false
  return function(...)
    if done then
      return
    end
    local result = callback(...)
    done = true
    return result
  end
end

---Register a `FileType` autocmd + synchronously call `installer(buf)` for
---already-loaded matching buffers. Installer must catch its own throws —
---a throwing installer strands the autocmd in the caller's group. The
---sweep runs before the id is returned, so callers' self-deleting closures
---can rely on `autocmd_id` still being nil during the sweep. Sweep matches
---by literal filetype; globs (`markdown.*`) work in the autocmd path but
---skip the sweep.
---@param patterns string[]
---@param installer fun(buf: integer)
---@param opts? table Extra opts merged into the autocmd (group, etc.)
---@return integer autocmd_id
M.install_on_ft = function(patterns, installer, opts)
  local pat_set = {}
  local deduped = {}
  for _, p in ipairs(patterns) do
    if not pat_set[p] then
      pat_set[p] = true
      table.insert(deduped, p)
    end
  end
  local autocmd_opts = vim.tbl_extend("force", opts or {}, {
    pattern = deduped,
    callback = function(ev) installer(ev.buf) end,
  })
  local id = vim.api.nvim_create_autocmd("FileType", autocmd_opts)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and pat_set[vim.bo[buf].filetype] then
      installer(buf)
    end
  end
  return id
end

---Resolve a function-form spec field; a throw becomes a structured notify
---and a nil return instead of aborting the caller.
---@param field any
---@param plugin zpack.Plugin?
---@param src? string Identifier for the failure notify
---@param field_name? string Which field is being resolved (for the notify)
---@return any
M.try_resolve_field = function(field, plugin, src, field_name)
  if type(field) ~= "function" then
    return field
  end
  local ok, result = pcall(field, plugin)
  if not ok then
    M.schedule_notify(
      ("Failed to resolve %s for %s: %s"):format(field_name or 'field', src or 'plugin', tostring(result)),
      vim.log.levels.ERROR
    )
    return nil
  end
  return result
end

---Coerce `spec.enabled` to a bool; function-form is pcall'd and a throw
---is treated as `false` with a structured notify.
---@param spec zpack.Spec
---@param src? string Identifier for the failure notify
---@return boolean
M.check_enabled = function(spec, src)
  local en = spec.enabled
  if en == false then
    return false
  end
  if type(en) == "function" then
    local ok, result = pcall(en)
    if not ok then
      M.schedule_notify(
        ("Failed to evaluate enabled for %s: %s"):format(src or 'plugin', tostring(result)),
        vim.log.levels.ERROR
      )
      return false
    end
    if not result then
      return false
    end
  end
  return true
end

---Coerce `spec.cond` (or `default_cond` when nil) to a bool; function-form
---is pcall'd and a throw is treated as `false` with a structured notify.
---@param spec zpack.Spec
---@param plugin zpack.Plugin?
---@param default_cond? boolean|(fun(plugin: zpack.Plugin):boolean)
---@param src? string Identifier for the failure notify
---@return boolean
M.check_cond = function(spec, plugin, default_cond, src)
  local cond = spec.cond
  if cond == nil then
    cond = default_cond
  end

  if cond == false then
    return false
  end
  if type(cond) == "function" then
    local ok, result = pcall(cond, plugin)
    if not ok then
      M.schedule_notify(
        ("Failed to evaluate cond for %s: %s"):format(src or 'plugin', tostring(result)),
        vim.log.levels.ERROR
      )
      return false
    end
    if not result then
      return false
    end
  end
  return true
end

---Normalize a plugin name for module matching
---Derive a plugin name from a src URL/path the same way `vim.pack.add`
---does when `name` is not explicitly set: basename of the URL/path,
---stripped of a trailing `.git`. Used to resolve a stable name before
---`vim.pack.add`'s load callback has populated `plugin.spec.name`.
---@param src string
---@return string
M.derive_name_from_src = function(src)
  local trimmed = src:gsub('/+$', '')
  local basename = trimmed:match('([^/]+)$') or trimmed
  return (basename:gsub('%.git$', ''))
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

---Check if a string looks like a semver range (not a branch/tag/commit)
---@param str any
---@return boolean
M.is_semver_like = function(str)
  if type(str) ~= 'string' then
    return false
  end
  return str:match('%*') ~= nil
      or str:match('^%d[%d%.]*%.[xX]$') ~= nil
      or str:match('^%d[%d%.]*%.%a') ~= nil
      or str:match('^[>=<^~]') ~= nil
      or str:match('[>=<]') ~= nil
      or str:match('^%d+[%d%.]*$') ~= nil
end

---Normalize plugin version using priority: version > sem_version > branch > tag > commit
---@param spec zpack.Spec
---@return string|vim.VersionRange|nil version
M.normalize_version = function(spec)
  if spec.version ~= nil then
    return spec.version
  elseif spec.sem_version then
    return vim.version.range(spec.sem_version)
  elseif spec.branch then
    return spec.branch
  elseif spec.tag then
    return spec.tag
  elseif spec.commit then
    return spec.commit
  end
  return nil
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
    local mod
    if dir_entry.name:sub(-4) == ".lua" then
      mod = dir_entry.name:sub(1, -5)
    elseif dir_entry.type == "directory" or dir_entry.type == "link" then
      mod = dir_entry.name
    end

    if mod and M.normalize_name(mod) == norm_name then
      plugin.main = mod
      return mod
    end
  end

  state.resolve_main_not_found[cache_key] = true
  return nil
end

---Track which plugin paths have had their after/plugin/ files sourced
---@type { [string]: true }
local sourced_plugin_paths = {}

---Source after/plugin/ files for a plugin.
---:packadd sources plugin/ files but never after/plugin/ files. The startup
---sequence that normally sources after/plugin/ from the rtp has already run
---by the time lazy-loaded plugins are activated, so we do it manually.
---@param plugin_path string
M.source_after_plugin_files = function(plugin_path)
  if sourced_plugin_paths[plugin_path] then
    return
  end

  local files = vim.fn.glob(plugin_path .. '/after/plugin/**/*.{vim,lua}', false, true)
  -- Per-file pcall so one broken file doesn't skip its siblings; cache
  -- marker is set after the loop so the first call always attempts every
  -- file even if a sibling throws.
  for _, file in ipairs(files) do
    local ok, err = pcall(vim.cmd.source, file)
    if not ok then
      M.schedule_notify(("Failed to source %s: %s"):format(file, tostring(err)), vim.log.levels.ERROR)
    end
  end

  sourced_plugin_paths[plugin_path] = true
end

---Track which plugin paths have had their ftdetect/ files sourced
---@type { [string]: true }
local sourced_ftdetect_paths = {}

---Source ftdetect/ files for a lazy plugin so its filetype rules are in
---place before any file is opened. Without this a plugin specced as
---`ft = 'rust'` would never load on `:edit foo.rs`, because the rules that
---set `&ft = 'rust'` live in the plugin's un-sourced `ftdetect/rust.vim`.
---@param plugin_path string
M.source_ftdetect_files = function(plugin_path)
  if sourced_ftdetect_paths[plugin_path] then
    return
  end
  sourced_ftdetect_paths[plugin_path] = true

  local files = vim.fn.glob(plugin_path .. '/ftdetect/*.{vim,lua}', false, true)
  -- ftdetect files must execute inside the `filetypedetect` augroup so their
  -- autocmds register there (matches Neovim's standard ftdetect sourcing).
  -- The augroup begin/end are issued as separate ex-commands rather than
  -- `|`-chained with the `source`, because a throw inside the chained source
  -- skips the trailing `augroup END` and leaves Neovim in `filetypedetect`
  -- — subsequent vimscript `autocmd` statements would silently land there.
  for _, file in ipairs(files) do
    vim.cmd('augroup filetypedetect')
    local ok, err = pcall(vim.cmd.source, file)
    vim.cmd('augroup END')
    if not ok then
      M.schedule_notify(("Failed to source %s: %s"):format(file, tostring(err)), vim.log.levels.ERROR)
    end
  end
end

return M
