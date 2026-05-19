local helpers = require('helpers')

describe("is_single_spec heuristic", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("single spec with string source and opts is detected", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', opts = { foo = true } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local entry = state.spec_registry['https://github.com/test/plugin']

    assert.is_not_nil(entry, "plugin should be registered")
    assert.is_truthy(entry.has_opts, "entry should record that opts were contributed")
    assert.are.equal(true, entry.sorted_specs[1].opts.foo)
  end)

  it("list of bare string specs is treated as list", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')

    assert.is_not_nil(state.spec_registry['https://github.com/test/plugin-a'])
    assert.is_not_nil(state.spec_registry['https://github.com/test/plugin-b'])
  end)

  it("single dependency spec with opts preserves all fields", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = {
            'test/dep',
            init = function() _G._test_dep_init_called = true end,
            opts = { select = { lookahead = true } },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local dep_entry = state.spec_registry['https://github.com/test/dep']

    assert.is_not_nil(dep_entry, "dependency should be registered")
    assert.is_truthy(dep_entry.has_opts, "dep entry should record that opts were contributed")
    assert.is_not_nil(dep_entry.sorted_specs[1].opts, "opts should be preserved on dependency")
    assert.are.equal(true, dep_entry.sorted_specs[1].opts.select.lookahead)
    assert.is_not_nil(dep_entry.merged_spec.init, "init should be preserved on dependency")

    _G._test_dep_init_called = nil
  end)

  it("list of string dependencies are all registered", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = { 'test/dep-a', 'test/dep-b' },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')

    assert.is_not_nil(state.spec_registry['https://github.com/test/dep-a'],
      "first string dep should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/test/dep-b'],
      "second string dep should be registered")
  end)

  it("list of table specs is treated as list", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a', opts = {} },
        { 'test/plugin-b', opts = { bar = true } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')

    assert.is_not_nil(state.spec_registry['https://github.com/test/plugin-a'],
      "first spec should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/test/plugin-b'],
      "second spec should be registered")
  end)

  it("single dependency with config preserves config function", function()
    local config_called = false

    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = {
            'test/dep-with-config',
            config = function() config_called = true end,
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local dep_entry = state.spec_registry['https://github.com/test/dep-with-config']

    assert.is_not_nil(dep_entry, "dependency should be registered")
    assert.is_not_nil(dep_entry.merged_spec.config, "config should be preserved on dependency")
  end)
end)
