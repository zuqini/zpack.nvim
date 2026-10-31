# Tips & Migration

- [Migrating from lazy.nvim](#migrating-from-lazynvim)
- [Gotchas](#gotchas)
- [Compatibility Notes](#compatibility-notes)
  - [Snacks.nvim dashboard with zpack.nvim](#snacksnvim-dashboard-with-zpacknvim)
  - [noice.nvim with vim.pack](#noicenvim-with-vimpack)
- [Lockfile location](#lockfile-location)
- [Native vim.pack commands](#native-vimpack-commands)
- [Upgrading from 1.x to 2.0](#upgrading-from-1x-to-20)

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with zpack. However, zpack follows `vim.pack` conventions over lazy.nvim conventions, and is missing a few advanced features:
- **version pinning**: lazy.nvim's `version` field maps to zpack's `sem_version`. `version` also reads a string that can't be a git ref (`*`, `1.*`, `^1.0`) as a range, but any other string, such as `1.x`, stays a ref. See [Spec Reference](spec.md) and [version pinning examples](examples.md#version-pinning-for-lazynvim-compatibility)
- **dev mode**: Set `dev = true` on a spec and configure `setup({ dev = { path = '~/projects' } })` — the source is rewritten to `<path>/<plugin-name>`. Live file-watch / auto-reload is out of scope; use `:ZPack reload {plugin}` to manually re-source. See [Spec Reference](spec.md) for `dev`/`deactivate`
- **profiling**: Use `nvim --startuptime startuptime.log`. Also refer to example [Neovim Profiler script](https://gist.github.com/zuqini/35993710f81983fbfa6baca67bdb32ed)
- **default lazy plugins**: lazy.nvim's community specs silently default top-level specs for utility libraries like `plenary.nvim` to `lazy = true`, even without lazy triggers or a lazy parent. zpack respects your specs as-written, so set `lazy = true` explicitly on such specs if you want the same default — or set `defaults.lazy = true` in [`setup()`](../README.md#configurations) to apply it to every spec
- **`enabled` vs `cond`**: lazy.nvim collapses both to a single "disabled" state. zpack splits them: `enabled = false` skips install entirely (the plugin is never cloned), while `cond = false` installs the plugin but skips its load (so it still shows up under `vim.pack`'s data dir). Use `enabled` when you want lazy.nvim's "don't install at all" behavior
- **empty triggers**: a trigger that resolves to nothing usable (`event = {}`, `cmd = { 123 }`, or a function that adds nothing) leaves the plugin eager, so it can't go unloaded with no way to load it; lazy.nvim makes it lazy. So does an `event` with no real event in it, with a warning
- **a key that can't load the plugin**: a plugin whose only keys are `{ lhs, false }` or `{ lhs, '<Nop>' }` stays lazy, as in lazy.nvim, and loads when something requires it. Set `lazy = false` if nothing does
- **`LazyFile`**: this is a LazyVim event, not a lazy.nvim one, and zpack doesn't define it. Use `event = { 'BufReadPost', 'BufNewFile', 'BufWritePre' }`
- **a list with fields**: `{ 'a/b', 'c/d', opts = {} }` is one spec for `a/b` and warns about the rest; lazy.nvim reads it as a list and ignores `opts`
- **`keys` given as `{ lhs, rhs, desc = ... }`**: zpack also takes one KeySpec without the extra nesting when it has anything besides strings; lazy.nvim always reads the outer table as a list. So does `{ lhs, rhs }` when the rhs can only be one (it is empty or `<Nop>`, starts with `<cmd>`, `<Plug>` or `:`, or has text before a final `<CR>`). Any other two strings are two keys in both, so `{ '<leader>d', 'dd' }` needs a field or nesting to be one key
- **merge order across specs**: specs under `dependencies` merge before top-level ones whatever the import order, so a later spec under `dependencies` can't override a top-level field, replace or disable its key, or clear its trigger with `false`; lazy.nvim goes by import order
- **a spec table listed in several places**: zpack keeps it while any plugin listing it stays, and treats it as a dependency only if every remaining listing is under `dependencies`; lazy.nvim records only its first listing
- **`opts_extend`**: in lazy.nvim each spec uses the nearest `opts_extend` at or before it, and a spec with none in effect replaces the lists before it, so of the lists set before the first `opts_extend` only the last is kept, and a later `opts_extend` that leaves a key out stops that key from appending. lazy.nvim also keeps only the list entries of a table at an `opts_extend` key, dropping its named keys. zpack combines `opts_extend` from all specs of a plugin, so it can be set on any of them, and appends a table with named keys (such as which-key's `{ mode = 'v', ... }`) as one entry. zpack appends `dependencies` specs' lists before top-level ones, while lazy.nvim appends in import order, so with plain lists the two match when only the plugin's first spec sets `opts_extend` (LazyVim does this) and no `dependencies` entry adds to the list

## Gotchas

Known gotchas when using zpack:
- **install/update feedback**: `vim.pack` surfaces install/update progress via `:messages` (e.g. `vim.pack: Downloading updates (0/83)`). These messages are hidden if you have `vim.opt.cmdheight = 0` — raise it, check `:messages`, or route them through a notifier like [snacks.notifier](https://github.com/folke/snacks.nvim), [nvim-notify](https://github.com/rcarriga/nvim-notify), or [noice.nvim](https://github.com/folke/noice.nvim). Also see [noice.nvim with vim.pack](#noicenvim-with-vimpack) for compatibility notes
- **names without an owner**: `{ 'mason.nvim', opts = ... }` only refers to the plugin of that name, as in lazy.nvim. Another spec has to give its source; otherwise it is skipped with a warning
- **same plugin, two owners**: specs deriving the same name (e.g. `williamboman/mason.nvim` in a `dependencies` list and `mason-org/mason.nvim` at top level) are folded into one plugin; a `dev = true` fragment wins, then an explicit `src`/`url`/`dir`, then a top-level spec over a dependency, and zpack warns unless the specs name a repo in common (a shared `[1]`, or a `src`/`url` equal to the other's `[1]`). Fields merge as usual, so the last `enabled` decides whether the plugin is disabled. Point both at the current owner, or set `name` on one to keep them apart
- **`vim.NIL` in opts**: as in lazy.nvim, a key set to `vim.NIL` is removed rather than passed to `setup()` wherever specs merge, which includes every top-level key of table opts. A table that replaces the earlier value (nothing, a scalar or a list was there) keeps its `vim.NIL`, and so do opts a function returns or edits. To hand a plugin a JSON `null` (e.g. in LSP settings), nest it in a table no earlier spec sets, or set it from function-form opts

## Compatibility Notes

#### Snacks.nvim dashboard with zpack.nvim

The default [Snacks.nvim](https://github.com/folke/snacks.nvim) dashboard configuration includes a startup time section that has a hard dependency on lazy.nvim. This will cause errors with any other plugin manager, not just zpack.

To work around this, remove the startup section from your dashboard configuration:

```lua
require('snacks').setup({
  dashboard = {
    sections = {
      { section = "header" },
      { section = "keys", gap = 1, padding = 1 },
      -- { section = "startup" }, -- Remove this line (depends on lazy.nvim)
    },
  }
})
```

See [snacks.nvim#1778](https://github.com/folke/snacks.nvim/issues/1778) for more details.

#### noice.nvim with vim.pack

[noice.nvim](https://github.com/folke/noice.nvim) filters out `vim.pack` messages by default, which means you won't see install/update notifications from your plugin manager.

To fix this, add a route that explicitly shows `vim.pack` messages:

```lua
require('noice').setup({
  routes = {
    {
      filter = {
        event = "msg_show",
        find = "vim.pack",
      },
    },
  },
})
```

## Lockfile location

`vim.pack` writes its lockfile to `$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json` — i.e. next to your `init.lua`. On Neovim 0.13+ the path is configurable through the `'packlockfile'` option (see `:h 'packlockfile'`), so you can keep it out of your config repo:

```lua
vim.o.packlockfile = vim.fs.joinpath(vim.fn.stdpath('data'), 'nvim-pack-lock.json')
```

Two caveats:
- `'packlockfile'` must be set **before the first `vim.pack` call**, which in practice means before the `vim.pack.add()` that installs zpack itself — put it at the very top of your `init.lua`.
- Changing the path does not move the existing file. Move (or delete and regenerate with `:ZPack update`) the old lockfile, otherwise `vim.pack` starts from an empty one.

zpack needs no configuration for this — it delegates to `vim.pack` for lockfile reads and writes, so `:ZPack update` and `:ZPack restore` follow whatever `'packlockfile'` points at.

## Native vim.pack commands

On Neovim 0.13+, the `:ZPack update`, `restore`, and `delete` subcommands have native `vim.pack` command equivalents (`:packupdate`, `:packupdate ++lockfile`, `:packdel`). Use whichever you prefer — zpack keeps its session state in sync either way. See `:h zpack-native-commands` for the full mapping.

## Upgrading from 1.x to 2.0

2.0.0 removes every option and command that was deprecated during the 1.x series. The renamed options (`confirm`, `disable_vim_loader`, `plugins_dir`) emitted runtime warnings throughout 1.x; the legacy `:Z*` commands are removed in favor of the `:ZPack <subcommand>` dispatcher. Removed options are now ignored silently, so update your `setup()` call before upgrading:

| Removed in 2.0 | Replacement |
|---|---|
| `setup({ confirm = … })` | `setup({ defaults = { confirm = … } })` |
| `setup({ disable_vim_loader = true })` | `setup({ performance = { vim_loader = false } })` |
| `setup({ plugins_dir = 'dir' })` | a `{ import = 'dir' }` entry in your spec list |
| `setup({ cmd_prefix = 'Z' })` | `setup({ cmd_name = 'Z' })` |
| `setup({ auto_import = … })` | removed — was already a no-op in 1.x |
| `require('zpack').add(…)` | removed — was already a no-op in 1.x |

### Commands

The per-action `:Z*` commands are now subcommands of a single `:ZPack` command:

| 1.x | 2.0 |
|---|---|
| `:ZUpdate` | `:ZPack update` |
| `:ZRestore` | `:ZPack restore` |
| `:ZClean` | `:ZPack clean` |
| `:ZBuild` | `:ZPack build` |
| `:ZLoad` | `:ZPack load` |
| `:ZDelete` | `:ZPack delete` |

The command name is configurable via `cmd_name` (default `ZPack`). If you relied on the old `cmd_prefix = 'Z'`, set `cmd_name = 'Z'` to type `:Z update`, `:Z clean`, etc. The `!` bang is still supported where it was before (e.g. `:ZPack! build`, `:ZPack! delete`).
