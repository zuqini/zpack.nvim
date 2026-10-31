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

---vim.notify's default handler echoes every level, so a debug note waits for
---'verbose'.
M.notify = function(msg, level)
  if level == vim.log.levels.DEBUG and vim.o.verbose == 0 then
    return
  end
  vim.notify('[zpack.nvim] ' .. msg, level)
end

local silenced = false

M.schedule_notify = function(msg, level)
  if silenced then
    return
  end
  vim.schedule(function()
    M.notify(msg, level)
  end)
end

---Call `fn` with schedule_notify silent.
---@param fn fun()
M.silently = function(fn)
  silenced = true
  local ok, err = pcall(fn)
  silenced = false
  if not ok then
    error(err, 0)
  end
end

---Where vim.pack installs a plugin.
---@param name string
---@return string
M.plugin_dir = function(name)
  return vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. name
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

---A table starting with a string is one KeySpec when it has a field, a
---non-string rhs, or a second string that can only be an rhs (empty, `<Nop>`,
---`<cmd>...`, `<Plug>...`, `:...`, `...<CR>`). `{ '<a>', '<b>' }`
---is a list of two keys, as in lazy.nvim, and so is any list holding a table.
---@param keys table
---@return boolean
local function is_single_key(keys)
  if type(keys[1]) ~= "string" then
    return false
  end
  local single = #keys == 1
  for k, v in pairs(keys) do
    if type(k) == "number" and type(v) == "table" then
      return false
    end
    if type(k) ~= "number" or type(v) ~= "string" then
      single = true
    end
  end
  if single then
    return true
  end
  local rhs = #keys == 2 and keys[2]:lower()
  return rhs ~= false and (M.is_nop_rhs(rhs)
    or rhs:find("^<cmd>") ~= nil or rhs:find("^<plug>") ~= nil or rhs:find("^:") ~= nil
    -- `<CR>` and `<C-x><CR>` are keys someone may map; text before `<CR>` is a command.
    or (rhs:find(".<cr>$") ~= nil and rhs:find("^<[^<>]*><cr>$") == nil))
end

---Normalize keys to a list of KeySpec tables
---@param keys zpack.KeySpec|zpack.KeySpec[]|string|string[]
---@return zpack.KeySpec[]
M.normalize_keys = function(keys)
  if type(keys) ~= "string" and type(keys) ~= "table" then
    return {}
  end
  local key_list = (type(keys) == "string" or is_single_key(keys))
      and { keys }
      or keys --[[@as string[]|zpack.KeySpec[] ]]

  local result = {}
  for _, key in ipairs(key_list) do
    if type(key) == "string" then
      table.insert(result, { key })
    elseif type(key) == "table" then
      table.insert(result, key)
    end
  end
  return result
end

---@param rhs any
---@return boolean
M.is_nop_rhs = function(rhs)
  return type(rhs) == "string" and (rhs == "" or rhs:lower() == "<nop>")
end

---What makes two keys the same mapping. lazy.nvim parity: `buffer = true` and
---`buffer = 0` both mean "current buffer".
---@param lhs string
---@param mode string
---@param ft string|string[]|nil
---@param buffer integer|boolean|nil
---@return string
M.key_id = function(lhs, mode, ft, buffer)
  local scope = M.normalize_ft_scope(ft)
  if scope then
    scope = vim.list_slice(scope)
    table.sort(scope)
  end
  return table.concat({
    vim.api.nvim_replace_termcodes(lhs, true, true, true),
    mode,
    scope and table.concat(scope, ",") or "",
    tostring(buffer == true and 0 or buffer or ""),
  }, "\0")
end

---Claim a key's lhs, ft and buffer in each of its modes.
---@param key zpack.KeySpec
---@param claimed { [string]: true }
---@return string[] kept The modes no later key had claimed
---@return integer total How many modes the key has
local function claim_key_modes(key, claimed)
  local modes = M.normalize_string_list(key.mode or "n")
  local kept = {}
  for _, mode in ipairs(modes) do
    local id = M.key_id(key[1], mode, key.ft, key.buffer)
    if not claimed[id] then
      claimed[id] = true
      kept[#kept + 1] = mode
    end
  end
  return kept, #modes
end

---Later keys replace earlier ones with the same lhs, mode, ft and buffer, one
---mode at a time (lazy.nvim's Keys.resolve). A key that loses only some of its
---modes is copied with the ones left. A malformed key is kept as it is, for the
---keys trigger to report against its plugin, since this also runs mid-merge.
---@param key_list zpack.KeySpec[]
---@return zpack.KeySpec[]
M.dedupe_keys = function(key_list)
  local claimed, reversed = {}, {}
  for i = #key_list, 1, -1 do
    local key = key_list[i]
    local ok, kept, total = pcall(claim_key_modes, key, claimed)
    if not ok or #kept == total then
      reversed[#reversed + 1] = key
    elseif #kept > 0 then
      reversed[#reversed + 1] = vim.tbl_extend("force", {}, key, { mode = kept })
    end
  end
  local result = {}
  for i = #reversed, 1, -1 do
    result[#result + 1] = reversed[i]
  end
  return result
end

---The keys to map: normalized, deduped, and without the ones a spec disabled
---with a `false` or vim.NIL rhs.
---@param keys zpack.KeySpec|zpack.KeySpec[]|string|string[]
---@return zpack.KeySpec[]
M.resolve_keys = function(keys)
  local result = {}
  for _, key in ipairs(M.dedupe_keys(M.normalize_keys(keys))) do
    if key[2] ~= false and key[2] ~= vim.NIL then
      result[#result + 1] = key
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
  local list = {}
  local ok, result = pcall(field, plugin, list)
  if not ok then
    M.schedule_notify(
      ("Failed to resolve %s for %s: %s"):format(field_name or 'field', src or 'plugin', tostring(result)),
      vim.log.levels.ERROR
    )
    return nil
  end
  if result == nil and next(list) ~= nil then
    return list
  end
  return result
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

---`check_enabled`, evaluated once per spec for a setup() run.
---@param spec zpack.Spec
---@param src? string Identifier for the failure notify
---@return boolean
M.spec_enabled = function(spec, src)
  local result = state.enabled_results[spec]
  if result == nil then
    result = M.check_enabled(spec, src)
    state.enabled_results[spec] = result
  end
  return result
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

---Derive a plugin name from a source (URL, path, or `[1]` short name):
---basename, stripped of a trailing `.git`. Used to resolve a stable name
---before `vim.pack.add`'s load callback has populated `plugin.spec.name`.
---@param src string
---@return string
M.derive_name_from_src = function(src)
  local trimmed = src:gsub('/+$', '')
  local basename = trimmed:match('([^/]+)$') or trimmed
  return (basename:gsub('%.git$', ''))
end

---Resolve a `[1]` value to a source. `owner/repo` shorthand expands to its
---GitHub URL; a full git URL (`scheme://`, `user@host:`) is returned
---unchanged (lazy.nvim parity). Filesystem paths are not recognized: vim.pack
---hands src to git verbatim, so local checkouts belong in `dir`, which
---normalize_source expands. Shared by `normalize_source` and merge.lua's
---coalesce fold so the two sites cannot drift on what a shorthand resolves to.
---@param src string `[1]` value: `owner/repo` or a full git URL
---@return string
M.expand_src = function(src)
  if src:match('^%a[%w+.-]*://') or src:match('^[%w_.-]+@[^/]+:') then
    return src
  end
  return 'https://github.com/' .. src
end

---Resolve a plugin's display/pack name. lazy.nvim parity: the name derives
---from `[1]` even when an explicit src/url/dir wins the source resolution,
---so `{ 'user/repo', url = fork }` keeps the name "repo" regardless of the
---fork's basename. An explicit `name` always wins.
---@param merged_spec zpack.Spec
---@param src string Normalized source (fallback name basis)
---@return string
M.resolve_plugin_name = function(merged_spec, src)
  if type(merged_spec.name) == 'string' then
    return merged_spec.name
  end
  if type(merged_spec[1]) == 'string' then
    return M.derive_name_from_src(merged_spec[1])
  end
  return M.derive_name_from_src(src)
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

---A string git can't take as a ref can only be a semver range. lazy.nvim parity,
---so a distro's `version = '*'` works; anything that could be a ref stays one.
---@param version any
---@return any
---@return boolean? is_range
local function range_if_not_a_ref(version)
  if type(version) == 'string' and (version:find('*', 1, true) or version:match('^[>=<^~]')) then
    local ok, range = pcall(vim.version.range, version)
    if ok and range then
      return range, true
    end
  end
  return version
end

---Normalize plugin version using priority: version > sem_version > branch > tag > commit > defaults.version.
---`version = false` is a lazy.nvim escape hatch meaning "no version constraint" —
---returns nil so vim.pack tracks the default branch even when a global default would
---otherwise pin a version.
---@param spec zpack.Spec
---@return string|vim.VersionRange|nil version
---@return boolean? is_soft A semver string, which falls back to the default branch; see zpack.pack
M.normalize_version = function(spec)
  if spec.version == false then
    return nil
  end
  if spec.version ~= nil then
    -- LLS doesn't narrow past the `== false` check above; cast.
    return range_if_not_a_ref(spec.version)
  elseif type(spec.sem_version) == 'string' then
    local range = vim.version.range(spec.sem_version)
    return range, range ~= nil
  elseif spec.branch then
    return spec.branch
  elseif spec.tag then
    return spec.tag
  elseif spec.commit then
    return spec.commit
  end
  local default_version = state.config and state.config.defaults and state.config.defaults.version
  if type(default_version) == 'string' or type(default_version) == 'table' then
    return range_if_not_a_ref(default_version)
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
