# zpack.nvim
<img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/zuqini/zpack.nvim"> <img alt="GitHub last commit" src="https://img.shields.io/github/last-commit/zuqini/zpack.nvim"> <img alt="GitHub License" src="https://img.shields.io/github/license/zuqini/zpack.nvim">

A super lightweight layer on top of Neovim's native `vim.pack` plugin manager to support a lazy.nvim-like declarative spec and minimalist lazy-loading.

```lua
-- ./lua/plugins/fundo.lua
return {
  { 'kevinhwang91/promise-async' },
  {
    'kevinhwang91/nvim-fundo',
    version = 'main',
    build = function() require('fundo').install() end,
    config = function()
      vim.o.undofile = true
      require('fundo').setup()
    end,
  },
}
```

The built-in plugin manager itself is currently a work in progress, so please expect breaking changes.

**[Why zpack?](#why-zpack)** | **[Examples](#examples)** | **[Spec Reference](#spec-reference)** | **[Migrating from lazy.nvim](#migrating-from-lazynvim)**

## Requirements

- Neovim 0.12.0+

## Usage

```lua
vim.pack.add({ 'https://github.com/zuqini/zpack.nvim' })

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

- `:ZUpdate` - Update all plugins. See `:h vim.pack.update()`
- `:ZClean` - Remove plugins that are no longer in your spec
- `:ZCleanAll` - Remove all installed plugins
- `:ZDelete <plugin>` - Remove a specific plugin (supports tab completion)

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

Additionally, because everything is just `vim.pack` under the hood, you can mix and match zpack.nvim specs and traditional `vim.pack.add({ ... })` as you wish!

Out of the box, zpack does not provide:
- UI dashboard for your plugins
- Profiling, dev mode, etc.
- Implicit dependency inference for lazy-loading

Many of these features are available through Neovim's native tooling. We're actively exploring ways to improve lazy-loading functionality without introducing significant complexity.

For anything else missing, contributions are welcome!

## Examples
For more examples, refer to my personal config:
- [zpack installation and setup](https://github.com/zuqini/nvim/blob/main/init.lua)
- [plugins directory structure](https://github.com/zuqini/nvim/tree/main/lua/plugins)
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

#### Lazy Load on Event with Pattern

```lua
-- Single pattern
return {
  'rust-lang/rust.vim',
  event = {
    event = 'BufReadPre',
    pattern = '*.rs',
  },
  config = function()
    vim.g.rustfmt_autosave = 1
  end,
}

-- Multiple patterns for same event
return {
  'polyglot-plugin',
  event = {
    event = 'BufReadPre',
    pattern = { '*.lua', '*.rs' },
  },
  config = function()
    -- plugin config
  end,
}

-- Multiple events with different patterns
return {
  'file-type-plugin',
  event = {
    { event = 'BufReadPre', pattern = '*.lua' },
    { event = 'BufNewFile', pattern = '*.rs' },
  },
  config = function()
    -- plugin config
  end,
}
```

#### Lazy Load on FileType

Load plugin when opening files of specific types. Automatically re-triggers `BufReadPre`, `BufReadPost`, and `FileType` events to ensure LSP clients and Treesitter attach properly:

```lua
return {
  'rust-lang/rust.vim',
  ft = 'rust',
  config = function()
    vim.g.rustfmt_autosave = 1
  end,
}

-- Multiple filetypes
return {
  'some-plugin',
  ft = { 'lua', 'rust', 'go' },
  config = function()
    -- plugin config
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

Control plugin load order with priority (higher values load first; default: 50):

```lua
-- Startup plugin: load colorscheme early
return {
  'folke/tokyonight.nvim',
  priority = 1000,
  config = function()
    vim.cmd('colorscheme tokyonight')
  end,
}

-- Lazy plugin: ensure base plugin loads before dependent
return {
  'user/base-plugin',
  event = 'VeryLazy',
  priority = 100,  -- Loads before other VeryLazy plugins
  config = function()
    _G.MyAPI = { setup = function() end }
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

```lua
{
  -- Plugin identification (provide at least one)
  [1] = "user/repo",                    -- Plugin short name. Expands to https://github.com/{user/repo}
  src = "https://...",                  -- Custom git URL (local paths also supported)
  name = "my-plugin",                   -- Custom plugin name (optional, overrides auto-derived name)

  -- Source control
  version = vim.version.range("1.*"),   -- Version range via vim.version.range()

  -- Loading control
  enabled = true|false|function,        -- Enable/disable plugin
  cond = true|false|function,           -- Condition to load plugin
  lazy = true|false,                    -- Force eager loading when false (auto-detected)
  priority = 50,                        -- Load priority (higher = earlier, default: 50)

  -- Lifecycle hooks
  init = function() end,                -- Runs before plugin loads, useful for certain vim plugins
  config = function() end,              -- Runs after plugin loads
  build = string|function,              -- Build command or function

  -- Lazy loading triggers (auto-sets lazy=true unless overridden)
  event = string|string[]|EventSpec|(string|EventSpec)[],  -- Autocommand event(s). Supports 'VeryLazy'
  pattern = string|string[],            -- Global fallback pattern(s) for all events
  cmd = string|string[],                -- Command(s) to create
  keys = KeySpec|KeySpec[],             -- Keymap(s) to create
  ft = string|string[],                 -- FileType(s) to lazy load on
}
```

### EventSpec Reference

```lua
{
  event = string|string[],        -- Event name(s) to trigger on
  pattern = string|string[],      -- Pattern(s) for the event (optional)
}
```

### KeySpec Reference

```lua
{
  [1] = "<leader>ff",             -- LHS keymap (required)
  [2] = function() end,           -- RHS function
  desc = "description",           -- Keymap description
  mode = "n"|{"n","v"},           -- Mode(s), default: "n"
  remap = true|false,             -- Allow remapping, default: false
  nowait = true|false,            -- Default: false
}
```

## Migrating from lazy.nvim

Most of your lazy.nvim plugin specs will work as-is with zpack.

<a name="key-differences"></a>
**Key differences:**

- **url**/**dir**: use `src` instead. See `:h vim.pack.Spec`
- **Dependencies**: zpack does not have a `dependencies` field to implicitly infer plugin ordering. Use `priority` to directly control load order (higher values load first) for both startup and lazy-loaded plugins, or structure your lazy-loading triggers (like `event`, `cmd`, `keys`) to ensure dependencies load before dependent plugins. See the `plenary.nvim` [example migration](#example-migration)
- **opt**: use `config = function() ... end` instead.
- **Other unsupported fields**: Remove lazy.nvim-specific fields like `dev`, `main`, `module`, etc. See the [Spec Reference](#spec-reference) for supported fields.

<a name="example-migration"></a>
**Example migration:**

```lua
-- lazy.nvim
return {
  'nvim-telescope/telescope.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = 'Telescope',
}
```

```lua
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

### blink.cmp + lazydev

Due to the lack of implicit dependency inference, when using `blink.cmp` with `lazydev`, add lazydev to `per_filetype` instead of `default` sources.

This approach also ensures lazydev loads only in Lua files, rather than every time blink.cmp loads (which happens even with lazy.nvim if lazydev is part of the default sources).

```lua
require('blink.cmp').setup({
  sources = {
    per_filetype = {
      lua = { inherit_defaults = true, 'lazydev' }
    },
    providers = {
      lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", fallbacks = { "lsp" } },
    },
  },
})
```
