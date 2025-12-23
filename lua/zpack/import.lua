local utils = require('zpack.utils')
local state = require('zpack.state')
local lazy = require('zpack.lazy')

local M = {}

---@param spec Spec
---@return boolean
local is_enabled = function(spec)
  if spec.enabled == false or (type(spec.enabled) == "function" and not spec.enabled()) then
    return false
  end
  return true
end

---@param spec Spec
---@return boolean
local check_condition = function(spec)
  if spec.cond == false or (type(spec.cond) == "function" and not spec.cond()) then
    return false
  end
  return true
end

---Normalize plugin source using priority: [1] > src > url > dir
---@param spec Spec
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

---@param spec Spec
---@return string
local get_source_url = function(spec)
  local src, err = normalize_source(spec)
  if not src then
    utils.schedule_notify(err, vim.log.levels.ERROR)
    error(err)
  end
  return src
end

---@param spec Spec
---@param src string
local index_spec = function(spec, src)
  table.insert(state.vim_packs, { src = src, version = spec.version, name = spec.name })

  if not check_condition(spec) then
    return
  end

  if not lazy.is_lazy(spec) then
    if spec.config then
      table.insert(state.src_with_startup_config, src)
    end

    if spec.init then
      table.insert(state.src_with_startup_init, src)
    end

    if spec.keys then
      local keys = (spec.keys[1] and type(spec.keys[1]) == "string") and { spec.keys } or spec.keys --[[@as KeySpec[] ]]
      for _, key in ipairs(keys) do
        table.insert(state.startup_keys, key)
      end
    end
  end
end

---Check if value is a single spec (not a list of specs)
---@param value Spec|Spec[]
---@return boolean
local is_single_spec = function(value)
  return type(value[1]) == "string"
      or value.src ~= nil
      or value.dir ~= nil
      or value.url ~= nil
end

---@param spec_item_or_list Spec|Spec[]
M.import_specs = function(spec_item_or_list)
  local specs = is_single_spec(spec_item_or_list)
      and { spec_item_or_list }
      or spec_item_or_list --[[@as Spec[] ]]

  for _, spec in ipairs(specs) do
    if not is_enabled(spec) then
      goto continue
    end

    local src = get_source_url(spec)
    state.spec_registry[src] = { spec = spec, loaded = false }
    index_spec(spec, src)

    ::continue::
  end
end

return M
