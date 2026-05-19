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

  it("VeryLazy event creates UIEnter autocmd", function()
    local state = require('zpack.state')

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
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'UIEnter'),
      "VeryLazy should create UIEnter autocmd"
    )
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
end)
