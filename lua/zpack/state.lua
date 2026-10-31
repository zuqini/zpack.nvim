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

---@type number
M.import_order = 0

---Where each imported spec table was declared: at the top level, or in a
---parent spec's `dependencies` (true) or `specs` (false). merge.lua drops a
---declared spec with its last parent, builds dependency_graph from these and
---then clears them.
---@type { [zpack.Spec]: true }
M.top_specs = {}

---@type { [zpack.Spec]: { [zpack.Spec]: true } }
M.spec_parents = {}

---@type { [zpack.Spec]: { [zpack.Spec]: boolean } }
M.spec_children = {}

---The src of the registry entry holding each imported spec.
---@type { [zpack.Spec]: string }
M.spec_src = {}

---Each spec's `enabled`, so a spec that is both a plugin and an import gets one
---answer from a function-form `enabled`.
---@type { [zpack.Spec]: boolean }
M.enabled_results = {}

---Specs already validated: a spec can be walked once per parent listing it.
---@type { [any]: true }
M.validated_specs = {}

---Which field gave each spec its source. A `reference` is a `[1]` without an
---owner, which names a plugin but no repo (lazy.nvim parity).
---@type { [zpack.Spec]: 'dev'|'explicit'|'repo'|'reference' }
M.source_kinds = {}

---Plugins whose version is a semver range written as a string, as in lazy.nvim,
---rather than a vim.VersionRange: with no tag to fit, they use the default branch.
---@type { [string]: true }
M.soft_versions = {}

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

---@type vim.pack.Spec[]
M.registered_plugins = {}
---@type string[] -- kept sorted for tab completion
M.registered_plugin_names = { 'zpack.nvim' }

---@type string[]
M.plugin_names_with_build = {}
---@type { [string]: boolean }
M.unloaded_plugin_names = {}

---The proxy commands of each lazy plugin, by source.
---@type { [string]: string[] }
M.cmd_proxies = {}
---The sources still waiting on each live proxy command.
---@type { [string]: { [string]: true } }
M.live_cmd_proxies = {}
M.CMD_PROXY_DESC = 'zpack: load the plugin that provides this command'

---@param cmd string
M.drop_cmd_proxy = function(cmd)
  if M.live_cmd_proxies[cmd] then
    M.live_cmd_proxies[cmd] = nil
    pcall(vim.api.nvim_del_user_command, cmd)
  end
end

---Drop the proxies only `src` still waits on. Another pending plugin keeps its
---trigger, and a real command that replaced the proxy stays.
---@param src string
M.drop_cmd_proxies = function(src)
  for _, cmd in ipairs(M.cmd_proxies[src] or {}) do
    local claimants = M.live_cmd_proxies[cmd]
    if claimants then
      claimants[src] = nil
      if next(claimants) == nil then
        local info = vim.api.nvim_get_commands({})[cmd]
        -- v0.12.0 reports a desc as `definition`.
        if info and (info.desc or info.definition) == M.CMD_PROXY_DESC then
          M.drop_cmd_proxy(cmd)
        else
          M.live_cmd_proxies[cmd] = nil
        end
      end
    end
  end
end

---Forget a trial resolve, to import the specs again. `validated_specs` and
---`enabled_results` stay, since a spec's warnings and `enabled` come once.
M.reset_specs = function()
  M.spec_registry = {}
  M.import_order = 0
  M.top_specs, M.spec_parents, M.spec_children, M.spec_src, M.source_kinds = {}, {}, {}, {}, {}
  M.dependency_graph, M.dependency_order, M.reverse_dependency_graph = {}, {}, {}
  M.src_to_pack_spec, M.name_to_src, M.lazy_parent_cache = {}, {}, {}
  M.soft_versions = {}
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
