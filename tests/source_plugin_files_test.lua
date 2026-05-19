local helpers = require('helpers')

describe("source_after_plugin_files", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("sources lua files from after/plugin/ directory", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local after_dir = tmpdir .. "/after/plugin"
    vim.fn.mkdir(after_dir, "p")

    local test_file = after_dir .. "/test_after.lua"
    local f = io.open(test_file, "w")
    f:write("_G._test_source_after_ran = true\n")
    f:close()

    _G._test_source_after_ran = nil
    utils.source_after_plugin_files(tmpdir)

    assert.is_truthy(_G._test_source_after_ran == true,
      "after/plugin/ lua file should be sourced")

    _G._test_source_after_ran = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("sources nested files from after/plugin/ subdirectories", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local subdir = tmpdir .. "/after/plugin/subdir"
    vim.fn.mkdir(subdir, "p")

    local test_file = subdir .. "/foo.lua"
    local f = io.open(test_file, "w")
    f:write("_G._test_nested_ran = true\n")
    f:close()

    _G._test_nested_ran = nil
    utils.source_after_plugin_files(tmpdir)

    assert.is_truthy(_G._test_nested_ran == true,
      "after/plugin/subdir/foo.lua should be sourced")

    _G._test_nested_ran = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("sources deeply nested files", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local deep_dir = tmpdir .. "/after/plugin/a/b/c"
    vim.fn.mkdir(deep_dir, "p")

    local test_file = deep_dir .. "/deep.lua"
    local f = io.open(test_file, "w")
    f:write("_G._test_deep_ran = true\n")
    f:close()

    _G._test_deep_ran = nil
    utils.source_after_plugin_files(tmpdir)

    assert.is_truthy(_G._test_deep_ran == true,
      "after/plugin/a/b/c/deep.lua should be sourced")

    _G._test_deep_ran = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("sources both top-level and nested files", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local after_dir = tmpdir .. "/after/plugin"
    local sub_dir = after_dir .. "/sub"
    vim.fn.mkdir(sub_dir, "p")

    local f = io.open(after_dir .. "/top.lua", "w")
    f:write("_G._test_top_ran = true\n")
    f:close()

    f = io.open(sub_dir .. "/deep.lua", "w")
    f:write("_G._test_sub_deep_ran = true\n")
    f:close()

    _G._test_top_ran = nil
    _G._test_sub_deep_ran = nil
    utils.source_after_plugin_files(tmpdir)

    assert.is_truthy(_G._test_top_ran == true,
      "after/plugin/top.lua should be sourced")
    assert.is_truthy(_G._test_sub_deep_ran == true,
      "after/plugin/sub/deep.lua should be sourced")

    _G._test_top_ran = nil
    _G._test_sub_deep_ran = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("does not source same path twice", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local after_dir = tmpdir .. "/after/plugin"
    vim.fn.mkdir(after_dir, "p")

    local test_file = after_dir .. "/counter.lua"
    local f = io.open(test_file, "w")
    f:write("_G._test_source_count = (_G._test_source_count or 0) + 1\n")
    f:close()

    _G._test_source_count = nil
    utils.source_after_plugin_files(tmpdir)
    utils.source_after_plugin_files(tmpdir)

    assert.are.equal(1, _G._test_source_count)

    _G._test_source_count = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("handles missing directories gracefully", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")

    local ok, err = pcall(utils.source_after_plugin_files, tmpdir)
    assert.is_truthy(ok, "should not error on missing directories: " .. tostring(err))

    vim.fn.delete(tmpdir, "rf")
  end)

  it("skips non-lua non-vim files in nested dirs", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local sub_dir = tmpdir .. "/after/plugin/sub"
    vim.fn.mkdir(sub_dir, "p")

    local txt_file = sub_dir .. "/readme.txt"
    local f = io.open(txt_file, "w")
    f:write("_G._test_txt_sourced = true\n")
    f:close()

    local lua_file = sub_dir .. "/real.lua"
    f = io.open(lua_file, "w")
    f:write("_G._test_lua_sourced = true\n")
    f:close()

    _G._test_txt_sourced = nil
    _G._test_lua_sourced = nil
    utils.source_after_plugin_files(tmpdir)

    assert.is_nil(_G._test_txt_sourced, ".txt file should not be sourced")
    assert.is_truthy(_G._test_lua_sourced == true, ".lua file should be sourced")

    _G._test_txt_sourced = nil
    _G._test_lua_sourced = nil
    vim.fn.delete(tmpdir, "rf")
  end)
end)
