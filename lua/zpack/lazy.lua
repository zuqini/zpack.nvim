-- inspired by https://www.reddit.com/r/neovim/comments/1mx71rc/how_i_vastly_improved_my_lazy_loading_experience/
local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.loader')
local event_handler = require('zpack.lazy_trigger.event')
local ft_handler = require('zpack.lazy_trigger.ft')
local cmd_handler = require('zpack.lazy_trigger.cmd')
local keys_handler = require('zpack.lazy_trigger.keys')

local M = {}

---@param spec Spec
---@return boolean
M.is_lazy = function(spec)
  if spec.lazy ~= nil then
    return spec.lazy
  end
  return (spec.event ~= nil) or (spec.cmd ~= nil) or (spec.keys ~= nil and #spec.keys > 0) or (spec.ft ~= nil)
end

---@return vim.pack.Spec[]
local register_lazy_packs = function()
  local registered_plugins = {}
  vim.pack.add(state.lazy_packs, {
    load = function(plugin)
      local pack_spec = plugin.spec
      local spec = state.src_spec[pack_spec.src].spec
      if state.src_to_request_build[pack_spec.src] then
        -- requested build, do not lazy load this
        loader.process_spec(pack_spec)
        return
      end

      table.insert(registered_plugins, pack_spec)
      if spec.event then
        event_handler.setup(plugin.spec, spec)
      end
      if spec.ft then
        ft_handler.setup(plugin.spec, spec)
      end
    end
  })
  return registered_plugins
end

M.process_all = function()
  table.sort(state.lazy_packs, util.compare_priority)
  local registered_pack_specs = register_lazy_packs()
  cmd_handler.setup(registered_pack_specs)
  keys_handler.setup(registered_pack_specs)
end

return M
