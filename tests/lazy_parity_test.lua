-- Cross-cutting regression tests for lazy.nvim spec parity work. Each
-- describe block pins one parity-gap bead from the closure series; failures
-- here mean a parity gap has re-opened, not that the broader feature is
-- broken in any deeper way.

local helpers = require('helpers')

describe("version = false (zpack_nvim-9tm)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("normalize_version returns nil for version = false", function()
    local utils = require('zpack.utils')
    assert.is_nil(utils.normalize_version({ version = false }))
  end)

  it("version = false skips emitting a version on the vim.pack spec", function()
    require('zpack').setup({
      spec = { { 'test/v', version = false, branch = 'main' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local found
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.src == 'https://github.com/test/v' then
          found = pack_spec
        end
      end
    end
    assert.is_not_nil(found, "plugin must register with vim.pack")
    assert.is_nil(found.version,
      "version = false must drop the version even when branch is set")
  end)

  it("validate_spec accepts version = false", function()
    local validate = require('zpack.validate')
    local errs = validate.validate_spec({ 'a/b', version = false })
    assert.are.equal(0, #errs,
      "version = false must pass validation; got: " .. table.concat(errs, '; '))
  end)
end)

describe("Plugin shape: name/dir/dependencies (zpack_nvim-clj)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("plugin.name/dir/dependencies are populated in callbacks", function()
    local captured
    require('zpack').setup({
      spec = {
        { 'test/A' },
        {
          'test/B',
          dependencies = { 'test/A' },
          config = function(plugin)
            captured = {
              name = plugin.name,
              dir = plugin.dir,
              dependencies = plugin.dependencies,
            }
          end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_not_nil(captured, "config should have been called for test/B")
    assert.are.equal('B', captured.name, "plugin.name must alias spec.name")
    assert.is_string(captured.dir, "plugin.dir must alias plugin.path")
    assert.is_table(captured.dependencies)
    assert.contains(captured.dependencies, 'A')
  end)
end)

describe("nested specs field (zpack_nvim-74a)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("specs are walked as peer plugins, not dependencies", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          specs = {
            { 'test/companion' },
          },
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/parent'])
    assert.is_not_nil(state.spec_registry['https://github.com/test/companion'])

    -- specs entries must NOT be marked as dependencies of the parent
    local companion = state.spec_registry['https://github.com/test/companion']
    local is_dep = companion.specs[1]._is_dependency
    assert.is_falsy(is_dep, "Nested specs are peers, not dependencies")
  end)

  it("specs nested inside a dependencies chain stay peers, not deps", function()
    require('zpack').setup({
      spec = {
        {
          'test/root',
          dependencies = {
            {
              'test/dep',
              specs = { { 'test/sibling' } },
            },
          },
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    local dep = state.spec_registry['https://github.com/test/dep']
    local sibling = state.spec_registry['https://github.com/test/sibling']
    assert.is_not_nil(dep, "dep must register")
    assert.is_not_nil(sibling, "sibling declared via nested specs must register")
    assert.is_true(dep.specs[1]._is_dependency, "dep itself remains a dep")
    assert.is_falsy(sibling.specs[1]._is_dependency,
      "specs nested under a dep must NOT inherit is_dependency from ctx")
  end)
end)

describe("pin = true (zpack_nvim-gi5)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("bulk :ZPack update excludes pinned plugins from the explicit names list", function()
    require('zpack').setup({
      spec = {
        { 'test/free' },
        { 'test/pinned', pin = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    _G.test_state.vim_pack_update_calls = {}
    vim.cmd('ZPack update')

    assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
    local call = _G.test_state.vim_pack_update_calls[1]
    assert.is_not_nil(call.names, "Pin filter must pass an explicit names list, not nil")
    assert.contains(call.names, 'free')
    local saw_pinned = false
    for _, n in ipairs(call.names) do
      if n == 'pinned' then saw_pinned = true end
    end
    assert.is_false(saw_pinned, "Pinned plugin must NOT appear in the update list")
  end)
end)

describe("optional = true (zpack_nvim-sg0)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("optional-only plugins are dropped from registration", function()
    require('zpack').setup({
      spec = {
        { 'test/orphan', optional = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_nil(state.spec_registry['https://github.com/test/orphan'],
      "An optional-only plugin must be pruned")
  end)

  it("optional plugin survives when also referenced as a required dependency", function()
    require('zpack').setup({
      spec = {
        { 'test/parent', dependencies = { 'test/shared' } },
        { 'test/shared', optional = true, opts = { from_optional = true } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/shared'],
      "Optional + dep-referent must survive")
  end)

  -- Regression: a table-form dep `{ 'foo/x', optional = true }` was the
  -- only contributor for `x` (string-form deps get wrapped fresh without
  -- `optional`). Pre-fix the optional prune disabled `x` and cascade-
  -- disabled the parent. `_is_dependency` now defeats `optional`.
  it("optional written on a table-form dep does not prune the parent", function()
    require('zpack').setup({
      spec = {
        { 'test/dep-parent', dependencies = { { 'test/dep-child', optional = true } } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/dep-parent'],
      "Parent must not be cascade-disabled by an optional table-form dep")
    assert.is_not_nil(state.spec_registry['https://github.com/test/dep-child'],
      "Table-form dep with `optional = true` must survive as a dep reference")
  end)
end)

describe("import = function() (zpack_nvim-fqs)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("function-form import returns specs that get registered", function()
    require('zpack').setup({
      spec = {
        { import = function()
            return { { 'test/dyn-a' }, { 'test/dyn-b' } }
          end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/dyn-a'])
    assert.is_not_nil(state.spec_registry['https://github.com/test/dyn-b'])
  end)

  it("throwing import function surfaces a structured notify", function()
    _G.test_state.notifications = {}
    require('zpack').setup({
      spec = {
        { import = function() error('simulated import failure', 0) end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local saw = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find('import function threw') then saw = true end
    end
    assert.is_true(saw, "import-function throw must surface a structured notify")
  end)
end)

describe(":ZPack sync (zpack_nvim-0sp)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("sync invokes vim.pack.update and clean_unused", function()
    require('zpack').setup({
      spec = { { 'test/p' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    _G.test_state.vim_pack_update_calls = {}
    _G.test_state.vim_pack_del_calls = {}

    -- Install an unrelated plugin via mocked vim.pack so clean_unused
    -- has something to remove.
    _G.test_state.registered_pack_specs['stray'] = {
      src = 'https://github.com/stray/stray',
      name = 'stray',
    }

    vim.cmd('ZPack sync')
    helpers.flush_pending()
    assert.are.equal(1, #_G.test_state.vim_pack_update_calls, "sync must update")
    local opts = _G.test_state.vim_pack_update_calls[1].opts
    assert.is_true(opts and opts.force == true,
      "sync must force-apply (no-force would race clean ahead of confirm)")
    assert.is_true(#_G.test_state.vim_pack_del_calls >= 1,
      "sync must clean unused plugins")
  end)
end)

describe("deactivate hook (zpack_nvim-aht) + :ZPack reload (zpack_nvim-dpl)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("validate accepts deactivate function", function()
    local validate = require('zpack.validate')
    local errs = validate.validate_spec({ 'a/b', deactivate = function() end })
    assert.are.equal(0, #errs)
  end)

  it("reload runs deactivate then re-runs config", function()
    local lifecycle = {}
    require('zpack').setup({
      spec = {
        {
          'test/relo',
          lazy = false,
          config = function() table.insert(lifecycle, 'config') end,
          deactivate = function() table.insert(lifecycle, 'deactivate') end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    -- The startup config call ran once during setup; reset before reload
    -- so the assertion below sees only the reload-time lifecycle events.
    lifecycle = {}

    vim.cmd('ZPack reload relo')
    helpers.flush_pending()

    -- Order: deactivate first (teardown), then config (fresh load).
    assert.are.same({ 'deactivate', 'config' }, lifecycle,
      ("Reload must call deactivate then config; got: %s"):format(vim.inspect(lifecycle)))
  end)

  it("reload clears package.loaded for plugin modules under its lua/", function()
    -- Plant a fake plugin on disk so the sweep has a real lua/ tree to fs_stat
    -- against. Mock vim.pack.get to point at it so reload resolves a real path.
    local tmp = vim.fn.tempname()
    local plugin_path = tmp .. '/sweepy'
    vim.fn.mkdir(plugin_path .. '/lua/sweepy/sub', 'p')
    local f = io.open(plugin_path .. '/lua/sweepy/init.lua', 'w')
    f:write('return { x = 1 }'); f:close()
    f = io.open(plugin_path .. '/lua/sweepy/sub/inner.lua', 'w')
    f:write('return { y = 2 }'); f:close()

    require('zpack').setup({
      spec = { { 'test/sweepy', lazy = false, main = 'sweepy' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Override path from the helpers' default stdpath('data')/... to the
    -- tmpdir we just populated, so the sweep's fs_stat actually finds files.
    local state = require('zpack.state')
    local src = 'https://github.com/test/sweepy'
    local pack_spec = _G.test_state.registered_pack_specs.sweepy
    state.spec_registry[src].plugin.path = plugin_path
    _G.test_state.original_vim_pack_get = vim.pack.get
    vim.pack.get = function() return { { spec = pack_spec, path = plugin_path } } end

    package.loaded['sweepy'] = { stale = true }
    package.loaded['sweepy.sub.inner'] = { stale = true }
    package.loaded['sweepy.absent'] = { stale = true } -- no file on disk
    package.loaded['unrelated'] = { stale = true }

    vim.cmd('ZPack reload sweepy')
    helpers.flush_pending()

    assert.is_nil(package.loaded['sweepy'], "reload must clear main module")
    assert.is_nil(package.loaded['sweepy.sub.inner'],
      "reload must clear submodule with on-disk file")
    assert.are.same({ stale = true }, package.loaded['sweepy.absent'],
      "reload must NOT clear keys with no on-disk file (sibling-plugin safety)")
    assert.are.same({ stale = true }, package.loaded['unrelated'],
      "reload must NOT touch keys outside the plugin's main namespace")
  end)
end)

describe("dev = true source rewrite (zpack_nvim-lkb)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("dev = true rewrites source to <dev.path>/<name> when dir exists", function()
    local dev_root = vim.fn.tempname()
    local plugin_dir = dev_root .. '/devplug.nvim'
    vim.fn.mkdir(plugin_dir, 'p')

    require('zpack').setup({
      spec = { { 'me/devplug.nvim', dev = true } },
      dev = { path = dev_root },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local found
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.src == plugin_dir then found = pack_spec end
      end
    end
    assert.is_not_nil(found, "dev = true must rewrite src to the local dir")
  end)

  it("dev.fallback = true falls back to remote when local dir is missing", function()
    require('zpack').setup({
      spec = { { 'me/devplug.nvim', dev = true } },
      dev = { path = vim.fn.tempname() .. '/missing', fallback = true },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local saw_remote
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.src == 'https://github.com/me/devplug.nvim' then
          saw_remote = true
        end
      end
    end
    assert.is_true(saw_remote, "fallback = true must use the remote source when local dir is missing")
  end)

  it("dev = true with no source field notifies and skips", function()
    require('zpack').setup({
      spec = { { dev = true, config = function() end } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local saw
    for _, n in ipairs(_G.test_state.notifications) do
      if type(n.msg) == 'string' and n.msg:find('requires a source field', 1, true) then
        saw = true
      end
    end
    assert.is_true(saw, "dev=true without a source field must notify")
  end)
end)

describe(":ZPack reload edge cases", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("reload re-runs init hook (matches fresh-load contract)", function()
    local lifecycle = {}
    require('zpack').setup({
      spec = {
        {
          'test/initrelo',
          lazy = false,
          init = function() table.insert(lifecycle, 'init') end,
          config = function() table.insert(lifecycle, 'config') end,
          deactivate = function() table.insert(lifecycle, 'deactivate') end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    lifecycle = {}

    vim.cmd('ZPack reload initrelo')
    helpers.flush_pending()

    assert.are.same({ 'deactivate', 'init', 'config' }, lifecycle,
      ("Reload must run deactivate → init → config; got: %s"):format(vim.inspect(lifecycle)))
  end)

  -- Regression: reload called try_call_hook unconditionally, emitting
  -- "expected init missing" ERROR for the common no-init case.
  it("reload does not emit 'expected init missing' notify when spec has no init", function()
    _G.test_state.notifications = {}
    require('zpack').setup({
      spec = {
        {
          'test/noinitrelo',
          lazy = false,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZPack reload noinitrelo')
    helpers.flush_pending()

    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(
        type(n.msg) == 'string' and n.msg:find('expected init missing', 1, true),
        ("Reload of a no-init spec must not emit 'expected init missing'; got: %s"):format(tostring(n.msg))
      )
    end
  end)

  it("reload skips deactivate when the plugin object is nil", function()
    -- Narrow but real window: vim.pack.add's load callback hasn't fired
    -- (install in progress or callback raised), so registry_entry.plugin
    -- stays nil. Reload must not call deactivate(nil).
    local called_deactivate = false
    require('zpack').setup({
      spec = {
        {
          'test/nilp',
          lazy = false,
          deactivate = function() called_deactivate = true end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Force the nil-plugin window the gate guards.
    local state = require('zpack.state')
    state.spec_registry['https://github.com/test/nilp'].plugin = nil

    vim.cmd('ZPack reload nilp')
    helpers.flush_pending()

    assert.is_false(called_deactivate,
      "Reload must NOT invoke deactivate when plugin object is nil")
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(type(n.msg) == 'string'
          and n.msg:find('Failed to run deactivate hook', 1, true),
        "Reload must not produce a deactivate failure notify for nil-plugin reload")
    end
  end)
end)

describe(":ZPack update names list preserves vim.pack universe under pin", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("includes installed-but-unregistered plugins so a single pin doesn't narrow the universe", function()
    require('zpack').setup({
      spec = {
        { 'test/free' },
        { 'test/pinned', pin = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Plugin vim.pack knows about but zpack does not (raw vim.pack.add or
    -- post-removal orphan). Pre-fix, any pin would skip this entry.
    _G.test_state.registered_pack_specs.orphan = {
      src = 'https://github.com/raw/orphan',
      name = 'orphan',
    }

    _G.test_state.vim_pack_update_calls = {}
    vim.cmd('ZPack update')

    assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
    local names = _G.test_state.vim_pack_update_calls[1].names
    assert.is_not_nil(names)
    local has_free, has_pinned, has_orphan = false, false, false
    for _, n in ipairs(names) do
      if n == 'free' then has_free = true end
      if n == 'pinned' then has_pinned = true end
      if n == 'orphan' then has_orphan = true end
    end
    assert.is_true(has_free, "non-pinned registry plugin must be in the update list")
    assert.is_false(has_pinned, "pinned plugin must be excluded")
    assert.is_true(has_orphan,
      "installed-but-unregistered plugin must be in the update list")
  end)
end)
