local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.loader')

local M = {}

---@param registered_pack_specs vim.pack.Spec[]
M.setup = function(registered_pack_specs)
  -- Build mapping of command names to plugins
  local cmd_to_pack_specs = {}
  for _, pack_spec in ipairs(registered_pack_specs) do
    local spec = state.src_spec[pack_spec.src].spec
    if spec.cmd then
      local commands = util.normalize_string_list(spec.cmd) --[[@as string[] ]]
      for _, cmd in ipairs(commands) do
        if not cmd_to_pack_specs[cmd] then
          cmd_to_pack_specs[cmd] = {}
        end
        table.insert(cmd_to_pack_specs[cmd], pack_spec)
      end
    end
  end

  -- Create user commands
  for cmd, pack_specs in pairs(cmd_to_pack_specs) do
    vim.api.nvim_create_user_command(cmd, function(cmd_args)
      pcall(vim.api.nvim_del_user_command, cmd)

      for _, pack_spec in ipairs(pack_specs) do
        loader.process_spec(pack_spec)
      end

      pcall(vim.api.nvim_cmd, {
        cmd = cmd,
        args = cmd_args.fargs,
      }, {})
    end, {})
  end
end

return M
