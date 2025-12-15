-- inspired by https://www.reddit.com/r/neovim/comments/1mx71rc/how_i_vastly_improved_my_lazy_loading_experience/
local util = require('zpack.util')
local state = require('zpack.state')
local hooks = require('zpack.hooks')
local keymap = require('zpack.keymap')

local M = {}

---@param spec Spec
---@return boolean
M.is_lazy = function(spec)
  if spec.lazy ~= nil then
    return spec.lazy
  end
  return (spec.event ~= nil) or (spec.cmd ~= nil) or (spec.keys ~= nil and #spec.keys > 0)
end

---@param vim_spec vim.pack.Spec
M.process_spec = function(vim_spec)
  local spec = state.src_spec[vim_spec.src]

  if spec.init then
    hooks.try_call_hook(vim_spec.src, 'init')
  end

  vim.cmd.packadd(vim_spec.name)

  if spec.config then
    hooks.try_call_hook(vim_spec.src, 'config')
  end

  if spec.build then
    hooks.execute_build(vim_spec.src, spec.build)
  end

  if spec.keys then
    keymap.apply_keys(spec.keys)
  end
end

---@param events string[]
---@return boolean, string[]
local split_very_lazy = function(events)
  local has_very_lazy = false
  local other_events = {}

  for _, event in ipairs(events) do
    if event == "VeryLazy" then
      has_very_lazy = true
    else
      table.insert(other_events, event)
    end
  end

  return has_very_lazy, other_events
end

---@param vim_spec vim.pack.Spec
---@param spec Spec
local setup_event_loading = function(vim_spec, spec)
  local events = type(spec.event) == "string" and { spec.event } or spec.event --[[@as string[] ]]

  local has_very_lazy, other_events = split_very_lazy(events)

  if has_very_lazy then
    vim.api.nvim_create_autocmd("UIEnter", {
      group = state.lazy_group,
      once = true,
      callback = function()
        vim.schedule(function()
          M.process_spec(vim_spec)
        end)
      end,
    })
  end

  if #other_events > 0 then
    vim.api.nvim_create_autocmd(other_events, {
      group = state.lazy_group,
      once = true,
      pattern = spec.pattern or '*',
      callback = function()
        M.process_spec(vim_spec)
      end,
    })
  end
end

---@param vim_spec vim.pack.Spec
---@param spec Spec
local setup_cmd_loading = function(vim_spec, spec)
  local commands = type(spec.cmd) == "string" and { spec.cmd } or spec.cmd --[[@as string[] ]]

  for _, cmd in ipairs(commands) do
    vim.api.nvim_create_user_command(cmd, function(cmd_args)
      local success, error_msg = pcall(vim.api.nvim_del_user_command, cmd)
      if not success then
        util.schedule_notify(("Failed to delete user command %s"):format(cmd, error_msg), vim.log.levels.ERROR)
      end

      M.process_spec(vim_spec)

      vim.api.nvim_cmd({
        cmd = cmd,
        args = cmd_args.fargs,
      }, {})
    end, {})
  end
end

---@param vim_spec vim.pack.Spec
---@param spec Spec
local setup_key_loading = function(vim_spec, spec)
  local keys = (spec.keys[1] and type(spec.keys[1]) == "string") and { spec.keys } or spec.keys --[[@as KeySpec[] ]]

  for _, key in ipairs(keys) do
    local lhs = key[1]
    local mode = key.mode or 'n'
    local modes = type(mode) == "string" and { mode } or mode --[[@as string[] ]]

    for _, m in ipairs(modes) do
      vim.keymap.set(m, lhs, function()
        vim.keymap.del(m, lhs)
        M.process_spec(vim_spec)
        vim.api.nvim_feedkeys(vim.keycode(lhs), 'm', false)
      end, { desc = key.desc })
    end
  end
end

M.process_all = function()
  -- Sort lazy packs by priority (higher priority = registered first)
  table.sort(state.lazy_packs, util.compare_priority)

  vim.pack.add(state.lazy_packs, {
    load = function(plugin)
      local spec = state.src_spec[plugin.spec.src]

      if spec.event then
        setup_event_loading(plugin.spec, spec)
      end

      if spec.cmd then
        setup_cmd_loading(plugin.spec, spec)
      end

      if spec.keys then
        setup_key_loading(plugin.spec, spec)
      end
    end
  })
end

return M
