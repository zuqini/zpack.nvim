# Changelog

## [3.0.0](https://github.com/zuqini/zpack.nvim/compare/v2.0.4...v3.0.0) (2026-11-06)


### ⚠ BREAKING CHANGES

* **merge:** a plugin's specs merge in import order, as in lazy.nvim, so a later spec under `dependencies` overrides a top-level one and its function `opts` sees the top-level opts
* **module_loader:** a `require` loads a lazy plugin only when the plugin holds the module's file, as in lazy.nvim; one with only the top-level name stays lazy
* **commands:** `:ZPack clean` and `:ZPack sync` list what they would delete and ask, defaulting to No; `!` skips the prompt
* **import:** a `nil` in a spec list no longer ends the list, so what follows it installs
* **lazy:** a plugin whose function-form trigger throws stays lazy instead of loading at startup
* **module_loader:** remove the unreachable profiler; `setup({ profiling = ... })` is ignored, and `print_profile` and `get_profile` are gone
* **module_loader:** `require` no longer loads a plugin whose name resembles a module it doesn't provide; a plugin registering a module from `plugin/` needs a trigger of its own
* **keys:** two strings in `keys` are two keys unless the second can only be an rhs, so `{ '<leader>d', 'dd' }` needs a field or nesting to stay one key
* **keys:** a later spec's key replaces an earlier one
* **import:** a bare name nothing defines is skipped rather than installed
* **merge:** a disabled dependency no longer disables the plugin listing it
* **merge:** the last spec to set `enabled` or `cond` wins, instead of any `false`
* **lazy:** an `event` with no real event in it, such as `LazyFile`, leaves the plugin eager with a warning
* **utils:** a `version` string git can't take as a ref, such as `*`, is a semver range
* **import:** spec modules import in module name order
* **version:** version fields follow lazy.nvim's priority: commit, tag, version, sem_version, branch, default

### Features

* close lazy.nvim parity gaps in spec lists, keys, triggers and bare names ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **import:** import specs from a plugin's own modules ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **merge:** support opts_extend ([#46](https://github.com/zuqini/zpack.nvim/issues/46)) ([b23ed1f](https://github.com/zuqini/zpack.nvim/commit/b23ed1fa137c78de06f2b7a528be4de4a51ca348)), closes [#45](https://github.com/zuqini/zpack.nvim/issues/45)


### Bug Fixes

* **cmd:** keep a numeric first argument on a lazy command's first use ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **commands:** `:ZPack clean` and `:ZPack sync` list what they would delete and ask, defaulting to No; `!` skips the prompt ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **commands:** `:ZPack clean` leaves a plugin active this session for next time rather than raising ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **ft:** a lazy `ft` plugin's `ftdetect/` is sourced once, as in lazy.nvim, so one that runs `set filetype=` fires `FileType` once per file ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **hooks:** a module brought in by an in-session update is found without a restart ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **hooks:** removing a plugin drops its command and key proxies, so its command gives E492 and a command it shared with another lazy plugin works for that plugin; an `init` removing a plugin no longer re-fires its event or crashes `setup()` when the plugin has its own `init` ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **import:** a `nil` in a spec list no longer ends the list, so what follows it installs ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **import:** a bare name nothing defines is skipped rather than installed ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **import:** a bare string in a spec list installs as a plugin, rather than being reported as invalid and skipped ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **import:** an `import` with no plugin of its own finds its module in a listed plugin named after it, installing it if missing, on the first start ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **import:** spec modules import in module name order ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **import:** take a plugin's `lua/` off `package.path` after startup ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **import:** warn when an import finds no specs ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **keys:** a key keeps its proxy while a plugin listing it is pending, as in lazy.nvim, so another plugin's `keys` on the same lhs don't stop it loading ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **keys:** a later spec's key replaces an earlier one ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **keys:** a plugin drops its key proxies as it loads, as in lazy.nvim, so a plugin that maps a key only when it's free (flash.nvim's `;` and `,`) gets it ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **keys:** two strings in `keys` are two keys unless the second can only be an rhs, so `{ '<leader>d', 'dd' }` needs a field or nesting to stay one key ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **lazy:** a plugin whose function-form trigger throws stays lazy instead of loading at startup ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **lazy:** an `event` with no real event in it, such as `LazyFile`, leaves the plugin eager with a warning ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **lazy:** no proxy over what a function-form trigger already loaded ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **lazy:** set up triggers in a session that installs a plugin ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **loader:** a function-form `opts` that throws is reported once and the plugin still loads without its `config`, as in lazy.nvim, instead of staying pending ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **loader:** a plugin already on 'runtimepath' that loads after a `config` turned detection on gets its `ftdetect/` once, not twice ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **loader:** a require or build after startup sources plugin/, and a failing dependency doesn't stop its parent ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **loader:** report a `plugin/` script's error without failing the load ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **loader:** source a plugin's dependencies before its plugin/, in the order they're listed ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **merge:** a disabled dependency no longer disables the plugin listing it ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **merge:** a plugin's specs merge in import order, as in lazy.nvim, so a later spec under `dependencies` overrides a top-level one and its function `opts` sees the top-level opts ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **merge:** a table listed at the top level and under a lazy parent's `dependencies` loads eagerly ([#49](https://github.com/zuqini/zpack.nvim/issues/49)) ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **merge:** clear opts keys set to vim.NIL ([#47](https://github.com/zuqini/zpack.nvim/issues/47)) ([3bd8cdf](https://github.com/zuqini/zpack.nvim/commit/3bd8cdf22f7582d2a336f774d00f0ceaf0e3f7c0))
* **merge:** drop a removed plugin's specs before deriving what stays ([#49](https://github.com/zuqini/zpack.nvim/issues/49)) ([871104e](https://github.com/zuqini/zpack.nvim/commit/871104e76ba75706b2e6ceadb4950f6b4481dc71))
* **merge:** plugins under an optional or disabled parent's `specs` are dropped ([#49](https://github.com/zuqini/zpack.nvim/issues/49)) ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **merge:** removals resting on other removals no longer depend on import order ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **merge:** the last spec to set `enabled` or `cond` wins, instead of any `false` ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **module_loader:** `require` no longer loads a plugin whose name resembles a module it doesn't provide; a plugin registering a module from `plugin/` needs a trigger of its own ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **module_loader:** a `require` loads a lazy plugin only when the plugin holds the module's file, as in lazy.nvim; one with only the top-level name stays lazy ([241c9ba](https://github.com/zuqini/zpack.nvim/commit/241c9ba9c3b12042a506be530e161fc9fb83f481))
* **module_loader:** a later `require` of a module whose load threw raises that error instead of returning `true` ([241c9ba](https://github.com/zuqini/zpack.nvim/commit/241c9ba9c3b12042a506be530e161fc9fb83f481))
* **module_loader:** a slash-form `require('lspconfig/util')` loads the pending plugin holding the module ([241c9ba](https://github.com/zuqini/zpack.nvim/commit/241c9ba9c3b12042a506be530e161fc9fb83f481))
* **module_loader:** load the plugin holding a module in a shared namespace, including a compiled one ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **module_loader:** when several pending plugins hold a module, the one named like it loads, as in lazy.nvim ([241c9ba](https://github.com/zuqini/zpack.nvim/commit/241c9ba9c3b12042a506be530e161fc9fb83f481))
* **pack:** a soft version installs from the default branch after another plugin's clone failed ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **pack:** read a tag as `vim.pack` does when deciding if one fits ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **pack:** restore a locked plugin at its revision when no tag fits its soft version ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **pack:** say when a plugin needs a restart to reach a tag or to update ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **runtime:** zpack escapes the path of each file it sources itself, so a `#` or `%` in the data path no longer fails with E194/E484 and loses the file ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **setup:** `setup()` with no `spec` and no `lua/plugins`, or one holding only dotfiles, is quiet, as in 2.x ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **setup:** `setup()`'s options no longer count as spec fields, so specs written beside them all install ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **setup:** a plugin vim.pack can't add no longer aborts setup() ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **setup:** a single spec with no array part, such as `{ import = ..., defaults = ... }`, is read as a spec rather than ignored for the default import ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **setup:** a string is the module to import, in `setup('custom.plugins')` and in `spec`, rather than reported and replaced by the default import ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **setup:** any other `setup()` argument that isn't a table is reported, and the default import goes on ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **setup:** source plugin/ when setup() runs after startup ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **startup:** `:colorscheme` loads the pending plugin holding the scheme first, as in lazy.nvim, so a Vim colors file can call its plugin's `autoload/` from an `init` or for a lazy plugin, and an eager scheme plugin set from an earlier plugin's `config` (themery.nvim's restore) gets its own `config` first ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **startup:** a `require` from an `init` loads the eager plugin holding the module, as in lazy.nvim, instead of failing with "module not found" ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **startup:** a lazy plugin's `cmd`, `event`, `ft` and `keys` are set up before the inits, as in lazy.nvim, so an `init` running one loads the plugin ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **startup:** an eager plugin's `ftdetect/` runs when filetype detection is on before `setup()`, as in lazy.nvim, so LazyVim's vimtex opens a `.cls` as `tex` ([bfd84e3](https://github.com/zuqini/zpack.nvim/commit/bfd84e346ec69018731317fbaf01d5037a9fccff))
* **startup:** run an eager plugin's `config` once when a lazy dependent loads it ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **utils:** a `version` or `tag` of the wrong type is dropped with a warning instead of failing every plugin ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **utils:** a `version` string git can't take as a ref, such as `*`, is a semver range ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **validate:** warn about a `sem_version` that isn't a semver range, and fall through to `branch` and `defaults.version` ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))
* **version:** a semver string no tag fits follows the default branch ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))
* **version:** version fields follow lazy.nvim's priority: commit, tag, version, sem_version, branch, default ([85ba638](https://github.com/zuqini/zpack.nvim/commit/85ba638530c25f53d0746e953f98340d98a0e71f))


### Performance Improvements

* speed up startup with many plugins ([#50](https://github.com/zuqini/zpack.nvim/issues/50)) ([2966b92](https://github.com/zuqini/zpack.nvim/commit/2966b92de2f18ac4a0df00f3df1047132a9bad7d))
* stop tracing zpack's startup code ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))


### Code Refactoring

* **module_loader:** remove the unreachable profiler; `setup({ profiling = ... })` is ignored, and `print_profile` and `get_profile` are gone ([936649e](https://github.com/zuqini/zpack.nvim/commit/936649e081cd8416498cb3cd38ff90f365012386))

## [2.0.4](https://github.com/zuqini/zpack.nvim/compare/v2.0.3...v2.0.4) (2026-09-25)


### Bug Fixes

* **utils:** allow non-GitHub URLs while still expanding the short form GitHub owner/repo paths ([#42](https://github.com/zuqini/zpack.nvim/issues/42)) ([a6fdbf5](https://github.com/zuqini/zpack.nvim/commit/a6fdbf521a577193beb57116c8b7ad217cf877b2))
* **utils:** only pass git URLs through [1]; flag local paths in validate ([#44](https://github.com/zuqini/zpack.nvim/issues/44)) ([451a0bb](https://github.com/zuqini/zpack.nvim/commit/451a0bbd0a4ae7f84aec780a27e3a89824976978)), closes [#42](https://github.com/zuqini/zpack.nvim/issues/42)

## [2.0.3](https://github.com/zuqini/zpack.nvim/compare/v2.0.2...v2.0.3) (2026-09-22)


### Bug Fixes

* **merge:** fold specs deriving the same plugin name, matching lazy.nvim ([#40](https://github.com/zuqini/zpack.nvim/issues/40)) ([892385a](https://github.com/zuqini/zpack.nvim/commit/892385ac2010bce457772cb628af04a560d927ca)), closes [#39](https://github.com/zuqini/zpack.nvim/issues/39)

## [2.0.2](https://github.com/zuqini/zpack.nvim/compare/v2.0.1...v2.0.2) (2026-08-20)


### Bug Fixes

* **import:** explicit src/url/dir overrides [1] shorthand, matching lazy.nvim ([#36](https://github.com/zuqini/zpack.nvim/issues/36)) ([7b40442](https://github.com/zuqini/zpack.nvim/commit/7b4044201f77ee527d2d80820318bb98eef56f61))

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
