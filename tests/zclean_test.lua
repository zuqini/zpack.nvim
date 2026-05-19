local helpers = require('helpers')

describe("ZPack clean", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("clean detects orphan plugins not in spec", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    _G.test_state.registered_pack_specs['orphan-plugin'] = {
      src = 'test/orphan-plugin',
      name = 'orphan-plugin',
    }

    vim.cmd('ZPack clean')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.contains(call.names, 'orphan-plugin')
    assert.are.equal(1, #call.names)
  end)

  it("clean does not delete plugins in spec", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZPack clean')
    helpers.flush_pending()

    assert.are.equal(0, #_G.test_state.vim_pack_del_calls)

    local found_info = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('No unused plugins') and notif.level == vim.log.levels.INFO then
        found_info = true
        break
      end
    end
    assert.is_truthy(found_info, "Should show info that no unused plugins exist")
  end)

  it("clean detects multiple orphan plugins", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    _G.test_state.registered_pack_specs['orphan-1'] = {
      src = 'test/orphan-1',
      name = 'orphan-1',
    }
    _G.test_state.registered_pack_specs['orphan-2'] = {
      src = 'test/orphan-2',
      name = 'orphan-2',
    }

    vim.cmd('ZPack clean')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.are.equal(2, #call.names)
  end)
end)
