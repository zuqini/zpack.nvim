# zpack.nvim
<img alt="GitHub code size in bytes" src="https://img.shields.io/github/languages/code-size/zuqini/zpack.nvim"> <img alt="GitHub last commit" src="https://img.shields.io/github/last-commit/zuqini/zpack.nvim"> <img alt="GitHub License" src="https://img.shields.io/github/license/zuqini/zpack.nvim">

A super lightweight layer on top of Neovim's native `vim.pack`, with support for the widely adopted lazy.nvim-like declarative spec and minimalist lazy-loading using only Neovim's builtin features.

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

**[Why zpack?](#why-zpack)** | **[Examples](#examples)** | **[Dependency Handling](#dependency-handling)** | **[Spec Reference](#spec-reference)** | **[Migrating from lazy.nvim](#migrating-from-lazynvim)**

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

- `:ZUpdate [plugin]` - Update all plugins, or a specific plugin if provided (supports tab completion). See `:h vim.pack.update()`
- `:ZClean` - Remove plugins that are no longer in your spec
- `:ZBuild[!] [plugin]` - Run build hook for a specific plugin, or all plugins with `!` (supports tab completion)
- `:ZDelete[!] [plugin]` - Remove a specific plugin, or all plugins with `!` (supports tab completion)

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

### Performance

By default, zpack enables `vim.loader` to cache Lua module bytecode and speed up startup. You can disable it:

```lua
require('zpack').setup({
  disable_vim_loader = true,
})
```

## Why zpack?

Neovim 0.12+ includes a built-in package manager (`vim.pack`) that handles plugin installation, updates, and version management. zpack is a thin layer that adds lazy-loading capabilities and a lazy.nvim-like declarative structure while leveraging the native infrastructure.

zpack might be for you if:
- you're a lazy.nvim user, love its declarative spec, and its wide adoption by plugin authors, but you don't need most of its advanced features
- you want to try `vim.pack`, but don't want to rewrite your entire plugins spec from scratch
- you're already comfortable with `vim.pack`, and want:
    - A minimalist lazy-loading implementation for faster startup
    - Declarative plugin specs to keep your config neat and tidy

Out of the box, zpack does not provide:
- UI dashboard for your plugins
- Profiling, dev mode, etc.
- Implicit dependency inference (see [Dependency Handling](#dependency-handling) for the explicit approach)

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
-- Inline pattern (same as lazy.nvim)
return {
  'rust-lang/rust.vim',
  event = 'BufReadPre *.rs',
  config = function()
    vim.g.rustfmt_autosave = 1
  end,
}

-- Or using EventSpec
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

Use `enabled` to skip `vim.pack.add` entirely, or `cond` to conditionally load after calling `vim.pack.add`:

```lua
-- enabled: Checked at setup time, vim.pack.add never called if false
return {
  'linux-only-plugin',
  enabled = vim.fn.has('linux') == 1,
  config = function()
    -- plugin config
  end,
}

-- cond: Checked at load time, vim.pack.add called but won't load if false
return {
  'project-specific-plugin',
  cond = function()
    return vim.fn.filereadable('.project-marker') == 1
  end,
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

Build hooks run after plugin installation or update. When a build hook runs, zpack loads all plugins first (in priority order) to ensure any cross-plugin dependencies are available. For example, a plugin's build hook can safely call `:TSInstall` even if nvim-treesitter is lazy-loaded.

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

## Dependency Handling

Unlike lazy.nvim, zpack does not have a `dependencies` field to automatically infer plugin load order. Instead, you explicitly control dependencies using one of two approaches:

### Option 1: Load Dependencies at Startup

The simplest approach is to load dependency plugins at startup (without lazy-loading triggers) while keeping the dependent plugin lazy-loaded. For most plugins, loading small dependencies at startup has negligible impact on startup time while keeping your config simple.

**lazy.nvim:**
```lua
return {
  'nvim-telescope/telescope.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = 'Telescope',
}
```

**zpack:**
```lua
return {
  { 'nvim-lua/plenary.nvim' },  -- Loads at startup
  {
    'nvim-telescope/telescope.nvim',
    cmd = 'Telescope',  -- Lazy-loaded on command
  }
}
```

### Option 2: Use Priority with Same Trigger

If you want both plugins lazy-loaded, use the same trigger with `priority` to control load order (higher = earlier):

```lua
local common_cmd_trigger = 'Telescope'
return {
  {
    'nvim-lua/plenary.nvim',
    cmd = common_cmd_trigger,
    priority = 1000,  -- Loads first
  },
  {
    'nvim-telescope/telescope.nvim',
    cmd = common_cmd_trigger,  -- Loads second
  }
}
```

**Note:** Priority only affects `vim.pack.add` order for lazy-loaded plugins with the same trigger. For non lazy-loaded plugins, all packages are added simultaneously via `vim.pack.add()` before calling plugin's config hooks, and priority only affects the order in which the config hooks are called. There should almost never be a need to define dependency priority for non lazy-loaded plugins.

## Spec Reference

```lua
{
  -- Plugin source (provide exactly one)
  [1] = "user/repo",                    -- Plugin short name. Expands to https://github.com/{user/repo}
  src = "https://...",                  -- Custom git URL or local path
  dir = "/path/to/plugin",              -- Local plugin directory (lazy.nvim compat, mapped to src)
  url = "https://...",                  -- Custom git URL (lazy.nvim compat, mapped to src)

  -- Plugin metadata
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
  event = string|string[]|EventSpec|(string|EventSpec)[],  -- Autocommand event(s). Supports 'VeryLazy' and inline patterns: "BufReadPre *.lua"
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

**Key differences:**

- **Dependencies**: zpack does not have a `dependencies` field. See [Dependency Handling](#dependency-handling) for how to manage plugin dependencies using `priority` or startup loading
- **opt**: use `config = function() ... end` instead
- **Other unsupported fields**: Remove lazy.nvim-specific fields like `dev`, `main`, `module`, etc. See the [Spec Reference](#spec-reference) for supported fields

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
