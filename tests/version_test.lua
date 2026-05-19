---@diagnostic disable: duplicate-set-field
local helpers = require('helpers')

describe("Version Normalization", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("version field takes priority over other version fields", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          version = 'main',
          branch = 'develop',
          tag = 'v1.0.0',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal('main', vim_pack_call[1].version)
  end)

  it("sem_version field is wrapped with vim.version.range()", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          sem_version = '^6',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")

    local version = vim_pack_call[1].version
    assert.is_not_nil(version, "version should be set")
    assert.are.equal('table', type(version))
    assert.is_not_nil(version.from, "vim.VersionRange should have 'from' field")
  end)

  it("branch field maps to version", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          branch = 'develop',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal('develop', vim_pack_call[1].version)
  end)

  it("tag field maps to version", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          tag = 'v1.0.0',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal('v1.0.0', vim_pack_call[1].version)
  end)

  it("commit field maps to version", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          commit = 'abc123def',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal('abc123def', vim_pack_call[1].version)
  end)

  it("sem_version takes priority over branch/tag/commit", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          sem_version = '^1.0.0',
          branch = 'main',
          tag = 'v1.0.0',
          commit = 'abc123',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")

    local version = vim_pack_call[1].version
    assert.are.equal('table', type(version))
  end)

  it("branch takes priority over tag and commit", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          branch = 'develop',
          tag = 'v1.0.0',
          commit = 'abc123',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal('develop', vim_pack_call[1].version)
  end)

  it("tag takes priority over commit", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          tag = 'v2.0.0',
          commit = 'abc123',
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal('v2.0.0', vim_pack_call[1].version)
  end)

  it("no version fields results in nil version", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin' },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.is_nil(vim_pack_call[1].version, "version should be nil when no version fields provided")
  end)

  it("vim.VersionRange passed directly through version field", function()
    local range = vim.version.range('^6')
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          version = range,
        },
      },
      defaults = { confirm = false },
    })

    local vim_pack_call = _G.test_state.vim_pack_calls[1]
    assert.is_not_nil(vim_pack_call, "vim.pack.add should have been called")
    assert.are.equal(range, vim_pack_call[1].version)
  end)

  it("semver-like version emits warning when vim.pack.add fails", function()
    local mock_vim_pack_add = vim.pack.add
    vim.pack.add = function()
      error("some error from vim.pack.add")
    end

    local ok = pcall(function()
      require('zpack').setup({
        spec = {
          {
            'test/plugin',
            version = '1.*',
          },
        },
        defaults = { confirm = false },
      })
    end)

    assert.are.equal(false, ok)
    assert.are.equal(true, #_G.test_state.notifications >= 2)

    local found_header = false
    local found_detail = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:match('`vim%.pack%.add` failed') then
        found_header = true
      end
      if notif.msg:match('sem_version') and notif.msg:match('1%.%*') then
        found_detail = true
      end
    end
    assert.are.equal(true, found_header)
    assert.are.equal(true, found_detail)

    vim.pack.add = mock_vim_pack_add
  end)

  it("multiple semver-like versions emit multiple warnings", function()
    local mock_vim_pack_add = vim.pack.add
    vim.pack.add = function()
      error("some error from vim.pack.add")
    end

    local ok = pcall(function()
      require('zpack').setup({
        spec = {
          { 'test/plugin-a', version = '1.*' },
          { 'test/plugin-b', version = '^2.0.0' },
          { 'test/plugin-c', version = 'main' },
        },
        defaults = { confirm = false },
      })
    end)

    assert.are.equal(false, ok)

    local found_header = false
    local detail_count = 0
    local found_plugin_a = false
    local found_plugin_b = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:match('`vim%.pack%.add` failed') then
        found_header = true
      end
      if notif.msg:match('sem_version') then
        detail_count = detail_count + 1
        if notif.msg:match('1%.%*') and notif.msg:match('plugin%-a') then
          found_plugin_a = true
        end
        if notif.msg:match('%^2%.0%.0') and notif.msg:match('plugin%-b') then
          found_plugin_b = true
        end
      end
    end

    assert.are.equal(true, found_header)
    assert.are.equal(2, detail_count)
    assert.are.equal(true, found_plugin_a)
    assert.are.equal(true, found_plugin_b)

    vim.pack.add = mock_vim_pack_add
  end)

  it("no warning when vim.pack.add fails but no semver-like versions", function()
    local mock_vim_pack_add = vim.pack.add
    vim.pack.add = function()
      error("some error from vim.pack.add")
    end

    local ok = pcall(function()
      require('zpack').setup({
        spec = {
          {
            'test/plugin',
            version = 'nonexistent-branch',
          },
        },
        defaults = { confirm = false },
      })
    end)

    assert.are.equal(false, ok)

    local found_warning = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:match('sem_version') then
        found_warning = true
        break
      end
    end
    assert.are.equal(false, found_warning)

    vim.pack.add = mock_vim_pack_add
  end)
end)
