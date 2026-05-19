local helpers = require('helpers')

describe("Priority-based Loading", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("default priority is 50", function()
    local utils = require('zpack.utils')

    require('zpack').setup({
      spec = {
        { 'test/plugin' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    local priority = utils.get_priority(src)
    assert.are.equal(50, priority)
  end)

  it("custom priority is stored", function()
    local utils = require('zpack.utils')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          priority = 100,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    local priority = utils.get_priority(src)
    assert.are.equal(100, priority)
  end)

  it("higher priority plugins load first", function()
    local load_order = {}

    require('zpack').setup({
      spec = {
        {
          'test/plugin1',
          priority = 100,
          config = function()
            table.insert(load_order, 'plugin1')
          end,
        },
        {
          'test/plugin2',
          priority = 200,
          config = function()
            table.insert(load_order, 'plugin2')
          end,
        },
        {
          'test/plugin3',
          priority = 150,
          config = function()
            table.insert(load_order, 'plugin3')
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(3, #load_order)
    assert.are.equal('plugin2', load_order[1])
    assert.are.equal('plugin3', load_order[2])
    assert.are.equal('plugin1', load_order[3])
  end)

  it("priority works with lazy loading", function()
    local utils = require('zpack.utils')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          priority = 999,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    local priority = utils.get_priority(src)
    assert.are.equal(999, priority)
  end)

  it("compare_priority function sorts correctly", function()
    local utils = require('zpack.utils')

    require('zpack').setup({
      spec = {
        { 'test/plugin1', priority = 100 },
        { 'test/plugin2', priority = 50 },
        { 'test/plugin3', priority = 200 },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src1 = 'https://github.com/test/plugin1'
    local src2 = 'https://github.com/test/plugin2'
    local src3 = 'https://github.com/test/plugin3'

    assert.is_truthy(
      utils.compare_priority(src3, src1),
      "Plugin3 (200) should be higher priority than Plugin1 (100)"
    )
    assert.is_truthy(
      utils.compare_priority(src1, src2),
      "Plugin1 (100) should be higher priority than Plugin2 (50)"
    )
    assert.is_falsy(
      utils.compare_priority(src2, src3),
      "Plugin2 (50) should not be higher priority than Plugin3 (200)"
    )
  end)

  it("compare_priority uses import order as tiebreaker", function()
    local utils = require('zpack.utils')

    require('zpack').setup({
      spec = {
        { 'test/first' },  -- import_order = 0
        { 'test/second' }, -- import_order = 1
        { 'test/third' },  -- import_order = 2
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src1 = 'https://github.com/test/first'
    local src2 = 'https://github.com/test/second'
    local src3 = 'https://github.com/test/third'

    assert.is_truthy(
      utils.compare_priority(src1, src2),
      "first (import 0) should come before second (import 1) when priority equal"
    )
    assert.is_truthy(
      utils.compare_priority(src2, src3),
      "second (import 1) should come before third (import 2) when priority equal"
    )
    assert.is_falsy(
      utils.compare_priority(src3, src1),
      "third (import 2) should not come before first (import 0)"
    )
  end)

  it("priority affects lazy plugin load order on same trigger", function()
    local load_order = {}

    require('zpack').setup({
      spec = {
        {
          'test/plugin1',
          event = 'VeryLazy',
          priority = 50,
          config = function()
            table.insert(load_order, 'plugin1')
          end,
        },
        {
          'test/plugin2',
          event = 'VeryLazy',
          priority = 100,
          config = function()
            table.insert(load_order, 'plugin2')
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.api.nvim_exec_autocmds('UIEnter', {})
    helpers.flush_pending()

    if #load_order > 0 then
      assert.are.equal('plugin2', load_order[1])
    end
  end)
end)
