local state = require('zpack.state')
local util = require('zpack.utils')

local M = {}

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
  vim.api.nvim_create_user_command('ZUpdate', function()
    vim.pack.update()
  end, {
    desc = 'Update all plugins',
  })

  vim.api.nvim_create_user_command('ZClean', function()
    M.clean_unused()
  end, {
    desc = 'Remove unused plugins',
  })

  vim.api.nvim_create_user_command('ZCleanAll', function()
    M.clean_all()
  end, {
    desc = 'Remove all plugins',
  })

  vim.api.nvim_create_user_command('ZDelete', function(opts)
    local plugin_name = opts.args
    if plugin_name == '' then
      util.schedule_notify('Usage: ZDelete <plugin_name>', vim.log.levels.ERROR)
      return
    end

    local installed = vim.pack.get()
    local found = false
    for _, pack in ipairs(installed) do
      if pack.spec.name == plugin_name then
        found = true
        break
      end
    end

    if not found then
      util.schedule_notify(('Plugin "%s" not found'):format(plugin_name), vim.log.levels.ERROR)
      return
    end

    vim.pack.del({ plugin_name })
    util.schedule_notify(('Deleted: %s'):format(plugin_name), vim.log.levels.INFO)
  end, {
    nargs = 1,
    desc = 'Delete a specific plugin',
    complete = function()
      local installed = vim.pack.get()
      local names = {}
      for _, pack in ipairs(installed) do
        table.insert(names, pack.spec.name)
      end
      return names
    end,
  })
end

return M
