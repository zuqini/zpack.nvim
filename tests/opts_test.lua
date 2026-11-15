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

  it("opts_extend concatenates list opts from separate specs of one plugin", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts_extend = { 'ensure_installed' },
          opts = { ensure_installed = { 'bash', 'c', 'diff' } },
          config = function(_, opts)
            received_opts = opts
          end,
        },
        { 'test/plugin', opts = { ensure_installed = { 'rust', 'ron' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts, "config should receive opts")
    assert.are.same({ 'bash', 'c', 'diff', 'rust', 'ron' }, received_opts.ensure_installed)
  end)

  it("opts_extend appends lists in import order, dependencies specs included", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          opts_extend = { 'ensure_installed' },
          opts = { ensure_installed = { 'top1' } },
          config = function(_, opts)
            received_opts = opts
          end,
        },
        { 'test/other', dependencies = { { 'test/plugin', opts = { ensure_installed = { 'dep' } } } } },
        { 'test/plugin', opts = { ensure_installed = { 'top2' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts, "config should receive opts")
    assert.are.same({ 'top1', 'dep', 'top2' }, received_opts.ensure_installed)
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

  it("returns the spec's main, which is on plugin.main", function()
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
    local entry = state.spec_registry['https://github.com/test/plugin']

    assert.are.equal('custom.module', utils.resolve_main(entry.plugin))
    assert.are.equal('custom.module', entry.plugin.main)
  end)

  it("keeps a detected main on plugin.main for later calls", function()
    helpers.write_plugin_files('kept.nvim', { 'kept/init.lua', 'other.lua' })
    require('zpack').setup({
      spec = {
        { 'test/kept.nvim', opts = {} },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local utils = require('zpack.utils')
    local entry = state.spec_registry['https://github.com/test/kept.nvim']
    assert.are.equal('kept', entry.plugin.main)

    vim.fn.delete(entry.plugin.path .. '/lua/kept', 'rf')
    utils.reset_lsdir_cache()
    assert.are.equal('kept', utils.resolve_main(entry.plugin))
  end)

  it("finds a module an update adds on :ZPack reload", function()
    helpers.write_plugin_files('late.nvim', { 'a.lua', 'b.lua' })
    local seen = {}
    require('zpack').setup({
      spec = {
        { 'test/late.nvim', opts = {}, config = function(plugin) seen[#seen + 1] = tostring(plugin.main) end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    helpers.write_plugin_files('late.nvim', { 'late/init.lua' })
    local spec = require('zpack.state').src_to_pack_spec['https://github.com/test/late.nvim']
    vim.api.nvim_exec_autocmds('PackChanged', { data = { kind = 'update', spec = spec } })
    vim.cmd('ZPack reload late.nvim')
    helpers.flush_pending()

    assert.are.same({ 'nil', 'late' }, seen)
  end)

  it("finds the module an update renames on :ZPack reload", function()
    helpers.write_plugin_files('moved.nvim', { 'moved_old/init.lua' })
    local called = {}
    for _, mod in ipairs({ 'moved_old', 'moved_new' }) do
      package.preload[mod] = function()
        return { setup = function() called[#called + 1] = mod end }
      end
    end
    require('zpack').setup({
      spec = {
        { 'test/moved.nvim', opts = {} },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    local src = 'https://github.com/test/moved.nvim'
    vim.fn.delete(state.spec_registry[src].plugin.path .. '/lua/moved_old', 'rf')
    helpers.write_plugin_files('moved.nvim', { 'moved_new/init.lua' })
    vim.api.nvim_exec_autocmds('PackChanged', { data = { kind = 'update', spec = state.src_to_pack_spec[src] } })
    vim.cmd('ZPack reload moved.nvim')
    helpers.flush_pending()

    for _, mod in ipairs({ 'moved_old', 'moved_new' }) do
      package.preload[mod] = nil
      package.loaded[mod] = nil
    end
    assert.are.same({ 'moved_old', 'moved_new' }, called)
    assert.are.equal('moved_new', state.spec_registry[src].plugin.main)
  end)

  it("requires the module an update renames through vim.loader on :ZPack reload", function()
    local root = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/indexed.nvim'
    _G.zpack_indexed_setups = {}
    local function write_module(mod)
      helpers.write_plugin_files('indexed.nvim', { mod .. '/init.lua' })
      vim.fn.writefile({ ("return { setup = function() table.insert(_G.zpack_indexed_setups, '%s') end }"):format(mod) },
        root .. '/lua/' .. mod .. '/init.lua')
    end
    write_module('indexed_old')
    vim.opt.runtimepath:prepend(root)
    finally(function()
      vim.opt.runtimepath:remove(root)
      _G.zpack_indexed_setups = nil
      package.loaded.indexed_old, package.loaded.indexed_new = nil, nil
    end)
    require('zpack').setup({
      spec = {
        { 'test/indexed.nvim', opts = {} },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    assert.is_true(vim.loader.enabled)

    local spec = require('zpack.state').src_to_pack_spec['https://github.com/test/indexed.nvim']
    vim.fn.delete(root .. '/lua/indexed_old', 'rf')
    write_module('indexed_new')
    vim.api.nvim_exec_autocmds('PackChanged', { data = { kind = 'update', spec = spec, path = root } })
    vim.cmd('ZPack reload indexed.nvim')
    helpers.flush_pending()

    assert.are.same({ 'indexed_old', 'indexed_new' }, _G.zpack_indexed_setups)
  end)

  it("keeps the spec's main, from any fragment, on :ZPack reload", function()
    helpers.write_plugin_files('pinned.nvim', { 'pinned_decoy.lua' })
    local called = {}
    for _, mod in ipairs({ 'pinned_decoy', 'pinned_chosen' }) do
      package.preload[mod] = function()
        return { setup = function() called[#called + 1] = mod end }
      end
    end
    require('zpack').setup({
      spec = {
        { 'test/pinned.nvim', opts = {} },
        { 'test/pinned.nvim', main = 'pinned_chosen' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    vim.cmd('ZPack reload pinned.nvim')
    helpers.flush_pending()

    for _, mod in ipairs({ 'pinned_decoy', 'pinned_chosen' }) do
      package.preload[mod] = nil
      package.loaded[mod] = nil
    end
    assert.are.same({ 'pinned_chosen', 'pinned_chosen' }, called)
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

    local main = utils.resolve_main(entry.plugin)
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

    local main = utils.resolve_main(entry.plugin)
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

  it("plugin.main is the spec's `main` in init and opts functions, as in lazy.nvim", function()
    local seen = {}

    require('zpack').setup({
      spec = {
        {
          'test/bare',
          main = 'bare.module',
          init = function(plugin)
            seen.init = plugin.main
          end,
        },
        {
          'test/plugin',
          main = 'test.module',
          opts = function(plugin)
            seen.opts = plugin.main
            return {}
          end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.same({ init = 'bare.module', opts = 'test.module' }, seen)
  end)

  it("plugin.main is the spec's `main` in cond and trigger functions", function()
    local seen = {}

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          main = 'test.module',
          cond = function(plugin)
            seen['cond: ' .. tostring(plugin.main)] = true
            return true
          end,
          cmd = function(plugin)
            seen['cmd: ' .. tostring(plugin.main)] = true
            return 'MainInTrigger'
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    pcall(vim.api.nvim_del_user_command, 'MainInTrigger')
    assert.are.same({ ['cond: test.module'] = true, ['cmd: test.module'] = true }, seen)
  end)

  it("a `main` of false leaves the plugin's module to detection, as in lazy.nvim", function()
    helpers.write_plugin_files('falsy', { 'falsy/init.lua' })
    local seen = {}

    require('zpack').setup({
      spec = {
        {
          'test/falsy',
          main = false,
          init = function(plugin)
            seen.init = tostring(plugin.main)
          end,
          config = function(plugin)
            seen.config = plugin.main
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.same({ init = 'nil', config = 'falsy' }, seen)
  end)

  it("the spec's `main` wins over a module detection would find", function()
    helpers.write_plugin_files('picked', { 'decoy.lua' })
    local called = {}
    package.loaded['decoy'] = { setup = function() called[#called + 1] = 'decoy' end }
    package.loaded['chosen'] = { setup = function() called[#called + 1] = 'chosen' end }

    require('zpack').setup({
      spec = {
        { 'test/picked', main = 'chosen', opts = {} },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    package.loaded['decoy'] = nil
    package.loaded['chosen'] = nil
    assert.are.same({ 'chosen' }, called)
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
