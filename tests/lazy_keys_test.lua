local helpers = require('helpers')

return function()
  helpers.describe("Lazy Loading - Keymaps", function()
    helpers.test("KeySpec supports string shorthand", function()
      helpers.setup_test_env()
      local loaded = false

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        keys = '<leader>tk',
        config = function()
          loaded = true
        end,
      })

      vim.schedule(function()
        local keymaps = vim.api.nvim_get_keymap('n')
        local found = false
        for _, map in ipairs(keymaps) do
          if map.lhs == ' tk' then
            found = true
            break
          end
        end
        helpers.assert_true(found, "String key should create keymap")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("KeySpec supports table format with desc", function()
      helpers.setup_test_env()

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        keys = {
          { '<leader>td', function() end, desc = 'Test description' },
        },
      })

      vim.schedule(function()
        local keymaps = vim.api.nvim_get_keymap('n')
        local found_with_desc = false
        for _, map in ipairs(keymaps) do
          if map.lhs == ' td' and map.desc == 'Test description' then
            found_with_desc = true
            break
          end
        end
        helpers.assert_true(found_with_desc, "KeySpec should create keymap with description")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("KeySpec supports custom modes", function()
      helpers.setup_test_env()

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        keys = {
          { '<leader>tv', function() end, mode = { 'n', 'v' } },
        },
      })

      vim.schedule(function()
        local normal_maps = vim.api.nvim_get_keymap('n')
        local visual_maps = vim.api.nvim_get_keymap('v')

        local found_in_normal = false
        local found_in_visual = false

        for _, map in ipairs(normal_maps) do
          if map.lhs == ' tv' then
            found_in_normal = true
            break
          end
        end

        for _, map in ipairs(visual_maps) do
          if map.lhs == ' tv' then
            found_in_visual = true
            break
          end
        end

        helpers.assert_true(found_in_normal, "KeySpec should create keymap in normal mode")
        helpers.assert_true(found_in_visual, "KeySpec should create keymap in visual mode")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("lazy keys plugin does not load at startup", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        keys = '<leader>tl',
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_false(
          state.spec_registry[src].loaded,
          "Lazy keys plugin should not be loaded at startup"
        )
      end)

      helpers.cleanup_test_env()
    end)
  end)
end
