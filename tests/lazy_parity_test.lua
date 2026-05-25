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
    assert.is_true(#_G.test_state.vim_pack_del_calls >= 1,
      "sync must clean unused plugins")
  end)
end)

describe(":ZPack check (zpack_nvim-xrx)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("check delegates to vim.pack.update without force", function()
    require('zpack').setup({
      spec = { { 'test/p' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    _G.test_state.vim_pack_update_calls = {}
    vim.cmd('ZPack check')
    assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
    local opts = _G.test_state.vim_pack_update_calls[1].opts
    -- Either nil (no opts) or { force = false } / unset. Must NOT be true.
    local force = opts and opts.force or false
    assert.is_false(force, "check must NOT force-apply")
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
end)
