if jit then jit.off(true, true) end

local utils = require('zpack.utils')
local pack = require('zpack.pack')
local state = require('zpack.state')
local validate = require('zpack.validate')

local M = {}

local TOP_LEVEL = {}

---Resolve `spec.dev == true` to a local path under `config.dev.path`. Returns
---nil when dev is not requested or when no name source can be derived. When
---the resolved dev path exists, it is used; when missing and `dev.fallback`
---is true, returns nil so the caller falls through to the regular source.
---@param spec zpack.Spec
---@return string|nil dev_path
local function resolve_dev_path(spec)
  if spec.dev ~= true then
    return nil
  end
  local dev_config = state.config.dev or {}
  -- Strip trailing slash so registry keys do not drift between sessions
  -- with vs. without the trailing slash on `dev.path`.
  local dev_base = vim.fn.expand(dev_config.path or '~/projects'):gsub('/+$', '')
  -- `spec.name` first: lazy.nvim parity for overriding the derived dir.
  -- This chain derives the checkout NAME ([1] before src, unlike
  -- normalize_source's src-first source precedence): a fork url still
  -- checks out under the upstream short name.
  local source_for_name = spec.name or spec[1] or spec.src or spec.url or spec.dir
  if type(source_for_name) ~= 'string' then
    utils.schedule_notify(
      ('dev = true on spec "%s" requires a source field (name/[1]/src/url/dir) to derive the local checkout name')
        :format(validate.spec_label(spec)),
      vim.log.levels.ERROR
    )
    return nil
  end
  local derived = pack.derive_name_from_src(source_for_name)
  if derived == '' then
    return nil
  end
  local dev_path = dev_base .. '/' .. derived
  local stat = vim.uv.fs_stat(dev_path)
  if stat and stat.type == 'directory' then
    return dev_path
  end
  -- Missing or non-directory local checkout: `fallback = true` lets the
  -- caller try the regular source; otherwise we still return the dev path
  -- so vim.pack's error message points the user at the bad local checkout.
  if dev_config.fallback == true then
    return nil
  end
  return dev_path
end

---Normalize plugin source using priority: dev > src > url > dir > [1]
---lazy.nvim parity: `[1]` is only a fallback for deriving the URL, so an
---explicit src/url/dir wins — `{ 'user/repo', url = fork }` installs the fork.
---validate_spec's local-path advisory in validate.lua mirrors the "`[1]` is the
---source" condition; update both together.
---@param spec zpack.Spec
---@return string|nil source URL/path, or nil if the spec has none
---@return 'dev'|'explicit'|'repo'|'reference'|nil kind
local normalize_source = function(spec)
  -- lazy.nvim spec parity: `dev = true` rewrites the source to a local
  -- checkout under `config.dev.path` (default '~/projects'). When the local
  -- directory is missing and `fallback = true` is set, resolution falls
  -- through to the regular src/url/dir/[1] chain below.
  local dev_path = resolve_dev_path(spec)
  if dev_path then
    return dev_path, 'dev'
  end
  -- Each source field must be a string; a non-string (over-nested spec or
  -- typo) would crash the `[1]` or `dir` expansion. Skip rather than
  -- abort setup().
  if type(spec.src) == 'string' then
    return spec.src, 'explicit'
  elseif type(spec.url) == 'string' then
    return spec.url, 'explicit'
  elseif type(spec.dir) == 'string' then
    return vim.fn.expand(spec.dir), 'explicit'
  elseif type(spec[1]) == 'string' then
    local short = spec[1] --[[@as string]]
    local has_owner = short:find('/', 1, true) or short:match('^[%w_.-]+@[^/]+:')
    return pack.expand_src(short), has_owner and 'repo' or 'reference'
  elseif spec.dev == true and type(spec.name) == 'string' then
    -- Only reachable under dev.fallback with no checkout.
    return pack.expand_src(spec.name), 'reference'
  end
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
---A single spec has a source identifier ([1]=string, src, dir, url, or a name
---with `dev = true`) and may have spec fields (opts, config, etc). A list of
---specs has tables or strings as elements. A table of fields alone is a spec with
---no source, for validate_spec to report, and so is one whose first entry is a
---string past a hole: the fields say one spec was meant, and [1] is gone.
---@param value zpack.Spec|zpack.Spec[]
---@return boolean
local is_single_spec = function(value)
  if validate.has_source_field(value) then
    return true
  end
  local last = table.maxn(value)
  if type(validate.declared_entry(value, 1)) == "string" then
    return last == 1 or has_non_integer_keys(value)
  end
  return last == 0
end

---Check if spec is an import spec. lazy.nvim parity: `import` accepts either
---a module-path string (walked as a Lua module directory) or a function
---returning a spec list (dynamic spec generation). A non-string/function
---`import` falls through to plugin-spec handling where the bad `import` is
---an advisory-only error (reported by validate_spec).
---@param spec zpack.Spec
---@return boolean
local is_import_spec = function(spec)
  return type(spec.import) == 'string' or type(spec.import) == 'function'
end

---lazy.nvim parity: a table with several list entries, or only list entries, is
---a nested list of specs; named fields beside several entries are ignored.
---@param value any
---@return boolean
local is_spec_list = function(value)
  if type(value) ~= "table" or is_single_spec(value) then
    return false
  end
  local last = table.maxn(value)
  return last > 1 or (last == 1 and not has_non_integer_keys(value))
end

---For what a later pass over the specs would report again, or wouldn't report
---at all once a plugin is installed.
---@param run zpack.ImportRun
---@param msg? string Nothing to say, if another listing of the same import has
---@param level integer
local defer_notify = function(run, msg, level)
  if msg then
    run.notes[#run.notes + 1] = { msg = msg, level = level }
  end
end

---Load a spec module and import its specs
---@param full_module string Full module path (e.g., 'plugins.telescope')
---@param run zpack.ImportRun
---@param parent? zpack.Spec The spec whose `dependencies` or `specs` holds this
---@param is_dep? boolean Whether that's its `dependencies`
local load_spec_module = function(full_module, run, parent, is_dep)
  local success, spec_item_or_list = pcall(require, full_module)

  if not success then
    defer_notify(run, ("Failed to load plugin spec from %s: %s"):format(full_module, spec_item_or_list), vim.log.levels.ERROR)
  elseif type(spec_item_or_list) ~= "table" then
    defer_notify(run, ("Invalid spec from %s, not a table: %s"):format(full_module, spec_item_or_list), vim.log.levels.ERROR)
  else
    M.import_specs(spec_item_or_list, run, parent, is_dep)
  end
end

---@param path string
---@return string
local function import_path_entry(path)
  return ('%s/lua/?.lua;%s/lua/?/init.lua;'):format(path, path)
end

---Put a plugin's modules within reach of `require`, for an import of its own
---specs. package.path rather than 'runtimepath', so a lazy plugin's modules still
---load it.
---@param path string
---@param run zpack.ImportRun
M.add_import_path = function(path, run)
  if not vim.list_contains(run.import_paths, path) then
    run.import_paths[#run.import_paths + 1] = path
    package.path = import_path_entry(path) .. package.path
  end
end

---For after startup, when a plugin's modules are on 'runtimepath' or load it, and
---one that `cond` keeps from loading shouldn't have them within reach.
---@param imported zpack.Imported
M.remove_import_paths = function(imported)
  for _, path in ipairs(imported.import_paths) do
    local from, to = package.path:find(import_path_entry(path), 1, true)
    if from then
      package.path = package.path:sub(1, from - 1) .. package.path:sub(to + 1)
    end
  end
end

---@param dir string
---@param module_path string
---@return string|nil root The module's file or directory under `dir`, without `.lua`
M.module_in = function(dir, module_path)
  local root = dir .. '/lua/' .. module_path:gsub('%.', '/')
  if vim.uv.fs_stat(root .. '.lua') or vim.uv.fs_stat(root) then
    return root
  end
end

---Find an import's file or directory, without `.lua`: the config, 'runtimepath',
---then plugins added for an import, so a later `{ import = 'p.plugins.extra' }`
---finds its plugin.
---@param module_path string
---@param run zpack.ImportRun
---@return string|nil
local find_module_root = function(module_path, run)
  local config_root = M.module_in(vim.fn.stdpath('config'), module_path)
  if config_root then
    return config_root
  end
  local relative = 'lua/' .. module_path:gsub('%.', '/')
  local file = vim.api.nvim_get_runtime_file(relative .. '.lua', false)[1]
  if file then
    return file:sub(1, -5)
  end
  local dir = vim.api.nvim_get_runtime_file(relative .. '/', false)[1]
  if dir then
    return (dir:gsub('/+$', ''))
  end
  for _, path in ipairs(run.import_paths) do
    local root = M.module_in(path, module_path)
    if root then
      return root
    end
  end
end

---Import specs from a module file or directory (lazy.nvim parity).
---`import = 'plugins'` resolves `lua/plugins.lua` as a single spec module if it
---exists, otherwise walks `lua/plugins/*.lua` and `lua/plugins/*/init.lua`.
---A module imported under several parents is walked once for each, so its specs
---stay while any of those listings does; `require` hands back the same tables,
---which register once. The plugin named by `owner` isn't activated here: vim.pack
---keeps the first spec it gets for a plugin, which has to be the merged one, so an
---installed plugin is read from disk and a missing one waits for import_run's settle,
---as does an import with no owner that misses.
---@param module_path string Module path (e.g., 'plugins' imports from lua/plugins.lua or lua/plugins/)
---@param run zpack.ImportRun
---@param owner? { spec: zpack.Spec, src: string } The plugin to look in if nothing else has the module
---@param parent? zpack.Spec The spec whose `dependencies` or `specs` holds this
---@param is_dep? boolean Whether that's its `dependencies`
local import_from_module = function(module_path, run, owner, parent, is_dep)
  local parents = run.imported_modules[module_path] or {}
  run.imported_modules[module_path] = parents
  local first_walk = next(parents) == nil
  local listing = parent or TOP_LEVEL
  -- A walk that found nothing doesn't stop a later spec's plugin being looked in.
  if parents[listing] == 'walked' or (parents[listing] and not owner) then
    return
  end

  local root = find_module_root(module_path, run)
  local owner_dir
  if not root and owner then
    local dir = pack.plugin_dir(pack.resolve_plugin_name(owner.spec, owner.src))
    if vim.uv.fs_stat(dir) then
      M.add_import_path(dir, run)
      root = find_module_root(module_path, run)
      owner_dir = dir
    elseif not run.tried_owners[owner.spec] then
      run.missing_owners[owner.spec] = true
      return
    end
  end
  parents[listing] = root and 'walked' or 'missed'
  run.missed_import = run.missed_import or not root
  local relative = '/lua/' .. module_path:gsub('%.', '/')
  local function no_specs(looked_in)
    return first_walk and ('zpack: no specs found for import "%s" (looked in %s)'):format(module_path, owner_dir and owner_dir .. relative or looked_in) or nil
  end
  local implicit = module_path == run.implicit_module
  if not root then
    local config_path = vim.fn.stdpath('config') .. relative
    if implicit and not vim.uv.fs_lstat(config_path) and not vim.uv.fs_lstat(config_path .. '.lua') then
      return
    end
    local msg = no_specs(config_path)
    if msg and owner and not owner_dir then
      msg = ("zpack: no specs found for import \"%s\" (%s isn't installed)"):format(module_path, pack.resolve_plugin_name(owner.spec, owner.src))
    elseif not owner then
      run.unowned_misses[#run.unowned_misses + 1] = module_path
      if msg then
        msg = msg .. ("; nor is it in an installed plugin you list named after it. If a plugin provides it, put the import on that plugin's spec: { 'user/dist', import = '%s' }"):format(module_path)
      end
    end
    defer_notify(run, msg, vim.log.levels.WARN)
    return
  end

  -- A `lua/<path>.lua` file takes precedence over a `lua/<path>/` directory:
  -- the file is the single, explicitly-named spec module and the directory walk
  -- is skipped. This mirrors Lua's own `require` resolution (`foo.lua` shadows
  -- `foo/init.lua`) so `import = 'plugins.telescope'` loads exactly that file.
  if vim.uv.fs_stat(("%s.lua"):format(root)) then
    load_spec_module(module_path, run, parent, is_dep)
    return
  end

  -- lazy.nvim parity: by module name, not file name, since the last spec wins:
  -- `foo` comes before `foo-extra`, though `foo-extra.lua` sorts before `foo.lua`.
  local modules = {}
  for _, entry in ipairs(utils.lsdir(root)) do
    if entry.name == "init.lua" then
      modules[#modules + 1] = module_path
    elseif entry.name:sub(-4) == ".lua" then
      modules[#modules + 1] = module_path .. "." .. entry.name:sub(1, -5)
    elseif (entry.type == "directory" or entry.type == "link")
        and vim.uv.fs_stat(root .. "/" .. entry.name .. "/init.lua") then
      modules[#modules + 1] = module_path .. "." .. entry.name
    end
  end
  table.sort(modules)
  for _, module in ipairs(modules) do
    load_spec_module(module, run, parent, is_dep)
  end
  local only_dotfiles = implicit and vim.iter(utils.lsdir(root)):all(function(entry)
    return vim.startswith(entry.name, '.')
  end)
  if #modules == 0 and not only_dotfiles then
    defer_notify(run, no_specs(root), vim.log.levels.WARN)
  end
end

---Import what a spec's `dependencies` or `specs` holds. validate_spec has reported
---any other value.
---@param spec zpack.Spec
---@param children any
---@param run zpack.ImportRun
---@param is_dep boolean
local import_children = function(spec, children, run, is_dep)
  if type(children) == 'string' or type(children) == 'table' then
    M.import_specs(children, run, spec, is_dep)
  end
end

---Follow a spec's `import`. lazy.nvim parity: `enabled` and `cond` apply to it.
---@param spec zpack.Spec
---@param run zpack.ImportRun
---@param src? string The spec's source, if it has one
---@param parent? zpack.Spec The spec whose `dependencies` or `specs` holds this
---@param is_dep? boolean Whether that's its `dependencies`
local import_spec = function(spec, run, src, parent, is_dep)
  local label = 'import:' .. (type(spec.import) == 'string' and spec.import or '<function>')
  if not utils.spec_enabled(spec, label, run.enabled_results) then
    return
  end
  local function report(msg)
    defer_notify(run, msg, vim.log.levels.ERROR)
  end
  if not utils.check_cond(spec, nil, nil, label, report) then
    return
  end
  if type(spec.import) == 'string' then
    local owner = src and run.graph.source_kinds[spec] ~= 'reference' and { spec = spec, src = src } or nil
    import_from_module(spec.import --[[@as string]], run, owner, parent, is_dep)
  else
    -- Per-setup() record: the function runs once and its specs are imported
    -- once per parent, which also guards against
    -- `f = function() return { { import = f } } end` self-recursion.
    local imported = run.imported_functions[spec.import]
    if not imported then
      imported = {}
      run.imported_functions[spec.import] = imported
      local ok, result = pcall(spec.import --[[@as fun(): any]])
      if not ok then
        imported.failure = ('zpack: import function threw: %s'):format(tostring(result))
        imported.failure_level = vim.log.levels.ERROR
      elseif type(result) == 'table' then
        imported.specs = result
      else
        imported.failure = ('zpack: import function returned non-table (%s)'):format(type(result))
        imported.failure_level = vim.log.levels.WARN
      end
    end
    local parents = run.function_parents[spec.import] or {}
    run.function_parents[spec.import] = parents
    local listing = parent or TOP_LEVEL
    if not parents[listing] then
      local first_listing = next(parents) == nil
      parents[listing] = true
      if imported.specs then
        M.import_specs(imported.specs, run, parent, is_dep)
      elseif first_listing then
        defer_notify(run, imported.failure, imported.failure_level)
      end
    end
  end
end

---Process one spec: an import spec recurses into a module directory; a plugin
---spec is registered into spec_registry and has its dependencies walked. A spec
---with a source and an `import` is both, plugin first (lazy.nvim parity:
---`{ 'LazyVim/LazyVim', import = 'lazyvim.plugins' }`).
---@param spec zpack.Spec
---@param run zpack.ImportRun
---@param parent? zpack.Spec The spec whose `dependencies` or `specs` holds this
---@param is_dep? boolean Whether that's its `dependencies`
local import_one_spec = function(spec, run, parent, is_dep)
  if not run.validated_specs[spec] then
    run.validated_specs[spec] = true
    local spec_errors = validate.validate_spec(spec)
    if #spec_errors > 0 then
      local label = type(spec) == 'table' and validate.spec_label(spec) or tostring(spec)
      local under = parent and (' under "%s"'):format(validate.spec_label(parent)) or ''
      utils.schedule_notify(
        ('zpack: invalid spec "%s"%s:\n  %s'):format(label, under, table.concat(spec_errors, '\n  ')),
        vim.log.levels.WARN
      )
    end
  end
  -- A non-table spec cannot be processed further. A table spec continues: a bad
  -- field is advisory and the spec still imports, while a missing source is caught
  -- downstream.
  if type(spec) ~= 'table' then
    return
  end

  -- A sourceless spec was already reported by validate_spec above; skip it
  -- rather than letting the loader abort setup() partway through.
  local src, source_kind = normalize_source(spec)
  if not src then
    if is_import_spec(spec) then
      import_spec(spec, run, nil, parent, is_dep)
    end
    return
  end
  is_dep = is_dep or false

  local graph = run.graph
  local seen = graph.top_specs[spec] or graph.spec_parents[spec] ~= nil
  if parent then
    graph.spec_parents[spec] = graph.spec_parents[spec] or {}
    graph.spec_parents[spec][parent] = true
    graph.spec_children[parent] = graph.spec_children[parent] or {}
    graph.spec_children[parent][spec] = graph.spec_children[parent][spec] or is_dep
  else
    graph.top_specs[spec] = true
  end
  -- lazy.nvim parity: a table listed in several places is one fragment, so
  -- its opts and lists count once. It is a dependency only if every
  -- listing is one.
  if seen then
    spec._is_dependency = spec._is_dependency and is_dep
    -- The import stays while any listing does, so it's walked per listing.
    if is_import_spec(spec) then
      import_spec(spec, run, src, parent, is_dep)
    end
    return
  end

  graph.spec_src[spec] = src
  graph.source_kinds[spec] = source_kind
  spec._import_order = run.next_import_order
  run.next_import_order = run.next_import_order + 1
  spec._is_dependency = is_dep

  if state.spec_registry[src] then
    table.insert(state.spec_registry[src].specs, spec)
  else
    state.spec_registry[src] = { specs = { spec }, load_status = "pending" }
  end

  -- Walk dependencies unconditionally. `enabled` is evaluated post-merge
  -- in resolve_all; gating the dep walk on the raw pre-merge spec would
  -- call function-form `enabled` eagerly at import time and diverge from
  -- the merged truth. prune_disabled handles cleanup afterward.
  import_children(spec, spec.dependencies, run, true)

  -- Nested `specs` are peer plugins; reset is_dependency so a parent
  -- reached via a `dependencies` chain doesn't propagate dep-status down.
  import_children(spec, spec.specs, run, false)

  if is_import_spec(spec) then
    import_spec(spec, run, src, parent, is_dep)
  end
end

---@param spec_item_or_list string|zpack.Spec|zpack.Spec[]
---@param run zpack.ImportRun
---@param parent? zpack.Spec The spec whose `dependencies` or `specs` holds this
---@param is_dep? boolean Whether that's its `dependencies`
M.import_specs = function(spec_item_or_list, run, parent, is_dep)
  if type(spec_item_or_list) == 'string' then
    spec_item_or_list = { spec_item_or_list }
  end
  local specs = is_single_spec(spec_item_or_list)
      and { spec_item_or_list }
      or spec_item_or_list --[[@as zpack.Spec[] ]]

  for i = 1, table.maxn(specs) do
    local spec = specs[i]
    -- lazy.nvim parity: a list may hold bare strings and nested lists.
    if is_spec_list(spec) then
      M.import_specs(spec, run, parent, is_dep)
    elseif not validate.is_nothing(spec) then
      import_one_spec(type(spec) == 'string' and { spec } or spec, run, parent, is_dep)
    end
  end
end

return M
