local helpers = require('helpers')

describe("Plugin Lifecycle Hooks", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("init hook runs before plugin loads", function()
    local init_ran = false
    local config_ran = false
    local init_ran_before_config = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          init = function()
            init_ran = true
            if not config_ran then
              init_ran_before_config = true
            end
          end,
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(init_ran, "init hook should run")
    assert.is_truthy(init_ran_before_config, "init should run before config")
  end)

  it("config hook runs after plugin loads", function()
    local config_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(config_ran, "config hook should run")
  end)

  it("init runs for lazy plugins at setup time", function()
    local init_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          init = function()
            init_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(init_ran, "init should run for lazy plugins at setup time")
  end)

  it("init runs only once for lazy plugins", function()
    local init_count = 0

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          init = function()
            init_count = init_count + 1
          end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(1, init_count)

    pcall(vim.cmd, 'TestCommand')
    helpers.flush_pending()
    assert.are.equal(1, init_count)
  end)

  it("config does not run for lazy plugins at setup time", function()
    local config_ran = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TestCommand',
          config = function()
            config_ran = true
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_falsy(config_ran, "config should not run for lazy plugins at setup time")
  end)

  it("build hook is string command", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          build = 'echo "build completed"',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec
    assert.is_not_nil(spec.build, "Build hook should be stored")
    assert.are.equal('string', type(spec.build))
  end)

  it("build hook is function", function()
    local build_fn = function() end

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          build = build_fn,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec
    assert.is_not_nil(spec.build, "Build hook should be stored")
    assert.are.equal('function', type(spec.build))
  end)

  it("init and config hooks work together", function()
    local execution_order = {}

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          init = function()
            table.insert(execution_order, 'init')
          end,
          config = function()
            table.insert(execution_order, 'config')
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(2, #execution_order)
    assert.are.equal('init', execution_order[1])
    assert.are.equal('config', execution_order[2])
  end)

  it("config hook can access plugin module", function()
    local can_access_globals = false

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function()
            can_access_globals = (vim ~= nil and vim.fn ~= nil)
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_truthy(can_access_globals, "config should have access to vim globals")
  end)

  -- Regression: vim.cmd.packadd in the eager startup loop used to be
  -- unprotected. One broken plugin (missing pack dir, throw in plugin/*.lua)
  -- aborted the entire loop, leaving every later plugin un-packadd'd and
  -- stranded at load_status="pending".
  it("startup eager loop continues after a packadd throws", function()
    local state = require('zpack.state')

    local original_packadd = vim.cmd.packadd
    vim.cmd.packadd = function(args)
      local name = type(args) == 'table' and args[1] or args
      if name == 'plugin-a' then
        error("simulated packadd failure for plugin-a", 0)
      end
      return original_packadd(args)
    end

    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
        { 'test/plugin-c' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.cmd.packadd = original_packadd

    -- plugin-b and plugin-c must reach load_status="loaded" despite plugin-a
    -- throwing earlier in the loop.
    assert.are.equal("loaded", state.spec_registry['https://github.com/test/plugin-b'].load_status,
      "plugin-b must load even though plugin-a threw in the same loop")
    assert.are.equal("loaded", state.spec_registry['https://github.com/test/plugin-c'].load_status,
      "plugin-c must load even though plugin-a threw in the same loop")

    -- The failing plugin must NOT be marked "loaded": the load_status
    -- finalization loop used to run unconditionally over every sorted pack,
    -- hiding packadd failures from :ZPack load and :checkhealth.
    assert.are_not.equal("loaded", state.spec_registry['https://github.com/test/plugin-a'].load_status,
      "plugin-a must not be marked loaded after its packadd threw")
    assert.is_not_nil(state.unloaded_plugin_names['plugin-a'],
      "plugin-a must remain in unloaded_plugin_names so :ZPack load can retry it")

    local saw_packadd_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to packadd plugin%-a") then
        saw_packadd_notify = true
        break
      end
    end
    assert.is_true(saw_packadd_notify, "packadd failure should surface a structured notify")
  end)

  -- Regression: keymap.apply_keys in the startup keys loop used to be
  -- unprotected. A malformed key spec throwing here would otherwise abort
  -- every later plugin's keymap application AND the load_status finalization
  -- loop right after it.
  it("startup apply_keys loop continues after one plugin's keys throw", function()
    local state = require('zpack.state')
    local keymap = require('zpack.keymap')

    local original_apply_keys = keymap.apply_keys
    keymap.apply_keys = function(keys, src)
      if keys and keys[1] and keys[1].__throw then
        error("simulated apply_keys failure", 0)
      end
      return original_apply_keys(keys, src)
    end

    -- lazy=false forces these onto the eager startup path despite having
    -- `keys`, so startup.process_all's apply_keys loop runs for them.
    require('zpack').setup({
      spec = {
        { 'test/plugin-a', lazy = false, keys = { { '<leader>xa', '<cmd>echo a<cr>', __throw = true } } },
        { 'test/plugin-b', lazy = false, keys = { { '<leader>xb', '<cmd>echo b<cr>' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    keymap.apply_keys = original_apply_keys

    assert.are.equal("loaded", state.spec_registry['https://github.com/test/plugin-b'].load_status,
      "plugin-b must reach 'loaded' even though plugin-a's apply_keys threw")

    local saw_keys_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to apply keys for plugin%-a") then
        saw_keys_notify = true
        break
      end
    end
    assert.is_true(saw_keys_notify, "apply_keys failure should surface a structured notify")
  end)

  -- Regression: startup's run_config loop used to call loader.run_config raw.
  -- merge.resolve_opts runs user-supplied function-form `opts` raw, so a throw
  -- escapes run_config, aborts the loop, and strands every later plugin un-
  -- configured but still marked "loaded" by the finalization loop.
  it("startup run_config loop continues after a function-form opts throws", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin-a',
          lazy = false,
          opts = function() error("simulated opts failure", 0) end,
          config = function() end,
        },
        {
          'test/plugin-b',
          lazy = false,
          config = function() _G._zpack_test_b_configured = true end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    assert.is_true(_G._zpack_test_b_configured == true,
      "plugin-b's config must run despite plugin-a's opts throwing")

    -- plugin-a's run_config threw; it must not be silently marked "loaded".
    assert.are_not.equal("loaded", state.spec_registry['https://github.com/test/plugin-a'].load_status,
      "plugin-a must not be marked loaded after its run_config threw")
    assert.is_not_nil(state.unloaded_plugin_names['plugin-a'],
      "plugin-a must remain in unloaded_plugin_names so :ZPack load can retry it")

    local saw_config_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to run config for plugin%-a") then
        saw_config_notify = true
        break
      end
    end
    assert.is_true(saw_config_notify, "run_config failure should surface a structured notify")

    _G._zpack_test_b_configured = nil
  end)

  -- Regression: a throw inside process_spec (e.g. packadd failing) used to
  -- leave load_status pinned at "loading" forever, so the next load attempt
  -- hit the misleading "Circular dependency detected" branch.
  it("process_spec resets load_status to pending on throw", function()
    local state = require('zpack.state')
    local loader = require('zpack.plugin_loader')

    require('zpack').setup({
      spec = { { 'test/plugin', cmd = 'TriggerLoad' } },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)

    local original_packadd = vim.cmd.packadd
    vim.cmd.packadd = function() error("simulated packadd failure", 0) end

    local pack_spec = state.src_to_pack_spec[src]
    local ok = loader.try_process_spec(pack_spec)

    vim.cmd.packadd = original_packadd

    assert.is_false(ok, "try_process_spec should report failure")
    assert.are.equal("pending", state.spec_registry[src].load_status,
      "load_status must reset so the retry isn't wedged into the 'circular dependency' branch")

    -- A second call must NOT hit the circular-dependency notify path.
    _G.test_state.notifications = {}
    loader.try_process_spec(pack_spec)
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(n.msg:find("Circular dependency"),
        "second call must not misreport as circular dependency")
    end
  end)

  -- Regression: util.resolve_field on function-form `keys` used to run outside
  -- the apply_keys pcall in startup.lua, so a throwing keys resolver would
  -- bubble out and strand every later plugin's apply_keys + finalization.
  it("startup apply_keys loop continues after a function-form keys resolver throws", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin-a', lazy = false, keys = function() error("simulated keys resolver failure", 0) end },
        { 'test/plugin-b', lazy = false, keys = { { '<leader>xb', '<cmd>echo b<cr>' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    assert.are.equal("loaded", state.spec_registry['https://github.com/test/plugin-b'].load_status,
      "plugin-b must reach 'loaded' even though plugin-a's keys resolver threw")

    local saw_resolve_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to resolve keys for") and n.msg:find("plugin%-a") then
        saw_resolve_notify = true
        break
      end
    end
    assert.is_true(saw_resolve_notify, "keys resolver failure should surface a structured notify")
  end)

  -- Regression: util.resolve_field on function-form `keys` used to run outside
  -- plugin_loader's apply_keys pcall — a throwing keys resolver would escape
  -- process_spec after load_status had already been committed, so
  -- try_process_spec would notify "Failed to load X" on a plugin that *did*
  -- load. The fix is try_resolve_field at the resolve site so the resolve
  -- failure is reported separately and the load path keeps its real status.
  it("lazy process_spec reports keys resolver failure separately from load", function()
    local state = require('zpack.state')
    local loader = require('zpack.plugin_loader')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          cmd = 'TriggerLoad',
          keys = function() error("simulated keys resolver failure", 0) end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local src = 'https://github.com/test/plugin'
    local pack_spec = state.src_to_pack_spec[src]
    _G.test_state.notifications = {}
    local ok = loader.try_process_spec(pack_spec)
    helpers.flush_pending()

    assert.is_true(ok, "process_spec must succeed (the plugin loads); only the keys resolve failed")
    assert.are.equal("loaded", state.spec_registry[src].load_status,
      "load_status must stay 'loaded'; the keys resolver runs after the commit")

    local saw_resolve_notify, saw_misleading_load_failure = false, false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to resolve keys for") then
        saw_resolve_notify = true
      end
      if n.msg:find("Failed to load") then
        saw_misleading_load_failure = true
      end
    end
    assert.is_true(saw_resolve_notify, "keys resolver failure should surface as a resolve notify")
    assert.is_false(saw_misleading_load_failure,
      "must not notify 'Failed to load' on a plugin that successfully loaded")
  end)

  -- Regression: execute_build used to run user-supplied vim cmd / function raw
  -- on a scheduled tick. A throwing build hook surfaced as a raw Neovim error
  -- stack trace instead of zpack's structured notify, inconsistent with every
  -- other lazy entry point.
  it("execute_build catches a throwing function-form build", function()
    local hooks = require('zpack.hooks')

    _G.test_state.notifications = {}
    hooks.execute_build(function() error("simulated build failure", 0) end, nil, 'test/plugin-x')
    helpers.flush_pending()

    local saw_build_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to run build for test/plugin%-x") then
        saw_build_notify = true
        break
      end
    end
    assert.is_true(saw_build_notify, "build failure should surface a structured notify")
  end)

  -- Regression: the lazy_trigger/event.lua and ft.lua sibling-loaded gate used
  -- to check `load_status == "loaded"` only. A plugin whose plugin/ files fire
  -- a sibling autocmd synchronously during packadd would re-enter the gate
  -- while load_status was still "loading" — the gate would miss and
  -- process_spec would take the "Circular dependency detected" notify branch.
  it("lazy event gate skips re-entry while load_status is 'loading'", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin', event = { 'BufEnter', 'FileType' } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local src = 'https://github.com/test/plugin'
    -- Pin the gate's contract directly: while a sibling event is mid-load,
    -- the other event's autocmd must not re-enter process_spec.
    state.spec_registry[src].load_status = "loading"
    _G.test_state.notifications = {}

    -- The 'event = { "BufEnter", "FileType" }' registration created a
    -- once-autocmd on FileType with pattern '*'. Fire it manually.
    vim.api.nvim_exec_autocmds('FileType', { pattern = 'lua' })

    -- Restore so cleanup doesn't observe a stuck 'loading' state.
    state.spec_registry[src].load_status = "pending"

    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(n.msg:find("Circular dependency"),
        "sibling gate must short-circuit on 'loading' instead of re-entering process_spec")
    end
  end)

  -- Regression: function-form spec.cmd / spec.keys / spec.event / spec.ft used
  -- to be resolved with the un-pcall'd util.resolve_field at registration sites
  -- (lazy.is_lazy, lazy.process_all, lazy_trigger.cmd.setup, lazy_trigger.keys
  -- .setup). A throw aborted setup() mid-flight, stranding every later plugin
  -- un-registered. try_resolve_field at the resolve sites now reports the
  -- failure and returns nil so registration continues.
  it("registration continues past a throwing function-form cmd/keys resolver", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin-a', cmd = function() error("simulated cmd resolver failure", 0) end },
        { 'test/plugin-b', cmd = 'TriggerB' },
        { 'test/plugin-c', keys = function() error("simulated keys resolver failure", 0) end },
        { 'test/plugin-d', keys = { { '<leader>xd', '<cmd>echo d<cr>' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    -- plugin-b and plugin-d should still be registered as lazy and waiting
    -- to be triggered. plugin-a / plugin-c, with broken resolvers, fall back
    -- to non-lazy registration but must NOT abort setup() for the rest.
    assert.is_not_nil(state.spec_registry['https://github.com/test/plugin-b'],
      "plugin-b must be registered even though plugin-a's cmd resolver threw")
    assert.is_not_nil(state.spec_registry['https://github.com/test/plugin-d'],
      "plugin-d must be registered even though plugin-c's keys resolver threw")

    local saw_cmd_resolve, saw_keys_resolve = false, false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to resolve cmd for") then
        saw_cmd_resolve = true
      end
      if n.msg:find("Failed to resolve keys for") then
        saw_keys_resolve = true
      end
    end
    assert.is_true(saw_cmd_resolve, "cmd resolver failure should surface a structured notify")
    assert.is_true(saw_keys_resolve, "keys resolver failure should surface a structured notify")
  end)

  -- Symmetric with the function-form build coverage above. A string-form
  -- `build = ":SomeCmd"` that errors at vim.cmd() must also surface as a
  -- structured notify, not a raw Neovim stack trace on a scheduled tick.
  it("execute_build catches a throwing string-form build", function()
    local hooks = require('zpack.hooks')

    _G.test_state.notifications = {}
    hooks.execute_build(":throw 'simulated string build failure'", nil, 'test/plugin-x')
    helpers.flush_pending()

    local saw_build_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to run build for test/plugin%-x") then
        saw_build_notify = true
        break
      end
    end
    assert.is_true(saw_build_notify, "string-form build failure should surface a structured notify")
  end)

  -- lazy.nvim spec parity: `build` strings prefixed with ':' are ex-commands;
  -- everything else is a shell command spawned in the plugin directory.
  it("execute_build with ':' prefix runs as an ex-command", function()
    local hooks = require('zpack.hooks')

    _G.test_state.ex_cmd_ran = false
    vim.api.nvim_create_user_command('ZPackBuildExCmdTest', function()
      _G.test_state.ex_cmd_ran = true
    end, {})

    hooks.execute_build(':ZPackBuildExCmdTest', nil, 'test/plugin-ex')
    helpers.flush_pending()

    pcall(vim.api.nvim_del_user_command, 'ZPackBuildExCmdTest')
    assert.is_true(_G.test_state.ex_cmd_ran, "':<ex>' build must run the ex-command")
  end)

  it("execute_build with non-':' string spawns a shell command", function()
    local hooks = require('zpack.hooks')

    local captured
    local original_system = vim.system
    vim.system = function(cmd, opts, on_exit)
      captured = { cmd = cmd, opts = opts, on_exit = on_exit }
      return setmetatable({}, { __index = function() return function() return { code = 0 } end end })
    end

    hooks.execute_build('echo hello', { path = '/tmp/zpack-test' }, 'test/plugin-sh')
    helpers.flush_pending()

    vim.system = original_system
    assert.is_not_nil(captured, "vim.system must be invoked for a non-':' build string")
    assert.are.equal('/tmp/zpack-test', captured.opts.cwd, "spawn must run inside plugin dir")
    -- Final cmd element is the user-supplied shell string
    assert.are.equal('echo hello', captured.cmd[#captured.cmd])
  end)

  it("execute_build iterates an array of steps in order", function()
    local hooks = require('zpack.hooks')

    local order = {}
    hooks.execute_build({
      function() table.insert(order, 'first') end,
      function() table.insert(order, 'second') end,
    }, nil, 'test/plugin-arr')
    helpers.flush_pending()

    assert.are.same({ 'first', 'second' }, order, "array build steps must run in declared order")
  end)

  it("execute_build skips when build is false", function()
    local hooks = require('zpack.hooks')

    local ran = false
    hooks.execute_build(false, { path = '/tmp' }, 'test/plugin-false')
    helpers.flush_pending()

    assert.is_false(ran, "build = false must be a no-op")
    _G.test_state.notifications = _G.test_state.notifications or {}
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(n.msg:find("Failed to run build for test/plugin%-false"))
    end
  end)

  it("execute_build mixed-type array dispatches each step independently", function()
    local hooks = require('zpack.hooks')

    _G.test_state.mixed_ran = false
    vim.api.nvim_create_user_command('ZPackBuildMixed', function()
      _G.test_state.mixed_ran = true
    end, {})
    local fn_ran = false

    hooks.execute_build({
      ':ZPackBuildMixed',
      function() fn_ran = true end,
    }, nil, 'test/plugin-mixed')
    helpers.flush_pending()

    pcall(vim.api.nvim_del_user_command, 'ZPackBuildMixed')
    assert.is_true(_G.test_state.mixed_ran, "ex-cmd step in mixed array must run")
    assert.is_true(fn_ran, "function step in mixed array must run")
  end)

  -- Regression: a user-supplied `enabled = function() ... end` that throws
  -- escaped check_enabled, aborted the merge.resolve_all loop, and bubbled
  -- out of setup() entirely. Treat throwing-enabled as disabled and notify.
  it("check_enabled treats a throwing enabled as disabled", function()
    _G.test_state.notifications = {}
    local utils = require('zpack.utils')

    local result = utils.check_enabled({
      enabled = function() error("simulated enabled failure", 0) end,
    }, 'test/plugin-x')
    helpers.flush_pending()

    assert.is_false(result, "throwing enabled should evaluate to false")

    local saw_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to evaluate enabled for test/plugin%-x") then
        saw_notify = true
        break
      end
    end
    assert.is_true(saw_notify, "throwing enabled should surface a structured notify")
  end)

  -- Regression: a user-supplied `cond = function(plugin) ... end` that threw
  -- propagated out of vim.pack.add's load callback, was re-raised by
  -- register_all, and escaped setup(). Treat throwing-cond as cond=false and
  -- notify so registration continues for every other plugin.
  it("check_cond treats a throwing cond as false", function()
    _G.test_state.notifications = {}
    local utils = require('zpack.utils')

    local result = utils.check_cond(
      { cond = function() error("simulated cond failure", 0) end },
      nil,
      nil,
      'test/plugin-x'
    )
    helpers.flush_pending()

    assert.is_false(result, "throwing cond should evaluate to false")

    local saw_notify = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find("Failed to evaluate cond for test/plugin%-x") then
        saw_notify = true
        break
      end
    end
    assert.is_true(saw_notify, "throwing cond should surface a structured notify")
  end)
end)
