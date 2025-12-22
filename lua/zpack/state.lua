local M = {}

local PRIORITY_MAX = 999999999

M.lazy_group = vim.api.nvim_create_augroup('LazyPack', { clear = true })
M.startup_group = vim.api.nvim_create_augroup('StartupPack', { clear = true })
M.lazy_build_group = vim.api.nvim_create_augroup('LazyBuildPack', { clear = true })

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
M.cached_plugin_names_with_build = nil
---@type { spec: vim.pack.Spec, priority: number }[]|nil
M.sorted_plugins = nil

M.build_sorted_plugins = function()
  local installed = vim.pack.get()
  local plugins = {}

  for _, pack in ipairs(installed) do
    local entry = M.src_spec[pack.spec.src]
    local priority = entry and (entry.spec.priority or 50) or PRIORITY_MAX
    table.insert(plugins, {
      spec = pack.spec,
      priority = priority,
    })
  end

  table.sort(plugins, function(a, b)
    return a.priority > b.priority
  end)

  M.sorted_plugins = plugins
end

---@return { spec: vim.pack.Spec, priority: number }[]
M.get_sorted_plugins = function()
  if not M.sorted_plugins then
    M.build_sorted_plugins()
  end
  return M.sorted_plugins
end

---@return vim.pack.Spec[]
M.get_installed_plugins = function()
  local specs = {}
  for _, plugin in ipairs(M.get_sorted_plugins()) do
    table.insert(specs, plugin.spec)
  end
  return specs
end

---@return string[]
M.get_installed_plugin_names = function()
  local names = {}
  for _, plugin in ipairs(M.get_sorted_plugins()) do
    table.insert(names, plugin.spec.name)
  end
  return names
end

M.get_plugin_names_with_build_hooks = function()
  return M.cached_plugin_names_with_build or {}
end

---@param refresh? boolean
M.update_cache = function(refresh)
  vim.schedule(function()
    if refresh then
      M.sorted_plugins = nil
    end

    local names_with_build = {}

    for _, plugin in ipairs(M.get_sorted_plugins()) do
      local src_spec_entry = M.src_spec[plugin.spec.src]
      if src_spec_entry and src_spec_entry.spec.build then
        table.insert(names_with_build, plugin.spec.name)
      end
    end

    M.cached_plugin_names_with_build = names_with_build
  end)
end

return M
