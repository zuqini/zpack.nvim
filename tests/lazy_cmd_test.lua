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
end)
