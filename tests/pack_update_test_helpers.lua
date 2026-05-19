local helpers = require('helpers')
local assert = require('luassert')

-- Parameterised test bodies shared by zupdate_test.lua and zrestore_test.lua.
-- This module is require'd, not discovered as a busted spec (its filename is
-- deliberately not *_test.lua), so it pulls in luassert explicitly rather than
-- relying on the `assert` global busted injects only into spec files.
local M = {}

---Build the shared :ZPack update / :ZPack restore cases for a command.
---@param config table { command, expected_opts, error_prefix, supports_bang }
---@return table[] list of { name = string, fn = function } busted cases
function M.cases(config)
  local command = config.command
  local expected_opts = config.expected_opts
  local error_prefix = config.error_prefix

  local cases = {}

  cases[#cases + 1] = {
    name = command .. " without args calls vim.pack.update correctly",
    fn = function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a' },
          { 'test/plugin-b' },
        },
        defaults = { confirm = false },
      })

      helpers.flush_pending()

      vim.cmd(command)
      helpers.flush_pending()

      assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
      local call = _G.test_state.vim_pack_update_calls[1]
      assert.is_nil(call.names, "names should be nil for all")
      if expected_opts then
        assert.is_not_nil(call.opts, "opts should be passed")
        for k, v in pairs(expected_opts) do
          assert.are.equal(v, call.opts[k])
        end
      else
        assert.is_nil(call.opts, "opts should be nil")
      end
    end,
  }

  cases[#cases + 1] = {
    name = command .. " with plugin name targets that plugin",
    fn = function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a' },
          { 'test/plugin-b' },
        },
        defaults = { confirm = false },
      })

      helpers.flush_pending()

      vim.cmd(command .. ' plugin-a')
      helpers.flush_pending()

      assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
      local call = _G.test_state.vim_pack_update_calls[1]
      assert.is_not_nil(call.names, "names should be provided")
      assert.contains(call.names, 'plugin-a')
      if expected_opts then
        for k, v in pairs(expected_opts) do
          assert.are.equal(v, call.opts[k])
        end
      else
        assert.is_nil(call.opts, "opts should be nil")
      end
    end,
  }

  cases[#cases + 1] = {
    name = command .. " with registered but not installed plugin still calls vim.pack.update",
    fn = function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a' },
          { 'test/plugin-b' },
        },
        defaults = { confirm = false },
      })

      helpers.flush_pending()

      _G.test_state.registered_pack_specs['plugin-a'] = nil

      vim.cmd(command .. ' plugin-a')
      helpers.flush_pending()

      assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
      local call = _G.test_state.vim_pack_update_calls[1]
      assert.is_not_nil(call.names, "names should be provided")
      assert.contains(call.names, 'plugin-a')
    end,
  }

  cases[#cases + 1] = {
    name = command .. " with plugin not in spec shows error",
    fn = function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a' },
        },
        defaults = { confirm = false },
      })

      helpers.flush_pending()

      vim.cmd(command .. ' non-existent-plugin')
      helpers.flush_pending()

      assert.are.equal(0, #_G.test_state.vim_pack_update_calls)

      local found_error = false
      for _, notif in ipairs(_G.test_state.notifications) do
        if notif.msg:find('not found in spec') and notif.level == vim.log.levels.ERROR then
          found_error = true
          break
        end
      end
      assert.is_truthy(found_error, "should notify error for plugin not in spec")
    end,
  }

  cases[#cases + 1] = {
    name = command .. " tab completion returns registered plugin names",
    fn = function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a' },
          { 'test/plugin-b' },
        },
        defaults = { confirm = false },
      })

      helpers.flush_pending()

      local completions = vim.fn.getcompletion(command .. ' ', 'cmdline')
      assert.contains(completions, 'plugin-a')
      assert.contains(completions, 'plugin-b')
    end,
  }

  if config.supports_bang then
    local bang_command = command:gsub('^(%S+)', '%1!')

    cases[#cases + 1] = {
      name = bang_command .. " passes force=true to vim.pack.update",
      fn = function()
        require('zpack').setup({
          spec = {
            { 'test/plugin-a' },
            { 'test/plugin-b' },
          },
          defaults = { confirm = false },
        })

        helpers.flush_pending()

        vim.cmd(bang_command)
        helpers.flush_pending()

        assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
        local call = _G.test_state.vim_pack_update_calls[1]
        assert.is_nil(call.names, "names should be nil for all")
        assert.is_not_nil(call.opts, "opts should be passed with bang")
        assert.are.equal(true, call.opts.force)
        if expected_opts then
          for k, v in pairs(expected_opts) do
            assert.are.equal(v, call.opts[k])
          end
        end
      end,
    }

    cases[#cases + 1] = {
      name = bang_command .. " with plugin name passes force=true and targets that plugin",
      fn = function()
        require('zpack').setup({
          spec = {
            { 'test/plugin-a' },
            { 'test/plugin-b' },
          },
          defaults = { confirm = false },
        })

        helpers.flush_pending()

        vim.cmd(bang_command .. ' plugin-a')
        helpers.flush_pending()

        assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
        local call = _G.test_state.vim_pack_update_calls[1]
        assert.contains(call.names, 'plugin-a')
        assert.is_not_nil(call.opts, "opts should be passed with bang")
        assert.are.equal(true, call.opts.force)
        if expected_opts then
          for k, v in pairs(expected_opts) do
            assert.are.equal(v, call.opts[k])
          end
        end
      end,
    }
  end

  if expected_opts and expected_opts.target == 'lockfile' then
    cases[#cases + 1] = {
      name = command .. " shows error when no lockfile exists",
      fn = function()
        require('zpack').setup({
          spec = {
            { 'test/plugin-a' },
          },
          defaults = { confirm = false },
        })

        helpers.flush_pending()

        local call_log = _G.test_state.vim_pack_update_calls
        local prev_update = vim.pack.update
        vim.pack.update = function(names, opts)
          table.insert(call_log, { names = names, opts = opts })
          error("no lockfile found")
        end

        vim.cmd(command)
        vim.pack.update = prev_update
        helpers.flush_pending()

        local found_error = false
        for _, notif in ipairs(_G.test_state.notifications) do
          if notif.msg:find(error_prefix) and notif.msg:find('lockfile') and notif.level == vim.log.levels.ERROR then
            found_error = true
            break
          end
        end
        assert.is_truthy(found_error, "should notify error when no lockfile exists")
      end,
    }
  end

  cases[#cases + 1] = {
    name = command .. " shows friendly error when vim.pack.update fails",
    fn = function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a' },
        },
        defaults = { confirm = false },
      })

      helpers.flush_pending()

      local call_log = _G.test_state.vim_pack_update_calls
      local prev_update = vim.pack.update
      vim.pack.update = function(names, opts)
        table.insert(call_log, { names = names, opts = opts })
        error("simulated failure")
      end

      vim.cmd(command)
      vim.pack.update = prev_update
      helpers.flush_pending()

      local found_error = false
      for _, notif in ipairs(_G.test_state.notifications) do
        if notif.msg:find(error_prefix) and notif.level == vim.log.levels.ERROR then
          found_error = true
          break
        end
      end
      assert.is_truthy(found_error, "should notify friendly error when vim.pack.update fails")
    end,
  }

  return cases
end

return M
