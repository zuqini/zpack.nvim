---@class zpack.KeymapOpts
---@field mode? string|string[]
---@field desc? string
---@field remap? boolean
---@field nowait? boolean
---@field expr? boolean
---@field silent? boolean
---@field replace_keycodes? boolean
---@field buffer? integer|boolean

---@class zpack.KeySpec : zpack.KeymapOpts
---@field [1] string
---@field [2]? string|fun()
---@field noremap? boolean
---@field ft? string|string[] FileType scope (lazy.nvim parity); keymap installs buffer-locally on matching FileType only (both proxy and real keymap)

---@class zpack.EventSpec
---@field event string|string[] Event name(s) to trigger on
---@field pattern? string|string[] Pattern(s) for the event

---Normalized event with pattern
---@class zpack.NormalizedEvent
---@field events string[] List of event names
---@field pattern string|string[] Pattern(s) for these events

---Plugin data passed to load callback from vim.pack.add
---@class zpack.Plugin
---@field spec vim.pack.Spec
---@field path string
---@field main? string The detected main module name (available in config hooks)

---@alias zpack.EventValue string|string[]|zpack.EventSpec|(string|zpack.EventSpec)[]
---@alias zpack.CmdValue string|string[]
---@alias zpack.KeysValue string|string[]|zpack.KeySpec|zpack.KeySpec[]
---@alias zpack.FtValue string|string[]

---@class zpack.Spec
---@field [1]? string Plugin short name (e.g., "user/repo"). Required if src/dir/url not provided
---@field src? string Custom git URL or local path. Required if [1]/dir/url not provided
---@field dir? string Local plugin directory path (lazy.nvim compat). Mapped to src
---@field url? string Custom git URL (lazy.nvim compat). Mapped to src
---@field name? string Custom plugin name. Overrides auto-derived name from URL
---@field init? fun(plugin: zpack.Plugin?)
---@field build? string|fun(plugin: zpack.Plugin?)
---@field enabled? boolean|(fun():boolean)
---@field cond? boolean|(fun(plugin: zpack.Plugin?):boolean)
---@field lazy? boolean
---@field priority? number Load priority for startup plugins. Higher priority loads first. Default: 50
---@field version? string|vim.VersionRange Git branch/tag/commit (string) or semver range (vim.VersionRange)
---@field sem_version? string Semver range string, auto-wrapped to vim.version.range() (lazy.nvim compat)
---@field branch? string Git branch (lazy.nvim compat). Mapped to version
---@field tag? string Git tag (lazy.nvim compat). Mapped to version
---@field commit? string Git commit (lazy.nvim compat). Mapped to version
---@field keys? zpack.KeysValue|fun(plugin: zpack.Plugin?):zpack.KeysValue
---@field config? fun(plugin: zpack.Plugin?, opts: table)|true
---@field opts? table|fun(plugin: zpack.Plugin?, opts: table):table
---@field main? string
---@field event? zpack.EventValue|fun(plugin: zpack.Plugin?):zpack.EventValue
---@field pattern? string|string[] Global fallback pattern applied to all events (unless zpack.EventSpec specifies its own)
---@field cmd? zpack.CmdValue|fun(plugin: zpack.Plugin?):zpack.CmdValue
---@field ft? zpack.FtValue|fun(plugin: zpack.Plugin?):zpack.FtValue
---@field module? boolean Auto-load when require()'d (default: true for lazy plugins)
---@field dependencies? string|string[]|zpack.Spec|zpack.Spec[] Plugin dependencies
---@field import? string Module path to import specs from (e.g., 'plugins')
---@field _import_order? number Internal: Order in which spec was imported
---@field _is_dependency? boolean Internal: Whether spec was imported as a dependency

---Plugin load lifecycle state.
---  `pending` — next trigger will start a load.
---  `loading` — process_spec body mid-flight; observed only from
---              synchronous re-entry (e.g. plugin/ files firing autocmds).
---  `loaded`  — committed after run_config succeeds; apply_keys runs after
---              this transition so a key-spec throw can't trigger a retry.
---@alias zpack.LoadStatus "pending" | "loading" | "loaded"

---@alias zpack.PluginStatus "pending" | "loading" | "loaded" | "disabled" | "installing"

---Public snapshot of a registered plugin. Returned by |zpack.get_plugins()|
---and |zpack.get_plugin()|. Consumers must treat instances as read-only.
---@class zpack.PluginInfo
---@field name string Resolved plugin name — the stable lookup key
---@field src string Git URL or local path passed to `vim.pack.add`; safe to display or pass to `vim.pack.get`
---@field status zpack.PluginStatus Current load/enablement state
---@field lazy boolean Whether the plugin is configured to lazy-load
---@field path? string Absolute plugin directory; nil while `status == "installing"`

---@class zpack.RegistryEntry
---@field specs zpack.Spec[]
---@field sorted_specs? zpack.Spec[]
---@field merged_spec? zpack.Spec
---@field has_opts? boolean Whether any spec in this entry contributes opts; authoritative existence check
---@field plugin zpack.Plugin?
---@field load_status zpack.LoadStatus
---@field enabled_result? boolean
---@field cond_result? boolean
---@field is_lazy_resolved? boolean

return {}
