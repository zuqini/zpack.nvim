local M = {}

M.lazy_group = vim.api.nvim_create_augroup('LazyPack', { clear = true })
M.startup_group = vim.api.nvim_create_augroup('StartupPack', { clear = true })
M.lazy_build_group = vim.api.nvim_create_augroup('LazyBuildPack', { clear = true })

---@type { [string]: { spec: Spec, loaded: boolean } }
M.spec_registry = {}
---@type { [string]: boolean }
M.src_with_pending_build = {}

---@type vim.pack.Spec[]
M.registered_plugins = {}
---@type string[]
M.registered_plugin_names = { 'zpack.nvim' }
---@type string[]
M.plugin_names_with_build = {}

return M
