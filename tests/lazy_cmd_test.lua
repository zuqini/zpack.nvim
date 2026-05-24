local helpers = require('helpers')

describe("Lazy Loading - Commands", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("plugin with cmd creates command placeholder", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.TestCommand, "Command should be created")
  end)

  it("plugin with multiple cmds creates all commands", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = { 'TestCmd1', 'TestCmd2', 'TestCmd3' },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.TestCmd1, "Command 1 should be created")
    assert.is_not_nil(commands.TestCmd2, "Command 2 should be created")
    assert.is_not_nil(commands.TestCmd3, "Command 3 should be created")
  end)

  it("lazy cmd plugin does not load at startup", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)
  end)

  it("plugin loads when command is invoked", function()
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()
    assert.is_truthy(loaded, "Plugin should load when command is invoked")
  end)

  it("plugin loads when command is invoked with args", function()
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    pcall(vim.cmd, 'TestCommand somearg')
    helpers.flush_pending()
    assert.is_truthy(loaded, "Plugin should load when command is invoked with args")
  end)

  -- The proxy is registered permissively so the cmdline parser accepts every
  -- form the real command might support. Without bang/count on the proxy,
  -- invocations like :Foo! / :1,5Foo / :5Foo error at parse time before the
  -- callback runs, and the plugin is never loaded.
  it("Lazy proxy command forwards bang to the real command", function()
    local captured
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestBangCmd',
          config = function()
            vim.api.nvim_create_user_command('TestBangCmd', function(a)
              captured = { bang = a.bang, args = a.args }
            end, { nargs = '*', bang = true })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.cmd('TestBangCmd! hello')
    helpers.flush_pending()

    assert.is_not_nil(captured, "Real command should run after proxy fires")
    assert.is_true(captured.bang, "Bang should be forwarded to real command")
    assert.are.equal('hello', captured.args)

    pcall(vim.api.nvim_del_user_command, 'TestBangCmd')
  end)

  it("Lazy proxy command forwards range to the real command", function()
    local captured
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestRangeCmd',
          config = function()
            vim.api.nvim_create_user_command('TestRangeCmd', function(a)
              captured = { range = a.range, line1 = a.line1, line2 = a.line2 }
            end, { nargs = '*', range = true })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b', 'c', 'd', 'e' })

    vim.cmd('1,3TestRangeCmd')
    helpers.flush_pending()

    assert.is_not_nil(captured, "Real command should run after proxy fires")
    assert.are.equal(2, captured.range, "Real command should see range=2 for 1,3 form")
    assert.are.equal(1, captured.line1)
    assert.are.equal(3, captured.line2)

    pcall(vim.api.nvim_del_user_command, 'TestRangeCmd')
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("Lazy proxy command forwards count to the real command", function()
    local captured
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCountCmd',
          config = function()
            vim.api.nvim_create_user_command('TestCountCmd', function(a)
              captured = { count = a.count }
            end, { nargs = '*', count = -1 })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.cmd('7TestCountCmd')
    helpers.flush_pending()

    assert.is_not_nil(captured, "Real command should run after proxy fires")
    assert.are.equal(7, captured.count, "Count should be forwarded to real command")

    pcall(vim.api.nvim_del_user_command, 'TestCountCmd')
  end)

  it("Lazy proxy command forwards mods (vertical, silent) to the real command", function()
    local captured
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestModsCmd',
          config = function()
            vim.api.nvim_create_user_command('TestModsCmd', function(a)
              captured = { vertical = a.smods.vertical, silent = a.smods.silent }
            end, { nargs = '*' })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.cmd('silent vertical TestModsCmd')
    helpers.flush_pending()

    assert.is_not_nil(captured, "Real command should run after proxy fires")
    assert.is_true(captured.vertical, "vertical modifier should be forwarded")
    assert.is_true(captured.silent, "silent modifier should be forwarded")

    pcall(vim.api.nvim_del_user_command, 'TestModsCmd')
  end)

  -- Regression (symmetric with lazy_keys_test "Lazy proxy bails on feedkeys
  -- when every plugin fails to load"): when every plugin claiming a cmd
  -- throws on load, the proxy has already deleted itself and no real cmd
  -- has replaced it. nvim_cmd would then raise "Not an editor command",
  -- producing a spurious notify on top of the per-plugin load-failure notify.
  it("Lazy proxy bails on re-fire when every plugin fails to load", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestBailCmd',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local original_packadd = vim.cmd.packadd
    vim.cmd.packadd = function() error("simulated packadd failure", 0) end

    local notify_messages = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_messages, { msg = msg, level = level })
    end

    pcall(vim.cmd, 'TestBailCmd')
    helpers.flush_pending()

    vim.cmd.packadd = original_packadd
    vim.notify = original_notify

    local saw_refire_notify = false
    for _, n in ipairs(notify_messages) do
      if n.msg:match("Failed to re%-fire :TestBailCmd") then
        saw_refire_notify = true
      end
    end
    assert.is_false(saw_refire_notify,
      "Proxy must not attempt nvim_cmd re-fire when every claiming plugin failed to load")
  end)

  -- Bead zpack_nvim-6n2: tab-completion on the lazy proxy must load the
  -- plugin so the user gets real completions on the first <Tab>, matching
  -- lazy.nvim's UX (handler/cmd.lua complete callback).
  it("Lazy proxy command loads plugin on tab-completion", function()
    local loaded = false
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCompleteLoad',
          config = function() loaded = true end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    -- vim.fn.getcompletion invokes the user command's complete callback.
    vim.fn.getcompletion('TestCompleteLoad ', 'cmdline')
    helpers.flush_pending()

    assert.is_true(loaded,
      "Plugin should load when tab-completion is requested on the proxy")
  end)

  -- Bead zpack_nvim-6n2: after the proxy fires its complete callback, the
  -- real command's completions take over so the user sees actual suggestions.
  it("Lazy proxy command returns real completions after load", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestRealComplete',
          config = function()
            vim.api.nvim_create_user_command('TestRealComplete', function() end, {
              nargs = '*',
              complete = function() return { 'apple', 'banana', 'cherry' } end,
            })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local results = vim.fn.getcompletion('TestRealComplete ', 'cmdline')
    helpers.flush_pending()

    assert.is_true(vim.tbl_contains(results, 'apple'),
      "real command's completions should be returned after proxy loads it")
    assert.is_true(vim.tbl_contains(results, 'banana'),
      "real command's completions should be returned after proxy loads it")

    pcall(vim.api.nvim_del_user_command, 'TestRealComplete')
  end)

  -- Bead zpack_nvim-6n2: the proxy is torn down so the real command's
  -- subsequent invocations bypass the proxy entirely.
  it("Lazy proxy command tears itself down after tab-completion fires", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestTearDownOnComplete',
          config = function()
            vim.api.nvim_create_user_command('TestTearDownOnComplete', function() end, {
              nargs = '*',
            })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.fn.getcompletion('TestTearDownOnComplete ', 'cmdline')
    helpers.flush_pending()

    -- After tab-complete loads the plugin, the real command (registered by
    -- the plugin's config) replaces the proxy. Verifying it exists and is
    -- callable is the load-path's post-condition.
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.TestTearDownOnComplete,
      "Real command should be present after proxy fires its complete callback")

    pcall(vim.api.nvim_del_user_command, 'TestTearDownOnComplete')
  end)
end)
