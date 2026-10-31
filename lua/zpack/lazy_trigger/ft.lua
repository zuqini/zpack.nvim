local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.plugin_loader')
local refire = require('zpack.lazy_trigger.refire')

local M = {}

---Plugins sharing a filetype load together and re-fire once: the re-fire runs
---every FileType handler, including the ftplugin, indent and syntax :runtime!
---scans over all of 'runtimepath', so one re-fire per plugin scales with both.
---Each group has its own autocmd; this holds the one still accepting plugins.
---@type { [string]: (fun(): boolean?)[] }
local open_groups = {}

---@param filetype string
---@return (fun(): boolean?)[]? group nil when the autocmd rejects `filetype` as a pattern
local function open_group(filetype)
  local group = {}
  -- The latch guards against nvim#25526: the plugin's own `ftplugin/*` sourced
  -- during packadd can nest-fire FileType on the same buffer despite `once`.
  local ok = pcall(util.autocmd, "FileType", util.latch_first_call(function(ev)
    if open_groups[filetype] == group then
      open_groups[filetype] = nil
    end

    local snap = refire.snapshot("FileType")
    local any_loaded = false
    for _, try_load in ipairs(group) do
      any_loaded = try_load() or any_loaded
    end
    if any_loaded then
      refire.exec(ev, snap)
    end
  end), { group = state.lazy_group, pattern = filetype, once = true })
  if not ok then
    return nil
  end
  open_groups[filetype] = group
  return group
end

---Autocmd patterns are comma-separated, except inside `{}` or after a backslash.
---@param pattern string
---@return string[] patterns
local function split_patterns(pattern)
  if pattern:find('[{\\]') then
    return { pattern }
  end
  local patterns = {}
  for part in pattern:gmatch('[^,]+') do
    table.insert(patterns, part)
  end
  return patterns
end

---@param pattern string
---@return boolean
local function is_literal(pattern)
  return pattern:match('^[%w_%-%.]+$') ~= nil
end

---Later plugins start new groups, so they run after an autocmd registered now.
---An `event = 'FileType'` plugin keeps its priority slot between ft plugins, so
---this closes the groups `patterns` can fire alongside.
---@param patterns string|string[]
M.close_groups = function(patterns)
  local entries = util.normalize_string_list(patterns)
  -- v0.12.0 treats an empty pattern list as matching everything
  if #entries == 0 then
    open_groups = {}
    return
  end
  -- Lowercased because 'fileignorecase' makes spellings of a name match
  local literals = {}
  for _, entry in ipairs(entries) do
    for _, pattern in ipairs(split_patterns(entry)) do
      if not is_literal(pattern) then
        open_groups = {}
        return
      end
      literals[pattern:lower()] = true
    end
  end
  for filetype in pairs(open_groups) do
    if literals[filetype:lower()] or not is_literal(filetype) then
      open_groups[filetype] = nil
    end
  end
end

---@param ft any
---@return string[] filetypes
---@return boolean ignored whether `ft` held anything besides a list of filetypes
local function usable_filetypes(ft)
  local list = type(ft) == "string" and { ft } or ft
  if type(list) ~= "table" then
    return {}, true
  end
  local filetypes = {}
  local usable = 0
  for _, entry in ipairs(list) do
    if type(entry) == "string" and entry ~= "" then
      usable = usable + 1
      vim.list_extend(filetypes, split_patterns(entry))
    end
  end
  return filetypes, usable < vim.tbl_count(list)
end

---@param pack_spec vim.pack.Spec
---@param ft zpack.FtValue
M.setup = function(pack_spec, ft)
  local filetypes, ignored = usable_filetypes(ft)
  local label = pack_spec.name or pack_spec.src
  if #filetypes == 0 then
    util.schedule_notify(
      ("%s: ft has no filetypes, so no filetype will load it"):format(label),
      vim.log.levels.WARN
    )
    return
  end
  if ignored then
    util.schedule_notify(
      ("%s: ignoring ft entries other than a list of non-empty strings"):format(label),
      vim.log.levels.WARN
    )
  end

  -- Source the plugin's ftdetect/* now so its filetype rules are active
  -- before any file is opened. Without this, `ft = '<custom>'` for a plugin
  -- that ships its own filetype detection (e.g. `ftdetect/rust.vim`) silently
  -- never triggers, because vim.pack defers the rules behind `:packadd`.
  local registry_entry = state.spec_registry[pack_spec.src]
  local plugin_path = registry_entry and registry_entry.plugin and registry_entry.plugin.path
  if plugin_path then
    util.source_ftdetect_files(plugin_path)
  end

  -- Latched per plugin, not per filetype: a plugin that failed on one filetype
  -- must not retry on the next, since :packadd re-sources plugin/ every time.
  local try_load = util.latch_first_call(function()
    -- Skip when a sibling already loaded (avoid double-fire), is mid-load
    -- (avoid spurious circular-dependency notify), or was removed.
    local entry = state.spec_registry[pack_spec.src]
    return entry and entry.load_status == "pending" and loader.try_process_spec(pack_spec)
  end)

  for _, filetype in ipairs(filetypes) do
    local group = open_groups[filetype] or open_group(filetype)
    if group then
      table.insert(group, try_load)
    else
      util.schedule_notify(
        ("%s: ignoring ft '%s', which isn't a valid autocmd pattern"):format(label, filetype),
        vim.log.levels.WARN
      )
    end
  end
end

return M
