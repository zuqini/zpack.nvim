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
      state.unloaded_plugin_names['lazy-plugin'] == true,
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
      state.unloaded_plugin_names['startup-plugin'],
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
      state.unloaded_plugin_names['lazy-plugin'] == true,
      "Plugin should be unloaded initially"
    )

    pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()

    assert.is_nil(
      state.unloaded_plugin_names['lazy-plugin'],
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
    assert.are.equal(2, vim.tbl_count(state.unloaded_plugin_names))

    vim.cmd('ZPack! load')
    helpers.flush_pending()

    assert.are.equal(0, vim.tbl_count(state.unloaded_plugin_names))
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
end)
