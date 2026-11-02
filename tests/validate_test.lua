---@diagnostic disable: duplicate-set-field
local helpers = require('helpers')

local find_notification = helpers.find_notification

describe("Config Validation", function()
  it("validate_config accepts a valid options table", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({
      cmd_name = 'ZPack',
      spec = {},
      defaults = { confirm = false, cond = function() return true end },
      performance = { vim_loader = true },
    })
    assert.are.equal(0, #errors)
  end)

  it("validate_config rejects a non-table opts", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config('nope')
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('expected table', 1, true) ~= nil,
      "error should mention expected table")
  end)

  it("validate_config flags a non-table defaults section", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({ defaults = 'oops' })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('defaults:', 1, true) ~= nil,
      "error should name the defaults field")
  end)

  it("validate_config flags a wrong-typed nested field", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({ defaults = { confirm = 'yes' } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('defaults.confirm', 1, true) ~= nil,
      "error should name defaults.confirm with its field path")
    assert.is_truthy(errors[1]:find('boolean', 1, true) ~= nil,
      "error should state the expected type")
  end)

  it("validate_config accepts a merged config (no spec field)", function()
    local validate = require('zpack.validate')
    -- Mirrors what :checkhealth passes: a fully merged zpack.Config.
    local errors = validate.validate_config({
      cmd_name = 'ZPack',
      defaults = { confirm = true },
      performance = { vim_loader = true },
      dev = { path = '~/projects', fallback = false },
    })
    assert.are.equal(0, #errors)
  end)

  it("validate_config ignores keys it doesn't know, like the removed profiling", function()
    local validate = require('zpack.validate')
    assert.are.equal(0, #validate.validate_config({ profiling = { loader = false } }))
    assert.are.equal(0, #validate.validate_config({ profiling = 'oops' }))
  end)

  it("validate_config accepts defaults.lazy and defaults.version", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({
      defaults = { lazy = true, version = 'main' },
    })
    assert.are.equal(0, #errors)

    errors = validate.validate_config({
      defaults = { version = vim.version.range('^1') },
    })
    assert.are.equal(0, #errors)
  end)

  it("validate_config flags a non-boolean defaults.lazy", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({ defaults = { lazy = 'yes' } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('defaults.lazy', 1, true) ~= nil,
      "error should name defaults.lazy")
    assert.is_truthy(errors[1]:find('boolean', 1, true) ~= nil,
      "error should state expected boolean")
  end)

  it("validate_config flags a wrong-typed defaults.version", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({ defaults = { version = 123 } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('defaults.version', 1, true) ~= nil,
      "error should name defaults.version")
  end)

  it("validate_config accepts defaults.version=false (the no-default opt-out)", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({ defaults = { version = false } })
    assert.are.equal(0, #errors,
      "defaults.version=false is the documented opt-out and must not error")
  end)
end)

describe("Spec Validation", function()
  it("validate_spec accepts a valid spec", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({
      'user/plugin',
      lazy = true,
      priority = 100,
      event = 'BufRead',
      cmd = { 'Foo', 'Bar' },
      config = true,
      opts = {},
      opts_extend = { 'ensure_installed' },
      enabled = function() return true end,
    })
    assert.are.equal(0, #errors)
  end)

  it("validate_spec accepts a single opts_extend key", function()
    local validate = require('zpack.validate')
    assert.are.equal(0, #validate.validate_spec({ 'user/plugin', opts_extend = 'ensure_installed' }))
  end)

  it("validate_spec flags an empty segment in a single opts_extend key", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', opts_extend = 'ensure_installed.' })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('empty segment', 1, true) ~= nil, "error should name the empty segment")
  end)

  it("validate_spec flags an opts_extend that is neither a key nor a list", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', opts_extend = true })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('opts_extend', 1, true) ~= nil, "error should name opts_extend")
  end)

  it("validate_spec flags a non-string opts_extend key", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', opts_extend = { 'ok', 1 } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('opts_extend[2]', 1, true) ~= nil, "error should name opts_extend[2]")
  end)

  it("validate_spec flags an opts_extend that is not a list", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', opts_extend = { ensure_installed = true } })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('opts_extend', 1, true) ~= nil, "error should name opts_extend")
  end)

  it("validate_spec flags opts_extend keys with an empty segment", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', opts_extend = { 'a.', 'a..b', 'a.b' } })
    assert.are.equal(2, #errors)
    assert.is_truthy(errors[1]:find('opts_extend[1]', 1, true) ~= nil, "error should name opts_extend[1]")
    assert.is_truthy(errors[2]:find('opts_extend[2]', 1, true) ~= nil, "error should name opts_extend[2]")
  end)

  it("validate_spec flags a non-boolean lazy", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', lazy = 'yes' })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('lazy', 1, true) ~= nil, "error should name lazy")
    assert.is_truthy(errors[1]:find('boolean', 1, true) ~= nil,
      "error should state expected boolean")
  end)

  it("validate_spec flags a non-number priority", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', priority = 'high' })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('priority', 1, true) ~= nil, "error should name priority")
  end)

  it("validate_spec flags a wrong-typed [1] source", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 123 })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('[1]', 1, true) ~= nil, "error should name the [1] field")
  end)

  it("validate_spec flags a [1] that looks like a local path", function()
    local validate = require('zpack.validate')
    for _, path in ipairs({ '~/repo', './repo', '/home/user/repo' }) do
      local errors = validate.validate_spec({ path })
      assert.are.equal(1, #errors, path)
      assert.is_truthy(errors[1]:find('use dir', 1, true) ~= nil,
        path .. " should point at dir")
    end
    assert.are.equal(0, #validate.validate_spec({ 'https://forge.example.com/owner/repo' }))
    assert.are.equal(0, #validate.validate_spec({ 'git@example.com:owner/repo.git' }))
  end)

  it("validate_spec does not flag a path-like [1] when an explicit source is set", function()
    local validate = require('zpack.validate')
    -- With src/url/dir present, [1] only feeds the name and never reaches git.
    assert.are.equal(0, #validate.validate_spec({ '~/repo', dir = '~/repo' }))
    assert.are.equal(0, #validate.validate_spec({ './repo', src = 'https://forge.example.com/owner/repo' }))
    assert.are.equal(0, #validate.validate_spec({ '/home/user/repo', url = 'https://forge.example.com/owner/repo' }))
    -- A dev spec loads from dev.path; [1] reaches git only under
    -- dev.fallback = true with a missing checkout, which validate cannot
    -- see, so it is not flagged.
    assert.are.equal(0, #validate.validate_spec({ '~/repo', dev = true }))
  end)

  it("validate_spec flags a sem_version that isn't a semver range", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ 'user/plugin', sem_version = 'abc' })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('sem_version "abc" is not a semver range', 1, true))
    assert.are.equal(0, #validate.validate_spec({ 'user/plugin', sem_version = '^1.2' }))
    assert.are.equal(0, #validate.validate_spec({ 'user/plugin', sem_version = '1.x' }))
  end)

  it("validate_spec rejects a non-table spec", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec('user/plugin')
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('expected spec table', 1, true) ~= nil,
      "error should mention expected spec table")
  end)

  it("validate_spec flags a spec with no plugin source", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ event = 'BufRead' })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('no plugin source', 1, true) ~= nil,
      "error should mention the missing source")
  end)

  it("validate_spec accepts an import spec with no source", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_spec({ import = 'plugins' })
    assert.are.equal(0, #errors)
  end)
end)

describe("Validation wired into setup()", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("invalid setup options emit an error notification but do not abort", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = 'yes' } })
    helpers.flush_pending()

    local notif = find_notification({ 'invalid options', 'defaults.confirm' }, vim.log.levels.ERROR)
    assert.is_not_nil(notif, "an error notification naming defaults.confirm should be emitted")

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['ZPack'], ":ZPack should still register — validation is advisory")
  end)

  it("a non-table section is reported and ignored without crashing", function()
    local ok = pcall(require('zpack').setup, { spec = {}, defaults = 'oops' })
    assert.is_truthy(ok, "setup must not crash on a non-table section")

    helpers.flush_pending()

    local notif = find_notification({ 'invalid options', 'defaults:' }, vim.log.levels.ERROR)
    assert.is_not_nil(notif, "the bad defaults section should be reported")

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['ZPack'], ":ZPack should still register")
  end)

  describe("given something other than a table", function()
    local function setup_with_default_import(arg)
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. '/lua', 'p')
      vim.fn.writefile({}, root .. '/lua/plugins.lua')
      package.loaded.plugins = { 'test/from-default-import' }
      local stdpath = vim.fn.stdpath
      vim.fn.stdpath = function(what) return what == 'config' and root or stdpath(what) end
      local ok, err = pcall(require('zpack').setup, arg)
      vim.fn.stdpath = stdpath
      package.loaded.plugins = nil
      assert.is_true(ok, err)
      helpers.flush_pending()
      assert.is_not_nil(require('zpack.state').spec_registry['https://github.com/test/from-default-import'])
      assert.is_not_nil(vim.api.nvim_get_commands({})['ZPack'])
    end

    for name, arg in pairs({
      number = 42,
      boolean = true,
      ['function'] = function() end,
    }) do
      it(name .. " is reported, then the default plugins are imported", function()
        setup_with_default_import(arg)
        assert.is_not_nil(find_notification({ 'invalid options', 'expected table, got ' .. type(arg) }, vim.log.levels.ERROR))
      end)
    end

    it("false reads as no options", function()
      setup_with_default_import(false)
      assert.is_nil(find_notification({ 'invalid options' }))
    end)
  end)

  it("a malformed spec emits a warning naming the field", function()
    require('zpack').setup({ spec = { { 'test/plugin', lazy = 'yes' } } })
    helpers.flush_pending()

    local notif = find_notification({ 'invalid spec', 'test/plugin', 'lazy' }, vim.log.levels.WARN)
    assert.is_not_nil(notif, "a warning naming the bad spec field should be emitted")
  end)

  it("a sourceless spec is reported and does not abort setup()", function()
    local ok = pcall(require('zpack').setup, { spec = { { event = 'BufRead' } } })
    assert.is_truthy(ok, "setup must not abort on a sourceless spec")

    helpers.flush_pending()

    local notif = find_notification({ 'invalid spec', 'no plugin source' }, vim.log.levels.WARN)
    assert.is_not_nil(notif, "the sourceless spec should be reported")

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds['ZPack'], ":ZPack should still register")
  end)

  it("a valid config emits no validation notification", function()
    require('zpack').setup({
      spec = { { 'test/plugin' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(find_notification({ 'invalid options' }),
      "no invalid-options notification for a valid config")
    assert.is_nil(find_notification({ 'invalid spec' }),
      "no invalid-spec notification for a valid spec")
  end)
end)
