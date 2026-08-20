local helpers = require('helpers')

describe("Setup and Initialization", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("setup() initializes zpack state", function()
    local state = require('zpack.state')

    assert.is_falsy(state.is_setup, "State should not be setup initially")

    require('zpack').setup({ spec = {}, defaults = { confirm = false } })

    assert.is_truthy(state.is_setup, "State should be setup after setup()")
    assert.is_not_nil(state.spec_registry, "Spec registry should exist")
    assert.is_not_nil(state.lazy_group, "Lazy group should exist")
    assert.is_not_nil(state.startup_group, "Startup group should exist")
  end)

  it("setup() cannot be called twice", function()
    local state = require('zpack.state')

    require('zpack').setup({ spec = {}, defaults = { confirm = false } })
    assert.is_truthy(state.is_setup, "State should be setup after first call")

    -- Second call should warn but state should remain setup
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })
    assert.is_truthy(state.is_setup, "State should still be setup after second call")
  end)

  it("setup() with specs as first argument registers plugins", function()
    local state = require('zpack.state')

    require('zpack').setup({
      { 'test/plugin1' },
      { 'test/plugin2' },
    })

    local src1 = 'https://github.com/test/plugin1'
    local src2 = 'https://github.com/test/plugin2'
    assert.is_not_nil(state.spec_registry[src1], "Plugin 1 should be registered")
    assert.is_not_nil(state.spec_registry[src2], "Plugin 2 should be registered")
  end)

  it("setup() with single spec as first argument", function()
    local state = require('zpack.state')

    require('zpack').setup({ 'test/plugin' })

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Single inline spec should be registered")
  end)

  it("setup() with spec field registers single plugin", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = { { 'test/plugin' } },
      defaults = { confirm = false },
    })

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin should be registered")
    local spec = state.spec_registry[src].merged_spec
    assert.are.equal('test/plugin', spec[1])
  end)

  it("setup() with spec as single spec (not wrapped in list)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = { 'test/plugin', config = function() end },
      defaults = { confirm = false },
    })

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Single spec should be registered")
  end)

  it("setup() with spec field registers multiple plugins", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin1' },
        { 'test/plugin2' },
      },
      defaults = { confirm = false },
    })

    local src1 = 'https://github.com/test/plugin1'
    local src2 = 'https://github.com/test/plugin2'
    assert.is_not_nil(state.spec_registry[src1], "Plugin 1 should be registered")
    assert.is_not_nil(state.spec_registry[src2], "Plugin 2 should be registered")
  end)

  it("plugin spec supports src field", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { src = 'https://custom.url/plugin.git' },
      },
      defaults = { confirm = false },
    })

    local src = 'https://custom.url/plugin.git'
    assert.is_not_nil(state.spec_registry[src], "Plugin with src should be registered")
  end)

  it("plugin spec supports url field (lazy.nvim compat)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { url = 'https://custom.url/plugin.git' },
      },
      defaults = { confirm = false },
    })

    local src = 'https://custom.url/plugin.git'
    assert.is_not_nil(state.spec_registry[src], "Plugin with url should be registered")
  end)

  it("plugin spec supports dir field (lazy.nvim compat)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { dir = '/path/to/local/plugin' },
      },
      defaults = { confirm = false },
    })

    local src = '/path/to/local/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin with dir should be registered")
  end)

  it("url overrides [1] shorthand (lazy.nvim fork idiom)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = 'https://github.com/pedro757/flash.nvim.git' },
      },
      defaults = { confirm = false },
    })

    assert.is_not_nil(state.spec_registry['https://github.com/pedro757/flash.nvim.git'],
      "explicit url should win over [1]")
    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'],
      "[1] shorthand must not be used when url is set")
  end)

  it("source precedence is src > url > dir > [1]", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/a', src = 'https://srv/a-src', url = 'https://srv/a-url', dir = '/tmp/a-dir' },
        { 'test/b', url = 'https://srv/b-url', dir = '/tmp/b-dir' },
        { 'test/c', dir = '/tmp/c-dir' },
      },
      defaults = { confirm = false },
    })

    assert.is_not_nil(state.spec_registry['https://srv/a-src'], "src should win over url/dir/[1]")
    assert.is_not_nil(state.spec_registry['https://srv/b-url'], "url should win over dir/[1]")
    assert.is_not_nil(state.spec_registry['/tmp/c-dir'], "dir should win over [1]")
    for _, short in ipairs({ 'test/a', 'test/b', 'test/c' }) do
      assert.is_nil(state.spec_registry['https://github.com/' .. short],
        ("[1] shorthand must not be used for %s"):format(short))
    end
  end)

  it("plugin name derives from [1] even when a fork url wins the source", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/tokyo-fork'

    require('zpack').setup({
      spec = {
        { 'folke/tokyonight.nvim', url = fork },
      },
      defaults = { confirm = false },
    })

    assert.are.equal(fork, state.name_to_src['tokyonight.nvim'],
      "name must come from [1], not the fork URL basename")
    assert.is_nil(state.name_to_src['tokyo-fork'],
      "fork URL basename must not become the plugin name")
    assert.are.equal('tokyonight.nvim', state.src_to_pack_spec[fork].name,
      "pack spec handed to vim.pack must carry the [1]-derived name")
  end)

  it("fork override in a separate spec fragment merges into one plugin", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local shorthand = 'https://github.com/folke/flash.nvim'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', cmd = 'Flash' },
        { 'folke/flash.nvim', url = fork },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[shorthand],
      "shorthand fragment must fold into the explicit-source entry")
    local entry = state.spec_registry[fork]
    assert.is_not_nil(entry, "fork entry should own the merged plugin")
    assert.are.equal('Flash', entry.merged_spec.cmd,
      "base fragment's fields must survive the fold")
    assert.are.equal(fork, state.name_to_src['flash.nvim'])
  end)

  it("fork override fragment merges regardless of import order", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local shorthand = 'https://github.com/folke/flash.nvim'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = fork },
        { 'folke/flash.nvim', cmd = 'Flash' },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[shorthand])
    local entry = state.spec_registry[fork]
    assert.is_not_nil(entry)
    assert.are.equal('Flash', entry.merged_spec.cmd)
  end)

  it("dependency declared by shorthand folds into the fork entry and rekeys the graph", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local shorthand = 'https://github.com/folke/flash.nvim'
    local parent = 'https://github.com/test/parent'

    require('zpack').setup({
      spec = {
        { 'test/parent', dependencies = { 'folke/flash.nvim' } },
        { 'folke/flash.nvim', url = fork },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[shorthand])
    assert.is_not_nil(state.spec_registry[fork])
    assert.is_truthy(state.dependency_graph[parent][fork],
      "parent's dep edge must be rekeyed onto the fork src")
    assert.is_nil(state.dependency_graph[parent][shorthand],
      "stale shorthand dep edge must be removed")
    assert.is_truthy(state.reverse_dependency_graph[fork][parent],
      "reverse edge must point at the fork src")
    assert.is_nil(state.reverse_dependency_graph[shorthand])
  end)

  it("two fork fragments sharing a [1] fold into the later fragment's source", function()
    local state = require('zpack.state')
    local fork1 = 'https://github.com/me/flash-fork'
    local fork2 = 'https://github.com/me/flash-fork.git'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = fork1, event = 'InsertEnter', branch = 'one' },
        { 'folke/flash.nvim', url = fork2, cmd = 'Flash', branch = 'two' },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[fork1],
      "earlier fork fragment must fold into the later one, not abort on a name conflict")
    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'])
    local entry = state.spec_registry[fork2]
    assert.is_not_nil(entry, "later fork fragment must own the merged plugin")
    assert.are.equal('InsertEnter', entry.merged_spec.event,
      "earlier fragment's fields must survive the fold")
    assert.are.equal('Flash', entry.merged_spec.cmd)
    assert.are.equal('two', entry.merged_spec.branch,
      "OVERRIDE fields must resolve later-fragment-wins across the fold")
    assert.are.equal(fork2, state.name_to_src['flash.nvim'])
  end)

  it("bare fragment plus two fork fragments merge into the latest fork", function()
    local state = require('zpack.state')
    local fork1 = 'https://github.com/me/flash-fork-one'
    local fork2 = 'https://github.com/me/flash-fork-two'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', cmd = 'Flash' },
        { 'folke/flash.nvim', url = fork1 },
        { 'folke/flash.nvim', url = fork2 },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'])
    assert.is_nil(state.spec_registry[fork1])
    local entry = state.spec_registry[fork2]
    assert.is_not_nil(entry, "latest fork must absorb every fragment")
    assert.are.equal('Flash', entry.merged_spec.cmd,
      "bare fragment's fields must land on the winning fork")
    assert.are.equal(fork2, state.name_to_src['flash.nvim'])
  end)

  it("dev = true fragment wins the fold over a fork fragment regardless of order", function()
    local state = require('zpack.state')
    local dev_root = vim.fn.tempname()
    vim.fn.mkdir(dev_root .. '/flash.nvim', 'p')
    local fork = 'https://github.com/me/flash-fork'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', dev = true },
        { 'folke/flash.nvim', url = fork },
      },
      dev = { path = dev_root },
      defaults = { confirm = false },
    })

    local dev_src = dev_root .. '/flash.nvim'
    assert.is_not_nil(state.spec_registry[dev_src],
      "dev fragment must own the merged plugin even though the fork fragment is later")
    assert.is_nil(state.spec_registry[fork], "fork fragment must fold into the dev entry")
    assert.are.equal(dev_src, state.name_to_src['flash.nvim'])
  end)

  it("dir field expands ~ to home directory", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { dir = '~/projects/my-plugin' },
      },
      defaults = { confirm = false },
    })

    local expected_src = vim.fn.expand('~/projects/my-plugin')
    assert.is_not_nil(state.spec_registry[expected_src], "dir should expand ~ to home directory")
  end)
end)
