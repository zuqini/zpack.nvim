-- Real nvim processes: the suite's stubbed vim.v can't reproduce startup's phases.
describe("a real startup", function()
  local root, repos

  local function make_repo(name)
    local repo = repos .. '/' .. name
    vim.fn.mkdir(repo .. '/plugin', 'p')
    vim.fn.mkdir(repo .. '/after/plugin', 'p')
    vim.fn.writefile({ ("table.insert(_G.LOG, '%s.plugin')"):format(name) }, repo .. '/plugin/' .. name .. '.lua')
    vim.fn.writefile({ ("table.insert(_G.LOG, '%s.after')"):format(name) }, repo .. '/after/plugin/' .. name .. '.lua')
    vim.fn.mkdir(repo .. '/lua', 'p')
    vim.fn.writefile({ 'return {}' }, repo .. '/lua/' .. name .. '.lua')
    for _, args in ipairs({
      { 'init', '-q' },
      { 'add', '.' },
      { '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'init' },
    }) do
      local result = vim.system(vim.list_extend({ 'git', '-C', repo }, args)):wait()
      assert.are.equal(0, result.code, result.stderr)
    end
    return 'file://' .. repo
  end

  ---@param spec_body string Lua for the spec list, with `aa`, `bb` and `cc` as repo URLs
  ---@param opts? { after_setup?: string, late?: boolean, noplugin?: boolean } Lua to run in init.lua after setup(), setup() at VimEnter, or --noplugin
  ---@return string[] log what ran by the time VimEnter's autocmds finished
  local function start(spec_body, opts)
    opts = opts or {}
    local home = root .. '/home'
    vim.fn.delete(home, 'rf')
    vim.fn.mkdir(home .. '/config/nvim', 'p')
    local out = root .. '/log.json'
    local init = home .. '/config/nvim/init.lua'
    vim.fn.writefile({
      '_G.LOG = {}',
      ("vim.opt.rtp:prepend(%q)"):format(vim.fn.getcwd()),
      ("local aa, bb, cc = %q, %q, %q"):format(make_repo('aa'), make_repo('bb'), make_repo('cc')),
      "local function setup()",
      ("  require('zpack').setup({ spec = %s, defaults = { confirm = false } })"):format((spec_body:gsub('\n', ' '))),
      "end",
      opts.late and '' or 'setup()',
      opts.after_setup or '',
      "vim.api.nvim_create_autocmd('VimEnter', { callback = function()",
      opts.late and '  setup()' or '',
      ("  vim.fn.writefile({ vim.json.encode(_G.LOG) }, %q)"):format(out),
      "  vim.cmd('qa!')",
      "end })",
    }, init)

    local result = vim.system(
      { vim.v.progpath, '--headless', opts.noplugin and '--noplugin' or '--headless', '-u', init, init },
      {
        timeout = 30000,
        env = {
          XDG_CONFIG_HOME = home .. '/config',
          XDG_DATA_HOME = home .. '/data',
          XDG_STATE_HOME = home .. '/state',
          XDG_CACHE_HOME = home .. '/cache',
        },
      }
    ):wait()
    assert.are.equal(0, result.code, result.stderr)
    return vim.json.decode(vim.fn.readfile(out)[1])
  end

  before_each(function()
    root = vim.fn.tempname()
    repos = root .. '/repos'
    vim.fn.mkdir(repos, 'p')
  end)

  after_each(function()
    vim.fn.delete(root, 'rf')
  end)

  it("sources after/plugin for a lazy plugin the startup file loads", function()
    local log = start([[{
      { url = aa, name = 'aa', event = 'BufReadPost', dependencies = { { url = bb, name = 'bb' } } },
    }]])
    table.sort(log)
    assert.are.same({ 'aa.after', 'aa.plugin', 'bb.after', 'bb.plugin' }, log)
  end)

  it("sources after/plugin once for a lazy plugin loaded during init", function()
    local log = start(
      [[{ { url = aa, name = 'aa', event = 'User EarlyX' } }]],
      { after_setup = "vim.api.nvim_exec_autocmds('User', { pattern = 'EarlyX' })" }
    )
    assert.are.equal(1, #vim.tbl_filter(function(entry) return entry == 'aa.after' end, log))
  end)

  it("sources after/plugin for a lazy plugin loaded during init with --noplugin", function()
    local log = start(
      [[{ { url = aa, name = 'aa', event = 'User EarlyX' } }]],
      { after_setup = "vim.api.nvim_exec_autocmds('User', { pattern = 'EarlyX' })", noplugin = true }
    )
    assert.are.same({ 'aa.plugin', 'aa.after' }, log)
  end)

  it("sources after/plugin once for an eager plugin", function()
    local log = start([[{ { url = aa, name = 'aa' } }]])
    assert.are.same({ 'aa.plugin', 'aa.after' }, log)
  end)

  describe("an eager plugin a lazy plugin depends on, loaded during the eager configs", function()
    local eager = [[{ url = aa, name = 'aa', priority = %d,
      config = function() table.insert(_G.LOG, 'aa.config') end }]]
    local lazy_bb = [[{ url = bb, name = 'bb', cmd = 'Foo', dependencies = { { url = aa, name = 'aa' } },
      config = function() table.insert(_G.LOG, 'bb.config') end }]]

    local function count(log, wanted)
      return #vim.tbl_filter(function(entry) return entry == wanted end, log)
    end

    local function assert_ran_once(log)
      assert.are.equal(1, count(log, 'aa.config'))
      assert.are.equal(1, count(log, 'bb.config'))
      assert.is_true(vim.fn.index(log, 'aa.config') < vim.fn.index(log, 'bb.config'))
    end

    for order, priority in pairs({ ['before'] = 100, ['after'] = 10 }) do
      it(("runs its config once when it comes %s the plugin listing the lazy one"):format(order), function()
        local log = start(('{ %s, %s, { url = cc, name = \'cc\', priority = 50, dependencies = { { url = bb, name = \'bb\' } } } }')
          :format(eager:format(priority), lazy_bb))
        assert_ran_once(log)
      end)

      it(("runs its config once when it comes %s the plugin whose config requires the lazy one"):format(order), function()
        local log = start(('{ %s, %s, { url = cc, name = \'cc\', priority = 50, config = function() require(\'bb\') end } }')
          :format(eager:format(priority), lazy_bb))
        assert_ran_once(log)
      end)

      it(("runs its config once when setup() runs at VimEnter and it comes %s"):format(order), function()
        local log = start(('{ %s, %s, { url = cc, name = \'cc\', priority = 50, dependencies = { { url = bb, name = \'bb\' } } } }')
          :format(eager:format(priority), lazy_bb), { late = true })
        assert_ran_once(log)
      end)
    end

    it("doesn't run it again from a lazy plugin its own config requires", function()
      local log = start(([[{ { url = aa, name = 'aa',
        config = function() table.insert(_G.LOG, 'aa.config'); require('bb') end },
        %s }]]):format(lazy_bb))
      assert.are.equal(1, count(log, 'aa.config'))
      assert.are.equal(1, count(log, 'bb.config'))
    end)
  end)

  describe("a plugin's modules after an import of its specs", function()
    local require_aa = "package.loaded.aa = nil; table.insert(_G.LOG, 'require:' .. tostring(pcall(require, 'aa')))"
    local own = "{ url = aa, name = 'aa', import = 'aa' }"

    it("aren't within reach if cond keeps it from loading", function()
      local log = start(("{ %s, { url = aa, name = 'aa', cond = false } }"):format(own), { after_setup = require_aa })
      assert.is_true(vim.list_contains(log, 'require:false'))
      assert.is_false(vim.list_contains(log, 'aa.plugin'))
    end)

    it("load it if it's lazy", function()
      local log = start("{ { url = aa, name = 'aa', import = 'aa', lazy = true } }", { after_setup = require_aa })
      assert.is_true(vim.list_contains(log, 'require:true'))
    end)

    it("stay in reach of an init, before an eager plugin is on 'runtimepath'", function()
      local log = start(("{ %s, { url = bb, name = 'bb', init = function() %s end } }"):format(own, require_aa))
      assert.is_true(vim.list_contains(log, 'require:true'))
    end)

    it("are on 'runtimepath' after startup if it's eager", function()
      local log = start(own, { after_setup = require_aa })
      assert.is_true(vim.list_contains(log, 'require:true'))
    end)
  end)

  it("sources after/plugin for an eager plugin when setup() runs at VimEnter", function()
    local log = start([[{ { url = aa, name = 'aa' } }]], { late = true })
    assert.are.same({ 'aa.plugin', 'aa.after' }, log)
  end)
end)

describe("sessions over one data directory", function()
  local root, home, urls

  local function git(repo, ...)
    local args = { 'git', '-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', ... }
    local result = vim.system(args):wait()
    assert.are.equal(0, result.code, result.stderr)
  end

  ---@param name string
  ---@param files? { [string]: string[] } Beyond the plugin/ script that logs its name
  local function make_repo(name, files)
    local repo = root .. '/repos/' .. name
    vim.fn.mkdir(repo .. '/plugin', 'p')
    vim.fn.writefile({ ("table.insert(_G.LOG, '%s.plugin')"):format(name) }, repo .. '/plugin/' .. name .. '.lua')
    for path, lines in pairs(files or {}) do
      vim.fn.mkdir(vim.fs.dirname(repo .. '/' .. path), 'p')
      vim.fn.writefile(lines, repo .. '/' .. path)
    end
    git(repo, 'init', '-q', '-b', 'main')
    git(repo, 'add', '.')
    git(repo, 'commit', '-qm', 'init')
    urls[name] = 'file://' .. repo
    return repo
  end

  ---@param spec_body string Lua for setup()'s options, with each repo's name as its URL
  ---@param at_enter? string Lua to run once startup has finished, logging to _G.LOG
  ---@param before_setup? string Lua to run in init.lua before setup()
  ---@param opts? { late?: boolean, args?: string[], stdin?: boolean|string } setup() at VimEnter, nvim's arguments, and its stdin as in vim.system
  ---@return { log: string[], notes: string[] }
  local function session(spec_body, at_enter, before_setup, opts)
    opts = opts or {}
    vim.fn.mkdir(home .. '/config/nvim', 'p')
    local out = root .. '/log.json'
    vim.fn.delete(out)
    local init = home .. '/config/nvim/init.lua'
    local lines = {
      '_G.LOG, _G.NOTES = {}, {}',
      "vim.notify = function(msg) table.insert(_G.NOTES, tostring(msg)) end",
      ("vim.opt.rtp:prepend(%q)"):format(vim.fn.getcwd()),
      "local function on_disk(name) return vim.uv.fs_stat(vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. name) ~= nil end",
      "local function in_git(name, ...) return vim.trim(vim.fn.system({ 'git', '-C', vim.fn.stdpath('data') .. '/site/pack/core/opt/' .. name, ... })) end",
    }
    for name, url in pairs(urls) do
      if name ~= 'zpack.nvim' then
        lines[#lines + 1] = ("local %s = %q"):format(name, url)
      end
    end
    vim.list_extend(lines, {
      before_setup or '',
      ("local function setup() require('zpack').setup(%s) end"):format((spec_body:gsub('\n', ' '))),
      opts.late and '' or 'setup()',
      "vim.api.nvim_create_autocmd('VimEnter', { callback = function() vim.schedule(function()",
      opts.late and 'setup()' or '',
      at_enter or '',
      "  vim.wait(100)",
      ("  vim.fn.writefile({ vim.json.encode({ log = _G.LOG, notes = _G.NOTES }) }, %q)"):format(out),
      "  vim.cmd('qa!')",
      "end) end })",
    })
    vim.fn.writefile(lines, init)

    local cmd = vim.list_extend({ vim.v.progpath, '--headless', '-u', init }, opts.args or {})
    local result = vim.system(cmd, {
      stdin = opts.stdin,
      timeout = 30000,
      env = {
        XDG_CONFIG_HOME = home .. '/config',
        XDG_DATA_HOME = home .. '/data',
        XDG_STATE_HOME = home .. '/state',
        XDG_CACHE_HOME = home .. '/cache',
      },
    }):wait()
    assert.are.equal(0, result.code, result.stderr)
    return vim.json.decode(vim.fn.readfile(out)[1])
  end

  before_each(function()
    root = vim.fn.tempname()
    home = root .. '/home'
    urls = {}
  end)

  after_each(function()
    vim.fn.delete(root, 'rf')
  end)

  ---Keeps a note of the list that was echoed and what vim.fn.confirm was asked, and answers.
  local function answering(choice)
    return table.concat({
      "local echo = vim.api.nvim_echo",
      "vim.api.nvim_echo = function(chunks, ...)",
      "  if chunks[1][1]:find('^These plugins') then table.insert(_G.LOG, 'listed: ' .. chunks[1][1]) else echo(chunks, ...) end",
      "end;",
      ("_G.PROMPTS = {}; vim.fn.confirm = function(msg) table.insert(_G.PROMPTS, msg); table.insert(_G.LOG, 'asked: ' .. msg); return %d end"):format(choice),
    }, ' ')
  end

  describe("a vim.pack.add that raises for the whole call", function()
    local both = "{ url = aa, name = 'aa' }, { url = bb, name = 'bb' }"
    local broken = ("{ spec = { %s, { src = '', name = 'cc' } }, defaults = { confirm = false } }"):format(both)
    local report = "table.insert(_G.LOG, 'aa=' .. tostring(on_disk('aa'))); table.insert(_G.LOG, 'bb=' .. tostring(on_disk('bb')))"

    before_each(function()
      make_repo('aa')
      make_repo('bb')
      session(('{ spec = { %s }, defaults = { confirm = false } }'):format(both))
    end)

    for _, cmd in ipairs({ 'clean', 'sync' }) do
      it(":ZPack " .. cmd .. " lists every plugin, and No deletes nothing", function()
        local result = session(broken, ("vim.cmd('ZPack %s'); vim.wait(1000); %s"):format(cmd, report), answering(2))
        assert.are.same({ 'listed: These plugins will be deleted:\n\naa\nbb', 'asked: Delete these 2 plugins?', 'aa=true', 'bb=true' }, result.log)
        assert.is_truthy(table.concat(result.notes, '\n'):find('Nothing deleted', 1, true))
      end)

      it(":ZPack " .. cmd .. " in a headless process deletes nothing, unprompted", function()
        local result = session(broken, ("vim.cmd('ZPack %s'); vim.wait(1000); %s"):format(cmd, report))
        assert.are.same({ 'aa=true', 'bb=true' }, result.log)
      end)
    end

    it("deletes what it listed on Yes", function()
      local result = session(broken, ("vim.cmd('ZPack clean'); vim.wait(1000); %s"):format(report), answering(1))
      assert.are.same({ 'listed: These plugins will be deleted:\n\naa\nbb', 'asked: Delete these 2 plugins?', 'aa=false', 'bb=false' }, result.log)
    end)
  end)

  describe(":ZPack clean over a plugin no longer in the spec", function()
    local both = "{ spec = { { url = aa, name = 'aa' }, { url = bb, name = 'bb' } }, defaults = { confirm = false } }"
    local just_aa = "{ spec = { { url = aa, name = 'aa', lazy = true } }, defaults = { confirm = false } }"
    local function clean(cmd)
      return ("vim.cmd('%s'); vim.wait(500); table.insert(_G.LOG, 'aa=' .. tostring(on_disk('aa'))); table.insert(_G.LOG, 'bb=' .. tostring(on_disk('bb')))"):format(cmd)
    end

    before_each(function()
      make_repo('aa')
      make_repo('bb')
      session(both)
    end)

    for label, stdin in pairs({
      ['at EOF'] = false,
      ['held open'] = true,
      ['holding a y'] = 'y\n',
    }) do
      it("deletes nothing in a headless process with stdin " .. label, function()
        local result = session(just_aa, clean('ZPack clean'), nil, { stdin = stdin or nil })
        assert.are.same({ 'aa=true', 'bb=true' }, result.log)
        assert.is_truthy(table.concat(result.notes, '\n'):find('Nothing deleted', 1, true))
      end)
    end

    for _, cmd in ipairs({ 'ZPack clean', 'ZPack sync' }) do
      it(("says it deleted nothing before +qa ends a headless +%s"):format(cmd), function()
        local out = root .. '/log.json'
        local write = ("+lua vim.fn.writefile({ vim.json.encode({ log = _G.LOG, notes = _G.NOTES }) }, %q)"):format(out)
        local result = session(just_aa, nil, nil, { args = { '+' .. cmd, write, '+qa' } })
        assert.is_truthy(table.concat(result.notes, '\n'):find('Nothing deleted', 1, true), vim.inspect(result.notes))
      end)
    end

    it("deletes nothing on No", function()
      local result = session(just_aa, clean('ZPack clean'), answering(2))
      assert.are.same({ 'listed: These plugins will be deleted:\n\nbb', 'asked: Delete this plugin?', 'aa=true', 'bb=true' }, result.log)
    end)

    it("deletes through vim.pack on Yes", function()
      local result = session(just_aa, clean('ZPack clean'), answering(1))
      assert.are.same({ 'listed: These plugins will be deleted:\n\nbb', 'asked: Delete this plugin?', 'aa=true', 'bb=false' }, result.log)
      assert.is_truthy(table.concat(result.notes, '\n'):find('Deleting 1 unused', 1, true))
    end)

    it("deletes without asking on a bang, in a headless process", function()
      assert.are.same({ 'aa=true', 'bb=false' }, session(just_aa, clean('ZPack! clean')).log)
    end)

    it("doesn't take defaults.confirm = false to mean yes", function()
      local result = session(just_aa, clean('ZPack clean'))
      assert.are.same({ 'aa=true', 'bb=true' }, result.log)
      assert.are.same({ 'listed: These plugins will be deleted:\n\nbb', 'asked: Delete this plugin?', 'aa=true', 'bb=true' },
        session(just_aa, clean('ZPack clean'), answering(2)).log)
    end)

    describe("from :ZPack sync", function()
      local head_at_prompt = "vim.fn.confirm = function() table.insert(_G.LOG, 'asked at ' .. in_git('aa', 'log', '-1', '--format=%%s')); return %d end"

      before_each(function()
        git(root .. '/repos/aa', 'commit', '-q', '--allow-empty', '-m', 'two')
      end)

      it("asks only once the update has finished, and No keeps the plugin", function()
        local result = session(just_aa, clean('ZPack sync'), head_at_prompt:format(2))
        assert.are.same({ 'asked at two', 'aa=true', 'bb=true' }, result.log)
      end)

      it("deletes on Yes", function()
        local result = session(just_aa, clean('ZPack sync'), head_at_prompt:format(1))
        assert.are.same({ 'asked at two', 'aa=true', 'bb=false' }, result.log)
      end)

      it("deletes nothing in a headless process", function()
        assert.are.same({ 'aa=true', 'bb=true' }, session(just_aa, clean('ZPack sync')).log)
      end)

      it("doesn't ask on a bang", function()
        local result = session(just_aa, clean('ZPack! sync'), head_at_prompt:format(2))
        assert.are.same({ 'aa=true', 'bb=false' }, result.log)
      end)

      it("doesn't clean when the update fails", function()
        local result = session(just_aa, clean('ZPack! sync'), "vim.pack.update = function() error('Keyboard interrupt') end")
        assert.are.same({ 'aa=true', 'bb=true' }, result.log)
        assert.is_truthy(table.concat(result.notes, '\n'):find('Sync update failed', 1, true))
      end)
    end)
  end)

  it("a typo in a repo's url lists the plugin it was meant to be, and No keeps it", function()
    make_repo('gone')
    make_repo('aa')
    session("{ spec = { { url = gone }, { url = aa, lazy = true } }, defaults = { confirm = false } }")
    local result = session(
      "{ spec = { { url = gone .. 'typo' }, { url = aa, lazy = true } }, defaults = { confirm = false } }",
      "vim.cmd('ZPack clean'); vim.wait(1000); table.insert(_G.LOG, tostring(on_disk('gone')))",
      answering(2)
    )
    assert.are.same({ 'listed: These plugins will be deleted:\n\ngone', 'asked: Delete this plugin?', 'true' }, result.log)
    assert.is_truthy(table.concat(result.notes, '\n'):find('gonetypo', 1, true))
  end)

  it(":ZPack clean doesn't raise over an import owner the final resolve pruned, and removes it next session", function()
    make_repo('dd', { ['lua/dd/plugins.lua'] = { 'return { { url = _G.dd, enabled = false } }' } })
    local spec = "{ spec = { { url = dd, name = 'dd', import = 'dd.plugins' } }, defaults = { confirm = false } }"
    local clean = "vim.cmd('ZPack! clean'); vim.wait(500); table.insert(_G.LOG, tostring(on_disk('dd')))"
    local result = session(spec, "table.insert(_G.LOG, 'present=' .. tostring(on_disk('dd'))); " .. clean, "_G.dd = dd")
    assert.is_true(vim.list_contains(result.log, 'present=true'))
    assert.is_falsy(table.concat(result.notes, '\n'):find('active', 1, true))
    assert.are.equal('true', result.log[#result.log])
    assert.are.equal('false', session(spec, clean, "_G.dd = dd").log[1])
  end)

  describe("an import of a plugin's module", function()
    local report = "table.insert(_G.LOG, 'aa=' .. tostring(on_disk('aa'))); table.insert(_G.LOG, 'dist=' .. tostring(on_disk('dist')))"

    local function make_dist()
      make_repo('aa')
      make_repo('dist', { ['lua/dist/plugins/extra.lua'] = { "return { { url = _G.aa, name = 'aa' } }" } })
    end

    it("on the plugin's own spec, installs it and imports on the first start", function()
      make_dist()
      local result = session(
        "{ spec = { { dist, import = 'dist.plugins.extra' } }, defaults = { confirm = false } }",
        report, "_G.aa = aa")
      assert.is_true(vim.list_contains(result.log, 'aa=true'))
      assert.is_true(vim.list_contains(result.log, 'dist=true'))
      local notes = table.concat(result.notes, '\n')
      assert.is_falsy(notes:find('no specs found', 1, true), notes)
    end)

    it("ends beside a bare string that won't install", function()
      vim.env.GIT_CONFIG_COUNT = '1'
      vim.env.GIT_CONFIG_KEY_0 = 'url.file:///no/.insteadOf'
      vim.env.GIT_CONFIG_VALUE_0 = 'https://github.com/no/'
      local ok, result = pcall(session,
        "{ spec = { 'no/such-repo', { import = 'x' } }, defaults = { confirm = false } }",
        "table.insert(_G.LOG, 'entered')")
      vim.env.GIT_CONFIG_COUNT, vim.env.GIT_CONFIG_KEY_0, vim.env.GIT_CONFIG_VALUE_0 = nil, nil, nil
      assert.is_true(ok, result)
      assert.are.same({ 'entered' }, result.log)
      assert.is_truthy(table.concat(result.notes, '\n'):find('no specs found', 1, true))
    end)
  end)

  describe("an import with no plugin of its own", function()
    local report = table.concat({
      "local names = {}",
      "for _, p in ipairs(require('zpack').get_plugins()) do names[#names + 1] = p.name .. (p.lazy and ':lazy' or ':eager') end",
      "table.sort(names)",
      "table.insert(_G.LOG, 'plugins=' .. table.concat(names, ','))",
    }, '; ')
    local read_one = { "table.insert(_G.LOG, 'read dist.one')", "return { { 'u/aa', lazy = true } }" }

    before_each(function()
      vim.env.GIT_CONFIG_COUNT = '1'
      vim.env.GIT_CONFIG_KEY_0 = 'url.file://' .. root .. '/repos/.insteadOf'
      vim.env.GIT_CONFIG_VALUE_0 = 'https://github.com/u/'
    end)

    after_each(function()
      vim.env.GIT_CONFIG_COUNT, vim.env.GIT_CONFIG_KEY_0, vim.env.GIT_CONFIG_VALUE_0 = nil, nil, nil
    end)

    local function plugins(result)
      for _, line in ipairs(result.log) do
        if vim.startswith(line, 'plugins=') then
          return line
        end
      end
    end

    local function spec(body)
      return ("{ spec = { %s }, defaults = { confirm = false } }"):format(body)
    end

    local function assert_found(result)
      local notes = table.concat(result.notes, '\n')
      assert.is_falsy(notes:find('no specs found', 1, true), notes)
    end

    local function assert_warned(result)
      local notes = table.concat(result.notes, '\n')
      assert.is_truthy(notes:find('no specs found', 1, true), notes)
    end

    ---Over a fresh data directory and again over the installed one.
    local function both_starts(body, wanted)
      local first = session(spec(body), report)
      assert_found(first)
      local later = session(spec(body), report)
      assert_found(later)
      assert.are.equal(plugins(first), plugins(later))
      assert.are.equal(wanted, plugins(later))
      return first, later
    end

    it("as in AstroNvim's template, finds it in the plugin listed beside it", function()
      make_repo('aa')
      vim.env.GIT_CONFIG_COUNT = '2'
      vim.env.GIT_CONFIG_KEY_1 = vim.env.GIT_CONFIG_KEY_0
      vim.env.GIT_CONFIG_VALUE_1 = 'https://github.com/AstroNvim/'
      make_repo('astrocommunity', { ['lua/astrocommunity/pack/lua/init.lua'] = { "return { { 'u/aa' } }" } })
      local ok, err = pcall(both_starts, "{ 'AstroNvim/astrocommunity', { import = 'astrocommunity.pack.lua' } }",
        'plugins=aa:eager,astrocommunity:eager')
      vim.env.GIT_CONFIG_KEY_1, vim.env.GIT_CONFIG_VALUE_1 = nil, nil
      assert.is_true(ok, err)
    end)

    it("finds each of several in a plugin listed apart", function()
      make_repo('aa')
      make_repo('bb')
      make_repo('dist', {
        ['lua/dist/one.lua'] = { "return { { 'u/aa' } }" },
        ['lua/dist/two/init.lua'] = { "return { { 'u/bb', lazy = true } }" },
      })
      both_starts("{ { 'u/dist' }, { import = 'dist.one' }, { import = 'dist.two' } }",
        'plugins=aa:eager,bb:lazy,dist:eager')
    end)

    it("finds it in a plugin listed after it", function()
      make_repo('aa')
      make_repo('dist', { ['lua/dist/one.lua'] = read_one })
      both_starts("{ { import = 'dist.one' }, { 'u/dist' } }", 'plugins=aa:lazy,dist:eager')
    end)

    it("finds it in a plugin the found module lists, for an import that module lists", function()
      make_repo('aa')
      make_repo('nested', { ['lua/nested/x.lua'] = { "return { { 'u/aa' } }" } })
      make_repo('dist', { ['lua/dist/one.lua'] = { "return { { 'u/nested' }, { import = 'nested.x' } }" } })
      both_starts("{ { 'u/dist' }, { import = 'dist.one' } }", 'plugins=aa:eager,dist:eager,nested:eager')
    end)

    it("reads an optional owner's import once what it found keeps that owner", function()
      make_repo('cc')
      make_repo('xx', { ['lua/xx/a.lua'] = { "return { { 'u/cc' } }" } })
      make_repo('dist', { ['lua/dist/one.lua'] = { "return { { 'u/xx' } }" } })
      both_starts("{ 'u/xx', optional = true, import = 'xx.a' }, { 'u/dist' }, { import = 'dist.one' }",
        'plugins=cc:eager,dist:eager,xx:eager')
    end)

    it("reads what a module found a pass late lists, beside an owner that's dropped", function()
      make_repo('aa')
      make_repo('cc')
      make_repo('gone')
      make_repo('nested', { ['lua/nested/x.lua'] = { "return { { 'u/cc' } }" } })
      make_repo('dist', {
        ['lua/dist/one.lua'] = { "return { { 'u/nested' }, { import = 'nested.x' } }" },
        ['lua/dist/two.lua'] = { "return { { 'u/aa' } }" },
      })
      both_starts(
        "{ import = 'dist.one' }, { 'u/dist', import = 'dist.two' }, { 'u/gone', import = 'gone.x' }, { 'u/gone', enabled = false }",
        'plugins=aa:eager,cc:eager,dist:eager,nested:eager')
    end)

    it("finds it through a bare name for the plugin", function()
      make_repo('aa')
      make_repo('dist', { ['lua/dist/one.lua'] = read_one })
      both_starts("{ { 'dist', import = 'dist.one' }, { 'u/dist' } }", 'plugins=aa:lazy,dist:eager')
    end)

    it("merges what it found at the import's list position, on both starts", function()
      make_repo('aa')
      make_repo('dist', { ['lua/dist/one.lua'] = { "return { { 'u/aa', opts = { list = { 'imported' }, last = 'imported' } } }" } })
      local body = [[
        { 'u/aa', opts_extend = { 'list' }, opts = { list = { 'before' }, last = 'before' },
          config = function(_, opts) table.insert(_G.LOG, 'opts=' .. table.concat(opts.list, ',') .. ' last=' .. opts.last) end },
        { 'u/dist' },
        { import = 'dist.one' },
        { 'u/aa', opts = { list = { 'after' }, last = 'after' } },
      ]]
      local first, later = both_starts(body, 'plugins=aa:eager,dist:eager')
      for _, result in ipairs({ first, later }) do
        assert.is_true(vim.list_contains(result.log, 'opts=before,imported,after last=after'), vim.inspect(result.log))
      end
    end)

    describe("doesn't read it from a plugin that's dropped", function()
      local bodies = {
        ["with enabled = false"] = "{ 'u/dist', enabled = false }, { import = 'dist.one' }",
        ["by a later fragment"] = "{ 'u/dist' }, { import = 'dist.one' }, { 'u/dist', enabled = false }",
        ["by a function-form enabled"] = "{ 'u/dist', enabled = function() table.insert(_G.LOG, 'asked'); return false end }, { import = 'dist.one' }",
        ["by the last spec's enabled"] = "{ 'u/dist', enabled = true }, { 'u/dist', enabled = false }, { import = 'dist.one' }",
        ["under a disabled parent"] = "{ 'u/parent', enabled = false, dependencies = { { 'u/dist' } } }, { import = 'dist.one' }",
        ["whose every fragment is optional"] = "{ 'u/dist', optional = true }, { import = 'dist.one' }",
      }
      for label, body in pairs(bodies) do
        it(label .. ", installed or not", function()
          make_repo('aa')
          make_repo('parent')
          make_repo('dist', { ['lua/dist/one.lua'] = read_one })
          local fresh = session(spec(body), report)
          assert_warned(fresh)
          assert.is_false(vim.list_contains(fresh.log, 'read dist.one'))
          local log = session(spec(body), "table.insert(_G.LOG, tostring(on_disk('dist')))").log
          assert.are.equal('false', log[#log])

          session(spec("{ 'u/dist' }"))
          local installed = session(spec(body), report)
          assert_warned(installed)
          assert.is_false(vim.list_contains(installed.log, 'read dist.one'))
          if label == "by a function-form enabled" then
            assert.are.equal(1, #vim.tbl_filter(function(l) return l == 'asked' end, installed.log))
          end
        end)
      end
    end)

    it("reads it when the last spec's enabled keeps the plugin", function()
      make_repo('aa')
      make_repo('dist', { ['lua/dist/one.lua'] = read_one })
      both_starts("{ 'u/dist', enabled = false }, { 'u/dist', enabled = true }, { import = 'dist.one' }",
        'plugins=aa:lazy,dist:eager')
    end)

    it("finds the directory a later fragment's name gives", function()
      make_repo('aa')
      make_repo('dist', { ['lua/dist/one.lua'] = read_one })
      local _, later = both_starts("{ 'u/dist' }, { import = 'dist.one' }, { 'u/dist', name = 'Renamed' }",
        'plugins=Renamed:eager,aa:lazy')
      assert.is_true(vim.list_contains(later.log, 'read dist.one'))
      local dirs = session(spec("{ 'u/dist', name = 'Renamed' }, { import = 'dist.one' }"),
        "table.insert(_G.LOG, 'renamed=' .. tostring(on_disk('Renamed'))); table.insert(_G.LOG, 'dist=' .. tostring(on_disk('dist')))")
      assert.is_true(vim.list_contains(dirs.log, 'renamed=true'))
      assert.is_true(vim.list_contains(dirs.log, 'dist=false'))
    end)

    it("doesn't apply to a spec with a source and an import, which looks only in its plugin", function()
      make_repo('aa')
      make_repo('own')
      make_repo('dist', { ['lua/dist/one.lua'] = read_one })
      local body = "{ 'u/own', import = 'dist.one' }, { 'u/dist' }"
      for _ = 1, 2 do
        local result = session(spec(body), report)
        assert_warned(result)
        assert.is_false(vim.list_contains(result.log, 'read dist.one'))
        assert.is_truthy(table.concat(result.notes, '\n'):find('/opt/own/lua/dist/one', 1, true))
      end
    end)

    describe("given several plugins that have the module", function()
      local function holders()
        make_repo('hold1', { ['lua/shared/mod.lua'] = { "table.insert(_G.LOG, 'read hold1')", "return {}" } })
        make_repo('shared_2', { ['lua/shared/mod.lua'] = { "table.insert(_G.LOG, 'read shared_2')", "return {}" } })
        make_repo('shared', { ['lua/shared/mod.lua'] = { "table.insert(_G.LOG, 'read shared')", "return {}" } })
      end

      it("reads the first listed of those named after it", function()
        holders()
        local first, later = both_starts("{ 'u/shared_2' }, { 'u/shared' }, { import = 'shared.mod' }",
          'plugins=shared:eager,shared_2:eager')
        for _, result in ipairs({ first, later }) do
          assert.is_true(vim.list_contains(result.log, 'read shared_2'))
          assert.is_false(vim.list_contains(result.log, 'read shared'))
        end
      end)

      it("reads the one named after the module, not the first listed", function()
        holders()
        local first, later = both_starts("{ 'u/hold1' }, { 'u/shared' }, { import = 'shared.mod' }",
          'plugins=hold1:eager,shared:eager')
        for _, result in ipairs({ first, later }) do
          assert.is_true(vim.list_contains(result.log, 'read shared'))
          assert.is_false(vim.list_contains(result.log, 'read hold1'))
        end
      end)
    end)

    describe("doesn't install other plugins ahead of the specs in a module named for its plugin", function()
      local on_disk_aa = "table.insert(_G.LOG, 'aa=' .. tostring(on_disk('aa')))"

      it("so a plugin that module disables isn't installed", function()
        make_repo('aa')
        make_repo('dist', { ['lua/dist/one.lua'] = { "return { { 'u/aa', enabled = false } }" } })
        local result = session(spec("{ 'u/aa' }, { 'u/dist' }, { import = 'dist.one' }"), on_disk_aa)
        assert.is_true(vim.list_contains(result.log, 'aa=false'), vim.inspect(result.log))
      end)

      it("so a version that module sets is the one installed", function()
        local aa = make_repo('aa')
        git(aa, 'tag', 'v1')
        git(aa, 'commit', '-q', '--allow-empty', '-m', 'two')
        make_repo('dist', { ['lua/dist/one.lua'] = { "return { { 'u/aa', version = 'v1' } }" } })
        local result = session(spec("{ 'u/aa' }, { 'u/dist' }, { import = 'dist.one' }"),
          "table.insert(_G.LOG, 'head=' .. in_git('aa', 'log', '-1', '--format=%s'))")
        assert.is_true(vim.list_contains(result.log, 'head=init'), vim.inspect(result.log))
      end)
    end)

    it("in a plugin not named for it, warns with the hint and doesn't read it", function()
      make_repo('aa')
      make_repo('other', { ['lua/dist/one.lua'] = read_one })
      for _ = 1, 2 do
        local result = session(spec("{ 'u/other' }, { import = 'dist.one' }"), report)
        assert_warned(result)
        assert.is_truthy(table.concat(result.notes, '\n'):find("{ 'user/dist', import = 'dist.one' }", 1, true))
        assert.is_false(vim.list_contains(result.log, 'read dist.one'))
        assert.are.equal('plugins=other:eager', plugins(result))
      end
    end)

    it("that no plugin has, warns with the hint on both starts", function()
      make_repo('aa')
      for _ = 1, 2 do
        local result = session(spec("{ 'u/aa' }, { import = 'zpack_no_such_module' }"), report)
        assert_warned(result)
        assert.is_truthy(table.concat(result.notes, '\n'):find("{ 'user/dist', import = 'zpack_no_such_module' }", 1, true))
        assert.are.equal('plugins=aa:eager', plugins(result))
      end
    end)

    describe("when the install is declined", function()
      local function answer_install(choice)
        return ("_G.PROMPTS = 0; vim.fn.confirm = function() _G.PROMPTS = _G.PROMPTS + 1; return %d end"):format(choice)
      end
      local prompted = report .. "; table.insert(_G.LOG, 'prompts=' .. _G.PROMPTS); table.insert(_G.LOG, 'dist=' .. tostring(on_disk('dist')))"
      local body = "{ spec = { { 'u/dist' }, { import = 'dist.one' } } }"

      it("of a plugin named for the module, warns and asks again next start", function()
        make_repo('aa')
        make_repo('dist', { ['lua/dist/one.lua'] = read_one })
        for _ = 1, 2 do
          local result = session(body, prompted, answer_install(2))
          assert_warned(result)
          assert.is_false(vim.list_contains(result.log, 'read dist.one'))
          assert.is_true(vim.list_contains(result.log, 'dist=false'), vim.inspect(result.log))
          assert.is_true(vim.list_contains(result.log, 'prompts=2'), vim.inspect(result.log))
        end
        local accepted = session(body, prompted, answer_install(1))
        assert_found(accepted)
        assert.is_true(vim.list_contains(accepted.log, 'read dist.one'))
      end)

      it("of a plugin with its own import beside it, as in LazyVim's starter, asks once before registering", function()
        make_repo('aa')
        make_repo('bb')
        make_repo('dist', { ['lua/dist/plugins.lua'] = { "return { { 'u/bb' } }" }, ['lua/dist/one.lua'] = read_one })
        local owned = "{ spec = { { 'u/dist', import = 'dist.plugins' }, { import = 'dist.one' } } }"
        local result = session(owned, prompted, answer_install(2))
        assert_warned(result)
        assert.is_true(vim.list_contains(result.log, 'dist=false'), vim.inspect(result.log))
        assert.is_true(vim.list_contains(result.log, 'prompts=2'), vim.inspect(result.log))
        local accepted = session(owned, prompted, answer_install(1))
        assert_found(accepted)
        assert.is_true(vim.list_contains(accepted.log, 'read dist.one'))
        assert.are.equal('plugins=aa:lazy,bb:eager,dist:eager', plugins(accepted))
      end)

      it("asks once when no plugin is named for the module, as for a gitignored local one", function()
        make_repo('aa')
        make_repo('dist')
        local result = session("{ spec = { { 'u/aa' }, { 'u/dist', cmd = 'D' }, { import = 'plugins.machine_local' } } }",
          prompted, answer_install(2))
        assert_warned(result)
        assert.is_true(vim.list_contains(result.log, 'dist=false'), vim.inspect(result.log))
        assert.is_true(vim.list_contains(result.log, 'prompts=1'), vim.inspect(result.log))
      end)
    end)

    describe("does no extra work", function()
      local count = table.concat({
        "local merge = require('zpack.merge')",
        "local resolve = merge.resolve_all",
        "_G.RESOLVES, _G.PASSES = 0, 0",
        "merge.resolve_all = function(...) _G.RESOLVES = _G.RESOLVES + 1; return resolve(...) end",
        "local import = require('zpack.import')",
        "local import_specs, depth = import.import_specs, 0",
        "import.import_specs = function(...)",
        "  if depth == 0 then _G.PASSES = _G.PASSES + 1 end",
        "  depth = depth + 1; local result = import_specs(...); depth = depth - 1; return result",
        "end",
      }, ' ')
      local counts = "table.insert(_G.LOG, 'resolves=' .. _G.RESOLVES .. ' passes=' .. _G.PASSES)"

      it("when each import resolves through the normal lookup", function()
        make_repo('aa')
        make_repo('d', { ['lua/d/x.lua'] = { "return { { 'u/aa' } }" } })
        vim.fn.mkdir(home .. '/config/nvim/lua/plugins', 'p')
        vim.fn.writefile({ "return { { 'u/d', lazy = true } }" }, home .. '/config/nvim/lua/plugins/one.lua')
        local body = spec("{ import = 'plugins' }, { 'u/d', import = 'd.x' }")
        session(body)
        local result = session(body, counts, count)
        assert.are.equal('resolves=1 passes=1', result.log[#result.log])
      end)

      it("for a later import from the plugin found, once installed", function()
        make_repo('aa')
        make_repo('bb')
        make_repo('dist', {
          ['lua/dist/one.lua'] = { "return { { 'u/aa' } }" },
          ['lua/dist/two.lua'] = { "return { { 'u/bb' } }" },
        })
        local body = spec("{ 'u/dist' }, { import = 'dist.one' }, { import = 'dist.two' }")
        session(body)
        local result = session(body, counts, count)
        assert.are.equal('resolves=2 passes=2', result.log[#result.log])
      end)
    end)
  end)

  describe("a top-level module an in-session update brings to a pending plugin", function()
    for label, earlier_require in pairs({
      ['the plugin was scanned for another module'] = 'unrelated',
      ['a require of it had already failed'] = 'brandnew',
    }) do
      it("loads when " .. label, function()
        local repo = make_repo('lz', { ['lua/lz.lua'] = { 'return {}' } })
        local spec = "{ spec = { { url = lz, name = 'lz', cmd = 'Lz' } }, defaults = { confirm = false } }"
        session(spec)
        vim.fn.writefile({ 'return {}' }, repo .. '/lua/brandnew.lua')
        git(repo, 'add', '.')
        git(repo, 'commit', '-qm', 'two')
        local result = session(spec, table.concat({
          ("table.insert(_G.LOG, 'before=' .. tostring((pcall(require, '%s'))))"):format(earlier_require),
          "vim.cmd('ZPack! update')",
          "vim.wait(1000)",
          "table.insert(_G.LOG, 'head=' .. in_git('lz', 'log', '-1', '--format=%s'))",
          "table.insert(_G.LOG, 'after=' .. tostring((pcall(require, 'brandnew'))))",
        }, '; '))
        for _, entry in ipairs({ 'before=false', 'head=two', 'after=true' }) do
          assert.is_true(vim.list_contains(result.log, entry), entry .. ' in ' .. vim.inspect(result.log))
        end
      end)
    end
  end)

  describe("the module setup() imports", function()
    local function warning(result)
      return table.concat(result.notes, '\n'):find('no specs found', 1, true)
    end

    local function make_empty_default()
      vim.fn.mkdir(home .. '/config/nvim/lua/plugins', 'p')
    end

    local function holding(file)
      return function()
        make_empty_default()
        vim.fn.writefile({}, home .. '/config/nvim/lua/plugins/' .. file)
      end
    end

    for name, make_default in pairs({
      missing = function() end,
      empty = make_empty_default,
      ['holding only a .gitkeep'] = holding('.gitkeep'),
      ['holding only a .DS_Store'] = holding('.DS_Store'),
    }) do
      for label, args in pairs({ ['no argument'] = '', ['only options'] = "{ defaults = { confirm = false } }" }) do
        it("given " .. label .. ", is nothing to warn about when " .. name, function()
          make_default()
          assert.is_falsy(warning(session(args)))
        end)
      end
    end

    for _, link in ipairs({ 'plugins', 'plugins.lua' }) do
      it("warns when lua/" .. link .. " is a dangling symlink", function()
        vim.fn.mkdir(home .. '/config/nvim/lua', 'p')
        assert.is_truthy(vim.uv.fs_symlink(home .. '/nowhere', home .. '/config/nvim/lua/' .. link))
        assert.is_truthy(warning(session('')))
      end)
    end

    it("warns when lua/plugins holds only a subdirectory with no init", function()
      vim.fn.mkdir(home .. '/config/nvim/lua/plugins/lang', 'p')
      vim.fn.writefile({ 'return {}' }, home .. '/config/nvim/lua/plugins/lang/python.lua')
      assert.is_truthy(warning(session('')))
    end)

    for label, args in pairs({ ['a string'] = "'plugins'", ['an import'] = "{ spec = { import = 'plugins' } }" }) do
      it("named by " .. label .. " warns when missing", function()
        assert.is_truthy(warning(session(args)))
      end)

      it("named by " .. label .. " warns when empty", function()
        make_empty_default()
        assert.is_truthy(warning(session(args)))
      end)
    end
  end)

  for label, args in pairs({
    ['a number'] = '42',
    ['a spec that is a number'] = '{ spec = 42 }',
    ['a spec that is an empty string'] = "{ spec = '' }",
  }) do
    it("setup() given " .. label .. " reports it, and :ZPack clean lists what it may have declared", function()
      make_repo('aa')
      session("{ spec = { { url = aa, name = 'aa' } }, defaults = { confirm = false } }")
      local result = session(args, "vim.cmd('ZPack clean'); vim.wait(500); table.insert(_G.LOG, 'aa=' .. tostring(on_disk('aa')))", answering(2))
      assert.is_truthy(table.concat(result.notes, '\n'):find('zpack.setup', 1, true), vim.inspect(result.notes))
      assert.are.same({ 'listed: These plugins will be deleted:\n\naa', 'asked: Delete this plugin?', 'aa=true' }, result.log)
    end)
  end

  describe("a spec that can't be read this session", function()
    local function head(repo)
      return ("table.insert(_G.LOG, '%s=' .. in_git('%s', 'log', '-1', '--format=%%s'))"):format(repo, repo)
    end
    local local_import = "{ spec = { { url = kept, name = 'kept' }, { import = 'plugins.local' } }, defaults = { confirm = false } }"

    ---Install with `lost` as this says, commit to both, then start with its spec gone.
    local function next_session(lost_fields, at_enter)
      local kept, lost = make_repo('kept'), make_repo('lost')
      git(lost, 'tag', 'v1')
      session(("{ spec = { { url = kept, name = 'kept' }, { url = lost, name = 'lost', %s } }, defaults = { confirm = false } }"):format(lost_fields))
      git(kept, 'commit', '-q', '--allow-empty', '-m', 'two')
      git(lost, 'commit', '-q', '--allow-empty', '-m', 'two')
      return session(local_import, at_enter .. "; vim.wait(1000); " .. head('kept') .. "; " .. head('lost')
        .. "; table.insert(_G.LOG, tostring(on_disk('lost')))")
    end

    for _, cmd in ipairs({ 'ZPack! update', 'ZPack sync' }) do
      it(":" .. cmd .. " moves a plugin whose pin was in it, and leaves it on disk", function()
        local result = next_session('pin = true', ("vim.cmd('%s')"):format(cmd))
        assert.are.same({ 'kept=two', 'lost=two', 'true' }, vim.list_slice(result.log, #result.log - 2))
        assert.is_falsy(table.concat(result.notes, '\n'):find('failed to load', 1, true))
      end)

      for _, fields in ipairs({ "version = 'v1'", "tag = 'v1'" }) do
        it((":%s holds a %s that was in it"):format(cmd, fields), function()
          local result = next_session(fields, ("vim.cmd('%s')"):format(cmd))
          assert.are.same({ 'kept=two', 'lost=init', 'true' }, vim.list_slice(result.log, #result.log - 2))
        end)
      end
    end

    it(":ZPack! restore doesn't undo that move, since the update rewrote the lockfile", function()
      local result = next_session('pin = true', "vim.cmd('ZPack sync'); vim.cmd('ZPack! restore')")
      assert.are.same({ 'kept=two', 'lost=two', 'true' }, vim.list_slice(result.log, #result.log - 2))
    end)
  end)

  it(":ZPack! delete deletes every plugin with zpack.nvim outside vim.pack", function()
    make_repo('aa')
    local result = session("{ spec = { { url = aa, name = 'aa' } }, defaults = { confirm = false } }",
      "vim.cmd('ZPack! delete'); table.insert(_G.LOG, tostring(on_disk('aa')))")
    assert.are.equal('false', result.log[#result.log])
    assert.is_truthy(table.concat(result.notes, '\n'):find('Deleting all 1 installed', 1, true))
  end)

  describe("a bulk update with a pin", function()
    local function heads()
      return "table.insert(_G.LOG, in_git('aa', 'log', '-1', '--format=%s')); table.insert(_G.LOG, in_git('bb', 'log', '-1', '--format=%s'))"
    end

    local function two_sessions(specs, before_setup, repos, report)
      local spec = ("{ spec = { %s }, defaults = { confirm = false } }"):format(specs)
      session(spec, nil, before_setup)
      for _, repo in ipairs(repos) do
        git(repo, 'commit', '-q', '--allow-empty', '-m', 'two')
      end
      return session(spec, "vim.cmd('ZPack! update'); vim.wait(1000); " .. report, before_setup)
    end

    it("updates the rest with zpack.nvim outside vim.pack", function()
      local aa, bb = make_repo('aa'), make_repo('bb')
      local result = two_sessions("{ url = aa, name = 'aa', pin = true }, { url = bb, name = 'bb' }", nil, { aa, bb }, heads())
      assert.are.same({ 'init', 'two' }, vim.list_slice(result.log, #result.log - 1))
      assert.is_nil(table.concat(result.notes, '\n'):find('Update failed', 1, true))
    end)

    local managed = "vim.pack.add({ { src = zpk, name = 'zpack.nvim' } }, { confirm = false })"
    local zpack_head = "table.insert(_G.LOG, in_git('zpack.nvim', 'log', '-1', '--format=%s'))"

    it("updates a zpack.nvim vim.pack manages", function()
      local aa, zpk = make_repo('aa'), make_repo('zpk')
      local result = two_sessions("{ url = aa, name = 'aa', pin = true }", managed, { aa, zpk }, zpack_head)
      assert.are.equal('two', result.log[#result.log])
    end)

    it("leaves a zpack.nvim that's pinned itself", function()
      local zpk = make_repo('zpk')
      local result = two_sessions("{ url = zpk, name = 'zpack.nvim', pin = true }", managed, { zpk }, zpack_head)
      assert.are.equal('init', result.log[#result.log])
    end)
  end)

  it("one bad version doesn't stop the other plugins' config or :ZPack", function()
    make_repo('aa')
    make_repo('bb')
    make_repo('cc')
    local result = session([[{ spec = {
      { url = aa, name = 'aa', tag = 3, config = function() table.insert(_G.LOG, 'aa.config') end },
      { url = bb, name = 'bb', version = true, config = function() table.insert(_G.LOG, 'bb.config') end },
      { url = cc, name = 'cc', config = function() table.insert(_G.LOG, 'cc.config') end },
    }, defaults = { confirm = false } }]], "table.insert(_G.LOG, 'cmd=' .. vim.fn.exists(':ZPack'))")
    for _, entry in ipairs({ 'aa.config', 'bb.config', 'cc.config', 'cmd=2' }) do
      assert.is_true(vim.list_contains(result.log, entry), entry)
    end
  end)

  it("installs an untagged plugin from its default branch after another plugin's clone failed", function()
    make_repo('untagged')
    make_repo('aa')
    local result = session(
      "{ spec = { { url = 'file:///no/such-repo', name = 'nosuch' }, { url = untagged, name = 'untagged', version = '*' }, { url = aa, name = 'aa' } }, defaults = { confirm = false } }",
      "table.insert(_G.LOG, 'untagged=' .. tostring(on_disk('untagged')))"
    )
    assert.are.equal('untagged=true', result.log[#result.log])
    local notes = table.concat(result.notes, '\n')
    assert.is_truthy(notes:find('nosuch', 1, true))
    assert.is_falsy(notes:find('No versions fit', 1, true))
  end)

  describe("installing with confirm on", function()
    local function answer(choice)
      return ("vim.fn.confirm = function() table.insert(_G.LOG, 'asked'); return %d end"):format(choice)
    end

    local function tagged_repo()
      local repo = make_repo('tagged')
      git(repo, 'tag', 'v1.0.0')
    end

    it("doesn't install what a whole-call error stopped vim.pack asking about", function()
      tagged_repo()
      local result = session(
        "{ spec = { { src = '', name = 'bad' }, { url = tagged, name = 'tagged', version = '*' } } }",
        "table.insert(_G.LOG, 'tagged=' .. tostring(on_disk('tagged')))",
        answer(1)
      )
      assert.are.same({ 'tagged=false' }, result.log)
    end)

    it("asks about a soft version beside a bad version, and a no means no", function()
      make_repo('aa')
      tagged_repo()
      local result = session(
        "{ spec = { { url = aa, name = 'aa', version = 2 }, { url = tagged, name = 'tagged', version = '*' } } }",
        "table.insert(_G.LOG, 'aa=' .. tostring(on_disk('aa'))); table.insert(_G.LOG, 'tagged=' .. tostring(on_disk('tagged')))",
        answer(2)
      )
      assert.are.same({ 'asked', 'aa=false', 'tagged=false' }, result.log)
    end)

    it("asks once to install an untagged plugin from its default branch", function()
      make_repo('untagged')
      local result = session(
        "{ spec = { { url = untagged, name = 'untagged', version = '*' } } }",
        "table.insert(_G.LOG, 'untagged=' .. tostring(on_disk('untagged')))",
        answer(1)
      )
      assert.are.same('asked', result.log[1])
      assert.are.equal(1, #vim.tbl_filter(function(entry) return entry == 'asked' end, result.log))
      assert.is_true(vim.list_contains(result.log, 'untagged=true'))
      assert.are.same({}, result.notes)
    end)
  end)

  describe("a semver string on an installed plugin", function()
    local defaults = "defaults = { confirm = false }"

    local function spec_with(field)
      return ("{ spec = { { url = vv, name = 'vv', %s } }, %s }"):format(field, defaults)
    end

    local report = table.concat({
      "table.insert(_G.LOG, in_git('vv', 'log', '-1', '--format=%s'))",
      "local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.fn.stdpath('config') .. '/nvim-pack-lock.json'), ''))",
      "table.insert(_G.LOG, tostring(lock.plugins.vv.version))",
    }, '; ')

    local function commit(repo, subject)
      git(repo, 'commit', '-q', '--allow-empty', '-m', subject)
    end

    it("moves to the tip, then says to restart and update again to reach a tag only a fetch finds", function()
      local repo = make_repo('vv')
      git(repo, 'tag', 'v1.0.0')
      session(spec_with("sem_version = '^1'"))
      commit(repo, 'two')
      git(repo, 'tag', 'v2.0.0')
      commit(repo, 'unreleased')

      local range = "sem_version = '^2'"
      local result = session(spec_with(range), "vim.cmd('ZPack! update vv'); " .. report)
      assert.are.equal('unreleased', result.log[#result.log - 1])
      assert.is_truthy(table.concat(result.notes, '\n'):find('Restart and update again', 1, true))

      local log = session(spec_with(range), "vim.cmd('ZPack! update vv'); " .. report).log
      assert.are.equal('two', log[#log - 1])
      assert.is_truthy(log[#log]:find('2.0.0', 1, true))

      result = session(spec_with(range), "vim.cmd('ZPack! update vv'); " .. report)
      assert.are.equal('two', result.log[#result.log - 1])
      assert.is_falsy(table.concat(result.notes, '\n'):find('Restart and update again', 1, true))
    end)

    for name, update in pairs({
      ['named update'] = "vim.cmd('ZPack! update vv')",
      ['bulk update'] = "vim.cmd('ZPack! update')",
      ['update from the confirm buffer'] = "vim.cmd('ZPack update vv'); vim.cmd('write')",
      ['sync'] = "vim.cmd('ZPack sync')",
    }) do
      it("with no tag follows the default branch in a " .. name, function()
        local repo = make_repo('vv')
        local star = "version = '*'"
        session(spec_with(star))
        commit(repo, 'two')
        local result = session(spec_with(star), update .. "; vim.wait(500); " .. report)
        assert.are.equal('two', result.log[#result.log - 1])
      end)
    end

    for name, update in pairs({
      ['a sync'] = "vim.cmd('ZPack sync')",
      ['the confirm buffer'] = "vim.cmd('ZPack update vv'); vim.cmd('write')",
    }) do
      it("with no tag says to restart when upstream adds one, from " .. name, function()
        local repo = make_repo('vv')
        local star = "version = '*'"
        session(spec_with(star))
        commit(repo, 'released')
        git(repo, 'tag', 'v1.0.0')
        commit(repo, 'unreleased')
        local result = session(spec_with(star), update .. "; vim.wait(500); " .. report)
        assert.are.equal('unreleased', result.log[#result.log - 1])
        assert.is_truthy(table.concat(result.notes, '\n'):find('Restart and update again', 1, true))
        local log = session(spec_with(star), "vim.cmd('ZPack! update vv'); " .. report).log
        assert.are.equal('released', log[#log - 1])
      end)
    end

    it("a failed fetch leaves it where it is, with vim.pack's error", function()
      local repo = make_repo('vv')
      local star = "version = '*'"
      session(spec_with(star))
      commit(repo, 'released')
      git(repo, 'tag', 'v1.0.0')
      commit(repo, 'unreleased')
      local fail_fetches = table.concat({
        "local shim = vim.fn.stdpath('data') .. '/shim'",
        "vim.fn.mkdir(shim, 'p')",
        "vim.fn.writefile({ '#!/bin/sh', 'case \"$*\" in *fetch*) echo transient >&2; exit 128;; esac', 'exec ' .. vim.fn.exepath('git') .. ' \"$@\"' }, shim .. '/git')",
        "vim.fn.setfperm(shim .. '/git', 'rwxr-xr-x')",
        "vim.env.PATH = shim .. ':' .. vim.env.PATH",
      }, '; ')
      local result = session(spec_with(star),
        fail_fetches .. "; vim.cmd('ZPack! update'); vim.wait(500); " .. report)
      assert.are.equal('init', result.log[#result.log - 1])
      assert.is_falsy(table.concat(result.notes, '\n'):find('Restart and update again', 1, true))
    end)

    describe("interrupted during a fetch", function()
      local function interrupted_by(cmd)
        make_repo('vv')
        make_repo('gone')
        local other = make_repo('other')
        local specs = "{ url = vv, name = 'vv', version = '*' }, { url = other, name = 'other' }"
        session(("{ spec = { %s, { url = gone, name = 'gone' } }, %s }"):format(specs, defaults))
        git(other, 'commit', '-q', '--allow-empty', '-m', 'two')
        return session(("{ spec = { %s }, %s }"):format(specs, defaults), table.concat({
          "local shim = vim.fn.stdpath('data') .. '/shim'",
          "vim.fn.mkdir(shim, 'p')",
          "vim.fn.writefile({ '#!/bin/sh', 'case \"$*\" in *fetch*) exec sleep 20;; esac', 'exec ' .. vim.fn.exepath('git') .. ' \"$@\"' }, shim .. '/git')",
          "vim.fn.setfperm(shim .. '/git', 'rwxr-xr-x')",
          "vim.env.PATH = shim .. ':' .. vim.env.PATH",
          "local timer = vim.uv.new_timer()",
          "timer:start(300, 300, function() vim.api.nvim_input('<C-c>') end)",
          "local start = vim.uv.hrtime()",
          ("vim.cmd('%s')"):format(cmd),
          "timer:stop()",
          "table.insert(_G.LOG, tostring((vim.uv.hrtime() - start) / 1e9 < 5))",
          "vim.env.PATH = vim.env.PATH:gsub('^[^:]*:', '')",
          "vim.wait(500)",
          "table.insert(_G.LOG, in_git('other', 'log', '-1', '--format=%s'))",
          "table.insert(_G.LOG, tostring(on_disk('gone')))",
        }, '; '))
      end

      for cmd, prefix in pairs({ ['ZPack! update'] = 'Update failed', ['ZPack sync'] = 'Sync update failed' }) do
        it(":" .. cmd .. " returns promptly, reports it, and doesn't clean", function()
          local result = interrupted_by(cmd)
          assert.are.same({ 'true', 'init', 'true' }, vim.list_slice(result.log, #result.log - 2))
          assert.is_truthy(table.concat(result.notes, '\n'):find(prefix, 1, true))
        end)
      end
    end)

    it("no fetch can fit still follows the default branch", function()
      local repo = make_repo('vv')
      git(repo, 'tag', 'v1.0.0')
      session(spec_with("sem_version = '^1'"))
      commit(repo, 'two')
      local log = session(spec_with("sem_version = '^2'"), "vim.cmd('ZPack! update vv'); " .. report).log
      assert.are.equal('two', log[#log - 1])
    end)

    describe("restored from a lockfile on a fresh machine", function()
      local check = "table.insert(_G.LOG, in_git('vv', 'log', '-1', '--format=%s')); table.insert(_G.LOG, tostring(vim.uv.fs_stat(vim.fn.stdpath('data') .. '/site/pack/core/opt/vv/plugin/vv.lua') ~= nil))"

      local function fresh_machine()
        vim.fn.delete(home .. '/data', 'rf')
      end

      -- vim.pack's first call restores the lockfile: zpack's own, or one before setup().
      local routes = {
        ['with zpack on rtp'] = function() return nil end,
        ['after the bootstrap vim.pack.add'] = function()
          return ("vim.pack.add({ %q }, { confirm = false })"):format('file://' .. make_repo('zpack.nvim'))
        end,
      }
      for route, first_call in pairs(routes) do
        describe(route, function()
          for name, field in pairs({ version = "version = '*'", sem_version = "sem_version = '*'" }) do
            it("installs the locked rev with its files when no tag fits, from " .. name, function()
              local before = first_call()
              local repo = make_repo('vv')
              session(spec_with(field), nil, before)
              session(spec_with(field), nil, before)
              commit(repo, 'two')
              fresh_machine()
              local result = session(spec_with(field), check .. "; " .. report, before)
              assert.is_true(vim.list_contains(result.log, 'vv.plugin'))
              assert.are.same({ 'init', 'true', 'init' }, vim.list_slice(result.log, #result.log - 3, #result.log - 1))

              local log = session(spec_with(field), "vim.cmd('ZPack! update vv'); " .. report, before).log
              assert.are.equal('two', log[#log - 1])
            end)
          end

          if vim.fn.exists('+packlockfile') == 1 then
            it("reads the lockfile 'packlockfile' points at", function()
              local boot = first_call()
              local before = "vim.o.packlockfile = vim.fn.stdpath('config') .. '/custom-lock.json'; " .. (boot or '')
              local repo = make_repo('vv')
              local star = "version = '*'"
              session(spec_with(star), nil, before)
              session(spec_with(star), nil, before)
              assert.are.equal(0, vim.fn.filereadable(home .. '/config/nvim/nvim-pack-lock.json'))
              commit(repo, 'two')
              fresh_machine()
              local result = session(spec_with(star), check, before)
              assert.is_true(vim.list_contains(result.log, 'vv.plugin'))
              assert.are.same({ 'init', 'true' }, vim.list_slice(result.log, #result.log - 1))
            end)
          end

          it("installs the locked rev of a plugin a tag fits, and keeps its range", function()
            local before = first_call()
            local repo = make_repo('vv')
            git(repo, 'tag', 'v1.0.0')
            session(spec_with("version = '*'"), nil, before)
            commit(repo, 'two')
            git(repo, 'tag', 'v1.1.0')
            fresh_machine()
            local result = session(spec_with("version = '*'"), check, before)
            assert.is_true(vim.list_contains(result.log, 'vv.plugin'))
            assert.are.same({ 'init', 'true' }, vim.list_slice(result.log, #result.log - 1))

            local log = session(spec_with("version = '*'"), "vim.cmd('ZPack! update vv'); " .. report, before).log
            assert.are.equal('two', log[#log - 1])
            assert.is_truthy(log[#log]:find('0.0.0', 1, true))
          end)

          for name, tags in pairs({
            ['a plugin a tag fits'] = true,
            ['a plugin no tag fits'] = false,
          }) do
            it(":ZPack update moves " .. name .. " in the session that restored it", function()
              local before = first_call()
              local repo = make_repo('vv')
              if tags then git(repo, 'tag', 'v1.0.0') end
              local star = "version = '*'"
              session(spec_with(star), nil, before)
              commit(repo, 'two')
              if tags then git(repo, 'tag', 'v1.1.0') end

              for _, update in ipairs({ "vim.cmd('ZPack! update')", "vim.cmd('ZPack! update vv')", "vim.cmd('ZPack sync')" }) do
                fresh_machine()
                local result = session(spec_with(star), update .. "; vim.wait(500); " .. report, before)
                assert.are.equal('two', result.log[#result.log - 1], update)
                assert.is_falsy(table.concat(result.notes, '\n'):find('estart', 1, true), update)
              end
            end)
          end

          for name, tags in pairs({
            ['an import owner a tag fits'] = true,
            ['an import owner no tag fits'] = false,
          }) do
            it(":ZPack update moves " .. name .. " in the session that restored it", function()
              local before = first_call()
              local repo = make_repo('dist', { ['lua/dist/plugins/core.lua'] = { 'return {}' } })
              if tags then git(repo, 'tag', 'v1.0.0') end
              local spec = ("{ spec = { { url = dist, name = 'dist', version = '*', import = 'dist.plugins' } }, %s }"):format(defaults)
              session(spec, nil, before)
              commit(repo, 'two')
              if tags then git(repo, 'tag', 'v1.1.0') end
              fresh_machine()

              local result = session(spec, "vim.cmd('ZPack! update dist'); vim.wait(500); table.insert(_G.LOG, in_git('dist', 'log', '-1', '--format=%s'))", before)
              assert.are.equal('two', result.log[#result.log])
              assert.is_falsy(table.concat(result.notes, '\n'):find('estart', 1, true))
            end)
          end
        end)
      end

      describe("with confirm on", function()
        local function answer(choice)
          return ("vim.fn.confirm = function() table.insert(_G.LOG, 'asked'); return %d end"):format(choice)
        end
        local on_disk_report = "table.insert(_G.LOG, 'vv=' .. tostring(on_disk('vv')))"

        local function restored_with(choice)
          local repo = make_repo('vv')
          session(spec_with("version = '*'"))
          commit(repo, 'two')
          fresh_machine()
          return session("{ spec = { { url = vv, name = 'vv', version = '*' } } }", on_disk_report .. "; " .. check, answer(choice))
        end

        it("asks once and installs the locked rev on a yes", function()
          local result = restored_with(1)
          assert.are.equal(1, #vim.tbl_filter(function(entry) return entry == 'asked' end, result.log))
          assert.is_true(vim.list_contains(result.log, 'vv=true'))
          assert.is_true(vim.list_contains(result.log, 'init'))
          assert.are.same({}, result.notes)
        end)

        it("on a no asks again for the plugin in the spec, and installs nothing", function()
          local result = restored_with(2)
          assert.are.equal(2, #vim.tbl_filter(function(entry) return entry == 'asked' end, result.log))
          assert.is_true(vim.list_contains(result.log, 'vv=false'))
        end)
      end)

      it("asks for the default branch when the lockfile has no such plugin", function()
        make_repo('vv')
        make_repo('other')
        session(("{ spec = { { url = other, name = 'other' } }, %s }"):format(defaults))
        local result = session(spec_with("version = '*'"), check)
        assert.are.same('true', result.log[#result.log])
      end)
    end)

    it("doesn't apply to a vim.version.range object", function()
      local repo = make_repo('vv')
      session(spec_with("version = false"))
      commit(repo, 'two')
      local log = session(spec_with("version = vim.version.range('*')"),
        "vim.cmd('ZPack! update vv'); " .. report).log
      assert.are.equal('init', log[#log - 1])
    end)
  end)

  describe("two lazy plugins sharing a module namespace", function()
    local function loads(result, name)
      return vim.list_contains(result.log, name .. '.plugin')
    end
    local function setup_args(first, second)
      return ("{ spec = { { url = %s, name = '%s', lazy = true }, { url = %s, name = '%s', lazy = true } }, defaults = { confirm = false } }")
        :format(first, first, second, second)
    end
    local function report(name)
      return ("local ok, mod = pcall(require, %q); table.insert(_G.LOG, tostring(ok) .. '=' .. tostring(ok and mod.from)); "):format(name)
    end

    before_each(function()
      make_repo('aa', { ['lua/shared/init.lua'] = { "return { from = 'aa' }" }, ['lua/shared/ina.lua'] = { "return { from = 'aa' }" } })
      make_repo('bb', { ['lua/shared/inb.lua'] = { "return { from = 'bb' }" }, ['lua/only_bb.lua'] = { "return { from = 'bb' }" } })
    end)

    for name, order in pairs({ ['listed first'] = { 'aa', 'bb' }, ['listed second'] = { 'bb', 'aa' } }) do
      it("loads the one holding the module when it's " .. name, function()
        local result = session(setup_args(order[1], order[2]), report('shared.inb'))
        assert.is_true(vim.list_contains(result.log, 'true=bb'))
        assert.is_true(loads(result, 'bb'))
        assert.is_false(loads(result, 'aa'))
      end)

      it("loads each for its own module when it's " .. name, function()
        local result = session(setup_args(order[1], order[2]), report('shared') .. report('shared.inb') .. report('shared.ina'))
        assert.are.same({ 'true=aa', 'true=bb', 'true=aa' }, vim.tbl_filter(function(entry)
          return entry:find('=', 1, true) ~= nil
        end, result.log))
      end)
    end

    it("loads the one holding a compiled module", function()
      make_repo('native', { ['lua/shared/compiled.so'] = { "not a real library" } })
      local result = session(setup_args('native', 'bb'), report('shared.compiled'))
      assert.is_true(loads(result, 'native'))
      assert.is_false(loads(result, 'bb'))
    end)

    describe("when both hold the file", function()
      local names = { mininvim = 'mini.nvim', miniai = 'mini.ai' }
      local function both_args(order)
        return ("{ spec = { { url = %s, name = '%s', lazy = true }, { url = %s, name = '%s', lazy = true } }, defaults = { confirm = false } }")
          :format(order[1], names[order[1]], order[2], names[order[2]])
      end

      before_each(function()
        for repo, plugin in pairs(names) do
          make_repo(repo, {
            ['lua/mini/ai.lua'] = { ("return { from = '%s' }"):format(plugin) },
            ['lua/other/x.lua'] = { ("return { from = '%s' }"):format(plugin) },
          })
        end
      end)

      for name, order in pairs({ ['listed first'] = { 'mininvim', 'miniai' }, ['listed second'] = { 'miniai', 'mininvim' } }) do
        it("loads the one named like the top-level module when it's " .. name, function()
          local result = session(both_args(order), report('mini.ai'))
          assert.is_true(vim.list_contains(result.log, 'true=mini.nvim'), vim.inspect(result.log))
          assert.is_false(loads(result, 'miniai'))
        end)

        it("loads the first listed when neither is named like it, with " .. names[order[1]] .. ' first', function()
          local result = session(both_args(order), report('other.x'))
          assert.is_true(vim.list_contains(result.log, 'true=' .. names[order[1]]), vim.inspect(result.log))
          assert.is_false(loads(result, order[2]))
        end)
      end
    end)

    it("loads neither for a module neither holds, and a later require still works", function()
      local result = session(setup_args('aa', 'bb'), report('shared.nope') .. report('shared.nope') .. report('shared.inb'))
      assert.is_true(vim.list_contains(result.log, 'false=false'))
      assert.is_true(vim.list_contains(result.log, 'true=bb'))
      assert.is_false(loads(result, 'aa'))
    end)

    it("loads a plugin with no lua/shared for nothing but its own module", function()
      make_repo('cc', { ['lua/other.lua'] = { "return { from = 'cc' }" } })
      local result = session(
        "{ spec = { { url = cc, name = 'cc', lazy = true }, { url = aa, name = 'aa', lazy = true }, { url = bb, name = 'bb', lazy = true } }, defaults = { confirm = false } }",
        report('shared.inb')
      )
      assert.is_true(vim.list_contains(result.log, 'true=bb'))
      assert.is_false(loads(result, 'cc'))
    end)

    it("loads neither for such a module once another trigger has loaded the other claimant", function()
      local result = session(setup_args('aa', 'bb'), report('shared.nope') .. "vim.cmd('ZPack load bb'); "
        .. report('shared.nope2') .. "table.insert(_G.LOG, 'aa=' .. require('zpack.api').get_plugin('aa').status); "
        .. report('shared.ina'))
      assert.are.same({ 'false=false', 'false=false', 'aa=pending', 'true=aa' }, vim.tbl_filter(function(entry)
        return entry:find('=', 1, true) ~= nil
      end, result.log))
    end)
  end)

  describe("a module no lazy plugin holds, required at startup", function()
    local probe = "config = function() local ok, err = pcall(require, %q); table.insert(_G.LOG, 'probe=' .. tostring(ok)); table.insert(_G.LOG, tostring(err)) end"
    local status = "table.insert(_G.LOG, 'status=' .. require('zpack.api').get_plugin(%q).status); "

    local function setup_args(lazy_spec, module)
      return ("{ spec = { %s, { url = ee, name = 'ee', %s } }, defaults = { confirm = false } }"):format(lazy_spec, probe:format(module))
    end

    local function assert_not_found(result, module)
      assert.is_true(vim.list_contains(result.log, 'probe=false'), vim.inspect(result.log))
      local err = result.log[vim.fn.index(result.log, 'probe=false') + 2]
      assert.are.equal(1, (err:find(("module '%s' not found:"):format(module), 1, true)), err)
    end

    before_each(function()
      make_repo('ee')
      make_repo('pairs', { ['lua/mini/pairs.lua'] = { "return { setup = function() table.insert(_G.LOG, 'pairs.setup') end }" } })
      make_repo('ts', {
        ['lua/nvim-treesitter/init.lua'] = { 'return {}' },
        ['lua/nvim-treesitter/config.lua'] = { 'return {}' },
      })
    end)

    it("leaves a plugin sharing its namespace lazy, as mini.pairs beside a require of mini.icons", function()
      local result = session(
        setup_args("{ url = pairs, name = 'mini.pairs', event = 'InsertEnter', opts = {} }", 'mini.icons'),
        status:format('mini.pairs') .. "vim.api.nvim_exec_autocmds('InsertEnter', {}); " .. status:format('mini.pairs')
      )
      assert_not_found(result, 'mini.icons')
      assert.are.same({ 'status=pending', 'pairs.plugin', 'pairs.setup', 'status=loaded' },
        vim.list_slice(result.log, #result.log - 3))
    end)

    it("leaves a plugin lazy whose old submodule is gone, as nvim-treesitter's main branch without configs", function()
      local result = session(
        setup_args("{ url = ts, name = 'nvim-treesitter', event = 'BufReadPost' }", 'nvim-treesitter.configs'),
        status:format('nvim-treesitter')
      )
      assert_not_found(result, 'nvim-treesitter.configs')
      assert.is_false(vim.list_contains(result.log, 'ts.plugin'))
      assert.are.equal('status=pending', result.log[#result.log])
    end)

    for label, module in pairs({ ['its file'] = 'mini.pairs', ['a directory with init.lua'] = 'nvim-treesitter' }) do
      it("still loads the plugin holding " .. label, function()
        local result = session(("{ spec = { %s, %s, { url = ee, name = 'ee', %s } }, defaults = { confirm = false } }"):format(
          "{ url = pairs, name = 'mini.pairs', event = 'InsertEnter', opts = {} }",
          "{ url = ts, name = 'nvim-treesitter', event = 'BufReadPost' }",
          probe:format(module)
        ))
        assert.is_true(vim.list_contains(result.log, 'probe=true'), vim.inspect(result.log))
        assert.are.equal(module == 'mini.pairs', vim.list_contains(result.log, 'pairs.setup'))
        assert.are.equal(module == 'mini.pairs', vim.list_contains(result.log, 'pairs.plugin'))
        assert.are.equal(module ~= 'mini.pairs', vim.list_contains(result.log, 'ts.plugin'))
      end)
    end

    it("still loads the plugin holding a submodule", function()
      local result = session(setup_args("{ url = ts, name = 'nvim-treesitter', event = 'BufReadPost' }", 'nvim-treesitter.config'))
      assert.is_true(vim.list_contains(result.log, 'probe=true'), vim.inspect(result.log))
      assert.is_true(vim.list_contains(result.log, 'ts.plugin'))
    end)
  end)

  describe("a lazy plugin's module on its first require", function()
    local function setup_args(specs)
      return ("{ spec = { %s }, defaults = { confirm = false } }"):format(specs)
    end
    local function report(name)
      return ("local ok, mod = pcall(require, %q); table.insert(_G.LOG, ok and mod.from or mod)"):format(name)
    end

    for _, slot in ipairs({ 1, 2 }) do
      it("loads though a searcher went in at slot " .. slot .. " after setup()", function()
        make_repo('aa', { ['lua/mine.lua'] = { "return { from = 'aa' }" } })
        local result = session(setup_args("{ url = aa, name = 'aa', lazy = true }"),
          ("table.insert(package.loaders, %d, function() end); %s"):format(slot, report('mine')))
        assert.are.equal('aa', result.log[#result.log])
      end)
    end

    for label, name in pairs({ ["a slash-form name, as require('lspconfig/util')"] = 'mine/sub', ['a leading dot'] = '.mine.sub' }) do
      it("loads for " .. label, function()
        make_repo('aa', { ['lua/mine/sub.lua'] = { "return { from = 'aa' }" } })
        local result = session(setup_args("{ url = aa, name = 'aa', lazy = true }"), report(name))
        assert.are.equal('aa', result.log[#result.log])
      end)
    end

    for _, name in ipairs({ '', '/' }) do
      it(("reports %q as not found"):format(name), function()
        make_repo('aa', { ['lua/mine.lua'] = { "return { from = 'aa' }" } })
        local result = session(setup_args("{ url = aa, name = 'aa', lazy = true }"), report(name))
        assert.are.equal(1, (result.log[#result.log]:find(("module '%s' not found:"):format(name), 1, true)), result.log[#result.log])
      end)
    end

    it("comes from the plugin it loaded, ahead of a dependency holding the same one", function()
      make_repo('parent', { ['lua/same.lua'] = { "return { from = 'parent' }" } })
      make_repo('dep', { ['lua/same.lua'] = { "return { from = 'dep' }" } })
      local result = session(
        setup_args("{ url = parent, name = 'parent', lazy = true, dependencies = { { url = dep, name = 'dep' } } }"),
        report('same'))
      assert.are.equal('parent', result.log[#result.log])
    end)

    it("reports a syntax error in it", function()
      make_repo('aa', { ['lua/mine.lua'] = { "return {" } })
      local result = session(setup_args("{ url = aa, name = 'aa', lazy = true }"), report('mine'))
      assert.is_truthy(result.log[#result.log]:find('aa/lua/mine.lua', 1, true), result.log[#result.log])
    end)

    for _, vim_loader in ipairs({ true, false }) do
      it("opens a compiled one with vim_loader = " .. tostring(vim_loader), function()
        make_repo('aa', { ['lua/nat/compiled.so'] = { "not a real library" } })
        local result = session(
          ("{ spec = { { url = aa, name = 'aa', lazy = true } }, performance = { vim_loader = %s }, defaults = { confirm = false } }"):format(vim_loader),
          report('nat.compiled'))
        assert.is_truthy(result.log[#result.log]:find('aa/lua/nat/compiled.so', 1, true), result.log[#result.log])
      end)
    end
  end)

  describe("a function-form trigger that requires its own plugin's module", function()
    local defaults = "defaults = { confirm = false }"
    local function plugin_with(trigger, opts)
      make_repo('aa', {
        ['lua/aa.lua'] = { "table.insert(_G.LOG, 'aa.require')", 'return {}' },
        ['plugin/cmd.lua'] = { "vim.cmd('command CmdA lua table.insert(_G.LOG, [[CmdA ran]])')" },
      })
      return ("{ spec = { { url = aa, name = 'aa', %s %s, config = function() table.insert(_G.LOG, 'aa.config') end } }, %s }")
        :format(opts or '', trigger, defaults)
    end
    local function keys_fn() return "keys = function() require('aa'); return { { 'zx', function() table.insert(_G.LOG, 'zx ran') end } } end" end
    local function count(log, wanted)
      return #vim.tbl_filter(function(entry) return entry == wanted end, log)
    end
    local function no_errors(result)
      assert.are.same({}, vim.tbl_filter(function(note) return note:find('Failed', 1, true) ~= nil end, result.notes))
    end
    local press = "vim.api.nvim_feedkeys('zx', 'xt', false); vim.api.nvim_feedkeys('zx', 'xt', false)"
    local status = "table.insert(_G.LOG, require('zpack').get_plugin('aa').status .. ' lazy=' .. tostring(require('zpack').get_plugin('aa').lazy))"

    for name, opts in pairs({ ['with nothing else'] = '', ['and lazy = true'] = 'lazy = true,' }) do
      it(name .. " loads it, reports nothing, and leaves the real keymap", function()
        local result = session(plugin_with(keys_fn(), opts), status .. "; " .. press)
        no_errors(result)
        assert.are.equal(1, count(result.log, 'aa.config'))
        assert.are.equal(2, count(result.log, 'zx ran'))
        assert.is_true(vim.list_contains(result.log, 'loaded lazy=true'))
      end)
    end

    it("in an event loads it and reports nothing", function()
      local result = session(plugin_with("event = function() require('aa'); return { 'User Never' } end"), status)
      no_errors(result)
      assert.are.equal(1, count(result.log, 'aa.config'))
      assert.is_true(vim.list_contains(result.log, 'loaded lazy=true'))
    end)

    it("in a ft loads it and reports nothing", function()
      local result = session(plugin_with("ft = function() require('aa'); return { 'zzft' } end"), status)
      no_errors(result)
      assert.are.equal(1, count(result.log, 'aa.config'))
      assert.is_true(vim.list_contains(result.log, 'loaded lazy=true'))
    end)

    for name, opts in pairs({ ['with nothing else'] = '', ['and lazy = true'] = 'lazy = true,' }) do
      it("in a cmd " .. name .. " leaves the plugin's own command", function()
        local result = session(plugin_with("cmd = function() require('aa'); return { 'CmdA' } end", opts),
          "vim.cmd('CmdA'); vim.cmd('CmdA')")
        no_errors(result)
        assert.are.equal(1, count(result.log, 'aa.config'))
        assert.are.equal(2, count(result.log, 'CmdA ran'))
        assert.is_falsy(table.concat(result.notes, '\n'):find('E174', 1, true))
      end)
    end

    it("when the function just throws, reports it and leaves the plugin lazy", function()
      make_repo('aa')
      local result = session(
        ("{ spec = { { url = aa, name = 'aa', keys = function() error('boom') end } }, %s }"):format(defaults), status)
      assert.is_truthy(table.concat(result.notes, '\n'):find('Failed to resolve keys', 1, true))
      assert.is_true(vim.list_contains(result.log, 'pending lazy=true'))
    end)
  end)

  describe("a plugin/ script that errors", function()
    local config = "config = function() table.insert(_G.LOG, 'config') end"
    local status = "table.insert(_G.LOG, 'status=' .. require('zpack').get_plugin('broken').status)"

    local function setup_args(fields)
      return ("{ spec = { { url = broken, name = 'broken', %s, %s } }, defaults = { confirm = false } }")
          :format(fields, config)
    end

    before_each(function()
      make_repo('broken', {
        ['lua/broken.lua'] = { "return { loaded = true }" },
        ['plugin/a.lua'] = { "table.insert(_G.LOG, 'a'); error('boom')" },
        ['plugin/b.lua'] = { "table.insert(_G.LOG, 'b')" },
        ['plugin/c.vim'] = { "lua table.insert(_G.LOG, 'c')", "throw 'boom'" },
        ['plugin/d.vim'] = { "lua table.insert(_G.LOG, 'd')" },
        ['after/plugin/z.lua'] = { "table.insert(_G.LOG, 'after')" },
      })
    end)

    local function assert_loaded(result)
      for _, entry in ipairs({ 'a', 'b', 'c', 'd', 'after', 'config', 'status=loaded' }) do
        assert.is_true(vim.list_contains(result.log, entry), entry .. ': ' .. vim.inspect(result))
      end
      assert.are.equal(1, #vim.tbl_filter(function(entry) return entry == 'config' end, result.log))
      assert.is_truthy(table.concat(result.notes, '\n'):find('boom', 1, true))
    end

    it("doesn't make require() throw or skip config, after startup", function()
      local result = session(setup_args("lazy = true"), table.concat({
        "local ok, mod = pcall(require, 'broken')",
        "table.insert(_G.LOG, 'require=' .. tostring(ok and mod.loaded))",
        status,
      }, '; '))
      assert_loaded(result)
      assert.is_true(vim.list_contains(result.log, 'require=true'))
    end)

    it("doesn't skip config on a require from a +cmd, between load_plugins and VimEnter", function()
      local result = session(setup_args("lazy = true"), status, nil,
        { args = { '+lua require("broken"); table.insert(_G.LOG, "required")' } })
      assert_loaded(result)
      assert.is_true(vim.list_contains(result.log, 'required'))
    end)

    it("doesn't skip config for a proxied command", function()
      assert_loaded(session(setup_args("cmd = 'BrokenCmd'"), "pcall(vim.cmd, 'BrokenCmd'); " .. status))
    end)

    it("doesn't skip config for an event", function()
      assert_loaded(session(setup_args("event = 'User BrokenGo'"),
        "vim.api.nvim_exec_autocmds('User', { pattern = 'BrokenGo' }); " .. status))
    end)

    it("doesn't skip config for :ZPack load", function()
      assert_loaded(session(setup_args("lazy = true"), "vim.cmd('ZPack load broken'); " .. status))
    end)

    it("doesn't skip config for an eager plugin when setup() runs at VimEnter", function()
      assert_loaded(session(setup_args("lazy = false"), status, nil, { late = true }))
    end)

    it("doesn't skip config for an eager plugin", function()
      local result = session(setup_args("lazy = false"), status)
      assert.is_true(vim.list_contains(result.log, 'config'))
      assert.is_true(vim.list_contains(result.log, 'status=loaded'))
    end)

    it("doesn't skip config for a parent's lazy dependency, or the parent's", function()
      make_repo('parent')
      local result = session(
        ("{ spec = { { url = parent, name = 'parent', lazy = true, dependencies = { { url = broken, name = 'broken', %s } },"
          .. " config = function() table.insert(_G.LOG, 'parent.config') end } }, defaults = { confirm = false } }"):format(config),
        "pcall(vim.cmd, 'ZPack load parent'); " .. status
      )
      assert_loaded(result)
      assert.is_true(vim.list_contains(result.log, 'parent.config'))
    end)
  end)

  describe("setup() at VimEnter", function()
    local late = { late = true }
    local function config(name)
      return ("config = function() table.insert(_G.LOG, '%s.config') end"):format(name)
    end

    before_each(function()
      make_repo('aa')
    end)

    it("reports a dependency cycle once and runs configs in the order init.lua does", function()
      make_repo('bb')
      local result = session(([[{ spec = {
        { url = aa, name = 'aa', priority = 100, dependencies = { 'bb' }, %s },
        { url = bb, name = 'bb', dependencies = { 'aa' }, %s },
      }, defaults = { confirm = false } }]]):format(config('aa'), config('bb')), nil, nil, late)
      assert.is_true(vim.fn.index(result.log, 'bb.config') < vim.fn.index(result.log, 'aa.config'))
      assert.is_nil(table.concat(result.notes, '\n'):find('already being loaded', 1, true))
    end)

    for name, opts in pairs({ ['at VimEnter'] = late, ['during init'] = {} }) do
      it("binds keys after every config, " .. name, function()
        make_repo('bb')
        local result = session([[{ spec = {
          { url = aa, name = 'aa', priority = 100, lazy = false,
            keys = { { 'zx', function() table.insert(_G.LOG, 'zx=keys') end } } },
          { url = bb, name = 'bb', priority = 50,
            config = function() vim.keymap.set('n', 'zx', function() table.insert(_G.LOG, 'zx=config') end) end },
        }, defaults = { confirm = false } }]], "vim.api.nvim_feedkeys('zx', 'xt', false)", nil, opts)
        assert.is_true(vim.list_contains(result.log, 'zx=keys'))
      end)
    end

    it("lets a config use a command a lower priority plugin's plugin/ defines", function()
      make_repo('bb', { ['plugin/cmd.lua'] = { "vim.api.nvim_create_user_command('BbCmd', function() table.insert(_G.LOG, 'BbCmd ran') end, {})" } })
      local result = session([[{ spec = {
        { url = aa, name = 'aa', priority = 100, config = function() vim.cmd('BbCmd') end },
        { url = bb, name = 'bb', priority = 50 },
      }, defaults = { confirm = false } }]], nil, nil, late)
      assert.is_true(vim.list_contains(result.log, 'BbCmd ran'))
    end)
  end)

  it("a lazy command's first use gets what the real command called directly gets", function()
    local define = {
      "local function define(name, opts)",
      "  vim.api.nvim_create_user_command(name, function(a)",
      "    table.insert(_G.LOG, ('ran %s args=[%s] fargs=%d range=%d line2=%d count=%d bang=%s vert=%s'):format(",
      "      name, a.args, #a.fargs, a.range, a.line2, a.count, a.bang, a.smods.vertical))",
      "  end, opts)",
      "end",
      "define('Star', { nargs = '*' })",
      "define('One', { nargs = 1 })",
      "define('Opt', { nargs = '?' })",
      "define('Plus', { nargs = '+' })",
      "define('Zero', {})",
      "define('Cnt', { count = 0, nargs = '?' })",
      "define('Rng', { range = true, nargs = '*' })",
      "define('Whole', { range = '%', nargs = '*' })",
      "define('Bang', { bang = true, nargs = '*' })",
    }
    make_repo('aa', { ['plugin/cmds.lua'] = define })

    local names = "'Star', 'One', 'Opt', 'Plus', 'Zero', 'Cnt', 'Rng', 'Whole', 'Bang'"
    local function run(trigger, invocation)
      local result = session(
        ("{ spec = { { url = aa, name = 'aa', %s } }, defaults = { confirm = false } }"):format(trigger),
        ("local ok = pcall(vim.cmd, %q); table.insert(_G.LOG, 'raised=' .. tostring(ok == false))"):format(invocation)
      )
      local errors = vim.tbl_filter(function(note) return note:find('Failed', 1, true) ~= nil end, result.notes)
      local ran = vim.tbl_filter(function(entry) return entry ~= 'aa.plugin' and entry ~= 'raised=false' end, result.log)
      return #errors > 0 and {} or ran
    end

    for _, invocation in ipairs({
      'Star', 'Star 1 2', 'One 3', 'Opt 3', 'Plus 3', 'Zero', 'Cnt', 'Cnt 3', 'Rng 3', 'Whole 3',
      '7Cnt', '1,3Cnt', '%Rng', '%Whole', '1,1Rng', 'Bang!', 'Bang! 3', 'vert Star 1', 'vert 7Cnt',
      'Star "1 2"', 'One "1 2"', 'Star a|b', 'One a|b',
    }) do
      assert.are.same(run('lazy = false', invocation), run(('cmd = { %s }'):format(names), invocation), invocation)
    end
  end)

  it("a command a pending sibling still claims doesn't skip config", function()
    make_repo('aa', { ['plugin/cmd.vim'] = { "command ZpackShared echo 1" } })
    make_repo('bb')
    local result = session([[{ spec = {
      { url = aa, name = 'aa', cmd = 'ZpackShared', event = 'User AaGo', config = function() table.insert(_G.LOG, 'aa.config') end },
      { url = bb, name = 'bb', cmd = 'ZpackShared' },
    }, defaults = { confirm = false } }]], table.concat({
      "vim.api.nvim_exec_autocmds('User', { pattern = 'AaGo' })",
      "table.insert(_G.LOG, 'aa=' .. require('zpack').get_plugin('aa').status)",
    }, '; '))
    assert.is_true(vim.list_contains(result.log, 'aa.config'))
    assert.is_true(vim.list_contains(result.log, 'aa=loaded'))
    assert.is_truthy(table.concat(result.notes, '\n'):find('E174', 1, true))
  end)
end)
