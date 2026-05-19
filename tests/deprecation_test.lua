local helpers = require('helpers')

describe("Deprecated Options", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("deprecated confirm option shows warning", function()
    require('zpack').setup({ spec = {}, confirm = false })

    helpers.flush_pending()

    local found_deprecation = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find("DEPRECATED") and notif.msg:find("confirm") then
        found_deprecation = true
        break
      end
    end

    assert.is_truthy(found_deprecation, "Should show deprecation warning for confirm")
  end)

  it("deprecated disable_vim_loader option shows warning", function()
    require('zpack').setup({ spec = {}, disable_vim_loader = true })

    helpers.flush_pending()

    local found_deprecation = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find("DEPRECATED") and notif.msg:find("disable_vim_loader") then
        found_deprecation = true
        break
      end
    end

    assert.is_truthy(found_deprecation, "Should show deprecation warning for disable_vim_loader")
  end)

  it("deprecated plugins_dir option shows warning", function()
    require('zpack').setup({ plugins_dir = 'my_plugins' })

    helpers.flush_pending()

    local found_deprecation = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find("DEPRECATED") and notif.msg:find("plugins_dir") then
        found_deprecation = true
        break
      end
    end

    assert.is_truthy(found_deprecation, "Should show deprecation warning for plugins_dir")
  end)

  it("invoking legacy :Z* commands emits the deprecation warning every time", function()
    require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZClean')
    vim.cmd('ZClean') -- repeated use must re-emit the warning
    vim.cmd('ZUpdate')
    helpers.flush_pending()

    local count = 0
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find("DEPRECATED") and notif.msg:find("Use :ZPack") then
        count = count + 1
      end
    end
    assert.are.equal(3, count)
  end)

  it("legacy :ZDelete delegates to the new delete subcommand with force=true", function()
    require('zpack').setup({
      spec = { { 'test/plugin-a' }, { 'test/plugin-b' } },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZDelete plugin-a')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.is_truthy(call.opts.force, "legacy :ZDelete must propagate force=true to Sub.delete")
    assert.contains(call.names, 'plugin-a')
  end)

  it("deprecated options still register plugins", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = { { 'test/plugin' } },
      confirm = false,
    })

    helpers.flush_pending()

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin should be registered")
  end)
end)
