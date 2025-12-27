# zpack.nvim Test Suite

Comprehensive test suite for zpack.nvim covering all major flows and lazy-loading paths.

## Running Tests

### Run all tests

From the project root directory:

```bash
nvim -u NONE --headless -S run_tests.lua
```

The `-u NONE` flag ensures no user config is loaded, so tests run against
the local codebase rather than an installed version of zpack.nvim.

Or from within Neovim after `cd` to project root:

```vim
:source run_tests.lua
```

### Run specific test module

```vim
:lua package.path = vim.fn.getcwd() .. '/lua/?.lua;' .. package.path
:lua require('tests.setup_test')()
```

### Test Results

All tests use mocked `vim.pack.add` to avoid actual plugin installation attempts. This allows tests to run quickly and reliably without network access or real plugin repositories.

## Test Structure

- `helpers.lua` - Test helper functions and assertions
- `*_test.lua` - Individual test modules
- `run_all.lua` - Test runner that executes all tests

## Writing New Tests

Use the test helpers to write new tests:

```lua
local helpers = require('tests.helpers')

return function()
  helpers.describe("Your Test Suite", function()
    helpers.test("should do something", function()
      helpers.setup_test_env()

      -- Your test code here
      helpers.assert_equal(actual, expected, "message")

      helpers.cleanup_test_env()
    end)
  end)
end
```

### Available Assertions

- `assert_equal(actual, expected, msg)` - Check equality
- `assert_true(condition, msg)` - Check if true
- `assert_false(condition, msg)` - Check if false
- `assert_nil(value, msg)` - Check if nil
- `assert_not_nil(value, msg)` - Check if not nil
- `assert_table_contains(tbl, value, msg)` - Check if table contains value

### Test Environment

- `setup_test_env()` - Initialize test environment
- `cleanup_test_env()` - Clean up after test
- Always call these at the start and end of each test to ensure isolation

## Notes

- Tests use `vim.schedule()` for async operations
- Each test should clean up after itself to prevent state pollution
- Mock plugins are used (e.g., 'test/plugin') to avoid actual vim.pack operations
