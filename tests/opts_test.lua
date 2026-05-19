local helpers = require('helpers')

describe("Plugin opts and auto-setup", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("opts table is recorded on the registry entry", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts = { enabled = true, theme = 'dark' },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local entry = state.spec_registry[src]
    assert.is_truthy(entry.has_opts, "has_opts should be true")
    -- opts is intentionally not stored on merged_spec; the raw value lives
    -- on sorted_specs and is resolved at load time via resolve_opts.
    assert.is_nil(entry.merged_spec.opts, "merged_spec.opts must always be nil")
    assert.are.equal(true, entry.sorted_specs[1].opts.enabled)
    assert.are.equal('dark', entry.sorted_specs[1].opts.theme)
  end)

  it("opts function is recorded on the sorted spec", function()
    local opts_fn = function() return { test = true } end

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts = opts_fn,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local entry = state.spec_registry[src]
    assert.is_truthy(entry.has_opts, "has_opts should be true for function-form opts")
    assert.is_nil(entry.merged_spec.opts, "merged_spec.opts must always be nil")
    assert.are.equal('function', type(entry.sorted_specs[1].opts))
  end)

  it("main field is stored in spec", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          main = 'custom.module',
          opts = {},
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec
    assert.are.equal('custom.module', spec.main)
  end)

  it("config = true is stored in spec", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = true,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec
    assert.are.equal(true, spec.config)
  end)

  it("config function receives opts as second argument", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts = { foo = 'bar', num = 42 },
          config = function(plugin, opts)
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts, "config should receive opts")
    assert.are.equal('bar', received_opts.foo)
    assert.are.equal(42, received_opts.num)
  end)

  it("config function receives resolved opts from function", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts = function(plugin)
            return { from_fn = true, path = plugin.path }
          end,
          config = function(plugin, opts)
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts, "config should receive resolved opts")
    assert.are.equal(true, received_opts.from_fn)
    assert.is_not_nil(received_opts.path, "opts function should receive plugin data")
  end)

  it("config receives empty table when no opts specified", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function(plugin, opts)
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts, "config should receive opts table")
    assert.are.equal('table', type(received_opts))
  end)

  it("lazy plugin with opts triggers config on load", function()
    local config_ran = false
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          opts = { lazy_opt = true },
          config = function(plugin, opts)
            config_ran = true
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_falsy(config_ran, "config should not run at setup for lazy plugin")

    pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()

    assert.is_truthy(config_ran, "config should run when lazy plugin loads")
    assert.are.equal(true, received_opts.lazy_opt)
  end)

  it("custom config function replaces auto-setup", function()
    local config_call_count = 0

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts = { some = 'opts' },
          config = function(plugin, opts)
            config_call_count = config_call_count + 1
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(1, config_call_count)
  end)

  it("opts without config does not call config function", function()
    local config_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts = { enabled = true },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_falsy(config_ran, "no config function should be called")
  end)
end)

describe("resolve_main caching", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("resolve_main result is cached in plugin.main", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          main = 'custom.module',
          opts = {},
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local utils = require('zpack.utils')
    local src = 'https://github.com/test/plugin'
    local entry = state.spec_registry[src]

    local spec = entry.merged_spec
    utils.resolve_main(entry.plugin, spec)
    assert.are.equal('custom.module', entry.plugin.main)
  end)

  it("resolve_main uses cached value on subsequent calls", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          main = 'cached.module',
          opts = {},
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local utils = require('zpack.utils')
    local src = 'https://github.com/test/plugin'
    local entry = state.spec_registry[src]

    local spec = entry.merged_spec
    local first_result = utils.resolve_main(entry.plugin, spec)
    spec.main = 'changed.module'
    local second_result = utils.resolve_main(entry.plugin, spec)

    assert.are.equal('cached.module', first_result)
    assert.are.equal('cached.module', second_result)
  end)
end)

describe("mini.* plugin handling", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("mini.* plugin uses plugin name as main module", function()
    require('zpack').setup({
      spec = {
        {
          'nvim-mini/mini.surround',
          opts = {},
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local utils = require('zpack.utils')
    local src = 'https://github.com/nvim-mini/mini.surround'
    local entry = state.spec_registry[src]

    local spec = entry.merged_spec
    local main = utils.resolve_main(entry.plugin, spec)
    assert.are.equal('mini.surround', main)
  end)

  it("mini.nvim does not use special handling", function()
    require('zpack').setup({
      spec = {
        {
          'nvim-mini/mini.nvim',
          opts = {},
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local utils = require('zpack.utils')
    local src = 'https://github.com/nvim-mini/mini.nvim'
    local entry = state.spec_registry[src]

    local spec = entry.merged_spec
    local main = utils.resolve_main(entry.plugin, spec)
    assert.is_nil(main, "mini.nvim should not match special case")
  end)
end)

describe("plugin.main in config hooks", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("plugin.main is available in config function", function()
    local received_main = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          main = 'test.module',
          config = function(plugin, opts)
            received_main = plugin.main
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal('test.module', received_main)
  end)

  it("plugin.main is nil when not detected", function()
    local received_main = "not_set"

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function(plugin, opts)
            received_main = plugin.main
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_nil(received_main)
  end)
end)

describe("normalize_name utility", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("removes nvim- prefix", function()
    local utils = require('zpack.utils')

    assert.are.equal('treesitter', utils.normalize_name('nvim-treesitter'))
    assert.are.equal('surround', utils.normalize_name('vim-surround'))
  end)

  it("removes .nvim suffix", function()
    local utils = require('zpack.utils')

    assert.are.equal('telescope', utils.normalize_name('telescope.nvim'))
    assert.are.equal('plugin', utils.normalize_name('plugin.vim'))
  end)

  it("removes -lua and .lua suffixes", function()
    local utils = require('zpack.utils')

    assert.are.equal('plenary', utils.normalize_name('plenary-lua'))
    assert.are.equal('plugin', utils.normalize_name('plugin.lua'))
  end)

  it("converts to lowercase and removes non-alpha", function()
    local utils = require('zpack.utils')

    assert.are.equal('myplugin', utils.normalize_name('My-Plugin_123'))
    assert.are.equal('caps', utils.normalize_name('CAPS'))
  end)

  it("handles complex names", function()
    local utils = require('zpack.utils')

    assert.are.equal('lspconfig', utils.normalize_name('nvim-lspconfig'))
    assert.are.equal('telescopefzfnative', utils.normalize_name('telescope-fzf-native.nvim'))
  end)
end)
