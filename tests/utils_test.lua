local helpers = require('helpers')

describe("lsdir utility", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("lsdir returns entries for existing directory", function()
    local utils = require('zpack.utils')
    local entries = utils.lsdir(vim.fn.stdpath('config') .. '/lua')

    assert.are.equal('table', type(entries))
  end)

  it("lsdir returns empty table for non-existent directory", function()
    local utils = require('zpack.utils')
    local entries = utils.lsdir('/non/existent/path/that/does/not/exist')

    assert.are.equal('table', type(entries))
    assert.are.equal(0, #entries)
  end)

  it("lsdir caches results", function()
    local utils = require('zpack.utils')
    local test_path = '/test/cache/path'

    local call_count = 0
    local original_fs_scandir = vim.uv.fs_scandir
    vim.uv.fs_scandir = function(path)
      if path == test_path then
        call_count = call_count + 1
        return nil
      end
      return original_fs_scandir(path)
    end

    utils.lsdir(test_path)
    utils.lsdir(test_path)
    utils.lsdir(test_path)

    assert.are.equal(1, call_count)

    vim.uv.fs_scandir = original_fs_scandir
  end)

  it("lsdir entries have name and type", function()
    local utils = require('zpack.utils')
    local original_fs_scandir = vim.uv.fs_scandir
    local original_fs_scandir_next = vim.uv.fs_scandir_next

    local call_idx = 0
    vim.uv.fs_scandir = function(path)
      if path == '/mock/dir' then
        return 'mock_handle'
      end
      return original_fs_scandir(path)
    end
    vim.uv.fs_scandir_next = function(handle)
      if handle == 'mock_handle' then
        call_idx = call_idx + 1
        if call_idx == 1 then
          return 'file.lua', 'file'
        elseif call_idx == 2 then
          return 'subdir', 'directory'
        end
        return nil
      end
      return original_fs_scandir_next(handle)
    end

    local entries = utils.lsdir('/mock/dir')

    assert.are.equal(2, #entries)
    assert.are.equal('file.lua', entries[1].name)
    assert.are.equal('file', entries[1].type)
    assert.are.equal('subdir', entries[2].name)
    assert.are.equal('directory', entries[2].type)

    vim.uv.fs_scandir = original_fs_scandir
    vim.uv.fs_scandir_next = original_fs_scandir_next
  end)

  it("reset_lsdir_cache clears cache", function()
    local utils = require('zpack.utils')
    local test_path = '/test/reset/path'

    local call_count = 0
    local original_fs_scandir = vim.uv.fs_scandir
    vim.uv.fs_scandir = function(path)
      if path == test_path then
        call_count = call_count + 1
        return nil
      end
      return original_fs_scandir(path)
    end

    utils.lsdir(test_path)
    assert.are.equal(1, call_count)

    utils.reset_lsdir_cache()
    utils.lsdir(test_path)
    assert.are.equal(2, call_count)

    vim.uv.fs_scandir = original_fs_scandir
  end)
end)

describe("is_semver_like utility", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("detects wildcard patterns", function()
    local utils = require('zpack.utils')

    assert.are.equal(true, utils.is_semver_like('1.*'))
    assert.are.equal(true, utils.is_semver_like('*'))
    assert.are.equal(true, utils.is_semver_like('1.2.*'))
    assert.are.equal(true, utils.is_semver_like('1.2.x'))
    assert.are.equal(true, utils.is_semver_like('1.x'))
    assert.are.equal(true, utils.is_semver_like('1.X'))
    assert.are.equal(true, utils.is_semver_like('1.2.X'))
    assert.are.equal(true, utils.is_semver_like('1.2.y'))
    assert.are.equal(true, utils.is_semver_like('1.a.b'))
  end)

  it("detects range operators", function()
    local utils = require('zpack.utils')

    assert.are.equal(true, utils.is_semver_like('>=1.0.0'))
    assert.are.equal(true, utils.is_semver_like('<=2.0.0'))
    assert.are.equal(true, utils.is_semver_like('>1.0'))
    assert.are.equal(true, utils.is_semver_like('<2.0'))
    assert.are.equal(true, utils.is_semver_like('^1.0.0'))
    assert.are.equal(true, utils.is_semver_like('~1.0.0'))
    assert.are.equal(true, utils.is_semver_like('foo=bar'))
  end)

  it("detects bare semver patterns", function()
    local utils = require('zpack.utils')

    assert.are.equal(true, utils.is_semver_like('1.0.0'))
    assert.are.equal(true, utils.is_semver_like('1.2'))
    assert.are.equal(true, utils.is_semver_like('1.2.3.4'))
  end)

  it("returns false for branch/tag names", function()
    local utils = require('zpack.utils')

    assert.are.equal(false, utils.is_semver_like('main'))
    assert.are.equal(false, utils.is_semver_like('master'))
    assert.are.equal(false, utils.is_semver_like('v1.0.0'))
    assert.are.equal(false, utils.is_semver_like('v1.x'))
    assert.are.equal(false, utils.is_semver_like('release-1.0'))
    assert.are.equal(false, utils.is_semver_like('feature/foo'))
  end)

  it("returns false for non-strings", function()
    local utils = require('zpack.utils')

    assert.are.equal(false, utils.is_semver_like(nil))
    assert.are.equal(false, utils.is_semver_like(123))
    assert.are.equal(false, utils.is_semver_like({}))
  end)
end)

describe('latch_first_call', function()
  it("invokes the inner callback exactly once across repeated calls", function()
    local utils = require('zpack.utils')
    local count = 0
    local latched = utils.latch_first_call(function() count = count + 1 end)

    latched()
    latched()
    latched()

    assert.are.equal(1, count,
      "Latch must absorb every call after the first (guards nvim#25526 double-dispatch)")
  end)

  it("forwards args and the return value on the first call", function()
    local utils = require('zpack.utils')
    local seen
    local latched = utils.latch_first_call(function(a, b)
      seen = { a, b }
      return a + b
    end)

    local result = latched(2, 3)
    assert.are.same({ 2, 3 }, seen)
    assert.are.equal(5, result)

    assert.is_nil(latched(99, 1),
      "Subsequent calls must not invoke the inner — return nil")
  end)
end)
