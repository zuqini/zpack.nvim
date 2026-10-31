local utils = require('zpack.utils')
local state = require('zpack.state')
local validate = require('zpack.validate')

local M = {}

local imported_modules = {}

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
  -- validate_config is advisory, so a bad value can reach here. Coerce to
  -- defaults rather than feed vim.fn.expand(false) → 'v:false' as a path.
  local dev_config = state.config.dev or {}
  local dev_path_opt = type(dev_config.path) == 'string' and dev_config.path or '~/projects'
  -- Strip trailing slash so registry keys do not drift between sessions
  -- with vs. without the trailing slash on `dev.path`.
  local dev_base = vim.fn.expand(dev_path_opt):gsub('/+$', '')
  -- `spec.name` first: lazy.nvim parity for overriding the derived dir.
  -- This chain derives the checkout NAME ([1] before src, unlike
  -- normalize_source's src-first source precedence): a fork url still
  -- checks out under the upstream short name.
  local source_for_name = spec.name or spec[1] or spec.src or spec.url or spec.dir
  if type(source_for_name) ~= 'string' then
    require('zpack.utils').schedule_notify(
      ('dev = true on spec "%s" requires a source field (name/[1]/src/url/dir) to derive the local checkout name')
        :format(validate.spec_label(spec)),
      vim.log.levels.ERROR
    )
    return nil
  end
  local derived = require('zpack.utils').derive_name_from_src(source_for_name)
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
    return utils.expand_src(short), has_owner and 'repo' or 'reference'
  elseif spec.dev == true and type(spec.name) == 'string' then
    -- Only reachable under dev.fallback with no checkout.
    return utils.expand_src(spec.name), 'reference'
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
---specs has tables or strings as elements.
---@param value zpack.Spec|zpack.Spec[]
---@return boolean
local is_single_spec = function(value)
  if value.src ~= nil or value.dir ~= nil or value.url ~= nil or value.import ~= nil
      or (value.dev == true and type(value.name) == "string") then
    return true
  end
  if type(value[1]) == "string" then
    return value[2] == nil or has_non_integer_keys(value)
  end
  return false
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
  return type(value) == "table" and value[1] ~= nil and not is_single_spec(value)
      and (value[2] ~= nil or not has_non_integer_keys(value))
end

---lazy.nvim parity: an empty table is an empty list, for the
---`cond and { ... } or {}` idiom.
---@param value any
---@return boolean
local is_nothing = function(value)
  return type(value) == "table" and next(value) == nil
end

---For what a later pass over the specs would report again, or wouldn't report
---at all once a plugin is installed.
---@param ctx zpack.ProcessContext
---@param msg string
---@param level integer
local defer_notify = function(ctx, msg, level)
  ctx.import_notes[#ctx.import_notes + 1] = { msg = msg, level = level }
end

---Load a spec module and import its specs
---@param full_module string Full module path (e.g., 'plugins.telescope')
---@param ctx zpack.ProcessContext
local load_spec_module = function(full_module, ctx)
  local success, spec_item_or_list = pcall(require, full_module)

  if not success then
    defer_notify(ctx, ("Failed to load plugin spec from %s: %s"):format(full_module, spec_item_or_list), vim.log.levels.ERROR)
  elseif type(spec_item_or_list) ~= "table" then
    defer_notify(ctx, ("Invalid spec from %s, not a table: %s"):format(full_module, spec_item_or_list), vim.log.levels.ERROR)
  else
    M.import_specs(spec_item_or_list, ctx)
  end
end

---Put a plugin's modules within reach of `require`, for an import of its own
---specs. package.path rather than 'runtimepath', so a lazy plugin's modules still
---load it.
---@param path string
---@param ctx zpack.ProcessContext
local add_import_path = function(path, ctx)
  if not vim.list_contains(ctx.import_paths, path) then
    ctx.import_paths[#ctx.import_paths + 1] = path
    package.path = ('%s/lua/?.lua;%s/lua/?/init.lua;%s'):format(path, path, package.path)
  end
end

---Find an import's file or directory, without `.lua`: the config, 'runtimepath',
---then plugins added for an import, so a later `{ import = 'p.plugins.extra' }`
---finds its plugin.
---@param module_path string
---@param ctx zpack.ProcessContext
---@return string|nil
local find_module_root = function(module_path, ctx)
  local relative = 'lua/' .. module_path:gsub('%.', '/')
  local config_root = vim.fn.stdpath('config') .. '/' .. relative
  if vim.uv.fs_stat(config_root .. '.lua') or vim.uv.fs_stat(config_root) then
    return config_root
  end
  local file = vim.api.nvim_get_runtime_file(relative .. '.lua', false)[1]
  if file then
    return file:sub(1, -5)
  end
  local dir = vim.api.nvim_get_runtime_file(relative .. '/', false)[1]
  if dir then
    return (dir:gsub('/+$', ''))
  end
  for _, path in ipairs(ctx.import_paths) do
    local root = path .. '/' .. relative
    if vim.uv.fs_stat(root .. '.lua') or vim.uv.fs_stat(root) then
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
---installed plugin is read from disk and a missing one waits for settle_missing_owners.
---@param module_path string Module path (e.g., 'plugins' imports from lua/plugins.lua or lua/plugins/)
---@param ctx zpack.ProcessContext
---@param owner? { spec: zpack.Spec, src: string } The plugin to look in if nothing else has the module
local import_from_module = function(module_path, ctx, owner)
  local parents = imported_modules[module_path] or {}
  imported_modules[module_path] = parents
  local first_walk = next(parents) == nil
  local parent = ctx.parent or TOP_LEVEL
  -- A walk that found nothing doesn't stop a later spec's plugin being looked in.
  if parents[parent] == 'walked' or (parents[parent] and not owner) then
    return
  end

  local root = find_module_root(module_path, ctx)
  local owner_dir
  if not root and owner then
    local settled = ctx.settled_owners[owner.spec]
    if settled == 'removed' then
      return
    end
    local dir = utils.plugin_dir(utils.resolve_plugin_name(owner.spec, owner.src))
    if vim.uv.fs_stat(dir) then
      add_import_path(dir, ctx)
      root = find_module_root(module_path, ctx)
      owner_dir = dir
    elseif not settled then
      ctx.missing_owners[owner.spec] = true
      return
    end
  end
  parents[parent] = root and 'walked' or 'missed'
  ctx.missed_import = ctx.missed_import or not root
  local relative = '/lua/' .. module_path:gsub('%.', '/')
  local lua_path = root or (vim.fn.stdpath('config') .. relative)

  -- A `lua/<path>.lua` file takes precedence over a `lua/<path>/` directory:
  -- the file is the single, explicitly-named spec module and the directory walk
  -- is skipped. This mirrors Lua's own `require` resolution (`foo.lua` shadows
  -- `foo/init.lua`) so `import = 'plugins.telescope'` loads exactly that file.
  if vim.uv.fs_stat(("%s.lua"):format(lua_path)) then
    load_spec_module(module_path, ctx)
    return
  end

  -- lazy.nvim parity: by module name, not file name, since the last spec wins:
  -- `foo` comes before `foo-extra`, though `foo-extra.lua` sorts before `foo.lua`.
  local modules = {}
  for _, entry in ipairs(utils.lsdir(lua_path)) do
    if entry.name == "init.lua" then
      modules[#modules + 1] = module_path
    elseif entry.name:sub(-4) == ".lua" then
      modules[#modules + 1] = module_path .. "." .. entry.name:sub(1, -5)
    elseif (entry.type == "directory" or entry.type == "link")
        and vim.uv.fs_stat(lua_path .. "/" .. entry.name .. "/init.lua") then
      modules[#modules + 1] = module_path .. "." .. entry.name
    end
  end
  table.sort(modules)
  for _, module in ipairs(modules) do
    load_spec_module(module, ctx)
  end
  if #modules == 0 and first_walk then
    defer_notify(ctx, ('zpack: no specs found for import "%s" (looked in %s)'):format(module_path, owner_dir and owner_dir .. relative or lua_path), vim.log.levels.WARN)
  end
end

---Import a spec's dependencies as its children.
---@param spec zpack.Spec
---@param src string Normalized source of the parent spec
---@param ctx zpack.ProcessContext
local register_dependencies = function(spec, src, ctx)
  local deps = spec.dependencies
  if type(deps) ~= 'string' and type(deps) ~= 'table' then
    utils.schedule_notify(
      ('Invalid dependencies for %s: expected string or table, got %s'):format(src, type(deps)),
      vim.log.levels.WARN
    )
    return
  end
  M.import_specs(deps --[[@as string|zpack.Spec[] ]], vim.tbl_extend('force', ctx, { is_dependency = true, parent = spec }))
end

---What is known of a plugin at import time. `path` is where it installs, which
---may not exist yet.
---@param spec zpack.Spec
---@param src string
---@return zpack.Plugin
local function plugin_at_import(spec, src)
  local name = utils.resolve_plugin_name(spec, src)
  ---@diagnostic disable-next-line: missing-fields
  local path = utils.plugin_dir(name)
  return { name = name, path = path, dir = path, spec = { name = name, src = src } }
end

---Follow a spec's `import`. lazy.nvim parity: `enabled` and `cond` apply to it.
---@param spec zpack.Spec
---@param ctx zpack.ProcessContext
---@param src? string The spec's source, if it has one
local import_spec = function(spec, ctx, src)
  local label = 'import:' .. (type(spec.import) == 'string' and spec.import or '<function>')
  if not utils.spec_enabled(spec, label)
      or not utils.check_cond(spec, src and plugin_at_import(spec, src) or nil, nil, label) then
    return
  end
  if type(spec.import) == 'string' then
    local owner = src and state.source_kinds[spec] ~= 'reference' and { spec = spec, src = src } or nil
    import_from_module(spec.import --[[@as string]], ctx, owner)
  else
    -- Per-setup() record: the function runs once and its specs are imported
    -- once per parent, which also guards against
    -- `f = function() return { { import = f } } end` self-recursion.
    local imported = ctx._imported_functions[spec.import]
    if not imported then
      imported = { parents = {} }
      ctx._imported_functions[spec.import] = imported
      local ok, result = pcall(spec.import --[[@as fun(): any]])
      if not ok then
        utils.schedule_notify(
          ('zpack: import function threw: %s'):format(tostring(result)),
          vim.log.levels.ERROR
        )
      elseif type(result) == 'table' then
        imported.specs = result
      else
        -- Mirror load_spec_module's non-table-return notify.
        utils.schedule_notify(
          ('zpack: import function returned non-table (%s)'):format(type(result)),
          vim.log.levels.WARN
        )
      end
    end
    if imported.specs and not imported.parents[ctx.parent or TOP_LEVEL] then
      imported.parents[ctx.parent or TOP_LEVEL] = true
      M.import_specs(imported.specs, ctx)
    end
  end
end

---Process one spec: an import spec recurses into a module directory; a plugin
---spec is registered into spec_registry and has its dependencies walked. A spec
---with a source and an `import` is both, plugin first (lazy.nvim parity:
---`{ 'LazyVim/LazyVim', import = 'lazyvim.plugins' }`).
---@param spec zpack.Spec
---@param ctx zpack.ProcessContext
local import_one_spec = function(spec, ctx)
  if not state.validated_specs[spec] then
    state.validated_specs[spec] = true
    local spec_errors = validate.validate_spec(spec)
    if #spec_errors > 0 then
      local label = type(spec) == 'table' and validate.spec_label(spec) or tostring(spec)
      local under = ctx.parent and (' under "%s"'):format(validate.spec_label(ctx.parent)) or ''
      utils.schedule_notify(
        ('zpack: invalid spec "%s"%s:\n  %s'):format(label, under, table.concat(spec_errors, '\n  ')),
        vim.log.levels.WARN
      )
    end
  end
  -- A non-table spec cannot be processed further; the warning is the
  -- actionable signal. A table spec continues: a bad field is advisory and
  -- the spec still imports, while a missing source is caught downstream.
  if type(spec) ~= 'table' then
    return
  end

  -- A sourceless spec was already reported by validate_spec above; skip it
  -- rather than letting the loader abort setup() partway through.
  local src, source_kind = normalize_source(spec)
  if not src then
    if is_import_spec(spec) then
      import_spec(spec, ctx)
    end
    return
  end
  local is_dep = ctx.is_dependency or false

  local seen = state.top_specs[spec] or state.spec_parents[spec] ~= nil
  if ctx.parent then
    state.spec_parents[spec] = state.spec_parents[spec] or {}
    state.spec_parents[spec][ctx.parent] = true
    state.spec_children[ctx.parent] = state.spec_children[ctx.parent] or {}
    state.spec_children[ctx.parent][spec] = state.spec_children[ctx.parent][spec] or is_dep
  else
    state.top_specs[spec] = true
  end
  -- lazy.nvim parity: a table listed in several places is one fragment, so
  -- its opts and lists count once. It is a dependency only if every
  -- listing is one.
  if seen then
    spec._is_dependency = spec._is_dependency and is_dep
    -- The import stays while any listing does, so it's walked per listing.
    if is_import_spec(spec) then
      import_spec(spec, ctx, src)
    end
    return
  end

  state.spec_src[spec] = src
  state.source_kinds[spec] = source_kind
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
  -- the merged truth. prune_disabled handles cleanup afterward.
  if spec.dependencies then
    register_dependencies(spec, src, ctx)
  end

  -- Nested `specs` are peer plugins; reset is_dependency so a parent
  -- reached via a `dependencies` chain doesn't propagate dep-status down.
  if type(spec.specs) == 'table' or type(spec.specs) == 'string' then
    local peer_ctx = vim.tbl_extend('force', ctx, { is_dependency = false, parent = spec })
    M.import_specs(spec.specs, peer_ctx)
  end

  if is_import_spec(spec) then
    import_spec(spec, ctx, src)
  end
end

---@param spec_item_or_list string|zpack.Spec|zpack.Spec[]
---@param ctx zpack.ProcessContext
M.import_specs = function(spec_item_or_list, ctx)
  if type(spec_item_or_list) == 'string' then
    spec_item_or_list = { spec_item_or_list }
  end
  local specs = is_single_spec(spec_item_or_list)
      and { spec_item_or_list }
      or spec_item_or_list --[[@as zpack.Spec[] ]]

  for _, spec in ipairs(specs) do
    -- lazy.nvim parity: a list may hold bare strings and nested lists.
    if is_spec_list(spec) then
      M.import_specs(spec, ctx)
    elseif not is_nothing(spec) then
      import_one_spec(type(spec) == 'string' and { spec } or spec, ctx)
    end
  end
end

---Decide what becomes of each plugin whose module was missing, now that all its
---specs are known: a resolve says whether it stays and under which name, source
---and version, so that's what gets installed. The resolve is a trial run, so it
---stays quiet and the caller starts the import over.
---@param ctx zpack.ProcessContext
local settle_missing_owners = function(ctx)
  local any_added = false
  -- Installed under a name another of its specs gives: no resolve needed to find it.
  for spec in pairs(ctx.missing_owners) do
    local src = state.spec_src[spec]
    for _, fragment in ipairs(state.spec_registry[src].specs) do
      local dir = fragment.name and utils.plugin_dir(utils.resolve_plugin_name(fragment, src))
      if dir and vim.uv.fs_stat(dir) then
        add_import_path(dir, ctx)
        ctx.settled_owners[spec] = 'added'
        ctx.missing_owners[spec] = nil
        any_added = true
        break
      end
    end
  end

  local to_add = {}
  if next(ctx.missing_owners) then
    local validated, enabled = state.validated_specs, state.enabled_results
    utils.silently(require('zpack.merge').resolve_all)
    state.validated_specs, state.enabled_results = validated, enabled

    for spec in pairs(ctx.missing_owners) do
      ctx.settled_owners[spec] = 'removed'
    end
    for src, entry in pairs(state.spec_registry) do
      local stays = false
      for _, spec in ipairs(entry.specs) do
        if ctx.missing_owners[spec] then
          ctx.settled_owners[spec] = 'added'
          stays = true
          any_added = true
        end
      end
      if stays then
        local pack_spec = state.src_to_pack_spec[src]
        local dir = utils.plugin_dir(pack_spec.name)
        if vim.uv.fs_stat(dir) then
          add_import_path(dir, ctx)
        else
          to_add[#to_add + 1] = { src = src, name = pack_spec.name, version = pack_spec.version }
        end
      end
    end
  end

  -- The specs of what's added can keep a plugin that was removed, so look again.
  -- An owner is added once, so this ends.
  if any_added then
    for spec, settled in pairs(ctx.settled_owners) do
      if settled == 'removed' then
        ctx.settled_owners[spec] = nil
      end
    end
  end
  if #to_add == 0 then
    return
  end
  local err = require('zpack.pack').add(to_add, {
    confirm = ctx.confirm,
    load = function(plugin)
      ctx.early_plugins[plugin.spec.name] = plugin
      add_import_path(plugin.path, ctx)
    end,
  })
  if err then
    utils.schedule_notify(('zpack: could not install a plugin for its import: %s'):format(err), vim.log.levels.ERROR)
  end
end

---@param ctx zpack.ProcessContext
M.flush_notes = function(ctx)
  for _, note in ipairs(ctx.import_notes) do
    utils.schedule_notify(note.msg, note.level)
  end
  ctx.import_notes = {}
end

---Import every spec, installing any plugin an import needs modules from.
---lazy.nvim parity: it too installs what's missing and reads the specs again.
---An import that comes before the spec of the plugin that has its module finds it
---on a second pass, as it would on a first install. Each pass settles at least one
---spec or adds a path, so this ends.
---@param spec_item_or_list string|zpack.Spec|zpack.Spec[]
---@param ctx zpack.ProcessContext
M.import_all = function(spec_item_or_list, ctx)
  while true do
    local known_paths = #ctx.import_paths
    ctx.import_notes, ctx.missing_owners, ctx.missed_import = {}, {}, false
    M.import_specs(spec_item_or_list, ctx)
    local found_more = ctx.missed_import and #ctx.import_paths > known_paths
    if next(ctx.missing_owners) == nil and not found_more then
      break
    end
    if next(ctx.missing_owners) then
      settle_missing_owners(ctx)
    end
    state.reset_specs()
    M.reset_imported_modules()
    for _, imported in pairs(ctx._imported_functions) do
      imported.parents = {}
    end
  end
  M.flush_notes(ctx)
end

M.reset_imported_modules = function()
  imported_modules = {}
end

return M
