local helpers = require('helpers')

describe("Setup and Initialization", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("setup() initializes zpack state", function()
    local state = require('zpack.state')

    assert.is_falsy(state.is_setup, "State should not be setup initially")

    require('zpack').setup({ spec = {}, defaults = { confirm = false } })

    assert.is_truthy(state.is_setup, "State should be setup after setup()")
    assert.is_not_nil(state.spec_registry, "Spec registry should exist")
    assert.is_not_nil(state.lazy_group, "Lazy group should exist")
    assert.is_not_nil(state.startup_group, "Startup group should exist")
  end)

  it("setup() cannot be called twice", function()
    local state = require('zpack.state')

    require('zpack').setup({ spec = {}, defaults = { confirm = false } })
    assert.is_truthy(state.is_setup, "State should be setup after first call")

    -- Second call should warn but state should remain setup
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })
    assert.is_truthy(state.is_setup, "State should still be setup after second call")
  end)

  it("setup() with specs as first argument registers plugins", function()
    local state = require('zpack.state')

    require('zpack').setup({
      { 'test/plugin1' },
      { 'test/plugin2' },
    })

    local src1 = 'https://github.com/test/plugin1'
    local src2 = 'https://github.com/test/plugin2'
    assert.is_not_nil(state.spec_registry[src1], "Plugin 1 should be registered")
    assert.is_not_nil(state.spec_registry[src2], "Plugin 2 should be registered")
  end)

  it("setup() with single spec as first argument", function()
    local state = require('zpack.state')

    require('zpack').setup({ 'test/plugin' })

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Single inline spec should be registered")
  end)

  it("setup() with spec field registers single plugin", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = { { 'test/plugin' } },
      defaults = { confirm = false },
    })

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin should be registered")
    local spec = state.spec_registry[src].merged_spec
    assert.are.equal('test/plugin', spec[1])
  end)

  it("setup() with spec as single spec (not wrapped in list)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = { 'test/plugin', config = function() end },
      defaults = { confirm = false },
    })

    local src = 'https://github.com/test/plugin'
    assert.is_not_nil(state.spec_registry[src], "Single spec should be registered")
  end)

  it("setup() with spec field registers multiple plugins", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/plugin1' },
        { 'test/plugin2' },
      },
      defaults = { confirm = false },
    })

    local src1 = 'https://github.com/test/plugin1'
    local src2 = 'https://github.com/test/plugin2'
    assert.is_not_nil(state.spec_registry[src1], "Plugin 1 should be registered")
    assert.is_not_nil(state.spec_registry[src2], "Plugin 2 should be registered")
  end)

  it("plugin spec supports src field", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { src = 'https://custom.url/plugin.git' },
      },
      defaults = { confirm = false },
    })

    local src = 'https://custom.url/plugin.git'
    assert.is_not_nil(state.spec_registry[src], "Plugin with src should be registered")
  end)

  it("plugin spec supports url field (lazy.nvim compat)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { url = 'https://custom.url/plugin.git' },
      },
      defaults = { confirm = false },
    })

    local src = 'https://custom.url/plugin.git'
    assert.is_not_nil(state.spec_registry[src], "Plugin with url should be registered")
  end)

  it("plugin spec supports dir field (lazy.nvim compat)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { dir = '/path/to/local/plugin' },
      },
      defaults = { confirm = false },
    })

    local src = '/path/to/local/plugin'
    assert.is_not_nil(state.spec_registry[src], "Plugin with dir should be registered")
  end)

  it("url overrides [1] shorthand (lazy.nvim fork idiom)", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = 'https://github.com/pedro757/flash.nvim.git' },
      },
      defaults = { confirm = false },
    })

    assert.is_not_nil(state.spec_registry['https://github.com/pedro757/flash.nvim.git'],
      "explicit url should win over [1]")
    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'],
      "[1] shorthand must not be used when url is set")
  end)

  it("source precedence is src > url > dir > [1]", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { 'test/a', src = 'https://srv/a-src', url = 'https://srv/a-url', dir = '/tmp/a-dir' },
        { 'test/b', url = 'https://srv/b-url', dir = '/tmp/b-dir' },
        { 'test/c', dir = '/tmp/c-dir' },
      },
      defaults = { confirm = false },
    })

    assert.is_not_nil(state.spec_registry['https://srv/a-src'], "src should win over url/dir/[1]")
    assert.is_not_nil(state.spec_registry['https://srv/b-url'], "url should win over dir/[1]")
    assert.is_not_nil(state.spec_registry['/tmp/c-dir'], "dir should win over [1]")
    for _, short in ipairs({ 'test/a', 'test/b', 'test/c' }) do
      assert.is_nil(state.spec_registry['https://github.com/' .. short],
        ("[1] shorthand must not be used for %s"):format(short))
    end
  end)

  it("plugin name derives from [1] even when a fork url wins the source", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/tokyo-fork'

    require('zpack').setup({
      spec = {
        { 'folke/tokyonight.nvim', url = fork },
      },
      defaults = { confirm = false },
    })

    assert.are.equal(fork, state.name_to_src['tokyonight.nvim'],
      "name must come from [1], not the fork URL basename")
    assert.is_nil(state.name_to_src['tokyo-fork'],
      "fork URL basename must not become the plugin name")
    assert.are.equal('tokyonight.nvim', state.src_to_pack_spec[fork].name,
      "pack spec handed to vim.pack must carry the [1]-derived name")
  end)

  it("fork override in a separate spec fragment merges into one plugin", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local shorthand = 'https://github.com/folke/flash.nvim'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', cmd = 'Flash' },
        { 'folke/flash.nvim', url = fork },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[shorthand],
      "shorthand fragment must fold into the explicit-source entry")
    local entry = state.spec_registry[fork]
    assert.is_not_nil(entry, "fork entry should own the merged plugin")
    assert.are.equal('Flash', entry.merged_spec.cmd,
      "base fragment's fields must survive the fold")
    assert.are.equal('Flash', entry.specs[1].cmd,
      "specs[1] must stay the earliest-imported fragment after the fold")
    assert.are.equal(fork, state.name_to_src['flash.nvim'])
  end)

  it("fork override fragment merges regardless of import order", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local shorthand = 'https://github.com/folke/flash.nvim'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = fork },
        { 'folke/flash.nvim', cmd = 'Flash' },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[shorthand])
    local entry = state.spec_registry[fork]
    assert.is_not_nil(entry)
    assert.are.equal('Flash', entry.merged_spec.cmd)
  end)

  it("dependency declared by shorthand folds into the fork entry and rekeys the graph", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local shorthand = 'https://github.com/folke/flash.nvim'
    local parent = 'https://github.com/test/parent'

    require('zpack').setup({
      spec = {
        { 'test/parent', dependencies = { 'folke/flash.nvim' } },
        { 'folke/flash.nvim', url = fork },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[shorthand])
    assert.is_not_nil(state.spec_registry[fork])
    assert.is_truthy(state.dependency_graph[parent][fork],
      "parent's dep edge must be rekeyed onto the fork src")
    assert.is_nil(state.dependency_graph[parent][shorthand],
      "stale shorthand dep edge must be removed")
    assert.is_truthy(state.reverse_dependency_graph[fork][parent],
      "reverse edge must point at the fork src")
    assert.is_nil(state.reverse_dependency_graph[shorthand])
  end)

  it("two fork fragments sharing a [1] fold into the later fragment's source", function()
    local state = require('zpack.state')
    local fork1 = 'https://github.com/me/flash-fork'
    local fork2 = 'https://github.com/me/flash-fork.git'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = fork1, event = 'InsertEnter', branch = 'one' },
        { 'folke/flash.nvim', url = fork2, cmd = 'Flash', branch = 'two' },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[fork1],
      "earlier fork fragment must fold into the later one, not abort on a name conflict")
    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'])
    local entry = state.spec_registry[fork2]
    assert.is_not_nil(entry, "later fork fragment must own the merged plugin")
    assert.are.equal('InsertEnter', entry.merged_spec.event,
      "earlier fragment's fields must survive the fold")
    assert.are.equal('Flash', entry.merged_spec.cmd)
    assert.are.equal('two', entry.merged_spec.branch,
      "OVERRIDE fields must resolve later-fragment-wins across the fold")
    assert.are.equal(fork2, state.name_to_src['flash.nvim'])
  end)

  it("bare fragment plus two fork fragments merge into the latest fork", function()
    local state = require('zpack.state')
    local fork1 = 'https://github.com/me/flash-fork-one'
    local fork2 = 'https://github.com/me/flash-fork-two'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', cmd = 'Flash' },
        { 'folke/flash.nvim', url = fork1 },
        { 'folke/flash.nvim', url = fork2 },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'])
    assert.is_nil(state.spec_registry[fork1])
    local entry = state.spec_registry[fork2]
    assert.is_not_nil(entry, "latest fork must absorb every fragment")
    assert.are.equal('Flash', entry.merged_spec.cmd,
      "bare fragment's fields must land on the winning fork")
    assert.are.equal(fork2, state.name_to_src['flash.nvim'])
  end)

  it("dependency on the plugin's own fork fragment leaves no empty reverse-graph set", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', dependencies = { { 'folke/flash.nvim', url = fork } } },
      },
      defaults = { confirm = false },
    })

    assert.is_not_nil(state.spec_registry[fork])
    assert.is_nil(state.spec_registry['https://github.com/folke/flash.nvim'])
    assert.is_nil(state.reverse_dependency_graph[fork],
      "dropping the fold's self-loop must not leave an empty reverse-dependency set")
  end)

  it("dev = true fragment wins the fold over a fork fragment regardless of order", function()
    local state = require('zpack.state')
    local dev_root = vim.fn.tempname()
    vim.fn.mkdir(dev_root .. '/flash.nvim', 'p')
    local fork = 'https://github.com/me/flash-fork'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', dev = true },
        { 'folke/flash.nvim', url = fork },
      },
      dev = { path = dev_root },
      defaults = { confirm = false },
    })

    local dev_src = dev_root .. '/flash.nvim'
    assert.is_not_nil(state.spec_registry[dev_src],
      "dev fragment must own the merged plugin even though the fork fragment is later")
    assert.is_nil(state.spec_registry[fork], "fork fragment must fold into the dev entry")
    assert.are.equal(dev_src, state.name_to_src['flash.nvim'])
  end)

  local function same_name_warnings()
    helpers.flush_pending()
    local found = {}
    for _, notif in ipairs(_G.test_state.notifications) do
      if notif.level == vim.log.levels.WARN and notif.msg:find('resolve to the same plugin', 1, true) then
        table.insert(found, notif.msg)
      end
    end
    return found
  end

  it("same-[1] fork override folds silently", function()
    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', cmd = 'Flash' },
        { 'folke/flash.nvim', url = 'https://github.com/me/flash-fork' },
      },
      defaults = { confirm = false },
    })

    assert.are.same({}, same_name_warnings(),
      "fragments naming the same [1] are an explicit override, not a source conflict")
  end)

  it("specs deriving the same name under different owners fold into one plugin", function()
    local state = require('zpack.state')
    local old = 'https://github.com/williamboman/mason.nvim'
    local new = 'https://github.com/mason-org/mason.nvim'
    local parent = 'https://github.com/test/lspconfig'
    local configured = false

    require('zpack').setup({
      spec = {
        { 'test/lspconfig', dependencies = { 'williamboman/mason.nvim' } },
        { 'mason-org/mason.nvim', config = function() configured = true end },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[old], "dependency-only fragment must fold into the top-level one")
    local entry = state.spec_registry[new]
    assert.is_not_nil(entry, "top-level fragment must own the merged plugin")
    assert.are.equal(2, #entry.specs)
    assert.are.equal(new, state.name_to_src['mason.nvim'])

    local names = {}
    for _, pack_spec in ipairs(_G.test_state.vim_pack_calls[1]) do
      if pack_spec.name == 'mason.nvim' then
        table.insert(names, pack_spec.src)
      end
    end
    assert.are.same({ new }, names, "vim.pack.add must receive a single mason.nvim spec")

    assert.is_truthy(state.dependency_graph[parent][new], "parent's dep edge must be rekeyed onto the winner")
    assert.is_nil(state.dependency_graph[parent][old])
    assert.is_truthy(state.reverse_dependency_graph[new][parent])
    assert.is_nil(state.reverse_dependency_graph[old])

    assert.is_true(configured, "config from the folded fragment must run")

    local warnings = same_name_warnings()
    assert.are.equal(1, #warnings, "exactly one WARN per fold of differing sources")
    assert.is_truthy(warnings[1]:find(old, 1, true), "warning must name the losing source")
    assert.is_truthy(warnings[1]:find('merged into ' .. new, 1, true), "warning must name the winning source")
  end)

  it("specs deriving the same name fold regardless of import order", function()
    local state = require('zpack.state')
    local old = 'https://github.com/williamboman/mason.nvim'
    local new = 'https://github.com/mason-org/mason.nvim'
    local parent = 'https://github.com/test/lspconfig'
    local configured = false

    require('zpack').setup({
      spec = {
        { 'mason-org/mason.nvim', config = function() configured = true end },
        { 'test/lspconfig', dependencies = { 'williamboman/mason.nvim' } },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[old], "top-level fragment must win even when imported first")
    assert.is_not_nil(state.spec_registry[new])
    assert.are.equal(new, state.name_to_src['mason.nvim'])
    assert.is_truthy(state.dependency_graph[parent][new])
    assert.is_nil(state.dependency_graph[parent][old])
    assert.is_true(configured, "config from the top-level fragment must run")
    assert.are.equal(1, #same_name_warnings())
  end)

  it("enabled = false on either same-name fragment disables the merged plugin (lazy.nvim parity)", function()
    local state = require('zpack.state')
    local configured = false

    require('zpack').setup({
      spec = {
        { 'williamboman/mason.nvim', enabled = false },
        { 'mason-org/mason.nvim', config = function() configured = true end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(state.spec_registry['https://github.com/mason-org/mason.nvim'],
      "the merged plugin must be pruned, not installed from the surviving owner")
    assert.is_nil(state.name_to_src['mason.nvim'])
    assert.is_false(configured)
    assert.are.equal(1, #same_name_warnings())
  end)

  it("explicit dependency fragment outranks a bare top-level fragment", function()
    local state = require('zpack.state')
    local old = 'https://github.com/old/x'
    local new = 'https://github.com/new/x'

    require('zpack').setup({
      spec = {
        { 'new/x', cmd = 'X' },
        { 'p/lsp', dependencies = { { 'old/x', url = old } } },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[new])
    assert.are.equal(old, state.name_to_src['x'])
    assert.are.equal('X', state.spec_registry[old].merged_spec.cmd)
    assert.are.equal(1, #same_name_warnings())
  end)

  it("a folded [1]-less fragment keeps its own name, not the winner's basename", function()
    local state = require('zpack.state')
    local upstream = 'https://github.com/user/repo'
    local fork = 'https://github.com/me/my-fork'
    local unrelated = 'https://github.com/someone/my-fork'

    require('zpack').setup({
      spec = {
        { url = upstream, event = 'InsertEnter' },
        { 'user/repo', url = fork },
        { 'someone/my-fork', cmd = 'Unrelated' },
      },
      defaults = { confirm = false },
    })

    assert.is_nil(state.spec_registry[upstream])
    assert.are.equal(fork, state.name_to_src['repo'])
    assert.are.equal(unrelated, state.name_to_src['my-fork'],
      "unrelated plugin sharing the fork's basename must survive")
    assert.are.equal('Unrelated', state.spec_registry[unrelated].merged_spec.cmd)
    assert.are.same({}, same_name_warnings(),
      "a url equal to the other fragment's [1] names the same repo, not a source conflict")
  end)

  it("explicit name keeps same-basename specs apart", function()
    local state = require('zpack.state')
    local old = 'https://github.com/williamboman/mason.nvim'
    local new = 'https://github.com/mason-org/mason.nvim'

    require('zpack').setup({
      spec = {
        { 'mason-org/mason.nvim' },
        { 'williamboman/mason.nvim', name = 'mason-legacy' },
      },
      defaults = { confirm = false },
    })

    assert.is_not_nil(state.spec_registry[new])
    assert.is_not_nil(state.spec_registry[old])
    assert.are.equal(new, state.name_to_src['mason.nvim'])
    assert.are.equal(old, state.name_to_src['mason-legacy'])
    assert.are.same({}, same_name_warnings())
  end)

  it("explicit name on one fragment keeps same-[1] fragments apart (lazy.nvim parity)", function()
    local state = require('zpack.state')
    local upstream = 'https://github.com/folke/flash.nvim'
    local fork = 'https://github.com/me/flash-fork'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', name = 'flash', url = fork },
        { 'folke/flash.nvim', cmd = 'Flash' },
      },
      defaults = { confirm = false },
    })

    assert.are.equal(fork, state.name_to_src['flash'])
    assert.are.equal(upstream, state.name_to_src['flash.nvim'])
    assert.are.same({}, same_name_warnings())
  end)

  it("entries fold by the name their merged spec resolves to, not by every [1] a fragment carries", function()
    local state = require('zpack.state')
    local upstream = 'https://github.com/user/repo'
    local other = 'https://github.com/other/repo'

    require('zpack').setup({
      spec = {
        { 'user/repo', event = 'InsertEnter' },
        { 'user/repo', name = 'alias' },
        { 'other/repo', cmd = 'Other' },
      },
      defaults = { confirm = false },
    })

    assert.are.equal(upstream, state.name_to_src['alias'])
    assert.are.equal('InsertEnter', state.spec_registry[upstream].merged_spec.event)
    assert.are.equal(other, state.name_to_src['repo'],
      "renaming user/repo via `name` must not fold an unrelated plugin with its old basename")
    assert.are.equal('Other', state.spec_registry[other].merged_spec.cmd)
    assert.are.same({}, same_name_warnings())
  end)

  it("a [1]-less fragment of a fork does not lend the fork's basename to the fold", function()
    local state = require('zpack.state')
    local fork = 'https://github.com/me/flash-fork'
    local unrelated = 'https://github.com/someone/flash-fork'

    require('zpack').setup({
      spec = {
        { 'folke/flash.nvim', url = fork },
        { url = fork, cmd = 'Flash' },
        { 'someone/flash-fork', cmd = 'Unrelated' },
      },
      defaults = { confirm = false },
    })

    assert.are.equal(fork, state.name_to_src['flash.nvim'])
    assert.are.equal('Flash', state.spec_registry[fork].merged_spec.cmd)
    assert.are.equal(unrelated, state.name_to_src['flash-fork'],
      "unrelated plugin sharing the fork's basename must survive")
    assert.are.same({}, same_name_warnings())
  end)

  it("dir field expands ~ to home directory", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        { dir = '~/projects/my-plugin' },
      },
      defaults = { confirm = false },
    })

    local expected_src = vim.fn.expand('~/projects/my-plugin')
    assert.is_not_nil(state.spec_registry[expected_src], "dir should expand ~ to home directory")
  end)
end)
