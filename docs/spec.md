# Spec Reference

```lua
{
  -- Plugin source (provide exactly one)
  [1] = "user/repo",                    -- Plugin short name. Expands to https://github.com/{user/repo}
  src = "https://...",                  -- Custom git URL or local path
  dir = "/path/to/plugin",              -- Local plugin directory (lazy.nvim compat, ~ expanded, mapped to src)
  url = "https://...",                  -- Custom git URL (lazy.nvim compat, mapped to src)

  -- Dependencies
  dependencies = string|string[]|zpack.Spec|zpack.Spec[], -- Plugin dependencies

  -- Loading control
  enabled = true|false|function,        -- Enable/disable plugin
  cond = true|false|function(plugin),   -- Condition to load plugin
  lazy = true|false,                    -- Force eager loading when false (auto-detected)
  priority = 50,                        -- Load priority (higher = earlier, default: 50)

  -- Plugin configuration
  opts = {},                            -- Options passed to setup(), triggers auto-setup
  -- opts = function(plugin, opts) return {} end, -- Can also be a function

  -- Lifecycle hooks
  init = function(plugin) end,          -- Runs before plugin loads, useful for certain vim plugins
  config = function(plugin, opts) end,  -- Runs after plugin loads, receives resolved opts
  -- config = true,                      -- Calls require(main).setup({})
  build = string|function(plugin),      -- Build command or function

  -- Lazy loading triggers (auto-sets lazy=true unless overridden)
  -- All triggers can also be functions that receive zpack.Plugin and return the respective type
  event = string|string[]|zpack.EventSpec|(string|zpack.EventSpec)[]|function(plugin), -- Autocommand event(s). Supports 'VeryLazy' and inline patterns: "BufReadPre *.lua". zpack auto-emits `User VeryLazy` once on UIEnter so user-config `autocmd User VeryLazy` hooks fire.
  pattern = string|string[],            -- Global fallback pattern(s) for all events
  cmd = string|string[]|function(plugin), -- Command(s) to create; tab-completion on the command also triggers the load
  keys = zpack.KeySpec|zpack.KeySpec[]|function(plugin), -- Keymap(s) to create
  ft = string|string[]|function(plugin), -- FileType(s) to lazy load on

  -- Source control (version for `vim.pack.add`, string|vim.VersionRange)
  version = "main",                     -- Git branch, tag, or commit
  -- version = vim.version.range("1.*"), -- Or semver range via vim.version.range()

  -- Source control (lazy.nvim compat, mapped to version)
  sem_version = "^1.0.0",               -- Semver string (corresponds to lazy.nvim spec's version), auto-wrapped to vim.version.range()
  branch = "main",                      -- Git branch
  tag = "v1.0.0",                       -- Git tag
  commit = "abc123",                    -- Git commit

  -- Plugin metadata
  name = "my-plugin",                   -- Custom plugin name (optional, overrides auto-derived name)
  main = "module.name",                 -- Explicit main module (auto-detected if not set)
  module = false,                       -- Disable module-based lazy loading for this plugin

  -- Spec imports
  import = "plugins.lsp",               -- Import from lua/{path}/*.lua and lua/{path}/*/init.lua
}
```

### zpack.Plugin Reference

The plugin data object passed to hooks and trigger functions:

```lua
{
  spec = vim.pack.Spec,           -- The resolved vim.pack spec (name, src, version)
  path = string,                  -- Absolute path to the plugin directory
}
```

### zpack.EventSpec Reference

```lua
{
  event = string|string[],        -- Event name(s) to trigger on
  pattern = string|string[],      -- Pattern(s) for the event (optional)
}
```

### zpack.KeySpec Reference

```lua
{
  [1] = "<leader>ff",             -- LHS keymap (required)
  [2] = function() end,           -- RHS function
  desc = "description",           -- Keymap description
  mode = "n"|{"n","v"},           -- Mode(s), default: "n"
  ft = "lua"|{"lua","vim"},       -- FileType scope; keymap installs buffer-locally on matching FileType only
  buffer = true|0|7,              -- Buffer scope: true/0 = current buffer; integer = specific buffer
  remap = true|false,             -- Allow remapping, default: false
  nowait = true|false,            -- Default: false
  expr = true|false,              -- RHS is an expression, default: false
  silent = true|false,            -- Suppress command-line output, default: false
  noremap = true|false,           -- Inverse of `remap` (lazy.nvim alias)
  replace_keycodes = true|false,  -- Replace keycodes in expr result; defaults to true when expr is true
}
```

A KeySpec whose `[2]` rhs is `<Nop>` (any case) or the empty string is
installed as a real no-op keymap rather than a lazy proxy — pressing the key
never loads the plugin. Useful for suppressing default mappings the plugin
would otherwise install. Matches lazy.nvim's `Util.is_nop` behavior.

### zpack.PluginInfo Reference

Snapshot of a registered plugin returned by the public API functions under `require('zpack.api')`. Treat as read-only. See `:help zpack-public-api` or [docs/public_api.md](public_api.md) for the full reference, including stability guarantees and field-level docs.

```lua
{
  name   = string,                        -- resolved plugin name
  src    = string,                        -- git URL or local path
  status = "loaded"|"pending"             -- current load/enablement state
         | "loading"|"disabled",
  lazy   = boolean,                       -- configured to lazy-load?
  path   = string,                        -- plugin directory on disk
  rev    = string?,                       -- installed git revision
}
```
