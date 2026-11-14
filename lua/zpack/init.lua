---@module 'zpack'

-- zpack's modules mostly run once, at startup, where tracing their loops costs
-- more than it ever saves: about 6 ms with 150 plugins. So each one that runs
-- then turns the JIT off for its own functions, leaving everything else's alone.
if jit then jit.off(true, true) end

local api = require('zpack.api')

local M = {}

---@class zpack.ProcessContext
---@field vim_packs vim.pack.Spec[]
---@field src_with_init string[]
---@field registered_startup_packs vim.pack.Spec[]
---@field registered_lazy_packs vim.pack.Spec[]
---@field load boolean Internal: past init, so plugins source their own scripts
---@field confirm boolean?
---@field defaults zpack.Config.Defaults
---@field imported zpack.Imported Internal: what the import found

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

---lazy.nvim parity: `dev = true` on a spec rewrites its source to a local
---directory under `path` (e.g. `~/projects/<derived-name>`). `fallback = true`
---falls back to the remote source when the local directory does not exist.
---@class zpack.Config.Dev
---@field path? string Base directory for local plugin checkouts (default: '~/projects')
---@field fallback? boolean Fall back to remote source if the local dir is missing (default: false)

---@class zpack.Config
---@field spec? zpack.Spec[]|string A string is the module to import
---@field cmd_name? string Name of the single user command (default: 'ZPack')
---@field defaults? zpack.Config.Defaults
---@field performance? zpack.Config.Performance
---@field dev? zpack.Config.Dev

local config = {
  cmd_name = 'ZPack',
  defaults = { confirm = true },
  performance = { vim_loader = true },
  dev = { path = '~/projects', fallback = false },
}

---@param ctx zpack.ProcessContext
local process_all = function(ctx)
  local hooks = require('zpack.hooks')
  local state = require('zpack.state')

  ctx.vim_packs = require('zpack.merge').resolve_all(ctx.imported.graph, ctx.imported.enabled_results)
  hooks.setup_delete_tracking()
  require('zpack.registration').register_all(ctx)

  -- Install module loader BEFORE startup processing (when inits and configs may require plugins)
  local module_loader = require('zpack.module_loader')
  module_loader.install()
  -- Eager plugins too until they're on 'runtimepath', for an init or a trigger function that requires one's module.
  module_loader.initialize_cache(vim.list_extend(vim.list_extend({}, ctx.registered_lazy_packs), ctx.registered_startup_packs))
  -- lazy.nvim parity: before the inits, which can run a lazy plugin's command, event, filetype or key.
  require('zpack.lazy').setup_triggers(ctx)
  require('zpack.lazy_trigger.colorscheme').setup(ctx.registered_startup_packs, ctx.registered_lazy_packs)

  require('zpack.startup').process_all(ctx)
  require('zpack.import').remove_import_paths(ctx.imported)
  hooks.run_pending_builds_on_startup()
  require('zpack.lazy_trigger.ft').source_ftdetect_after_startup()
  require('zpack.lazy_trigger.event').fire_very_lazy()
  vim.api.nvim_clear_autocmds({ group = state.startup_group })
  hooks.setup_lazy_build_tracking()
end

---What's left of setup()'s table once its options are out, for specs written as
---its array elements. `dev` is an option only as a table: `dev = true` belongs to a
---spec written in place, as in `setup({ 'u/a', dev = true })`.
---@param opts table
---@return table
local function specs_beside_options(opts)
  local specs = {}
  for key, value in pairs(opts) do
    local is_option = key == 'dev' and type(value) == 'table'
        or key == 'spec' or key == 'cmd_name' or key == 'defaults' or key == 'performance' or key == 'profiling'
    if not is_option then
      specs[key] = value
    end
  end
  return specs
end

---@param opts? zpack.Config|string A string is the module to import
M.setup = function(opts)
  if not check_version() then return end

  local state = require('zpack.state')
  if state.is_setup then
    require('zpack.utils').schedule_notify('zpack.setup() has already been called', vim.log.levels.WARN)
    return
  end

  opts = type(opts) == 'string' and { spec = opts } or opts or {}

  -- Report malformed options up front. Validation is advisory: setup
  -- continues, and the `type(...) == 'table'` guards on the section merges
  -- below ignore a bad field instead of crashing in `vim.tbl_extend`.
  local validate = require('zpack.validate')
  local config_errors = validate.validate_config(opts)
  if #config_errors > 0 then
    require('zpack.utils').schedule_notify(
      'zpack.setup: invalid options:\n  ' .. table.concat(config_errors, '\n  '),
      vim.log.levels.ERROR
    )
  end
  opts = type(opts) == 'table' and opts or { spec = opts }

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
  local import_run = require('zpack.import_run')

  -- Before the imports: one that needs its plugin's modules can install it.
  require('zpack.hooks').setup_build_tracking()

  local spec = (type(opts.spec) == 'string' and opts.spec ~= '' and { import = opts.spec })
      or (type(opts.spec) == 'table' and opts.spec)
      or ((table.maxn(opts) > 0 or validate.has_source_field(opts)) and specs_beside_options(opts))
      or nil
  ctx.imported = import_run.import_all(spec, ctx)
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
