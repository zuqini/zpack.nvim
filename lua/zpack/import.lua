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

---@param spec Spec
---@return string
local get_source_url = function(spec)
  return spec.src and spec.src or 'https://github.com/' .. spec[1]
end

---@param spec Spec
---@param src string
local categorize_spec = function(spec, src)
  if lazy.is_lazy(spec) then
    table.insert(state.lazy_packs, { src = src, version = spec.version, name = spec.name })
  else
    table.insert(state.startup_packs, { src = src, version = spec.version, name = spec.name })

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

---@param spec_item_or_list Spec|Spec[]
M.import_specs = function(spec_item_or_list)
  local specs = (type(spec_item_or_list[1]) == "string" or spec_item_or_list.src)
      and { spec_item_or_list }
      or spec_item_or_list --[[@as Spec[] ]]

  for _, spec in ipairs(specs) do
    if not is_enabled(spec) then
      goto continue
    end

    if not check_condition(spec) then
      goto continue
    end

    local src = get_source_url(spec)
    state.src_spec[src] = spec
    categorize_spec(spec, src)

    ::continue::
  end
end

return M
