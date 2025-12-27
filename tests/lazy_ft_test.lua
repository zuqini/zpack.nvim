local helpers = require('helpers')

return function()
  helpers.describe("Lazy Loading - FileType", function()
    helpers.test("single filetype creates FileType autocmd", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        ft = 'rust',
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found = false
        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'FileType' and vim.tbl_contains(cmd.pattern or {}, 'rust') then
            found = true
            break
          end
        end
        helpers.assert_true(found, "Single filetype should create FileType autocmd")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("multiple filetypes create FileType autocmd with all patterns", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        ft = { 'lua', 'vim', 'python' },
      })

      vim.schedule(function()
        local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
        local found_lua = false
        local found_vim = false
        local found_python = false

        for _, cmd in ipairs(autocmds) do
          if cmd.event == 'FileType' then
            local patterns = cmd.pattern or {}
            if vim.tbl_contains(patterns, 'lua') then found_lua = true end
            if vim.tbl_contains(patterns, 'vim') then found_vim = true end
            if vim.tbl_contains(patterns, 'python') then found_python = true end
          end
        end

        helpers.assert_true(found_lua or found_vim or found_python,
          "Multiple filetypes should create FileType autocmd")
      end)

      helpers.cleanup_test_env()
    end)

    helpers.test("lazy ft plugin does not load at startup", function()
      helpers.setup_test_env()
      local state = require('zpack.state')

      require('zpack').setup({ auto_import = false })
      require('zpack').add({
        'test/plugin',
        ft = 'lua',
      })

      vim.schedule(function()
        local src = 'https://github.com/test/plugin'
        helpers.assert_false(
          state.spec_registry[src].loaded,
          "Lazy ft plugin should not be loaded at startup"
        )
      end)

      helpers.cleanup_test_env()
    end)
  end)
end
