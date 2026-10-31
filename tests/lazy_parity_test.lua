-- Cross-cutting regression tests for lazy.nvim spec parity work. Each
-- describe block pins one parity-gap bead from the closure series; failures
-- here mean a parity gap has re-opened, not that the broader feature is
-- broken in any deeper way.

local helpers = require('helpers')

describe("version = false (zpack_nvim-9tm)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("normalize_version returns nil for version = false", function()
    local utils = require('zpack.utils')
    assert.is_nil(utils.normalize_version({ version = false }))
  end)

  it("version = false skips emitting a version on the vim.pack spec", function()
    require('zpack').setup({
      spec = { { 'test/v', version = false, branch = 'main' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local found
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.src == 'https://github.com/test/v' then
          found = pack_spec
        end
      end
    end
    assert.is_not_nil(found, "plugin must register with vim.pack")
    assert.is_nil(found.version,
      "version = false must drop the version even when branch is set")
  end)

  it("validate_spec accepts version = false", function()
    local validate = require('zpack.validate')
    local errs = validate.validate_spec({ 'a/b', version = false })
    assert.are.equal(0, #errs,
      "version = false must pass validation; got: " .. table.concat(errs, '; '))
  end)
end)

describe("Plugin shape: name/dir/dependencies (zpack_nvim-clj)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("plugin.name/dir/dependencies are populated in callbacks", function()
    local captured
    require('zpack').setup({
      spec = {
        { 'test/A' },
        {
          'test/B',
          dependencies = { 'test/A' },
          config = function(plugin)
            captured = {
              name = plugin.name,
              dir = plugin.dir,
              dependencies = plugin.dependencies,
            }
          end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_not_nil(captured, "config should have been called for test/B")
    assert.are.equal('B', captured.name, "plugin.name must alias spec.name")
    assert.is_string(captured.dir, "plugin.dir must alias plugin.path")
    assert.is_table(captured.dependencies)
    assert.contains(captured.dependencies, 'A')
  end)
end)

describe("nested specs field (zpack_nvim-74a)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("specs are walked as peer plugins, not dependencies", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          specs = {
            { 'test/companion' },
          },
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/parent'])
    assert.is_not_nil(state.spec_registry['https://github.com/test/companion'])

    -- specs entries must NOT be marked as dependencies of the parent
    local companion = state.spec_registry['https://github.com/test/companion']
    local is_dep = companion.specs[1]._is_dependency
    assert.is_falsy(is_dep, "Nested specs are peers, not dependencies")
  end)

  it("specs nested inside a dependencies chain stay peers, not deps", function()
    require('zpack').setup({
      spec = {
        {
          'test/root',
          dependencies = {
            {
              'test/dep',
              specs = { { 'test/sibling' } },
            },
          },
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local state = require('zpack.state')
    local dep = state.spec_registry['https://github.com/test/dep']
    local sibling = state.spec_registry['https://github.com/test/sibling']
    assert.is_not_nil(dep, "dep must register")
    assert.is_not_nil(sibling, "sibling declared via nested specs must register")
    assert.is_true(dep.specs[1]._is_dependency, "dep itself remains a dep")
    assert.is_falsy(sibling.specs[1]._is_dependency,
      "specs nested under a dep must NOT inherit is_dependency from ctx")
  end)
end)

describe("pin = true (zpack_nvim-gi5)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("bulk :ZPack update excludes pinned plugins from the explicit names list", function()
    require('zpack').setup({
      spec = {
        { 'test/free' },
        { 'test/pinned', pin = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    _G.test_state.vim_pack_update_calls = {}
    vim.cmd('ZPack update')

    assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
    local call = _G.test_state.vim_pack_update_calls[1]
    assert.is_not_nil(call.names, "Pin filter must pass an explicit names list, not nil")
    assert.contains(call.names, 'free')
    local saw_pinned = false
    for _, n in ipairs(call.names) do
      if n == 'pinned' then saw_pinned = true end
    end
    assert.is_false(saw_pinned, "Pinned plugin must NOT appear in the update list")
  end)
end)

describe("optional = true (zpack_nvim-sg0)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("optional-only plugins are dropped from registration", function()
    require('zpack').setup({
      spec = {
        { 'test/orphan', optional = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_nil(state.spec_registry['https://github.com/test/orphan'],
      "An optional-only plugin must be pruned")
  end)

  it("optional plugin survives when also referenced as a required dependency", function()
    require('zpack').setup({
      spec = {
        { 'test/parent', dependencies = { 'test/shared' } },
        { 'test/shared', optional = true, opts = { from_optional = true } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/shared'],
      "Optional + dep-referent must survive")
  end)

  -- Regression: a table-form dep `{ 'foo/x', optional = true }` was the
  -- only contributor for `x` (string-form deps get wrapped fresh without
  -- `optional`). Pre-fix the optional prune disabled `x` and cascade-
  -- disabled the parent. `_is_dependency` now defeats `optional`.
  it("optional written on a table-form dep skips the dep, not the parent", function()
    require('zpack').setup({
      spec = {
        { 'test/dep-parent', dependencies = { { 'test/dep-child', optional = true } } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/dep-parent'],
      "Parent must not be cascade-disabled by an optional table-form dep")
    assert.is_nil(state.spec_registry['https://github.com/test/dep-child'],
      "A dep whose specs are all optional is skipped, as in lazy.nvim")
    assert.is_nil(state.dependency_graph['https://github.com/test/dep-parent'],
      "A skipped optional dep leaves no edge")
  end)
end)

describe("specs declared under a removed plugin's dependencies", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup_with(parent)
    local received = nil
    require('zpack').setup({
      spec = {
        {
          'test/mason',
          opts_extend = { 'ensure_installed' },
          opts = { ensure_installed = { 'stylua' } },
          config = function(_, opts) received = opts end,
        },
        parent,
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    return received
  end

  it("are dropped from a plugin that stays when the parent is skipped as optional", function()
    local opts = setup_with({
      'test/dap', optional = true,
      dependencies = { { 'test/mason', opts = { ensure_installed = { 'delve' } } } },
    })
    assert.are.same({ 'stylua' }, opts.ensure_installed)
  end)

  it("are dropped from a plugin that stays when the parent is disabled", function()
    local opts = setup_with({
      'test/dap', enabled = false,
      dependencies = { { 'test/mason', opts = { ensure_installed = { 'delve' } } } },
    })
    local state = require('zpack.state')
    assert.are.same({ 'stylua' }, opts.ensure_installed)
    assert.are.equal(1, #state.spec_registry['https://github.com/test/mason'].specs)
  end)

  it("are dropped through a chain of dependencies", function()
    local opts = setup_with({
      'test/dap', optional = true,
      dependencies = {
        { 'test/dap-go', dependencies = { { 'test/mason', opts = { ensure_installed = { 'delve' } } } } },
      },
    })
    local state = require('zpack.state')
    assert.are.same({ 'stylua' }, opts.ensure_installed)
    assert.is_nil(state.spec_registry['https://github.com/test/dap-go'])
  end)

  it("drop a plugin left with only optional specs", function()
    require('zpack').setup({
      spec = {
        { 'test/dap', enabled = false, dependencies = { 'test/ui' } },
        { 'test/ui', optional = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_nil(state.spec_registry['https://github.com/test/ui'])
  end)

  for _, order in ipairs({ 'before', 'after' }) do
    it(("stay while another parent declaring the same table stays (disabled parent %s)"):format(order), function()
      local mason = { 'test/mason', opts = { ensure_installed = { 'delve' } } }
      local disabled = { 'test/dap', enabled = false, dependencies = { mason } }
      local kept = { 'test/lsp', dependencies = { mason } }
      require('zpack').setup({
        spec = order == 'before' and { disabled, kept } or { kept, disabled },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local state = require('zpack.state')
      local entry = state.spec_registry['https://github.com/test/mason']
      assert.is_not_nil(entry)
      assert.is_true(state.dependency_graph['https://github.com/test/lsp']['https://github.com/test/mason'])
      local opts = require('zpack.merge').resolve_opts(entry.sorted_specs, nil, entry.merged_spec.opts_extend)
      assert.are.same({ 'delve' }, opts.ensure_installed)
    end)
  end

  local GH = 'https://github.com/'

  local function setup_spec(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state')
  end

  local function pack_add_names()
    local names = {}
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack in ipairs(call) do
        names[#names + 1] = pack.name .. ' <- ' .. pack.src
      end
    end
    table.sort(names)
    return names
  end

  local function warnings()
    local msgs = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level == vim.log.levels.WARN then
        msgs[#msgs + 1] = n.msg
      end
    end
    return msgs
  end

  it("do not disable a plugin that stays, or its dependents", function()
    local state = setup_spec({
      { 'test/dap', enabled = false, dependencies = { { 'test/mason', enabled = false } } },
      { 'test/mason' },
      { 'test/lsp', dependencies = { 'test/mason' } },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'test/mason'])
    assert.is_not_nil(state.spec_registry[GH .. 'test/lsp'])
    assert.are.same({}, warnings())
  end)

  it("do not disable a plugin through a dependency only they declared", function()
    local state = setup_spec({
      { 'test/p', enabled = false, dependencies = { { 'test/a', dependencies = { 'test/z' } } } },
      { 'test/a' },
      { 'test/z', enabled = false },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'test/a'])
    assert.are.same({}, warnings())
  end)

  it("do not add their dependencies to a plugin that stays", function()
    local state = setup_spec({
      { 'test/p', enabled = false, dependencies = { { 'test/a', dependencies = { 'test/x' } } } },
      { 'test/a' },
      { 'test/x', cmd = 'XCmd' },
    })
    assert.is_nil(state.dependency_graph[GH .. 'test/a'])
    assert.is_nil(state.reverse_dependency_graph[GH .. 'test/x'])
    assert.are.same({}, state.spec_registry[GH .. 'test/a'].plugin.dependencies)
    assert.are.same({ 'a' }, _G.test_state.loaded_plugins)
  end)

  it("leave the plugin the name it was folded under", function()
    setup_spec({
      { 'test/p', enabled = false, dependencies = { { 'user/repo', name = 'alias' } } },
      { 'user/repo' },
      { 'other/repo' },
    })
    assert.are.same({ 'alias <- ' .. GH .. 'user/repo', 'repo <- ' .. GH .. 'other/repo' }, pack_add_names())
  end)

  it("do not decide where the plugin installs from", function()
    local state = setup_spec({
      { 'test/p', enabled = false, dependencies = { { 'user/repo', url = 'https://example.com/fork/repo' } } },
      { 'user/repo', dependencies = { 'test/dep' } },
      { 'test/top', dependencies = { 'user/repo' } },
    })
    assert.are.same({ 'dep <- ' .. GH .. 'test/dep', 'repo <- ' .. GH .. 'user/repo', 'top <- ' .. GH .. 'test/top' },
      pack_add_names())
    assert.is_true(state.dependency_graph[GH .. 'user/repo'][GH .. 'test/dep'])
    assert.is_true(state.dependency_graph[GH .. 'test/top'][GH .. 'user/repo'])
  end)

  it("include those under the parent's specs", function()
    local received
    setup_spec({
      { 'test/theme', enabled = false, specs = { { 'test/bufferline', opts = { from_theme = true } }, { 'test/extra' } } },
      { 'test/bufferline', opts = { base = true }, config = function(_, opts) received = opts end },
    })
    assert.are.same({ base = true }, received)
    assert.are.same({ 'bufferline <- ' .. GH .. 'test/bufferline' }, pack_add_names())
  end)

  it("log a plugin left with only optional specs", function()
    setup_spec({
      { 'test/dap', enabled = false, dependencies = { 'test/ui' } },
      { 'test/ui', optional = true },
    })
    local logged = vim.tbl_filter(function(n)
      return n.msg:find('test/ui skipped', 1, true) ~= nil
    end, _G.test_state.notifications)
    assert.are.equal(1, #logged)
  end)

  for _, field in ipairs({ 'specs', 'dependencies' }) do
    it(("still disable a plugin before an optional parent's %s go"):format(field), function()
      local state = setup_spec({
        { 'test/o', optional = true, [field] = { { 'test/x', enabled = false } } },
        { 'test/x' },
        { 'test/user', dependencies = { 'test/x' } },
      })
      assert.is_nil(state.spec_registry[GH .. 'test/x'])
      assert.is_not_nil(state.spec_registry[GH .. 'test/user'])
    end)
  end

  it("still disable a plugin before a nested optional parent goes", function()
    local state = setup_spec({
      { 'test/t', specs = { { 'test/o', optional = true, specs = { { 'test/y', enabled = false } } }, { 'test/y' } } },
    })
    assert.is_nil(state.spec_registry[GH .. 'test/y'])
    assert.is_not_nil(state.spec_registry[GH .. 'test/t'])
  end)

  -- The outcome used to depend on pairs() order, so try several names.
  for _, names in ipairs({
    { 'beta', 'gamma', 'd' }, { 'a1', 'z9', 'm5' }, { 'q', 'b', 'x' }, { 'zz', 'aa', 'mm' },
    { 'dap', 'mason', 'lsp' }, { 'k', 'kk', 'kkk' }, { 'x2', 'x1', 'x3' }, { 'n', 'o', 'p' },
  }) do
    local disabled, kept, dep = 'test/' .. names[1], 'test/' .. names[2], 'test/' .. names[3]
    it(("do not disable a plugin through a dependency declared under a nested disabled plugin (%s)")
      :format(table.concat(names, ',')), function()
      local state = setup_spec({
        { 'test/r', specs = { { disabled, enabled = false, dependencies = { { kept, dependencies = { dep } } } } } },
        { kept },
        { dep, enabled = false },
      })
      assert.is_not_nil(state.spec_registry[GH .. kept])
      assert.are.same({}, warnings())
    end)
  end

  for _, names in ipairs({
    { 'n1', 'n2' }, { 'n2', 'n1' }, { 'aa', 'zz' }, { 'zz', 'aa' }, { 'k', 'kk' }, { 'kk', 'k' },
    { 'q', 'b' }, { 'b', 'q' }, { 'dap', 'mason' }, { 'mason', 'dap' },
  }) do
    local first, second = 'test/' .. names[1], 'test/' .. names[2]
    local label = table.concat(names, ',')

    it(("warn about each plugin with a disabled dependency, nested or not (%s)")
      :format(label), function()
      local state = setup_spec({
        { 'test/r', specs = { { first, dependencies = { 'test/x', { second, dependencies = { 'test/y' } } } } } },
        { second },
        { 'test/x', enabled = false },
        { 'test/y', enabled = false },
      })
      assert.is_not_nil(state.spec_registry[GH .. first])
      assert.is_not_nil(state.spec_registry[GH .. second])
      local notes = 0
      for _, n in ipairs(_G.test_state.notifications) do
        if n.level == vim.log.levels.DEBUG and n.msg:find('may not work', 1, true) then
          notes = notes + 1
        end
      end
      assert.are.equal(2, notes)
    end)

    it(("do not disable a plugin through a nested disabled plugin's dependencies (%s)"):format(label), function()
      local state = setup_spec({
        { 'test/top', dependencies = { { first, enabled = false, dependencies = { { second, enabled = false } } } } },
        { second },
        { 'test/c', dependencies = { second } },
      })
      assert.is_not_nil(state.spec_registry[GH .. second])
      assert.is_not_nil(state.spec_registry[GH .. 'test/c'])
    end)

    it(("apply the specs of a plugin whose dependency is disabled (%s)"):format(label), function()
      local state = setup_spec({
        { 'test/user', dependencies = { first } },
        { first },
        { 'test/gone', dependencies = { second }, specs = { { first, enabled = false } } },
        { second, enabled = false },
      })
      assert.is_not_nil(state.spec_registry[GH .. 'test/user'])
      assert.is_nil(state.spec_registry[GH .. first])
      assert.is_not_nil(state.spec_registry[GH .. 'test/gone'])
    end)
  end

  it("evaluate a function-form enabled once", function()
    local calls = 0
    setup_spec({
      { 'test/p', enabled = false, dependencies = { { 'test/x', opts = { a = 1 } } } },
      { 'test/x', enabled = function() calls = calls + 1 return true end },
    })
    assert.are.equal(1, calls)
  end)

  it("evaluate a function-form enabled once when a dropped spec of the plugin set enabled", function()
    local calls = 0
    setup_spec({
      { 'test/x', enabled = function() calls = calls + 1 return true end },
      { 'test/p', enabled = false, dependencies = { { 'test/x', enabled = true } } },
    })
    assert.are.equal(1, calls)
  end)

  it("do not cascade to a plugin that has only optional specs", function()
    local state = setup_spec({
      { 'test/mason' },
      { 'test/dap', optional = true, dependencies = { { 'test/mason', opts = {} } } },
      { 'test/mason', enabled = false },
    })
    assert.is_nil(state.spec_registry[GH .. 'test/dap'])
    assert.are.same({}, warnings())
  end)

  it("leave a plugin the source the fold gave it while a spec with that source remains", function()
    setup_spec({
      { 'test/a', dependencies = { 'mason-org/mason.nvim' } },
      { 'test/b', dependencies = 'mason.nvim' },
      { 'test/opt', optional = true, dependencies = { { 'mason-org/mason.nvim', opts = {} } } },
    })
    assert.are.same({ 'a <- ' .. GH .. 'test/a', 'b <- ' .. GH .. 'test/b', 'mason.nvim <- ' .. GH .. 'mason-org/mason.nvim' },
      pack_add_names())
  end)

  it("drop a plugin settled by a top-level spec before one resting on its specs", function()
    local state = setup_spec({
      { 'test/x', dependencies = { { 'test/y', enabled = false } } },
      { 'test/y' },
      { 'test/x', enabled = false },
      { 'test/a', dependencies = { 'test/y' } },
    })
    assert.is_nil(state.spec_registry[GH .. 'test/x'])
    assert.is_not_nil(state.spec_registry[GH .. 'test/y'])
    assert.is_not_nil(state.spec_registry[GH .. 'test/a'])
  end)

  -- lua/plugins/*.lua files import in name order, so try both.
  for _, avante_first in ipairs({ true, false }) do
    it(("apply specs whatever the import order (%s first)")
      :format(avante_first and 'avante' or 'blink'), function()
      local avante = { 'yetone/avante.nvim', event = 'VeryLazy', dependencies = { 'hrsh7th/nvim-cmp' } }
      local blink = {
        'saghen/blink.cmp',
        event = 'InsertEnter',
        dependencies = { { 'rafamadriz/friendly-snippets', enabled = false } },
        specs = { { 'hrsh7th/nvim-cmp', enabled = false } },
      }
      local state = setup_spec(avante_first and { avante, blink } or { blink, avante })
      assert.is_not_nil(state.spec_registry[GH .. 'yetone/avante.nvim'])
      assert.is_nil(state.spec_registry[GH .. 'hrsh7th/nvim-cmp'])
      assert.is_not_nil(state.spec_registry[GH .. 'saghen/blink.cmp'])
    end)
  end

  it("are not kept in state after setup", function()
    local state = setup_spec({ { 'test/p', enabled = false, dependencies = { 'test/x' } }, { 'test/x' } })
    assert.is_nil(next(state.top_specs))
    assert.is_nil(next(state.spec_parents))
    assert.is_nil(next(state.spec_children))
    assert.is_nil(next(state.spec_src))
  end)

  it("keep the edge to a table listed in both a parent's dependencies and specs", function()
    local x = { 'test/x', cmd = 'XCmd' }
    local state = setup_spec({ { 'test/p', dependencies = { x }, specs = { x } } })
    assert.is_true(state.dependency_graph[GH .. 'test/p'][GH .. 'test/x'])
    assert.are.same({ 'p', 'x' }, _G.test_state.loaded_plugins)
  end)

  it("stay when the parent stays", function()
    local opts = setup_with({
      'test/dap',
      dependencies = { { 'test/mason', opts = { ensure_installed = { 'delve' } } } },
    })
    assert.are.same({ 'delve', 'stylua' }, opts.ensure_installed)
  end)
end)

describe("a spec table listed in several places", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("counts once toward opts_extend lists", function()
    local received
    local mason = { 'test/mason', opts = { ensure_installed = { 'delve' } } }
    require('zpack').setup({
      spec = {
        {
          'test/mason',
          opts_extend = { 'ensure_installed' },
          opts = { ensure_installed = { 'stylua' } },
          config = function(_, opts) received = opts end,
        },
        { 'test/dap', dependencies = { mason } },
        { 'test/lsp', dependencies = { mason } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.are.equal(2, #state.spec_registry['https://github.com/test/mason'].specs)
    assert.are.same({ 'delve', 'stylua' }, received.ensure_installed)
    assert.is_true(state.dependency_graph['https://github.com/test/dap']['https://github.com/test/mason'])
    assert.is_true(state.dependency_graph['https://github.com/test/lsp']['https://github.com/test/mason'])
  end)

  it("goes with its parent when it and another table list each other", function()
    local a = { 'test/a' }
    local b = { 'test/b', dependencies = { a } }
    a.dependencies = { b }
    require('zpack').setup({
      spec = { { 'test/p', enabled = false, dependencies = { a } }, { 'test/keep' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_nil(state.spec_registry['https://github.com/test/a'])
    assert.is_nil(state.spec_registry['https://github.com/test/b'])
    assert.is_not_nil(state.spec_registry['https://github.com/test/keep'])
  end)

  for _, order in ipairs({ 'first', 'second' }) do
    it(("stays when also listed at the top level (top-level listing %s)"):format(order), function()
      local plenary = { 'test/plenary', opts = { x = 1 } }
      local disabled = { 'test/p1', enabled = false, dependencies = { plenary } }
      require('zpack').setup({
        spec = order == 'first' and { plenary, disabled } or { disabled, plenary },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local entry = require('zpack.state').spec_registry['https://github.com/test/plenary']
      assert.is_not_nil(entry)
      assert.is_false(entry.specs[1]._is_dependency)
    end)

    it(("is a dependency when its other listing goes (removed listing %s)"):format(order), function()
      local t = { 'test/t' }
      local removed = { 'test/b', enabled = false, specs = { t } }
      local parent = { 'test/a', event = 'BufRead', dependencies = { t } }
      require('zpack').setup({
        spec = order == 'first' and { removed, parent } or { parent, removed },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      local entry = require('zpack.state').spec_registry['https://github.com/test/t']
      assert.is_true(entry.specs[1]._is_dependency)
      assert.is_true(entry.is_lazy_resolved)
    end)
  end
end)

describe("import = function() (zpack_nvim-fqs)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("function-form import returns specs that get registered", function()
    require('zpack').setup({
      spec = {
        { import = function()
            return { { 'test/dyn-a' }, { 'test/dyn-b' } }
          end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/test/dyn-a'])
    assert.is_not_nil(state.spec_registry['https://github.com/test/dyn-b'])
  end)

  it("throwing import function surfaces a structured notify", function()
    _G.test_state.notifications = {}
    require('zpack').setup({
      spec = {
        { import = function() error('simulated import failure', 0) end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local saw = false
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find('import function threw') then saw = true end
    end
    assert.is_true(saw, "import-function throw must surface a structured notify")
  end)
end)

describe(":ZPack sync (zpack_nvim-0sp)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("sync invokes vim.pack.update and clean_unused", function()
    require('zpack').setup({
      spec = { { 'test/p' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    _G.test_state.vim_pack_update_calls = {}
    _G.test_state.vim_pack_del_calls = {}

    -- Install an unrelated plugin via mocked vim.pack so clean_unused
    -- has something to remove.
    _G.test_state.registered_pack_specs['stray'] = {
      src = 'https://github.com/stray/stray',
      name = 'stray',
    }

    vim.cmd('ZPack sync')
    helpers.flush_pending()
    assert.are.equal(1, #_G.test_state.vim_pack_update_calls, "sync must update")
    local opts = _G.test_state.vim_pack_update_calls[1].opts
    assert.is_true(opts and opts.force == true,
      "sync must force-apply (no-force would race clean ahead of confirm)")
    assert.is_true(#_G.test_state.vim_pack_del_calls >= 1,
      "sync must clean unused plugins")
  end)
end)

describe("deactivate hook (zpack_nvim-aht) + :ZPack reload (zpack_nvim-dpl)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("validate accepts deactivate function", function()
    local validate = require('zpack.validate')
    local errs = validate.validate_spec({ 'a/b', deactivate = function() end })
    assert.are.equal(0, #errs)
  end)

  it("reload runs deactivate then re-runs config", function()
    local lifecycle = {}
    require('zpack').setup({
      spec = {
        {
          'test/relo',
          lazy = false,
          config = function() table.insert(lifecycle, 'config') end,
          deactivate = function() table.insert(lifecycle, 'deactivate') end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    -- The startup config call ran once during setup; reset before reload
    -- so the assertion below sees only the reload-time lifecycle events.
    lifecycle = {}

    vim.cmd('ZPack reload relo')
    helpers.flush_pending()

    -- Order: deactivate first (teardown), then config (fresh load).
    assert.are.same({ 'deactivate', 'config' }, lifecycle,
      ("Reload must call deactivate then config; got: %s"):format(vim.inspect(lifecycle)))
  end)

  it("reload clears package.loaded for plugin modules under its lua/", function()
    -- Plant a fake plugin on disk so the sweep has a real lua/ tree to fs_stat
    -- against. Mock vim.pack.get to point at it so reload resolves a real path.
    local tmp = vim.fn.tempname()
    local plugin_path = tmp .. '/sweepy'
    vim.fn.mkdir(plugin_path .. '/lua/sweepy/sub', 'p')
    local f = io.open(plugin_path .. '/lua/sweepy/init.lua', 'w')
    f:write('return { x = 1 }'); f:close()
    f = io.open(plugin_path .. '/lua/sweepy/sub/inner.lua', 'w')
    f:write('return { y = 2 }'); f:close()

    require('zpack').setup({
      spec = { { 'test/sweepy', lazy = false, main = 'sweepy' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Override path from the helpers' default stdpath('data')/... to the
    -- tmpdir we just populated, so the sweep's fs_stat actually finds files.
    local state = require('zpack.state')
    local src = 'https://github.com/test/sweepy'
    local pack_spec = _G.test_state.registered_pack_specs.sweepy
    state.spec_registry[src].plugin.path = plugin_path
    _G.test_state.original_vim_pack_get = vim.pack.get
    vim.pack.get = function() return { { spec = pack_spec, path = plugin_path } } end

    package.loaded['sweepy'] = { stale = true }
    package.loaded['sweepy.sub.inner'] = { stale = true }
    package.loaded['sweepy.absent'] = { stale = true } -- no file on disk
    package.loaded['unrelated'] = { stale = true }

    vim.cmd('ZPack reload sweepy')
    helpers.flush_pending()

    assert.is_nil(package.loaded['sweepy'], "reload must clear main module")
    assert.is_nil(package.loaded['sweepy.sub.inner'],
      "reload must clear submodule with on-disk file")
    assert.are.same({ stale = true }, package.loaded['sweepy.absent'],
      "reload must NOT clear keys with no on-disk file (sibling-plugin safety)")
    assert.are.same({ stale = true }, package.loaded['unrelated'],
      "reload must NOT touch keys outside the plugin's main namespace")
  end)
end)

describe("dev = true source rewrite (zpack_nvim-lkb)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("dev = true rewrites source to <dev.path>/<name> when dir exists", function()
    local dev_root = vim.fn.tempname()
    local plugin_dir = dev_root .. '/devplug.nvim'
    vim.fn.mkdir(plugin_dir, 'p')

    require('zpack').setup({
      spec = { { 'me/devplug.nvim', dev = true } },
      dev = { path = dev_root },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local found
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.src == plugin_dir then found = pack_spec end
      end
    end
    assert.is_not_nil(found, "dev = true must rewrite src to the local dir")
  end)

  it("dev.fallback = true falls back to remote when local dir is missing", function()
    require('zpack').setup({
      spec = { { 'me/devplug.nvim', dev = true } },
      dev = { path = vim.fn.tempname() .. '/missing', fallback = true },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local saw_remote
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.src == 'https://github.com/me/devplug.nvim' then
          saw_remote = true
        end
      end
    end
    assert.is_true(saw_remote, "fallback = true must use the remote source when local dir is missing")
  end)

  it("dev = true with no source field notifies and skips", function()
    require('zpack').setup({
      spec = { { dev = true, config = function() end } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local saw
    for _, n in ipairs(_G.test_state.notifications) do
      if type(n.msg) == 'string' and n.msg:find('requires a source field', 1, true) then
        saw = true
      end
    end
    assert.is_true(saw, "dev=true without a source field must notify")
  end)
end)

describe(":ZPack reload edge cases", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("reload re-runs init hook (matches fresh-load contract)", function()
    local lifecycle = {}
    require('zpack').setup({
      spec = {
        {
          'test/initrelo',
          lazy = false,
          init = function() table.insert(lifecycle, 'init') end,
          config = function() table.insert(lifecycle, 'config') end,
          deactivate = function() table.insert(lifecycle, 'deactivate') end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    lifecycle = {}

    vim.cmd('ZPack reload initrelo')
    helpers.flush_pending()

    assert.are.same({ 'deactivate', 'init', 'config' }, lifecycle,
      ("Reload must run deactivate → init → config; got: %s"):format(vim.inspect(lifecycle)))
  end)

  -- Regression: reload called try_call_hook unconditionally, emitting
  -- "expected init missing" ERROR for the common no-init case.
  it("reload does not emit 'expected init missing' notify when spec has no init", function()
    _G.test_state.notifications = {}
    require('zpack').setup({
      spec = {
        {
          'test/noinitrelo',
          lazy = false,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    _G.test_state.notifications = {}

    vim.cmd('ZPack reload noinitrelo')
    helpers.flush_pending()

    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(
        type(n.msg) == 'string' and n.msg:find('expected init missing', 1, true),
        ("Reload of a no-init spec must not emit 'expected init missing'; got: %s"):format(tostring(n.msg))
      )
    end
  end)

  it("reload skips deactivate when the plugin object is nil", function()
    -- Narrow but real window: vim.pack.add's load callback hasn't fired
    -- (install in progress or callback raised), so registry_entry.plugin
    -- stays nil. Reload must not call deactivate(nil).
    local called_deactivate = false
    require('zpack').setup({
      spec = {
        {
          'test/nilp',
          lazy = false,
          deactivate = function() called_deactivate = true end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Force the nil-plugin window the gate guards.
    local state = require('zpack.state')
    state.spec_registry['https://github.com/test/nilp'].plugin = nil

    vim.cmd('ZPack reload nilp')
    helpers.flush_pending()

    assert.is_false(called_deactivate,
      "Reload must NOT invoke deactivate when plugin object is nil")
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_falsy(type(n.msg) == 'string'
          and n.msg:find('Failed to run deactivate hook', 1, true),
        "Reload must not produce a deactivate failure notify for nil-plugin reload")
    end
  end)
end)

describe(":ZPack update names list preserves vim.pack universe under pin", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("includes installed-but-unregistered plugins so a single pin doesn't narrow the universe", function()
    require('zpack').setup({
      spec = {
        { 'test/free' },
        { 'test/pinned', pin = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Plugin vim.pack knows about but zpack does not (raw vim.pack.add or
    -- post-removal orphan). Pre-fix, any pin would skip this entry.
    _G.test_state.registered_pack_specs.orphan = {
      src = 'https://github.com/raw/orphan',
      name = 'orphan',
    }

    _G.test_state.vim_pack_update_calls = {}
    vim.cmd('ZPack update')

    assert.are.equal(1, #_G.test_state.vim_pack_update_calls)
    local names = _G.test_state.vim_pack_update_calls[1].names
    assert.is_not_nil(names)
    local has_free, has_pinned, has_orphan = false, false, false
    for _, n in ipairs(names) do
      if n == 'free' then has_free = true end
      if n == 'pinned' then has_pinned = true end
      if n == 'orphan' then has_orphan = true end
    end
    assert.is_true(has_free, "non-pinned registry plugin must be in the update list")
    assert.is_false(has_pinned, "pinned plugin must be excluded")
    assert.is_true(has_orphan,
      "installed-but-unregistered plugin must be in the update list")
  end)
end)

describe("spec lists", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function registered(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry
  end

  local function warnings()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("a dependencies list may mix tables and bare strings in any order", function()
    local registry = registered({
      { 'test/parent', dependencies = { { 'test/first', lazy = true }, 'test/second' } },
    })
    assert.is_not_nil(registry['https://github.com/test/first'])
    assert.is_not_nil(registry['https://github.com/test/second'])
    assert.is_true(require('zpack.state').dependency_graph['https://github.com/test/parent']['https://github.com/test/second'])
    assert.are.same({}, warnings())
  end)

  it("a bad dependencies entry warns and setup() carries on", function()
    local registry = registered({
      { 'test/parent', dependencies = { { 'test/first' }, 42 } },
      { 'test/after' },
    })
    assert.is_not_nil(registry['https://github.com/test/first'])
    assert.is_not_nil(registry['https://github.com/test/after'])
    assert.are.equal(1, #warnings())
  end)

  it("a top-level list may hold bare strings", function()
    local registry = registered({ 'test/a', { 'test/b' }, 'test/c' })
    assert.is_not_nil(registry['https://github.com/test/a'])
    assert.is_not_nil(registry['https://github.com/test/b'])
    assert.is_not_nil(registry['https://github.com/test/c'])
    assert.are.same({}, warnings())
  end)

  it("a list of only bare strings is a list of plugins, not one spec", function()
    local registry = registered({ 'test/a', 'test/b' })
    assert.is_not_nil(registry['https://github.com/test/a'])
    assert.is_not_nil(registry['https://github.com/test/b'])
  end)

  it("specs may be a string or hold bare strings", function()
    local registry = registered({
      { 'test/p', specs = 'test/a' },
      { 'test/q', specs = { 'test/b', 'test/c' } },
    })
    assert.is_not_nil(registry['https://github.com/test/a'])
    assert.is_not_nil(registry['https://github.com/test/b'])
    assert.is_not_nil(registry['https://github.com/test/c'])
    assert.are.same({}, warnings())
  end)

  it("lists may nest", function()
    local registry = registered({
      { { 'test/a' }, { { 'test/b' }, 'test/c' } },
      { 'test/p', dependencies = { { { 'test/d' }, { 'test/e' } } } },
    })
    for _, name in ipairs({ 'a', 'b', 'c', 'd', 'e' }) do
      assert.is_not_nil(registry['https://github.com/test/' .. name], name)
    end
    assert.is_true(require('zpack.state').dependency_graph['https://github.com/test/p']['https://github.com/test/e'])
    assert.are.same({}, warnings())
  end)

  it("an empty table in a list is nothing", function()
    local registry = registered({ {}, { 'test/a', dependencies = { {}, 'test/b' }, specs = { {} } } })
    assert.is_not_nil(registry['https://github.com/test/a'])
    assert.is_not_nil(registry['https://github.com/test/b'])
    assert.are.same({}, warnings())
  end)

  it("a spec with a source and an import registers the plugin and imports", function()
    local registry = registered({
      { 'test/framework', import = function() return { { 'test/from-import' } } end, lazy = true },
    })
    assert.is_not_nil(registry['https://github.com/test/framework'])
    assert.is_not_nil(registry['https://github.com/test/from-import'])
    assert.is_true(registry['https://github.com/test/framework'].sorted_specs[1]._import_order
      < registry['https://github.com/test/from-import'].sorted_specs[1]._import_order)
  end)

  for name, cond in pairs({ ['false'] = false, ['a function returning false'] = function() return false end }) do
    it("cond of " .. name .. " on an import skips it", function()
      local registry = registered({
        { import = function() return { { 'test/from-import' } } end, cond = cond },
      })
      assert.is_nil(registry['https://github.com/test/from-import'])
    end)
  end

  it("a dependencies entry may be an import", function()
    local registry = registered({
      { 'test/p', dependencies = { { import = function() return { { 'test/i' } } end } } },
      { 'test/q', dependencies = { import = function() return { { 'test/j' } } end } },
    })
    assert.is_true(require('zpack.state').dependency_graph['https://github.com/test/p']['https://github.com/test/i'])
    assert.is_true(require('zpack.state').dependency_graph['https://github.com/test/q']['https://github.com/test/j'])
    assert.are.same({}, warnings())
  end)

  it("entries after [1] in a spec with fields warn rather than vanish", function()
    registered({ { 'test/a', 'test/b', lazy = true } })
    local found = warnings()
    assert.are.equal(1, #found)
    assert.is_truthy(found[1]:find('entries after [1]', 1, true))
  end)

  it("a non-table specs value warns instead of aborting setup()", function()
    local registry = registered({
      { 'test/p', specs = 42 },
      { 'test/after' },
    })
    assert.is_not_nil(registry['https://github.com/test/p'])
    assert.is_not_nil(registry['https://github.com/test/after'])
    assert.are.equal(1, #warnings())
  end)

  describe("a module imported under several parents", function()
    local config_root, original_stdpath

    before_each(function()
      config_root = vim.fn.tempname()
      vim.fn.mkdir(config_root .. '/lua/shared_mod', 'p')
      vim.fn.writefile({ "return { { 'test/from-module' } }" }, config_root .. '/lua/shared_mod/x.lua')
      vim.opt.runtimepath:prepend(config_root)
      original_stdpath = vim.fn.stdpath
      vim.fn.stdpath = function(what)
        return what == 'config' and config_root or original_stdpath(what)
      end
    end)

    after_each(function()
      vim.fn.stdpath = original_stdpath
      vim.opt.runtimepath:remove(config_root)
      package.loaded['shared_mod.x'] = nil
      vim.fn.delete(config_root, 'rf')
    end)

    it("stays when a top-level import follows a removed parent's", function()
      local registry = registered({
        { 'test/p', enabled = false, specs = { { import = 'shared_mod' } } },
        { import = 'shared_mod' },
      })
      assert.is_not_nil(registry['https://github.com/test/from-module'])
    end)

    it("stays when a top-level import precedes a removed parent's", function()
      local registry = registered({
        { import = 'shared_mod' },
        { 'test/p', enabled = false, specs = { { import = 'shared_mod' } } },
      })
      assert.is_not_nil(registry['https://github.com/test/from-module'])
    end)

    it("registers its specs once", function()
      local registry = registered({
        { 'test/p', specs = { { import = 'shared_mod' } } },
        { import = 'shared_mod' },
      })
      assert.are.equal(1, #registry['https://github.com/test/from-module'].specs)
    end)
  end)

  it("a function import under a removed parent stays when imported at the top level too", function()
    local calls = 0
    local function shared()
      calls = calls + 1
      return { { 'test/from-fn' } }
    end
    local registry = registered({
      { 'test/p', enabled = false, specs = { { import = shared } } },
      { import = shared },
    })
    assert.is_not_nil(registry['https://github.com/test/from-fn'])
    assert.are.equal(1, #registry['https://github.com/test/from-fn'].specs)
    assert.are.equal(1, calls)
  end)
end)

describe("a [1] without an owner refers to a plugin by name", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function pack_srcs(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    local srcs = {}
    for src in pairs(require('zpack.state').spec_registry) do
      srcs[#srcs + 1] = src
    end
    table.sort(srcs)
    return srcs
  end

  local function warnings()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("does not take over the source of the plugin it refers to", function()
    local spec = {
      { 'catppuccin/nvim', name = 'catppuccin' },
      { 'catppuccin', optional = true, lazy = true },
    }
    assert.are.same({ 'https://github.com/catppuccin/nvim' }, pack_srcs(spec))
    assert.are.same({}, warnings())
  end)

  it("loses to the real repo whichever is imported first or at which tier", function()
    for _, spec in ipairs({
      { { 'mason.nvim', lazy = true }, { 'test/b', dependencies = { 'owner/mason.nvim' } } },
      { { 'test/b', dependencies = { 'owner/mason.nvim' } }, { 'mason.nvim', lazy = true } },
      { { 'test/a', dependencies = 'mason.nvim' }, { 'test/b', dependencies = { 'owner/mason.nvim' } } },
      { { 'test/b', dependencies = { 'owner/mason.nvim' } }, { 'test/a', dependencies = 'mason.nvim' } },
    }) do
      helpers.cleanup_test_env()
      helpers.setup_test_env()
      local srcs = pack_srcs(spec)
      assert.is_true(vim.list_contains(srcs, 'https://github.com/owner/mason.nvim'))
      assert.is_false(vim.list_contains(srcs, 'https://github.com/mason.nvim'))
      assert.are.same({}, warnings())
    end
  end)

  it("adds its fields and edge to the plugin it refers to", function()
    pack_srcs({
      { 'owner/mason.nvim' },
      { 'test/a', dependencies = 'mason.nvim' },
    })
    local state = require('zpack.state')
    assert.is_true(state.dependency_graph['https://github.com/test/a']['https://github.com/owner/mason.nvim'])
  end)

  it("is skipped with a warning when nothing gives a source, keeping its parent", function()
    local srcs = pack_srcs({ { 'test/a', dependencies = 'mason.nvim' } })
    assert.are.same({ 'https://github.com/test/a' }, srcs)
    local found = warnings()
    assert.are.equal(1, #found)
    assert.is_truthy(found[1]:find('mason.nvim', 1, true))
    assert.is_nil(require('zpack.state').dependency_graph['https://github.com/test/a'])
  end)

  it("names the plugin it refers to when skipped", function()
    pack_srcs({ { 'foo', name = 'bar' } })
    local found = warnings()
    assert.are.equal(1, #found)
    assert.is_truthy(found[1]:find('bar skipped', 1, true))
  end)

  describe("with dev = true whose checkout is missing, under dev.fallback", function()
    local function dev_srcs(spec)
      require('zpack').setup({
        spec = spec,
        dev = { path = vim.fn.tempname(), fallback = true },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      return vim.tbl_keys(require('zpack.state').spec_registry)
    end

    it("joins the plugin that gives a source, in either order", function()
      assert.are.same({ 'https://github.com/a/missing.nvim' },
        dev_srcs({ { 'a/missing.nvim' }, { 'missing.nvim', dev = true } }))
    end)

    it("is skipped when nothing gives one", function()
      assert.are.same({}, dev_srcs({ { 'missing.nvim', dev = true } }))
      assert.are.equal(1, #warnings())
    end)
  end)

  it("is skipped quietly when optional", function()
    assert.are.same({}, pack_srcs({ { 'catppuccin', optional = true } }))
    assert.are.same({}, warnings())
  end)

  it("is skipped when the only spec giving a source was dropped", function()
    local srcs = pack_srcs({
      { 'test/p', enabled = false, specs = { { 'owner/mason.nvim' } } },
      { 'mason.nvim', lazy = true },
    })
    assert.are.same({}, srcs)
    assert.are.equal(1, #warnings())
  end)

  it("keeps its dependencies when skipped", function()
    assert.are.same({ 'https://github.com/test/dep' }, pack_srcs({ { 'mason.nvim', dependencies = { 'test/dep' } } }))
  end)

  it("keeps a source given on the same spec", function()
    assert.are.same({ 'https://example.com/x.git' }, pack_srcs({ { 'x', url = 'https://example.com/x.git' } }))
    assert.are.same({}, warnings())
  end)
end)

describe("merged keys", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function resolved(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry['https://github.com/test/a']
  end

  local function mapped(lhs, mode)
    return vim.fn.maparg(lhs, mode or 'n') ~= ''
  end

  after_each(function()
    for _, lhs in ipairs({ '<F21>', '<F22>', '<F23>' }) do
      pcall(vim.keymap.del, { 'n', 'x' }, lhs)
      pcall(vim.keymap.del, 'n', lhs)
      pcall(vim.keymap.del, 'x', lhs)
    end
  end)

  it("string keys from two specs stay two keys", function()
    local entry = resolved({
      { 'test/a', keys = '<F21>' },
      { 'test/a', keys = '<F22>' },
    })
    assert.are.same({ { '<F21>' }, { '<F22>' } }, entry.merged_spec.keys)
    assert.is_true(mapped('<F21>'))
    assert.is_true(mapped('<F22>'))
  end)

  it("a list of strings is a list of keys, in one spec too", function()
    resolved({ { 'test/a', keys = { '<F21>', '<F22>' } } })
    assert.is_true(mapped('<F21>'))
    assert.is_true(mapped('<F22>'))
  end)

  it("a single KeySpec merged with a list keeps its rhs and options", function()
    local fn = function() end
    local entry = resolved({
      { 'test/a', keys = { '<F21>', fn, desc = 'one' } },
      { 'test/a', keys = { { '<F22>', fn } } },
    })
    assert.are.equal(2, #entry.merged_spec.keys)
    assert.are.equal('one', entry.merged_spec.keys[1].desc)
    assert.is_true(mapped('<F21>'))
    assert.is_true(mapped('<F22>'))
  end)

  it("a later spec's key replaces an earlier one", function()
    local entry = resolved({
      { 'test/a', keys = { { '<F21>', 'first' } } },
      { 'test/a', keys = { { '<F21>', 'second' } } },
    })
    assert.are.same({ { '<F21>', 'second' } }, entry.merged_spec.keys)
  end)

  it("a standalone spec's key beats a dependency's", function()
    local entry = resolved({
      { 'test/a', keys = { { '<F21>', 'standalone' } } },
      { 'test/p', dependencies = { { 'test/a', keys = { { '<F21>', 'dep' } } } } },
    })
    assert.are.same({ { '<F21>', 'standalone' } }, entry.merged_spec.keys)
  end)

  for name, rhs in pairs({ ['false'] = false, ['vim.NIL'] = vim.NIL }) do
    it("a later rhs of " .. name .. " disables a key and leaves the plugin lazy", function()
      local entry = resolved({
        { 'test/a', keys = { { '<F21>', 'x' }, { '<F22>', 'y' } } },
        { 'test/a', keys = { { '<F21>', rhs } } },
      })
      assert.is_false(mapped('<F21>'))
      assert.is_true(mapped('<F22>'))
      assert.is_true(entry.is_lazy_resolved)
    end)
  end

  it("a key disabled in its only spec is not mapped", function()
    resolved({ { 'test/a', keys = { { '<F21>', false } } } })
    assert.is_false(mapped('<F21>'))
  end)

  it("every key disabled still leaves the plugin lazy", function()
    local entry = resolved({
      { 'test/a', keys = { { '<F21>', 'x' } } },
      { 'test/a', keys = { { '<F21>', false } } },
    })
    assert.is_true(entry.is_lazy_resolved)
    assert.is_false(mapped('<F21>'))
  end)

  it("disabling one mode keeps the key's other modes", function()
    resolved({
      { 'test/a', keys = { { '<F21>', 'x', mode = { 'n', 'x' } } } },
      { 'test/a', keys = { { '<F21>', false, mode = 'x' } } },
    })
    assert.is_true(mapped('<F21>', 'n'))
    assert.is_false(mapped('<F21>', 'x'))
  end)

  it("lhs spellings of one key are one key", function()
    local entry = resolved({
      { 'test/a', keys = { { '<F21>', 'x' } } },
      { 'test/a', keys = { { '<f21>', false } } },
    })
    assert.is_false(mapped('<F21>'))
    assert.is_true(entry.is_lazy_resolved)
  end)

  it("a second string that can only be an rhs keeps one key", function()
    for _, rhs in ipairs({ '<cmd>Foo<cr>', '<Cmd>Foo<CR>', ':Foo<cr>', '<Plug>(foo)' }) do
      local keys = require('zpack.utils').normalize_keys({ '<F21>', rhs })
      assert.are.same({ { '<F21>', rhs } }, keys)
    end
  end)

  it("three strings stay three keys whatever the second looks like", function()
    assert.are.same({ { '<F21>' }, { '<cmd>x' }, { '<F22>' } },
      require('zpack.utils').normalize_keys({ '<F21>', '<cmd>x', '<F22>' }))
  end)

  it("a list starting with a string and holding a table is a list", function()
    assert.are.same({ { '<F21>' }, { '<F22>', 'x' } },
      require('zpack.utils').normalize_keys({ '<F21>', { '<F22>', 'x' } }))
  end)

  it("a key's table is not edited when it loses a mode", function()
    local key = { '<F21>', 'x', mode = { 'n', 'x' } }
    resolved({
      { 'test/a', keys = { key } },
      { 'test/a', keys = { { '<F21>', false, mode = 'x' } } },
    })
    assert.are.same({ 'n', 'x' }, key.mode)
  end)
end)

describe("function-form triggers across specs", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function resolved(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry['https://github.com/test/a']
  end

  local fields = {
    { 'cmd', 'ZpackOne', 'ZpackTwo' },
    { 'ft', 'lua', 'rust' },
    { 'event', 'BufRead', 'InsertEnter' },
    { 'keys', { '<F21>', 'x' }, { '<F22>', 'y' } },
  }

  for _, f in ipairs(fields) do
    local field, one, two = f[1], f[2], f[3]
    local function sets(value)
      return { 'test/a', [field] = value }
    end

    local function list(entry)
      return entry.merged_spec[field](entry.plugin, {})
    end

    it(field .. ": function then value keeps both", function()
      local entry = resolved({
        sets(function() return { one } end),
        sets({ two }),
      })
      assert.is_true(require('zpack.state').is_setup)
      assert.are.equal(2, #list(entry))
    end)

    it(field .. ": value then function receives the list and may replace it", function()
      local received
      local entry = resolved({
        sets({ one }),
        sets(function(_, acc) received = #acc; return { two } end),
      })
      assert.are.equal(1, #list(entry))
      assert.are.equal(1, received)
    end)

    it(field .. ": a function may edit the list in place and return nothing", function()
      local entry = resolved({
        sets({ one }),
        sets(function(_, acc) acc[#acc + 1] = two end),
      })
      assert.are.equal(2, #list(entry))
    end)

    it(field .. ": merging does not edit a spec's list", function()
      local own = { one }
      local entry = resolved({
        sets(own),
        sets(function(_, acc) acc[#acc + 1] = two end),
      })
      list(entry)
      list(entry)
      assert.are.same({ one }, own)
    end)
  end

  for _, f in ipairs(fields) do
    local field, one = f[1], f[2]

    it(field .. ": a lone function may edit the list and return nothing", function()
      local entry = resolved({
        { 'test/a', [field] = function(_, list) list[#list + 1] = one end },
      })
      assert.is_true(entry.is_lazy_resolved)
      assert.are.equal(1, #require('zpack.utils').try_resolve_field(entry.merged_spec[field], entry.plugin, 'a', field))
    end)

    it(field .. ": a function adding nothing leaves the plugin eager and setup() whole", function()
      local entry = resolved({
        { 'test/a', [field] = function(_, list) return list end },
        { 'test/after' },
      })
      assert.is_false(entry.is_lazy_resolved)
      assert.is_true(require('zpack.state').is_setup)
    end)

    it(field .. ": two functions adding nothing leave the plugin eager", function()
      local entry = resolved({
        { 'test/a', [field] = function() end },
        { 'test/a', [field] = function() end },
      })
      assert.is_false(entry.is_lazy_resolved)
    end)
  end

  for _, field in ipairs({ 'event', 'cmd', 'ft', 'keys' }) do
    it(field .. " = false leaves the plugin eager and setup() whole", function()
      local entry = resolved({ { 'test/a', [field] = false }, { 'test/after' } })
      assert.is_false(entry.is_lazy_resolved)
      assert.are.equal('loaded', entry.load_status)
      assert.is_true(require('zpack.state').is_setup)
    end)

    it(field .. ": a function returning false leaves the plugin eager", function()
      local entry = resolved({ { 'test/a', [field] = function() return false end } })
      assert.is_false(entry.is_lazy_resolved)
    end)

    it(field .. ": a later false clears the earlier value", function()
      local one = field == 'keys' and { { '<F21>', 'x' } } or (field == 'ft' and 'lua' or (field == 'cmd' and 'ZpackFalse' or 'BufRead'))
      local entry = resolved({ { 'test/a', [field] = one }, { 'test/a', [field] = false }, { 'test/after' } })
      assert.is_false(entry.is_lazy_resolved)
      assert.is_true(require('zpack.state').is_setup)
    end)

    it(field .. ": a value after false counts alone", function()
      local one = field == 'keys' and { { '<F21>', 'x' } } or (field == 'ft' and 'lua' or (field == 'cmd' and 'ZpackFalse' or 'BufRead'))
      local entry = resolved({ { 'test/a', [field] = false }, { 'test/a', [field] = one } })
      assert.is_true(entry.is_lazy_resolved)
      pcall(vim.api.nvim_del_user_command, 'ZpackFalse')
      pcall(vim.keymap.del, 'n', '<F21>')
    end)
  end

  it("a nested list of event names registers each event", function()
    local entry = resolved({ { 'test/a', event = { 'BufDelete', { 'BufHidden', 'BufNewFile' } } } })
    assert.is_true(entry.is_lazy_resolved)
    local autocmds = vim.api.nvim_get_autocmds({ group = require('zpack.state').lazy_group })
    local seen = {}
    for _, au in ipairs(autocmds) do
      seen[au.event] = true
    end
    assert.is_true(seen.BufDelete and seen.BufHidden and seen.BufNewFile)
  end)

  it("a malformed trigger reports its plugin and the others still set up", function()
    for _, spec in ipairs({
      { 'test/a', keys = { { desc = 'no lhs' } } },
      { 'test/a', cmd = { { 'Nested' } } },
      { 'test/a', event = 42 },
      { 'test/a', cmd = 42 },
      { 'test/a', ft = 42 },
      { 'test/a', keys = 42 },
      { 'test/a', cmd = function(plugin) return plugin and 42 end },
    }) do
      helpers.cleanup_test_env()
      helpers.setup_test_env()
      resolved({ spec, { 'test/b', cmd = 'ZpackAfterBad' } })
      assert.is_true(require('zpack.state').is_setup)
      assert.are.equal(2, vim.fn.exists(':ZpackAfterBad'))
      pcall(vim.api.nvim_del_user_command, 'ZpackAfterBad')
    end
  end)

  it("two plugins claiming one key spelled differently both load on it", function()
    require('zpack').setup({
      spec = {
        { 'test/a', keys = { { '<C-F21>', 'x' } } },
        { 'test/b', keys = { { '<c-f21>', 'y' } } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-F21>', true, true, true), 'x', false)
    helpers.flush_pending()
    local registry = require('zpack.state').spec_registry
    assert.are.equal('loaded', registry['https://github.com/test/a'].load_status)
    assert.are.equal('loaded', registry['https://github.com/test/b'].load_status)
    pcall(vim.keymap.del, 'n', '<C-F21>')
  end)

  it("an empty ft on a plugin with lazy = true does not abort setup()", function()
    resolved({ { 'test/a', lazy = true, ft = {} }, { 'test/after' } })
    assert.is_true(require('zpack.state').is_setup)
  end)

  it("a function editing key entries does not pile up or reach the spec", function()
    local own = { '<F21>', 'r' }
    local entry = resolved({
      { 'test/a', keys = { own } },
      { 'test/a', keys = function(_, keys) for _, k in ipairs(keys) do k[1] = '<F22>' .. k[1] end end },
    })
    local utils = require('zpack.utils')
    local first = utils.try_resolve_field(entry.merged_spec.keys, entry.plugin, 'a', 'keys')
    local second = utils.try_resolve_field(entry.merged_spec.keys, entry.plugin, 'a', 'keys')
    assert.are.same(first, second)
    assert.are.equal('<F21>', own[1])
  end)

  it("is not called before the plugin exists, and the plugin is lazy meanwhile", function()
    local seen_nil = false
    local entry = resolved({
      { 'test/a', keys = function(plugin) seen_nil = seen_nil or plugin == nil; return { { plugin.name .. 'x', 'r' } } end },
    })
    assert.is_false(seen_nil)
    assert.is_true(entry.is_lazy_resolved)
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_nil(n.msg:find('Failed to resolve', 1, true))
    end
    pcall(vim.keymap.del, 'n', 'ax')
  end)

  it("a dep sorted before its function-triggered parent stays lazy", function()
    resolved({
      { 'test/a', keys = function(plugin) return { { plugin.name .. 'y', 'r' } } end,
        dependencies = { { 'test/dep', priority = 100 } } },
    })
    assert.is_true(require('zpack.state').spec_registry['https://github.com/test/dep'].is_lazy_resolved)
    pcall(vim.keymap.del, 'n', 'ay')
  end)

  it("a lone function receives an empty list", function()
    local entry = resolved({
      { 'test/a', ft = function(_, ft) ft[#ft + 1] = 'lua'; return ft end },
    })
    assert.is_true(entry.is_lazy_resolved)
    assert.are.equal(1, #require('zpack.utils').try_resolve_field(entry.merged_spec.ft, nil, 'a', 'ft'))
  end)

  it("a throwing function in a merged field is reported, not fatal", function()
    resolved({
      { 'test/a', event = function() error('boom') end },
      { 'test/a', event = 'BufRead' },
      { 'test/after' },
    })
    assert.is_true(require('zpack.state').is_setup)
    local saw = false
    for _, n in ipairs(_G.test_state.notifications) do
      saw = saw or n.msg:find('boom', 1, true) ~= nil
    end
    assert.is_true(saw)
  end)

  it("EventSpecs from two specs both survive", function()
    local entry = resolved({
      { 'test/a', event = { event = 'BufRead', pattern = '*.lua' } },
      { 'test/a', event = { event = 'InsertEnter' } },
    })
    assert.are.equal(2, #entry.merged_spec.event)
  end)

  it("the same EventSpec from two specs counts once", function()
    local entry = resolved({
      { 'test/a', event = { event = 'BufRead', pattern = '*.lua' } },
      { 'test/a', event = { event = 'BufRead', pattern = '*.lua' } },
    })
    assert.are.equal(1, #entry.merged_spec.event)
  end)

  it("EventSpecs differing only by pattern both survive", function()
    local entry = resolved({
      { 'test/a', event = { event = 'BufRead', pattern = '*.lua' } },
      { 'test/a', event = { event = 'BufRead', pattern = '*.rs' } },
    })
    assert.are.equal(2, #entry.merged_spec.event)
  end)
end)

describe("the same-name fold warning", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function warnings(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("is not given for a spec under a removed plugin", function()
    assert.are.same({}, warnings({
      { 'u/p', enabled = false, dependencies = { 'other/x' } },
      { 'me/x' },
    }))
  end)

  it("is given while both sides stay", function()
    local found = warnings({ { 'other/x' }, { 'me/x' } })
    assert.are.equal(1, #found)
    assert.is_truthy(found[1]:find('resolve to the same plugin', 1, true))
  end)

  it("is not given when both sides sit under a removed plugin", function()
    assert.are.same({}, warnings({ { 'u/p', enabled = false, dependencies = { 'a/foo', 'b/foo' } } }))
  end)

  it("is not given when both sides are skipped as optional", function()
    assert.are.same({}, warnings({ { 'a/foo', optional = true }, { 'b/foo', optional = true } }))
  end)

  it("is given when the whole plugin is disabled", function()
    local found = warnings({ { 'old/x', enabled = false }, { 'new/x' } })
    assert.are.equal(1, #found)
  end)
end)

describe("a dependency of a lazy plugin's dependency", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local src = function(name)
    return 'https://github.com/u/' .. name
  end

  local function registered(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry
  end

  it("is lazy, and loads with the top plugin", function()
    local registry = registered({
      { 'u/a', cmd = 'ZpackChainA', dependencies = { { 'u/b', dependencies = { 'u/c' } } } },
    })
    assert.is_true(registry[src('b')].is_lazy_resolved)
    assert.is_true(registry[src('c')].is_lazy_resolved)
    assert.are.equal('pending', registry[src('c')].load_status)
    pcall(vim.cmd.ZpackChainA)
    helpers.flush_pending()
    assert.are.equal('loaded', registry[src('c')].load_status)
    pcall(vim.api.nvim_del_user_command, 'ZpackChainA')
  end)

  it("stays eager under a parent with lazy = false", function()
    local registry = registered({
      { 'u/a', cmd = 'ZpackChainB', dependencies = { { 'u/b', lazy = false, dependencies = { 'u/c' } } } },
    })
    assert.is_false(registry[src('c')].is_lazy_resolved)
    pcall(vim.api.nvim_del_user_command, 'ZpackChainB')
  end)

  it("stays eager when the chain ends at an eager plugin", function()
    local registry = registered({
      { 'u/a', dependencies = { { 'u/b', dependencies = { 'u/c' } } } },
    })
    assert.is_false(registry[src('c')].is_lazy_resolved)
  end)

  it("settles a dependency cycle without overflowing", function()
    local registry = registered({
      { 'u/a', dependencies = { 'u/b' } },
      { 'u/b', dependencies = { 'u/a' } },
    })
    assert.is_false(registry[src('a')].is_lazy_resolved)
    assert.is_false(registry[src('b')].is_lazy_resolved)
  end)

  it("in a dependency-only cycle under a lazy plugin is lazy from every member", function()
    local b = { 'u/b' }
    local c = { 'u/c', dependencies = { b } }
    b.dependencies = { c }
    local registry = registered({ { 'u/a', cmd = 'ZpackChainC', dependencies = { b } } })
    assert.is_true(registry[src('b')].is_lazy_resolved)
    assert.is_true(registry[src('c')].is_lazy_resolved)
    pcall(vim.api.nvim_del_user_command, 'ZpackChainC')
  end)
end)

describe("the disabled dependency warning", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("names only the plugin whose own dependency is disabled", function()
    require('zpack').setup({
      spec = {
        { 'u/top', dependencies = { 'u/mid' } },
        { 'u/mid', dependencies = { 'u/leaf' } },
        { 'u/leaf', enabled = false },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level == vim.log.levels.DEBUG and n.msg:find('may not work', 1, true) then
        found[#found + 1] = n.msg
      end
    end
    assert.are.equal(1, #found)
    assert.is_truthy(found[1]:find(
      'https://github.com/u/mid may not work: its dependency https://github.com/u/leaf has enabled=false', 1, true))
  end)

  it("stays quiet about a dependency the plugin's own spec turned off", function()
    require('zpack').setup({
      spec = {
        { 'u/p', dependencies = { { 'u/fzf', enabled = false } } },
        { 'u/p', dependencies = { 'u/fzf' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local state = require('zpack.state')
    assert.is_not_nil(state.spec_registry['https://github.com/u/p'])
    assert.is_nil(state.spec_registry['https://github.com/u/fzf'])
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_true(n.level < vim.log.levels.WARN, n.msg)
    end
  end)

  it("appears once per parent and dependency", function()
    require('zpack').setup({
      spec = {
        { 'u/p', dependencies = { 'u/d' } },
        { 'u/p', dependencies = { 'u/d' } },
        { 'u/d', enabled = false },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local count = 0
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find('may not work', 1, true) then
        count = count + 1
      end
    end
    assert.are.equal(1, count)
  end)
end)

describe("true on a trigger", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup(spec)
    require('zpack').setup({ spec = { spec }, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry['https://github.com/test/a']
  end

  for _, field in ipairs({ 'event', 'cmd', 'ft', 'keys' }) do
    it(field .. " = true warns and leaves the plugin eager", function()
      local entry = setup({ 'test/a', [field] = true })
      assert.is_false(entry.is_lazy_resolved)
      local errors = require('zpack.validate').validate_spec({ 'test/a', [field] = true })
      assert.are.equal(1, #errors)
      assert.truthy(errors[1]:find(field, 1, true))
    end)

    it(field .. " = false is accepted and leaves the plugin eager", function()
      local entry = setup({ 'test/a', [field] = false })
      assert.is_false(entry.is_lazy_resolved)
      assert.are.same({}, require('zpack.validate').validate_spec({ 'test/a', [field] = false }))
    end)
  end

  it("keys = { true } warns and leaves the plugin eager", function()
    local entry = setup({ 'test/a', keys = { true } })
    assert.is_false(entry.is_lazy_resolved)
    assert.are.equal(1, #require('zpack.validate').validate_spec({ 'test/a', keys = { true } }))
  end)
end)

describe("malformed triggers stay with their plugin", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup(spec)
    require('zpack').setup({
      spec = vim.list_extend(spec, { { 'test/after', cmd = 'ZpackAfterBad', keys = { { '<F23>', 'x' } } } }),
      defaults = { confirm = false },
    })
    helpers.flush_pending()
  end

  local function notified(pattern)
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find(pattern, 1, true) then
        return true
      end
    end
    return false
  end

  local function assert_rest_set_up()
    assert.is_true(require('zpack.state').is_setup)
    assert.are.equal(2, vim.fn.exists(':ZpackAfterBad'))
    assert.are_not.equal('', vim.fn.maparg('<F23>', 'n'))
    assert.are.equal(2, vim.fn.exists(':ZPack'))
    pcall(vim.api.nvim_del_user_command, 'ZpackAfterBad')
    pcall(vim.keymap.del, 'n', '<F23>')
  end

  for _, case in ipairs({
    { 'invalid cmd name', { { 'test/a', cmd = 'foo' } } },
    { 'invalid cmd name beside a good one', { { 'test/a', cmd = { 'ZpackGoodOne', 'bad' } } } },
    { 'key-level ft of the wrong type', { { 'test/a', keys = { { 'za', ft = { 1 } } } } } },
    { 'key mode of the wrong type', { { 'test/a', keys = { { 'za', mode = 1 } } } } },
    { 'key without a string lhs', { { 'test/a', keys = { { 1, 'a' } } } } },
    { 'merged key mode of the wrong type',
      { { 'test/a', keys = { { 'za', mode = 1 } } }, { 'test/a', keys = 'zb' } } },
    { 'merged key ft that cannot sort',
      { { 'test/a', keys = { { 'za', ft = { 1, 'x' } } } }, { 'test/a', keys = 'zb' } } },
    { 'merged key without an lhs',
      { { 'test/a', keys = { { desc = 'x' } } }, { 'test/a', keys = 'zb' } } },
    { 'merged cmd of the wrong type', { { 'test/a', cmd = { 1 } }, { 'test/a', cmd = 'zb' } } },
    { 'merged event of the wrong type', { { 'test/a', event = { 1 } }, { 'test/a', event = 'BufRead' } } },
    { 'merged ft of the wrong type', { { 'test/a', ft = { 1 } }, { 'test/a', ft = 'lua' } } },
    { 'true trigger', { { 'test/a', cmd = true, keys = true, ft = true, event = true } } },
  }) do
    it(case[1] .. " leaves setup() and other plugins intact", function()
      setup(case[2])
      assert_rest_set_up()
      pcall(vim.api.nvim_del_user_command, 'ZpackGoodOne')
    end)
  end

  it("reports an invalid command name against its plugin", function()
    setup({ { 'test/a', cmd = { 'foo', 'ZpackGoodTwo' } } })
    pcall(vim.api.nvim_del_user_command, 'ZpackGoodTwo')
    assert.is_true(notified('Failed to set up cmd for a'))
  end)

  it("a bad key doesn't strand the plugin's other keys", function()
    setup({ { 'test/a', keys = { { 1, 'a' }, { '<F24>', 'c' } } } })
    assert.is_true(notified('Failed to set up keys for a'))
    assert.are_not.equal('', vim.fn.maparg('<F24>', 'n'))
    pcall(vim.keymap.del, 'n', '<F24>')
    pcall(vim.keymap.del, 'n', '<F23>')
  end)

  it("a merged bad key doesn't strand the plugin's other keys", function()
    setup({
      { 'test/a', keys = { { 'za', mode = 1 } } },
      { 'test/a', keys = { { '<F24>', 'c' } } },
    })
    assert.is_true(notified('Failed to set up keys for a'))
    assert.are_not.equal('', vim.fn.maparg('<F24>', 'n'))
    pcall(vim.keymap.del, 'n', '<F24>')
    pcall(vim.keymap.del, 'n', '<F23>')
  end)
end)

describe("rhs-only strings in a two-string key", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  for _, rhs in ipairs({ '<Nop>', '<nop>', '', '<cmd>x<cr>', '<Plug>(x)', ':x<cr>' }) do
    it(("{ lhs, %q } is one key"):format(rhs), function()
      local keys = require('zpack.utils').normalize_keys({ 'zx', rhs })
      assert.are.equal(1, #keys)
      assert.are.equal('zx', keys[1][1])
      assert.are.equal(rhs, keys[1][2])
    end)
  end

  it("{ 'zx', '<Nop>' } installs a no-op that doesn't load the plugin", function()
    require('zpack').setup({
      spec = { { 'test/a', keys = { 'zx', '<Nop>' } } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    assert.are.equal('', vim.fn.maparg('<lt>Nop>', 'n'))
    assert.is_false(vim.fn.maparg('zx', 'n', false, true).expr == 1)
    pcall(vim.keymap.del, 'n', 'zx')
  end)
end)

describe("a function trigger that yields nothing", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("leaves its dependency eager and loaded first, even with a higher priority", function()
    require('zpack').setup({
      spec = { { 'test/a', keys = function() end, dependencies = { { 'test/dep', priority = 1000 } } } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    local registry = require('zpack.state').spec_registry
    assert.is_false(registry['https://github.com/test/a'].is_lazy_resolved)
    assert.is_false(registry['https://github.com/test/dep'].is_lazy_resolved)
    -- Added last, so it comes first in 'runtimepath' and sources first.
    assert.are.same({ 'a', 'dep' }, _G.test_state.loaded_plugins)
  end)

  it("doesn't depend on the order plugins come back from vim.pack", function()
    for _, priority in ipairs({ 1, 1000 }) do
      helpers.cleanup_test_env()
      helpers.setup_test_env()
      require('zpack').setup({
        spec = { { 'test/a', cmd = function() end, dependencies = { { 'test/dep', priority = priority } } } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
      assert.is_false(require('zpack.state').spec_registry['https://github.com/test/dep'].is_lazy_resolved)
    end
  end)

  it("calls the trigger with the plugin from the dependency's check too", function()
    local saw_nil = false
    require('zpack').setup({
      spec = { { 'test/a', cmd = function(plugin)
        saw_nil = saw_nil or plugin == nil
        return 'ZpackFromFn'
      end, dependencies = { { 'test/dep', priority = 1000 } } } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    assert.is_false(saw_nil)
    assert.is_true(require('zpack.state').spec_registry['https://github.com/test/dep'].is_lazy_resolved)
    pcall(vim.api.nvim_del_user_command, 'ZpackFromFn')
  end)
end)
describe("cond and enabled on an import", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function registered(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry
  end

  local function import()
    return { { 'test/imported' } }
  end

  for _, field in ipairs({ 'cond', 'enabled' }) do
    it(field .. " = false skips the import, so its plugins aren't registered", function()
      local registry = registered({ { import = import, [field] = false } })
      assert.is_nil(registry['https://github.com/test/imported'])
    end)

    it(field .. " = true follows the import", function()
      local registry = registered({ { import = import, [field] = true } })
      assert.is_not_nil(registry['https://github.com/test/imported'])
    end)
  end

  it("cond receives no plugin", function()
    local called, arg = false, 'unset'
    registered({ { import = import, cond = function(plugin)
      called, arg = true, plugin
      return true
    end } })
    assert.is_true(called)
    assert.is_nil(arg)
  end)

  it("defaults.cond doesn't apply to an import", function()
    require('zpack').setup({ spec = { { import = import } }, defaults = { confirm = false, cond = false } })
    helpers.flush_pending()
    assert.is_not_nil(require('zpack.state').spec_registry['https://github.com/test/imported'])
  end)

  it("on a plugin with an import, cond keeps the plugin and enabled removes it", function()
    local registry = registered({ { 'test/withcond', import = import, cond = false } })
    assert.is_not_nil(registry['https://github.com/test/withcond'])
    assert.is_nil(registry['https://github.com/test/imported'])
    helpers.cleanup_test_env()
    helpers.setup_test_env()
    registry = registered({ { 'test/withenabled', import = import, enabled = false } })
    assert.is_nil(registry['https://github.com/test/withenabled'])
    assert.is_nil(registry['https://github.com/test/imported'])
  end)
end)


describe("a plugin turned off by an optional spec", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local GH = 'https://github.com/'

  local function setup_spec(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state')
  end

  local function warnings()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("is removed without disabling the plugins depending on it", function()
    local state = setup_spec({
      { 'test/cmp', dependencies = { 'test/cmp-buffer' } },
      { 'test/cmp', dependencies = { { 'test/snippets', opts = {} } } },
      { 'test/snippets', optional = true, enabled = false },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'test/cmp'])
    assert.is_not_nil(state.spec_registry[GH .. 'test/cmp-buffer'])
    assert.is_nil(state.spec_registry[GH .. 'test/snippets'])
    assert.is_nil(state.dependency_graph[GH .. 'test/cmp'][GH .. 'test/snippets'])
    assert.are.same({}, warnings())
  end)

  it("is removed when the spec under dependencies is the optional one", function()
    local state = setup_spec({
      { 'test/p', dependencies = { { 'test/d', optional = true, enabled = function() return false end } } },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'test/p'])
    assert.is_nil(state.spec_registry[GH .. 'test/d'])
    assert.are.same({}, warnings())
  end)

  it("notes its dependents if another spec turns it off outright", function()
    local state = setup_spec({
      { 'test/p', dependencies = { 'test/d' } },
      { 'test/d', optional = true, enabled = false },
      { 'test/d', enabled = false },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'test/p'])
    assert.is_nil(state.spec_registry[GH .. 'test/d'])
    local notes = 0
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level == vim.log.levels.DEBUG and n.msg:find('may not work', 1, true) then
        notes = notes + 1
      end
    end
    assert.are.equal(1, notes)
  end)
end)

describe("event setup", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup_event(event)
    require('zpack').setup({ spec = { { 'test/a', event = event } }, defaults = { confirm = false } })
    helpers.flush_pending()
    local found = {}
    for _, au in ipairs(vim.api.nvim_get_autocmds({ group = require('zpack.state').lazy_group })) do
      found[au.event .. ' ' .. au.pattern] = true
    end
    return found
  end

  local function errors()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.ERROR then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("keeps the events after an invalid one", function()
    local found = setup_event({ 'NotAnEvent', 'InsertEnter', 'BufRead' })
    assert.is_true(found['InsertEnter *'])
    assert.is_true(found['BufReadPost *'])
    assert.are.equal(1, #errors())
    assert.is_truthy(errors()[1]:find('for a:', 1, true))
  end)

  it("keeps the events beside an invalid one in an EventSpec", function()
    local found = setup_event({ { event = { 'NotAnEvent', 'InsertEnter' }, pattern = '*.lua' } })
    assert.is_true(found['InsertEnter *.lua'])
    assert.are.equal(1, #errors())
  end)

  it("keeps the events beside a non-string in an EventSpec", function()
    local found = setup_event({ { event = 123 }, 'InsertEnter' })
    assert.is_true(found['InsertEnter *'])
    assert.are.equal(1, #errors())
  end)

  it("reads an inline pattern in a nested list", function()
    local found = setup_event({ { 'BufEnter *.lua', 'BufRead' }, 'InsertEnter' })
    assert.is_true(found['BufEnter *.lua'])
    assert.is_true(found['BufReadPost *'])
    assert.is_true(found['InsertEnter *'])
    assert.are.same({}, errors())
  end)

  it("reads an EventSpec in a nested list", function()
    local found = setup_event({ { { event = 'BufRead', pattern = '*.lua' } } })
    assert.is_true(found['BufReadPost *.lua'])
  end)

  it("loads a plugin once when several of its events fire", function()
    local loads = 0
    require('zpack').setup({
      spec = { {
        'test/a',
        event = { { event = { 'User', 'BufRead' }, pattern = 'ZpackOnce' } },
        config = function() loads = loads + 1 end,
      } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    vim.api.nvim_exec_autocmds('User', { pattern = 'ZpackOnce' })
    vim.api.nvim_exec_autocmds('BufRead', { pattern = 'ZpackOnce' })
    helpers.flush_pending()
    assert.are.equal(1, loads)
  end)
end)

describe("a trigger nothing can fire", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function is_lazy(fields)
    require('zpack').setup({
      spec = { vim.tbl_extend('force', { 'test/a' }, fields) },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    return require('zpack.state').spec_registry['https://github.com/test/a'].is_lazy_resolved
  end

  for label, fields in pairs({
    ['a function returning a number as cmd'] = { cmd = function() return 123 end },
    ['a number as cmd'] = { cmd = 123 },
    ['a list of numbers as cmd'] = { cmd = { 123 } },
    ['a number as keys'] = { keys = 123 },
    ['a key with no modes'] = { keys = { { 'a', mode = {} } } },
    ['a key with no lhs'] = { keys = { { mode = 'n' } } },
    ['a list of numbers as event'] = { event = { 123 } },
    ['an empty entry in event'] = { event = { {} } },
    ['an event table without an event'] = { event = { pattern = '*.lua' } },
    ['a list of numbers as ft'] = { ft = { 123 } },
  }) do
    it(("leaves the plugin eager: %s"):format(label), function()
      assert.is_false(is_lazy(fields))
    end)
  end

  for label, fields in pairs({
    ['a nested event list'] = { event = { { 'BufRead' } } },
    ['an EventSpec'] = { event = { event = 'BufRead', pattern = '*.lua' } },
    ['a list with an EventSpec'] = { event = { { event = { 'BufRead' } } } },
    ['a list of commands'] = { cmd = { 'Foo' } },
    ['a filetype'] = { ft = 'lua' },
    ['a string key'] = { keys = 'a' },
    ['a key with an rhs'] = { keys = { { 'a', 'b' } } },
    ['a usable entry beside a bad one'] = { cmd = { 123, 'Foo' } },
  }) do
    it(("keeps the plugin lazy: %s"):format(label), function()
      assert.is_true(is_lazy(fields))
    end)
  end

  it("still registers a filetype listed beside a bad one", function()
    assert.is_true(is_lazy({ ft = { 123, 'zpackgood' } }))
    local state = require('zpack.state')
    assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = state.lazy_group, event = 'FileType', pattern = 'zpackgood' }))
  end)
end)

describe("an rhs ending in <CR> in a two-string key", function()
  local util = require('zpack.utils')

  it("is one key", function()
    assert.are.same({ { '<leader>a', '<Esc>:w<CR>' } }, util.normalize_keys({ '<leader>a', '<Esc>:w<CR>' }))
    assert.are.same({ { '<leader>a', 'ifoo<cr>' } }, util.normalize_keys({ '<leader>a', 'ifoo<cr>' }))
  end)

  it("leaves other two-string lists as two keys", function()
    assert.are.same({ { '<leader>a' }, { 'dd' } }, util.normalize_keys({ '<leader>a', 'dd' }))
    assert.are.same({ { 'a<CR>' }, { 'b' } }, util.normalize_keys({ 'a<CR>', 'b' }))
  end)
end)

describe("a spec with both a source and an import", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local GH = 'https://github.com/'

  local function setup_spec(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state').spec_registry
  end

  it("runs a function-form enabled once", function()
    local calls = 0
    local registry = setup_spec({
      { 'test/x', import = function() return { { 'test/y' } } end, enabled = function() calls = calls + 1 return true end },
    })
    assert.are.equal(1, calls)
    assert.is_not_nil(registry[GH .. 'test/x'])
    assert.is_not_nil(registry[GH .. 'test/y'])
  end)

  it("decides the plugin and the import with one enabled result", function()
    local calls = 0
    local registry = setup_spec({
      {
        'test/x',
        import = function() return { { 'test/y' } } end,
        enabled = function() calls = calls + 1 return calls > 1 end,
      },
    })
    assert.is_nil(registry[GH .. 'test/x'])
    assert.is_nil(registry[GH .. 'test/y'])
  end)

  it("gives a function-form cond the plugin's name and source at the import", function()
    local seen = {}
    local registry = setup_spec({
      {
        'test/x',
        import = function() return { { 'test/y' } } end,
        cond = function(plugin)
          seen[#seen + 1] = plugin
          return plugin.name == 'x'
        end,
      },
    })
    assert.is_not_nil(registry[GH .. 'test/y'])
    assert.are.equal('x', seen[1].name)
    assert.are.equal('x', seen[1].spec.name)
    assert.are.equal(GH .. 'test/x', seen[1].spec.src)
    for _, n in ipairs(_G.test_state.notifications) do
      assert.is_true(n.level < vim.log.levels.ERROR, n.msg)
    end
  end)
end)

describe("a name with dev = true and no other source", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup_dev(spec, dev)
    local path = vim.fn.tempname()
    vim.fn.mkdir(path .. '/foo', 'p')
    require('zpack').setup({
      dev = vim.tbl_extend('force', { path = path }, dev or {}),
      spec = spec,
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    return require('zpack.state').spec_registry[path .. '/foo'], path
  end

  local function warnings()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("is a plugin under dependencies", function()
    local entry = setup_dev({ { 'test/p', dependencies = { { name = 'foo', dev = true } } } })
    assert.is_not_nil(entry)
    assert.are.same({}, warnings())
  end)

  it("is a plugin as the whole dependencies value", function()
    assert.is_not_nil((setup_dev({ { 'test/p', dependencies = { name = 'foo', dev = true } } })))
    assert.are.same({}, warnings())
  end)

  it("is a plugin under specs", function()
    assert.is_not_nil((setup_dev({ { 'test/p', specs = { name = 'foo', dev = true } } })))
    assert.are.same({}, warnings())
  end)

  it("is a plugin at the top level, without a missing-source warning", function()
    assert.is_not_nil((setup_dev({ { name = 'foo', dev = true } })))
    assert.are.same({}, warnings())
  end)

  it("warns when the checkout is missing and dev.fallback leaves it no source", function()
    setup_dev({ { name = 'gone', dev = true } }, { fallback = true })
    assert.are.equal(1, #warnings())
    assert.is_truthy(warnings()[1]:find('gone', 1, true))
  end)
end)

describe("a bad spec listed in several places", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function invalid_warnings()
    local count = 0
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find('invalid spec', 1, true) then
        count = count + 1
      end
    end
    return count
  end

  local function setup_spec(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
  end

  it("warns once when it has a source", function()
    local shared = { 'test/s', event = 123 }
    setup_spec({ shared, { 'test/p', dependencies = { shared } } })
    assert.are.equal(1, invalid_warnings())
  end)

  it("warns once when it has none", function()
    local shared = { opts = {} }
    setup_spec({ { 'test/a', specs = { shared } }, { 'test/b', specs = { shared } } })
    assert.are.equal(1, invalid_warnings())
  end)

  it("warns once when an import under several parents returns it", function()
    local shared = { 'test/s', event = 123 }
    local import = function() return { shared } end
    setup_spec({ { 'test/a', specs = { { import = import } } }, { 'test/b', specs = { { import = import } } } })
    assert.are.equal(1, invalid_warnings())
  end)
end)

describe("enabled and cond across specs", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local GH = 'https://github.com/'

  local function setup_spec(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state')
  end

  it("let a later spec re-enable a plugin", function()
    local state = setup_spec({ { 'u/x', enabled = false }, { 'u/x', enabled = true } })
    assert.is_not_nil(state.spec_registry[GH .. 'u/x'])
  end)

  it("let a top-level spec re-enable what a spec under dependencies disabled", function()
    local state = setup_spec({
      { 'u/p', dependencies = { { 'u/d', enabled = false } } },
      { 'u/d', enabled = true },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'u/p'])
    assert.is_not_nil(state.spec_registry[GH .. 'u/d'])
  end)

  it("give a top-level spec the last word over a later spec under dependencies", function()
    local state = setup_spec({
      { 'u/d', enabled = true },
      { 'u/p', dependencies = { { 'u/d', enabled = false } } },
    })
    assert.is_not_nil(state.spec_registry[GH .. 'u/d'])
  end)

  it("fall back to the earlier enabled when the deciding spec is dropped", function()
    local state = setup_spec({
      { 'u/x', enabled = false },
      { 'u/gone', enabled = false, specs = { { 'u/x', enabled = true } } },
    })
    assert.is_nil(state.spec_registry[GH .. 'u/x'])
  end)

  it("let a later cond load a plugin an earlier cond would not", function()
    local state = setup_spec({ { 'u/x', cond = false }, { 'u/x', cond = true } })
    assert.is_true(state.spec_registry[GH .. 'u/x'].cond_result)
  end)

  it("let a later cond stop a plugin an earlier cond would load", function()
    local state = setup_spec({ { 'u/x', cond = true }, { 'u/x', cond = false } })
    assert.is_false(state.spec_registry[GH .. 'u/x'].cond_result)
  end)

  it("run only the deciding cond function", function()
    local earlier = 0
    setup_spec({
      { 'u/x', cond = function() earlier = earlier + 1; return false end },
      { 'u/x', cond = function() return true end },
    })
    assert.are.equal(0, earlier)
  end)
end)

describe("an event that doesn't exist", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup_a(fields)
    require('zpack').setup({
      spec = { vim.tbl_extend('force', { 'test/a' }, fields) },
      defaults = { confirm = false },
    })
    helpers.flush_pending()
    return require('zpack.state').spec_registry['https://github.com/test/a']
  end

  local function warnings()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level == vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  for label, event in pairs({
    ['alone'] = 'LazyFile',
    ['in a list'] = { 'LazyFile', 'AlsoNotAnEvent' },
    ['in an EventSpec'] = { event = 'LazyFile', pattern = '*.lua' },
    ['with an inline pattern'] = 'LazyFile *.lua',
  }) do
    it(("leaves the plugin eager, with a warning naming it: %s"):format(label), function()
      local entry = setup_a({ event = event })
      assert.is_false(entry.is_lazy_resolved)
      assert.are.equal('loaded', entry.load_status)
      assert.are.equal(1, #warnings())
      assert.is_truthy(warnings()[1]:find('LazyFile', 1, true))
    end)
  end

  for label, event in pairs({
    ['beside a real one'] = { 'LazyFile', 'InsertEnter' },
    ['beside VeryLazy'] = { 'LazyFile', 'VeryLazy' },
  }) do
    it(("keeps the plugin lazy: %s"):format(label), function()
      assert.is_true(setup_a({ event = event }).is_lazy_resolved)
    end)
  end

  it("keeps the plugin lazy beside another trigger", function()
    assert.is_true(setup_a({ event = 'LazyFile', cmd = 'ZpackA' }).is_lazy_resolved)
    pcall(vim.api.nvim_del_user_command, 'ZpackA')
  end)

  it("is reported even when the plugin is set to lazy = false", function()
    setup_a({ event = 'LazyFile', lazy = false })
    assert.are.equal(1, #warnings())
  end)

  for _, event in ipairs({ 'VeryLazy', 'User ZpackReady', 'bufread', 'BufEnter *.lua' }) do
    it(("doesn't count %s"):format(event), function()
      local entry = setup_a({ event = event })
      assert.is_true(entry.is_lazy_resolved)
      assert.are.same({}, warnings())
    end)
  end
end)

describe("an import that finds nothing", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function warnings(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("warns, naming the module", function()
    local found = warnings({ { import = 'zpack_no_such_module' } })
    assert.are.equal(1, #found)
    assert.is_truthy(found[1]:find('no specs found for import "zpack_no_such_module"', 1, true))
  end)

  it("warns for a plugin's own module, which isn't searched", function()
    local found = warnings({ { 'test/distro', import = 'zpack_no_such_module' } })
    assert.are.equal(1, #found)
  end)

  it("warns once when listed under several parents", function()
    local import = { import = 'zpack_no_such_module' }
    local found = warnings({ { 'test/a', specs = { import } }, { 'test/b', specs = { import } }, { import = 'zpack_no_such_module' } })
    assert.are.equal(1, #found)
  end)

  it("stays quiet when enabled = false skips it", function()
    assert.are.same({}, warnings({ { import = 'zpack_no_such_module', enabled = false } }))
  end)
end)

describe("the invalid spec warning", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function warning(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    for _, n in ipairs(_G.test_state.notifications) do
      if n.msg:find('invalid spec', 1, true) then
        return n.msg
      end
    end
  end

  it("names the plugin a bad entry sits under", function()
    assert.is_truthy(warning({ { 'test/p', dependencies = { 123 } } }):find('under "test/p"', 1, true))
  end)

  it("shows a spec that has nothing to name it by", function()
    assert.is_truthy(warning({ { 'test/p', dependencies = { { opts = { a = 1 } } } } }):find('a = 1', 1, true))
  end)

  it("names no parent at the top level", function()
    assert.is_nil(warning({ { opts = {} } }):find('under', 1, true))
  end)
end)

describe("the third xhigh review of the parity follow-up", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  local function setup(spec, extra)
    require('zpack').setup(vim.tbl_extend('force', { spec = spec, defaults = { confirm = false } }, extra or {}))
    helpers.flush_pending()
    return require('zpack.state')
  end

  local function warnings()
    local found = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level >= vim.log.levels.WARN then
        found[#found + 1] = n.msg
      end
    end
    return found
  end

  it("keeps a plugin lazy on a key with the empty map-mode", function()
    local state = setup({
      { 'u/a', keys = { { '<leader>a', '<cmd>A<cr>', mode = '' } } },
      { 'u/b', keys = { { '<leader>b', '<cmd>B<cr>', mode = { '' } } } },
    })
    assert.is_true(state.spec_registry['https://github.com/u/a'].is_lazy_resolved)
    assert.is_true(state.spec_registry['https://github.com/u/b'].is_lazy_resolved)
  end)

  it("reads two strings ending in a lone <CR> as two keys, in either order", function()
    local util = require('zpack.utils')
    assert.are.same({ { '<Tab>' }, { '<CR>' } }, util.normalize_keys({ '<Tab>', '<CR>' }))
    assert.are.same({ { '<CR>' }, { '<Tab>' } }, util.normalize_keys({ '<CR>', '<Tab>' }))
    assert.are.same({ { '<Tab>' }, { '<C-x><CR>' } }, util.normalize_keys({ '<Tab>', '<C-x><CR>' }))
    assert.are.same({ { '<leader>a', 'ifoo<CR>' } }, util.normalize_keys({ '<leader>a', 'ifoo<CR>' }))
  end)

  it("joins a dev name to the plugin of that name when dev.fallback finds no checkout", function()
    local state = setup({ { 'u/foo', lazy = true }, { name = 'foo', dev = true, opts = { a = 1 } } },
      { dev = { path = vim.fn.tempname(), fallback = true } })
    local entry = state.spec_registry['https://github.com/u/foo']
    assert.is_not_nil(entry)
    assert.is_true(entry.has_opts)
    assert.are.same({}, warnings())
  end)

  it("leaves a plugin eager on a comma list of events, with a warning", function()
    local state = setup({ { 'u/a', event = 'BufRead,BufNewFile' } })
    assert.is_false(state.spec_registry['https://github.com/u/a'].is_lazy_resolved)
    assert.are.equal(1, #warnings())
    assert.is_truthy(warnings()[1]:find('BufRead,BufNewFile', 1, true))
  end)

  it("leaves a plugin eager on an event whose pattern can't be used", function()
    local state = setup({ { 'u/a', event = 'BufRead', pattern = 123 } })
    assert.is_false(state.spec_registry['https://github.com/u/a'].is_lazy_resolved)
  end)

  it("leaves a plugin eager on a command name nvim rejects, with a warning", function()
    local state = setup({ { 'u/a', cmd = 'foo' } })
    assert.is_false(state.spec_registry['https://github.com/u/a'].is_lazy_resolved)
    local found = warnings()
    assert.is_truthy(found[#found]:find('invalid command name: foo', 1, true))
  end)

  it("stays lazy when one command name in a list is usable", function()
    local state = setup({ { 'u/a', cmd = { 'foo', 'Bar' } } })
    assert.is_true(state.spec_registry['https://github.com/u/a'].is_lazy_resolved)
  end)

  it("keeps what an undefined bare name declares", function()
    local state = setup({
      { 'telescope.nvim', dependencies = { 'u/ext' } },
      { 'foo', specs = { { 'u/e' } } },
    })
    assert.is_nil(state.spec_registry['https://github.com/telescope.nvim'])
    assert.is_not_nil(state.spec_registry['https://github.com/u/ext'])
    assert.is_not_nil(state.spec_registry['https://github.com/u/e'])
    assert.is_not_nil(_G.test_state.registered_pack_specs['ext'])
    assert.are.equal(2, #warnings())
  end)

  it("still drops what an optional or disabled parent declares", function()
    local state = setup({
      { 'u/p', optional = true, dependencies = { 'u/under-optional' } },
      { 'u/q', enabled = false, dependencies = { 'u/under-disabled' } },
    })
    assert.is_nil(state.spec_registry['https://github.com/u/under-optional'])
    assert.is_nil(state.spec_registry['https://github.com/u/under-disabled'])
  end)

  it("survives a non-string name or sem_version", function()
    local state = setup({
      { 'u/a', name = 123 },
      { 'u/b', name = {} },
      { 'u/c', sem_version = 123 },
      { 'u/d', sem_version = {} },
      { 'u/after' },
    })
    assert.is_not_nil(state.spec_registry['https://github.com/u/after'].plugin)
    assert.is_not_nil(_G.test_state.registered_pack_specs['a'])
  end)

  it("accepts init = false", function()
    assert.are.same({}, require('zpack.validate').validate_spec({ 'u/a', init = false }))
    assert.are.equal(1, #require('zpack.validate').validate_spec({ 'u/a', init = true }))
  end)

  it("labels a spec with a string, whatever its fields hold", function()
    local label = require('zpack.validate').spec_label
    assert.are.equal('string', type(label({ { 'x' }, opts = {} })))
    assert.are.equal('string', type(label({ import = function() end, enabled = 123 })))
    assert.are.equal('u/a', label({ 'u/a' }))
    assert.are.equal('foo', label({ { 'x' }, name = 'foo' }))
  end)

  it("doesn't warn about a dependency turned off elsewhere", function()
    setup({ { 'u/p', dependencies = { 'u/x' } }, { 'u/x', enabled = false } })
    assert.are.same({}, warnings())
    local noted = false
    for _, n in ipairs(_G.test_state.notifications) do
      noted = noted or (n.level == vim.log.levels.DEBUG and n.msg:find('may not work', 1, true) ~= nil)
    end
    assert.is_true(noted)
  end)

  describe("zpack_nvim-8cy", function()
    it("sets up lazy triggers in a session that installs a plugin", function()
      local add = vim.pack.add
      vim.pack.add = function(packs, opts)
        for _, pack_spec in ipairs(packs) do
          require('zpack.state').src_with_pending_build[pack_spec.src] = true
        end
        return add(packs, opts)
      end
      local state = setup({ { 'u/a', cmd = 'ZpackInstallSessionCmd' } })
      vim.pack.add = add
      assert.is_not_nil(vim.api.nvim_get_commands({})['ZpackInstallSessionCmd'])
      assert.are.same({}, state.src_with_pending_build)
      vim.api.nvim_del_user_command('ZpackInstallSessionCmd')
    end)
  end)

  describe("zpack_nvim-yvt", function()
    it("adds eager dependencies last, which sources them first", function()
      setup({ { 'u/parent', dependencies = { { 'u/dep', lazy = false } } } })
      local order = {}
      for i, name in ipairs(_G.test_state.loaded_plugins) do
        order[name] = i
      end
      assert.is_true(order.parent < order.dep)
    end)
  end)

  describe("zpack_nvim-dso", function()
    it("keeps a shared spec's import whichever listing comes first", function()
      local function fn() return { { 'm/kept' } } end
      local s = { 'u/x', import = fn }
      local state = setup({ { 'u/p', enabled = false, dependencies = { s } }, s })
      assert.is_not_nil(state.spec_registry['https://github.com/m/kept'])
    end)
  end)

  describe("zpack_nvim-nvx", function()
    it("walks a nested list with a named field", function()
      local state = setup({ { { 'c/d' }, { 'e/f' }, foo = 1 } })
      assert.is_not_nil(state.spec_registry['https://github.com/c/d'])
      assert.is_not_nil(state.spec_registry['https://github.com/e/f'])
      assert.are.same({}, warnings())
    end)

    it("still reports one nested entry beside a field as a bad spec", function()
      setup({ { { 'x/y' }, opts = {} } })
      assert.are.equal(1, #warnings())
    end)
  end)

  describe("zpack_nvim-na9", function()
    local root, saved_path

    local function write(path, content)
      vim.fn.mkdir(vim.fs.dirname(path), 'p')
      local f = assert(io.open(path, 'w'))
      f:write(content)
      f:close()
    end

    before_each(function()
      root = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/zpackdist'
      saved_path = package.path
      write(root .. '/lua/zpackdist/plugins.lua', "return { { 'dist/core' } }")
      write(root .. '/lua/zpackdist/extras/one.lua', "return { { 'dist/extra' } }")
    end)

    after_each(function()
      vim.fn.delete(root, 'rf')
      package.path = saved_path
      package.loaded['zpackdist.plugins'] = nil
      package.loaded['zpackdist.extras.one'] = nil
    end)

    it("imports a plugin's own modules, then later imports from it", function()
      local state = setup({
        { 'u/zpackdist', import = 'zpackdist.plugins' },
        { import = 'zpackdist.extras.one' },
      })
      assert.is_not_nil(state.spec_registry['https://github.com/u/zpackdist'].plugin)
      assert.is_not_nil(state.spec_registry['https://github.com/dist/core'])
      assert.is_not_nil(state.spec_registry['https://github.com/dist/extra'])
      assert.are.same({}, warnings())
    end)

    it("registers the plugin when vim.pack skips an active plugin's load callback", function()
      local add = vim.pack.add
      local active = {}
      vim.pack.add = function(packs, opts)
        local fresh = {}
        for _, pack_spec in ipairs(packs) do
          if not active[pack_spec.name] then
            active[pack_spec.name] = true
            fresh[#fresh + 1] = pack_spec
          end
        end
        return add(fresh, opts)
      end
      local state = setup({ { 'u/zpackdist', import = 'zpackdist.plugins' } })
      vim.pack.add = add
      local entry = state.spec_registry['https://github.com/u/zpackdist']
      assert.is_not_nil(entry.plugin)
      assert.are.equal('zpackdist', entry.plugin.name)
    end)

    it("doesn't add a plugin early for an import the config has", function()
      local calls = #_G.test_state.vim_pack_calls
      setup({ { 'u/other', import = 'zpack.does.not.exist.anywhere' } })
      assert.is_true(#_G.test_state.vim_pack_calls - calls <= 2)
      assert.is_truthy(table.concat(warnings(), '\n'):find('no specs found', 1, true))
    end)

    it("never adds a bare name early, since it has no real source", function()
      setup({ { 'zpackdist', import = 'zpackdist.plugins' } })
      for _, call in ipairs(_G.test_state.vim_pack_calls) do
        for _, pack_spec in ipairs(call) do
          assert.are_not.equal('https://github.com/zpackdist', pack_spec.src)
        end
      end
    end)
  end)
end)

describe("the fourth xhigh review of the parity follow-up", function()
  local GH = 'https://github.com/'
  local root, saved_path, modules

  before_each(function()
    helpers.setup_test_env()
    root = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/zd'
    saved_path = package.path
    modules = {}
  end)

  after_each(function()
    vim.fn.delete(root, 'rf')
    package.path = saved_path
    for _, name in ipairs(modules) do
      package.loaded[name] = nil
    end
    helpers.cleanup_test_env()
  end)

  local function write(base, module, content)
    local path = base .. '/lua/' .. module:gsub('%.', '/') .. '.lua'
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    local f = assert(io.open(path, 'w'))
    f:write(content)
    f:close()
    modules[#modules + 1] = (module:gsub('%.init$', ''))
    modules[#modules + 1] = module
  end

  local function setup(spec)
    require('zpack').setup({ spec = spec, defaults = { confirm = false } })
    helpers.flush_pending()
    return require('zpack.state')
  end

  local function warnings()
    local out = {}
    for _, n in ipairs(_G.test_state.notifications) do
      if n.level == vim.log.levels.WARN or n.level == vim.log.levels.ERROR then
        out[#out + 1] = n.msg
      end
    end
    return out
  end

  local function added(name)
    local found = {}
    for _, call in ipairs(_G.test_state.vim_pack_calls) do
      for _, pack_spec in ipairs(call) do
        if pack_spec.name == name then
          found[#found + 1] = pack_spec
        end
      end
    end
    return found
  end

  describe("importing from a plugin", function()
    before_each(function()
      write(root, 'zd.plugins', "return { { 'dist/core' } }")
    end)

    it("installs a plugin with what its other specs say", function()
      local range = vim.version.range('1.*')
      local state = setup({
        { 'u/zd', import = 'zd.plugins' },
        { 'u/zd', url = 'https://example.com/fork/zd', version = range },
      })
      local first = added('zd')[1]
      assert.are.equal('https://example.com/fork/zd', first.src)
      assert.are.equal(range, first.version)
      assert.is_not_nil(state.spec_registry['https://example.com/fork/zd'].plugin)
      assert.is_not_nil(state.spec_registry[GH .. 'dist/core'])
    end)

    it("installs it under the name another spec gives it", function()
      local renamed = vim.fn.stdpath('data') .. '/site/pack/zpack/opt/zd2'
      write(renamed, 'zd2.plugins', "return { { 'dist/two' } }")
      local state = setup({
        { 'u/zd', import = 'zd2.plugins' },
        { 'u/zd', name = 'zd2' },
      })
      vim.fn.delete(renamed, 'rf')
      assert.are.same({}, added('zd'))
      assert.is_not_nil(state.spec_registry[GH .. 'dist/two'])
    end)

    it("doesn't install a plugin under a disabled parent", function()
      local state = setup({ { 'u/p', enabled = false, dependencies = { { 'u/zd', import = 'zd.plugins' } } } })
      assert.are.same({}, added('zd'))
      assert.is_nil(state.spec_registry[GH .. 'dist/core'])
      assert.are.same({}, warnings())
    end)

    it("doesn't install a plugin another spec disables", function()
      setup({ { 'u/zd', import = 'zd.plugins' }, { 'u/zd', enabled = false } })
      assert.are.same({}, added('zd'))
      assert.are.same({}, warnings())
    end)

    it("reads an installed plugin without adding it early", function()
      local installed = vim.fn.stdpath('data') .. '/site/pack/core/opt/zdisk'
      write(installed, 'zdisk.plugins', "return { { 'dist/disk' } }")
      local state = setup({ { 'u/zdisk', import = 'zdisk.plugins' }, { 'u/zdisk', version = 'v1' } })
      vim.fn.delete(installed, 'rf')
      assert.are.equal(1, #_G.test_state.vim_pack_calls)
      assert.are.equal('v1', added('zdisk')[1].version)
      assert.is_not_nil(state.spec_registry[GH .. 'dist/disk'])
    end)

    it("keeps the order of the specs after an install", function()
      write(root, 'zd.order', "return { { 'dist/o', enabled = false } }")
      local state = setup({ { 'u/zd', import = 'zd.order' }, { 'dist/o', enabled = true } })
      assert.is_not_nil(state.spec_registry[GH .. 'dist/o'])
    end)

    it("reports and evaluates a spec once across the passes", function()
      local calls, runs = 0, 0
      local state = setup({
        { 'u/zd', import = 'zd.plugins' },
        { 'u/x', enabled = function() calls = calls + 1; return true end, opts = 1 },
        { import = function() runs = runs + 1; return { { 'u/fn' } } end },
        { import = 'zpack.nothing.here' },
      })
      assert.are.equal(1, calls)
      assert.are.equal(1, runs)
      assert.is_not_nil(state.spec_registry[GH .. 'u/fn'])
      local missing, invalid = 0, 0
      for _, msg in ipairs(warnings()) do
        missing = missing + (msg:find('no specs found', 1, true) and 1 or 0)
        invalid = invalid + (msg:find('invalid spec', 1, true) and 1 or 0)
      end
      assert.are.equal(1, missing)
      assert.are.equal(1, invalid)
    end)

    it("finds a later import an earlier one needed the install for", function()
      write(root, 'zd.early', "return { { 'dist/early' } }")
      local state = setup({ { import = 'zd.early' }, { 'u/zd', import = 'zd.plugins' } })
      assert.is_not_nil(state.spec_registry[GH .. 'dist/early'])
      assert.are.same({}, warnings())
    end)

    it("gives cond the path the plugin installs to", function()
      local seen
      setup({ { 'u/zd', import = 'zd.plugins', cond = function(p)
        seen = seen or p.path
        return vim.uv.fs_stat(p.path .. '/nope') == nil
      end } })
      assert.are.equal(vim.fn.stdpath('data') .. '/site/pack/core/opt/zd', seen)
      assert.are.same({}, warnings())
    end)

    it("imports by module name, with init.lua as the module itself", function()
      write(root, 'zd.sorted.a-b', "vim.g.zd_order = (vim.g.zd_order or '') .. 'a-b ' return {}")
      write(root, 'zd.sorted.a', "vim.g.zd_order = (vim.g.zd_order or '') .. 'a ' return {}")
      write(root, 'zd.sorted.init', "vim.g.zd_order = (vim.g.zd_order or '') .. 'init ' return {}")
      vim.g.zd_order = nil
      setup({ { 'u/zd', import = 'zd.sorted' } })
      assert.are.equal('init a a-b ', vim.g.zd_order)
      assert.is_nil(package.loaded['zd.sorted.init'])
      assert.is_not_nil(package.loaded['zd.sorted'])
      vim.g.zd_order = nil
    end)
  end)

  it("sets up no trigger for a lazy plugin a pending build loaded", function()
    local add = vim.pack.add
    vim.pack.add = function(packs, opts)
      for _, pack_spec in ipairs(packs) do
        if pack_spec.name == 'b' then
          require('zpack.state').src_with_pending_build[pack_spec.src] = true
        end
      end
      return add(packs, opts)
    end
    local state = setup({
      { 'u/b', cmd = 'ZpackBuildProxy', build = function() end, dependencies = { { 'u/d', cmd = 'ZpackBuildDep' } } },
      { 'u/other', cmd = 'ZpackOtherProxy' },
    })
    vim.pack.add = add
    local commands = vim.api.nvim_get_commands({})
    assert.is_nil(commands.ZpackBuildProxy)
    assert.is_nil(commands.ZpackBuildDep)
    assert.are.equal('loaded', state.spec_registry[GH .. 'u/b'].load_status)
    assert.is_not_nil(commands.ZpackOtherProxy)
    vim.api.nvim_del_user_command('ZpackOtherProxy')
  end)

  it("finishes optional drops before a reference promotes what it declares", function()
    local spec = {}
    for i = 1, 30 do
      spec[i] = {
        'u/p' .. i,
        optional = true,
        dependencies = { { 'foo' .. i, dependencies = { 'u/c' .. i } } },
      }
    end
    local state = setup(spec)
    for i = 1, 30 do
      assert.is_nil(state.spec_registry[GH .. 'u/c' .. i])
    end
  end)

  describe("debug notes", function()
    local verbose

    before_each(function()
      verbose = vim.o.verbose
    end)

    after_each(function()
      vim.o.verbose = verbose
    end)

    local function notes()
      local count = 0
      for _, n in ipairs(_G.test_state.notifications) do
        count = count + (n.level == vim.log.levels.DEBUG and 1 or 0)
      end
      return count
    end

    it("wait for 'verbose'", function()
      vim.o.verbose = 0
      setup({ { 'u/p', dependencies = { 'u/x' } }, { 'u/x', enabled = false }, { 'u/o', optional = true } })
      assert.are.equal(0, notes())
    end)

    it("come out with 'verbose'", function()
      vim.o.verbose = 1
      setup({ { 'u/p', dependencies = { 'u/x' } }, { 'u/x', enabled = false }, { 'u/o', optional = true } })
      assert.are.equal(2, notes())
    end)
  end)

  describe("load order", function()
    local log

    before_each(function()
      log = {}
      vim.cmd.packadd = function(args)
        log[#log + 1] = args[1] .. (args.bang and '!' or '')
      end
    end)

    it("sources a lazy plugin after its dependencies, with it on 'runtimepath' first", function()
      local state = setup({ { 'u/parent', cmd = 'ZpackPp', dependencies = { 'u/dep' } } })
      log = {}
      require('zpack.plugin_loader').process_spec(state.src_to_pack_spec[GH .. 'u/parent'])
      assert.are.same({ 'parent!', 'dep', 'parent' }, log)
      pcall(vim.api.nvim_del_user_command, 'ZpackPp')
    end)

    it("adds a lazy plugin without dependencies once", function()
      local state = setup({ { 'u/solo', cmd = 'ZpackSolo' } })
      log = {}
      require('zpack.plugin_loader').process_spec(state.src_to_pack_spec[GH .. 'u/solo'])
      assert.are.same({ 'solo' }, log)
      pcall(vim.api.nvim_del_user_command, 'ZpackSolo')
    end)

    it("loads dependencies in the order they're listed", function()
      local deps = {}
      local expected = {}
      for i = 1, 12 do
        deps[i] = 'u/d' .. i
        expected[i] = GH .. 'u/d' .. i
      end
      setup({ { 'u/d3' }, { 'u/p', dependencies = deps } })
      assert.are.same(expected, require('zpack.utils').sorted_dependencies(GH .. 'u/p'))
    end)

    it("sources eager plugins dependency first when setup() runs after startup", function()
      vim.v = setmetatable({ vim_did_init = 1 }, { __index = _G.test_state.original_vim_v })
      setup({ { 'u/parent', dependencies = { { 'u/dep', lazy = false } } } })
      assert.are.same({ 'dep', 'parent' }, log)
    end)
  end)

  it("keeps going when vim.pack can't add a plugin", function()
    local add = vim.pack.add
    vim.pack.add = function(packs, opts)
      local good = vim.tbl_filter(function(p) return p.name ~= 'bad' end, packs)
      add(good, opts)
      error('vim.pack:\n\n`bad`:\nclone failed')
    end
    local configured = false
    local state = setup({
      { 'u/bad', cmd = 'ZpackBadCmd' },
      { 'u/good', dependencies = { 'u/bad' }, config = function() configured = true end },
    })
    vim.pack.add = add
    assert.is_true(configured)
    assert.is_nil(state.spec_registry[GH .. 'u/bad'])
    assert.is_nil(vim.api.nvim_get_commands({}).ZpackBadCmd)
    assert.is_not_nil(vim.api.nvim_get_commands({}).ZPack)
    assert.is_truthy(table.concat(warnings(), '\n'):find('clone failed', 1, true))
    pcall(vim.api.nvim_del_user_command, 'ZPack')
  end)

  it("reads a version git can't take as a ref as a semver range", function()
    local utils = require('zpack.utils')
    for _, version in ipairs({ '*', '1.*', 'v2.*', '^1.0', '~1.2', '>=1.0' }) do
      assert.are.equal('table', type(utils.normalize_version({ version = version })), version)
    end
    for _, version in ipairs({ 'main', 'v1', '1.x', '0.1.x', '1.0.0', 'release/1' }) do
      assert.are.equal(version, utils.normalize_version({ version = version }))
    end
  end)

  it("reads defaults.version the same way", function()
    setup({ { 'u/a' } })
    require('zpack.state').config.defaults.version = '*'
    assert.are.equal('table', type(require('zpack.utils').normalize_version({})))
    require('zpack.state').config.defaults.version = nil
  end)
end)
