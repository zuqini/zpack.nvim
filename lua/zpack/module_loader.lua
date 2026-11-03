if jit then jit.off(true, true) end

local state = require('zpack.state')
local util = require('zpack.utils')

local M = {}

---@type { [string]: string|false }
local module_lookup_cache = {}

---@type vim.pack.Spec[]
local lazy_pack_specs = {}

---@param path string A plugin's directory
---@param modname string
---@return string? file
local function module_file(path, modname)
  local base = path .. "/lua/" .. modname:gsub("%.", "/")
  for _, suffix in ipairs({ ".lua", "/init.lua", ".so", ".dll" }) do
    if vim.uv.fs_stat(base .. suffix) then
      return base .. suffix
    end
  end
end

---@param path string A plugin's directory
---@param topmod string
---@return boolean
local function claims_topmod(path, topmod)
  for _, entry in ipairs(util.lsdir(path .. "/lua")) do
    if util.top_module(entry) == topmod or entry.name == topmod .. ".so" or entry.name == topmod .. ".dll" then
      return true
    end
  end
  return false
end

---Find the pending plugin to load for a module: of the claimants of the top-level name
---holding its file, the one named like that name as in lazy.nvim, else the first.
---Once the first is found, only plugins named like it are scanned.
---@param modname string
---@return string? src plugin source if found
local function find_src_by_scanning(modname)
  local topmod = modname:match("^[^.]*")
  local norm = util.normalize_name(topmod)
  local first

  for _, pack_spec in ipairs(lazy_pack_specs) do
    local src = pack_spec.src
    local registry_entry = state.spec_registry[src]
    local plugin = registry_entry and registry_entry.plugin
    if plugin and registry_entry.load_status == "pending" and registry_entry.merged_spec.module ~= false then
      local named = util.normalize_name(plugin.spec.name) == norm
      if (named or not first) and claims_topmod(plugin.path, topmod) and module_file(plugin.path, modname) then
        if named then
          return src
        end
        first = src
      end
    end
  end
  return first
end

---Initialize module loader with lazy plugins
---@param lazy_packs vim.pack.Spec[]
function M.initialize_cache(lazy_packs)
  module_lookup_cache = {}
  lazy_pack_specs = lazy_packs
end

function M.reset_lookup_cache()
  module_lookup_cache = {}
end

---Find plugin source by scanning filesystem for the module
---@param modname string
---@return string? src
local function find_src_for_module(modname)
  local cached = module_lookup_cache[modname]
  if cached ~= nil then
    return cached or nil
  end

  local src = find_src_by_scanning(modname)
  module_lookup_cache[modname] = src or false
  return src
end

---The plugin's own copy, though a dependency now on 'runtimepath' may hold one too.
---@param path string
---@param modname string
---@return function|string|nil
local function load_from_plugin(path, modname)
  local file = module_file(path, modname)
  if not file then
    return nil
  end
  if file:sub(-4) == ".lua" then
    local chunk, err = loadfile(file)
    return chunk or err
  end
  -- Named as Lua 5.1's C searcher names it. Without vim.loader, no searcher after this one has 'runtimepath'.
  local open, err = package.loadlib(file, "luaopen_" .. modname:gsub("^.-%-", ""):gsub("%.", "_"))
  return open or err
end

---Custom loader that triggers packadd for lazy plugins
---@param modname string
---@return function|string|nil
function M.loader(modname)
  modname = modname:gsub("/", "."):gsub("^%.+", "")
  local src = find_src_for_module(modname)
  if not src then
    return nil
  end

  local registry_entry = state.spec_registry[src]
  if not registry_entry or registry_entry.load_status ~= "pending" then
    return nil
  end

  local pack_spec = state.src_to_pack_spec[src]
  if not pack_spec then
    return nil
  end

  require('zpack.plugin_loader').process_spec(pack_spec, { bang = true })

  local mod = package.loaded[modname]
  if mod ~= nil then
    return function()
      return mod
    end
  end

  return load_from_plugin(registry_entry.plugin.path, modname)
end

function M.install()
  table.insert(package.loaders, 3, M.loader)
end

return M
