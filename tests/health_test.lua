---@diagnostic disable: duplicate-set-field
local helpers = require('helpers')

---Replace vim.health with a capturing stub. Returns the report and a restore fn.
local function capture_health()
  local report = { sections = {} }
  local current
  local original = vim.health
  vim.health = {
    start = function(name)
      current = { name = name, items = {} }
      table.insert(report.sections, current)
    end,
    ok = function(msg) table.insert(current.items, { kind = 'ok', msg = msg }) end,
    warn = function(msg, advice)
      table.insert(current.items, { kind = 'warn', msg = msg, advice = advice })
    end,
    error = function(msg, advice)
      table.insert(current.items, { kind = 'error', msg = msg, advice = advice })
    end,
    info = function(msg) table.insert(current.items, { kind = 'info', msg = msg }) end,
  }
  return report, function() vim.health = original end
end

local function section(report, name)
  for _, sec in ipairs(report.sections) do
    if sec.name == name then
      return sec
    end
  end
  return nil
end

---True when `sec` has an item of `kind` whose message contains every needle.
local function has_item(sec, kind, needles)
  for _, item in ipairs(sec.items) do
    if item.kind == kind then
      local matched = true
      for _, needle in ipairs(needles) do
        if not item.msg:find(needle, 1, true) then
          matched = false
          break
        end
      end
      if matched then
        return true
      end
    end
  end
  return false
end

---Run health.check() against a freshly-required health module.
local function run_check()
  package.loaded['zpack.health'] = nil
  require('zpack.health').check()
end

describe("Health Check", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("check() produces every report section without error", function()
    local report, restore = capture_health()

    local ok, err = pcall(run_check)
    restore()
    assert.is_truthy(ok, "health.check() should not throw: " .. tostring(err))

    for _, name in ipairs({ 'Environment', 'Setup', 'Configuration', 'Plugins', 'Reporting a bug' }) do
      assert.is_not_nil(section(report, name), "missing section: " .. name)
    end
  end)

  it("environment section reports Neovim and vim.pack as OK", function()
    local report, restore = capture_health()
    run_check()
    restore()

    local env = section(report, 'Environment')
    assert.is_truthy(has_item(env, 'ok', { 'Neovim' }), "Neovim version should be OK")
    assert.is_truthy(has_item(env, 'ok', { 'vim.pack' }), "vim.pack should be OK")
  end)

  it("warns when setup() has not been called", function()
    local report, restore = capture_health()
    run_check()
    restore()

    local setup = section(report, 'Setup')
    assert.is_truthy(has_item(setup, 'warn', { 'setup()' }),
      "Setup section should warn that setup() was not called")
  end)

  it("after a valid setup, config is OK and plugins are counted", function()
    require('zpack').setup({
      spec = { { 'test/plugin' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local report, restore = capture_health()
    run_check()
    restore()

    local setup = section(report, 'Setup')
    assert.is_truthy(has_item(setup, 'ok', { 'setup()' }), "Setup should be OK")

    local config = section(report, 'Configuration')
    assert.is_truthy(has_item(config, 'ok', { 'valid' }), "Configuration should be valid")
    assert.is_truthy(has_item(config, 'ok', { 'No deprecated options' }),
      "no deprecated options should be reported")

    local plugins = section(report, 'Plugins')
    assert.is_truthy(has_item(plugins, 'ok', { 'plugin(s) registered' }),
      "Plugins section should report a registered count")
  end)

  it("surfaces deprecated options in use", function()
    require('zpack').setup({ spec = {}, confirm = false })
    helpers.flush_pending()

    local report, restore = capture_health()
    run_check()
    restore()

    local config = section(report, 'Configuration')
    assert.is_truthy(has_item(config, 'warn', { 'confirm' }),
      "Configuration section should warn about the deprecated confirm option")
  end)

  it("surfaces an invalid merged config", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = 'yes' } })
    helpers.flush_pending()

    local report, restore = capture_health()
    run_check()
    restore()

    local config = section(report, 'Configuration')
    assert.is_truthy(has_item(config, 'error', { 'defaults.confirm' }),
      "Configuration section should report the bad defaults.confirm field")
  end)
end)
