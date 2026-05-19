local helpers = require('helpers')

describe("Legacy cmd_prefix Commands (deprecated)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("default prefix registers Z-prefixed legacy commands", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['ZUpdate'], "ZUpdate command should exist")
    assert.is_not_nil(cmds['ZRestore'], "ZRestore command should exist")
    assert.is_not_nil(cmds['ZClean'], "ZClean command should exist")
    assert.is_not_nil(cmds['ZBuild'], "ZBuild command should exist")
    assert.is_not_nil(cmds['ZLoad'], "ZLoad command should exist")
    assert.is_not_nil(cmds['ZDelete'], "ZDelete command should exist")
  end)

  it("custom cmd_prefix registers prefixed legacy commands", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_prefix = 'Pack' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['PackUpdate'], "PackUpdate command should exist")
    assert.is_not_nil(cmds['PackDelete'], "PackDelete command should exist")
    assert.is_nil(cmds['ZUpdate'], "default ZUpdate should not exist with a custom prefix")
    helpers.delete_zpack_commands(nil, 'Pack')
  end)

  it("empty cmd_prefix registers bare legacy commands", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_prefix = '' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['Update'], "Update command should exist")
    assert.is_not_nil(cmds['Delete'], "Delete command should exist")
    helpers.delete_zpack_commands(nil, '')
  end)

  it("cmd_prefix with digits after the first letter is valid", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_prefix = 'Z2' })

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['Z2Update'], "Z2Update command should exist")
    assert.is_not_nil(cmds['Z2Delete'], "Z2Delete command should exist")
    helpers.delete_zpack_commands(nil, 'Z2')
  end)

  it("invoking a legacy command warns with its :ZPack replacement", function()
    require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZClean')
    helpers.flush_pending()

    local found = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find(":ZClean is deprecated", 1, true)
        and notif.msg:find("Use :ZPack clean", 1, true) then
        found = true
        break
      end
    end
    assert.is_truthy(found, "invoking :ZClean should warn to use :ZPack clean")
  end)

  it("legacy commands reference the configured cmd_name", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_name = 'MyPack' })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZLoad') -- no bang, no arg -> warns "Use :<cmd_name>! load"
    helpers.flush_pending()

    local found = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find(':MyPack! load', 1, true) then
        found = true
        break
      end
    end
    assert.is_truthy(found, "legacy :ZLoad should point at the configured :MyPack command")
    helpers.delete_zpack_commands('MyPack')
  end)

  it("legacy command with extra arguments warns like the dispatcher", function()
    require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZUpdate plugin-a extra-arg')
    helpers.flush_pending()

    assert.are.equal(0, #_G.test_state.vim_pack_update_calls)

    local found_warning = false
    local misleading_error = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('at most one argument') and notif.level == vim.log.levels.WARN then
        found_warning = true
      end
      if notif.msg:find('not found in spec') then
        misleading_error = true
      end
    end
    assert.is_truthy(found_warning, "legacy :ZUpdate should warn about too many arguments")
    assert.is_falsy(misleading_error, 'legacy :ZUpdate must not emit the misleading joined-args error')
  end)

  it("legacy clean rejects positional arguments without a raw Vim error", function()
    require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    local ok = pcall(vim.cmd, 'ZClean junk')
    helpers.flush_pending()

    assert.is_truthy(ok, "legacy :ZClean junk must not raise a raw Vim parse error")

    local found_warning = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('no arguments') and notif.level == vim.log.levels.WARN then
        found_warning = true
        break
      end
    end
    assert.is_truthy(found_warning, "legacy :ZClean should warn that clean accepts no arguments")
  end)

  it("invalid cmd_prefix emits an error plus a deprecation notice and registers no legacy commands", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false }, cmd_prefix = 'My-Pack' })

    helpers.flush_pending()

    local cmds = vim.api.nvim_get_commands({})
    assert.is_nil(cmds['My-PackUpdate'], "no legacy commands should be registered for an invalid prefix")
    assert.is_nil(cmds['ZUpdate'], "an invalid prefix should not fall back to the default Z prefix")
    assert.is_not_nil(cmds['ZPack'], "the primary :ZPack command should still be registered")

    local found_error = false
    local found_deprecation = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('Invalid cmd_prefix') and notif.level == vim.log.levels.ERROR then
        found_error = true
      end
      if notif.msg:find('DEPRECATED') and notif.msg:find('cmd_prefix', 1, true)
        and notif.level == vim.log.levels.WARN then
        found_deprecation = true
      end
    end
    assert.is_truthy(found_error, "an invalid cmd_prefix should emit an error notification")
    assert.is_truthy(found_deprecation, "an invalid cmd_prefix should also emit the cmd_prefix deprecation notice")
  end)

  it("non-string cmd_prefix does not abort setup", function()
    local ok = pcall(require('zpack').setup, {
      spec = {},
      defaults = { confirm = false },
      cmd_prefix = {},
    })
    assert.is_truthy(ok, "setup() must not abort when cmd_prefix is not a string")

    helpers.flush_pending()

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['ZPack'], "the primary :ZPack command should still be registered")

    local found_error = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('Invalid cmd_prefix') and notif.level == vim.log.levels.ERROR then
        found_error = true
        break
      end
    end
    assert.is_truthy(found_error, "a non-string cmd_prefix should emit an error notification")
  end)
end)
