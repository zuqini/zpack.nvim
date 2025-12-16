---@class KeySpec
---@field [1] string
---@field [2]? fun()
---@field remap? boolean
---@field desc? string
---@field mode? string|string[]
---@field nowait? boolean

---@class Spec
---@field [1]? string Plugin short name (e.g., "user/repo"). Required if src is not provided
---@field src? string Custom git URL. Required if [1] is not provided
---@field name? string Custom plugin name. Overrides auto-derived name from URL
---@field init? fun()
---@field build? string|fun()
---@field enabled? boolean|(fun():boolean)
---@field cond? boolean|(fun():boolean)
---@field lazy? boolean
---@field priority? number Load priority for startup plugins. Higher priority loads first. Default: 50
---@field version? string
---@field keys? KeySpec|KeySpec[]
---@field config? fun()
---@field event? string|string[]
---@field pattern? string|string[]
---@field cmd? string|string[]

return {}
