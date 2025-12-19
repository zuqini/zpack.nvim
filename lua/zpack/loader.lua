local state = require('zpack.state')
local hooks = require('zpack.hooks')
local keymap = require('zpack.keymap')

local M = {}

---@param pack_spec vim.pack.Spec
M.process_spec = function(pack_spec)
  -- Guard against multiple triggers loading the same plugin
  if state.src_spec[pack_spec.src].loaded then
    return
  end
  local spec = state.src_spec[pack_spec.src].spec

  if spec.init then
    hooks.try_call_hook(pack_spec.src, 'init')
  end

  vim.cmd.packadd(pack_spec.name)

  if spec.config then
    hooks.try_call_hook(pack_spec.src, 'config')
  end

  if spec.keys then
    keymap.apply_keys(spec.keys)
  end

  state.src_spec[pack_spec.src].loaded = true
end

return M
