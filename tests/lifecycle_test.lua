local helpers = require('helpers')

describe("Plugin Lifecycle Hooks", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("init hook runs before plugin loads", function()
    local init_ran = false
    local config_ran = false
    local init_ran_before_config = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          init = function()
            init_ran = true
            if not config_ran then
              init_ran_before_config = true
            end
          end,
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(init_ran, "init hook should run")
    assert.is_truthy(init_ran_before_config, "init should run before config")
  end)

  it("config hook runs after plugin loads", function()
    local config_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(config_ran, "config hook should run")
  end)

  it("init runs for lazy plugins at setup time", function()
    local init_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          init = function()
            init_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(init_ran, "init should run for lazy plugins at setup time")
  end)

  it("init runs only once for lazy plugins", function()
    local init_count = 0

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          init = function()
            init_count = init_count + 1
          end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(1, init_count)

    pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()
    assert.are.equal(1, init_count)
  end)

  it("config does not run for lazy plugins at setup time", function()
    local config_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_falsy(config_ran, "config should not run for lazy plugins at setup time")
  end)

  it("build hook is string command", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          build = 'echo "build completed"',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec
    assert.is_not_nil(spec.build, "Build hook should be stored")
    assert.are.equal('string', type(spec.build))
  end)

  it("build hook is function", function()
    local build_fn = function() end

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          build = build_fn,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec
    assert.is_not_nil(spec.build, "Build hook should be stored")
    assert.are.equal('function', type(spec.build))
  end)

  it("init and config hooks work together", function()
    local execution_order = {}

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          init = function()
            table.insert(execution_order, 'init')
          end,
          config = function()
            table.insert(execution_order, 'config')
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(2, #execution_order)
    assert.are.equal('init', execution_order[1])
    assert.are.equal('config', execution_order[2])
  end)

  it("config hook can access plugin module", function()
    local can_access_globals = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function()
            can_access_globals = (vim ~= nil and vim.fn ~= nil)
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(can_access_globals, "config should have access to vim globals")
  end)
end)
