-- Real nvim processes: the suite's stubbed vim.v can't reproduce startup's phases.
describe("a real startup", function()
  local root, repos

  local function make_repo(name)
    local repo = repos .. '/' .. name
    vim.fn.mkdir(repo .. '/plugin', 'p')
    vim.fn.mkdir(repo .. '/after/plugin', 'p')
    vim.fn.writefile({ ("table.insert(_G.LOG, '%s.plugin')"):format(name) }, repo .. '/plugin/' .. name .. '.lua')
    vim.fn.writefile({ ("table.insert(_G.LOG, '%s.after')"):format(name) }, repo .. '/after/plugin/' .. name .. '.lua')
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

  ---@param spec_body string Lua for the spec list, with `aa` and `bb` as repo URLs
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
      ("local aa, bb = %q, %q"):format(make_repo('aa'), make_repo('bb')),
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

  it("sources after/plugin for an eager plugin when setup() runs at VimEnter", function()
    local log = start([[{ { url = aa, name = 'aa' } }]], { late = true })
    assert.are.same({ 'aa.plugin', 'aa.after' }, log)
  end)
end)
