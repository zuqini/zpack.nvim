local helpers = require('helpers')

return function()
  helpers.describe("Lazy Loading - Events", function()
    helpers.test("inline event pattern is parsed correctly", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = 'BufReadPre *.lua',
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found = false
        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'BufReadPre' and vim.tbl_contains(cmd.pattern or {}, '*.lua') then
            found = true
            break
          end
        end
        helpers.assert_true(found, "Inline event pattern should create autocmd")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("EventSpec with pattern creates autocmd with pattern", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = {
          event = 'BufRead',
          pattern = '*.rs',
        },
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found = false
        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'BufRead' and vim.tbl_contains(cmd.pattern or {}, '*.rs') then
            found = true
            break
          end
        end
        helpers.assert_true(found, "EventSpec pattern should create autocmd with pattern")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("EventSpec with multiple patterns creates autocmd", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = {
          event = 'BufRead',
          pattern = { '*.lua', '*.vim' },
        },
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found = false
        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'BufRead' then
            local patterns = cmd.pattern or {}
            if vim.tbl_contains(patterns, '*.lua') or vim.tbl_contains(patterns, '*.vim') then
              found = true
              break
            end
          end
        end
        helpers.assert_true(found, "EventSpec with multiple patterns should create autocmd")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("global pattern fallback is applied to events", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = 'BufRead',
        pattern = '*.md',
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found = false
        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'BufRead' and vim.tbl_contains(cmd.pattern or {}, '*.md') then
            found = true
            break
          end
        end
        helpers.assert_true(found, "Global pattern should be applied to events")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("VeryLazy event creates UIEnter autocmd", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = 'VeryLazy',
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found = false
        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'UIEnter' then
            found = true
            break
          end
        end
        helpers.assert_true(found, "VeryLazy should create UIEnter autocmd")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("multiple EventSpecs with different patterns", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = {
          { event = 'BufReadPre', pattern = '*.lua' },
          { event = 'BufNewFile', pattern = '*.rs' },
        },
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found_lua = false
        local found_rs = false

        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'BufReadPre' and vim.tbl_contains(cmd.pattern or {}, '*.lua') then
            found_lua = true
          end
          if cmd.event == 'BufNewFile' and vim.tbl_contains(cmd.pattern or {}, '*.rs') then
            found_rs = true
          end
        end

        helpers.assert_true(found_lua, "Should create BufReadPre autocmd with *.lua pattern")
        helpers.assert_true(found_rs, "Should create BufNewFile autocmd with *.rs pattern")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("lazy event plugin does not load at startup", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        event = 'BufRead',
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_false(
          state.spec_registry[src].loaded,
          "Lazy event plugin should not be loaded at startup"
        )
      end)

      helpers.cleanup_test_env()
    end)
  end)
end
