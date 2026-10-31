local state = require('zpack.state')
local utils = require('zpack.utils')

local M = {}

---How vim.pack reads tags: since 0.13, `v1.2` is no version to it.
local STRICT_TAGS = vim.fn.has('nvim-0.13') == 1

---@param tag string?
---@param range vim.VersionRange
---@return boolean
local function fits(tag, range)
  local version = tag and tag:match('^v?%d') and vim.version.parse(tag, { strict = STRICT_TAGS })
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
  for _, entry in ipairs(utils.lsdir(dir .. '/.git/refs/tags')) do
    if fits(entry.name, range) then
      return true
    end
  end
  return false
end

---What's left of a vim.pack.add error without some plugins' parts of it, which
---it separates with blank lines.
---@param err string
---@param without { [string]: true }
---@return string[]
local function other_errors(err, without)
  local kept = {}
  for _, part in ipairs(vim.split(err, '\n\n', { plain = true })) do
    local name = part:match('^`([^`]+)`:\n')
    if not without[name] and not part:match('vim%.pack:$') then
      kept[#kept + 1] = part
    end
  end
  return kept
end

---vim.pack.add, except that a version written as a semver string (see
---state.soft_versions) follows the default branch when no tag fits it, as in
---lazy.nvim, where vim.pack raises. That's decided here for an installed plugin,
---so that `:ZPack update` doesn't raise over it either, and by trying for one
---that isn't.
---@param packs vim.pack.Spec[]
---@param opts { confirm: boolean?, load: fun(plugin: table) }
---@return string? err
M.add = function(packs, opts)
  for _, pack_spec in ipairs(packs) do
    local dir = utils.plugin_dir(pack_spec.name)
    if state.soft_versions[pack_spec.src] and vim.uv.fs_stat(dir)
        and not has_fitting_tag(dir, pack_spec.version --[[@as vim.VersionRange]]) then
      pack_spec.version = nil
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

  local retry, retrying = {}, {}
  for _, pack_spec in ipairs(packs) do
    if state.soft_versions[pack_spec.src] and pack_spec.version and not loaded[pack_spec.name] then
      pack_spec.version = nil
      retry[#retry + 1] = pack_spec
      retrying[pack_spec.name] = true
    end
  end
  if #retry == 0 then
    return err
  end

  local errors = other_errors(err, retrying)
  -- The user has already said yes to installing these.
  local retry_ok, retry_err = pcall(vim.pack.add, retry, { confirm = false, load = load })
  if not retry_ok then
    errors[#errors + 1] = tostring(retry_err)
  end
  return #errors > 0 and table.concat(errors, '\n\n') or nil
end

return M
