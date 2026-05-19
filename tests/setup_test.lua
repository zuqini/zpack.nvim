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

  it("add() shows deprecation error", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })
    require('zpack').add({ 'test/plugin' })

    helpers.flush_pending()

    local found_deprecation = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find("REMOVED") and notif.msg:find("add") then
        found_deprecation = true
        break
      end
    end

    assert.is_truthy(found_deprecation, "Should show deprecation error for add()")
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
