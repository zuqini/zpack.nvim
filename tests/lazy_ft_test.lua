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

  -- nvim#25526 (https://github.com/neovim/neovim/issues/25526): `once = true`
  -- autocmds can fire twice in the same tick when the plugin's own ftplugin/*
  -- (sourced during packadd) nest-fires FileType before load_status flips.
  -- Mirrors the event-side guard test.
  it("ft proxy callback only refires once on synchronous double-invocation", function()
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
          ft = 'lua',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local target
    for _, au in ipairs(vim.api.nvim_get_autocmds({ group = state.lazy_group })) do
      if au.event == 'FileType' then
        target = au
        break
      end
    end
    assert.is_not_nil(target, "FileType autocmd should be registered")
    assert.is_not_nil(target.callback, "Callback must be exposed for the test")

    local ev = { event = 'FileType', buf = vim.api.nvim_get_current_buf(), match = 'lua' }
    target.callback(ev)
    target.callback(ev)

    refire.exec = original_exec

    assert.are.equal(1, exec_call_count,
      "refire.exec must fire exactly once across two callback invocations")
  end)

  -- A plugin that ships its own filetype detection (e.g. `ftdetect/foo.vim`)
  -- specced as `ft = 'foo'` must have its ftdetect sourced at registration —
  -- otherwise opening a `.foo` file never sets `ft = foo`, so the FileType
  -- autocmd never fires, and the plugin silently never loads.
  it("ft trigger sources the plugin's ftdetect/ files at registration", function()
    local plugin_name = 'plugin'
    local plugin_dir = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/' .. plugin_name
    vim.fn.mkdir(plugin_dir .. '/ftdetect', 'p')
    local marker_file = vim.fn.tempname()
    local ftdetect_file = plugin_dir .. '/ftdetect/zpackmark.vim'
    local f = assert(io.open(ftdetect_file, 'w'))
    f:write(("call writefile(['sourced'], '%s')\n"):format(marker_file))
    f:close()

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          ft = 'zpackmark',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local sourced = vim.fn.filereadable(marker_file) == 1
    vim.fn.delete(ftdetect_file)
    vim.fn.delete(marker_file)
    vim.fn.delete(plugin_dir, 'rf')

    assert.is_true(sourced,
      "Plugin's ftdetect/*.vim should be sourced at ft-trigger registration")
  end)
  describe("plugins sharing a filetype", function()
    local opened = {}

    after_each(function()
      for _, buf in ipairs(opened) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
      opened = {}
    end)

    local function open_as(filetype)
      local buf = vim.api.nvim_create_buf(true, false)
      table.insert(opened, buf)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = filetype
      helpers.flush_pending()
    end

    local function count_filetype_fires()
      local group = vim.api.nvim_create_augroup('CountFT', { clear = true })
      local count = { n = 0 }
      vim.api.nvim_create_autocmd('FileType', {
        group = group,
        pattern = '*',
        callback = function() count.n = count.n + 1 end,
      })
      return count, group
    end

    it("load in priority order and re-fire FileType once", function()
      local order = {}
      local function spec(name, priority)
        return {
          'test/' .. name,
          ft = 'rust',
          priority = priority,
          config = function() table.insert(order, name) end,
        }
      end
      require('zpack').setup({
        spec = { spec('low', 1), spec('high', 100), spec('mid', 50) },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local count, group = count_filetype_fires()

      open_as('rust')

      assert.are.same({ 'high', 'mid', 'low' }, order)
      assert.are.equal(2, count.n, "the original dispatch plus one re-fire")
      vim.api.nvim_del_augroup_by_id(group)
    end)

    it("still load the rest and re-fire when one fails", function()
      local loaded = {}
      require('zpack').setup({
        spec = {
          { 'test/bad', ft = 'rust', priority = 100, config = function() end },
          { 'test/good', ft = 'rust', config = function() table.insert(loaded, 'good') end },
        },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local count, group = count_filetype_fires()
      local loader = require('zpack.plugin_loader')
      local original = loader.process_spec
      loader.process_spec = function(pack_spec, opts)
        if pack_spec.name == 'bad' then error('simulated load failure', 0) end
        return original(pack_spec, opts)
      end

      open_as('rust')
      loader.process_spec = original

      assert.are.same({ 'good' }, loaded)
      assert.are.equal(2, count.n)
      vim.api.nvim_del_augroup_by_id(group)
    end)

    it("do not re-fire when every load failed", function()
      require('zpack').setup({
        spec = { { 'test/bad', ft = 'rust' } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local count, group = count_filetype_fires()
      local loader = require('zpack.plugin_loader')
      local original = loader.process_spec
      loader.process_spec = function() error('simulated load failure', 0) end

      open_as('rust')
      loader.process_spec = original

      assert.are.equal(1, count.n)
      vim.api.nvim_del_augroup_by_id(group)
    end)

    it("load once and skip the re-fire for a second filetype", function()
      local configs = 0
      require('zpack').setup({
        spec = { { 'test/multi', ft = { 'rust', 'zig' }, config = function() configs = configs + 1 end } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local count, group = count_filetype_fires()

      open_as('rust')
      assert.are.equal(1, configs)
      assert.are.equal(2, count.n)

      count.n = 0
      open_as('zig')
      assert.are.equal(1, configs)
      assert.are.equal(1, count.n, "the plugin is already loaded, so nothing to re-fire")
      vim.api.nvim_del_augroup_by_id(group)
    end)

    it("do not retry a failed plugin on its next filetype", function()
      require('zpack').setup({
        spec = { { 'test/bad', ft = { 'rust', 'zig' } } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local loader = require('zpack.plugin_loader')
      local original = loader.process_spec
      local attempts = 0
      loader.process_spec = function()
        attempts = attempts + 1
        error('simulated load failure', 0)
      end

      open_as('rust')
      open_as('zig')
      loader.process_spec = original

      assert.are.equal(1, attempts)
    end)

    for label, ft in pairs({
      ['an empty list'] = {},
      ['a function returning an empty list'] = function() return {} end,
      ['a map'] = { rust = true },
      ['an empty string'] = '',
      ['a list holding an empty string'] = { '' },
      ['only commas'] = ',',
      ['a function returning a non-table'] = function() return true end,
    }) do
      it("warn when ft is " .. label .. " instead of aborting setup", function()
        local after_it = false
        require('zpack').setup({
          spec = {
            { 'test/none', lazy = true, ft = ft },
            { 'test/after-it', config = function() after_it = true end },
          },
          defaults = { confirm = false },
        })
        helpers.flush_pending()

        assert.is_true(after_it)
        assert.is_truthy(helpers.find_notification({ 'no filetypes' }, vim.log.levels.WARN))
      end)
    end

    for label, ft in pairs({
      ['an unclosed brace'] = '{',
      ['a buffer pattern for a missing buffer'] = '<buffer=999999>',
    }) do
      it("warn when ft is " .. label .. " instead of aborting setup", function()
        local after_it = false
        require('zpack').setup({
          spec = {
            { 'test/none', lazy = true, ft = ft },
            { 'test/after-it', config = function() after_it = true end },
          },
          defaults = { confirm = false },
        })
        helpers.flush_pending()

        assert.is_true(after_it)
        assert.is_truthy(helpers.find_notification({ 'valid autocmd pattern' }, vim.log.levels.WARN))
      end)
    end

    it("still load on the valid filetypes next to an invalid pattern", function()
      local loaded = false
      require('zpack').setup({
        spec = { { 'test/mixed', ft = { '{', 'rust' }, config = function() loaded = true end } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()

      open_as('rust')
      assert.is_true(loaded)
    end)

    it("warn about named keys in ft and still load on its list entries", function()
      local loaded = false
      require('zpack').setup({
        spec = { { 'test/mixed', ft = { 'rust', zig = true }, config = function() loaded = true end } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()

      assert.is_truthy(helpers.find_notification({ 'ignoring ft entries' }, vim.log.levels.WARN))
      open_as('rust')
      assert.is_true(loaded)
    end)

    it("warn about other entries next to a comma-separated string", function()
      require('zpack').setup({
        spec = { { 'test/mixed', ft = { 'rust,toml', 5 } } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()

      assert.is_truthy(helpers.find_notification({ 'ignoring ft entries' }, vim.log.levels.WARN))
    end)

    local function priority_specs(middle)
      local order = {}
      local function spec(name, priority, fields)
        return vim.tbl_extend('error', {
          'test/' .. name,
          priority = priority,
          config = function() table.insert(order, name) end,
        }, fields)
      end
      require('zpack').setup({
        spec = { spec('high', 100, { ft = 'rust' }), spec('mid', 50, middle), spec('low', 10, { ft = 'rust' }) },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      return order
    end

    it("group a comma-separated string with the same literal filetype", function()
      local order = priority_specs({ ft = 'rust,toml' })
      local count, group = count_filetype_fires()

      open_as('rust')

      assert.are.same({ 'high', 'mid', 'low' }, order)
      assert.are.equal(2, count.n)
      vim.api.nvim_del_augroup_by_id(group)
    end)

    it("load a comma-separated string on its second filetype", function()
      local order = priority_specs({ ft = { 'rust,toml' } })

      open_as('toml')

      assert.are.same({ 'mid' }, order)
    end)

    for _, filetype in ipairs({ 'rust', 'toml' }) do
      it("keep the commas of a brace pattern, loading on " .. filetype, function()
        local loaded = false
        require('zpack').setup({
          spec = { { 'test/braces', ft = '{rust,toml}', config = function() loaded = true end } },
          defaults = { confirm = false },
        })
        helpers.flush_pending()

        open_as(filetype)

        assert.is_true(loaded)
      end)
    end

    for label, event in pairs({
      ['another literal filetype'] = 'FileType markdown',
      ['a list of other filetypes'] = { event = 'FileType', pattern = { 'markdown', 'toml' } },
    }) do
      it("are not split by an event plugin on " .. label, function()
        local order = priority_specs({ event = event })
        local count, group = count_filetype_fires()

        open_as('rust')

        assert.are.same({ 'high', 'low' }, order)
        assert.are.equal(2, count.n)
        vim.api.nvim_del_augroup_by_id(group)
      end)
    end

    for label, event in pairs({
      ['a comma-separated pattern'] = 'FileType rust,toml',
      ['a list holding the filetype'] = { event = 'FileType', pattern = { 'markdown', 'rust' } },
      ['a glob'] = 'FileType r*',
      ['a brace pattern'] = 'FileType {rust,toml}',
      ['a differently cased pattern'] = { event = 'FileType', pattern = 'Rust' },
    }) do
      it("keep priority order around an event plugin on " .. label, function()
        local saved_fic = vim.go.fileignorecase
        vim.go.fileignorecase = true
        local order = priority_specs({ event = event })

        open_as('rust')
        vim.go.fileignorecase = saved_fic

        assert.are.same({ 'high', 'mid', 'low' }, order)
      end)
    end

    local accepts_empty_pattern, empty_pattern_au = pcall(vim.api.nvim_create_autocmd, 'User', { pattern = {}, command = '' })
    if accepts_empty_pattern then
      vim.api.nvim_del_autocmd(empty_pattern_au)
      it("keep priority order around an event plugin on an empty pattern list", function()
        -- With a real event too: on its own the empty list is no trigger, so the plugin is eager.
        local order = priority_specs({ event = { 'User ZpackNever', { event = 'FileType', pattern = {} } } })

        open_as('rust')

        assert.are.same({ 'high', 'mid', 'low' }, order)
      end)
    end

    local function outline_specs(event)
      local order = {}
      local function spec(name, priority, fields)
        return vim.tbl_extend('error', {
          'test/' .. name,
          priority = priority,
          config = function() table.insert(order, name) end,
        }, fields)
      end
      require('zpack').setup({
        spec = {
          spec('high', 100, { ft = 'Outline' }),
          spec('mid', 50, { event = event }),
          spec('low', 10, { ft = 'Outline' }),
        },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      return order
    end

    it("keep an uppercase filetype's group whole around an event plugin on another filetype", function()
      local order = outline_specs('FileType markdown')
      local count, group = count_filetype_fires()

      open_as('Outline')
      vim.api.nvim_del_augroup_by_id(group)

      assert.are.same({ 'high', 'low' }, order)
      assert.are.equal(2, count.n)
    end)

    it("split an uppercase filetype's group for an event plugin on another spelling", function()
      local saved_fic = vim.go.fileignorecase
      vim.go.fileignorecase = true
      local order = outline_specs('FileType outline')

      open_as('Outline')
      vim.go.fileignorecase = saved_fic

      assert.are.same({ 'high', 'mid', 'low' }, order)
    end)

    it("keep priority order when a literal event plugin can match a glob group", function()
      local order = {}
      local function spec(name, priority, fields)
        return vim.tbl_extend('error', {
          'test/' .. name,
          priority = priority,
          config = function() table.insert(order, name) end,
        }, fields)
      end
      require('zpack').setup({
        spec = {
          spec('high', 100, { ft = 'r*' }),
          spec('mid', 50, { event = 'FileType rust' }),
          spec('low', 10, { ft = 'r*' }),
        },
        defaults = { confirm = false },
      })
      helpers.flush_pending()

      open_as('rust')

      assert.are.same({ 'high', 'mid', 'low' }, order)
    end)

    describe("with real plugin directories", function()
      local root, saved_rtp, saved_pp, opt_dir
      local filetype = 'zpackgroupft'

      local function mkplugin(name, ftplugin_lines)
        local path = opt_dir .. '/' .. name
        vim.fn.mkdir(path .. '/ftplugin', 'p')
        if ftplugin_lines then
          vim.fn.writefile(ftplugin_lines, path .. '/ftplugin/' .. filetype .. '.lua')
        end
      end

      before_each(function()
        saved_rtp, saved_pp = vim.go.rtp, vim.go.packpath
        root = vim.fn.tempname()
        opt_dir = root .. '/pack/zpack/opt'
        vim.fn.mkdir(opt_dir, 'p')
        vim.go.rtp = root .. ',' .. saved_rtp
        vim.go.packpath = root
        vim.cmd.packadd = _G.test_state.original_vim_cmd_packadd
        vim.cmd('filetype plugin on')
      end)

      after_each(function()
        vim.cmd('filetype plugin off')
        vim.cmd('filetype off')
        _G.zpack_ftplugin_runs = nil
        vim.go.rtp, vim.go.packpath = saved_rtp, saved_pp
        vim.fn.delete(root, 'rf')
      end)

      local function guarded_ftplugin(name, extra)
        return {
          'if vim.b.did_ftplugin then return end',
          'vim.b.did_ftplugin = 1',
          ("vim.b.zpack_winner = '%s'"):format(name),
          ("_G.zpack_ftplugin_runs = (_G.zpack_ftplugin_runs or '') .. '%s,'"):format(name),
          extra or '',
        }
      end

      local function setup_ftplugin_pair(extra)
        _G.zpack_ftplugin_runs = nil
        mkplugin('high', guarded_ftplugin('high', extra))
        mkplugin('low', guarded_ftplugin('low', extra))
        require('zpack').setup({
          spec = {
            { 'test/high', ft = filetype, priority = 100 },
            { 'test/low', ft = filetype, priority = 10 },
          },
          defaults = { confirm = false },
        })
        helpers.flush_pending()
      end

      it("let the lowest priority win among guarded ftplugins", function()
        setup_ftplugin_pair()

        open_as(filetype)

        assert.are.equal('low', vim.b.zpack_winner)
        assert.are.equal('low,', _G.zpack_ftplugin_runs)
      end)

      it("keep the winner for ftplugins with b:undo_ftplugin, without running the loser to undo it", function()
        setup_ftplugin_pair("vim.b.undo_ftplugin = ''")

        open_as(filetype)

        assert.are.equal('low', vim.b.zpack_winner)
        assert.are.equal('low,', _G.zpack_ftplugin_runs)
      end)

      it("run an earlier plugin's FileType handler on the trigger buffer once the last has loaded", function()
        mkplugin('high'); mkplugin('low')
        local seen = {}
        local augroup = vim.api.nvim_create_augroup('ZpackEarlierHandler', { clear = true })
        require('zpack').setup({
          spec = {
            {
              'test/high',
              ft = filetype,
              priority = 100,
              config = function()
                vim.api.nvim_create_autocmd('FileType', {
                  group = augroup,
                  pattern = filetype,
                  callback = function(ev)
                    table.insert(seen, { buf = ev.buf, line = vim.api.nvim_buf_get_lines(ev.buf, 0, 1, false)[1] })
                  end,
                })
              end,
            },
            {
              'test/low',
              ft = filetype,
              priority = 10,
              config = function()
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'from low' })
              end,
            },
          },
          defaults = { confirm = false },
        })
        helpers.flush_pending()

        open_as(filetype)

        assert.are.same({ { buf = vim.api.nvim_get_current_buf(), line = 'from low' } }, seen)
        vim.api.nvim_del_augroup_by_id(augroup)
      end)

      it("miss a second buffer loaded during the group for a handler of a pending plugin", function()
        mkplugin('high'); mkplugin('low')
        local seen = {}
        local second
        local augroup = vim.api.nvim_create_augroup('ZpackPendingHandler', { clear = true })
        require('zpack').setup({
          spec = {
            {
              'test/high',
              ft = filetype,
              priority = 100,
              config = function()
                second = vim.api.nvim_create_buf(true, false)
                vim.bo[second].filetype = filetype
              end,
            },
            {
              'test/low',
              ft = filetype,
              priority = 10,
              config = function()
                vim.api.nvim_create_autocmd('FileType', {
                  group = augroup,
                  pattern = filetype,
                  callback = function(ev) table.insert(seen, ev.buf) end,
                })
              end,
            },
          },
          defaults = { confirm = false },
        })
        helpers.flush_pending()

        open_as(filetype)

        assert.is_truthy(second)
        assert.are.same({ vim.api.nvim_get_current_buf() }, seen)
        vim.api.nvim_del_augroup_by_id(augroup)
      end)
    end)

    for label, event in pairs({
      ['FileType'] = 'FileType',
      ['FileType with a pattern'] = 'FileType rust',
      ['an event spec'] = { event = 'FileType', pattern = 'rust' },
    }) do
      it("keep priority order around an event plugin on " .. label, function()
        local order = {}
        local function loaded(name)
          return function() table.insert(order, name) end
        end
        require('zpack').setup({
          spec = {
            { 'test/alpha', ft = 'rust', priority = 100, config = loaded('alpha') },
            { 'test/beta', event = event, priority = 50, config = loaded('beta') },
            { 'test/gamma', ft = 'rust', priority = 10, config = loaded('gamma') },
          },
          defaults = { confirm = false },
        })
        helpers.flush_pending()

        open_as('rust')

        assert.are.same({ 'alpha', 'beta', 'gamma' }, order)
      end)
    end

    it("stay one group when the event plugin is outside their priorities", function()
      local spec = {
        { 'test/first', event = 'FileType', priority = 100 },
        { 'test/alpha', ft = 'rust', priority = 50 },
        { 'test/gamma', ft = 'rust', priority = 10 },
      }
      require('zpack').setup({ spec = spec, defaults = { confirm = false } })
      helpers.flush_pending()
      local count, group = count_filetype_fires()

      open_as('rust')

      assert.are.equal(3, count.n, "the original dispatch, the event plugin's re-fire and one group re-fire")
      vim.api.nvim_del_augroup_by_id(group)
    end)

    it("do not re-fire for a plugin removed before the filetype fired", function()
      require('zpack').setup({
        spec = { { 'test/gone', ft = 'rust' } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      require('zpack.state').spec_registry['https://github.com/test/gone'] = nil
      local count, group = count_filetype_fires()

      open_as('rust')

      assert.are.equal(1, count.n)
      vim.api.nvim_del_augroup_by_id(group)
    end)
  end)
end)
