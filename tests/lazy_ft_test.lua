local helpers = require('helpers')

describe("Lazy Loading - FileType", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("single filetype creates FileType autocmd", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'rust',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    assert.is_not_nil(
      helpers.find_autocmd(autocmds, 'FileType', 'rust'),
      "Single filetype should create FileType autocmd"
    )
  end)

  it("multiple filetypes create FileType autocmd with all patterns", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = { 'lua', 'vim', 'python' },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    local found = helpers.find_autocmd(autocmds, 'FileType', 'lua')
      or helpers.find_autocmd(autocmds, 'FileType', 'vim')
      or helpers.find_autocmd(autocmds, 'FileType', 'python')
    assert.is_not_nil(found, "Multiple filetypes should create FileType autocmd")
  end)

  it("ft re-fire chains BufReadPre, BufReadPost, and FileType", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_ft.lua')
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

    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'

    helpers.flush_pending()

    assert.are.equal(3, #fired_events)
    assert.are.equal('BufReadPre', fired_events[1])
    assert.are.equal('BufReadPost', fired_events[2])
    assert.are.equal('FileType', fired_events[3])

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("ft re-fire forwards data only to FileType", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local test_group = vim.api.nvim_create_augroup('ZpackTest', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_ft_data.lua')
    local pre_data = 'not_called'
    local post_data = 'not_called'
    local ft_data = 'not_called'

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
      vim.api.nvim_create_autocmd('FileType', {
        group = test_group,
        pattern = '*',
        callback = function(ev) ft_data = ev.data end,
        once = true,
      })
    end

    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'

    helpers.flush_pending()

    assert.is_nil(pre_data, "BufReadPre should not receive data")
    assert.is_nil(post_data, "BufReadPost should not receive data")

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(test_group)
  end)

  it("ft re-fire fires ALL FileType handlers including pre-existing", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local pre_existing_group = vim.api.nvim_create_augroup('PreExistingFT', { clear = true })
    local new_group = vim.api.nvim_create_augroup('NewPluginFT', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_ft_all.lua')
    local pre_existing_count = 0
    local new_count = 0

    vim.api.nvim_create_autocmd('FileType', {
      group = pre_existing_group,
      pattern = '*',
      callback = function()
        pre_existing_count = pre_existing_count + 1
      end,
    })

    loader.process_spec = function(pack_spec)
      original_process_spec(pack_spec)
      vim.api.nvim_create_autocmd('FileType', {
        group = new_group,
        pattern = '*',
        callback = function()
          new_count = new_count + 1
        end,
      })
    end

    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'

    helpers.flush_pending()

    assert.is_truthy(pre_existing_count >= 2, "Pre-existing FileType handler should fire from both original and re-fire")
    assert.is_truthy(new_count >= 1, "New FileType handler should fire from re-fire")

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(pre_existing_group)
    vim.api.nvim_del_augroup_by_id(new_group)
  end)

  it("ft re-fire deduplicates BufReadPost chain events", function()
    local loader = require('zpack.plugin_loader')
    local original_process_spec = loader.process_spec
    local pre_existing_group = vim.api.nvim_create_augroup('PreExistingBRP', { clear = true })
    local new_group = vim.api.nvim_create_augroup('NewPluginBRP', { clear = true })

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/test_ft_dedup.lua')
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

    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'

    helpers.flush_pending()

    assert.are.equal(0, pre_existing_count)
    assert.are.equal(1, new_count)

    loader.process_spec = original_process_spec
    vim.api.nvim_del_augroup_by_id(pre_existing_group)
    vim.api.nvim_del_augroup_by_id(new_group)
  end)

  it("lazy ft plugin does not load at startup", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)
  end)
end)
