local M = {}

M.lazy_group = vim.api.nvim_create_augroup('LazyPack', { clear = true })
M.startup_group = vim.api.nvim_create_augroup('StartupPack', { clear = true })

---@type vim.pack.Spec[]
M.startup_packs = {}
---@type vim.pack.Spec[]
M.lazy_packs = {}
---@type KeySpec[]
M.startup_keys = {}
---@type { [string]: { spec: Spec, loaded: boolean } }
M.src_spec = {}
---@type { [string]: boolean }
M.src_to_request_build = {}
---@type string[]
M.src_with_startup_init = {}
---@type string[]
M.src_with_startup_config = {}

---@type string[]|nil
M.cached_plugin_names = nil
---@type string[]|nil
M.cached_plugin_names_with_build = nil

M.update_cache = function()
  vim.schedule(function()
    local installed = vim.pack.get()
    local all_names = {}
    local names_with_build = {}

    for _, pack in ipairs(installed) do
      table.insert(all_names, pack.spec.name)
      local src_spec_entry = M.src_spec[pack.spec.src]
      if src_spec_entry and src_spec_entry.spec.build then
        table.insert(names_with_build, pack.spec.name)
      end
    end

    M.cached_plugin_names = all_names
    M.cached_plugin_names_with_build = names_with_build
  end)
end

return M
