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

---Plugin data passed to load callback from vim.pack.add and forwarded to
---spec hooks (init/config/opts/cond/build/deactivate). zpack's own fields are
---`spec`, `path`, and the late-resolved `main`; lazy.nvim parity adds
---`name` (alias for spec.name), `dir` (alias for path), and `dependencies`
---(sorted list of resolved dependency names from this plugin's outgoing
---deps in the resolved spec tree).
---@class zpack.Plugin
---@field spec vim.pack.Spec
---@field path string
---@field name? string Resolved plugin name (alias for spec.name; lazy.nvim parity)
---@field dir? string Plugin directory (alias for path; lazy.nvim parity)
---@field dependencies? string[] Sorted list of dependency names (lazy.nvim parity)
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
---@field build? false|string|(string|fun(plugin: zpack.Plugin?))[]|fun(plugin: zpack.Plugin?)
---@field enabled? boolean|(fun():boolean)
---@field cond? boolean|(fun(plugin: zpack.Plugin?):boolean)
---@field lazy? boolean
---@field priority? number Load priority for startup plugins. Higher priority loads first. Default: 50
---@field version? string|vim.VersionRange|false Git branch/tag/commit (string), semver range (vim.VersionRange), or `false` to opt out of versioning (lazy.nvim parity)
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
---@field specs? zpack.Spec|zpack.Spec[] Companion plugin specs grouped with this one (lazy.nvim parity)
---@field pin? boolean Exclude from :ZPack update bulk runs (lazy.nvim parity)
---@field optional? boolean Only install if also referenced non-optionally (lazy.nvim parity)
---@field dev? boolean Use local checkout under `dev.path` (lazy.nvim parity)
---@field deactivate? fun(plugin: zpack.Plugin?) Teardown hook invoked by :ZPack reload (lazy.nvim parity)
---@field import? string|fun():zpack.Spec[] Module path string or function returning specs (lazy.nvim parity)
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
