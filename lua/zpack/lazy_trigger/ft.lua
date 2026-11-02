if jit then jit.off(true, true) end

local util = require('zpack.utils')
local runtime = require('zpack.runtime')
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

---Later plugins start new groups, so they run after an autocmd registered now.
---An `event = 'FileType'` plugin keeps its priority slot between ft plugins, at the
---cost of a re-fire for each group it splits, which ft-only configs never pay.
M.close_groups = function()
  open_groups = {}
end

---@class zpack.ParsedFt
---@field filetypes string[]
---@field usable boolean Whether it holds a non-empty string
---@field ignored boolean Whether it held anything besides a list of filetypes

---@param ft any
---@return zpack.ParsedFt?
M.parse = function(ft)
  if not ft then
    return nil
  end
  local list = type(ft) == "string" and { ft } or ft
  if type(list) ~= "table" then
    return { filetypes = {}, usable = false, ignored = true }
  end
  local filetypes = {}
  local usable = 0
  for _, entry in ipairs(list) do
    if type(entry) == "string" and entry ~= "" then
      usable = usable + 1
      vim.list_extend(filetypes, split_patterns(entry))
    end
  end
  return { filetypes = filetypes, usable = usable > 0, ignored = usable < vim.tbl_count(list) }
end

---@param pack_spec vim.pack.Spec
---@param parsed zpack.ParsedFt
M.setup = function(pack_spec, parsed)
  local filetypes = parsed.filetypes
  local label = pack_spec.name or pack_spec.src
  if #filetypes == 0 then
    util.schedule_notify(
      ("%s: ft has no filetypes, so no filetype will load it"):format(label),
      vim.log.levels.WARN
    )
    return
  end
  if parsed.ignored then
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
    runtime.source_ftdetect_files(plugin_path)
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
