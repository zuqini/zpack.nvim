local helpers = require('helpers')

describe("Command Name Configuration", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("default cmd_name creates :ZPack command", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['ZPack'], "ZPack command should exist")
  end)

  it("custom cmd_name creates the configured command", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = 'Pack' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['Pack'], "Pack command should exist")
    assert.is_nil(cmds['ZPack'], "Default ZPack command should not exist with custom name")
    helpers.delete_zpack_commands('Pack')
  end)

  it("subcommand completion lists available subcommands", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })

    local completions = vim.fn.getcompletion('ZPack ', 'cmdline')
    assert.contains(completions, 'update')
    assert.contains(completions, 'restore')
    assert.contains(completions, 'clean')
    assert.contains(completions, 'build')
    assert.contains(completions, 'load')
    assert.contains(completions, 'delete')
  end)

  it("empty cmd_name is rejected", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = '' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds['ZPack'], "ZPack command should not exist when cmd_name rejected")
  end)

  it("lowercase cmd_name is rejected", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = 'pack' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds['pack'], "Commands with lowercase name should not be created")
    assert.is_nil(cmds['ZPack'], "Default command should not be created")
  end)

  it("cmd_name with hyphen is rejected", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = 'My-Pack' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds['My-Pack'], "Command with hyphen should not be created")
    assert.is_nil(cmds['ZPack'], "Default command should not be created")
  end)

  it("cmd_name starting with digit is rejected", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = '123' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds['123'], "Command starting with digit should not be created")
    assert.is_nil(cmds['ZPack'], "Default command should not be created")
  end)

  it("cmd_name with special characters is rejected", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = 'Pack!' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds['Pack!'], "Command with special char should not be created")
    assert.is_nil(cmds['ZPack'], "Default command should not be created")
  end)

  it("cmd_name with whitespace is rejected", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = ' Z' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds[' Z'], "Command with whitespace should not be created")
    assert.is_nil(cmds['ZPack'], "Default command should not be created")
  end)

  it("cmd_name with digits after first letter is valid", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = 'Z2' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['Z2'], "Z2 command should exist")
    helpers.delete_zpack_commands('Z2')
  end)
end)
