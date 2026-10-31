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
---@field parent? zpack.Spec Internal: The spec whose `dependencies` or `specs` is being imported
---@field _imported_functions table<function, { parents: table, specs: table? }> Internal: per-setup() record of function-form `import`
---@field early_plugins table<string, zpack.Plugin> Internal: plugins added while importing their specs, by name, until registered
---@field import_paths string[] Internal: where those plugins are, for later imports
---@field missing_owners table<zpack.Spec, true> Internal: specs importing from a plugin that isn't installed, this pass
---@field settled_owners table<zpack.Spec, 'added'|'removed'> Internal: what became of them
---@field import_notes { msg: string, level: integer }[] Internal: what the last pass has to report

---@return zpack.ProcessContext
local function create_context(opts)
  opts = opts or {}
  return {
    src_with_init = {},
    registered_startup_packs = {},
    registered_lazy_packs = {},
    load = vim.v.vim_did_init == 1,
    confirm = opts.confirm,
    defaults = opts.defaults or {},
    _imported_functions = {},
    early_plugins = {},
    import_paths = {},
    missing_owners = {},
    settled_owners = {},
    import_notes = {},
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
  hooks.setup_delete_tracking()
  require('zpack.registration').register_all(ctx)

  -- Install module loader AFTER registration (when we know lazy plugins)
  -- but BEFORE startup processing (when configs may require lazy modules)
  local module_loader = require('zpack.module_loader')
  module_loader.setup(config.profiling)
  module_loader.initialize_cache(ctx.registered_lazy_packs)
  module_loader.install()

  require('zpack.startup').process_all(ctx)
  -- Before the triggers: a proxy for what a build just loaded would outlive the load.
  hooks.run_pending_builds_on_startup(ctx)
  require('zpack.lazy').process_all(ctx)
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

  -- Expose the fully merged config so :checkhealth and other tooling can
  -- introspect it. Sections are flat one-level tables, so the `tbl_extend`
  -- merges above are sufficient (no `tbl_deep_extend` needed). This is the
  -- same table `setup()` works from, not a copy — treat it as read-only.
  state.config = config

  if config.performance.vim_loader then
    vim.loader.enable()
  end

  local ctx = create_context({ confirm = config.defaults.confirm, defaults = config.defaults })
  local import = require('zpack.import')

  -- Before the imports: one that needs its plugin's modules can install it.
  require('zpack.hooks').setup_build_tracking()

  local spec = (type(opts.spec) == 'table' and opts.spec) or (opts[1] and opts) or nil
  import.import_all(spec or { import = 'plugins' }, ctx)

  process_all(ctx)

  require('zpack.commands').setup(config.cmd_name)
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
