# Changelog

## [2.0.1](https://github.com/zuqini/zpack.nvim/compare/v2.0.0...v2.0.1) (2026-08-02)


### Bug Fixes

* **import:** added support of importing spec-files directly, as it was in lazy.nvim ([#30](https://github.com/zuqini/zpack.nvim/issues/30)) ([0b61779](https://github.com/zuqini/zpack.nvim/commit/0b6177970cc02308af975daf2023c9fdd58a008f))

## [2.0.0](https://github.com/zuqini/zpack.nvim/compare/v1.2.1...v2.0.0) (2026-06-03)


### ⚠ BREAKING CHANGES

2.0.0 removes every previously deprecated `setup()` option, the `zpack.add()`
function, and the legacy `:Z*` commands. Update your config before upgrading:

| Removed in 2.0 | Replacement |
|---|---|
| `setup({ confirm = … })` | `setup({ defaults = { confirm = … } })` |
| `setup({ disable_vim_loader = true })` | `setup({ performance = { vim_loader = false } })` |
| `setup({ plugins_dir = 'dir' })` | a `{ import = 'dir' }` entry in your spec list |
| `setup({ cmd_prefix = 'Z' })` | `setup({ cmd_name = 'Z' })` |
| legacy `:ZUpdate` / `:ZClean` / `:ZDelete` / `:ZRestore` / `:ZLoad` / `:ZBuild` | `:ZPack update` / `clean` / `delete` / `restore` / `load` / `build` (or `:Z …` with `cmd_name = 'Z'`) |
| `setup({ auto_import = … })` | removed — was already a no-op in 1.x |
| `require('zpack').add(…)` | removed — was already a no-op in 1.x |

See [Upgrading from 1.x to 2.0](https://github.com/zuqini/zpack.nvim/blob/main/docs/tips.md#upgrading-from-1x-to-20) for the full migration guide.

### Features

* adopt Neovim plugin best practices ([#23](https://github.com/zuqini/zpack.nvim/issues/23)) ([2f45de6](https://github.com/zuqini/zpack.nvim/commit/2f45de670e4dcbc6a8ae7b11284764772f1cf3e3))
* close lazy.nvim parity gaps across lazy triggers ([#27](https://github.com/zuqini/zpack.nvim/issues/27)) ([9ed473a](https://github.com/zuqini/zpack.nvim/commit/9ed473adbf6af59b650ecd716b56bf0ccbf0d7f8))
* **lazy-parity:** add defaults.lazy and defaults.version ([#29](https://github.com/zuqini/zpack.nvim/issues/29)) ([d52f0dd](https://github.com/zuqini/zpack.nvim/commit/d52f0ddf85cf8fe74952f7825d3f9ea5f31b2968))
* lazy.nvim spec parity (pin/optional/dev/specs/build/reload/sync) ([#28](https://github.com/zuqini/zpack.nvim/issues/28)) ([b6f82cd](https://github.com/zuqini/zpack.nvim/commit/b6f82cdd9774357b0267f0b896b9d2e1c867743a))
* remove deprecated features for 2.0.0 ([#25](https://github.com/zuqini/zpack.nvim/issues/25)) ([4681a74](https://github.com/zuqini/zpack.nvim/commit/4681a74a1a7f265549a5dd98b7ce838bb1b85e92))
* support bang on :ZPack update/restore; document 0.13 native commands ([4f9b312](https://github.com/zuqini/zpack.nvim/commit/4f9b31274dbedf7ac08b9a138e1bf52bf4fe91b4))
* sync state with vim.pack via PackChanged on plugin removal ([0b65048](https://github.com/zuqini/zpack.nvim/commit/0b65048efd8891ec4e1aba4acc678b35af719b18))


### Bug Fixes

* address PR [#21](https://github.com/zuqini/zpack.nvim/issues/21)/[#22](https://github.com/zuqini/zpack.nvim/issues/22) review follow-ups ([c9c6c61](https://github.com/zuqini/zpack.nvim/commit/c9c6c612b9ffe7953e46ff4759d86274b9a9526d))
* command-specific legacy command deprecation notice ([8970a43](https://github.com/zuqini/zpack.nvim/commit/8970a43b3ab24c7c5d27020e2a23922e198ef5ca))
* correct bang placement in usage hints; always warn on legacy commands ([2f4bf35](https://github.com/zuqini/zpack.nvim/commit/2f4bf356e0faec7d3c99bca725df0d721446b971))
* guard non-number priority and non-string import field ([af3f109](https://github.com/zuqini/zpack.nvim/commit/af3f1097152a36493144be22f6e8fd7c32351c90))
* guard non-string src/url/dir in normalize_source ([b127f63](https://github.com/zuqini/zpack.nvim/commit/b127f63279a67f10dd5a3e0c5fc75b7a9cc6785a))
* harden lazy-load path against operator-pending loss + throw-leaks ([#26](https://github.com/zuqini/zpack.nvim/issues/26)) ([c6079d5](https://github.com/zuqini/zpack.nvim/commit/c6079d5b10301bf4c3f59863fd2a23d00271a0e2))
* preserve typeahead order on multi-key sequences ([6b99fcb](https://github.com/zuqini/zpack.nvim/commit/6b99fcb107c1436dfbb7e5cbb0c7072799973a11))


### Code Refactoring

* :ZPack with subcommands ([d197fc6](https://github.com/zuqini/zpack.nvim/commit/d197fc6281550f3872c10b1e3ae16b55d656b27b))
