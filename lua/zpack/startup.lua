local state = require('zpack.state')
local hooks = require('zpack.hooks')
local keymap = require('zpack.keymap')
local lazy = require('zpack.lazy')
local util = require('zpack.util')

local M = {}

local sort_by_priority = function()
  table.sort(state.startup_packs, util.compare_priority)
  table.sort(state.src_with_startup_init, util.compare_priority)
  table.sort(state.src_with_startup_config, util.compare_priority)
end

local setup_build_tracking = function()
  vim.api.nvim_create_autocmd('PackChanged', {
    group = state.startup_group,
    callback = function(event)
      if event.data.kind == "update" or event.data.kind == "install" then
        state.src_to_request_build[event.data.spec.src] = true
      end
    end,
  })
end

local run_init_hooks = function()
  for _, src in ipairs(state.src_with_startup_init) do
    hooks.try_call_hook(src, 'init')
  end
end

local add_startup_packs = function()
  vim.pack.add(state.startup_packs)
end

local run_config_hooks = function()
  for _, src in ipairs(state.src_with_startup_config) do
    hooks.try_call_hook(src, 'config')
  end
end

local run_build_hooks = function()
  vim.schedule(function()
    for src, _ in pairs(state.src_to_request_build) do
      local spec = state.src_spec[src]
      local build = spec.build
      if not lazy.is_lazy(spec) and build then
        if type(build) == "string" then
          vim.cmd(build)
        elseif type(build) == "function" then
          build()
        end
      end
    end
  end)
end

local apply_startup_keys = function()
  keymap.apply_keys(state.startup_keys)
end

M.process_all = function()
  sort_by_priority()
  setup_build_tracking()
  run_init_hooks()
  add_startup_packs()
  run_config_hooks()
  run_build_hooks()
  apply_startup_keys()
end

return M
