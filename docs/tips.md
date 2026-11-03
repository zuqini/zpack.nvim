# Tips & Migration

- [Migrating from lazy.nvim](#migrating-from-lazynvim)
- [Gotchas](#gotchas)
- [Compatibility Notes](#compatibility-notes)
  - [Snacks.nvim dashboard with zpack.nvim](#snacksnvim-dashboard-with-zpacknvim)
  - [noice.nvim with vim.pack](#noicenvim-with-vimpack)
- [Lockfile location](#lockfile-location)
- [Native vim.pack commands](#native-vimpack-commands)
- [Upgrading to 3.0](#upgrading-to-30)
- [Upgrading from 1.x to 2.0](#upgrading-from-1x-to-20)

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with zpack. However, zpack follows `vim.pack` conventions over lazy.nvim conventions, and is missing a few advanced features:
- **version pinning**: lazy.nvim's `version` field maps to zpack's `sem_version`. `version` also reads a string that can't be a git ref (`*`, `1.*`, `^1.0`) as a range, but any other string, such as `1.x`, stays a ref. As in lazy.nvim, a range written as a string follows the default branch if no tag fits. A plugin's version is fixed for the session, so if upstream later adds one, `:ZPack update` still moves the plugin to the branch's tip and says so; a restart and another update move it to the tag. A `vim.version.range()` object is an error from `vim.pack` if no tag fits. See [Spec Reference](spec.md) and [version pinning examples](examples.md#version-pinning-for-lazynvim-compatibility)
- **dev mode**: Set `dev = true` on a spec and configure `setup({ dev = { path = '~/projects' } })` — the source is rewritten to `<path>/<plugin-name>`. Live file-watch / auto-reload is out of scope; use `:ZPack reload {plugin}` to manually re-source. See [Spec Reference](spec.md) for `dev`/`deactivate`
- **profiling**: Use `nvim --startuptime startuptime.log`. Also refer to example [Neovim Profiler script](https://gist.github.com/zuqini/35993710f81983fbfa6baca67bdb32ed)
- **default lazy plugins**: lazy.nvim's community specs silently default top-level specs for utility libraries like `plenary.nvim` to `lazy = true`, even without lazy triggers or a lazy parent. zpack respects your specs as-written, so set `lazy = true` explicitly on such specs if you want the same default — or set `defaults.lazy = true` in [`setup()`](../README.md#configurations) to apply it to every spec
- **`enabled` vs `cond`**: lazy.nvim collapses both to a single "disabled" state. zpack splits them: `enabled = false` skips install entirely (the plugin is never cloned), while `cond = false` installs the plugin but skips its load (so it still shows up under `vim.pack`'s data dir). Use `enabled` when you want lazy.nvim's "don't install at all" behavior. On a spec with an `import`, a false `cond` works like `enabled` for what the import declares: see [`cond` on an `import` acts like `enabled`](#cond-on-an-import-acts-like-enabled)
- **empty triggers**: a trigger that resolves to nothing usable (`event = {}`, `cmd = { 123 }`, or a function that adds nothing) leaves the plugin eager, so it can't go unloaded with no way to load it; lazy.nvim makes it lazy. An `event` with no real event in it is eager too, with a warning. A function that throws counts as set, so a plugin stays lazy when its function requires the plugin's own module, which then loads it, and otherwise shows the error
- **a key that can't load the plugin**: a plugin whose only keys are `{ lhs, false }` or `{ lhs, '<Nop>' }` stays lazy, as in lazy.nvim, and loads when something requires it. Set `lazy = false` if nothing does
- **`LazyFile`**: this is a LazyVim event, not a lazy.nvim one, and zpack doesn't define it. Use `event = { 'BufReadPost', 'BufNewFile', 'BufWritePre' }`
- **a `nil` in a list**: zpack walks past it, so `{ { 'a/b' }, vim.g.flag and { 'c/d' } or nil, { 'e/f' } }` keeps `e/f` without a warning, as LazyVim's AI extras expect; lazy.nvim's `ipairs` stops at the first `nil` and silently drops the rest
- **a list with fields**: `{ 'a/b', 'c/d', opts = {} }` is one spec for `a/b` and warns about the rest (`{ nil, 'a/b', opts = {} }` is one spec with no source, and warns the same way), and `:ZPack clean` lists an installed `c/d` as unused until it's split; lazy.nvim reads it as a list and ignores `opts`
- **`keys` given as `{ lhs, rhs, desc = ... }`**: zpack also takes one KeySpec without the extra nesting when it has anything besides strings; lazy.nvim always reads the outer table as a list. So does `{ lhs, rhs }` when the rhs can only be one (it is empty or `<Nop>`, starts with `<cmd>`, `<Plug>` or `:`, or has text before a final `<CR>`). Any other two strings are two keys in both, so `{ '<leader>d', 'dd' }` needs a field or nesting to be one key
- **merge order across specs**: specs under `dependencies` merge before top-level ones whatever the import order, so a later spec under `dependencies` can't override a top-level field, replace or disable its key, or clear its trigger with `false`; lazy.nvim goes by import order
- **shadowed runtime files**: when `setup()` runs from `init.lua` and two eager plugins ship the same runtime file, such as `colors/x.lua`, the higher `priority` plugin wins, being first on 'runtimepath'; in lazy.nvim the lower `priority` one wins, since it loads later and goes ahead of the other
- **a spec table listed in several places**: zpack keeps it while any plugin listing it stays, and treats it as a dependency only if every remaining listing is under `dependencies`; lazy.nvim records only its first listing
- **an `import` with no plugin of its own**: `{ { 'u/dist' }, { import = 'dist.one' } }` looks for the module in your listed plugins named after its top level, by name or repository, when your config, 'runtimepath' and the plugins other `import` specs add don't have it, installing what's missing, on the first start and every later one. lazy.nvim tries those first and then every other plugin; zpack doesn't try the rest and warns, so for a module named otherwise put the `import` on its plugin's spec. zpack also finds a plugin listed after the `import`, where lazy.nvim reports no specs found, and it doesn't read a plugin that ends up disabled or dropped, where lazy.nvim reads one already on disk. A spec with a source and an `import`, `{ 'u/own', import = 'dist.one' }`, looks only in `u/own`
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

zpack needs no configuration for this: `:ZPack update`, `:ZPack restore` and installing a plugin at its locked revision all follow whatever `'packlockfile'` points at.

## Native vim.pack commands

On Neovim 0.13+, the `:ZPack update`, `restore`, and `delete` subcommands have native `vim.pack` command equivalents (`:packupdate`, `:packupdate ++lockfile`, `:packdel`). zpack keeps its session state in sync either way, but the native commands don't know about specs, so `:packupdate` moves a `pin = true` plugin that `:ZPack update` leaves alone. See `:h zpack-native-commands` for the full mapping.

## Upgrading to 3.0

These changes can affect a working config, nearly all of them without any error. The release notes list the rest.

### `keys = { lhs, rhs }` is two keys

`keys = { '<leader>a', 'dd' }` used to map `<leader>a` to `dd`. As in lazy.nvim, it's now a list of two keys that only load the plugin, and nothing warns: `<leader>a` has no rhs, so it does nothing once the plugin is loaded, and a proxy sits over native `dd` until then.

Nest the key, which lazy.nvim reads the same way, or give it a field:

```lua
-- 2.x
keys = { '<leader>a', 'dd' }
-- 3.0
keys = { { '<leader>a', 'dd' } }
keys = { '<leader>a', 'dd', desc = 'Delete line' }
```

A second string that can only be an rhs is still one key: empty, `<Nop>`, `<cmd>...`, `<Plug>...`, `:...`, or text ending in `<CR>`.

### The last spec setting `enabled` decides

`{ 'u/x', enabled = false }` beside `{ 'u/x', enabled = true }` used to leave the plugin out, whichever came first. Now the last one in merge order decides, so this installs it. Set `enabled = false` in the last spec, or drop the `enabled = true`.

### The last spec setting `cond` decides

`{ 'u/x', cond = false }` beside `{ 'u/x', cond = true }` used to keep the plugin from loading, whichever came first. Now the last one in merge order decides, so this loads it, and of several functions only that spec's runs.

### A later key replaces an earlier one

Two specs of a plugin mapping the same lhs in the same mode, `ft` and buffer used to get the first one's rhs. Now they get the last one's, as in lazy.nvim. A spec under `dependencies` still merges before a top-level one.

### Version fields follow lazy.nvim's order

If several are set, the order was `version`, `sem_version`, `branch`, `tag`, `commit`. It's now `commit`, `tag`, `version`, `sem_version`, `branch`, and `version = false` no longer overrides `commit`, `tag` or `branch`. So a plugin can end up on a different revision. Nothing moves at startup, since `vim.pack` leaves an installed plugin alone: this applies to an install with no lockfile entry, and to an installed plugin at `:ZPack update`.

```lua
-- 2.x: tip of main. 3.0: c1, so an update moves it back
{ 'u/x', version = 'main', commit = c1 }
-- 2.x: default branch. 3.0: tip of dev
{ 'u/x', version = false, branch = 'dev' }
-- 2.x: default branch. 3.0: an install raises in vim.pack and the plugin isn't added; an update leaves it where it is
{ 'u/x', version = false, branch = 'no-such-branch' }
```

### A spec with both a source and an `import` is a plugin too

`{ 'u/dist', import = 'dist.plugins' }` used to be only an import. Now `u/dist` is also registered, so it's installed, loaded and kept by `:ZPack clean`. Add `lazy = true` if it should only supply specs.

### Dependencies follow a lazy plugin down

`{ 'u/p', cmd = 'P', dependencies = { { 'u/d', dependencies = { 'u/c' } } } }` used to load `u/c` at startup, with `u/p` and `u/d` waiting for `:P`. Now `u/c` waits too. Set `lazy = false` on it to keep it eager.

### A lazy plugin's `plugin/` runs after its dependencies'

A lazy plugin's `plugin/` scripts used to run before its dependencies were loaded. Now they run after, as in lazy.nvim, so `plugin/` can use a dependency, and a dependency's `plugin/` can't count on its parent's having run.

### An `optional` dependency stays out

`{ 'u/p', dependencies = { { 'u/d', optional = true } } }` used to install `u/d`. As in lazy.nvim, it's now left out unless another spec asks for it without `optional`, and `:ZPack clean` deletes an installed copy.

### A dependency that fails no longer stops a lazy parent

A dependency whose function-form `opts` throws used to stop a lazy plugin listing it from loading. Now the error is reported and the plugin loads without it, as in lazy.nvim. An eager parent already loaded.

### A disabled dependency no longer removes the plugin listing it

`{ 'u/p', dependencies = { { 'u/d', enabled = false } } }` used to remove `u/p` too, with a warning. Now `u/p` stays, without `u/d` and without a warning. To remove both, disable the parent:

```lua
{ 'u/p', enabled = false, dependencies = { 'u/d' } }
```

### A disabled or `optional` plugin's `dependencies` and `specs` no longer count

`opts` in a `dependencies` spec of a plugin that is disabled, or left out as `optional`, used to reach that dependency when another spec kept it. Now that spec goes with the plugin listing it. LazyVim's lang extras have this shape but lose nothing: an `optional` nvim-lint or nvim-dap carrying `{ 'mason-org/mason.nvim', opts = { ensure_installed = ... } }` never added to mason's list in 2.x, which ignored `opts_extend`, so LazyVim's own mason spec replaced the list. 3.0 adds it when another spec lists that plugin without `optional`. Move what should stay to a spec that stays:

```lua
-- 2.x: u/d gets { a = 1, b = 2 }. 3.0: only { b = 2 }
{ 'u/p', enabled = false, dependencies = { { 'u/d', opts = { a = 1 } } } },
{ 'u/d', opts = { b = 2 } },
-- 3.0
{ 'u/p', enabled = false, dependencies = { 'u/d' } },
{ 'u/d', opts = { a = 1, b = 2 } },
```

A plugin declared under `specs` goes the same way, whether its parent is disabled or left out as `optional`. `{ 'u/p', enabled = false, specs = { { 'u/s' } } }` used to install `u/s`. Now it doesn't, and `:ZPack clean` deletes an installed copy. List `u/s` at the top level to keep it.

### `cond` on an `import` acts like `enabled`

`cond` on a spec with an `import` used to be ignored. Now a false `cond` means the module isn't read and its plugins aren't registered, so they aren't installed and **`:ZPack clean` and `:ZPack sync` delete the ones that are**.

A function-form `cond` gets no plugin argument at an `import`, as in lazy.nvim, so `cond = function(p) return p.name end` throws there, which reports the error and skips the import. On `{ 'user/repo', import = '...' }` it also runs for the plugin, with the plugin.

To keep the plugins installed but unloaded, set `cond` on the plugins themselves or use `defaults.cond`, which doesn't apply to the `import`:

```lua
-- 2.x, and deletes the plugins on :ZPack clean in 3.0
{ import = 'plugins.work', cond = is_work_machine }
-- lua/plugins/work.lua, for 3.0
return { { 'user/repo', cond = is_work_machine } }
```

### Eager plugins swap order on 'runtimepath'

When `setup()` runs from `init.lua`, eager plugins now reach 'runtimepath' with the highest `priority` first and a plugin's dependencies ahead of it. In 2.x the order was the reverse. Two things follow:

- `plugin/` scripts run in that order: a higher `priority` runs first, and a dependency runs before the plugin listing it.
- When two plugins ship the same runtime file, such as `colors/x.lua`, the first on 'runtimepath' wins. That used to be the lower `priority` plugin and is now the higher one.

`config` order hasn't changed. Swapping the two plugins' `priority` brings back the old `plugin/` order and the old winner of a shadowed file, but it also swaps their `config` order. For a plugin and its dependency, swapping changes nothing, since the dependency comes first either way.

### `setup()` at `VimEnter` sources `plugin/`

When `setup()` runs once startup has passed `plugin/`, such as at `VimEnter`, eager plugins' `plugin/` and `after/plugin/` scripts now run. They used to be skipped.

### `vim.NIL` in `opts` removes the key

A key set to `vim.NIL` is now removed at the top level of `opts`, even with only one spec, and in a table merged into one an earlier spec set at the same place. It used to reach the plugin as `vim.NIL`.

To hand a plugin a JSON `null`, as some LSP settings need, set it from function-form `opts`, or nest it in a table no earlier spec sets:

```lua
opts = function(_, opts)
  opts.setting = vim.NIL
  return opts
end
```

### Plugins sharing a filetype see less in `config`

Plugins sharing an `ft` load together in `priority` order and re-trigger `BufReadPre`, `BufReadPost` and `FileType` once, after the last of them. So a plugin's `config` no longer sees the `ftplugin` or `BufRead` handler effects of an earlier plugin in the group, such as a `vim.b` variable, even with `dependencies` declared. lazy.nvim behaves the same way.

Read such values from a `FileType` handler or the plugin's own `ftplugin` instead of from `config`.

The buffer usually ends up in the same state, with two exceptions:

- If several plugins ship an `ftplugin` guarded by `b:did_ftplugin` that don't set `b:undo_ftplugin`, the lowest `priority` plugin's now runs instead of the highest's.
- If a plugin's `config` loads another buffer of that filetype, `FileType` handlers of plugins still pending in the group miss that buffer. Declaring the pending plugin as a dependency avoids this.

### `packpath` isn't consulted for eager plugins

When `setup()` runs from `init.lua`, an eager plugin normally goes on 'runtimepath' from the directory `vim.pack` installed it in, not through `:packadd!`. A copy with the same name elsewhere on 'packpath' no longer joins 'runtimepath', and a 'packpath' that doesn't include `vim.pack`'s directory no longer stops the plugin loading. Lazy plugins still use `:packadd`.

To use a second copy on purpose, add it yourself with `vim.opt.runtimepath:prepend(path)`. Otherwise remove the leftover copy.

### `:ZPack clean` and `:ZPack sync` ask before deleting

`:ZPack clean`, and `:ZPack sync` after its update, list what they would delete and ask, defaulting to No. A headless run deletes nothing unless you add `!`, as in `:ZPack! clean`, which is for scripts. `defaults.confirm = false` doesn't skip this: it only means don't ask before installing.

A plugin zpack can't see looks unused, so read the list if startup reported an error: a spec module that throws or doesn't return a table, an `import` that finds no module, a module of fields with no plugin source, entries after `[1]` in a spec with fields, as in `{ 'a/b', 'c/d', opts = {} }`, or a failed `vim.pack.add`: a typo in a `url` lists the plugin you meant, and a call that fails as a whole, such as for a `src` of the wrong form, lists every plugin. Only a module that throws or doesn't return a table was reported in 2.x. `setup()` with no spec is the one import that may find nothing: no `lua/plugins/`, or one that is empty or holds only dotfiles such as `.gitkeep`, is nothing to report.

`:ZPack sync` still updates when a spec can't be read. A plugin with `pin = true` in that spec moves, because `pin` exists only in zpack's specs. Its `version` or `tag` holds, since `vim.pack` takes an inactive plugin's version from the lockfile. `:ZPack restore` doesn't undo the move unless the lockfile is in git, because the update rewrites the revision in the lockfile.

An `import` whose gitignored module isn't on this machine warns at every start. To stop that, say so with `enabled`:

```lua
{
  import = 'plugins.machine_local',
  enabled = function()
    return vim.uv.fs_stat(vim.fn.stdpath('config') .. '/lua/plugins/machine_local.lua') ~= nil
  end,
}
```

A helper in an imported directory, such as `lua/plugins/util.lua` returning `{ on_attach = fn }`: it reads as a spec with no source. Move it out of the directory.

### Smaller changes

- An `import` of a plugin's module, with the plugin listed apart as in `{ { 'u/dist' }, { import = 'dist.plugins.extra' } }`, used to import nothing. Now zpack finds the module in a listed plugin named after it, here `u/dist`, so what it declares is installed and loaded. If you had such a line doing nothing, remove it to keep it that way.
- `event = {}` or `cmd = {}` used to leave a plugin lazy, with no trigger to load it. Now it's eager. `lazy = true` keeps it lazy.
- Plain tables in `opts` are copied when handed to `config` and `setup()`, so `opts.x` isn't the table you wrote. A table with a metatable other than `vim.empty_dict()`'s is still passed by reference.
- `lua/plugins/*.lua` import by sorted module name, where it used to be file system order, and later specs win: `foo` comes before `foo-extra`, so `foo-extra`'s `opts` now override `foo`'s.
- A table listed both at the top level and under a lazy plugin's `dependencies` used to stay lazy. Now it's a plugin of its own and loads at startup, in `local d = { 'u/d' }` with `{ d, { 'u/p', cmd = 'P', dependencies = { d } } }`. `lazy = true` on the table keeps it lazy.
- A `nil` in a spec list used to end the list. `{ { 'u/x' }, flag and { 'u/y' } or nil, { 'u/d' } }` now installs `u/d` when `flag` is false.
- A function-form `event`, `cmd`, `ft` or `keys` that throws used to leave the plugin loading at startup. The error is still reported, but the plugin now stays lazy, and only its other triggers or a `require` of its modules load it.
- `opts_extend` used to be ignored. Now it applies, so lists that used to replace each other are joined: `{ 'u/x', opts_extend = { 'l' }, opts = { l = { 'a' } } }` beside `{ 'u/x', opts = { l = { 'b' } } }` gave `{ 'b' }` and now gives `{ 'a', 'b' }`.
- A bare string in a spec list used to be reported as an invalid spec and skipped. `{ 'u/a', { 'u/b' } }` now installs both. A string without an owner, as in a module returning `{ 'lua_ls', 'rust_analyzer' }`, is still skipped with a warning.
- A `require` used to load a lazy plugin whose name or `main` looked like the module's name, or whose `lua/` had only the module's top-level name. So an optional `pcall(require, 'mini.icons')` at startup loaded and configured a lazy `mini.pairs`, and `pcall(require, 'nvim-treesitter.configs')` loaded nvim-treesitter's main branch, which has no such module. As in lazy.nvim, a `require` now loads only the plugin holding the module's file under `lua/`, and fails as usual when none does. A plugin that makes a module at load time, from `plugin/` or `package.preload`, needs a trigger of its own.
- `setup({ profiling = ... })` is ignored without a word, and `print_profile` and `get_profile` are gone from `zpack.module_loader`.

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
