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
