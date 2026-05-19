local helpers = require('helpers')

describe("Plugin Data (zpack.Plugin)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("plugin object is stored in registry after registration", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin should be registered")
    assert.is_not_nil(state.spec_registry[src].plugin, "Plugin data should be stored")
  end)

  it("plugin object has spec field", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    local plugin = state.spec_registry[src].plugin
    assert.is_not_nil(plugin, "Plugin data should exist")
    assert.is_not_nil(plugin.spec, "Plugin should have spec field")
    assert.is_not_nil(plugin.spec.src, "Plugin spec should have src")
  end)

  it("plugin object has path field", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    local plugin = state.spec_registry[src].plugin
    assert.is_not_nil(plugin, "Plugin data should exist")
    assert.is_not_nil(plugin.path, "Plugin should have path field")
    assert.are.equal('string', type(plugin.path))
  end)

  it("config hook receives plugin argument", function()
    local received_plugin = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function(plugin)
            received_plugin = plugin
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_plugin, "config should receive plugin argument")
    assert.is_not_nil(received_plugin.spec, "plugin should have spec")
    assert.is_not_nil(received_plugin.path, "plugin should have path")
  end)

  it("init hook receives plugin argument", function()
    local received_plugin = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          init = function(plugin)
            received_plugin = plugin
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_plugin, "init should receive plugin argument")
    assert.is_not_nil(received_plugin.spec, "plugin should have spec")
    assert.is_not_nil(received_plugin.path, "plugin should have path")
  end)

  it("cond function receives plugin argument", function()
    local received_plugin = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cond = function(plugin)
            received_plugin = plugin
            return true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_plugin, "cond should receive plugin argument")
    assert.is_not_nil(received_plugin.spec, "plugin should have spec")
    assert.is_not_nil(received_plugin.path, "plugin should have path")
  end)

  it("cond function can use plugin.path", function()
    local path_received = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cond = function(plugin)
            path_received = plugin.path
            return true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(path_received, "cond should receive plugin.path")
    assert.are.equal('string', type(path_received))
  end)

  it("cmd can be a function returning commands", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      cmd = function(plugin)
        return { 'TestCmd1', 'TestCmd2' }
      end,
    }

    local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
    assert.is_truthy(lazy_module.is_lazy(spec, mock_plugin), "Plugin with cmd function should be lazy")
  end)

  it("event can be a function returning events", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      event = function(plugin)
        return 'VeryLazy'
      end,
    }

    local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
    assert.is_truthy(lazy_module.is_lazy(spec, mock_plugin), "Plugin with event function should be lazy")
  end)

  it("ft can be a function returning filetypes", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      ft = function(plugin)
        return { 'lua', 'vim' }
      end,
    }

    local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
    assert.is_truthy(lazy_module.is_lazy(spec, mock_plugin), "Plugin with ft function should be lazy")
  end)

  it("keys can be a function returning keymaps", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      keys = function(plugin)
        return { { '<leader>t', function() end, desc = 'Test' } }
      end,
    }

    local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
    assert.is_truthy(lazy_module.is_lazy(spec, mock_plugin), "Plugin with keys function should be lazy")
  end)

  it("function trigger returning nil means not lazy", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      cmd = function(plugin)
        return nil
      end,
    }

    local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
    assert.is_falsy(lazy_module.is_lazy(spec, mock_plugin), "Plugin with cmd function returning nil should not be lazy")
  end)

  it("cmd function receives plugin and returns value", function()
    local received_plugin = nil
    local returned_cmds = { 'TestCommand' }

    local spec = {
      'test/plugin',
      cmd = function(plugin)
        received_plugin = plugin
        return returned_cmds
      end,
    }

    local mock_plugin = { spec = { src = 'test', name = 'plugin' }, path = '/mock/path' }
    local lazy_module = require('zpack.lazy')
    lazy_module.is_lazy(spec, mock_plugin)

    assert.is_not_nil(received_plugin, "cmd function should receive plugin")
    assert.are.equal('/mock/path', received_plugin.path)
  end)

  it("startup plugin keys can be a function", function()
    local keys_called = false
    local received_plugin = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = function(plugin)
            keys_called = true
            received_plugin = plugin
            return { { '<leader>test', function() end } }
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(keys_called, "keys function should be called for startup plugin")
    assert.is_not_nil(received_plugin, "keys function should receive plugin")
  end)
end)
