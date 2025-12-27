local helpers = require('helpers')

return function()
  helpers.describe("Conditional Loading", function()
    helpers.test("enabled=false prevents plugin registration", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        enabled = false,
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_nil(state.spec_registry[src], "Plugin should not be registered when enabled=false")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("enabled=true allows plugin registration", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        enabled = true,
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_not_nil(state.spec_registry[src], "Plugin should be registered when enabled=true")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("enabled function returning false prevents registration", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        enabled = function() return false end,
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_nil(
          state.spec_registry[src],
          "Plugin should not be registered when enabled function returns false"
        )
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("enabled function returning true allows registration", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        enabled = function() return true end,
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_not_nil(
          state.spec_registry[src],
          "Plugin should be registered when enabled function returns true"
        )
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("cond=false prevents plugin loading", function()
      helpers.setup_test_env()
      local utils = require('zpack.utils')

      local spec = {
        'test/plugin',
        cond = false,
      }

      local should_load = utils.check_cond(spec)
      helpers.assert_false(should_load, "Plugin should not load when cond=false")

      helpers.cleanup_test_env()
    end)

    helpers.test("cond=true allows plugin loading", function()
      helpers.setup_test_env()
      local utils = require('zpack.utils')

      local spec = {
        'test/plugin',
        cond = true,
      }

      local should_load = utils.check_cond(spec)
      helpers.assert_true(should_load, "Plugin should load when cond=true")

      helpers.cleanup_test_env()
    end)

    helpers.test("cond function returning false prevents loading", function()
      helpers.setup_test_env()
      local utils = require('zpack.utils')

      local spec = {
        'test/plugin',
        cond = function() return false end,
      }

      local should_load = utils.check_cond(spec)
      helpers.assert_false(should_load, "Plugin should not load when cond function returns false")

      helpers.cleanup_test_env()
    end)

    helpers.test("cond function returning true allows loading", function()
      helpers.setup_test_env()
      local utils = require('zpack.utils')

      local spec = {
        'test/plugin',
        cond = function() return true end,
      }

      local should_load = utils.check_cond(spec)
      helpers.assert_true(should_load, "Plugin should load when cond function returns true")

      helpers.cleanup_test_env()
    end)

    helpers.test("cond nil defaults to true", function()
      helpers.setup_test_env()
      local utils = require('zpack.utils')

      local spec = {
        'test/plugin',
      }

      local should_load = utils.check_cond(spec)
      helpers.assert_true(should_load, "Plugin should load when cond is nil (default true)")

      helpers.cleanup_test_env()
    end)

    helpers.test("enabled and cond work together", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        enabled = true,
        cond = false,
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_not_nil(
          state.spec_registry[src],
          "Plugin should be registered (enabled=true)"
        )

        local utils = require('zpack.utils')
        local should_load = utils.check_cond(state.spec_registry[src].spec)
        helpers.assert_false(should_load, "Plugin should not load (cond=false)")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("enabled prevents config execution", function()
      helpers.setup_test_env()
      local config_ran = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        enabled = false,
        config = function()
          config_ran = true
        end,
      })

      vim.schedule(function()
        helpers.assert_false(config_ran, "Config should not run when enabled=false")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("lazy=false overrides lazy triggers", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        cmd = 'TestCommand',
        lazy = false,
      }

      helpers.assert_false(lazy_module.is_lazy(spec), "Plugin should not be lazy when lazy=false")

      helpers.cleanup_test_env()
    end)

    helpers.test("lazy=true forces lazy loading even without triggers", function()
      helpers.setup_test_env()
      local lazy_module = require('zpack.lazy')

      local spec = {
        'test/plugin',
        lazy = true,
      }

      helpers.assert_true(lazy_module.is_lazy(spec), "Plugin should be lazy when lazy=true")

      helpers.cleanup_test_env()
    end)
  end)
end
