local helpers = require('helpers')

describe("ZPack load", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("lazy plugin is tracked as unloaded", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/lazy-plugin',
          cmd = 'TestCommand',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(
      helpers.unloaded_plugin_names()['lazy-plugin'] == true,
      "Lazy plugin should be tracked as unloaded"
    )
  end)

  it("startup plugin is not tracked as unloaded", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/startup-plugin',
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_nil(
      helpers.unloaded_plugin_names()['startup-plugin'],
      "Startup plugin should not be in unloaded list"
    )
  end)

  it("plugin is removed from unloaded list when loaded", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/lazy-plugin',
          cmd = 'TestCommand',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(
      helpers.unloaded_plugin_names()['lazy-plugin'] == true,
      "Plugin should be unloaded initially"
    )

    pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()

    assert.is_nil(
      helpers.unloaded_plugin_names()['lazy-plugin'],
      "Plugin should be removed from unloaded list after loading"
    )
  end)

  it("load without bang shows warning", function()
    require('zpack').setup({
      spec = {
        {
          'test/lazy-plugin',
          cmd = 'TestCommand',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    pcall(vim.cmd, 'ZPack load')
    helpers.flush_pending()

    local found_warning = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find(':ZPack! load', 1, true) and notif.level == vim.log.levels.WARN then
        found_warning = true
        break
      end
    end
    assert.is_truthy(found_warning, "Should show warning about using :ZPack! load")
  end)

  it("ZPack! load loads all unloaded plugins", function()
    local state = require('zpack.state')
    local config_called = {}

    require('zpack').setup({
      spec = {
        {
          'test/plugin-a',
          cmd = 'TestA',
          config = function() config_called['plugin-a'] = true end,
        },
        {
          'test/plugin-b',
          cmd = 'TestB',
          config = function() config_called['plugin-b'] = true end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(2, vim.tbl_count(helpers.unloaded_plugin_names()))

    vim.cmd('ZPack! load')
    helpers.flush_pending()

    assert.are.equal(0, vim.tbl_count(helpers.unloaded_plugin_names()))
    assert.is_truthy(config_called['plugin-a'], "Plugin A config should be called")
    assert.is_truthy(config_called['plugin-b'], "Plugin B config should be called")
  end)

  it("ZPack! load with no unloaded plugins shows info message", function()
    require('zpack').setup({
      spec = {
        {
          'test/startup-plugin',
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZPack! load')
    helpers.flush_pending()

    local found_info = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('All plugins are already loaded') and notif.level == vim.log.levels.INFO then
        found_info = true
        break
      end
    end
    assert.is_truthy(found_info, "Should show info that all plugins are loaded")
  end)

  it("load already-loaded plugin shows info message", function()
    require('zpack').setup({
      spec = {
        {
          'test/startup-plugin',
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    pcall(vim.cmd, 'ZPack load startup-plugin')
    helpers.flush_pending()

    local found_info = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('already loaded') and notif.level == vim.log.levels.INFO then
        found_info = true
        break
      end
    end
    assert.is_truthy(found_info, "Should show info that plugin is already loaded")
  end)

  it("load! goes through startup plugins, then lazy ones, each by priority", function()
    local order = {}
    local function log(name) return function() order[#order + 1] = name end end
    local status = {}
    local packadd = vim.cmd.packadd
    local fail_once = { ['eager-bad'] = true, ['eager-bad2'] = true }
    vim.cmd.packadd = function(args)
      if fail_once[args[1]] then
        fail_once[args[1]] = nil
        error('once', 0)
      end
      return packadd(args)
    end
    require('zpack').setup({
      spec = {
        { 'test/lazy-low', lazy = true, priority = 10, config = log('lazy-low') },
        { 'test/lazy-high', lazy = true, priority = 90, config = log('lazy-high') },
        { 'test/eager-bad', lazy = false, priority = 90, config = log('eager-bad') },
        { 'test/eager-bad2', lazy = false, priority = 10, config = log('eager-bad2') },
        { 'test/off', lazy = true, cond = false, config = log('off') },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    status.before = vim.tbl_keys(helpers.unloaded_plugin_names())
    table.sort(status.before)
    assert.are.same({ 'eager-bad', 'eager-bad2', 'lazy-high', 'lazy-low' }, status.before)

    local names = {}
    for _, pack_spec in ipairs(helpers.registered_plugins()) do
      names[#names + 1] = pack_spec.name
    end
    assert.are.same({ 'eager-bad', 'eager-bad2', 'lazy-high', 'lazy-low' }, names)

    vim.cmd('ZPack! load')
    helpers.flush_pending()
    assert.are.same({ 'eager-bad', 'eager-bad2', 'lazy-high', 'lazy-low' }, order)
  end)

  it("completes names from what's registered, with zpack.nvim, without cond = false", function()
    require('zpack').setup({
      spec = {
        { 'test/Bravo', lazy = true, build = 'x' },
        { 'test/alpha', lazy = true },
        { 'test/off', lazy = true, cond = false, build = 'x' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local function complete(line)
      return vim.fn.getcompletion(line, 'cmdline')
    end
    assert.are.same({ 'alpha', 'Bravo', 'zpack.nvim' }, complete('ZPack update '))
    assert.are.same({ 'alpha', 'Bravo' }, complete('ZPack load '))
    assert.are.same({ 'Bravo' }, complete('ZPack build '))

    vim.cmd('ZPack load alpha')
    helpers.flush_pending()
    assert.are.same({ 'Bravo' }, complete('ZPack load '))
    assert.are.same({ 'alpha', 'Bravo', 'zpack.nvim' }, complete('ZPack reload '))

    vim.pack.del({ 'alpha' })
    helpers.flush_pending()
    assert.are.same({ 'Bravo', 'zpack.nvim' }, complete('ZPack update '))
  end)
end)
