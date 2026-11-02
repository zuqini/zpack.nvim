local helpers = require('helpers')

describe("a false entry in a spec list", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  for name, spec in pairs({
    ['at the top level'] = function() return { false, { 'test/plugin' } } end,
    ['under dependencies'] = function() return { { 'test/parent', dependencies = { false, { 'test/plugin' } } } } end,
  }) do
    it("declares nothing and says nothing, " .. name, function()
      require('zpack').setup({ spec = spec(), defaults = { confirm = false } })
      helpers.flush_pending()
      assert.are.same({}, _G.test_state.notifications)
      local state = require('zpack.state')
      assert.is_not_nil(state.spec_registry['https://github.com/test/plugin'])
    end)
  end
end)

describe("Spec Import", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  describe("a list with nil holes", function()
    local function names_in_order()
      local state = require('zpack.state')
      local entries = vim.tbl_values(state.spec_registry)
      table.sort(entries, function(a, b) return a.specs[1]._import_order < b.specs[1]._import_order end)
      return vim.tbl_map(function(entry) return entry.specs[1][1] end, entries)
    end

    for name, case in pairs({
      ['of tables'] = { { { 'test/a' }, nil, { 'test/b' } }, { 'test/a', 'test/b' } },
      ['starting with a hole'] = { { nil, { 'test/a' } }, { 'test/a' } },
      ['of strings'] = { { 'test/a', vim.g.zpack_no_such_flag and 'test/x', 'test/b' }, { 'test/a', 'test/b' } },
      ['of strings starting with a hole'] = { { nil, 'test/a', nil, 'test/b' }, { 'test/a', 'test/b' } },
      ['with several holes'] = { { 'test/a', nil, nil, 'test/b', nil, { 'test/c' } }, { 'test/a', 'test/b', 'test/c' } },
      ['nested in a list'] = { { { { 'test/a' }, nil, { 'test/b' } } }, { 'test/a', 'test/b' } },
      ['of strings nested in a list'] = { { { 'test/a', nil, 'test/b' } }, { 'test/a', 'test/b' } },
      ['nested, starting with a hole'] = { { { nil, { 'test/a' } }, { 'test/b' } }, { 'test/a', 'test/b' } },
      ['beside fields, nested'] = { { { { 'test/a' }, nil, { 'test/b' }, opts = {} } }, { 'test/a', 'test/b' } },
      ['of tables starting with a hole, beside fields'] = { { { nil, { 'test/a' }, opts = {} } }, { 'test/a' } },
    }) do
      it(name .. " is walked in order, without a word", function()
        require('zpack').setup({ spec = case[1] })
        helpers.flush_pending()
        assert.are.same(case[2], names_in_order())
        assert.are.same({}, _G.test_state.notifications)
      end)
    end

    it("passed as setup()'s own list is the spec", function()
      require('zpack').setup({ nil, { 'test/a' } })
      helpers.flush_pending()
      assert.are.same({ 'test/a' }, names_in_order())
      assert.are.same({}, _G.test_state.notifications)
    end)

    it("passed as setup()'s own list beside options is the spec", function()
      require('zpack').setup({ nil, { 'test/a' }, defaults = { confirm = false } })
      helpers.flush_pending()
      assert.are.same({ 'test/a' }, names_in_order())
      assert.are.same({}, _G.test_state.notifications)
    end)

    for field, is_dep in pairs({ dependencies = true, specs = false }) do
      it("as a " .. field .. " value is walked past the hole", function()
        require('zpack').setup({ spec = { { 'test/p', [field] = { 'test/a', nil, 'test/b' } } } })
        helpers.flush_pending()
        local registry = require('zpack.state').spec_registry
        assert.are.equal(is_dep, registry['https://github.com/test/a'].specs[1]._is_dependency)
        assert.are.equal(is_dep, registry['https://github.com/test/b'].specs[1]._is_dependency)
        assert.are.same({}, _G.test_state.notifications)
      end)
    end

    it("from a module, as LazyVim's ai extras write it, keeps what follows the hole", function()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. '/lua', 'p')
      vim.fn.writefile({
        'return {',
        "  { 'test/supermaven', event = 'InsertEnter' },",
        "  { 'test/cmp', optional = true, dependencies = { 'supermaven' } },",
        "  vim.g.zpack_test_ai_cmp and { 'test/blink', optional = true } or nil,",
        "  { 'test/lualine', opts = function() end, config = function() end },",
        '}',
      }, root .. '/lua/zpack_hole_specs.lua')
      vim.opt.rtp:prepend(root)
      package.loaded.zpack_hole_specs = nil
      require('zpack').setup({ spec = { { import = 'zpack_hole_specs' }, { 'test/cmp' } } })
      helpers.flush_pending()
      assert.are.same({ 'test/supermaven', 'test/cmp', 'test/lualine' }, names_in_order())
      assert.are.same({}, vim.tbl_filter(function(note)
        return note.level >= vim.log.levels.WARN
      end, _G.test_state.notifications))
      package.loaded.zpack_hole_specs = nil
    end)

    for name, spec in pairs({
      ['alone'] = { 'test/a' },
      ['with fields'] = { 'test/a', opts = {}, config = function() end },
      ['with a trailing nil'] = { 'test/a', nil },
    }) do
      it("doesn't touch a single spec " .. name, function()
        require('zpack').setup({ spec = { spec } })
        helpers.flush_pending()
        assert.are.same({ 'test/a' }, names_in_order())
        assert.are.same({}, _G.test_state.notifications)
      end)
    end
  end)

  it("import loads *.lua files from directory", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'foo.lua', type = 'file' },
          { name = 'bar.lua', type = 'file' },
        }
      end
      return {}
    end

    package.loaded['test_plugins.foo'] = { 'test/foo-plugin' }
    package.loaded['test_plugins.bar'] = { 'test/bar-plugin' }

    local state = require('zpack.state')
    helpers.mock_config_dir('/mock/config/lua/test_plugins')
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/foo-plugin'], "foo-plugin should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/test/bar-plugin'], "bar-plugin should be registered")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.foo'] = nil
    package.loaded['test_plugins.bar'] = nil
  end)

  it("import loads */init.lua files from subdirectories", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'mini', type = 'directory' },
        }
      end
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins/mini/init.lua' then
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins.mini'] = { 'test/mini-plugin' }

    local state = require('zpack.state')
    helpers.mock_config_dir('/mock/config/lua/test_plugins')
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/mini-plugin'],
      "mini-plugin should be registered")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.mini'] = nil
  end)

  it("import loads both *.lua and */init.lua", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'telescope.lua', type = 'file' },
          { name = 'mini', type = 'directory' },
        }
      end
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins/mini/init.lua' then
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins.telescope'] = { 'test/telescope' }
    package.loaded['test_plugins.mini'] = { 'test/mini' }

    local state = require('zpack.state')
    helpers.mock_config_dir('/mock/config/lua/test_plugins')
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/telescope'], "telescope should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/test/mini'], "mini should be registered")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.telescope'] = nil
    package.loaded['test_plugins.mini'] = nil
  end)

  it("import resolves a single spec file directly (lua/<path>.lua)", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    local lsdir_called = false
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins/telescope' then
        lsdir_called = true
      end
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins/telescope.lua' then
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins.telescope'] = { 'test/telescope' }

    local state = require('zpack.state')
    require('zpack').setup({ { import = 'test_plugins.telescope' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/telescope'],
      "single-file import should register the file's spec")
    assert.is_false(lsdir_called,
      "a single-file import must not walk a same-named directory")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.telescope'] = nil
  end)

  it("a lua/<path>.lua file takes precedence over a lua/<path>/ directory", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    vim.fn.stdpath = function() return '/mock/config' end
    -- Both `lua/test_plugins.lua` and `lua/test_plugins/foo.lua` exist; the file
    -- wins and the directory entry must be ignored.
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'foo.lua', type = 'file' },
        }
      end
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins.lua' then
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins'] = { 'test/file-spec' }
    package.loaded['test_plugins.foo'] = { 'test/dir-spec' }

    local state = require('zpack.state')
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/file-spec'],
      "the file spec should be registered")
    assert.is_nil(state.spec_registry['https://github.com/test/dir-spec'],
      "the directory spec must be ignored when a same-named .lua file exists")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins'] = nil
    package.loaded['test_plugins.foo'] = nil
  end)

  it("single-file import with enabled=false skips import", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    local resolved = false
    local lsdir_called = false
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function()
      lsdir_called = true
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins/foo.lua' then
        resolved = true
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins.foo'] = { 'test/foo-plugin' }

    local state = require('zpack.state')
    require('zpack').setup({ { import = 'test_plugins.foo', enabled = false } })
    helpers.flush_pending()

    assert.is_nil(state.spec_registry['https://github.com/test/foo-plugin'],
      "single-file import should not register when enabled=false")
    assert.is_false(resolved,
      "enabled=false must short-circuit before any single-file resolution")
    assert.is_false(lsdir_called,
      "enabled=false must short-circuit before any directory walk")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.foo'] = nil
  end)

  it("import only goes 1 level deep for init.lua", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'level1', type = 'directory' },
        }
      end
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins/level1/init.lua' then
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins.level1'] = { 'test/level1-plugin' }

    local state = require('zpack.state')
    helpers.mock_config_dir('/mock/config/lua/test_plugins')
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/level1-plugin'],
      "level1-plugin should be registered")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.level1'] = nil
  end)

  it("import with enabled=false skips import", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'foo.lua', type = 'file' },
        }
      end
      return {}
    end

    package.loaded['test_plugins.foo'] = { 'test/foo-plugin' }

    local state = require('zpack.state')
    require('zpack').setup({ { import = 'test_plugins', enabled = false } })
    helpers.flush_pending()

    assert.is_nil(state.spec_registry['https://github.com/test/foo-plugin'],
      "foo-plugin should NOT be registered when enabled=false")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.foo'] = nil
  end)

  -- Regression: an import spec's `enabled = function() error(...) end` used to
  -- abort setup() mid-import, stranding every later spec. After routing the
  -- import spec's eager enabled through utils.spec_enabled, a throwing enabled
  -- is treated as disabled (import skipped) and setup() continues to siblings.
  it("import with throwing enabled is skipped, sibling specs still register", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'foo.lua', type = 'file' },
        }
      end
      return {}
    end

    package.loaded['test_plugins.foo'] = { 'test/foo-plugin' }

    _G.test_state.notifications = {}
    local state = require('zpack.state')
    require('zpack').setup({
      { import = 'test_plugins', enabled = function() error("boom", 0) end },
      { 'test/sibling-plugin' },
    })
    helpers.flush_pending()

    assert.is_nil(state.spec_registry['https://github.com/test/foo-plugin'],
      "foo-plugin should NOT be registered when import's enabled throws")
    assert.is_not_nil(state.spec_registry['https://github.com/test/sibling-plugin'],
      "sibling spec must still register after throwing import enabled")

    local saw_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to evaluate enabled for import:test_plugins") then
        saw_notify = true
        break
      end
    end
    assert.is_true(saw_notify, "throwing import enabled should surface a structured notify")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.foo'] = nil
  end)

  it("nested import works (init.lua with import)", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_fs_stat = vim.uv.fs_stat
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        return {
          { name = 'mini', type = 'directory' },
        }
      elseif path == '/mock/config/lua/test_plugins/mini' then
        return {
          { name = 'ai.lua', type = 'file' },
          { name = 'surround.lua', type = 'file' },
        }
      end
      return {}
    end
    vim.uv.fs_stat = function(path)
      if path == '/mock/config/lua/test_plugins/mini/init.lua' then
        return { type = 'file' }
      end
      return original_fs_stat(path)
    end

    package.loaded['test_plugins.mini'] = { import = 'test_plugins.mini' }
    package.loaded['test_plugins.mini.ai'] = { 'echasnovski/mini.ai' }
    package.loaded['test_plugins.mini.surround'] = { 'echasnovski/mini.surround' }

    local state = require('zpack.state')
    helpers.mock_config_dir('/mock/config/lua/test_plugins/mini')
    helpers.mock_config_dir('/mock/config/lua/test_plugins')
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/echasnovski/mini.ai'],
      "mini.ai should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/echasnovski/mini.surround'],
      "mini.surround should be registered")

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.mini'] = nil
    package.loaded['test_plugins.mini.ai'] = nil
    package.loaded['test_plugins.mini.surround'] = nil
  end)

  it("duplicate import is skipped", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local lsdir_call_count = 0
    vim.fn.stdpath = function() return '/mock/config' end
    utils.lsdir = function(path)
      if path == '/mock/config/lua/test_plugins' then
        lsdir_call_count = lsdir_call_count + 1
        return {
          { name = 'foo.lua', type = 'file' },
        }
      end
      return {}
    end

    package.loaded['test_plugins.foo'] = { 'test/foo-plugin' }

    helpers.mock_config_dir('/mock/config/lua/test_plugins')
    require('zpack').setup({
      { import = 'test_plugins' },
      { import = 'test_plugins' },
    })
    helpers.flush_pending()

    assert.are.equal(1, lsdir_call_count)

    utils.lsdir = original_lsdir
    package.loaded['test_plugins.foo'] = nil
  end)

  it("spec with a non-string import is skipped, not crashed on", function()
    local state = require('zpack.state')
    -- A malformed `import` (a number/table instead of a module path) is
    -- reported by validation; setup() must not abort partway through.
    require('zpack').setup({ { import = 123 } })
    helpers.flush_pending()

    assert.is_truthy(state.is_setup,
      "setup() should complete despite the malformed import spec")
  end)

  it("spec with a non-string source is skipped, not crashed on", function()
    local state = require('zpack.state')
    -- `[1]` is a number, not a "user/plugin" string. normalize_source must
    -- not crash expanding it; the spec is skipped and setup() completes
    -- rather than aborting partway through. An option keeps it a spec rather
    -- than a list.
    require('zpack').setup({ spec = { { 42, opts = {} } } })
    helpers.flush_pending()

    assert.is_truthy(state.is_setup,
      "setup() should complete despite the malformed spec")
    assert.is_nil(next(state.spec_registry),
      "the malformed spec must be skipped, not registered")
  end)
end)
