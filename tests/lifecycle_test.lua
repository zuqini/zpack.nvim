local helpers = require('helpers')

return function()
  helpers.describe("Plugin Lifecycle Hooks", function()
    helpers.test("init hook runs before plugin loads", function()
      helpers.setup_test_env()
      local init_ran = false
      local config_ran = false
      local init_ran_before_config = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        init = function()
          init_ran = true
          if not config_ran then
            init_ran_before_config = true
          end
        end,
        config = function()
          config_ran = true
        end,
      })

      vim.schedule(function()
        helpers.assert_true(init_ran, "init hook should run")
        helpers.assert_true(init_ran_before_config, "init should run before config")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("config hook runs after plugin loads", function()
      helpers.setup_test_env()
      local config_ran = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        config = function()
          config_ran = true
        end,
      })

      vim.schedule(function()
        helpers.assert_true(config_ran, "config hook should run")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("init runs for lazy plugins at setup time", function()
      helpers.setup_test_env()
      local init_ran = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        cmd = 'TestCommand',
        init = function()
          init_ran = true
        end,
      })

      vim.schedule(function()
        helpers.assert_true(init_ran, "init should run for lazy plugins at setup time")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("config does not run for lazy plugins at setup time", function()
      helpers.setup_test_env()
      local config_ran = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        cmd = 'TestCommand',
        config = function()
          config_ran = true
        end,
      })

      vim.schedule(function()
        helpers.assert_false(config_ran, "config should not run for lazy plugins at setup time")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("build hook is string command", function()
      helpers.setup_test_env()

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        build = 'echo "build completed"',
      })

      vim.schedule(function()
        local state = require('zpack.state')
        local src = 'https://github.com/test/plugin'
        helpers.assert_not_nil(state.spec_registry[src].spec.build, "Build hook should be stored")
        helpers.assert_equal(
          type(state.spec_registry[src].spec.build),
          'string',
          "Build hook should be string"
        )
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("build hook is function", function()
      helpers.setup_test_env()
      local build_fn = function() end

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        build = build_fn,
      })

      vim.schedule(function()
        local state = require('zpack.state')
        local src = 'https://github.com/test/plugin'
        helpers.assert_not_nil(state.spec_registry[src].spec.build, "Build hook should be stored")
        helpers.assert_equal(
          type(state.spec_registry[src].spec.build),
          'function',
          "Build hook should be function"
        )
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("init and config hooks work together", function()
      helpers.setup_test_env()
      local execution_order = {}

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        init = function()
          table.insert(execution_order, 'init')
        end,
        config = function()
          table.insert(execution_order, 'config')
        end,
      })

      vim.schedule(function()
        helpers.assert_equal(#execution_order, 2, "Both hooks should run")
        helpers.assert_equal(execution_order[1], 'init', "init should run first")
        helpers.assert_equal(execution_order[2], 'config', "config should run second")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("config hook can access plugin module", function()
      helpers.setup_test_env()
      local can_access_globals = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        config = function()
          can_access_globals = (vim ~= nil and vim.fn ~= nil)
        end,
      })

      vim.schedule(function()
        helpers.assert_true(can_access_globals, "config should have access to vim globals")
      end)

      helpers.cleanup_test_env()
    end)
  end)
end
