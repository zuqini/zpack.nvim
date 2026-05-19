---@diagnostic disable: duplicate-set-field
local helpers = require('helpers')

---Find a notification whose message contains every needle, at an optional level.
local function find_notification(needles, level)
  for _, notif in ipairs(_G.test_state.notifications) do
    local matched = true
    for _, needle in ipairs(needles) do
      if not notif.msg:find(needle, 1, true) then
        matched = false
        break
      end
    end
    if matched and (level == nil or notif.level == level) then
      return notif
    end
  end
  return nil
end

describe("Config Validation", function()
  it("validate_config accepts a valid options table", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({
      cmd_name = 'ZPack',
      spec = {},
      defaults = { confirm = false, cond = function() return true end },
      performance = { vim_loader = true },
      profiling = { loader = false, require = false },
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

  it("validate_config flags a non-string legacy plugins_dir", function()
    local validate = require('zpack.validate')
    local errors = validate.validate_config({ plugins_dir = 123 })
    assert.are.equal(1, #errors)
    assert.is_truthy(errors[1]:find('plugins_dir', 1, true) ~= nil,
      "error should name plugins_dir")
  end)

  it("validate_config accepts a merged config (no spec/legacy fields)", function()
    local validate = require('zpack.validate')
    -- Mirrors what :checkhealth passes: a fully merged zpack.Config.
    local errors = validate.validate_config({
      cmd_name = 'ZPack',
      defaults = { confirm = true },
      performance = { vim_loader = true },
      profiling = { loader = false, require = false },
    })
    assert.are.equal(0, #errors)
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
      enabled = function() return true end,
    })
    assert.are.equal(0, #errors)
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
