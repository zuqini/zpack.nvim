local helpers = require('helpers')

describe("ZPack delete", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("delete single plugin uses force=true", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZPack delete plugin-a')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.is_not_nil(call.opts, "opts should be passed to vim.pack.del")
    assert.is_truthy(call.opts.force, "force option should be true")
    assert.contains(call.names, 'plugin-a')
  end)

  it("ZPack! delete all plugins uses force=true", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
        { 'test/plugin-c' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZPack! delete')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.is_not_nil(call.opts, "opts should be passed to vim.pack.del")
    assert.is_truthy(call.opts.force, "force option should be true")
    assert.are.equal(4, #call.names)
    assert.contains(call.names, 'zpack.nvim')
  end)

  it("delete! clears state for every registered plugin", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
        { 'test/plugin-c' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local state = require('zpack.state')
    assert.are.equal(3, #state.registered_plugins)

    vim.cmd('ZPack! delete')
    helpers.flush_pending()

    assert.are.equal(0, #state.registered_plugins)
    assert.is_nil(next(state.spec_registry), "spec_registry should be empty after delete!")
    assert.is_nil(next(state.src_to_pack_spec), "src_to_pack_spec should be empty after delete!")
  end)

  it("delete! also wipes state for cond-disabled plugins", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b', cond = false },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local state = require('zpack.state')
    local src_b = 'https://github.com/test/plugin-b'
    -- A cond-disabled plugin is installed and tracked in spec_registry, but
    -- never reaches registered_plugins -- the set delete! used to wipe.
    assert.are.equal(1, #state.registered_plugins)
    assert.is_not_nil(state.spec_registry[src_b], "cond-disabled plugin has a registry entry")

    vim.cmd('ZPack! delete')
    helpers.flush_pending()

    assert.is_nil(next(state.spec_registry), "delete! should wipe spec_registry, including cond-disabled plugins")
    assert.is_nil(next(state.src_to_pack_spec), "src_to_pack_spec should be empty after delete!")
  end)

  it("delete without bang and no arg shows warning", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZPack delete')
    helpers.flush_pending()

    assert.are.equal(0, #_G.test_state.vim_pack_del_calls)
  end)

  it("delete clears dependency graph entries for deleted plugin", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a', dependencies = { 'test/plugin-b' } },
        { 'test/plugin-b', dependencies = { 'test/plugin-c' } },
        { 'test/plugin-c' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local state = require('zpack.state')
    local src_b = 'https://github.com/test/plugin-b'
    local src_a = 'https://github.com/test/plugin-a'
    local src_c = 'https://github.com/test/plugin-c'
    assert.is_not_nil(state.dependency_graph[src_b], "plugin-b should have dependency graph entry")
    assert.is_not_nil(state.reverse_dependency_graph[src_b], "plugin-b should have reverse dependency graph entry")

    vim.cmd('ZPack delete plugin-b')
    helpers.flush_pending()

    assert.is_nil(state.dependency_graph[src_b], "plugin-b dependency graph entry should be cleared")
    assert.is_nil(state.reverse_dependency_graph[src_b], "plugin-b reverse dependency graph entry should be cleared")

    local a_deps = state.dependency_graph[src_a]
    if a_deps then
      assert.is_nil(a_deps[src_b], "plugin-b should be removed from plugin-a's dependencies")
    end

    local c_rdeps = state.reverse_dependency_graph[src_c]
    if c_rdeps then
      assert.is_nil(c_rdeps[src_b], "plugin-b should be removed from plugin-c's reverse dependencies")
    end
  end)

  it("delete clears src_to_pack_spec for deleted plugin", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local state = require('zpack.state')
    local src_a = 'https://github.com/test/plugin-a'
    local src_b = 'https://github.com/test/plugin-b'
    assert.is_not_nil(state.src_to_pack_spec[src_a], "plugin-a should have src_to_pack_spec entry")

    vim.cmd('ZPack delete plugin-a')
    helpers.flush_pending()

    assert.is_nil(state.src_to_pack_spec[src_a], "plugin-a src_to_pack_spec entry should be cleared")
    assert.is_not_nil(state.src_to_pack_spec[src_b], "plugin-b src_to_pack_spec entry should remain")
  end)

  it("external vim.pack.del syncs zpack state via PackChanged", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local state = require('zpack.state')
    local src_a = 'https://github.com/test/plugin-a'
    local src_b = 'https://github.com/test/plugin-b'
    assert.is_not_nil(state.spec_registry[src_a], "plugin-a should be registered")
    assert.contains(state.registered_plugin_names, 'plugin-a')

    -- Simulate :packdel / a direct vim.pack.del call, bypassing :ZPack delete.
    vim.pack.del({ 'plugin-a' })
    helpers.flush_pending()

    assert.is_nil(state.spec_registry[src_a], "plugin-a should be removed from registry")
    assert.is_not_nil(state.spec_registry[src_b], "plugin-b should remain registered")

    local still_listed = false
    for _, name in ipairs(state.registered_plugin_names) do
      if name == 'plugin-a' then
        still_listed = true
      end
    end
    assert.is_falsy(still_listed, "plugin-a should no longer be in registered names")
  end)

  it("firing a deleted lazy plugin's trigger does not error or load it", function()
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin-a',
          cmd = 'TestCommand',
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    assert.is_not_nil(
      vim.api.nvim_get_commands({}).TestCommand,
      "lazy cmd trigger should be registered before deletion"
    )

    -- Remove the plugin while its lazy trigger is still live.
    vim.pack.del({ 'plugin-a' })
    helpers.flush_pending()

    local ok = pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()

    assert.is_truthy(ok, "firing a deleted lazy plugin's command should not error")
    assert.is_falsy(loaded, "deleted lazy plugin should not load when its trigger fires")
  end)

  it("delete non-existent plugin does not call vim.pack.del", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZPack delete non-existent-plugin')
    helpers.flush_pending()

    assert.are.equal(0, #_G.test_state.vim_pack_del_calls)

    local found_error = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('not installed') and notif.level == vim.log.levels.ERROR then
        found_error = true
        break
      end
    end
    assert.is_truthy(found_error, "should notify error for non-existent plugin")
  end)
end)
