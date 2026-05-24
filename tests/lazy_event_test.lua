local helpers = require('helpers')

describe("Lazy Loading - Events", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("inline event pattern is parsed correctly", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPre *.lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'BufReadPre', '*.lua'),
      "Inline event pattern should create autocmd"
    )
  end)

  it("EventSpec with pattern creates autocmd with pattern", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = {
            event = 'BufRead',
            pattern = '*.rs',
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'BufReadPost', '*.rs'),
      "EventSpec pattern should create autocmd with pattern"
    )
  end)

  it("EventSpec with multiple patterns creates autocmd", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = {
            event = 'BufRead',
            pattern = { '*.lua', '*.vim' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    local found = helpers.find_autocmd(autocmds, 'BufReadPost', '*.lua')
      or helpers.find_autocmd(autocmds, 'BufReadPost', '*.vim')
    assert.is_not_nil(found, "EventSpec with multiple patterns should create autocmd")
  end)

  it("global pattern fallback is applied to events", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufRead',
          pattern = '*.md',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'BufReadPost', '*.md'),
      "Global pattern should be applied to events"
    )
  end)

  it("VeryLazy plugin loads when setup runs post-UIEnter", function()
    -- Test environment has vim_did_enter == 1, so the per-plugin UIEnter
    -- autocmd path is skipped and the load is scheduled directly. Without
    -- this fast-path, `event = 'VeryLazy'` plugins would never load after
    -- a `:luafile` / config reload because UIEnter is already in the past.
    local state = require('zpack.state')
    assert.are.equal(1, vim.v.vim_did_enter,
      "Test prerequisite: this test exercises the post-UIEnter setup path")

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'VeryLazy',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local src = 'https://github.com/test/plugin'
    assert.are.equal('loaded', state.spec_registry[src].load_status,
      "VeryLazy plugin should be loaded via the post-UIEnter fast-path")
  end)

  it("multiple EventSpecs with different patterns", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = {
            { event = 'BufReadPre', pattern = '*.lua' },
            { event = 'BufNewFile', pattern = '*.rs' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'BufReadPre', '*.lua'),
      "Should create BufReadPre autocmd with *.lua pattern"
    )
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'BufNewFile', '*.rs'),
      "Should create BufNewFile autocmd with *.rs pattern"
    )
  end)

  it("re-fired event forwards original ev.data", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_data.lua')
    local received_data = nil

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = test_group,
        pattern = '*',
        callback = function(ev)
          received_data = ev.data
        end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('BufReadPost', {
      buffer = buf,
      data = { client_id = 42 },
    })

    helpers.flush_pending()

    assert.is_not_nil(received_data, "Re-fired event should forward data")
    assert.are.equal(42, received_data.client_id)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("re-fire triggers when buffer is still valid", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_refire.lua')
    local refire_count = 0

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = test_group,
        pattern = '*',
        callback = function()
          refire_count = refire_count + 1
        end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })

    helpers.flush_pending()

    assert.are.equal(1, refire_count)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("re-fire skips invalid buffer without error", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_invalid.lua')
    local refire_count = 0

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_buf_delete(buf, { force = true })
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = test_group,
        pattern = '*',
        callback = function()
          refire_count = refire_count + 1
        end,
        once = true,
      })
    end

    local ok = pcall(vim.api.nvim_exec_autocmds, 'BufReadPost', { buffer = buf })

    helpers.flush_pending()

    assert.is_truthy(ok, "Should not error when buffer becomes invalid during lazy-load")
    assert.are.equal(0, refire_count)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("re-fire chains BufReadPre before BufReadPost", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_chain.lua')
    local fired_events = {}

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('BufReadPre', {
        group = test_group,
        pattern = '*',
        callback = function() table.insert(fired_events, 'BufReadPre') end,
        once = true,
      })
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = test_group,
        pattern = '*',
        callback = function() table.insert(fired_events, 'BufReadPost') end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })

    helpers.flush_pending()

    assert.are.equal(2, #fired_events)
    assert.are.equal('BufReadPre', fired_events[1])
    assert.are.equal('BufReadPost', fired_events[2])

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("re-fire chains BufReadPre and BufReadPost before FileType", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'FileType',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_ft_chain.lua')
    local fired_events = {}

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      for _, ev_name in ipairs({ 'BufReadPre', 'BufReadPost', 'FileType' }) do
        vim.api.nvim_create_autocmd(ev_name, {
          group = test_group,
          pattern = '*',
          callback = function() table.insert(fired_events, ev_name) end,
          once = true,
        })
      end
    end

    vim.api.nvim_exec_autocmds('FileType', { buffer = buf })

    helpers.flush_pending()

    assert.are.equal(3, #fired_events)
    assert.are.equal('BufReadPre', fired_events[1])
    assert.are.equal('BufReadPost', fired_events[2])
    assert.are.equal('FileType', fired_events[3])

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("re-fire chain only forwards data to the original event", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_data_chain.lua')
    local pre_data = 'not_called'
    local post_data = 'not_called'

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('BufReadPre', {
        group = test_group,
        pattern = '*',
        callback = function(ev) pre_data = ev.data end,
        once = true,
      })
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = test_group,
        pattern = '*',
        callback = function(ev) post_data = ev.data end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('BufReadPost', {
      buffer = buf,
      data = { client_id = 99 },
    })

    helpers.flush_pending()

    assert.is_nil(pre_data, "BufReadPre should not receive data")
    assert.is_not_nil(post_data, "BufReadPost should receive data")
    assert.are.equal(99, post_data.client_id)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("event without chain does not fire dependency events", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'LspAttach',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_no_chain.lua')
    local fired_events = {}

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('LspAttach', {
        group = test_group,
        pattern = '*',
        callback = function() table.insert(fired_events, 'LspAttach') end,
        once = true,
      })
      vim.api.nvim_create_autocmd('BufReadPre', {
        group = test_group,
        pattern = '*',
        callback = function() table.insert(fired_events, 'BufReadPre') end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('LspAttach', { buffer = buf })

    helpers.flush_pending()

    assert.are.equal(1, #fired_events)
    assert.are.equal('LspAttach', fired_events[1])

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("re-fire does not double-fire pre-existing augroup handlers", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local pre_existing_group = vim.api.nvim_create_augroup('PreExisting', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_dedup.lua')
    local pre_existing_count = 0

    vim.api.nvim_create_autocmd('BufReadPost', {
      group = pre_existing_group,
      pattern = '*',
      callback = function()
        pre_existing_count = pre_existing_count + 1
      end,
    })

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
    end

    vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })

    helpers.flush_pending()

    assert.are.equal(1, pre_existing_count)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(pre_existing_group)
  end)

  it("re-fire fires only newly-added augroup handlers", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local pre_existing_group = vim.api.nvim_create_augroup('PreExisting', { clear = true })
    local new_group = vim.api.nvim_create_augroup('NewPlugin', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_new_only.lua')
    local pre_existing_count = 0
    local new_count = 0

    vim.api.nvim_create_autocmd('BufReadPost', {
      group = pre_existing_group,
      pattern = '*',
      callback = function()
        pre_existing_count = pre_existing_count + 1
      end,
    })

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = new_group,
        pattern = '*',
        callback = function()
          new_count = new_count + 1
        end,
      })
    end

    vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })

    helpers.flush_pending()

    assert.are.equal(1, pre_existing_count)
    assert.are.equal(1, new_count)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(pre_existing_group)
    vim.api.nvim_del_augroup_by_id(new_group)
  end)

  it("re-fire pcall prevents one group error from breaking the chain", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local error_group = vim.api.nvim_create_augroup('ErrorPlugin', { clear = true })
    local ok_group = vim.api.nvim_create_augroup('OkPlugin', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_pcall.lua')
    local ok_fired = false

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('BufReadPre', {
        group = error_group,
        pattern = '*',
        callback = function() error("intentional test error") end,
        once = true,
      })
      vim.api.nvim_create_autocmd('BufReadPost', {
        group = ok_group,
        pattern = '*',
        callback = function() ok_fired = true end,
        once = true,
      })
    end

    local ok = pcall(vim.api.nvim_exec_autocmds, 'BufReadPost', { buffer = buf })

    helpers.flush_pending()

    assert.is_truthy(ok_fired, "BufReadPost handler should still fire despite BufReadPre error")

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(error_group)
    vim.api.nvim_del_augroup_by_id(ok_group)
  end)

  it("lazy event plugin does not load at startup", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufRead',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)
  end)

  -- `User <pattern>` autocmds are matched by literal pattern, not by buffer
  -- state, so `nvim_exec_autocmds('User', { buffer = ... })` (the old refire
  -- shape) never fires them. The plugin's own `User LspAttach` handler must
  -- be re-fired with `pattern = 'LspAttach'`.
  it("re-fire fires plugin's User <pattern> handlers via pattern dispatch", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'User LspAttach',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local refire_count = 0
    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('User', {
        group = test_group,
        pattern = 'LspAttach',
        callback = function() refire_count = refire_count + 1 end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('User', { pattern = 'LspAttach' })

    helpers.flush_pending()

    assert.are.equal(1, refire_count, "Plugin's User LspAttach handler should fire after lazy-load")

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  -- ColorScheme autocmds are matched by colorscheme name pattern, not by
  -- buffer state — same shape as `User <pattern>`. A colorscheme-extending
  -- plugin lazy-loaded by `event = 'ColorScheme tokyonight'` would load but
  -- its own `ColorScheme tokyonight` handlers would never fire under buffer
  -- dispatch.
  it("re-fire fires plugin's ColorScheme <pattern> handlers via pattern dispatch", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'ColorScheme tokyonight',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local refire_count = 0
    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = test_group,
        pattern = 'tokyonight',
        callback = function() refire_count = refire_count + 1 end,
        once = true,
      })
    end

    vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'tokyonight' })

    helpers.flush_pending()

    assert.are.equal(1, refire_count, "Plugin's ColorScheme tokyonight handler should fire after lazy-load")

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  -- Regression: for `event = { 'A', 'FileType' }`, A fires first and loads
  -- the plugin, but the FileType proxy outlives the load (once=true is per-
  -- autocmd). When FileType fires naturally, the proxy ALSO fires, calls
  -- try_process_spec (already-loaded no-op), and refire.exec unconditionally
  -- re-dispatches FileType — double-firing the plugin's FileType handler.
  it("event proxy skips refire when sibling event already loaded plugin", function()
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })
    local ft_fire_count = 0

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = { 'InsertEnter', 'FileType' },
          config = function()
            vim.api.nvim_create_autocmd('FileType', {
              group = test_group,
              callback = function() ft_fire_count = ft_fire_count + 1 end,
            })
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    -- Load via InsertEnter first.
    vim.api.nvim_exec_autocmds('InsertEnter', {})
    helpers.flush_pending()
    ft_fire_count = 0

    -- Now fire FileType naturally — should only count once (the plugin's own
    -- handler firing via natural dispatch), not twice (once natural + once via
    -- the now-stale FileType proxy's refire).
    vim.api.nvim_exec_autocmds('FileType', {})
    helpers.flush_pending()

    assert.are.equal(1, ft_fire_count,
      "FileType handler must fire exactly once; the stale proxy must not refire")

    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  -- Regression: `nvim_exec_autocmds('User', {})` (no pattern) reaches the User
  -- proxy with `ev.match = ''`. Refire must fall back to pattern='*' so the
  -- plugin's `User '*'` handlers still fire; otherwise the load happens but
  -- the plugin's own handlers silently never run.
  it("re-fire falls back to pattern='*' when ev.match is empty for User", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    -- Install the mock BEFORE setup() so that the auto-emitted `User VeryLazy`
    -- (scheduled by lazy.fire_very_lazy when `vim_did_enter == 1`) and the
    -- test's explicit `nvim_exec_autocmds('User', {})` both route through it.
    -- The once-true `User *` proxy is consumed by whichever dispatch lands
    -- first; the explicit one must land first so the empty-match-fallback
    -- contract is what's being pinned.
    local refire_count = 0
    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('User', {
        group = test_group,
        pattern = '*',
        callback = function() refire_count = refire_count + 1 end,
        once = true,
      })
    end

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'User',
        },
      },
      defaults = { confirm = false },
    })

    -- No `flush_pending` before the explicit dispatch: the VeryLazy emit is
    -- scheduled (vim.schedule), so it has not yet run. The explicit dispatch
    -- below consumes the proxy first with `ev.match = ''`, exercising the
    -- empty-match-fallback path. The scheduled emit fires harmlessly later
    -- (proxy already consumed, test handler is once-true and consumed).
    vim.api.nvim_exec_autocmds('User', {})
    helpers.flush_pending()

    assert.are.equal(1, refire_count,
      "Plugin's User '*' handler should fire after lazy-load with empty match")

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  -- Bead zpack_nvim-8k9: per-autocmd `done` flag guards against nvim#25526
  -- (https://github.com/neovim/neovim/issues/25526), where a `once = true`
  -- autocmd can fire twice in the same tick. The visible contract: invoking
  -- the lazy-load callback twice in a row dispatches refire exactly once,
  -- even if the load_status gate hasn't yet committed `loaded`.
  it("event proxy callback only refires once on synchronous double-invocation", function()
    local refire = require('zpack.lazy_trigger.refire')
    local state = require('zpack.state')
    local exec_call_count = 0
    local original_exec = refire.exec
    refire.exec = function(...)
      exec_call_count = exec_call_count + 1
      return original_exec(...)
    end

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          event = 'BufReadPost',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local target
    for _, au in ipairs(vim.api.nvim_get_autocmds({ group = state.lazy_group })) do
      if au.event == 'BufReadPost' then
        target = au
        break
      end
    end
    assert.is_not_nil(target, "BufReadPost autocmd should be registered")
    assert.is_not_nil(target.callback, "Callback must be exposed for the test")

    local ev = { event = 'BufReadPost', buf = vim.api.nvim_get_current_buf(), match = '' }
    target.callback(ev)
    target.callback(ev)

    refire.exec = original_exec

    assert.are.equal(1, exec_call_count,
      "refire.exec must fire exactly once across two callback invocations")
  end)

  -- lazy.nvim emits `User VeryLazy` once on UIEnter so configs can hook
  -- `nvim_create_autocmd("User", { pattern = "VeryLazy" })` for post-setup
  -- delayed init. zpack must mirror that contract for ported configs.
  it("setup emits User VeryLazy on UIEnter", function()
    local fired = false
    local test_group = vim.api.nvim_create_augroup('ZpackVeryLazyTest', { clear = true })
    vim.api.nvim_create_autocmd('User', {
      group = test_group,
      pattern = 'VeryLazy',
      callback = function() fired = true end,
    })

    require('zpack').setup({
      spec = {
        { 'test/plugin' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.api.nvim_exec_autocmds('UIEnter', {})
    helpers.flush_pending()

    vim.api.nvim_del_augroup_by_id(test_group)

    assert.is_true(fired, "User VeryLazy should fire on UIEnter")
  end)
end)
