---@module 'zpack'

local api = require('zpack.api')

local M = {}

---@class zpack.ProcessContext
---@field vim_packs vim.pack.Spec[]
---@field src_with_init string[]
---@field registered_startup_packs vim.pack.Spec[]
---@field registered_lazy_packs vim.pack.Spec[]
---@field load boolean?
---@field confirm boolean?
---@field defaults zpack.Config.Defaults
---@field is_dependency? boolean Internal: Whether currently importing as dependency
---@field _imported_functions? table<function, true> Internal: dedup set for function-form `import`

---@return zpack.ProcessContext
local function create_context(opts)
  opts = opts or {}
  return {
    src_with_init = {},
    registered_startup_packs = {},
    registered_lazy_packs = {},
    load = opts.load,
    confirm = opts.confirm,
    defaults = opts.defaults or {},
  }
end

local function check_version()
  if vim.fn.has('nvim-0.12') ~= 1 then
    require('zpack.utils').schedule_notify('requires Neovim 0.12+', vim.log.levels.ERROR)
    return false
  end
  return true
end

---@class zpack.Config.Defaults
---@field cond? boolean|(fun(plugin: zpack.Plugin):boolean)
---@field confirm? boolean
---@field lazy? boolean Treat every spec as lazy unless it sets `lazy = false` (lazy.nvim parity)
---@field version? string|vim.VersionRange|false Default version when none set; `false` means no default (lazy.nvim parity)

---@class zpack.Config.Performance
---@field vim_loader? boolean

---@class zpack.Config.Profiling
---@field loader? boolean Gather stats about module loader (default: false)
---@field require? boolean Track each require in the module loader (default: false)

---lazy.nvim parity: `dev = true` on a spec rewrites its source to a local
---directory under `path` (e.g. `~/projects/<derived-name>`). `fallback = true`
---falls back to the remote source when the local directory does not exist.
---@class zpack.Config.Dev
---@field path? string Base directory for local plugin checkouts (default: '~/projects')
---@field fallback? boolean Fall back to remote source if the local dir is missing (default: false)

---@class zpack.Config
---@field spec? zpack.Spec[]
---@field cmd_name? string Name of the single user command (default: 'ZPack')
---@field defaults? zpack.Config.Defaults
---@field performance? zpack.Config.Performance
---@field profiling? zpack.Config.Profiling
---@field dev? zpack.Config.Dev
---@field plugins_dir? string @deprecated Use { import = 'dir' } in spec instead
---@field confirm? boolean @deprecated Use defaults.confirm instead
---@field disable_vim_loader? boolean @deprecated Use performance.vim_loader instead
---@field cmd_prefix? string @deprecated Legacy :<Prefix><Suffix> commands; use :<cmd_name> <subcommand>
---@field auto_import? any @deprecated Removed; pass specs to setup() instead

local config = {
  cmd_name = 'ZPack',
  defaults = { confirm = true },
  performance = { vim_loader = true },
  profiling = { loader = false, require = false },
  dev = { path = '~/projects', fallback = false },
}

---@param ctx zpack.ProcessContext
local process_all = function(ctx)
  local hooks = require('zpack.hooks')
  local state = require('zpack.state')

  vim.api.nvim_clear_autocmds({ group = state.lazy_build_group })
  vim.api.nvim_clear_autocmds({ group = state.delete_group })
  ctx.vim_packs = require('zpack.merge').resolve_all()
  hooks.setup_build_tracking()
  hooks.setup_delete_tracking()
  require('zpack.registration').register_all(ctx)

  -- Install module loader AFTER registration (when we know lazy plugins)
  -- but BEFORE startup processing (when configs may require lazy modules)
  local module_loader = require('zpack.module_loader')
  module_loader.setup(config.profiling)
  module_loader.initialize_cache(ctx.registered_lazy_packs)
  module_loader.install()

  require('zpack.startup').process_all(ctx)
  require('zpack.lazy').process_all(ctx)
  hooks.run_pending_builds_on_startup(ctx)
  vim.api.nvim_clear_autocmds({ group = state.startup_group })
  hooks.setup_lazy_build_tracking()
end

---@param opts? zpack.Config
M.setup = function(opts)
  if not check_version() then return end

  local state = require('zpack.state')
  if state.is_setup then
    require('zpack.utils').schedule_notify('zpack.setup() has already been called', vim.log.levels.WARN)
    return
  end

  opts = opts or {}

  -- Report malformed options up front. Validation is advisory: setup
  -- continues, and the `type(...) == 'table'` guards on the section merges
  -- below ignore a bad field instead of crashing in `vim.tbl_extend`.
  local config_errors = require('zpack.validate').validate_config(opts)
  if #config_errors > 0 then
    require('zpack.utils').schedule_notify(
      'zpack.setup: invalid options:\n  ' .. table.concat(config_errors, '\n  '),
      vim.log.levels.ERROR
    )
  end

  state.is_setup = true

  local deprecation = require('zpack.deprecation')

  -- Record deprecated/removed options for :checkhealth zpack. Assigned fresh
  -- so the list reflects only this setup() call.
  state.deprecations = {}
  for _, key in ipairs(deprecation.deprecated_option_keys) do
    if opts[key] ~= nil then
      state.deprecations[#state.deprecations + 1] = key
    end
  end

  if opts.cmd_name ~= nil then
    config.cmd_name = opts.cmd_name
  end

  if type(opts.defaults) == 'table' then
    config.defaults = vim.tbl_extend('force', config.defaults, opts.defaults)
  end

  if type(opts.performance) == 'table' then
    config.performance = vim.tbl_extend('force', config.performance, opts.performance)
  end

  if type(opts.profiling) == 'table' then
    config.profiling = vim.tbl_extend('force', config.profiling, opts.profiling)
  end

  if type(opts.dev) == 'table' then
    config.dev = vim.tbl_extend('force', config.dev, opts.dev)
  end

  -- Handle deprecated opts.confirm
  if opts.confirm ~= nil then
    deprecation.notify_deprecated('confirm')
    config.defaults.confirm = opts.confirm
  end

  -- Handle deprecated opts.disable_vim_loader
  if opts.disable_vim_loader ~= nil then
    deprecation.notify_deprecated('disable_vim_loader')
    config.performance.vim_loader = not opts.disable_vim_loader
  end

  -- Expose the fully merged config so :checkhealth and other tooling can
  -- introspect it. Sections are flat one-level tables, so the `tbl_extend`
  -- merges above are sufficient (no `tbl_deep_extend` needed). This is the
  -- same table `setup()` works from, not a copy — treat it as read-only.
  state.config = config

  if config.performance.vim_loader then
    vim.loader.enable()
  end

  if opts.auto_import ~= nil then
    deprecation.notify_removed('auto_import')
  end

  -- `cmd_prefix` is deprecated but will still work for a while
  local legacy_prefix = opts.cmd_prefix ~= nil and opts.cmd_prefix or 'Z'

  local ctx = create_context({ confirm = config.defaults.confirm, defaults = config.defaults })
  local import = require('zpack.import')

  local spec = (type(opts.spec) == 'table' and opts.spec) or (opts[1] and opts) or nil
  if spec then
    import.import_specs(spec, ctx)
  end

  if type(opts.plugins_dir) == 'string' then
    deprecation.notify_deprecated('plugins_dir')
    import.import_specs({ import = opts.plugins_dir }, ctx)
  elseif not spec then
    import.import_specs({ import = 'plugins' }, ctx)
  end

  process_all(ctx)

  require('zpack.commands').setup(config.cmd_name)
  require('zpack.commands').setup_legacy(legacy_prefix, config.cmd_name)
end

---@deprecated Use setup({ spec = { ... } }) instead
M.add = function()
  require('zpack.deprecation').notify_removed('add')
end

---Public API contract version. Alias for |zpack.api.VERSION|.
---@type integer
M.VERSION = api.VERSION

---Return a snapshot of every plugin zpack knows about. Plugins disabled by
---`enabled = false` are pruned during setup and will not appear. See
---|zpack.PluginInfo| for the returned shape. Alias for |zpack.api.get_plugins|;
---the signature is inherited from there.
M.get_plugins = api.get_plugins

---Look up a single plugin by its resolved name. Returns nil when no plugin
---with that name is registered; never throws. Alias for |zpack.api.get_plugin|;
---the signature is inherited from there.
M.get_plugin = api.get_plugin

return M
