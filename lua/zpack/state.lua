if jit then jit.off(true, true) end

local M = {}

---@type boolean
M.is_setup = false

---The fully merged config from the last successful `setup()`. Populated for
---introspection (e.g. |zpack.health|); nil until `setup()` completes.
---@type zpack.Config?
M.config = nil

M.lazy_group = vim.api.nvim_create_augroup('LazyPack', { clear = true })
M.startup_group = vim.api.nvim_create_augroup('StartupPack', { clear = true })
M.lazy_build_group = vim.api.nvim_create_augroup('LazyBuildPack', { clear = true })
M.delete_group = vim.api.nvim_create_augroup('DeletePack', { clear = true })

---@type { [string]: zpack.RegistryEntry }
M.spec_registry = {}

---@type { [string]: { [string]: true } }
M.dependency_graph = {}

---Where each plugin lists each dependency, as an import order.
---@type { [string]: { [string]: integer } }
M.dependency_order = {}

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

---Forget a trial resolve, to import the specs again.
M.reset_specs = function()
  M.spec_registry = {}
  M.dependency_graph, M.dependency_order, M.reverse_dependency_graph = {}, {}, {}
  M.src_to_pack_spec, M.name_to_src, M.lazy_parent_cache = {}, {}, {}
end

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
end

return M
