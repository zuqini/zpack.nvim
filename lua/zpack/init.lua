---@module 'zpack'

local M = {}

---@class ProcessContext
---@field vim_packs vim.pack.Spec[]
---@field src_with_startup_init string[]
---@field src_with_startup_config string[]
---@field startup_keys KeySpec[]
---@field registered_startup_packs vim.pack.Spec[]
---@field registered_lazy_packs vim.pack.Spec[]
---@field load boolean?
---@field confirm boolean?

---@return ProcessContext
local function create_context(opts)
  opts = opts or {}
  return {
    vim_packs = {},
    src_with_startup_init = {},
    src_with_startup_config = {},
    startup_keys = {},
    registered_startup_packs = {},
    registered_lazy_packs = {},
    load = opts.load,
    confirm = opts.confirm,
  }
end

local function check_version()
  if vim.fn.has('nvim-0.12') ~= 1 then
    vim.schedule(function()
      vim.notify('zpack.nvim requires Neovim 0.12+', vim.log.levels.ERROR)
    end)
    return false
  end
  return true
end

---@param plugins_dir string
---@param ctx ProcessContext
local import_specs_from_dir = function(plugins_dir, ctx)
  local plugin_paths = vim.fn.glob(vim.fn.stdpath('config') .. '/lua/' .. plugins_dir .. '/*.lua', false, true)

  for _, plugin_path in ipairs(plugin_paths) do
    local plugin_name = vim.fn.fnamemodify(plugin_path, ":t:r")
    local success, spec_item_or_list = pcall(require, plugins_dir .. "." .. plugin_name)

    if not success then
      require('zpack.utils').schedule_notify(
        ("Failed to load plugin spec for %s: %s"):format(plugin_name, spec_item_or_list),
        vim.log.levels.ERROR
      )
    elseif type(spec_item_or_list) ~= "table" then
      require('zpack.utils').schedule_notify(
        ("Invalid spec for %s, not a table: %s"):format(plugin_name, spec_item_or_list),
        vim.log.levels.ERROR
      )
    else
      require('zpack.import').import_specs(spec_item_or_list, ctx)
    end
  end
end

---@param ctx ProcessContext
local process_all = function(ctx)
  local hooks = require('zpack.hooks')
  local state = require('zpack.state')

  vim.api.nvim_clear_autocmds({ group = state.lazy_build_group })
  hooks.setup_build_tracking()
  require('zpack.registration').register_all(ctx)
  require('zpack.startup').process_all(ctx)
  require('zpack.lazy').process_all(ctx)
  hooks.run_pending_builds_on_startup(ctx)
  vim.api.nvim_clear_autocmds({ group = state.startup_group })
  hooks.setup_lazy_build_tracking()
end

---@class ZpackConfig
---@field plugins_dir? string
---@field auto_import? boolean
---@field disable_vim_loader? boolean
---@field confirm? boolean

local config = {
  confirm = true,
}

---@param opts? ZpackConfig
M.setup = function(opts)
  if not check_version() then return end
  opts = opts or {}

  if opts.confirm ~= nil then
    config.confirm = opts.confirm
  end

  if not opts.disable_vim_loader then
    vim.loader.enable()
  end

  local plugins_dir = opts.plugins_dir or 'plugins'
  local auto_import = opts.auto_import
  if auto_import == nil then auto_import = true end

  if auto_import then
    local ctx = create_context({ confirm = config.confirm })
    import_specs_from_dir(plugins_dir, ctx)
    process_all(ctx)
  end
  require('zpack.commands').setup()
end

---@param spec_item_or_list Spec|Spec[]
M.add = function(spec_item_or_list)
  if not check_version() then return end
  vim.schedule(function()
    local ctx = create_context({ load = true, confirm = config.confirm })
    require('zpack.import').import_specs(spec_item_or_list, ctx)
    process_all(ctx)
  end)
end

return M
