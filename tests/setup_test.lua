local helpers = require('helpers')

return function()
  helpers.describe("Setup and Initialization", function()
    helpers.test("setup() initializes zpack state", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      helpers.assert_false(state.is_setup, "State should not be setup initially")

      require('zpack').setup({ auto_import = false, confirm = false })

      helpers.assert_true(state.is_setup, "State should be setup after setup()")
      helpers.assert_not_nil(state.spec_registry, "Spec registry should exist")
      helpers.assert_not_nil(state.lazy_group, "Lazy group should exist")
      helpers.assert_not_nil(state.startup_group, "Startup group should exist")

      helpers.cleanup_test_env()
    end)

    helpers.test("setup() cannot be called twice", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false, confirm = false })
      helpers.assert_true(state.is_setup, "State should be setup after first call")

      -- Second call should still work but state should remain setup
      require('zpack').setup({ auto_import = false, confirm = false })
      helpers.assert_true(state.is_setup, "State should still be setup after second call")

      helpers.cleanup_test_env()
    end)

    helpers.test("add() requires setup() to be called first", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      helpers.assert_false(state.is_setup, "State should not be setup initially")

      -- This should not crash but also should not work
      require('zpack').add({ 'test/plugin' })

      helpers.cleanup_test_env()
    end)

    helpers.test("add() registers single plugin spec", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false, confirm = false })

      -- Give the initial spec import flag time to be set
      state.initial_spec_imported = true

      require('zpack').add({ 'test/plugin' })

      -- Wait a bit for vim.schedule to run
      vim.wait(100, function() return false end)

      local src = 'https://github.com/test/plugin'
      helpers.assert_not_nil(state.spec_registry[src], "Plugin should be registered")
      helpers.assert_equal(state.spec_registry[src].spec[1], 'test/plugin', "Spec should match")

      helpers.cleanup_test_env()
    end)

    helpers.test("add() registers multiple plugin specs", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false, confirm = false })
      state.initial_spec_imported = true

      require('zpack').add({
        { 'test/plugin1' },
        { 'test/plugin2' },
      })

      vim.wait(100, function() return false end)

      local src1 = 'https://github.com/test/plugin1'
      local src2 = 'https://github.com/test/plugin2'
      helpers.assert_not_nil(state.spec_registry[src1], "Plugin 1 should be registered")
      helpers.assert_not_nil(state.spec_registry[src2], "Plugin 2 should be registered")

      helpers.cleanup_test_env()
    end)

    helpers.test("plugin spec supports src field", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false, confirm = false })
      state.initial_spec_imported = true

      require('zpack').add({
        src = 'https://custom.url/plugin.git'
      })

      vim.wait(100, function() return false end)

      local src = 'https://custom.url/plugin.git'
      helpers.assert_not_nil(state.spec_registry[src], "Plugin with src should be registered")

      helpers.cleanup_test_env()
    end)

    helpers.test("plugin spec supports url field (lazy.nvim compat)", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false, confirm = false })
      state.initial_spec_imported = true

      require('zpack').add({
        url = 'https://custom.url/plugin.git'
      })

      vim.wait(100, function() return false end)

      local src = 'https://custom.url/plugin.git'
      helpers.assert_not_nil(state.spec_registry[src], "Plugin with url should be registered")

      helpers.cleanup_test_env()
    end)

    helpers.test("plugin spec supports dir field (lazy.nvim compat)", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false, confirm = false })
      state.initial_spec_imported = true

      require('zpack').add({
        dir = '/path/to/local/plugin'
      })

      vim.wait(100, function() return false end)

      local src = '/path/to/local/plugin'
      helpers.assert_not_nil(state.spec_registry[src], "Plugin with dir should be registered")

      helpers.cleanup_test_env()
    end)
  end)
end
