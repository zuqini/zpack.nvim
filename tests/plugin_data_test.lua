local helpers = require('helpers')

return function()
  helpers.describe("Plugin Data (zpack.Plugin)", function()
    helpers.test("plugin object is stored in registry after registration", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_not_nil(state.spec_registry[src], "Plugin should be registered")
        helpers.assert_not_nil(state.spec_registry[src].plugin, "Plugin data should be stored")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("plugin object has spec field", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        local plugin = state.spec_registry[src].plugin
        helpers.assert_not_nil(plugin, "Plugin data should exist")
        helpers.assert_not_nil(plugin.spec, "Plugin should have spec field")
        helpers.assert_not_nil(plugin.spec.src, "Plugin spec should have src")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("plugin object has path field", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        local plugin = state.spec_registry[src].plugin
        helpers.assert_not_nil(plugin, "Plugin data should exist")
        helpers.assert_not_nil(plugin.path, "Plugin should have path field")
        helpers.assert_equal(type(plugin.path), 'string', "Plugin path should be a string")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("config hook receives plugin argument", function()
      helpers.setup_test_env()
      local received_plugin = nil

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        config = function(plugin)
          received_plugin = plugin
        end,
      })

      vim.schedule(function()
        helpers.assert_not_nil(received_plugin, "config should receive plugin argument")
        helpers.assert_not_nil(received_plugin.spec, "plugin should have spec")
        helpers.assert_not_nil(received_plugin.path, "plugin should have path")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("init hook receives plugin argument", function()
      helpers.setup_test_env()
      local received_plugin = nil

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        init = function(plugin)
          received_plugin = plugin
        end,
      })

      vim.schedule(function()
        helpers.assert_not_nil(received_plugin, "init should receive plugin argument")
        helpers.assert_not_nil(received_plugin.spec, "plugin should have spec")
        helpers.assert_not_nil(received_plugin.path, "plugin should have path")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("cond function receives plugin argument", function()
      helpers.setup_test_env()
      local received_plugin = nil

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        cond = function(plugin)
          received_plugin = plugin
          return true
        end,
      })

      vim.schedule(function()
        helpers.assert_not_nil(received_plugin, "cond should receive plugin argument")
        helpers.assert_not_nil(received_plugin.spec, "plugin should have spec")
        helpers.assert_not_nil(received_plugin.path, "plugin should have path")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("cond function can use plugin.path", function()
      helpers.setup_test_env()
      local path_received = nil

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        cond = function(plugin)
          path_received = plugin.path
          return true
        end,
      })

      vim.schedule(function()
        helpers.assert_not_nil(path_received, "cond should receive plugin.path")
        helpers.assert_equal(type(path_received), 'string', "plugin.path should be a string")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("cmd can be a function returning commands", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        cmd = function(plugin)
          return { 'TestCmd1', 'TestCmd2' }
        end,
      }

      local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
      helpers.assert_true(lazy_module.is_lazy(spec, mock_plugin), "Plugin with cmd function should be lazy")

      helpers.cleanup_test_env()
    end)

    helpers.test("event can be a function returning events", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        event = function(plugin)
          return 'VeryLazy'
        end,
      }

      local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
      helpers.assert_true(lazy_module.is_lazy(spec, mock_plugin), "Plugin with event function should be lazy")

      helpers.cleanup_test_env()
    end)

    helpers.test("ft can be a function returning filetypes", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        ft = function(plugin)
          return { 'lua', 'vim' }
        end,
      }

      local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
      helpers.assert_true(lazy_module.is_lazy(spec, mock_plugin), "Plugin with ft function should be lazy")

      helpers.cleanup_test_env()
    end)

    helpers.test("keys can be a function returning keymaps", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        keys = function(plugin)
          return { { '<leader>t', function() end, desc = 'Test' } }
        end,
      }

      local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
      helpers.assert_true(lazy_module.is_lazy(spec, mock_plugin), "Plugin with keys function should be lazy")

      helpers.cleanup_test_env()
    end)

    helpers.test("function trigger returning nil means not lazy", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        cmd = function(plugin)
          return nil
        end,
      }

      local mock_plugin = { spec = { src = 'test' }, path = '/mock/path' }
      helpers.assert_false(lazy_module.is_lazy(spec, mock_plugin), "Plugin with cmd function returning nil should not be lazy")

      helpers.cleanup_test_env()
    end)

    helpers.test("cmd function receives plugin and returns value", function()
      helpers.setup_test_env()
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

      helpers.assert_not_nil(received_plugin, "cmd function should receive plugin")
      helpers.assert_equal(received_plugin.path, '/mock/path', "plugin.path should match")

      helpers.cleanup_test_env()
    end)

    helpers.test("startup plugin keys can be a function", function()
      helpers.setup_test_env()
      local keys_called = false
      local received_plugin = nil

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        lazy = false,
        keys = function(plugin)
          keys_called = true
          received_plugin = plugin
          return { { '<leader>test', function() end } }
        end,
      })

      vim.schedule(function()
        helpers.assert_true(keys_called, "keys function should be called for startup plugin")
        helpers.assert_not_nil(received_plugin, "keys function should receive plugin")
      end)

      helpers.cleanup_test_env()
    end)
  end)
end
