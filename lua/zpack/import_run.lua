if jit then jit.off(true, true) end

local import = require('zpack.import')
local pack = require('zpack.pack')
local state = require('zpack.state')
local utils = require('zpack.utils')

local M = {}

---Where a pass found its specs, for merge.resolve_all.
---@class zpack.SpecGraph
---@field top_specs { [zpack.Spec]: true } Specs declared at the top level
---@field spec_parents { [zpack.Spec]: { [zpack.Spec]: true } } Specs declared under a parent's `dependencies` or `specs`
---@field spec_children { [zpack.Spec]: { [zpack.Spec]: boolean } } The reverse: true for `dependencies`, false for `specs`
---@field spec_src { [zpack.Spec]: string } The src of the registry entry holding each spec
---@field source_kinds { [zpack.Spec]: 'dev'|'explicit'|'repo'|'reference' } Which field gave each spec its source. A `reference` is a `[1]` without an owner, which names a plugin but no repo (lazy.nvim parity)

---@return zpack.SpecGraph
local function new_graph()
  return {
    top_specs = {},
    spec_parents = {},
    spec_children = {},
    spec_src = {},
    source_kinds = {},
  }
end

---Install plugins an import needs modules from, with the specs a trial resolve gave.
---@param packs vim.pack.Spec[]
---@param run zpack.ImportRun
---@param on_load? fun(plugin: zpack.Plugin)
local install = function(packs, run, on_load)
  local err = pack.add(packs, {
    confirm = run.confirm,
    load = function(plugin)
      run.early_plugins[plugin.spec.name] = plugin
      if on_load then
        on_load(plugin)
      end
    end,
  })
  if err then
    utils.schedule_notify(('zpack: could not install a plugin for its import: %s'):format(err), vim.log.levels.ERROR)
  end
end

---Install each plugin whose module was missing that the trial resolve keeps, under
---the name, source and version it gives. vim.pack keeps the first spec it gets, so
---that's the merged one. Each is tried once per run.
---@param run zpack.ImportRun
local install_kept_owners = function(run)
  local to_add = {}
  for src, entry in pairs(state.spec_registry) do
    local stays = false
    for _, spec in ipairs(entry.specs) do
      if run.missing_owners[spec] then
        run.tried_owners[spec] = true
        stays = true
      end
    end
    if stays then
      local pack_spec = state.src_to_pack_spec[src]
      local dir = pack.plugin_dir(pack_spec.name)
      if vim.uv.fs_stat(dir) then
        import.add_import_path(dir, run)
      else
        to_add[#to_add + 1] = { src = src, name = pack_spec.name, version = pack_spec.version }
      end
    end
  end
  if #to_add > 0 then
    install(to_add, run, function(plugin)
      import.add_import_path(plugin.path, run)
    end)
  end
end

---Look for imports with no plugin of their own in the plugins that stay whose name or
---repository is named after the module's top level, installing those that are
---missing, unless already tried as an owner: the first listed that has it.
---@param listed vim.pack.Spec[] What the trial resolve keeps
---@param run zpack.ImportRun
local search_named_plugins = function(listed, run)
  local tops = {}
  for _, module in ipairs(run.unowned_misses) do
    tops[utils.normalize_name(module:match('^[^.]*'))] = true
  end
  local named = vim.tbl_filter(function(pack_spec)
    return tops[utils.normalize_name(pack_spec.name)] or tops[utils.normalize_name(pack.derive_name_from_src(pack_spec.src))]
  end, listed)
  table.sort(named, function(a, b)
    return utils.get_import_order(a.src) < utils.get_import_order(b.src)
  end)
  local to_add = vim.tbl_filter(function(pack_spec)
    local tried = vim.iter(state.spec_registry[pack_spec.src].specs):any(function(spec)
      return run.tried_owners[spec]
    end)
    return not tried and not vim.uv.fs_stat(pack.plugin_dir(pack_spec.name))
  end, named)
  if #to_add > 0 then
    install(to_add, run)
  end
  for _, module in ipairs(run.unowned_misses) do
    for _, pack_spec in ipairs(named) do
      local dir = pack.plugin_dir(pack_spec.name)
      if import.module_in(dir, module) then
        import.add_import_path(dir, run)
        break
      end
    end
  end
end

---Put more within reach of the imports that missed, from a trial resolve of the specs
---so far: the plugins they belong to, or failing that the plugins named after them.
---The resolve is a trial run, so the caller starts the import over.
---@param run zpack.ImportRun
---@return boolean found Whether anything new is in reach
local settle = function(run)
  local known_paths = #run.import_paths
  local listed = require('zpack.merge').resolve_all(run.graph, run.enabled_results, function() end)
  install_kept_owners(run)
  if #run.import_paths == known_paths and #run.unowned_misses > 0 then
    search_named_plugins(listed, run)
  end
  return #run.import_paths > known_paths
end

---What merge, registration and init read of an import.
---@class zpack.Imported
---@field graph zpack.SpecGraph Where the last pass found its specs
---@field enabled_results table<zpack.Spec, boolean> Each spec's `enabled`, across passes and for merge, so a function-form `enabled` runs once
---@field early_plugins table<string, zpack.Plugin> Plugins added while importing their specs, by name, until registered
---@field import_paths string[] Plugins put on package.path for an import, to take off after startup

---One setup()'s import, across its passes.
---@class zpack.ImportRun : zpack.Imported
---@field confirm boolean?
---@field implicit_module? string The module imported because setup() was given no spec, which may well not exist
---@field validated_specs table<any, true> Specs already validated, across passes: a spec can be walked once per parent listing it
---@field imported_functions table<function, { specs: table?, failure: string?, failure_level: integer? }> Per-setup() record of function-form `import`
---@field missing_owners table<zpack.Spec, true> Specs importing from a plugin that isn't installed, this pass
---@field tried_owners table<zpack.Spec, true> Those a trial resolve kept, so installed or asked to be, once per run
---@field missed_import? boolean An import found no module, this pass
---@field unowned_misses string[] Modules of imports with no plugin of their own that found none, this pass
---@field notes { msg: string, level: integer }[] What the last pass has to report
---@field next_import_order integer This pass's
---@field imported_modules { [string]: { [zpack.Spec|table]: 'walked'|'missed' } } For each import path, how each listing of it went, this pass
---@field function_parents { [function]: { [zpack.Spec|table]: true } } For each import function, the listings its specs were imported under, this pass

---Import every spec, installing any plugin an import needs modules from.
---lazy.nvim parity: it too installs what's missing and reads the specs again.
---An import that comes before the spec of the plugin that has its module finds it
---on a second pass, as it would on a first install. Each pass but the last adds a
---path, so this ends.
---@param spec_item_or_list? string|zpack.Spec|zpack.Spec[] Default: the module `plugins`
---@param opts { confirm: boolean? }
---@return zpack.Imported
M.import_all = function(spec_item_or_list, opts)
  local implicit_module = spec_item_or_list == nil and 'plugins' or nil
  spec_item_or_list = spec_item_or_list or { import = implicit_module }
  local run = {
    confirm = opts.confirm,
    implicit_module = implicit_module,
    validated_specs = {},
    enabled_results = {},
    imported_functions = {},
    early_plugins = {},
    import_paths = {},
    tried_owners = {},
  }
  local last = false
  while true do
    local known_paths = #run.import_paths
    run.notes, run.missing_owners, run.missed_import, run.unowned_misses = {}, {}, false, {}
    run.next_import_order, run.imported_modules, run.function_parents = 0, {}, {}
    run.graph = new_graph()
    import.import_specs(spec_item_or_list, run)
    local found_more = run.missed_import and #run.import_paths > known_paths
    if last or not (found_more or next(run.missing_owners) or #run.unowned_misses > 0) then
      break
    end
    last = not found_more and not settle(run)
    state.reset_specs()
  end
  for _, note in ipairs(run.notes) do
    utils.schedule_notify(note.msg, note.level)
  end
  return {
    graph = run.graph,
    enabled_results = run.enabled_results,
    early_plugins = run.early_plugins,
    import_paths = run.import_paths,
  }
end

return M
