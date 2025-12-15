# zpack.nvim

A super lightweight layer on top of Neovim's native `vim.pack` plugin manager to support a lazy.nvim-like declarative spec and minimalist lazy-loading.

The built-in plugin manager itself is currently a work in progress, so please expect breaking changes.

**[Why zpack?](#why-zpack)** | **[Examples](#examples)** | **[Spec Reference](#spec-reference)** | **[Migrating from lazy.nvim](#migrating-from-lazynvim)**

## Requirements

- Neovim 0.12.0+

## Usage

```lua
vim.pack.add({{ src = "https://github.com/zuqini/zpack.nvim" }})

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading zpack.nvim so that mappings are correct.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- automatically import specs from `/lua/plugins/*.lua`
require('zpack').setup({})
-- automatically import specs from a custom directory
require('zpack').setup({ plugins_dir = 'a/b/my_plugins' })
-- add your spec manually
require('zpack').setup({ auto_import = false })
require('zpack').add({
    { 'neovim/nvim-lspconfig', config = function() ... end },
    ...
})
```

### Commands

zpack provides the following commands:

- `:ZUpdate` - Update all plugins
- `:ZClean` - Remove plugins that are no longer in your spec

### Directory Structure

Under the default setting, create plugin specs in `lua/plugins/`:

```
lua/
  plugins/
    treesitter.lua
    telescope.lua
    lsp.lua
```

Each file returns a spec (or list of specs):

```lua
-- lua/plugins/telescope.lua
return {
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  keys = {
    { '<leader>ff', function() require('telescope.builtin').find_files() end, desc = 'Find files' },
  },
  config = function()
    require('telescope').setup({})
  end,
}
```

## Why zpack?

Neovim 0.12+ includes a built-in package manager (`vim.pack`) that handles plugin installation, updates, and version management. zpack is a thin layer that adds lazy-loading capabilities and a lazy.nvim-like declarative structure while leveraging the native infrastructure.

zpack might be for you if:
- you're a lazy.nvim user, love its declarative spec, and its wide adoption by plugin authors, but you don't need most of its advanced features
- you want to try `vim.pack`, but don't want to rewrite your entire plugins spec from scratch
- you're already comfortable with `vim.pack`, and want:
    - A minimalist lazy-loading implementation for faster startup
    - Declarative plugin specs to keep your config neat and tidy
    - A simple, readable codebase you can understand

Out of the box, zpack does not currently provide:
- UI dashboard for your plugins
- Profiling, dev mode, etc.
- Automatic dependency resolution for lazy-loading
- Advanced lazy-loading optimizations

Many of these features are available through Neovim's native tooling. We're actively exploring ways to improve lazy-loading functionality without introducing significant complexity.

For anything else missing, contributions are welcome!

## Examples

```lua
return {
  'nvim-treesitter/nvim-treesitter',
  config = function()
    require('nvim-treesitter.configs').setup({
      ensure_installed = { 'lua', 'vim' },
      highlight = { enable = true },
    })
  end,
}
```

#### Lazy Load on Event

```lua
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter', -- Also supports 'VeryLazy'
  config = function()
    require('nvim-autopairs').setup({})
  end,
}
```

#### Lazy Load on Command

```lua
return {
  'nvim-tree/nvim-tree.lua',
  cmd = { 'NvimTreeToggle', 'NvimTreeFocus' },
  config = function()
    require('nvim-tree').setup({})
  end,
}
```

#### Lazy Load on Keymap

```lua
return {
  'folke/flash.nvim',
  keys = {
    { 's', function() require('flash').jump() end, mode = { 'n', 'x', 'o' }, desc = 'Flash' },
    { 'S', function() require('flash').treesitter() end, mode = { 'n', 'x', 'o' }, desc = 'Flash Treesitter' },
  },
  config = function()
    require('flash').setup({})
  end,
}
```

#### Conditional Loading

```lua
return {
  'linux-only-plugin',
  enabled = vim.fn.has('linux') == 1,
  config = function()
    -- plugin config
  end,
}
```

#### Load Priority

Control load order for startup plugins (higher priority loads first):

```lua
return {
  'folke/tokyonight.nvim',
  priority = 1000,  -- Load colorscheme early
  config = function()
    vim.cmd('colorscheme tokyonight')
  end,
}
```

#### Build Hook

```lua
return {
  'nvim-telescope/telescope-fzf-native.nvim',
  build = 'make',
  config = function()
    require('telescope').load_extension('fzf')
  end,
}
```

#### Multiple Plugins in One File

```lua
return {
  { 'nvim-lua/plenary.nvim' },
  { 'nvim-tree/nvim-web-devicons' },
  {
    'nvim-lualine/lualine.nvim',
    config = function()
      require('lualine').setup({})
    end,
  },
}
```

## Spec Reference

Based on the `Spec` type definition:

```lua
{
  -- Plugin identification (provide at least one)
  [1] = "user/repo",                    -- Plugin short name. Expands to https://github.com/{user/repo}
  src = "https://...",                  -- Custom git URL (local paths also supported)

  -- Source control
  version = vim.version.range("1.*"),   -- Version range via vim.version.range()

  -- Loading control
  enabled = true|false|function,        -- Enable/disable plugin
  cond = true|false|function,           -- Condition to load plugin
  lazy = true|false,                    -- Force eager loading when false (auto-detected)
  priority = 50,                        -- Load priority for startup plugins (higher = earlier, default: 50)

  -- Lifecycle hooks
  init = function() end,                -- Runs before plugin loads
  config = function() end,              -- Runs after plugin loads
  build = string|function,              -- Build command or function

  -- Lazy loading triggers (auto-sets lazy=true)
  event = string|string[],              -- Autocommand event(s). Supports 'VeryLazy'
  pattern = string|string[],            -- Event pattern(s)
  cmd = string|string[],                -- Command(s) to create
  keys = KeySpec|KeySpec[],             -- Keymap(s) to create
}
```

### KeySpec Reference

```lua
{
  [1] = "<leader>ff",             -- LHS keymap (required)
  [2] = function() end,           -- RHS function
  desc = "description",           -- Keymap description
  mode = "n"|{"n","v"},           -- Mode(s), default: "n"
  noremap = true|false,           -- Default: true
  nowait = true|false,            -- Default: false
}
```

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with zpack. Simply copy your specs from `lazy.setup()` to `zpack.setup()` or your `lua/plugins/` directory.

**Key differences:**

- **Dependencies**: zpack does not have a `dependencies` field. Use `priority` to control load order for startup plugins (higher values load first), or structure your lazy-loading triggers (like `event`, `cmd`, `keys`) to ensure dependencies load before dependent plugins.
- **url**/**dir**: use `src` instead. See `:h vim.pack.Spec`
- **opt**: For simplicity, use `config` instead.
- **Other unsupported fields**: Remove lazy.nvim-specific fields like `dev`, `name`, `module`, etc. See the [Spec Reference](#spec-reference) for supported fields.

**Example migration:**

```lua
-- lazy.nvim
{
  'nvim-telescope/telescope.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = 'Telescope',
}

-- zpack
-- Add plenary as a separate spec to load on startup
{ 'nvim-lua/plenary.nvim' },
-- Alternatively, add plenary on the same cmd as Telescope with higher priority
{
  'nvim-lua/plenary.nvim'
  cmd = 'Telescope',
  priority = 1000,
},

-- Telescope will load when needed via cmd trigger
{
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
}
```

