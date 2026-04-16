<h1 align="center">
  <img height="80px" src="https://github.com/user-attachments/assets/079c0646-7043-4397-b826-e4e893b2cf60" alt="zpack.nvim">
</h1>
<div align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/zuqini/zpack.nvim/tests.yml?style=for-the-badge&logo=githubactions&logoColor=white&label=tests&labelColor=1e1b4b"> <img src="https://img.shields.io/github/issues/zuqini/zpack.nvim?style=for-the-badge&logo=github&logoColor=white&color=8b5cf6&labelColor=1e1b4b"> <img src="https://img.shields.io/github/issues-pr/zuqini/zpack.nvim?style=for-the-badge&logo=github&logoColor=white&color=8b5cf6&labelColor=1e1b4b">

  <img src="https://img.shields.io/github/last-commit/zuqini/zpack.nvim?style=for-the-badge&logo=neovim&color=8b5cf6&labelColor=1e1b4b"> <img src="https://img.shields.io/github/license/zuqini/zpack.nvim?style=for-the-badge&logo=opensourceinitiative&logoColor=white&color=8b5cf6&labelColor=1e1b4b">
</div>

A thin layer on top of Neovim's native `vim.pack`, adding support for lazy-loading and the widely adopted lazy.nvim-like declarative spec.

**[Why zpack?](#why-zpack)** | **[Spec Examples](docs/examples.md)** | **[Spec Reference](docs/spec.md)** | **[Tips & Migration](docs/tips.md)**

## Requirements

- Neovim 0.12.0+

## Installation

```lua
-- install with vim.pack directly
vim.pack.add({ 'https://github.com/zuqini/zpack.nvim' })
```

## Usage

```lua
-- Make sure to setup `mapleader` and `maplocalleader` before loading
-- zpack.nvim so that keymaps referenced from zpack.Spec are aware
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- automatically import specs from `./lua/plugins/`
require('zpack').setup()
```

#### Directory Structure

Under the default setting, create plugin specs in `lua/plugins/`:

```
lua/
  plugins/
    treesitter.lua
    lsp.lua
    ...
```

Each file should return a spec or list of specs (see [spec examples](docs/examples.md) or [spec reference](docs/spec.md)):

```lua
-- ./lua/plugins/fundo.lua
return {
  'kevinhwang91/nvim-fundo',
  dependencies = { "kevinhwang91/promise-async" },
  cond = not vim.g.vscode,
  version = 'main',
  build = function() require('fundo').install() end,
  opts = {},
  config = function(_, opts)
    vim.o.undofile = true
    require('fundo').setup(opts)
  end,
}
```

#### Commands

zpack provides the following commands (default prefix: `Z`, customizable via `cmd_prefix` option):

- `:ZUpdate [plugin]` - Update all plugins, or a specific plugin if provided (supports tab completion). See `:h vim.pack.update()`
- `:ZRestore [plugin]` - Restore all plugins, or a specific plugin, to the lockfile state (supports tab completion). Requires a lockfile to exist (created automatically by `:ZUpdate`). See `:h vim.pack.update()`
- `:ZClean` - Remove plugins that are no longer in your spec
- `:ZBuild[!] [plugin]` - Run build hook for a specific plugin, or all plugins with `!` (supports tab completion)
- `:ZLoad[!] [plugin]` - Load a specific unloaded plugin, or all unloaded plugins with `!` (supports tab completion)
- `:ZDelete[!] [plugin]` - Remove a specific plugin, or all plugins with `!` (supports tab completion)
  - Deleting active plugins in your spec can result in errors in your current session. Restart Neovim to re-install them.


#### Configurations

```lua
require('zpack').setup({
  -- { import = 'plugins' }  -- default import spec if not explicitly passed in via [1] or spec
  defaults = {
    confirm = true,          -- set to false to skip vim.pack install prompts (default: true)
    cond = nil,              -- global condition for all plugins, e.g. not vim.g.is_vscode (default: nil)
  },
  performance = {
    vim_loader = true,       -- enables vim.loader for faster startup (default: true)
  },
  cmd_prefix = 'Z',          -- command prefix: :ZUpdate, :ZClean, etc. (default: 'Z')
})
```

Plugin-level settings always take precedence over `defaults`.

#### Importing Specs

```lua
-- automatically import specs from `./lua/plugins/`
require('zpack').setup()

-- or import from a custom directory e.g. `./lua/a/b/plugins/`
require('zpack').setup({ { import = 'a.b.plugins' } })

-- or add your specs inline in setup
require('zpack').setup({
  { 'neovim/nvim-lspconfig', config = function() ... end },
  ...
  { import = 'plugins.mini' }, -- or additionally import from `./lua/plugins/mini/`
})

-- or via the spec field
require('zpack').setup({
  spec = {
    { 'neovim/nvim-lspconfig', config = function() ... end },
    ...
  },
})
```

## Why zpack?

Neovim 0.12+ includes a built-in package manager (`vim.pack`) that handles plugin installation, updates, and version management. zpack is a thin layer that adds lazy-loading capabilities and support for a lazy.nvim-like declarative spec while completely leveraging the native infrastructure.

#### Features
- [z***pack***] is completely native
    - Install and manage your plugins _(including zpack)_ all within `vim.pack`
    - zpack shares the same native user experience as `vim.pack` — cloning, updates, lockfile, and version management. Your editor stays aligned with Neovim core's design philosophy and evolves with it
- [<img width="14" src="https://github.com/user-attachments/assets/1c28419d-f791-4aa4-ada1-b34fb12e95d5">pack] is "batteries included"
    - Add plugins using the same lazy.nvim spec provided by plugin authors you know and love
    - Minimal configurations necessary
- [💤pack] powers up `vim.pack` without the frills
    - Powerful lazy-loading triggers
    - Build triggers for installation/updates
    - Plugin management commands

zpack might be for you if:
- you want your plugin management to stay aligned with Neovim core's design philosophy, but you need a bit more out of the box
- you're a lazy.nvim user but don't use most of its advanced features. You just want a light plugin manager that works, backed by what's already built-in
- you want a manager that supports the lazy.nvim specs plugin authors already provide
- you simplified your config to use `vim.pack` as-is, but you miss lazy-loading, build hooks, plugin management commands, or drop-in lazy plugin specs

As a thin layer, zpack does not provide:
- UI dashboard for your plugins (see [Extensions](#extensions) for community solutions)
- Advanced profiling, change-detection, etc.

If you're a lazy.nvim user, see [Migrating from lazy.nvim](docs/tips.md#migrating-from-lazynvim)

## Spec Examples

See **[Spec Examples](docs/examples.md)** for a full set of examples covering lazy-loading, version pinning, build hooks, dependencies, and more.

## Spec Reference

See **[Spec Reference](docs/spec.md)** for the full spec definition, including `zpack.Plugin`, `zpack.EventSpec`, and `zpack.KeySpec`.

## Tips & Migration

See **[Tips & Migration](docs/tips.md)** for lazy.nvim migration guide and compatibility notes for popular plugins (Snacks.nvim dashboard, noice.nvim, etc.).

## Public API

See **[Public API](docs/public_api.md)** for the supported introspection surface used by third-party tooling like dashboards and status UIs. Also available as `:help zpack-public-api`.

## Extensions

- [zshow.nvim](https://github.com/sairyy/zshow.nvim) — A floating window UI for viewing installed plugins, grouped by load status.

## Acknowledgements

zpack's spec design and several features are inspired by [lazy.nvim](https://github.com/folke/lazy.nvim). Credit to folke for the excellent plugin manager that influenced this project.

zpack's logo is designed by [DodolCat](https://www.instagram.com/_dodolcat/).
