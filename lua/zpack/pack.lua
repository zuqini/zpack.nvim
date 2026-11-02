if jit then jit.off(true, true) end

local state = require('zpack.state')
local utils = require('zpack.utils')

local M = {}

---Where vim.pack installs a plugin.
---@param name string
---@return string
M.plugin_dir = function(name)
  return vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. name
end

---Derive a plugin name from a source (URL, path, or `[1]` short name):
---basename, stripped of a trailing `.git`. Used to resolve a stable name
---before `vim.pack.add`'s load callback has populated `plugin.spec.name`.
---@param src string
---@return string
M.derive_name_from_src = function(src)
  local trimmed = src:gsub('/+$', '')
  local basename = trimmed:match('([^/]+)$') or trimmed
  return (basename:gsub('%.git$', ''))
end

---Resolve a `[1]` value to a source. `owner/repo` shorthand expands to its
---GitHub URL; a full git URL (`scheme://`, `user@host:`) is returned
---unchanged (lazy.nvim parity). Filesystem paths are not recognized: vim.pack
---hands src to git verbatim, so local checkouts belong in `dir`, which
---normalize_source expands. Shared by `normalize_source` and fold.lua's
---coalesce fold so the two sites cannot drift on what a shorthand resolves to.
---@param src string `[1]` value: `owner/repo` or a full git URL
---@return string
M.expand_src = function(src)
  if src:match('^%a[%w+.-]*://') or src:match('^[%w_.-]+@[^/]+:') then
    return src
  end
  return 'https://github.com/' .. src
end

---Resolve a plugin's display/pack name. lazy.nvim parity: the name derives
---from `[1]` even when an explicit src/url/dir wins the source resolution,
---so `{ 'user/repo', url = fork }` keeps the name "repo" regardless of the
---fork's basename. An explicit `name` always wins.
---@param merged_spec zpack.Spec
---@param src string Normalized source (fallback name basis)
---@return string
M.resolve_plugin_name = function(merged_spec, src)
  if type(merged_spec.name) == 'string' then
    return merged_spec.name
  end
  if type(merged_spec[1]) == 'string' then
    return M.derive_name_from_src(merged_spec[1])
  end
  return M.derive_name_from_src(src)
end

---Check if a string looks like a semver range (not a branch/tag/commit)
---@param str any
---@return boolean
M.is_semver_like = function(str)
  if type(str) ~= 'string' then
    return false
  end
  return str:match('%*') ~= nil
      or str:match('^%d[%d%.]*%.[xX]$') ~= nil
      or str:match('^%d[%d%.]*%.%a') ~= nil
      or str:match('^[>=<^~]') ~= nil
      or str:match('[>=<]') ~= nil
      or str:match('^%d+[%d%.]*$') ~= nil
end

---A string git can't take as a ref can only be a semver range. lazy.nvim parity,
---so a distro's `version = '*'` works; anything that could be a ref stays one.
---@param version any
---@return any
---@return boolean? is_range
local function range_if_not_a_ref(version)
  if type(version) == 'string' and (version:find('*', 1, true) or version:match('^[>=<^~]')) then
    local ok, range = pcall(vim.version.range, version)
    if ok and range then
      return range, true
    end
  end
  return version
end

---What vim.pack.add takes as a version. It raises for the whole call on anything
---else, losing every plugin over one bad field, which validate_spec reports.
---@param version any
---@return boolean
local function is_version(version)
  return type(version) == 'string' or (type(version) == 'table' and (pcall(version.has, version, '1')))
end

---Normalize plugin version using lazy.nvim's priority: commit > tag > version >
---sem_version > branch > defaults.version.
---`version = false` is a lazy.nvim escape hatch meaning "no version constraint" —
---a commit, tag or branch still applies, but sem_version and a global default don't.
---@param spec zpack.Spec
---@return string|vim.VersionRange|nil version
---@return boolean? is_soft A semver string, which falls back to the default branch; see zpack.pack
M.normalize_version = function(spec)
  if type(spec.commit) == 'string' then
    return spec.commit
  elseif type(spec.tag) == 'string' then
    return spec.tag
  elseif is_version(spec.version) then
    return range_if_not_a_ref(spec.version)
  end
  local range = type(spec.sem_version) == 'string' and spec.version ~= false and vim.version.range(spec.sem_version)
  if range then
    return range, true
  elseif type(spec.branch) == 'string' then
    return spec.branch
  elseif spec.version == false then
    return nil
  end
  local default_version = state.config and state.config.defaults and state.config.defaults.version
  if is_version(default_version) then
    return range_if_not_a_ref(default_version)
  end
  return nil
end

---How vim.pack reads tags: since 0.13, `v1.2` and `release-1.2.3` are no versions to it.
local STRICT_TAGS = vim.fn.has('nvim-0.13') == 1

---@param tag string?
---@param range vim.VersionRange
---@return boolean
local function fits(tag, range)
  local version = tag and vim.version.parse(tag, { strict = STRICT_TAGS })
  return version ~= nil and range:has(version)
end

---@param dir string A plugin's directory
---@param range vim.VersionRange
---@return boolean
local function has_fitting_tag(dir, range)
  local packed = io.open(dir .. '/.git/packed-refs', 'r')
  if packed then
    for line in packed:lines() do
      if fits(line:match('^%x+ refs/tags/(.+)$'), range) then
        packed:close()
        return true
      end
    end
    packed:close()
  end
  for name, kind in vim.fs.dir(dir .. '/.git/refs/tags', { depth = math.huge }) do
    if kind == 'file' and fits(name, range) then
      return true
    end
  end
  return false
end

---@param pack_spec vim.pack.Spec
---@return vim.VersionRange?
local function soft_version(pack_spec)
  local entry = state.spec_registry[pack_spec.src]
  return entry and entry.soft_version
end

---vim.pack.add, except that a version written as a semver string (see
---zpack.RegistryEntry) follows the default branch when no tag fits it, as in
---lazy.nvim, where vim.pack raises. That's decided from the local tags for an
---installed plugin, so that vim.pack.update doesn't raise over it either, and by
---trying for one that isn't.
---@param packs vim.pack.Spec[]
---@param opts { confirm: boolean?, load: fun(plugin: table) }
---@return string? err
M.add = function(packs, opts)
  -- vim.pack's first call in a session installs what's in the lockfile, at the locked
  -- revisions. Alone, so that's already on disk when local tags are read below, and
  -- with zpack on 'runtimepath' as much as after a vim.pack.add of zpack itself.
  local synced, sync_err = pcall(vim.pack.add, {}, { confirm = opts.confirm })
  if not synced then
    return tostring(sync_err)
  end

  for _, pack_spec in ipairs(packs) do
    local range = soft_version(pack_spec)
    if range then
      local dir = M.plugin_dir(pack_spec.name)
      if vim.uv.fs_stat(dir) and not has_fitting_tag(dir, range) then
        pack_spec.version = nil
      end
    end
  end

  local loaded = {}
  local function load(plugin)
    loaded[plugin.spec.name] = true
    opts.load(plugin)
  end
  local ok, err = pcall(vim.pack.add, packs, { confirm = opts.confirm, load = load })
  if ok then
    return nil
  end
  err = tostring(err)

  local soft = {}
  for _, pack_spec in ipairs(packs) do
    if soft_version(pack_spec) and pack_spec.version and not loaded[pack_spec.name] then
      soft[pack_spec.name] = pack_spec
    end
  end

  -- vim.pack separates each plugin's error with blank lines. One that raises for
  -- the whole call names no plugin, and comes before it has asked to install.
  local retry, errors = {}, {}
  for _, part in ipairs(vim.split(err, '\n\n', { plain = true })) do
    local name = part:match('^%s*`([^`]+)`:\n')
    if soft[name] then
      soft[name].version = nil
      retry[#retry + 1] = soft[name]
    elseif not part:match('vim%.pack:$') then
      errors[#errors + 1] = part
    end
  end
  if #retry == 0 then
    return err
  end

  -- The user has already said yes to installing these.
  local retry_ok, retry_err = pcall(vim.pack.add, retry, { confirm = false, load = load })
  if not retry_ok then
    errors[#errors + 1] = tostring(retry_err)
  end
  return #errors > 0 and table.concat(errors, '\n\n') or nil
end

---vim.pack.update fetches a plugin's tags, but a plugin's spec is fixed for the
---session, so one following its default branch goes to the tip even if a tag now
---fits it. M.add finds the tag after a restart, so say so.
---@param names? string[] Default: every plugin
M.notify_new_tags = function(names)
  for src, entry in pairs(state.spec_registry) do
    local pack_spec = state.src_to_pack_spec[src]
    if entry.soft_version and pack_spec.version == nil
        and (not names or vim.list_contains(names, pack_spec.name))
        and has_fitting_tag(M.plugin_dir(pack_spec.name), entry.soft_version) then
      utils.schedule_notify(
        ('%s: a tag now fits its version, but this update follows the default branch. Restart and update again to move to the tag.'):format(pack_spec.name),
        vim.log.levels.WARN
      )
    end
  end
end

return M
