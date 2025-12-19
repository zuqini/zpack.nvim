local util = require('zpack.utils')
local state = require('zpack.state')
local keymap = require('zpack.keymap')
local loader = require('zpack.loader')

local M = {}

---Create a unique key identifier from lhs and mode
---@param lhs string The key mapping (e.g., "<leader>ff")
---@param mode string The mode (e.g., "n", "v")
---@return string Unique identifier
local create_key_id = function(lhs, mode)
  return lhs .. '-' .. mode
end

---@param registered_pack_specs vim.pack.Spec[]
M.setup = function(registered_pack_specs)
  -- Build mapping of keys to plugins
  local key_to_info = {}
  for _, pack_spec in ipairs(registered_pack_specs) do
    local spec = state.src_spec[pack_spec.src].spec
    if spec.keys then
      local keys = util.normalize_keys(spec.keys) --[[@as KeySpec[] ]]
      for _, key in ipairs(keys) do
        local lhs = key[1]
        local mode = key.mode or 'n'
        local modes = util.normalize_string_list(mode) --[[@as string[] ]]

        -- Split modes because different plugins might use same key in different modes
        for _, m in ipairs(modes) do
          local key_id = create_key_id(lhs, m)
          if not key_to_info[key_id] then
            key_to_info[key_id] = {
              split_mode = m,
              pack_specs = {},
              key_spec = key,
            }
          end
          table.insert(key_to_info[key_id].pack_specs, pack_spec)
        end
      end
    end
  end

  -- Create keymaps
  for _, key_info in pairs(key_to_info) do
    local lhs = key_info.key_spec[1]
    keymap.map(lhs, function()
      pcall(vim.keymap.del, key_info.split_mode, lhs)
      for _, pack_spec in ipairs(key_info.pack_specs) do
        loader.process_spec(pack_spec)
      end
      vim.api.nvim_feedkeys(vim.keycode(lhs), 'm', false)
    end, false, key_info.key_spec.desc, key_info.split_mode, false)
  end
end

return M
