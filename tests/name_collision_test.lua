local helpers = require('helpers')

---@param pattern string
---@return boolean
local function warned(pattern)
  for _, notif in ipairs(_G.test_state.notifications) do
    if notif.msg:find(pattern, 1, true) and notif.level == vim.log.levels.WARN then
      return true
    end
  end
  return false
end

---@return string[]
local function registered_srcs()
  local srcs = {}
  for _, pack_spec in ipairs(require('zpack.state').registered_plugins) do
    table.insert(srcs, pack_spec.src)
  end
  table.sort(srcs)
  return srcs
end

describe("Sources differing only in case", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("resolve to one plugin", function()
    require('zpack').setup({
      spec = {
        { 'test/Plugin.nvim' },
        { 'test/plugin.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({ 'https://github.com/test/Plugin.nvim' }, registered_srcs())
  end)

  it("merge their specs rather than racing for the directory", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        { 'test/Plugin.nvim', opts = { a = 1 } },
        {
          'test/plugin.nvim',
          opts = { b = 2 },
          config = function(_, opts)
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_not_nil(received_opts, "config from the second casing should still run")
    assert.are.equal(1, received_opts.a)
    assert.are.equal(2, received_opts.b)
  end)

  it("fold a dependency onto the casing of the plugin's own spec", function()
    -- The shape that motivated this: one spec file declares the plugin, and
    -- another lists it as a dependency with different casing.
    require('zpack').setup({
      spec = {
        { 'test/ZSnip.nvim' },
        { 'test/other', dependencies = { 'test/zsnip.nvim' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({
      'https://github.com/test/ZSnip.nvim',
      'https://github.com/test/other',
    }, registered_srcs())
  end)

  it("keep the dependency graph keyed by the surviving source", function()
    -- `register_dependencies` keys the graph from its own `normalize_source`
    -- call, before the dependency spec reaches the registry. If that key is
    -- not folded too it names a source no registry entry has, and the edge
    -- reads downstream as "no dependency" -- silently, since every consumer
    -- guards on the entry existing.
    require('zpack').setup({
      spec = {
        { 'test/ZSnip.nvim' },
        { 'test/other', dependencies = { 'test/zsnip.nvim' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    local parent = 'https://github.com/test/other'
    local dep = 'https://github.com/test/ZSnip.nvim'
    assert.are.same({ [dep] = true }, state.dependency_graph[parent])
    assert.are.same({ [parent] = true }, state.reverse_dependency_graph[dep])
  end)

  it("load a case-folded dependency when its lazy parent triggers", function()
    require('zpack').setup({
      spec = {
        { 'test/ZSnip.nvim', lazy = true },
        { 'test/other', cmd = 'Other', dependencies = { 'test/zsnip.nvim' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    assert.are.same({}, _G.test_state.loaded_plugins)

    vim.cmd('Other')
    helpers.flush_pending()

    assert.contains(_G.test_state.loaded_plugins, 'other')
    assert.contains(_G.test_state.loaded_plugins, 'ZSnip.nvim')
  end)

  it("keep the casing imported first", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin.nvim' },
        { 'test/PLUGIN.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({ 'https://github.com/test/plugin.nvim' }, registered_srcs())
  end)

  it("are not folded for local directories", function()
    -- Two paths differing in case are two directories on a case-sensitive
    -- filesystem, so they stay separate specs -- both installable, with a
    -- warning about the filesystems where they are not.
    require('zpack').setup({
      spec = {
        { dir = '/tmp/zpack-test/Plugin.nvim' },
        { dir = '/tmp/zpack-test/plugin.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({
      '/tmp/zpack-test/Plugin.nvim',
      '/tmp/zpack-test/plugin.nvim',
    }, registered_srcs())
    assert.is_true(warned('differing only in case'), "should report the case clash")
  end)
end)

describe("Two plugins claiming one directory", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("keep the one imported first and report the other", function()
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim' },
        { 'bob/shared.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({ 'https://github.com/alice/shared.nvim' }, registered_srcs())
    assert.is_true(warned('https://github.com/bob/shared.nvim'), "should name the skipped source")
    assert.is_true(warned('name = "..."'), "should say how to keep both")
  end)

  it("survive together when the names differ only in case", function()
    -- `shared.nvim` and `Shared.nvim` are two directories on ext4. Dropping
    -- one would remove a plugin that installs perfectly well there, so both
    -- are kept and the portability problem is reported instead.
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim' },
        { 'bob/Shared.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({
      'https://github.com/alice/shared.nvim',
      'https://github.com/bob/Shared.nvim',
    }, registered_srcs())
    assert.is_true(warned('differing only in case'), "should report the case clash")
    assert.is_false(warned('skipping'), "neither plugin is dropped")
  end)

  it("are both installed once `name` breaks the tie", function()
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim' },
        { 'bob/shared.nvim', name = 'shared-bob.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({
      'https://github.com/alice/shared.nvim',
      'https://github.com/bob/shared.nvim',
    }, registered_srcs())
    assert.is_false(warned('same plugin directory'), "nothing collides once names differ")
  end)

  it("do not let a disabled plugin win the directory", function()
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim', enabled = false },
        { 'bob/shared.nvim' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({ 'https://github.com/bob/shared.nvim' }, registered_srcs())
    assert.is_false(warned('same plugin directory'), "the disabled spec is not competing")
  end)

  it("take the skipped plugin's dep-only dependencies with them", function()
    -- bob/helper.nvim exists only to serve bob/shared.nvim. Once bob is
    -- skipped nothing wants it, so it must not be installed anyway.
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim' },
        { 'bob/shared.nvim', dependencies = { 'bob/helper.nvim' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.are.same({ 'https://github.com/alice/shared.nvim' }, registered_srcs())
  end)

  it("keep a dependency that something else still wants", function()
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim' },
        { 'bob/shared.nvim', dependencies = { 'common/helper.nvim' } },
        { 'carol/thing.nvim', dependencies = { 'common/helper.nvim' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.contains(registered_srcs(), 'https://github.com/common/helper.nvim')
  end)

  it("leave no graph edge naming a source the registry dropped", function()
    require('zpack').setup({
      spec = {
        { 'alice/shared.nvim' },
        { 'bob/shared.nvim', dependencies = { 'bob/helper.nvim' } },
        { 'carol/thing.nvim', dependencies = { 'bob/shared.nvim' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    for src, deps in pairs(state.dependency_graph) do
      assert.is_not_nil(state.spec_registry[src], src .. ' has outgoing edges but no entry')
      for dep_src in pairs(deps) do
        assert.is_not_nil(state.spec_registry[dep_src], dep_src .. ' is depended on but has no entry')
      end
    end
    for dep_src, parents in pairs(state.reverse_dependency_graph) do
      assert.is_not_nil(state.spec_registry[dep_src], dep_src .. ' has incoming edges but no entry')
      for parent_src in pairs(parents) do
        assert.is_not_nil(state.spec_registry[parent_src], parent_src .. ' is a parent but has no entry')
      end
    end
  end)
end)
