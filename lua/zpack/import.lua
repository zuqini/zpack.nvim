local utils = require('zpack.utils')
local state = require('zpack.state')
local lazy = require('zpack.lazy')

local M = {}

---@param spec zpack.Spec
---@return boolean
local is_enabled = function(spec)
  if spec.enabled == false or (type(spec.enabled) == "function" and not spec.enabled()) then
    return false
  end
  return true
end

---Normalize plugin source using priority: [1] > src > url > dir
---@param spec zpack.Spec
---@return string|nil source URL/path, or nil if invalid
---@return string|nil error message if validation fails
local normalize_source = function(spec)
  if spec[1] then
    return 'https://github.com/' .. spec[1]
  elseif spec.src then
    return spec.src
  elseif spec.url then
    return spec.url
  elseif spec.dir then
    return spec.dir
  else
    return nil, "spec must provide one of: [1], src, dir, or url"
  end
end

---@param spec zpack.Spec
---@return string
local get_source_url = function(spec)
  local src, err = normalize_source(spec)
  if not src then
    utils.schedule_notify(err, vim.log.levels.ERROR)
    error(err)
  end
  return src
end

---@param spec zpack.Spec
---@param src string
---@param ctx ProcessContext
local index_spec = function(spec, src, ctx)
  table.insert(ctx.vim_packs, { src = src, version = spec.version, name = spec.name })

  if not utils.check_cond(spec) then
    return
  end

  if not lazy.is_lazy(spec) then
    if spec.config then
      table.insert(ctx.src_with_startup_config, src)
    end

    if spec.init then
      table.insert(ctx.src_with_startup_init, src)
    end

    if spec.keys then
      for _, key in ipairs(utils.normalize_keys(spec.keys)) do
        table.insert(ctx.startup_keys, key)
      end
    end
  end
end

---Check if value is a single spec (not a list of specs)
---@param value zpack.Spec|zpack.Spec[]
---@return boolean
local is_single_spec = function(value)
  return type(value[1]) == "string"
      or value.src ~= nil
      or value.dir ~= nil
      or value.url ~= nil
end

---@param spec_item_or_list zpack.Spec|zpack.Spec[]
---@param ctx ProcessContext
M.import_specs = function(spec_item_or_list, ctx)
  local specs = is_single_spec(spec_item_or_list)
      and { spec_item_or_list }
      or spec_item_or_list --[[@as zpack.Spec[] ]]

  for _, spec in ipairs(specs) do
    if not is_enabled(spec) then
      goto continue
    end

    local src = get_source_url(spec)
    -- already imported, skip
    if state.spec_registry[src] then
      goto continue
    end

    state.spec_registry[src] = { spec = spec, loaded = false }
    index_spec(spec, src, ctx)

    ::continue::
  end
end

return M
