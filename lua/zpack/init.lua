---@module 'zpack'

local M = {}

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
local import_specs_from_dir = function(plugins_dir)
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
      require('zpack.import').import_specs(spec_item_or_list)
    end
  end
end

local process_all = function()
  require('zpack.hooks').setup_build_tracking()
  require('zpack.startup').process_all()
  require('zpack.lazy').process_all()
  require('zpack.hooks').run_build_hooks()
  require('zpack.state').update_cache()
end

---@class ZpackConfig
---@field plugins_dir? string
---@field auto_import? boolean
---@field disable_vim_loader? boolean

---@param opts? ZpackConfig
M.setup = function(opts)
  if not check_version() then return end
  opts = opts or {}

  if not opts.disable_vim_loader then
    vim.loader.enable()
  end

  local plugins_dir = opts.plugins_dir or 'plugins'
  local auto_import = opts.auto_import
  if auto_import == nil then auto_import = true end

  if auto_import then
    import_specs_from_dir(plugins_dir)
    process_all()
  end
  require('zpack.commands').setup()
end

---@param spec_item_or_list Spec|Spec[]
M.add = function(spec_item_or_list)
  if not check_version() then return end
  require('zpack.import').import_specs(spec_item_or_list)
  process_all()
end

return M
