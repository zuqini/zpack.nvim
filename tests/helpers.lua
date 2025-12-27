local M = {}

M.test_results = {}
M.test_count = 0
M.passed_count = 0
M.failed_count = 0

function M.reset()
  M.test_results = {}
  M.test_count = 0
  M.passed_count = 0
  M.failed_count = 0
end

function M.assert_equal(actual, expected, msg)
  if actual ~= expected then
    error(string.format(
      "%s\nExpected: %s\nActual: %s",
      msg or "Assertion failed",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

function M.assert_true(condition, msg)
  if not condition then
    error(msg or "Expected true but got false")
  end
end

function M.assert_false(condition, msg)
  if condition then
    error(msg or "Expected false but got true")
  end
end

function M.assert_nil(value, msg)
  if value ~= nil then
    error(string.format("%s\nExpected nil but got: %s", msg or "Assertion failed", vim.inspect(value)))
  end
end

function M.assert_not_nil(value, msg)
  if value == nil then
    error(msg or "Expected non-nil value")
  end
end

function M.assert_table_contains(tbl, value, msg)
  for _, v in ipairs(tbl) do
    if v == value then
      return
    end
  end
  error(string.format(
    "%s\nTable does not contain: %s\nTable: %s",
    msg or "Assertion failed",
    vim.inspect(value),
    vim.inspect(tbl)
  ))
end

function M.test(name, fn)
  M.test_count = M.test_count + 1
  local success, err = pcall(fn)

  if success then
    M.passed_count = M.passed_count + 1
    table.insert(M.test_results, { name = name, passed = true })
    print(string.format("✓ %s", name))
  else
    M.failed_count = M.failed_count + 1
    table.insert(M.test_results, { name = name, passed = false, error = err })
    print(string.format("✗ %s", name))
    print(string.format("  Error: %s", err))
  end
end

function M.describe(description, fn)
  print(string.format("\n%s", description))
  fn()
end

function M.summary()
  print(string.format("\n%s", string.rep("=", 60)))
  print(string.format("Tests: %d total, %d passed, %d failed",
    M.test_count, M.passed_count, M.failed_count))
  print(string.rep("=", 60))

  if M.failed_count > 0 then
    print("\nFailed tests:")
    for _, result in ipairs(M.test_results) do
      if not result.passed then
        print(string.format("  - %s", result.name))
      end
    end
  end

  return M.failed_count == 0
end

function M.setup_test_env()
  _G.test_state = {
    loaded_plugins = {},
    executed_hooks = {},
    created_commands = {},
    created_keymaps = {},
    triggered_events = {},
    vim_pack_calls = {},
  }

  -- Mock vim.pack.add to prevent actual plugin installation
  _G.test_state.original_vim_pack_add = vim.pack.add
  vim.pack.add = function(specs)
    table.insert(_G.test_state.vim_pack_calls, specs)
    -- Don't actually install anything
    return
  end
end

function M.cleanup_test_env()
  -- Clear autocmds before reloading modules
  if package.loaded['zpack.state'] then
    local state = package.loaded['zpack.state']
    if state.lazy_group then
      vim.api.nvim_clear_autocmds({ group = state.lazy_group })
    end
    if state.startup_group then
      vim.api.nvim_clear_autocmds({ group = state.startup_group })
    end
    if state.lazy_build_group then
      vim.api.nvim_clear_autocmds({ group = state.lazy_build_group })
    end
  end

  -- Restore original vim.pack.add
  if _G.test_state and _G.test_state.original_vim_pack_add then
    vim.pack.add = _G.test_state.original_vim_pack_add
  end

  _G.test_state = nil

  -- Force reload all zpack modules to reset state
  package.loaded['zpack.state'] = nil
  package.loaded['zpack.init'] = nil
  package.loaded['zpack.import'] = nil
  package.loaded['zpack.registration'] = nil
  package.loaded['zpack.startup'] = nil
  package.loaded['zpack.lazy'] = nil
  package.loaded['zpack.hooks'] = nil
  package.loaded['zpack.loader'] = nil
  package.loaded['zpack.lazy_trigger.event'] = nil
  package.loaded['zpack.lazy_trigger.ft'] = nil
  package.loaded['zpack.lazy_trigger.cmd'] = nil
  package.loaded['zpack.lazy_trigger.keys'] = nil
  package.loaded['zpack.keymap'] = nil
  package.loaded['zpack.utils'] = nil
  package.loaded['zpack.commands'] = nil
end

function M.track_plugin_load(plugin_name)
  table.insert(_G.test_state.loaded_plugins, plugin_name)
end

function M.track_hook_execution(hook_name, plugin_src)
  table.insert(_G.test_state.executed_hooks, { hook = hook_name, src = plugin_src })
end

function M.wait_for_condition(condition, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 1000
  interval_ms = interval_ms or 10

  local start = vim.loop.now()
  while vim.loop.now() - start < timeout_ms do
    if condition() then
      return true
    end
    vim.wait(interval_ms)
  end
  return false
end

return M
