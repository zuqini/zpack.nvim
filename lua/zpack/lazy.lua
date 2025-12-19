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
  return (spec.event ~= nil) or (spec.cmd ~= nil) or (spec.keys ~= nil and #spec.keys > 0) or (spec.ft ~= nil)
end

---@param pack_spec vim.pack.Spec
M.process_spec = function(pack_spec)
  -- Guard against multiple triggers loading the same plugin
  if state.src_spec[pack_spec.src].loaded then
    return
  end
  local spec = state.src_spec[pack_spec.src].spec

  if spec.init then
    hooks.try_call_hook(pack_spec.src, 'init')
  end

  vim.cmd.packadd(pack_spec.name)

  if spec.config then
    hooks.try_call_hook(pack_spec.src, 'config')
  end

  if spec.keys then
    keymap.apply_keys(spec.keys)
  end

  state.src_spec[pack_spec.src].loaded = true
end

---@param value any
---@return boolean
local is_event_spec = function(value)
  return type(value) == "table" and value.event ~= nil
end

---@param spec Spec
---@return NormalizedEvent[]
local normalize_and_apply_fallback_pattern = function(spec)
  local result = {}
  local fallback_pattern = spec.pattern or '*'

  if not spec.event then
    return result
  end

  local event_list = (type(spec.event) == "string" or is_event_spec(spec.event))
      and { spec.event }
      or spec.event --[[@as string[]|EventSpec[] ]]

  for _, event in ipairs(event_list) do
    if type(event) == "string" then
      table.insert(result, {
        events = { event },
        pattern = fallback_pattern
      })
    elseif is_event_spec(event) then
      table.insert(result, {
        events = util.normalize_string_list(event.event),
        pattern = event.pattern or fallback_pattern
      })
    end
  end

  return result
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

---@param pack_spec vim.pack.Spec
---@param spec Spec
local setup_event_loading = function(pack_spec, spec)
  local normalized_events = normalize_and_apply_fallback_pattern(spec)

  for _, normalized_event in ipairs(normalized_events) do
    local has_very_lazy, other_events = split_very_lazy(normalized_event.events)

    if has_very_lazy then
      vim.api.nvim_create_autocmd("UIEnter", {
        group = state.lazy_group,
        once = true,
        callback = function()
          vim.schedule(function()
            M.process_spec(pack_spec)
          end)
        end,
      })
    end

    if #other_events > 0 then
      vim.api.nvim_create_autocmd(other_events, {
        group = state.lazy_group,
        once = true,
        pattern = normalized_event.pattern,
        callback = function()
          M.process_spec(pack_spec)
        end,
      })
    end
  end
end

---@param pack_spec vim.pack.Spec
---@param spec Spec
local setup_ft_loading = function(pack_spec, spec)
  local filetypes = util.normalize_string_list(spec.ft)

  vim.api.nvim_create_autocmd("FileType", {
    group = state.lazy_group,
    pattern = filetypes,
    once = true,
    callback = function(ev)
      M.process_spec(pack_spec)

      -- Re-trigger events for the buffer that triggered loading to ensure LSP/Treesitter attach
      vim.schedule(function()
        local bufnr = ev.buf
        vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })
        vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
        vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
      end)
    end,
  })
end

---Build a mapping of command names to all plugins that lazy-load on that command
---@param registered_pack_specs vim.pack.Spec[] Array of registered plugin objects from vim.pack.add
---@return table<string, vim.pack.Spec[]>
local build_cmd_mapping = function(registered_pack_specs)
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
  return cmd_to_pack_specs
end

---@param cmd_to_pack_specs table<string, vim.pack.Spec[]>
local setup_shared_cmd_loading = function(cmd_to_pack_specs)
  for cmd, pack_specs in pairs(cmd_to_pack_specs) do
    vim.api.nvim_create_user_command(cmd, function(cmd_args)
      pcall(vim.api.nvim_del_user_command, cmd)

      for _, pack_spec in ipairs(pack_specs) do
        M.process_spec(pack_spec)
      end

      pcall(vim.api.nvim_cmd, {
        cmd = cmd,
        args = cmd_args.fargs,
      }, {})
    end, {})
  end
end

---Build a mapping of keys to all plugins that lazy-load on that key
---@param registered_pack_specs vim.pack.Spec[] Array of registered plugin objects from vim.pack.add
---@return table<string, {pack_specs: vim.pack.Spec[], key_spec: KeySpec}>
local build_key_mapping = function(registered_pack_specs)
  local key_to_info = {}
  for _, pack_spec in ipairs(registered_pack_specs) do
    local spec = state.src_spec[pack_spec.src].spec
    if spec.keys then
      local keys = util.normalize_keys(spec.keys) --[[@as KeySpec[] ]]
      for _, key in ipairs(keys) do
        local lhs = key[1]
        local mode = key.mode or 'n'
        local modes = util.normalize_string_list(mode) --[[@as string[] ]]

        for _, m in ipairs(modes) do
          local key_id = lhs .. ":" .. m
          if not key_to_info[key_id] then
            key_to_info[key_id] = {
              pack_specs = {},
              key_spec = key,
            }
          end
          table.insert(key_to_info[key_id].pack_specs, pack_spec)
        end
      end
    end
  end
  return key_to_info
end

---@param key_to_info table<string, {pack_specs: vim.pack.Spec[], key_spec: KeySpec}>
local setup_shared_key_loading = function(key_to_info)
  for key_id, key_info in pairs(key_to_info) do
    local lhs = key_info.key_spec[1]
    local rhs = key_info.key_spec[2]
    local mode = key_id:match(":(.+)$")
    local desc = key_info.key_spec.desc

    vim.keymap.set(mode, lhs, function()
      pcall(vim.keymap.del, mode, lhs)

      for _, pack_spec in ipairs(key_info.pack_specs) do
        M.process_spec(pack_spec)
      end

      if rhs then
        vim.keymap.set(mode, lhs, rhs, { desc = desc })
      end
      vim.api.nvim_feedkeys(vim.keycode(lhs), 'm', false)
    end, { desc = desc })
  end
end

---@return vim.pack.Spec[]
local register_lazy_packs = function()
  local registered_plugins = {}
  vim.pack.add(state.lazy_packs, {
    load = function(plugin)
      local pack_spec = plugin.spec
      local spec = state.src_spec[pack_spec.src].spec
      if state.src_to_request_build[pack_spec.src] then
        -- requested build, do not lazy load this
        M.process_spec(pack_spec)
        return
      end

      table.insert(registered_plugins, pack_spec)
      if spec.event then
        setup_event_loading(plugin.spec, spec)
      end
      if spec.ft then
        setup_ft_loading(plugin.spec, spec)
      end
    end
  })
  return registered_plugins
end

M.process_all = function()
  table.sort(state.lazy_packs, util.compare_priority)
  local registered_pack_specs = register_lazy_packs()
  local cmd_to_pack_specs = build_cmd_mapping(registered_pack_specs)
  setup_shared_cmd_loading(cmd_to_pack_specs)
  local key_to_info = build_key_mapping(registered_pack_specs)
  setup_shared_key_loading(key_to_info)
end

return M
