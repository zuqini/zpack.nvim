local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.plugin_loader')

local M = {}

---Split the strings in `cmd` into names nvim_create_user_command takes and the rest.
---@param cmd any
---@return string[] valid, string[] invalid
local function classify_names(cmd)
  local valid, invalid = {}, {}
  local names = util.normalize_string_list(cmd)
  for _, name in ipairs(type(names) == 'table' and names or {}) do
    if type(name) == 'string' and name ~= '' then
      local list = name:find('^%u%w*$') and valid or invalid
      list[#list + 1] = name
    end
  end
  return valid, invalid
end

---@param cmd any
---@return boolean
M.has_commands = function(cmd)
  return #classify_names(cmd) > 0
end

---@param cmd any
---@return string[]
M.invalid_commands = function(cmd)
  local _, invalid = classify_names(cmd)
  return invalid
end

---@param registered_pack_specs vim.pack.Spec[]
M.setup = function(registered_pack_specs)
  local cmd_to_pack_specs = {}
  for _, pack_spec in ipairs(registered_pack_specs) do
    local registry_entry = state.spec_registry[pack_spec.src]
    local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
    local plugin = registry_entry.plugin

    local cmd = util.try_resolve_field(spec.cmd, plugin, pack_spec.name or pack_spec.src, 'cmd')
    if cmd then
      local commands = util.normalize_string_list(cmd) --[[@as string[] ]]
      for _, c in ipairs(type(commands) == 'table' and commands or {}) do
        if type(c) ~= 'string' then
          util.schedule_notify(
            ("Invalid cmd for %s: expected string, got %s"):format(pack_spec.name or pack_spec.src, type(c)),
            vim.log.levels.ERROR
          )
        else
          if not cmd_to_pack_specs[c] then
            cmd_to_pack_specs[c] = {}
          end
          table.insert(cmd_to_pack_specs[c], pack_spec)
        end
      end
    end
  end

  -- Proxy is registered with bang + count=-1 so the cmdline parser accepts
  -- `:Foo!` / `:1,5Foo` / `:5Foo` without erroring at parse time (which
  -- would prevent the plugin from ever loading). count=-1 also implicitly
  -- accepts a range form (Neovim documents that count-decl commands take
  -- `:1,3Foo` and treat the range's end as the count). `register = true`
  -- is NOT set: it would destructively consume the first arg char as a
  -- register and corrupt every non-register invocation. Tradeoff: the
  -- typed register is silently dropped on the first lazy invocation of a
  -- register-accepting command — subsequent calls go through the real
  -- command directly. `:%Foo` (the whole-buffer range) is also not
  -- accepted by count=-1; range=true is the alternative but rejects the
  -- bare `:5Foo` count form that LazyVim-style users commonly type.
  for cmd, pack_specs in pairs(cmd_to_pack_specs) do
    -- Loading the claiming plugins tears down the proxy and lets the real
    -- command's callback/complete take over. Shared by the invocation
    -- callback and the tab-completion callback so first-tab completions
    -- come from the real command, not an empty proxy.
    local function load_plugins()
      state.drop_cmd_proxy(cmd)
      local any_ok = false
      for _, pack_spec in ipairs(pack_specs) do
        if loader.try_process_spec(pack_spec) then
          any_ok = true
        end
      end
      return any_ok
    end

    util.try_trigger_setup(pack_specs[1].name or pack_specs[1].src, 'cmd', function()
      vim.api.nvim_create_user_command(cmd, function(cmd_args)
        -- Build the dispatch struct from the proxy invocation before loading,
        -- so a load failure can't lose typed args. Forwards `range` (not
        -- `count`): nvim_cmd auto-translates range to count for count-decl
        -- real commands, but forwarding count to a range-decl command would
        -- error with "Command cannot accept count". The range-only path also
        -- correctly handles the bare `:5Foo` count form, since count=-1
        -- proxies report cmd_args.range == 1, line1 == 5.
        local command = {
          cmd = cmd,
          bang = cmd_args.bang or nil,
          mods = cmd_args.smods --[[@as vim.api.keyset.cmd.mods]],
          args = cmd_args.fargs,
          range = (cmd_args.range or 0) > 0
              and (cmd_args.range == 1 and { cmd_args.line1 } or { cmd_args.line1, cmd_args.line2 })
              or nil,
        }

        -- Proxy already self-deleted; nvim_cmd would error with "Not an
        -- editor command" on top of the per-plugin load-failure notify.
        if not load_plugins() then
          return
        end

        -- lazy.nvim spec parity (handler/cmd.lua:44-47): after loading the
        -- real command, consult its nargs. For `nargs = '1'` or `nargs = '?'`,
        -- the proxy's whitespace-split fargs are re-packed into a single arg
        -- string so :Foo hello world stays one arg. Without this, a nargs=1
        -- real command would reject the proxy-fired call as "too many
        -- arguments" on first invocation only.
        local info = vim.api.nvim_get_commands({})[cmd]
            or vim.api.nvim_buf_get_commands(0, {})[cmd]
        if info and cmd_args.args and cmd_args.args ~= ""
            and info.nargs and info.nargs:find("[1?]") then
          command.args = { cmd_args.args }
        end

        local ok, err = pcall(vim.api.nvim_cmd, command, {})
        if not ok then
          util.schedule_notify(("Failed to re-fire :%s: %s"):format(cmd, tostring(err)), vim.log.levels.ERROR)
        end
      end, {
        desc = state.CMD_PROXY_DESC,
        nargs = '*',
        bang = true,
        count = -1,
        -- Tabbing at the cmdline loads the plugin so the real command's
        -- complete handler can return actual completions on the first press,
        -- matching lazy.nvim's UX (handler/cmd.lua complete callback).
        complete = function(_, line)
          if not load_plugins() then
            return {}
          end
          return vim.fn.getcompletion(line, 'cmdline')
        end,
      })
      state.live_cmd_proxies[cmd] = {}
      for _, pack_spec in ipairs(pack_specs) do
        state.live_cmd_proxies[cmd][pack_spec.src] = true
        local proxies = state.cmd_proxies[pack_spec.src] or {}
        state.cmd_proxies[pack_spec.src] = proxies
        proxies[#proxies + 1] = cmd
      end
    end)
  end
end

return M
