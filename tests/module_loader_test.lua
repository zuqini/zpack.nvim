---@diagnostic disable: duplicate-set-field
local helpers = require('helpers')

describe("Module Loader", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("module_to_src index is built for lazy plugins", function()
    require('zpack').setup({
      spec = {
        { 'test/lazy-plugin', lazy = true },
        { 'test/startup-plugin' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    -- Access internal state via a test helper
    local state = require('zpack.state')
    local src = 'https://github.com/test/lazy-plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)
  end)

  it("module = false excludes plugin from module loader index", function()
    helpers.write_plugin_files('no-module-plugin', { 'nomoduleplugin.lua' })
    require('zpack').setup({
      spec = {
        { 'test/no-module-plugin', lazy = true, module = false, cmd = 'TestCmd' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    local utils = require('zpack.utils')
    -- The plugin should not be in the module index
    -- We test this indirectly by checking the loader returns nil for this module
    local result = module_loader.loader('nomoduleplugin')
    assert.is_nil(result, "Loader should return nil for module=false plugin")
  end)

  it("loader returns nil for unknown modules", function()
    require('zpack').setup({
      spec = {
        { 'test/some-plugin', lazy = true },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    local result = module_loader.loader('completely-unknown-module')
    assert.is_nil(result, "Loader should return nil for unknown modules")
  end)

  it("loader returns nil for already loaded plugins", function()
    require('zpack').setup({
      spec = {
        { 'test/already-loaded', cmd = 'TestCmd' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    -- Manually set the plugin as loaded
    local state = require('zpack.state')
    local src = 'https://github.com/test/already-loaded'
    state.spec_registry[src].load_status = "loaded"

    local module_loader = require('zpack.module_loader')
    local result = module_loader.loader('already-loaded')
    assert.is_nil(result, "Loader should return nil for already loaded plugins")
  end)

  it("loader returns nil for plugins currently being loaded", function()
    require('zpack').setup({
      spec = {
        { 'test/loading-plugin', cmd = 'TestCmd' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    -- Manually set the plugin as loading
    local state = require('zpack.state')
    local src = 'https://github.com/test/loading-plugin'
    state.spec_registry[src].load_status = "loading"

    local module_loader = require('zpack.module_loader')
    local result = module_loader.loader('loading-plugin')
    assert.is_nil(result, "Loader should return nil for plugins being loaded")
  end)

  it("loader triggers plugin load for pending lazy plugin", function()
    helpers.write_plugin_files('trigger-plugin', { 'trigger-plugin.lua' })
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'test/trigger-plugin',
          lazy = true,
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local state = require('zpack.state')
    local src = 'https://github.com/test/trigger-plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)

    local module_loader = require('zpack.module_loader')
    module_loader.loader('trigger-plugin')

    helpers.flush_pending()
    assert.is_truthy(loaded, "Config should have run")
    assert.are.equal("loaded", state.spec_registry[src].load_status)
  end)

  it("self-require during loading does not cause circular dependency error", function()
    helpers.write_plugin_files('self-require', { 'self-require.lua' })
    local config_called = false
    local no_error = true

    require('zpack').setup({
      spec = {
        {
          'test/self-require',
          lazy = true,
          config = function()
            -- Simulate plugin code that requires itself during setup
            local module_loader = require('zpack.module_loader')
            -- This should return nil and not cause an error
            local result = module_loader.loader('self-require')
            if result ~= nil then
              no_error = false
            end
            config_called = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    module_loader.loader('self-require')

    helpers.flush_pending()
    assert.is_truthy(config_called, "Config should have been called")
    assert.is_truthy(no_error, "Self-require should return nil without error")
  end)

  it("nested loading does not cause circular dependency error", function()
    helpers.write_plugin_files('plugin-a', { 'plugin-a.lua' })
    helpers.write_plugin_files('plugin-b', { 'plugin-b.lua' })
    local plugin_a_loaded = false
    local plugin_b_loaded = false
    local no_circular_error = true

    require('zpack').setup({
      spec = {
        {
          'test/plugin-a',
          lazy = true,
          config = function()
            -- A's config triggers loading B
            local module_loader = require('zpack.module_loader')
            module_loader.loader('plugin-b')
            -- After B loads, A tries to require itself (common pattern)
            local result = module_loader.loader('plugin-a')
            if result ~= nil then
              no_circular_error = false
            end
            plugin_a_loaded = true
          end,
        },
        {
          'test/plugin-b',
          lazy = true,
          config = function()
            plugin_b_loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    module_loader.loader('plugin-a')

    helpers.flush_pending()
    assert.is_truthy(plugin_a_loaded, "Plugin A should be loaded")
    assert.is_truthy(plugin_b_loaded, "Plugin B should be loaded")
    assert.is_truthy(no_circular_error, "No circular dependency error should occur")
  end)

  it("A requires B requires A chain is handled gracefully", function()
    helpers.write_plugin_files('chain-a', { 'chain-a.lua' })
    helpers.write_plugin_files('chain-b', { 'chain-b.lua' })
    local plugin_a_config_count = 0
    local plugin_b_config_count = 0
    local notifications = {}

    -- Capture notifications to check for circular dependency errors
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    require('zpack').setup({
      spec = {
        {
          'test/chain-a',
          lazy = true,
          config = function()
            plugin_a_config_count = plugin_a_config_count + 1
            -- A's config requires B
            local module_loader = require('zpack.module_loader')
            module_loader.loader('chain-b')
          end,
        },
        {
          'test/chain-b',
          lazy = true,
          config = function()
            plugin_b_config_count = plugin_b_config_count + 1
            -- B's config requires A back (should be no-op since A is loading)
            local module_loader = require('zpack.module_loader')
            module_loader.loader('chain-a')
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    module_loader.loader('chain-a')

    helpers.flush_pending()
    vim.notify = original_notify

    assert.are.equal(1, plugin_a_config_count)
    assert.are.equal(1, plugin_b_config_count)

    -- Check no circular dependency error was reported
    local has_circular_error = false
    for _, n in ipairs(notifications) do
      if n.msg and n.msg:find("Circular dependency") then
        has_circular_error = true
        break
      end
    end
    assert.is_falsy(has_circular_error, "Should not report circular dependency error")
  end)

  it("a module named unlike its plugin loads it, with main set", function()
    helpers.write_plugin_files('weird-name', { 'actual_module.lua' })
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'test/weird-name',
          lazy = true,
          main = 'actual_module',
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    -- Should be able to load via the main module name
    module_loader.loader('actual_module')

    helpers.flush_pending()
    assert.is_truthy(loaded, "Should load via explicit main module name")
  end)

  it("submodule require triggers parent plugin load", function()
    helpers.write_plugin_files('parent-plugin', { 'parent-plugin/utils/helpers.lua' })
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'test/parent-plugin',
          lazy = true,
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    -- Requiring a submodule should trigger the parent plugin load
    module_loader.loader('parent-plugin.utils.helpers')

    helpers.flush_pending()
    assert.is_truthy(loaded, "Submodule require should trigger parent plugin load")
  end)

  it("module loader is installed at position 3 (after vim.loader)", function()
    require('zpack').setup({
      spec = {
        { 'test/some-plugin', lazy = true },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    local found_at_pos_3 = false
    if package.loaders[3] == module_loader.loader then
      found_at_pos_3 = true
    end
    assert.is_truthy(found_at_pos_3, "Module loader should be at position 3")
  end)

  it("plugin with dots in name (mini.*) is matched correctly", function()
    helpers.write_plugin_files('mini.extra', { 'mini/extra.lua' })
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'nvim-mini/mini.extra',
          lazy = true,
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    -- require("mini.extra") should match plugin "mini.extra"
    module_loader.loader('mini.extra')

    helpers.flush_pending()
    assert.is_truthy(loaded, "mini.extra should load when require('mini.extra') is called")
  end)

  it("deeply nested module require matches plugin with dots", function()
    helpers.write_plugin_files('mini.extra', { 'mini/extra/ai_spec.lua' })
    local loaded = false

    require('zpack').setup({
      spec = {
        {
          'nvim-mini/mini.extra',
          lazy = true,
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    -- require("mini.extra.ai_spec") should still match plugin "mini.extra"
    module_loader.loader('mini.extra.ai_spec')

    helpers.flush_pending()
    assert.is_truthy(loaded, "mini.extra should load when require('mini.extra.ai_spec') is called")
  end)

  it("filesystem scanning finds module when name doesn't match plugin", function()
    local loaded = false

    local plugin_path, base_path = helpers.create_mock_plugin_dir('nvim-web-devicons', { 'nvim-web-devicons' })

    local original_vim_pack_add = vim.pack.add
    vim.pack.add = function(specs, opts)
      opts = opts or {}
      for _, pack_spec in ipairs(specs) do
        local name = pack_spec.name or pack_spec.src:match('[^/]+$')
        pack_spec.name = name
        _G.test_state.registered_pack_specs[name] = pack_spec
        local mock_plugin = {
          spec = pack_spec,
          path = plugin_path,
          name = name,
        }
        if opts.load then
          opts.load(mock_plugin)
        end
      end
    end

    require('zpack').setup({
      spec = {
        {
          'test/nvim-web-devicons',
          lazy = true,
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    module_loader.loader('nvim-web-devicons')

    helpers.flush_pending()
    assert.is_truthy(loaded, "Plugin should load via filesystem scanning when module name matches actual file")

    vim.pack.add = original_vim_pack_add
    helpers.cleanup_mock_plugin_dir(base_path)
  end)

  it("filesystem scanning finds module with a different name", function()
    local loaded = false

    local plugin_path, base_path = helpers.create_mock_plugin_dir('some-odd-plugin', { 'odd_module' })

    local original_vim_pack_add = vim.pack.add
    vim.pack.add = function(specs, opts)
      opts = opts or {}
      for _, pack_spec in ipairs(specs) do
        local name = pack_spec.name or pack_spec.src:match('[^/]+$')
        pack_spec.name = name
        _G.test_state.registered_pack_specs[name] = pack_spec
        local mock_plugin = {
          spec = pack_spec,
          path = plugin_path,
          name = name,
        }
        if opts.load then
          opts.load(mock_plugin)
        end
      end
    end

    require('zpack').setup({
      spec = {
        {
          'test/some-odd-plugin',
          lazy = true,
          config = function()
            loaded = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    module_loader.loader('odd_module')

    helpers.flush_pending()
    assert.is_truthy(loaded, "Plugin should load via filesystem scanning")

    vim.pack.add = original_vim_pack_add
    helpers.cleanup_mock_plugin_dir(base_path)
  end)

  it("filesystem scanning caches results", function()
    local load_count = 0

    local plugin_path, base_path = helpers.create_mock_plugin_dir('cached-plugin', { 'cached_mod' })

    local original_vim_pack_add = vim.pack.add
    vim.pack.add = function(specs, opts)
      opts = opts or {}
      for _, pack_spec in ipairs(specs) do
        local name = pack_spec.name or pack_spec.src:match('[^/]+$')
        pack_spec.name = name
        _G.test_state.registered_pack_specs[name] = pack_spec
        local mock_plugin = {
          spec = pack_spec,
          path = plugin_path,
          name = name,
        }
        if opts.load then
          opts.load(mock_plugin)
        end
      end
    end

    require('zpack').setup({
      spec = {
        {
          'test/cached-plugin',
          lazy = true,
          config = function()
            load_count = load_count + 1
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local module_loader = require('zpack.module_loader')
    module_loader.loader('cached_mod')
    helpers.flush_pending()
    module_loader.loader('cached_mod')
    helpers.flush_pending()

    assert.are.equal(1, load_count)

    vim.pack.add = original_vim_pack_add
    helpers.cleanup_mock_plugin_dir(base_path)
  end)

  it("scans no other plugin when the first claimant holds the module", function()
    local owner_path, owner_base = helpers.create_mock_plugin_dir('owner', { 'owned' })
    local other_path, other_base = helpers.create_mock_plugin_dir('other', { 'unrelated' })

    local original_vim_pack_add = vim.pack.add
    vim.pack.add = function(specs, opts)
      for _, pack_spec in ipairs(specs) do
        pack_spec.name = pack_spec.src:match('[^/]+$')
        _G.test_state.registered_pack_specs[pack_spec.name] = pack_spec
        opts.load({ spec = pack_spec, name = pack_spec.name, path = pack_spec.name == 'owner' and owner_path or other_path })
      end
    end

    require('zpack').setup({
      spec = { { 'test/owner', lazy = true }, { 'test/other', lazy = true } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Under `nvim -l` zpack's own requires reach this loader during setup and scan everything.
    local state = require('zpack.state')
    local module_loader = require('zpack.module_loader')
    require('zpack.utils').reset_lsdir_cache()
    module_loader.initialize_cache({
      state.src_to_pack_spec['https://github.com/test/owner'],
      state.src_to_pack_spec['https://github.com/test/other'],
    })

    local scanned = {}
    local original_scandir = vim.uv.fs_scandir
    vim.uv.fs_scandir = function(path)
      scanned[#scanned + 1] = path
      return original_scandir(path)
    end
    module_loader.loader('owned')
    vim.uv.fs_scandir = original_scandir
    vim.pack.add = original_vim_pack_add

    assert.are.same({ owner_path .. '/lua' }, scanned)

    helpers.cleanup_mock_plugin_dir(owner_base)
    helpers.cleanup_mock_plugin_dir(other_base)
  end)

  -- Regression: a throw inside process_spec used to leave the loader wedged, so
  -- it silently no-op'd every subsequent require of the plugin's modules.
  it("loader retries after process_spec throws", function()
    helpers.write_plugin_files('throw-plugin', { 'throw-plugin.lua' })
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/throw-plugin', lazy = true },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/throw-plugin'

    local original_packadd = vim.cmd.packadd
    vim.cmd.packadd = function() error("simulated packadd failure", 0) end

    local module_loader = require('zpack.module_loader')
    local ok = pcall(module_loader.loader, 'throw-plugin')
    assert.is_false(ok, "loader should propagate the throw")

    vim.cmd.packadd = original_packadd

    -- Restore registry state so the retry exercises the loader path freshly;
    -- the load_status reset is covered by lifecycle_test.
    assert.are.equal("pending", state.spec_registry[src].load_status,
      "process_spec must reset load_status (cross-checks the plugin_loader fix)")

    -- Re-attempting the load must NOT silently no-op.
    local loaded = false
    state.spec_registry[src].merged_spec.config = function() loaded = true end
    module_loader.loader('throw-plugin')
    helpers.flush_pending()
    assert.is_true(loaded, "second require must reach the loader body, not silently no-op")
  end)

  describe("a module's top-level name", function()
    local function status(name)
      return require('zpack.state').spec_registry['https://github.com/test/' .. name].load_status
    end

    local function setup(names)
      local spec = {}
      for _, name in ipairs(names) do
        spec[#spec + 1] = { 'test/' .. name, lazy = true }
      end
      require('zpack').setup({ spec = spec, defaults = { confirm = false } })
      helpers.flush_pending()
    end

    for label, names in pairs({
      ['listed first'] = { 'nvim-dap', 'nvim-dap-ui' },
      ['listed second'] = { 'nvim-dap-ui', 'nvim-dap' },
    }) do
      it("isn't a prefix that normalizes to another plugin's name, with it " .. label, function()
        helpers.write_plugin_files('nvim-dap', { 'dap/init.lua', 'dap/ui/widgets.lua' })
        helpers.write_plugin_files('nvim-dap-ui', { 'dapui/init.lua' })
        setup(names)

        local ok, widgets = pcall(require, 'dap.ui.widgets')
        package.loaded['dap.ui.widgets'] = nil

        assert.is_true(ok, widgets)
        assert.are.equal('loaded', status('nvim-dap'))
        assert.are.equal('pending', status('nvim-dap-ui'))
      end)
    end

    it("doesn't load a plugin it only normalizes to the name of", function()
      helpers.write_plugin_files('foo-bar.nvim', { 'fb/init.lua' })
      setup({ 'foo-bar.nvim' })

      assert.is_false((pcall(require, 'foobar')))
      assert.are.equal('pending', status('foo-bar.nvim'))
    end)

    it("doesn't load a plugin named after it with no lua/", function()
      setup({ 'plain.nvim' })

      assert.is_false((pcall(require, 'plain.thing')))
      assert.are.equal('pending', status('plain.nvim'))
    end)

    for _, file in ipairs({ 'compiled.so', 'compiled.dll' }) do
      it("is claimed by a top-level " .. file, function()
        helpers.write_plugin_files('native', { file })
        setup({ 'native' })

        require('zpack.module_loader').loader('compiled')

        assert.are.equal('loaded', status('native'))
      end)
    end
  end)
end)
