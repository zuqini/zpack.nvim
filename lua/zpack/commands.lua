local state = require('zpack.state')
local util = require('zpack.utils')
local hooks = require('zpack.hooks')
local loader = require('zpack.loader')

local M = {}

local get_plugin_or_notify = function(plugin_name)
  local pack = vim.pack.get({ plugin_name })[1]
  if not pack then
    util.schedule_notify(('Plugin "%s" not found'):format(plugin_name), vim.log.levels.ERROR)
    return nil
  end
  return pack
end

local get_installed_plugin_names = function()
  return state.cached_plugin_names or {}
end

local get_plugin_names_with_build_hooks = function()
  return state.cached_plugin_names_with_build or {}
end

M.clean_all = function()
  local installed_packs = vim.pack.get()

  util.schedule_notify(("Deleting all %d installed plugin(s)..."):format(#installed_packs), vim.log.levels.INFO)

  local names_to_delete = {}
  for _, pack in ipairs(installed_packs) do
    table.insert(names_to_delete, pack.spec.name)
  end

  vim.pack.del(names_to_delete)

  util.schedule_notify("All plugins deleted.", vim.log.levels.INFO)
end

M.clean_unused = function()
  local installed_packs = vim.pack.get()
  local specs_by_src = state.src_spec
  local to_delete = {}

  for _, pack in ipairs(installed_packs) do
    local src = pack.spec.src
    -- do not delete zpack
    if not specs_by_src[src] and not string.find(src, 'zpack') then
      table.insert(to_delete, pack.spec)
    end
  end

  if #to_delete == 0 then
    util.schedule_notify("No unused plugins to clean", vim.log.levels.INFO)
    return
  end

  util.schedule_notify(("Deleting %d unused plugin(s)..."):format(#to_delete), vim.log.levels.INFO)

  local names_to_delete = {}
  for _, spec in ipairs(to_delete) do
    table.insert(names_to_delete, spec.name)
  end

  vim.pack.del(names_to_delete)

  for _, spec in ipairs(to_delete) do
    util.schedule_notify(("Deleted: %s"):format(spec.name or spec.src), vim.log.levels.INFO)
  end
end

M.setup = function()
  vim.api.nvim_create_user_command('ZUpdate', function(opts)
    local plugin_name = opts.args
    if plugin_name == '' then
      vim.pack.update()
    else
      if not get_plugin_or_notify(plugin_name) then
        return
      end
      vim.pack.update({ plugin_name })
    end
  end, {
    nargs = '?',
    desc = 'Update all plugins or a specific plugin',
    complete = get_installed_plugin_names,
  })

  vim.api.nvim_create_user_command('ZClean', function()
    M.clean_unused()
  end, {
    desc = 'Remove unused plugins',
  })

  vim.api.nvim_create_user_command('ZBuild', function(opts)
    local plugin_name = opts.args
    if plugin_name == '' then
      if not opts.bang then
        util.schedule_notify('Use :ZBuild! to run build hooks for all plugins', vim.log.levels.WARN)
        return
      end
      hooks.run_all_build_hooks()
      return
    end

    local pack = get_plugin_or_notify(plugin_name)
    if not pack then
      return
    end

    local src_spec_entry = state.src_spec[pack.spec.src]
    if not src_spec_entry or not src_spec_entry.spec.build then
      util.schedule_notify(('Plugin "%s" has no build hook'):format(plugin_name), vim.log.levels.WARN)
      return
    end

    loader.process_spec(pack.spec)
    state.src_to_request_build[pack.spec.src] = true
    hooks.execute_build(src_spec_entry.spec.build)
    util.schedule_notify(('Running build hook for %s'):format(plugin_name), vim.log.levels.INFO)
  end, {
    nargs = '?',
    bang = true,
    desc = 'Run build hook for a specific plugin or all plugins',
    complete = get_plugin_names_with_build_hooks,
  })

  vim.api.nvim_create_user_command('ZDelete', function(opts)
    local plugin_name = opts.args
    if plugin_name == '' then
      if not opts.bang then
        util.schedule_notify(
          'Use :ZDelete! to confirm deletion of all installed plugin(s)',
          vim.log.levels.WARN
        )
        return
      end
      M.clean_all()
      return
    end

    if not get_plugin_or_notify(plugin_name) then
      return
    end

    vim.pack.del({ plugin_name })
    util.schedule_notify(('Deleted: %s'):format(plugin_name), vim.log.levels.INFO)
  end, {
    nargs = '?',
    bang = true,
    desc = 'Delete all plugins or a specific plugin',
    complete = get_installed_plugin_names,
  })
end

return M
