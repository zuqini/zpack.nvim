---@diagnostic disable: duplicate-set-field
local luassert = require('luassert')
local say = require('say')

local M = {}

-- `assert.contains(tbl, value)` — a list-membership assertion luassert has no
-- built-in for. Registered as a real luassert assertion (rather than a bare
-- helper that raises via error()) so a failed containment check is classified
-- by busted as a 'failure', not an 'error', like every other assertion.
local function table_contains(_, arguments)
  local tbl = arguments[1]
  if type(tbl) ~= 'table' then
    return false
  end
  for _, v in ipairs(tbl) do
    if v == arguments[2] then
      return true
    end
  end
  return false
end

say:set('assertion.contains.positive', 'Expected table to contain value.\nTable:\n%s\nValue:\n%s')
say:set('assertion.contains.negative', 'Expected table to not contain value.\nTable:\n%s\nValue:\n%s')
luassert:register('assertion', 'contains', table_contains,
  'assertion.contains.positive', 'assertion.contains.negative')

function M.setup_test_env()
  _G.test_state = {
    loaded_plugins = {},
    executed_hooks = {},
    created_commands = {},
    created_keymaps = {},
    triggered_events = {},
    vim_pack_calls = {},
    notifications = {},
  }

  vim.g.mapleader = ' '

  _G.test_state.original_notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(_G.test_state.notifications, { msg = msg, level = level })
  end

  _G.test_state.original_vim_pack_add = vim.pack.add
  vim.pack.add = function(specs, opts)
    table.insert(_G.test_state.vim_pack_calls, specs)
    opts = opts or {}

    for _, pack_spec in ipairs(specs) do
      local name = pack_spec.name or pack_spec.src:match('[^/]+$')
      pack_spec.name = name
      _G.test_state.registered_pack_specs[name] = pack_spec
      local mock_plugin = {
        spec = pack_spec,
        path = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/' .. name,
        name = name,
      }

      if opts.load then
        opts.load(mock_plugin)
      end
    end
  end

  _G.test_state.original_vim_cmd_packadd = vim.cmd.packadd
  vim.cmd.packadd = function(args)
    local plugin_name = type(args) == 'table' and args[1] or args
    table.insert(_G.test_state.loaded_plugins, plugin_name)
  end

  _G.test_state.original_vim_pack_get = vim.pack.get
  _G.test_state.registered_pack_specs = {}
  _G.test_state.pack_revs = {}
  vim.pack.get = function(names, _opts)
    local function make_entry(name, pack_spec)
      return {
        spec = pack_spec,
        path = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/' .. name,
        name = name,
        rev = _G.test_state.pack_revs[name] or ('mock-rev-' .. name),
      }
    end
    local results = {}
    if names == nil or #names == 0 then
      for name, pack_spec in pairs(_G.test_state.registered_pack_specs) do
        table.insert(results, make_entry(name, pack_spec))
      end
    else
      for _, name in ipairs(names) do
        local pack_spec = _G.test_state.registered_pack_specs[name]
        if pack_spec then
          table.insert(results, make_entry(name, pack_spec))
        end
      end
    end
    return #results > 0 and results or {}
  end

  _G.test_state.original_vim_pack_del = vim.pack.del
  _G.test_state.vim_pack_del_calls = {}
  vim.pack.del = function(names, opts)
    table.insert(_G.test_state.vim_pack_del_calls, { names = names, opts = opts })
    for _, name in ipairs(names) do
      local pack_spec = _G.test_state.registered_pack_specs[name]
      _G.test_state.registered_pack_specs[name] = nil
      -- Mirror real vim.pack.del: fire PackChanged for each removed plugin.
      if pack_spec then
        vim.api.nvim_exec_autocmds('PackChanged', {
          data = { kind = 'delete', spec = pack_spec },
        })
      end
    end
  end

  _G.test_state.original_vim_pack_update = vim.pack.update
  _G.test_state.vim_pack_update_calls = {}
  vim.pack.update = function(names, opts)
    table.insert(_G.test_state.vim_pack_update_calls, { names = names, opts = opts })
  end
end

function M.cleanup_test_env()
  -- Clear autocmds before reloading modules
  if package.loaded['zpack.state'] then
    local state = package.loaded['zpack.state']
    if state.lazy_group then
      vim.api.nvim_clear_autocmds({ group = state.lazy_group })
    end
    if state.startup_group then
      vim.api.nvim_clear_autocmds({ group = state.startup_group })
    end
    if state.lazy_build_group then
      vim.api.nvim_clear_autocmds({ group = state.lazy_build_group })
    end
    if state.delete_group then
      vim.api.nvim_clear_autocmds({ group = state.delete_group })
    end
  end

  -- Restore original vim.pack.add, vim.pack.get, vim.cmd.packadd, and vim.notify
  if _G.test_state then
    if _G.test_state.original_vim_pack_add then
      vim.pack.add = _G.test_state.original_vim_pack_add
    end
    if _G.test_state.original_vim_pack_get then
      vim.pack.get = _G.test_state.original_vim_pack_get
    end
    if _G.test_state.original_vim_pack_del then
      vim.pack.del = _G.test_state.original_vim_pack_del
    end
    if _G.test_state.original_vim_pack_update then
      vim.pack.update = _G.test_state.original_vim_pack_update
    end
    if _G.test_state.original_vim_cmd_packadd then
      vim.cmd.packadd = _G.test_state.original_vim_cmd_packadd
    end
    if _G.test_state.original_notify then
      vim.notify = _G.test_state.original_notify
    end
  end

  _G.test_state = nil

  M.delete_zpack_commands()

  -- Force reload all zpack modules to reset state
  package.loaded['zpack.state'] = nil
  package.loaded['zpack'] = nil
  package.loaded['zpack.import'] = nil
  package.loaded['zpack.registration'] = nil
  package.loaded['zpack.startup'] = nil
  package.loaded['zpack.lazy'] = nil
  package.loaded['zpack.hooks'] = nil
  package.loaded['zpack.plugin_loader'] = nil
  package.loaded['zpack.lazy_trigger.event'] = nil
  package.loaded['zpack.lazy_trigger.ft'] = nil
  package.loaded['zpack.lazy_trigger.refire'] = nil
  package.loaded['zpack.lazy_trigger.cmd'] = nil
  package.loaded['zpack.lazy_trigger.keys'] = nil
  package.loaded['zpack.keymap'] = nil
  package.loaded['zpack.utils'] = nil
  package.loaded['zpack.commands'] = nil
  package.loaded['zpack.deprecation'] = nil
  package.loaded['zpack.merge'] = nil
  package.loaded['zpack.module_loader'] = nil
  package.loaded['zpack.api'] = nil

  -- Remove our module loader from package.loaders if present
  for i = #package.loaders, 1, -1 do
    local loader = package.loaders[i]
    if type(loader) == "function" then
      local info = debug.getinfo(loader, "S")
      if info and info.source and info.source:find("module_loader") then
        table.remove(package.loaders, i)
      end
    end
  end
end

function M.wait_for_condition(condition, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 1000
  interval_ms = interval_ms or 10

  local start = vim.loop.now()
  while vim.loop.now() - start < timeout_ms do
    vim.wait(interval_ms)
    if condition() then
      return true
    end
  end
  return false
end

function M.flush_pending()
  -- Process all pending vim.schedule callbacks by waiting with a condition that
  -- never returns true. 50ms is sufficient for most deferred operations while
  -- keeping tests fast. The condition returns false to ensure we always wait
  -- the full duration, allowing all queued callbacks to execute.
  vim.wait(50, function() return false end)
end

function M.find_autocmd(autocmds, event, pattern)
  for _, cmd in ipairs(autocmds) do
    if cmd.event == event then
      if pattern == nil then
        return cmd
      end
      -- Pattern can be a single value or comma-separated list
      if cmd.pattern == pattern or (cmd.pattern and cmd.pattern:find(pattern, 1, true)) then
        return cmd
      end
    end
  end
  return nil
end

function M.create_mock_plugin_dir(name, modules)
  local base_path = vim.fn.tempname()
  vim.fn.mkdir(base_path, 'p')
  local plugin_path = base_path .. '/' .. name
  vim.fn.mkdir(plugin_path .. '/lua', 'p')

  for _, mod_name in ipairs(modules) do
    local mod_path = plugin_path .. '/lua/' .. mod_name .. '.lua'
    local f = io.open(mod_path, 'w')
    if f then
      f:write('return {}')
      f:close()
    end
  end

  return plugin_path, base_path
end

function M.cleanup_mock_plugin_dir(base_path)
  vim.fn.delete(base_path, 'rf')
end

---@param cmd_name? string Primary command name registered by `setup` (default 'ZPack').
---@param legacy_prefix? string Prefix for the deprecated :<Prefix><Suffix> commands (default 'Z').
function M.delete_zpack_commands(cmd_name, legacy_prefix)
  cmd_name = cmd_name or 'ZPack'
  legacy_prefix = legacy_prefix or 'Z'
  pcall(vim.api.nvim_del_user_command, cmd_name)
  for _, suffix in ipairs({ 'Update', 'Restore', 'Clean', 'Build', 'Load', 'Delete' }) do
    pcall(vim.api.nvim_del_user_command, legacy_prefix .. suffix)
  end
end

return M
