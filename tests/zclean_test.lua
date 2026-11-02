local helpers = require('helpers')

describe("ZPack clean", function()
  local real_confirm, real_echo = vim.fn.confirm, vim.api.nvim_echo
  local prompts, echoed

  ---Answer vim.fn.confirm with this, noting what it was asked and what was echoed.
  local function answer(choice)
    prompts, echoed = {}, {}
    vim.api.nvim_echo = function(chunks)
      echoed[#echoed + 1] = chunks[1][1]
    end
    vim.fn.confirm = function(msg, choices, default, kind)
      prompts[#prompts + 1] = { msg = msg, choices = choices, default = default, kind = kind }
      return choice
    end
  end

  before_each(helpers.setup_test_env)
  after_each(function()
    vim.fn.confirm, vim.api.nvim_echo = real_confirm, real_echo
    helpers.cleanup_test_env()
  end)

  it("clean detects orphan plugins not in spec", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    _G.test_state.registered_pack_specs['orphan-plugin'] = {
      src = 'test/orphan-plugin',
      name = 'orphan-plugin',
    }

    vim.cmd('ZPack! clean')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.contains(call.names, 'orphan-plugin')
    assert.are.equal(1, #call.names)
  end)

  it("clean does not delete plugins in spec", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
        { 'test/plugin-b' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    vim.cmd('ZPack! clean')
    helpers.flush_pending()

    assert.are.equal(0, #_G.test_state.vim_pack_del_calls)

    local found_info = false
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.msg:find('No unused plugins') and notif.level == vim.log.levels.INFO then
        found_info = true
        break
      end
    end
    assert.is_truthy(found_info, "Should show info that no unused plugins exist")
  end)

  it("clean detects multiple orphan plugins", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin-a' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    _G.test_state.registered_pack_specs['orphan-1'] = {
      src = 'test/orphan-1',
      name = 'orphan-1',
    }
    _G.test_state.registered_pack_specs['orphan-2'] = {
      src = 'test/orphan-2',
      name = 'orphan-2',
    }

    vim.cmd('ZPack! clean')
    helpers.flush_pending()

    assert.are.equal(1, #_G.test_state.vim_pack_del_calls)
    local call = _G.test_state.vim_pack_del_calls[1]
    assert.are.equal(2, #call.names)
  end)

  describe("zpack itself", function()
    local function cleaned(pack)
      require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })
      helpers.flush_pending()
      _G.test_state.registered_pack_specs[pack.name] = pack
      local deleted = {}
      local original = vim.pack.del
      vim.pack.del = function(names)
        vim.list_extend(deleted, names)
      end
      vim.cmd('ZPack! clean')
      vim.pack.del = original
      return vim.list_contains(deleted, pack.name)
    end

    it("is kept", function()
      assert.is_false(cleaned({ src = 'https://github.com/zuqini/zpack.nvim', name = 'zpack.nvim' }))
    end)

    it("is kept when installed from a fork with a .git url", function()
      assert.is_false(cleaned({ src = 'https://example.com/me/zpack.nvim.git', name = 'zpack.nvim' }))
    end)

    it("does not shield a plugin that only has zpack in its name", function()
      assert.is_true(cleaned({ src = 'https://github.com/u/zpack-extras', name = 'zpack-extras' }))
    end)
  end)

  describe("asks first", function()
    local function orphans()
      require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })
      helpers.flush_pending()
      for _, name in ipairs({ 'orphan-2', 'orphan-1' }) do
        _G.test_state.registered_pack_specs[name] = { src = 'test/' .. name, name = name }
      end
    end

    local function deleted_names()
      local calls = _G.test_state.vim_pack_del_calls
      return calls[1] and calls[1].names or {}
    end

    it("listing the plugins one per line, with Yes and No, defaulting to No, despite defaults.confirm = false", function()
      answer(2)
      orphans()
      vim.cmd('ZPack clean')
      assert.are.same({ 'These plugins will be deleted:\n\norphan-1\norphan-2' }, echoed)
      assert.are.same({ {
        msg = 'Delete these 2 plugins?',
        choices = '&Yes\n&No',
        default = 2,
        kind = 'Question',
      } }, prompts)
    end)

    it("asking about one plugin in the singular", function()
      answer(2)
      require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })
      helpers.flush_pending()
      _G.test_state.registered_pack_specs['orphan-1'] = { src = 'test/orphan-1', name = 'orphan-1' }
      vim.cmd('ZPack clean')
      assert.are.same({ 'These plugins will be deleted:\n\norphan-1' }, echoed)
      assert.are.equal('Delete this plugin?', prompts[1].msg)
    end)

    for label, choice in pairs({ No = 2, ['an interrupted prompt'] = 0 }) do
      it(label .. " deletes nothing and says so", function()
        answer(choice)
        orphans()
        vim.cmd('ZPack clean')
        helpers.flush_pending()
        assert.are.same({}, _G.test_state.vim_pack_del_calls)
        assert.is_not_nil(helpers.find_notification({ 'Nothing deleted' }, vim.log.levels.INFO))
        assert.is_nil(helpers.find_notification({ 'Deleting' }))
      end)
    end

    it("Yes deletes the plugins it listed", function()
      answer(1)
      orphans()
      vim.cmd('ZPack clean')
      helpers.flush_pending()
      assert.are.same({ 'orphan-1', 'orphan-2' }, deleted_names())
      assert.is_not_nil(helpers.find_notification({ 'Deleting 2 unused' }, vim.log.levels.INFO))
    end)

    it("not with a bang", function()
      answer(2)
      orphans()
      vim.cmd('ZPack! clean')
      assert.are.same({}, prompts)
      assert.are.same({}, echoed)
      table.sort(deleted_names())
      assert.are.same({ 'orphan-1', 'orphan-2' }, deleted_names())
    end)

    it("not when there's nothing to delete", function()
      answer(1)
      require('zpack').setup({ spec = { { 'test/plugin-a' } }, defaults = { confirm = false } })
      helpers.flush_pending()
      vim.cmd('ZPack clean')
      helpers.flush_pending()
      assert.are.same({}, prompts)
      assert.is_not_nil(helpers.find_notification({ 'No unused plugins' }, vim.log.levels.INFO))
    end)
  end)

  describe("after a spec can't be read or a plugin failed to add", function()
    local function deleted_by(cmd, spec)
      local fs_stat = vim.uv.fs_stat
      vim.uv.fs_stat = function(path, ...)
        if path:find('/installed%-plugin$') then
          return { type = 'directory' }
        end
        return fs_stat(path, ...)
      end
      require('zpack').setup({ spec = spec, defaults = { confirm = false } })
      helpers.flush_pending()
      vim.uv.fs_stat = fs_stat
      _G.test_state.registered_pack_specs['installed-plugin'] =
        { src = 'https://github.com/test/installed-plugin', name = 'installed-plugin' }
      vim.cmd(cmd)
      helpers.flush_pending()
      return _G.test_state.vim_pack_del_calls[1] and _G.test_state.vim_pack_del_calls[1].names or {}
    end

    local function module(name, lines)
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. '/lua', 'p')
      vim.fn.writefile(lines, root .. '/lua/' .. name .. '.lua')
      vim.opt.rtp:prepend(root)
      package.loaded[name] = nil
    end

    ---The problem is reported, the plugin is listed, and No keeps it.
    local function assert_reported_and_listed(spec, report, level)
      answer(2)
      assert.are.same({}, deleted_by('ZPack clean', spec))
      assert.are.equal(1, #prompts)
      assert.are.same({ 'These plugins will be deleted:\n\ninstalled-plugin' }, echoed)
      assert.is_not_nil(helpers.find_notification({ report }, level or vim.log.levels.WARN),
        vim.inspect(_G.test_state.notifications))
    end

    it("vim.pack.add raising lists what was emptied from the registry, and Yes deletes it", function()
      vim.pack.add = function() error('spec.src: expected non-empty string') end
      assert_reported_and_listed({ { 'test/installed-plugin' } }, 'expected non-empty string', vim.log.levels.ERROR)
      vim.cmd('ZPack clean')
      assert.are.same({}, _G.test_state.vim_pack_del_calls)
      answer(1)
      vim.cmd('ZPack clean')
      assert.are.same({ 'installed-plugin' }, _G.test_state.vim_pack_del_calls[1].names)
    end)

    it("a clone that failed is listed, since it may be a typo in one's url", function()
      local add = vim.pack.add
      vim.pack.add = function(packs, opts)
        add(vim.tbl_filter(function(p) return p.name ~= 'never-cloned' end, packs), opts)
        error('vim.pack:\n\n`never-cloned`:\nclone failed')
      end
      assert_reported_and_listed({ { 'test/never-cloned' } }, 'clone failed', vim.log.levels.ERROR)
    end)

    it("a spec module that fails", function()
      module('zpack_broken_specs', { "error('boom')" })
      assert_reported_and_listed({ { import = 'zpack_broken_specs' } }, 'Failed to load plugin spec', vim.log.levels.ERROR)
    end)

    it("an import whose module isn't found", function()
      assert_reported_and_listed({ { import = 'zpack_no_such_module' } }, 'no specs found')
    end)

    it("an import function that throws", function()
      assert_reported_and_listed({ { import = function() error('boom') end } }, 'import function threw', vim.log.levels.ERROR)
    end)

    it("an import function that returns nothing", function()
      assert_reported_and_listed({ { import = function() end } }, 'import function returned non-table')
    end)

    it("an import's throwing cond", function()
      assert_reported_and_listed({ { import = 'zpack_no_such_module', cond = function() error('boom') end } },
        'Failed to evaluate cond', vim.log.levels.ERROR)
    end)

    it("an enabled function that throws", function()
      assert_reported_and_listed({ { 'test/installed-plugin', enabled = function() error('boom') end } },
        'Failed to evaluate enabled', vim.log.levels.ERROR)
    end)

    it("a spec with no usable source", function()
      assert_reported_and_listed({ { src = 42 } }, 'invalid spec')
    end)

    for name, spec in pairs({
      ['fields'] = { { 'test/ok-plugin', 'test/installed-plugin', opts = {} } },
      ['fields past a hole'] = { { 'test/ok-plugin', nil, 'test/installed-plugin', opts = {} } },
      ['fields under dependencies'] = { { 'test/p', dependencies = { { 'test/ok-plugin', 'test/installed-plugin', opts = {} } } } },
      ['a src'] = { { src = 'https://github.com/test/ok-plugin', 'test/other', 'test/installed-plugin' } },
      ['a sourceless import'] = { { import = function() return {} end, { 'test/ok-plugin' }, { 'test/installed-plugin' } } },
      ['fields after a leading hole'] = { { nil, 'test/installed-plugin', opts = {} } },
      ['fields after a leading false'] = { { false, 'test/installed-plugin', opts = {} } },
      ['fields after a leading {}'] = { { {}, 'test/installed-plugin', opts = {} } },
    }) do
      it("entries after [1] beside " .. name, function()
        assert_reported_and_listed(spec, 'entries after [1]')
      end)
    end

    for name, spec in pairs({
      ['dependencies value'] = { { 'test/ok-plugin', dependencies = { name = 'installed-plugin', opts = {} } } },
      ['specs value'] = { { 'test/ok-plugin', specs = { name = 'installed-plugin', opts = {} } } },
      ['whole spec'] = { name = 'installed-plugin', opts = {} },
      ['import function result'] = { { import = function() return { name = 'installed-plugin' } end } },
    }) do
      it("a table of fields alone as a " .. name, function()
        assert_reported_and_listed(spec, 'no plugin source')
      end)
    end

    it("a table of fields alone returned by a module", function()
      module('zpack_fields_specs', { "return { repo = 'x/y', opts = {} }" })
      assert_reported_and_listed({ { import = 'zpack_fields_specs' } }, 'no plugin source')
    end)

    for name, spec in pairs({
      ['dependencies function'] = { 'test/ok-plugin', dependencies = function() end },
      ['specs function'] = { 'test/ok-plugin', specs = function() end },
      ['non-string import'] = { 'test/ok-plugin', import = 42 },
      ['import = true'] = { 'test/ok-plugin', import = true },
    }) do
      it("a plugin's unreadable " .. name, function()
        assert_reported_and_listed({ spec }, 'invalid spec')
      end)
    end

    for name, specs in pairs({
      ['function'] = { { 'test/ok-plugin' }, function() return { { 'test/installed-plugin' } } end },
      ['number'] = { { 'test/ok-plugin' }, 42 },
      ['true'] = { { 'test/ok-plugin' }, true },
      ['function in a nested list'] = { { 'test/ok-plugin' }, { { 'test/other' }, function() end } },
      ['function under dependencies'] = { { 'test/ok-plugin', dependencies = { function() end } } },
    }) do
      it("a list entry that's a " .. name, function()
        assert_reported_and_listed(specs, 'invalid spec')
      end)
    end

    for name, lines in pairs({
      ['has no return'] = { "local specs = { { 'test/installed-plugin' } }" },
      ['is empty'] = {},
      ['only has comments'] = { '-- nothing yet' },
      ['returns a non-table'] = { 'return 1' },
    }) do
      it("a module that " .. name, function()
        local mod = 'zpack_invalid_' .. name:gsub('%W', '_')
        module(mod, lines)
        assert_reported_and_listed({ { import = mod } }, 'not a table', vim.log.levels.ERROR)
      end)

      it("a file in a directory that " .. name, function()
        local root = vim.fn.tempname()
        local mod = 'zpack_invalid_dir_' .. name:gsub('%W', '_')
        vim.fn.mkdir(root .. '/lua/' .. mod, 'p')
        vim.fn.writefile(lines, root .. '/lua/' .. mod .. '/one.lua')
        vim.opt.rtp:prepend(root)
        package.loaded[mod .. '.one'] = nil
        assert_reported_and_listed({ { import = mod } }, 'not a table', vim.log.levels.ERROR)
      end)
    end

    describe("still reported under a plugin that's dropped", function()
      local missing = { { 'test/parent', enabled = false, dependencies = { { import = 'zpack_no_such_module' } } } }

      it("for an import that isn't found", function()
        assert_reported_and_listed(missing, 'no specs found')
      end)

      it("for a module that errors, a function that throws, and a cond that throws", function()
        module('zpack_broken_under', { "error('boom')" })
        local spec = { { 'test/parent', enabled = false, dependencies = {
          { import = 'zpack_broken_under' },
          { import = function() error('boom') end },
          { import = 'zpack_no_such_module', cond = function() error('boom') end },
        } } }
        assert_reported_and_listed(spec, 'Failed to load plugin spec', vim.log.levels.ERROR)
        assert.is_not_nil(helpers.find_notification({ 'import function threw' }, vim.log.levels.ERROR))
        assert.is_not_nil(helpers.find_notification({ 'Failed to evaluate cond' }, vim.log.levels.ERROR))
      end)
    end)

    describe("a plugin past a nil in a list stays declared", function()
      for name, specs in pairs({
        ['nil before a plugin'] = { { 'test/ok-plugin' }, nil, { 'test/installed-plugin' } },
        ['nil first'] = { nil, { 'test/installed-plugin' } },
        ['nil under dependencies'] = { { 'test/ok-plugin', dependencies = { nil, { 'test/installed-plugin' } } } },
        ['nil in a string-led list'] = { { 'test/ok-plugin', dependencies = { 'test/other', nil, 'test/installed-plugin' } } },
      }) do
        it(name, function()
          answer(1)
          assert.are.same({}, deleted_by('ZPack clean', specs))
          assert.are.same({}, prompts)
        end)
      end
    end)

    it("a disabled plugin is still unused", function()
      assert.are.same({ 'installed-plugin' },
        deleted_by('ZPack! clean', { { 'test/installed-plugin', enabled = false }, { 'test/other' } }))
    end)

    describe("an update goes on as usual", function()
      local lost_import = { import = 'zpack_no_such_module' }

      local function updated_by(cmd, spec)
        deleted_by(cmd, spec)
        return _G.test_state.vim_pack_update_calls[1]
      end

      local function no_warning_about_it()
        assert.is_nil(helpers.find_notification({ 'failed to load' }))
      end

      it("over every plugin vim.pack has", function()
        assert.is_nil(updated_by('ZPack! update', { { 'test/ok-plugin' }, lost_import }).names)
        no_warning_about_it()
      end)

      it("minus a pin that did register", function()
        local names = updated_by('ZPack! update',
          { { 'test/ok-plugin' }, { 'test/pinned-plugin', pin = true }, lost_import }).names
        table.sort(names)
        assert.are.same({ 'installed-plugin', 'ok-plugin' }, names)
        no_warning_about_it()
      end)

      it("for a bulk restore too", function()
        assert.is_nil(updated_by('ZPack! restore', { { 'test/ok-plugin' }, lost_import }).names)
        no_warning_about_it()
      end)

      it("for a plugin named outright", function()
        assert.are.same({ 'ok-plugin' }, updated_by('ZPack update ok-plugin', { { 'test/ok-plugin' }, lost_import }).names)
      end)

      it("and a named plugin that isn't found just says so", function()
        for _, cmd in ipairs({ 'ZPack update gamma', 'ZPack restore gamma' }) do
          _G.test_state.notifications = {}
          assert.is_nil(updated_by(cmd, { { 'test/ok-plugin' }, lost_import }))
          assert.is_not_nil(helpers.find_notification({ 'Plugin "gamma" not found in spec' }, vim.log.levels.ERROR), cmd)
          no_warning_about_it()
        end
      end)
    end)
  end)

  describe(":ZPack sync", function()
    local spec = { { 'test/ok-plugin' }, { import = 'zpack_no_such_module' } }
    local log

    local function sync(cmd)
      require('zpack').setup({ spec = spec, defaults = { confirm = false } })
      helpers.flush_pending()
      _G.test_state.registered_pack_specs['orphan'] = { src = 'test/orphan', name = 'orphan' }
      log = {}
      local update, del, confirm = vim.pack.update, vim.pack.del, vim.fn.confirm
      vim.pack.update = function(...) log[#log + 1] = 'update'; update(...) end
      vim.pack.del = function(...) log[#log + 1] = 'delete'; del(...) end
      vim.fn.confirm = function(...) log[#log + 1] = 'ask'; return confirm(...) end
      vim.cmd(cmd)
      helpers.flush_pending()
    end

    it("updates despite a spec it can't read, then asks", function()
      answer(1)
      sync('ZPack sync')
      assert.are.same({ 'update', 'ask', 'delete' }, log)
      assert.is_true(_G.test_state.vim_pack_update_calls[1].opts.force)
      assert.is_nil(_G.test_state.vim_pack_update_calls[1].names)
      assert.are.same({ 'These plugins will be deleted:\n\norphan' }, echoed)
    end)

    it("keeps the update when No deletes nothing", function()
      answer(2)
      sync('ZPack sync')
      assert.are.same({ 'update', 'ask' }, log)
    end)

    it("with a bang doesn't ask", function()
      answer(2)
      sync('ZPack! sync')
      assert.are.same({ 'update', 'delete' }, log)
    end)

    for _, cmd in ipairs({ 'ZPack sync', 'ZPack! sync' }) do
      it("skips clean when the update fails: " .. cmd, function()
        answer(1)
        vim.pack.update = function() error('Keyboard interrupt') end
        sync(cmd)
        assert.are.same({ 'update' }, log)
        assert.is_not_nil(helpers.find_notification({ 'Sync update failed' }, vim.log.levels.ERROR))
      end)
    end
  end)
end)
