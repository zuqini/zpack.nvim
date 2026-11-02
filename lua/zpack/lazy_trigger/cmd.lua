if jit then jit.off(true, true) end

local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.plugin_loader')
local cmd_proxy = require('zpack.cmd_proxy')

local M = {}

---@class zpack.ParsedCmd
---@field names string[] Every string, each of which gets a proxy; a bad name reports itself there
---@field usable boolean Whether one is a name nvim_create_user_command takes
---@field invalid string[] Non-empty strings it doesn't take
---@field not_strings any[]

---@param cmd any
---@return zpack.ParsedCmd?
M.parse = function(cmd)
  if not cmd then
    return nil
  end
  local parsed = { names = {}, usable = false, invalid = {}, not_strings = {} }
  local names = util.normalize_string_list(cmd)
  for _, name in ipairs(type(names) == 'table' and names or {}) do
    if type(name) ~= 'string' then
      parsed.not_strings[#parsed.not_strings + 1] = name
    else
      parsed.names[#parsed.names + 1] = name
      if name:find('^%u%w*$') then
        parsed.usable = true
      elseif name ~= '' then
        parsed.invalid[#parsed.invalid + 1] = name
      end
    end
  end
  return parsed
end

---@param registered_pack_specs vim.pack.Spec[]
M.setup = function(registered_pack_specs)
  local cmd_to_pack_specs = {}
  for _, pack_spec in ipairs(registered_pack_specs) do
    local label = pack_spec.name or pack_spec.src
    local registry_entry = state.spec_registry[pack_spec.src]
    local parsed = util.read_trigger(registry_entry, 'cmd', M.parse, registry_entry.plugin, label)
    if parsed then
      for _, c in ipairs(parsed.not_strings) do
        util.schedule_notify(
          ("Invalid cmd for %s: expected string, got %s"):format(label, type(c)),
          vim.log.levels.ERROR
        )
      end
      for _, c in ipairs(parsed.names) do
        if not cmd_to_pack_specs[c] then
          cmd_to_pack_specs[c] = {}
        end
        table.insert(cmd_to_pack_specs[c], pack_spec)
      end
    end
  end

  -- A cmd function can load a plugin by requiring its modules, whose own command
  -- a proxy would replace or collide with.
  for cmd, pack_specs in pairs(cmd_to_pack_specs) do
    local waiting = vim.tbl_filter(function(pack_spec)
      return state.spec_registry[pack_spec.src].load_status ~= 'loaded'
    end, pack_specs)
    cmd_to_pack_specs[cmd] = #waiting > 0 and waiting or nil
  end

  -- Proxy is registered with bang + range + addr='other' so the cmdline parser
  -- accepts `:Foo!` / `:1,5Foo` / `:%Foo` without erroring at parse time (which
  -- would prevent the plugin from ever loading). A `count` declaration would
  -- read a numeric first arg as the count, and the default addr='lines' rejects
  -- `:5Foo` in a buffer shorter than 5 lines with E16. addr='other' has its own
  -- limit: marks and patterns, `:'<,'>Foo` or `:/x/Foo`, are E16 here even when
  -- the real command takes them. `register = true` is NOT set: it would
  -- destructively consume the first arg char as a register and corrupt every
  -- non-register invocation. Tradeoff: the typed register is silently dropped
  -- on the first lazy invocation of a register-accepting command — subsequent
  -- calls go through the real command directly.
  for cmd, pack_specs in pairs(cmd_to_pack_specs) do
    -- Loading the claiming plugins tears down the proxy and lets the real
    -- command's callback/complete take over. Shared by the invocation
    -- callback and the tab-completion callback so first-tab completions
    -- come from the real command, not an empty proxy.
    local function load_plugins()
      cmd_proxy.drop(cmd)
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
        -- correctly handles the bare `:5Foo` count form, which the proxy
        -- reports as cmd_args.range == 1, line1 == 5.
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
        desc = cmd_proxy.DESC,
        nargs = '*',
        bang = true,
        range = true,
        addr = 'other',
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
      cmd_proxy.claim(cmd, pack_specs)
    end)
  end
end

return M
