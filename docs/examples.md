# Spec Examples

- [Plugin Spec](#plugin-spec)
- [Lazy Load on Command](#lazy-load-on-command)
- [Lazy Load on Keymap](#lazy-load-on-keymap)
- [Lazy Load on Event](#lazy-load-on-event)
- [Lazy Load on Event with Pattern](#lazy-load-on-event-with-pattern)
- [Lazy Load on FileType](#lazy-load-on-filetype)
- [Conditional Loading](#conditional-loading)
- [Build Hook](#build-hook)
- [Dependencies](#dependencies)
- [Version Pinning](#version-pinning)
  - [Version Pinning for lazy.nvim compatibility](#version-pinning-for-lazynvim-compatibility)
- [Load Priority](#load-priority)
- [Using Plugin Data in Hooks](#using-plugin-data-in-hooks)
- [Explicit Main Module](#explicit-main-module)
- [Multiple Plugins in One File](#multiple-plugins-in-one-file)
- [Real-World Config](#real-world-config)

#### Plugin Spec

```lua
return {
  'nvim-mini/mini.bracketed',
  -- If `opts` or `config = true` is set, the config hook calls
  --    `require(MAIN).setup(opts)` by default.
  opts = {}, -- calls `require('mini.bracketed').setup({})`
}
```

```lua
return {
  'nvim-lualine/lualine.nvim',
  opts = { theme = 'tokyonight' },
  -- Explicitly define a `config` function hook if you need to run custom logic on plugin load.
  -- The resolved `zpack.Plugin` and `opts` table are passed as its arguments:
  config = function(_, opts)
    vim.opt.showmode = false 
    require('lualine').setup(opts)
  end,
}
```

#### Lazy Load on Command

```lua
return {
  'nvim-tree/nvim-tree.lua',
  cmd = { 'NvimTreeToggle', 'NvimTreeFocus' },
  opts = {},
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
  opts = {},
}
```

#### Lazy Load on Event

```lua
return {
  'windwp/nvim-autopairs',
  event = 'InsertEnter', -- Also supports 'VeryLazy'
  opts = {},
}
```

#### Lazy Load on Event with Pattern

```lua
-- Inline pattern
return {
  'rust-lang/rust.vim',
  event = 'BufReadPre *.rs',
}

-- Or using EventSpec for multiple patterns
return {
  'polyglot-plugin',
  event = {
    event = 'BufReadPre',
    pattern = { '*.lua', '*.rs' },
  },
  opts = {},
}
```

#### Lazy Load on FileType

Load plugin when opening files of specific types. Automatically re-triggers `BufReadPre`, `BufReadPost`, and `FileType` events to ensure LSP clients and Treesitter attach properly:

```lua
return {
  'rust-lang/rust.vim',
  ft = { 'rust', 'toml' },
}
```

#### Conditional Loading

Use `enabled` to skip `vim.pack.add` entirely, or `cond` to conditionally load after calling `vim.pack.add`:

```lua
return {
  'project-specific-plugin',
  enabled = vim.fn.has('linux') == 1, -- skip installation
  cond = function() return vim.fn.filereadable('.project-marker') == 1 end, -- skip loading
  opts = {},
}
```

#### Build Hook

```lua
return {
  'nvim-telescope/telescope-fzf-native.nvim',
  build = 'make',
}
```

#### Dependencies

```lua
return {
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { 'nvim-tree/nvim-web-devicons', opts = {} },
  },
}
```

Dependencies are automatically loaded before the parent plugin when the parent's lazy trigger fires.

#### Version Pinning

`vim.pack.add` expects `version` to be `string|vim.VersionRange`:

```lua
return {
  'mrcjkb/rustaceanvim',
  version = vim.version.range('^6'), -- semver version
  -- version = 'main', -- branch
  -- version = 'v1.0.0', -- tag
  -- version = 'abc123', -- commit
}
```
See `:h vim.pack.Spec`, `:h vim.version.range()`, and `:h vim.VersionRange`.

##### Version Pinning for lazy.nvim compatibility

```lua
return {
  'mrcjkb/rustaceanvim',
  sem_version = '^6',  -- corresponds to lazy.nvim spec's `version`, auto-wrapped to vim.version.range()
  -- branch = 'main',
  -- tag = 'v1.0.0',
  -- commit = 'abc123',
}
```

#### Load Priority

Control plugin load order with priority (higher values load first; default: 50):

```lua
-- to load colorscheme early
return {
  'folke/tokyonight.nvim',
  priority = 1000,
  config = function() vim.cmd('colorscheme tokyonight') end,
}
```

#### Using Plugin Data in Hooks

All lifecycle hooks (`init`, `config`, `build`, `cond`) and lazy-loading triggers (`event`, `cmd`, `keys`, `ft`) can be functions that receive a `zpack.Plugin` object containing the resolved plugin path and spec:

```lua
return {
  'some/plugin',
  build = function(plugin)
    -- plugin.path: absolute path to the plugin directory
    -- plugin.spec: the vim.pack.Spec with resolved name, src, version
    vim.fn.system({ 'make', '-C', plugin.path })
  end,
}
```

#### Explicit Main Module

If automatic module detection fails, specify the module explicitly with `main`:

```lua
return {
  'some/plugin-with-unusual-structure',
  main = 'plugin.core',
  opts = {},
}
```

#### Multiple Plugins in One File

```lua
return {
  { 'nvim-lua/plenary.nvim' },
  { 'nvim-tree/nvim-web-devicons' },
  { 'nvim-lualine/lualine.nvim', opts = { theme = 'auto' } },
  { import = 'plugins.mini' },
}
```

#### Real-World Config

For more examples, refer to example config:
- [zpack installation and setup](https://github.com/zuqini/nvim/blob/main/init.lua)
- [plugins directory structure](https://github.com/zuqini/nvim/tree/main/lua/plugins)
