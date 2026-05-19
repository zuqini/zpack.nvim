local helpers = require('helpers')

describe("Conditional Loading", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("enabled=false prunes plugin from registry", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = false,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.is_nil(state.spec_registry[src], "enabled=false plugin should be pruned from spec_registry")
    assert.is_falsy(
      vim.tbl_contains(state.registered_plugin_names, 'plugin'),
      "Plugin should not be in registered_plugin_names when enabled=false"
    )
    assert.is_nil(
      _G.test_state.registered_pack_specs['plugin'],
      "Plugin should not be passed to vim.pack.add when enabled=false"
    )
  end)

  it("enabled=true allows plugin registration", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = true,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin should be registered when enabled=true")
  end)

  it("enabled function returning false prunes plugin from registry", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = function() return false end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.is_nil(state.spec_registry[src], "enabled fn returning false should prune from spec_registry")
    assert.is_falsy(
      vim.tbl_contains(state.registered_plugin_names, 'plugin'),
      "Plugin should not be in registered_plugin_names"
    )
    assert.is_nil(
      _G.test_state.registered_pack_specs['plugin'],
      "Plugin should not be passed to vim.pack.add"
    )
  end)

  it("enabled function returning nil counts as disabled and prunes", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = function() return nil end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_nil(
      state.spec_registry['https://github.com/test/plugin'],
      "enabled fn returning nil should be treated as disabled and pruned"
    )
    assert.is_nil(
      _G.test_state.registered_pack_specs['plugin'],
      "nil-returning enabled should not reach vim.pack.add"
    )
  end)

  it("enabled function returning true allows registration", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = function() return true end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(
      state.spec_registry[src],
      "Plugin should be registered when enabled function returns true"
    )
  end)

  it("cond=false prevents plugin loading", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
      cond = false,
    }

    local should_load = utils.check_cond(spec)
    assert.is_falsy(should_load, "Plugin should not load when cond=false")
  end)

  it("cond=true allows plugin loading", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
      cond = true,
    }

    local should_load = utils.check_cond(spec)
    assert.is_truthy(should_load, "Plugin should load when cond=true")
  end)

  it("cond function returning false prevents loading", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
      cond = function() return false end,
    }

    local should_load = utils.check_cond(spec)
    assert.is_falsy(should_load, "Plugin should not load when cond function returns false")
  end)

  it("cond function returning true allows loading", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
      cond = function() return true end,
    }

    local should_load = utils.check_cond(spec)
    assert.is_truthy(should_load, "Plugin should load when cond function returns true")
  end)

  it("cond nil defaults to true", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
    }

    local should_load = utils.check_cond(spec)
    assert.is_truthy(should_load, "Plugin should load when cond is nil (default true)")
  end)

  it("enabled and cond work together", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = true,
          cond = false,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(
      state.spec_registry[src],
      "Plugin should be registered (enabled=true)"
    )

    local utils = require('zpack.utils')
    local spec = state.spec_registry[src].merged_spec
    local should_load = utils.check_cond(spec)
    assert.is_falsy(should_load, "Plugin should not load (cond=false)")
  end)

  it("enabled prevents config execution", function()
    local config_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          enabled = false,
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_falsy(config_ran, "Config should not run when enabled=false")
  end)

  it("lazy=false overrides lazy triggers", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      cmd = 'TestCommand',
      lazy = false,
    }

    assert.is_falsy(lazy_module.is_lazy(spec), "Plugin should not be lazy when lazy=false")
  end)

  it("lazy=true forces lazy loading even without triggers", function()
    local lazy_module = require('zpack.lazy')

    local spec = {
      'test/plugin',
      lazy = true,
    }

    assert.is_truthy(lazy_module.is_lazy(spec), "Plugin should be lazy when lazy=true")
  end)

  it("default_cond=false prevents loading when spec.cond is nil", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
    }

    local should_load = utils.check_cond(spec, nil, false)
    assert.is_falsy(should_load, "Plugin should not load when default_cond=false and spec.cond is nil")
  end)

  it("default_cond function returning false prevents loading", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
    }

    local should_load = utils.check_cond(spec, nil, function() return false end)
    assert.is_falsy(should_load, "Plugin should not load when default_cond function returns false")
  end)

  it("spec.cond overrides default_cond", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
      cond = true,
    }

    local should_load = utils.check_cond(spec, nil, false)
    assert.is_truthy(should_load, "Plugin should load when spec.cond=true even if default_cond=false")
  end)

  it("spec.cond=false overrides default_cond=true", function()
    local utils = require('zpack.utils')

    local spec = {
      'test/plugin',
      cond = false,
    }

    local should_load = utils.check_cond(spec, nil, true)
    assert.is_falsy(should_load, "Plugin should not load when spec.cond=false even if default_cond=true")
  end)

  it("cond function receives nil-safe plugin arg at merge-pipeline time", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cond = function(plugin) return plugin ~= nil end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local entry = state.spec_registry['https://github.com/test/plugin']
    assert.is_not_nil(entry, "Registry entry should exist")
    assert.are.equal(true, entry.cond_result)
  end)

  it("check_enabled handles merge_and-composed functions without crashing", function()
    local merge = require('zpack.merge')
    local utils = require('zpack.utils')

    local base = { enabled = function() return true end }
    local incoming = { enabled = function() return false end }
    local merged = merge.merge_specs(base, incoming)

    assert.are.equal("function", type(merged.enabled))
    local result = utils.check_enabled(merged)
    assert.is_falsy(result, "merged function AND_LOGIC should evaluate to false")

    local both_true = merge.merge_specs(
      { enabled = function() return true end },
      { enabled = function() return true end }
    )
    assert.is_truthy(utils.check_enabled(both_true), "both-true functions should merge to true")
  end)
end)
