local M = {}

---@type boolean
M.is_setup = false

---The fully merged config from the last successful `setup()`. Populated for
---introspection (e.g. |zpack.health|); nil until `setup()` completes.
---@type zpack.Config?
M.config = nil

---Names of deprecated/removed `setup()` options the user passed, recorded so
---`:checkhealth zpack` can report them.
---@type string[]
M.deprecations = {}

M.lazy_group = vim.api.nvim_create_augroup('LazyPack', { clear = true })
M.startup_group = vim.api.nvim_create_augroup('StartupPack', { clear = true })
M.lazy_build_group = vim.api.nvim_create_augroup('LazyBuildPack', { clear = true })
M.delete_group = vim.api.nvim_create_augroup('DeletePack', { clear = true })

---@type { [string]: zpack.RegistryEntry }
M.spec_registry = {}

---@type number
M.import_order = 0

---@type { [string]: { [string]: true } }
M.dependency_graph = {}

---@type { [string]: { [string]: true } }
M.reverse_dependency_graph = {}

---@type { [string]: vim.pack.Spec }
M.src_to_pack_spec = {}

---@type { [string]: string }
M.name_to_src = {}

---@type { [string]: boolean }
M.lazy_parent_cache = {}

---@type { [string]: boolean }
M.resolve_main_not_found = {}

---@type { [string]: boolean }
M.src_with_pending_build = {}

---@type vim.pack.Spec[]
M.registered_plugins = {}
---@type string[] -- kept sorted for tab completion
M.registered_plugin_names = { 'zpack.nvim' }

---@type string[]
M.plugin_names_with_build = {}
---@type { [string]: boolean }
M.unloaded_plugin_names = {}

M.remove_plugin = function(plugin_name, src)
  M.spec_registry[src] = nil
  M.src_with_pending_build[src] = nil
  M.src_to_pack_spec[src] = nil
  M.name_to_src[plugin_name] = nil
  M.lazy_parent_cache[src] = nil
  M.resolve_main_not_found[src] = nil

  M.dependency_graph[src] = nil
  M.reverse_dependency_graph[src] = nil
  for _, deps in pairs(M.dependency_graph) do
    deps[src] = nil
  end
  for _, rdeps in pairs(M.reverse_dependency_graph) do
    rdeps[src] = nil
  end

  M.registered_plugins = vim.tbl_filter(function(spec)
    return spec.name ~= plugin_name
  end, M.registered_plugins)

  M.registered_plugin_names = vim.tbl_filter(function(name)
    return name ~= plugin_name
  end, M.registered_plugin_names)

  M.plugin_names_with_build = vim.tbl_filter(function(name)
    return name ~= plugin_name
  end, M.plugin_names_with_build)

  M.unloaded_plugin_names[plugin_name] = nil
end

return M
