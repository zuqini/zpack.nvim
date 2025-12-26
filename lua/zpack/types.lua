---@class zpack.KeySpec
---@field [1] string
---@field [2]? string|fun()
---@field remap? boolean
---@field desc? string
---@field mode? string|string[]
---@field nowait? boolean

---@class zpack.EventSpec
---@field event string|string[] Event name(s) to trigger on
---@field pattern? string|string[] Pattern(s) for the event

---Normalized event with pattern
---@class zpack.NormalizedEvent
---@field events string[] List of event names
---@field pattern string|string[] Pattern(s) for these events

---@class zpack.Spec
---@field [1]? string Plugin short name (e.g., "user/repo"). Required if src/dir/url not provided
---@field src? string Custom git URL or local path. Required if [1]/dir/url not provided
---@field dir? string Local plugin directory path (lazy.nvim compat). Mapped to src
---@field url? string Custom git URL (lazy.nvim compat). Mapped to src
---@field name? string Custom plugin name. Overrides auto-derived name from URL
---@field init? fun()
---@field build? string|fun()
---@field enabled? boolean|(fun():boolean)
---@field cond? boolean|(fun():boolean)
---@field lazy? boolean
---@field priority? number Load priority for startup plugins. Higher priority loads first. Default: 50
---@field version? string|vim.VersionRange Git branch/tag/commit (string) or semver range (vim.VersionRange)
---@field keys? string|string[]|zpack.KeySpec|zpack.KeySpec[]
---@field config? fun()
---@field event? string|string[]|zpack.EventSpec|(string|zpack.EventSpec)[]
---@field pattern? string|string[] Global fallback pattern applied to all events (unless zpack.EventSpec specifies its own)
---@field cmd? string|string[]
---@field ft? string|string[]

return {}
