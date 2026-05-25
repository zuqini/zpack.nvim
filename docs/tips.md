# Tips & Migration

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with zpack. However, zpack follows `vim.pack` conventions over lazy.nvim conventions, and is missing a few advanced features:
- **version pinning**: lazy.nvim's `version` field maps to zpack's `sem_version`. See [Spec Reference](spec.md) and [version pinning examples](examples.md#version-pinning-for-lazynvim-compatibility)
- **dev mode**: Set `dev = true` on a spec and configure `setup({ dev = { path = '~/projects' } })` — the source is rewritten to `<path>/<plugin-name>`. Live file-watch / auto-reload is out of scope; use `:ZPack reload {plugin}` to manually re-source. See [Spec Reference](spec.md) for `dev`/`deactivate`
- **profiling**: Use `nvim --startuptime startuptime.log`. Also refer to example [Neovim Profiler script](https://gist.github.com/zuqini/35993710f81983fbfa6baca67bdb32ed)
- **default lazy plugins**: lazy.nvim's community specs silently default top-level specs for utility libraries like `plenary.nvim` to `lazy = true`, even without lazy triggers or a lazy parent. zpack respects your specs as-written, so set `lazy = true` explicitly on such specs if you want the same default

## Gotchas

Known gotchas when using zpack:
- **install/update feedback**: `vim.pack` surfaces install/update progress via `:messages` (e.g. `vim.pack: Downloading updates (0/83)`). These messages are hidden if you have `vim.opt.cmdheight = 0` — raise it, check `:messages`, or route them through a notifier like [snacks.notifier](https://github.com/folke/snacks.nvim), [nvim-notify](https://github.com/rcarriga/nvim-notify), or [noice.nvim](https://github.com/folke/noice.nvim). Also see [noice.nvim with vim.pack](#noicenvim-with-vimpack) for compatibility notes

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

## Native vim.pack commands

On Neovim 0.13+, the `:ZPack update`, `restore`, and `delete` subcommands have native `vim.pack` command equivalents (`:packupdate`, `:packupdate ++lockfile`, `:packdel`). Use whichever you prefer — zpack keeps its session state in sync either way. See the [command reference](../README.md#commands) for the full mapping.
