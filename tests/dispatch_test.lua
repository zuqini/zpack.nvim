local helpers = require('helpers')

describe(":ZPack subcommand dispatch", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("a bang on a non-bang subcommand warns and does not run", function()
    require('zpack').setup({
      spec = { { 'test/plugin-a' } },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    -- An installed plugin absent from the spec gives `clean` something to
    -- delete, so a wrongly-accepted bang would surface as a non-zero
    -- vim_pack_del_calls below.
    _G.test_state.registered_pack_specs['orphan-plugin'] = {
      src = 'test/orphan-plugin',
      name = 'orphan-plugin',
    }

    vim.cmd('ZPack! clean')
    helpers.flush_pending()

    assert.are.equal(0, #_G.test_state.vim_pack_del_calls)

    local found_warning = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('does not accept') and notif.level == vim.log.levels.WARN then
        found_warning = true
        break
      end
    end
    assert.is_truthy(found_warning, "should warn that clean does not accept a bang")
  end)

  it("extra positional arguments warn and do not run", function()
    require('zpack').setup({
      spec = { { 'test/plugin-a' } },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZPack update plugin-a extra-arg')
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
    assert.is_truthy(found_warning, "should warn about too many arguments")
    assert.is_falsy(misleading_error, 'must not emit the misleading joined-args "not found in spec" error')
  end)

  it("clean rejects positional arguments", function()
    require('zpack').setup({
      spec = { { 'test/plugin-a' } },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZPack clean junk')
    helpers.flush_pending()

    local found_warning = false
    local clean_ran = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('no arguments') and notif.level == vim.log.levels.WARN then
        found_warning = true
      end
      if notif.msg:find('unused plugin') then
        clean_ran = true
      end
    end
    assert.is_truthy(found_warning, "should warn that clean accepts no arguments")
    assert.is_falsy(clean_ran, "clean must not run when given arguments")
  end)

  it("completion after a bang-attached subcommand targets its arguments", function()
    require('zpack').setup({
      spec = { { 'test/lazy-plugin', cmd = 'TestCommand' } },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local completions = vim.fn.getcompletion('ZPack!load ', 'cmdline')
    assert.contains(completions, 'lazy-plugin')
  end)
end)
