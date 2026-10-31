local helpers = require('helpers')
local utils = require('zpack.utils')

local function mkplugin(opt_dir, name, with_after)
  local path = opt_dir .. '/' .. name
  vim.fn.mkdir(path .. '/lua', 'p')
  if with_after then
    vim.fn.mkdir(path .. '/after/plugin', 'p')
  end
  return path
end

describe('utils.add_packs_to_rtp', function()
  local root, opt_dir, saved_rtp, saved_pp

  before_each(function()
    saved_rtp, saved_pp = vim.go.rtp, vim.go.packpath
    root = vim.fn.tempname()
    vim.fn.mkdir(root, 'p')
    -- macOS tempname() is under a symlink, which changes how :packadd! matches rtp entries
    root = vim.uv.fs_realpath(root)
    opt_dir = root .. '/pack/core/opt'
    vim.fn.mkdir(opt_dir, 'p')
  end)

  after_each(function()
    vim.go.rtp, vim.go.packpath = saved_rtp, saved_pp
    vim.fn.delete(root, 'rf')
  end)

  ---The reference behaviour: real `:packadd!`, one plugin at a time.
  local function via_packadd(rtp, names)
    vim.go.rtp = rtp
    vim.go.packpath = root
    for _, name in ipairs(names) do
      vim.cmd.packadd({ name, bang = true })
    end
    return vim.go.rtp
  end

  local function via_batch(rtp, names)
    vim.go.rtp = rtp
    local paths = {}
    for i, name in ipairs(names) do
      paths[i] = opt_dir .. '/' .. name
    end
    local added = utils.add_packs_to_rtp(paths)
    return added, vim.go.rtp
  end

  local function assert_matches_packadd(rtp, names)
    local expected = via_packadd(rtp, names)
    local added, actual = via_batch(rtp, names)
    assert.is_true(added)
    assert.are.equal(expected, actual)
  end

  it('matches :packadd! with the pack root and after entries in rtp', function()
    mkplugin(opt_dir, 'a'); mkplugin(opt_dir, 'b', true); mkplugin(opt_dir, 'c'); mkplugin(opt_dir, 'd', true)
    assert_matches_packadd(table.concat({ '/cfg', root, '/rt', root .. '/after', '/cfg/after' }, ','), { 'a', 'b', 'c', 'd' })
  end)

  it('matches :packadd! with no after entry in rtp', function()
    mkplugin(opt_dir, 'a', true); mkplugin(opt_dir, 'b', true); mkplugin(opt_dir, 'c')
    assert_matches_packadd(table.concat({ '/cfg', root, '/rt' }, ','), { 'a', 'b', 'c' })
  end)

  it('matches :packadd! when a plugin under the root was prepended to bootstrap it', function()
    local boot = mkplugin(opt_dir, 'zpack.nvim')
    mkplugin(opt_dir, 'a'); mkplugin(opt_dir, 'b', true)
    assert_matches_packadd(table.concat({ boot, '/cfg', root, '/rt', '/cfg/after' }, ','), { 'a', 'zpack.nvim', 'b' })
  end)

  it('matches :packadd! when a sibling dir sharing the root prefix follows the root', function()
    mkplugin(opt_dir, 'a'); mkplugin(opt_dir, 'b')
    assert_matches_packadd(table.concat({ '/cfg', root, root .. '2', '/rt', '/cfg/after' }, ','), { 'a', 'b' })
  end)

  it('leaves rtp alone and defers to :packadd! when a sibling dir sharing the root prefix comes first', function()
    mkplugin(opt_dir, 'a')
    local rtp = table.concat({ '/cfg', root .. '2', root, '/rt', '/cfg/after' }, ',')
    local added, actual = via_batch(rtp, { 'a' })
    assert.is_false(added)
    assert.are.equal(rtp, actual)
  end)

  it('matches :packadd! when a symlinked dev plugin under the root was prepended', function()
    local dev = vim.fn.tempname()
    vim.fn.mkdir(dev, 'p')
    local boot = opt_dir .. '/boot'
    assert(vim.uv.fs_symlink(dev, boot))
    mkplugin(opt_dir, 'a')
    assert_matches_packadd(table.concat({ boot, '/cfg', root, '/rt', '/cfg/after' }, ','), { 'a' })
    vim.fn.delete(dev, 'rf')
  end)

  it('matches :packadd! when a symlink to the root comes before it', function()
    local alias = root .. '-alias'
    assert(vim.uv.fs_symlink(root, alias))
    mkplugin(opt_dir, 'a')
    assert_matches_packadd(table.concat({ alias, '/rt', root, '/cfg/after' }, ','), { 'a' })
    vim.fn.delete(alias)
  end)

  describe("with 'fileignorecase'", function()
    local saved_fic

    before_each(function()
      saved_fic = vim.go.fileignorecase
      vim.go.fileignorecase = true
    end)

    after_each(function()
      vim.go.fileignorecase = saved_fic
    end)

    it('matches :packadd! when the root in rtp differs in case', function()
      mkplugin(opt_dir, 'a')
      assert_matches_packadd(table.concat({ '/cfg', root:upper(), '/rt', '/cfg/after' }, ','), { 'a' })
    end)

    it('matches :packadd! when a plugin in rtp differs in case', function()
      local a = mkplugin(opt_dir, 'a', true)
      mkplugin(opt_dir, 'b')
      assert_matches_packadd(table.concat({ a:upper(), '/cfg', root, '/rt', '/cfg/after' }, ','), { 'a', 'b' })
    end)
  end)

  it('matches :packadd! when "after" is only part of an entry name', function()
    mkplugin(opt_dir, 'a', true); mkplugin(opt_dir, 'b')
    assert_matches_packadd(
      table.concat({ '/afterglow', '/x/after-all', root, '/x/after/y', '/rt', '/cfg/after' }, ','),
      { 'a', 'b' }
    )
  end)

  it('skips plugins already in rtp without adding their after dir', function()
    local a = mkplugin(opt_dir, 'a', true)
    mkplugin(opt_dir, 'b', true)
    assert_matches_packadd(table.concat({ a, '/cfg', root, '/rt', '/cfg/after' }, ','), { 'a', 'b' })
  end)

  it('leaves rtp alone and defers to :packadd! without the pack root before the first after', function()
    mkplugin(opt_dir, 'a')
    local rtp = table.concat({ '/cfg', '/rt', '/cfg/after', root }, ',')
    local added, actual = via_batch(rtp, { 'a' })
    assert.is_false(added)
    assert.are.equal(rtp, actual)
  end)

  it('leaves rtp alone and defers to :packadd! when rtp has escapes', function()
    mkplugin(opt_dir, 'a')
    local rtp = table.concat({ root, [[/odd\,dir]], '/cfg/after' }, ',')
    local added, actual = via_batch(rtp, { 'a' })
    assert.is_false(added)
    assert.are.equal(rtp, actual)
  end)

  it('leaves rtp alone and defers to :packadd! when a plugin name has a slash', function()
    mkplugin(opt_dir, 'a')
    mkplugin(opt_dir, 'foo/bar')
    mkplugin(opt_dir, 'b')
    local rtp = table.concat({ '/cfg', root, '/rt', '/cfg/after' }, ',')
    local added, actual = via_batch(rtp, { 'a', 'foo/bar', 'b' })
    assert.is_false(added)
    assert.are.equal(rtp, actual)
  end)

  it('leaves rtp alone and defers to :packadd! when a plugin is in rtp with a trailing slash', function()
    local a = mkplugin(opt_dir, 'a')
    local rtp = table.concat({ a .. '/', '/cfg', root, '/rt', '/cfg/after' }, ',')
    local added, actual = via_batch(rtp, { 'a' })
    assert.is_false(added)
    assert.are.equal(rtp, actual)
  end)

  it('leaves rtp alone and defers to :packadd! when rtp ends in a comma', function()
    mkplugin(opt_dir, 'a')
    local rtp = root .. ','
    local added, actual = via_batch(rtp, { 'a' })
    assert.is_false(added)
    assert.are.equal(rtp, actual)
  end)

  it('defers to :packadd! for an empty list', function()
    assert.is_false((via_batch(root, {})))
  end)

  for _, name in ipairs({ 'vim-afterglow', 'after', 'after.nvim' }) do
    it(('leaves rtp alone and defers to :packadd! for a plugin named %s'):format(name), function()
      mkplugin(opt_dir, name, true); mkplugin(opt_dir, 'zeta', true)
      local rtp = table.concat({ root, root .. '/after' }, ',')
      local added, actual = via_batch(rtp, { name, 'zeta' })
      assert.is_false(added)
      assert.are.equal(rtp, actual)
    end)
  end

  it('leaves rtp alone and defers to :packadd! under a root containing "after"', function()
    local rafter = root .. '/rafter/site'
    local opt = rafter .. '/pack/core/opt'
    mkplugin(opt, 'a', true); mkplugin(opt, 'b', true)
    vim.go.rtp = table.concat({ rafter, rafter .. '/after' }, ',')
    local rtp = vim.go.rtp
    assert.is_false(utils.add_packs_to_rtp({ opt .. '/a', opt .. '/b' }))
    assert.are.equal(rtp, vim.go.rtp)
  end)

  it('does not write rtp when every plugin is already active', function()
    local a = mkplugin(opt_dir, 'a', true)
    local rtp = table.concat({ a, '/cfg', root, '/rt', '/cfg/after' }, ',')
    vim.go.rtp = rtp
    local writes = 0
    local group = vim.api.nvim_create_augroup('ZpackRtpWrites', { clear = true })
    vim.api.nvim_create_autocmd('OptionSet', {
      group = group,
      pattern = 'runtimepath',
      callback = function() writes = writes + 1 end,
    })

    local added = utils.add_packs_to_rtp({ a })

    vim.api.nvim_del_augroup_by_id(group)
    assert.is_true(added)
    assert.are.equal(0, writes)
    assert.are.equal(rtp, vim.go.rtp)
  end)

  -- Catches runtime.c changing under the Lua copy: CI runs this on stable and nightly.
  describe('on random layouts', function()
    local names = { 'a', 'b', 'c', 'd', 'e' }
    local after_names = { 'after', 'vim-afterglow' }
    local saved_cwd, saved_fic, seed

    local function random(n)
      seed = (seed * 1103515245 + 12345) % 2147483648
      return math.floor(seed / 65536) % n + 1
    end

    local function random_rtp(pool)
      local entries = {}
      for i = 1, random(8) do
        entries[i] = pool[random(#pool)]
      end
      if random(10) <= 7 then
        table.insert(entries, random(#entries + 1), root)
      end
      return table.concat(entries, ',')
    end

    local function random_names()
      local picked, used = {}, {}
      for _ = 1, random(5) do
        local name = names[random(#names)]
        if not used[name] then
          used[name] = true
          picked[#picked + 1] = name
        end
      end
      -- Most layouts stay free of these, since one defers the whole batch
      if random(5) == 1 then
        table.insert(picked, random(#picked + 1), after_names[random(#after_names)])
      end
      return picked
    end

    before_each(function()
      saved_cwd, saved_fic = vim.fn.getcwd(), vim.go.fileignorecase
      for _, name in ipairs(names) do
        mkplugin(opt_dir, name, name == 'b' or name == 'd')
      end
      for _, name in ipairs(after_names) do
        mkplugin(opt_dir, name, true)
      end
      vim.fn.mkdir(root .. '2', 'p')
      vim.fn.mkdir(root .. '/sub', 'p')
      assert(vim.uv.fs_symlink(root, root .. '-alias'))
    end)

    after_each(function()
      vim.fn.chdir(saved_cwd)
      vim.go.fileignorecase = saved_fic
      vim.fn.delete(root .. '2', 'rf')
      vim.fn.delete(root .. '-alias')
    end)

    for fic_index, fic in ipairs({ false, true }) do
      -- Relative and empty entries only reach the root from some directories
      for cwd_index, cwd in ipairs({ '..', '.', 'sub', 'pack/core/opt' }) do
        it(("matches :packadd! with fileignorecase=%s from <root>/%s"):format(fic, cwd), function()
          seed = 42 + 10 * fic_index + cwd_index
          vim.go.fileignorecase = fic
          vim.fn.chdir(root .. '/' .. cwd)
          local base = vim.fs.basename(root)
          local pool = {
            '/cfg', '/rt', root, root .. '/', root .. '//', './' .. base, base, base .. '/',
            root .. '/sub', root .. '/none', root .. '2', root .. '-alias', root .. '-alias/',
            opt_dir .. '/a', opt_dir .. '/b', opt_dir .. '/c/', opt_dir .. '/d//', opt_dir .. '/b/after',
            opt_dir .. '/after', opt_dir .. '/vim-afterglow/after',
            root .. '-alias/pack/core/opt/a', '/cfg/after', '/x/after/y', '/afterglow', root .. '/after',
            'after', './after', '/after', '', '~/x', '$HOME/x', '/a b', '.', '..', '../nosuch',
          }
          local batched = 0
          for _ = 1, 250 do
            local rtp, picked = random_rtp(pool), random_names()
            vim.go.rtp = rtp
            -- Nightly expands ~ and $VARs on write
            local unchanged = vim.go.rtp
            local added, actual = via_batch(rtp, picked)
            if added then
              batched = batched + 1
              local context = ('rtp=%s plugins=%s'):format(rtp, table.concat(picked, ' '))
              assert.are.equal(via_packadd(rtp, picked), actual, context)
            else
              assert.are.equal(unchanged, actual)
            end
          end
          assert.is_true(batched > 50)
        end)
      end
    end
  end)
end)

describe('eager plugins at startup', function()
  local root, opt_dir, saved_rtp, saved_pp, base_rtp

  local function packadd_rejects(rejected)
    vim.cmd.packadd = function(args)
      table.insert(_G.test_state.loaded_plugins, args[1])
      if rejected[args[1]] then
        error('simulated packadd failure', 0)
      end
    end
  end

  before_each(function()
    helpers.setup_test_env()
    saved_rtp, saved_pp = vim.go.rtp, vim.go.packpath
    local data = vim.fn.tempname()
    vim.fn.mkdir(data, 'p')
    data = vim.uv.fs_realpath(data)
    root = data .. '/site'
    opt_dir = root .. '/pack/zpack/opt'
    vim.fn.mkdir(opt_dir, 'p')
    local stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      return what == 'data' and data or stdpath(what)
    end
    base_rtp = table.concat({ '/cfg', root, vim.env.VIMRUNTIME, '/cfg/after' }, ',')
    vim.go.rtp = base_rtp
    vim.go.packpath = root
  end)

  after_each(function()
    vim.fn.delete(vim.fs.dirname(root), 'rf')
    vim.go.rtp, vim.go.packpath = saved_rtp, saved_pp
    helpers.cleanup_test_env()
  end)

  it('reach rtp as :packadd! would, without calling it', function()
    mkplugin(opt_dir, 'a', true); mkplugin(opt_dir, 'b'); mkplugin(opt_dir, 'c', true)
    local native_packadd = _G.test_state.original_vim_cmd_packadd
    for _, name in ipairs({ 'c', 'b', 'a' }) do
      native_packadd({ name, bang = true })
    end
    local expected = vim.go.rtp
    vim.go.rtp = base_rtp

    local configured = {}
    local function spec(name, priority)
      return { 'test/' .. name, priority = priority, config = function() table.insert(configured, name) end }
    end
    require('zpack').setup({
      spec = { spec('c', 1), spec('a', 100), spec('b', 50) },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.equal(expected, vim.go.rtp)
    assert.are.same({}, _G.test_state.loaded_plugins)
    assert.are.same({ 'a', 'b', 'c' }, configured)
    assert.are.equal('loaded', require('zpack.state').spec_registry['https://github.com/test/a'].load_status)
  end)

  it('keep the after dir order of :packadd! with "after" in a plugin name', function()
    mkplugin(opt_dir, 'vim-afterglow', true); mkplugin(opt_dir, 'zeta', true)
    local native_packadd = _G.test_state.original_vim_cmd_packadd
    vim.cmd.packadd = native_packadd
    vim.go.rtp = table.concat({ root, root .. '/after' }, ',')
    local start = vim.go.rtp
    for _, name in ipairs({ 'zeta', 'vim-afterglow' }) do
      native_packadd({ name, bang = true })
    end
    local expected = vim.go.rtp
    vim.go.rtp = start

    require('zpack').setup({
      spec = { { 'test/vim-afterglow', priority = 100 }, { 'test/zeta', priority = 1 } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.equal(expected, vim.go.rtp)
  end)

  it('leave every plugin to :packadd! when a path is not a directory, which fails it', function()
    mkplugin(opt_dir, 'good')
    vim.fn.writefile({}, opt_dir .. '/file')
    packadd_rejects({ file = true })

    local configured = {}
    local function spec(name)
      return { 'test/' .. name, config = function() table.insert(configured, name) end }
    end
    require('zpack').setup({ spec = { spec('file'), spec('good') }, defaults = { confirm = false } })
    helpers.flush_pending()

    table.sort(_G.test_state.loaded_plugins)
    assert.are.same({ 'file', 'good' }, _G.test_state.loaded_plugins)
    assert.are.same({ 'good' }, configured)
    assert.is_nil(vim.go.rtp:find(opt_dir .. '/file', 1, true))
    assert.are_not.equal('loaded', require('zpack.state').spec_registry['https://github.com/test/file'].load_status)
  end)

  it('keep load order in rtp when one is only found as another pack copy', function()
    mkplugin(opt_dir, 'y'); mkplugin(opt_dir, 'z')
    vim.fn.mkdir(root .. '/pack/vendored/opt/x/lua', 'p')
    local native_packadd = _G.test_state.original_vim_cmd_packadd
    vim.cmd.packadd = native_packadd
    for _, name in ipairs({ 'z', 'y', 'x' }) do
      native_packadd({ name, bang = true })
    end
    local expected = vim.go.rtp
    vim.go.rtp = base_rtp

    local function spec(name, priority)
      return { 'test/' .. name, priority = priority }
    end
    require('zpack').setup({
      spec = { spec('x', 100), spec('y', 50), spec('z', 1) },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.equal(expected, vim.go.rtp)
  end)

  it('survive an init hook deleting one of them', function()
    mkplugin(opt_dir, 'gone'); mkplugin(opt_dir, 'kept')
    vim.cmd.packadd = _G.test_state.original_vim_cmd_packadd
    local configured = false
    require('zpack').setup({
      spec = {
        { 'test/gone', init = function()
          vim.fn.delete(opt_dir .. '/gone', 'rf')
          require('zpack.state').remove_plugin('gone', 'https://github.com/test/gone')
        end },
        { 'test/kept', config = function() configured = true end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_true(configured)
    assert.is_nil(vim.go.rtp:find(opt_dir .. '/gone', 1, true))
    assert.is_truthy(vim.go.rtp:find(opt_dir .. '/kept', 1, true))
  end)
end)
