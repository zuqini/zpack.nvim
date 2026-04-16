local utils = require('zpack.utils')
local state = require('zpack.state')

local M = {}

local imported_modules = {}

---Normalize plugin source using priority: [1] > src > url > dir
---When dev=true, resolve to the local dev path instead of fetching from remote
---@param spec zpack.Spec
---@return string|nil source URL/path, or nil if invalid
---@return string|nil error message if validation fails
local normalize_source = function(spec)
  if spec.dev then
    local plugin_name = spec.name
    if not plugin_name then
      if spec[1] then
        plugin_name = spec[1]:match('([^/]+)$') or spec[1]
      else
        return nil, "dev = true requires [1] or name to derive the plugin directory"
      end
    end
    local dev_plugin_path = state.dev_path .. '/' .. plugin_name
    if not vim.uv.fs_stat(dev_plugin_path) then
      return nil, ("Dev mode: plugin '%s' not found in '%s'"):format(plugin_name, state.dev_path)
    end
    return dev_plugin_path
  end
  if spec[1] then
    return 'https://github.com/' .. spec[1]
  elseif spec.src then
    return spec.src
  elseif spec.url then
    return spec.url
  elseif spec.dir then
    return vim.fn.expand(spec.dir)
  else
    return nil, "spec must provide one of: [1], src, dir, or url"
  end
end

---@param spec zpack.Spec
---@return string|nil
local get_source_url = function(spec)
  local src, err = normalize_source(spec)
  if not src then
    utils.schedule_notify(err, vim.log.levels.ERROR)
  end
  return src
end

---Check if a table has any non-integer keys
---@param tbl table
---@return boolean
local has_non_integer_keys = function(tbl)
  for k in pairs(tbl) do
    if type(k) ~= "number" then
      return true
    end
  end
  return false
end

---Check if value is a single spec (not a list of specs)
---A single spec has a source identifier ([1]=string, src, dir, url) and may have
---spec fields (opts, config, etc). A list of specs has tables or strings as elements.
---@param value zpack.Spec|zpack.Spec[]
---@return boolean
local is_single_spec = function(value)
  if value.src ~= nil or value.dir ~= nil or value.url ~= nil or value.import ~= nil then
    return true
  end
  if type(value[1]) == "string" then
    return value[2] == nil or has_non_integer_keys(value)
  end
  return false
end

---Check if spec is an import spec
---@param spec zpack.Spec
---@return boolean
local is_import_spec = function(spec)
  return spec.import ~= nil
end

---Normalize dependencies to spec array
---@param deps string|string[]|zpack.Spec|zpack.Spec[]
---@param parent_src string
---@return zpack.Spec[]
local normalize_dependencies = function(deps, parent_src)
  if type(deps) == "string" then
    return { { deps } }
  end
  if type(deps) ~= "table" then
    utils.schedule_notify(
      ("Invalid dependencies for %s: expected string or table, got %s"):format(parent_src, type(deps)),
      vim.log.levels.WARN
    )
    return {}
  end
  if is_single_spec(deps) then
    return { deps }
  end
  if type(deps[1]) == "string" then
    local result = {}
    for i, dep in ipairs(deps) do
      if type(dep) == "string" then
        table.insert(result, { dep })
      elseif type(dep) == "table" then
        table.insert(result, dep)
      else
        utils.schedule_notify(
          ("Invalid dependency at index %d for %s: expected string or table, got %s"):format(i, parent_src, type(dep)),
          vim.log.levels.WARN
        )
      end
    end
    return result
  end
  return deps
end

---Load a spec module and import its specs
---@param full_module string Full module path (e.g., 'plugins.telescope')
---@param ctx zpack.ProcessContext
local load_spec_module = function(full_module, ctx)
  local success, spec_item_or_list = pcall(require, full_module)

  if not success then
    utils.schedule_notify(
      ("Failed to load plugin spec from %s: %s"):format(full_module, spec_item_or_list),
      vim.log.levels.ERROR
    )
  elseif type(spec_item_or_list) ~= "table" then
    utils.schedule_notify(
      ("Invalid spec from %s, not a table: %s"):format(full_module, spec_item_or_list),
      vim.log.levels.ERROR
    )
  else
    M.import_specs(spec_item_or_list, ctx)
  end
end

---Import specs from a module directory
---@param module_path string Module path (e.g., 'plugins' imports from lua/plugins/*.lua)
---@param ctx zpack.ProcessContext
local import_from_module = function(module_path, ctx)
  if imported_modules[module_path] then
    return
  end
  imported_modules[module_path] = true

  local lua_path = vim.fn.stdpath('config') .. '/lua/' .. module_path:gsub('%.', '/')

  for _, entry in ipairs(utils.lsdir(lua_path)) do
    if entry.name:sub(-4) == ".lua" then
      local plugin_name = entry.name:sub(1, -5)
      load_spec_module(module_path .. "." .. plugin_name, ctx)
    elseif entry.type == "directory" or entry.type == "link" then
      local init_path = lua_path .. "/" .. entry.name .. "/init.lua"
      if vim.uv.fs_stat(init_path) then
        load_spec_module(module_path .. "." .. entry.name, ctx)
      end
    end
  end
end

---@param spec_item_or_list zpack.Spec|zpack.Spec[]
---@param ctx zpack.ProcessContext
M.import_specs = function(spec_item_or_list, ctx)
  local specs = is_single_spec(spec_item_or_list)
      and { spec_item_or_list }
      or spec_item_or_list --[[@as zpack.Spec[] ]]

  for _, spec in ipairs(specs) do
    if is_import_spec(spec) then
      if spec.enabled == false or (type(spec.enabled) == "function" and not spec.enabled()) then
        goto continue
      end
      import_from_module(spec.import, ctx)
      goto continue
    end

    local src = get_source_url(spec)
    if not src then goto continue end
    local is_dep = ctx.is_dependency or false

    spec._import_order = state.import_order
    state.import_order = state.import_order + 1
    spec._is_dependency = is_dep

    if state.spec_registry[src] then
      table.insert(state.spec_registry[src].specs, spec)
    else
      state.spec_registry[src] = { specs = { spec }, load_status = "pending" }
    end

    -- Walk dependencies unconditionally. `enabled` is evaluated post-merge
    -- in resolve_all; gating the dep walk on the raw pre-merge spec would
    -- call function-form `enabled` eagerly at import time and diverge from
    -- the merged truth. prune_disabled_subtrees handles cleanup afterward.
    if spec.dependencies then
      local dep_specs = normalize_dependencies(spec.dependencies, src)
      state.dependency_graph[src] = state.dependency_graph[src] or {}
      local dep_ctx = vim.tbl_extend('force', ctx, { is_dependency = true })
      for _, dep_spec in ipairs(dep_specs) do
        local dep_src, err = normalize_source(dep_spec)
        if not dep_src then
          if err then
            utils.schedule_notify(("Invalid dependency for %s: %s"):format(src, err), vim.log.levels.WARN)
          end
          goto skip_dep
        end
        if not state.dependency_graph[src][dep_src] then
          state.dependency_graph[src][dep_src] = true
          state.reverse_dependency_graph[dep_src] = state.reverse_dependency_graph[dep_src] or {}
          state.reverse_dependency_graph[dep_src][src] = true
        end
        M.import_specs(dep_spec, dep_ctx)
        ::skip_dep::
      end
    end

    ::continue::
  end
end

M.reset_imported_modules = function()
  imported_modules = {}
end

return M
