---@module 'zpack'

local import = require('zpack.import')
local lazy = require('zpack.lazy')
local startup = require('zpack.startup')
local commands = require('zpack.commands')
local hooks = require('zpack.hooks')
local util = require('zpack.utils')

local M = {}

---@param plugins_dir string
local import_specs_from_dir = function(plugins_dir)
  local plugin_paths = vim.fn.glob(vim.fn.stdpath('config') .. '/lua/' .. plugins_dir .. '/*.lua', false, true)

  for _, plugin_path in ipairs(plugin_paths) do
    local plugin_name = vim.fn.fnamemodify(plugin_path, ":t:r")
    local success, spec_item_or_list = pcall(require, plugins_dir .. "." .. plugin_name)

    if not success then
      util.schedule_notify(
        ("Failed to load plugin spec for %s: %s"):format(plugin_name, spec_item_or_list),
        vim.log.levels.ERROR
      )
    elseif type(spec_item_or_list) ~= "table" then
      util.schedule_notify(
        ("Invalid spec for %s, not a table: %s"):format(plugin_name, spec_item_or_list),
        vim.log.levels.ERROR
      )
    else
      import.import_specs(spec_item_or_list)
    end
  end
end

local process_all = function()
  hooks.setup_build_tracking()
  startup.process_all()
  lazy.process_all()
  hooks.run_build_hooks()
end

---@class ZpackConfig
---@field plugins_dir? string
---@field auto_import? boolean

---@param opts? ZpackConfig
M.setup = function(opts)
  opts = opts or {}
  local plugins_dir = opts.plugins_dir or 'plugins'
  local auto_import = opts.auto_import
  if auto_import == nil then auto_import = true end

  if auto_import then
    import_specs_from_dir(plugins_dir)
    process_all()
  end
  commands.setup()
end

---@param spec_item_or_list Spec|Spec[]
M.add = function(spec_item_or_list)
  import.import_specs(spec_item_or_list)
  process_all()
end

return M
