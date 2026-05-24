local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.plugin_loader')
local refire = require('zpack.lazy_trigger.refire')

local M = {}

---@param pack_spec vim.pack.Spec
---@param ft zpack.FtValue
M.setup = function(pack_spec, ft)
  local filetypes = util.normalize_string_list(ft)

  -- Source the plugin's ftdetect/* now so its filetype rules are active
  -- before any file is opened. Without this, `ft = '<custom>'` for a plugin
  -- that ships its own filetype detection (e.g. `ftdetect/rust.vim`) silently
  -- never triggers, because vim.pack defers the rules behind `:packadd`.
  local registry_entry = state.spec_registry[pack_spec.src]
  local plugin_path = registry_entry and registry_entry.plugin and registry_entry.plugin.path
  if plugin_path then
    util.source_ftdetect_files(plugin_path)
  end

  -- latch_first_call guards against nvim#25526; needed here because the
  -- plugin's own `ftplugin/*` sourced during packadd can nest-fire FileType
  -- on the same buffer before load_status flips.
  util.autocmd("FileType", util.latch_first_call(function(ev)
    -- Skip when a sibling already loaded (avoid double-fire) or is
    -- mid-load (avoid spurious circular-dependency notify).
    local entry = state.spec_registry[pack_spec.src]
    if entry and entry.load_status ~= "pending" then
      return
    end
    local snap = refire.snapshot("FileType")
    if not loader.try_process_spec(pack_spec) then
      return
    end
    refire.exec(ev, snap)
  end), { group = state.lazy_group, pattern = filetypes, once = true })
end

return M
