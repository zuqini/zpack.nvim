local helpers = require('helpers')

describe("Spec Import", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("import loads *.lua files from directory", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/foo-plugin'], "foo-plugin should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/test/bar-plugin'], "bar-plugin should be registered")

    utils.lsdir = original_lsdir
    vim.fn.stdpath = original_stdpath
    package.loaded['test_plugins.foo'] = nil
    package.loaded['test_plugins.bar'] = nil
  end)

  it("import loads */init.lua files from subdirectories", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/mini-plugin'],
      "mini-plugin should be registered")

    utils.lsdir = original_lsdir
    vim.fn.stdpath = original_stdpath
    vim.uv.fs_stat = original_fs_stat
    package.loaded['test_plugins.mini'] = nil
  end)

  it("import loads both *.lua and */init.lua", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/telescope'], "telescope should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/test/mini'], "mini should be registered")

    utils.lsdir = original_lsdir
    vim.fn.stdpath = original_stdpath
    vim.uv.fs_stat = original_fs_stat
    package.loaded['test_plugins.telescope'] = nil
    package.loaded['test_plugins.mini'] = nil
  end)

  it("import only goes 1 level deep for init.lua", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/test/level1-plugin'],
      "level1-plugin should be registered")

    utils.lsdir = original_lsdir
    vim.fn.stdpath = original_stdpath
    vim.uv.fs_stat = original_fs_stat
    package.loaded['test_plugins.level1'] = nil
  end)

  it("import with enabled=false skips import", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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
    vim.fn.stdpath = original_stdpath
    package.loaded['test_plugins.foo'] = nil
  end)

  it("nested import works (init.lua with import)", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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
    require('zpack').setup({ { import = 'test_plugins' } })
    helpers.flush_pending()

    assert.is_not_nil(state.spec_registry['https://github.com/echasnovski/mini.ai'],
      "mini.ai should be registered")
    assert.is_not_nil(state.spec_registry['https://github.com/echasnovski/mini.surround'],
      "mini.surround should be registered")

    utils.lsdir = original_lsdir
    vim.fn.stdpath = original_stdpath
    vim.uv.fs_stat = original_fs_stat
    package.loaded['test_plugins.mini'] = nil
    package.loaded['test_plugins.mini.ai'] = nil
    package.loaded['test_plugins.mini.surround'] = nil
  end)

  it("duplicate import is skipped", function()
    local utils = require('zpack.utils')
    local original_lsdir = utils.lsdir
    local original_stdpath = vim.fn.stdpath
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

    require('zpack').setup({
      { import = 'test_plugins' },
      { import = 'test_plugins' },
    })
    helpers.flush_pending()

    assert.are.equal(1, lsdir_call_count)

    utils.lsdir = original_lsdir
    vim.fn.stdpath = original_stdpath
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
    -- An over-nested spec — `[1]` is a table, not a "user/plugin" string.
    -- normalize_source must not crash concatenating it; the spec is
    -- skipped and setup() completes rather than aborting partway through.
    require('zpack').setup({ spec = { { { 'user/plugin' } } } })
    helpers.flush_pending()

    assert.is_truthy(state.is_setup,
      "setup() should complete despite the malformed spec")
    assert.is_nil(next(state.spec_registry),
      "the malformed spec must be skipped, not registered")
  end)
end)
