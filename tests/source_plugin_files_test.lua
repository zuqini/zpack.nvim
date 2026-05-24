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

  -- Regression: the cache flag used to be set before the source loop, AND a
  -- throw propagated out of the loop instead of being caught per-file. The
  -- combination meant a throw on file N skipped N+1..end with no retry.
  -- Per-file pcall now ensures every file is attempted on the first call.
  it("continues sourcing later files when one throws", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local after_dir = tmpdir .. "/after/plugin"
    vim.fn.mkdir(after_dir, "p")

    local f = io.open(after_dir .. "/a_throws.lua", "w")
    f:write("error('intentional throw from a_throws.lua')\n")
    f:close()

    f = io.open(after_dir .. "/b_after.lua", "w")
    f:write("_G._test_b_ran = true\n")
    f:close()

    _G._test_b_ran = nil
    utils.source_after_plugin_files(tmpdir)
    helpers.flush_pending()

    assert.is_true(_G._test_b_ran == true,
      "later file must still source after an earlier file throws")

    local saw_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to source.*a_throws%.lua") then
        saw_notify = true
        break
      end
    end
    assert.is_true(saw_notify, "throwing file should surface a structured notify")

    _G._test_b_ran = nil
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

describe("source_ftdetect_files", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("sources lua files from ftdetect/ directory", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local ftdetect_dir = tmpdir .. "/ftdetect"
    vim.fn.mkdir(ftdetect_dir, "p")

    local f = io.open(ftdetect_dir .. "/zztest.lua", "w")
    f:write("_G._test_ftdetect_ran = true\n")
    f:close()

    _G._test_ftdetect_ran = nil
    utils.source_ftdetect_files(tmpdir)

    assert.is_true(_G._test_ftdetect_ran == true,
      "ftdetect/ lua file should be sourced")

    _G._test_ftdetect_ran = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("does not source same path twice", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local ftdetect_dir = tmpdir .. "/ftdetect"
    vim.fn.mkdir(ftdetect_dir, "p")

    local f = io.open(ftdetect_dir .. "/counter.lua", "w")
    f:write("_G._test_ftdetect_count = (_G._test_ftdetect_count or 0) + 1\n")
    f:close()

    _G._test_ftdetect_count = nil
    utils.source_ftdetect_files(tmpdir)
    utils.source_ftdetect_files(tmpdir)

    assert.are.equal(1, _G._test_ftdetect_count)

    _G._test_ftdetect_count = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  it("handles missing ftdetect/ directory gracefully", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")

    local ok, err = pcall(utils.source_ftdetect_files, tmpdir)
    assert.is_true(ok, "should not error on missing ftdetect/: " .. tostring(err))

    vim.fn.delete(tmpdir, "rf")
  end)

  it("continues sourcing later files when one throws", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local ftdetect_dir = tmpdir .. "/ftdetect"
    vim.fn.mkdir(ftdetect_dir, "p")

    local f = io.open(ftdetect_dir .. "/a_throws.lua", "w")
    f:write("error('intentional throw from a_throws.lua')\n")
    f:close()

    f = io.open(ftdetect_dir .. "/b_ok.lua", "w")
    f:write("_G._test_ftdetect_b_ran = true\n")
    f:close()

    _G._test_ftdetect_b_ran = nil
    utils.source_ftdetect_files(tmpdir)
    helpers.flush_pending()

    assert.is_true(_G._test_ftdetect_b_ran == true,
      "later file must still source after an earlier file throws")

    local saw_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to source.*a_throws%.lua") then
        saw_notify = true
        break
      end
    end
    assert.is_true(saw_notify, "throwing file should surface a structured notify")

    _G._test_ftdetect_b_ran = nil
    vim.fn.delete(tmpdir, "rf")
  end)

  -- Regression: a throwing ftdetect file used to leak the `filetypedetect`
  -- augroup (the `augroup END` was `|`-chained with the `source` and never
  -- ran on throw). Any subsequent vimscript `autocmd` then landed in
  -- `filetypedetect` instead of the default group.
  it("throwing ftdetect file does not leak filetypedetect augroup", function()
    local utils = require('zpack.utils')
    local tmpdir = vim.fn.tempname()
    local ftdetect_dir = tmpdir .. "/ftdetect"
    vim.fn.mkdir(ftdetect_dir, "p")

    local f = io.open(ftdetect_dir .. "/boom.lua", "w")
    f:write("error('intentional throw')\n")
    f:close()

    utils.source_ftdetect_files(tmpdir)
    helpers.flush_pending()

    -- Register a vimscript autocmd with no explicit group; if the augroup
    -- leaked, this would be reported under `filetypedetect`.
    vim.cmd([[autocmd BufRead *.zz_augroup_check echo "test"]])
    local listing = vim.fn.execute("autocmd BufRead *.zz_augroup_check")

    assert.is_nil(listing:match("filetypedetect"),
      "subsequent autocmd must not land in the filetypedetect augroup")

    vim.cmd([[autocmd! BufRead *.zz_augroup_check]])
    vim.fn.delete(tmpdir, "rf")
  end)
end)
