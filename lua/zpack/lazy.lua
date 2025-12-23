-- inspired by https://www.reddit.com/r/neovim/comments/1mx71rc/how_i_vastly_improved_my_lazy_loading_experience/
local state = require('zpack.state')
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

---@param ctx ProcessContext
M.process_all = function(ctx)
  if next(state.src_with_pending_build) ~= nil then
    return
  end

  for _, pack_spec in ipairs(ctx.registered_lazy_packs) do
    local spec = state.spec_registry[pack_spec.src].spec
    if spec.event then
      event_handler.setup(pack_spec, spec)
    end
    if spec.ft then
      ft_handler.setup(pack_spec, spec)
    end
  end
  cmd_handler.setup(ctx.registered_lazy_packs)
  keys_handler.setup(ctx.registered_lazy_packs)
end

return M
