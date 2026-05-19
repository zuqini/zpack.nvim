# zpack.nvim Test Suite

Comprehensive test suite for zpack.nvim covering all major flows and lazy-loading paths.

The suite runs under [busted](https://lunarmodules.github.io/busted/). Because
the tests exercise real Neovim APIs (`vim.api`, `vim.pack`, autocmds,
`vim.uv`, ...), busted runs *inside* Neovim via `nvim -l` rather than under a
standalone Lua interpreter.

## Running Tests

### One-time setup

busted and its dependencies are installed into a project-local LuaRocks tree
(`.luarocks/`, gitignored). Install it built against LuaJIT so its native
dependency (luafilesystem) is ABI-compatible with Neovim's bundled LuaJIT:

```bash
luarocks --lua-version=5.1 --lua-dir=<luajit-prefix> --tree .luarocks install busted 2.3.0
```

`<luajit-prefix>` is your LuaJIT install prefix — e.g. `$(brew --prefix luajit)`
on macOS.

### Run all tests

From the project root:

```bash
nvim -u NONE -l tests/busted.lua
```

The command exits 0 when the suite is green and non-zero when any test fails.

### Run a subset

busted's CLI flags are passed through. For example, run only tests whose name
matches a pattern, or shuffle run order to surface ordering dependencies:

```bash
nvim -u NONE -l tests/busted.lua --filter "lazy"
nvim -u NONE -l tests/busted.lua --shuffle
```

## Test Structure

- `tests/busted.lua` — bootstraps busted to run in-process under `nvim -l`.
- `tests/*_test.lua` — native busted spec files. Each registers its
  `describe`/`it` blocks at load time; busted discovers them directly via the
  `.busted` `pattern`.
- `tests/helpers.lua` — the mocked `vim.pack` test environment
  (`setup_test_env`/`cleanup_test_env`) plus shared utilities. It also
  registers the `assert.contains` luassert assertion.
- `tests/pack_update_test_helpers.lua` — parameterised cases shared by
  `zupdate_test.lua` and `zrestore_test.lua`. It is `require`'d, not discovered
  as a spec (its filename is intentionally not `*_test.lua`).
- `.busted` — busted configuration (test root and spec-file pattern).

All tests use a mocked `vim.pack` to avoid real plugin installation, so they
run quickly and without network access.

## Writing New Tests

Add a `tests/<name>_test.lua` spec file. busted discovers it automatically —
there is no registration step:

```lua
local helpers = require('helpers')

describe("Your Test Suite", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("should do something", function()
    -- Your test code here
    assert.are.equal(expected, actual)
  end)
end)
```

Pure unit tests that do not touch the mocked `vim.pack` environment can omit
the `before_each`/`after_each` pair.

### Available Assertions

Assertions come from busted's bundled [luassert](https://github.com/lunarmodules/luassert):

- `assert.are.equal(expected, actual)` — `==` (identity) equality
- `assert.are.same(expected, actual)` — deep/recursive equality
- `assert.is_truthy(value)` / `assert.is_falsy(value)` — truthiness
- `assert.is_true(value)` / `assert.is_false(value)` — strict boolean equality
- `assert.is_nil(value)` / `assert.is_not_nil(value)` — nil checks
- `assert.contains(tbl, value)` — list membership (registered by `helpers.lua`)

A failed assertion is reported by busted as a **failure**; an uncaught error
(nil index, `require` failure, ...) is reported as an **error**.

### Test Environment

- `before_each(helpers.setup_test_env)` installs the mocked `vim.pack`
  environment and the shared `_G.test_state` table before each test.
- `after_each(helpers.cleanup_test_env)` restores the real `vim.*` functions
  and resets zpack's module state after each test — on both the passing and
  failing path — so tests stay isolated.

## Notes

- Test isolation is handled by `before_each`/`after_each`; individual tests do
  not need to clean up the mock environment themselves.
- Mock plugins are used (e.g. `test/plugin`) to avoid actual `vim.pack` operations.
- CI runs the suite (`nvim -u NONE -l tests/busted.lua`) on every push and
  pull request; see `.github/workflows/tests.yml`. CI's LuaRocks is already
  bound to LuaJIT, so it installs busted with just
  `luarocks install --tree .luarocks busted 2.3.0` — no `--lua-version` /
  `--lua-dir` needed.
