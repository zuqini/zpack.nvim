local helpers = require('helpers')

local PLUGIN_INFO_KEYS = {
  name = true,
  src = true,
  status = true,
  lazy = true,
  path = true,
}

local function find_by_name(list, name)
  for _, info in ipairs(list) do
    if info.name == name then
      return info
    end
  end
  return nil
end

describe("Public API (zpack.get_plugins / get_plugin)", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("get_plugins returns an entry for each registered plugin", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha' },
        { 'test/beta' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local list = require('zpack').get_plugins()
    assert.is_not_nil(find_by_name(list, 'alpha'), "alpha should be in get_plugins()")
    assert.is_not_nil(find_by_name(list, 'beta'), "beta should be in get_plugins()")
  end)

  it("get_plugins entry shape has name, src, status, lazy", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = find_by_name(require('zpack').get_plugins(), 'alpha')
    assert.is_not_nil(info, "alpha should be listed")
    assert.are.equal('alpha', info.name)
    assert.are.equal('https://github.com/test/alpha', info.src)
    assert.are.equal('loaded', info.status)
    assert.are.equal(false, info.lazy)
  end)

  it("PluginInfo exposes exactly the documented key set", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha' },
        { 'test/gamma', cond = false },
        { 'test/delta', lazy = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local list = require('zpack').get_plugins()
    assert.is_truthy(#list >= 3, "all three plugins should be listed")
    for _, info in ipairs(list) do
      for k in pairs(info) do
        assert.is_truthy(
          PLUGIN_INFO_KEYS[k] == true,
          ("PluginInfo leaked undocumented key %q on %q — if this is intentional, bump zpack.api.VERSION and update PLUGIN_INFO_KEYS"):format(k, tostring(info.name))
        )
      end
      -- Every key must be present (rawget catches silent-nil regressions
      -- that `pairs` iteration would miss).
      for k in pairs(PLUGIN_INFO_KEYS) do
        assert.is_truthy(
          rawget(info, k) ~= nil,
          ("PluginInfo is missing required key %q on %q"):format(k, tostring(info.name))
        )
      end
    end
  end)

  it("enabled=false plugins are pruned and not returned", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', enabled = false },
        { 'test/beta' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local list = require('zpack').get_plugins()
    assert.is_nil(find_by_name(list, 'alpha'), "enabled=false plugin must not appear in get_plugins()")
    assert.is_not_nil(find_by_name(list, 'beta'), "beta should still be listed")
  end)

  it("enabled=false plugins do not reach vim.pack.add", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', enabled = false },
        { 'test/beta' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(_G.test_state.registered_pack_specs['alpha'], "alpha must not be installed")
    assert.is_not_nil(_G.test_state.registered_pack_specs['beta'], "beta should be installed")
  end)

  it("get_plugin returns nil for enabled=false plugins", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', enabled = false },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(require('zpack').get_plugin('alpha'), "pruned plugin must not be findable")
  end)

  it("lazy plugins report lazy=true and status=pending", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', lazy = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = find_by_name(require('zpack').get_plugins(), 'alpha')
    assert.is_not_nil(info, "lazy alpha should be listed")
    assert.are.equal(true, info.lazy)
    assert.are.equal('pending', info.status)
  end)

  it("get_plugin returns a single entry by name", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha' },
        { 'test/beta' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('beta')
    assert.is_not_nil(info, "get_plugin should find beta")
    assert.are.equal('beta', info.name)
    assert.are.equal('https://github.com/test/beta', info.src)
  end)

  it("get_plugin returns nil for unknown name", function()
    require('zpack').setup({
      spec = { { 'test/alpha' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(require('zpack').get_plugin('does-not-exist'), "unknown name should return nil")
    assert.is_nil(require('zpack').get_plugin(''), "empty name should return nil")
  end)

  it("cond=false reports status=disabled", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', cond = false },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('alpha')
    assert.is_not_nil(info, "cond-disabled alpha should still be listed")
    assert.are.equal('disabled', info.status)
  end)

  it("cond function returning false reports status=disabled", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', cond = function() return false end },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('alpha')
    assert.is_not_nil(info, "cond-fn-disabled alpha should still be listed")
    assert.are.equal('disabled', info.status)
  end)

  it("cond_disabled lazy plugin still reports lazy=true", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', cond = false, lazy = true },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('alpha')
    assert.is_not_nil(info, "alpha should be listed")
    assert.are.equal('disabled', info.status)
    assert.are.equal(true, info.lazy)
  end)

  it("cond_disabled event-triggered plugin reports lazy=true", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', cond = false, event = 'BufReadPost' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('alpha')
    assert.is_not_nil(info, "alpha should be listed")
    assert.are.equal(true, info.lazy)
  end)

  it("disable propagates and prunes parent + child", function()
    require('zpack').setup({
      spec = {
        { 'test/parent', dependencies = { 'test/child' } },
        { 'test/child', enabled = false },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(require('zpack').get_plugin('parent'), "parent should be pruned after dep-propagated disable")
    assert.is_nil(require('zpack').get_plugin('child'), "child should be pruned after explicit disable")
  end)

  it("dep-only plugin is pruned when its only parent is disabled", function()
    require('zpack').setup({
      spec = {
        { 'test/parent', enabled = false, dependencies = { 'test/dep' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(require('zpack').get_plugin('parent'), "disabled parent should be pruned")
    assert.is_nil(require('zpack').get_plugin('dep'), "dep-only child of disabled parent should be pruned")
    assert.is_nil(_G.test_state.registered_pack_specs['dep'], "orphaned dep must not reach vim.pack.add")
  end)

  it("dep with another live parent survives when one parent is disabled", function()
    require('zpack').setup({
      spec = {
        { 'test/keeper', dependencies = { 'test/shared' } },
        { 'test/dropper', enabled = false, dependencies = { 'test/shared' } },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_not_nil(require('zpack').get_plugin('keeper'), "keeper should survive")
    assert.is_not_nil(require('zpack').get_plugin('shared'), "shared dep should survive (still referenced by keeper)")
    assert.is_nil(require('zpack').get_plugin('dropper'), "dropper should be pruned")
  end)

  it("status reports loading while a lazy-loaded plugin's config is running", function()
    local observed_status
    require('zpack').setup({
      spec = {
        {
          'test/alpha',
          lazy = true,
          config = function()
            local info = require('zpack').get_plugin('alpha')
            observed_status = info and info.status
          end,
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Before lazy-load, alpha is pending.
    assert.are.equal('pending', require('zpack').get_plugin('alpha').status)

    pcall(vim.cmd, 'ZPack! load alpha')

    assert.are.equal('loading', observed_status)
    assert.are.equal('loaded', require('zpack').get_plugin('alpha').status)
  end)

  it("PluginInfo does not expose a rev field (install state is vim.pack's)", function()
    require('zpack').setup({
      spec = { { 'test/alpha' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('alpha')
    assert.is_not_nil(info, "alpha should exist")
    assert.is_nil(
      rawget(info, 'rev'),
      "rev was intentionally removed from PluginInfo — consumers must use vim.pack.get"
    )
  end)

  it("get_plugins surfaces entries whose load callback has not fired as installing", function()
    -- Simulate vim.pack deferring the load callback (e.g. fresh install
    -- awaiting confirmation): record the spec but don't invoke opts.load.
    vim.pack.add = function(specs, _opts)
      table.insert(_G.test_state.vim_pack_calls, specs)
      for _, pack_spec in ipairs(specs) do
        local name = pack_spec.name or pack_spec.src:match('[^/]+$')
        pack_spec.name = name
        _G.test_state.registered_pack_specs[name] = pack_spec
      end
    end

    local ok, err = pcall(function()
      require('zpack').setup({
        spec = { { 'test/alpha' } },
        defaults = { confirm = false },
      })
      helpers.flush_pending()
    end)
    assert.is_truthy(ok, "setup must not throw when load callback is deferred: " .. tostring(err))

    local info = find_by_name(require('zpack').get_plugins(), 'alpha')
    assert.is_not_nil(info, "pending-install entries must surface in get_plugins()")
    assert.are.equal('installing', info.status)
    assert.are.equal(nil, info.path)
    assert.are.equal('alpha', info.name)

    -- get_plugin() is symmetric with get_plugins(): name_to_src is populated
    -- at resolve_all time from merged_spec.name (or a derived basename), so
    -- installing entries are findable by the same name they will carry once
    -- the load callback fires.
    local looked_up = require('zpack').get_plugin('alpha')
    assert.is_not_nil(looked_up, "get_plugin must resolve installing entries")
    assert.are.equal('installing', looked_up.status)
    assert.are.equal('alpha', looked_up.name)
  end)

  it("get_plugins does not include zpack itself", function()
    _G.test_state.registered_pack_specs['zpack.nvim'] = {
      name = 'zpack.nvim',
      src = 'https://github.com/zuqini/zpack.nvim',
    }

    require('zpack').setup({
      spec = { { 'test/alpha' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local list = require('zpack').get_plugins()
    assert.is_nil(
      find_by_name(list, 'zpack.nvim'),
      "zpack.nvim should not be in the API — consumers that need it can query vim.pack.get directly"
    )
    assert.is_not_nil(find_by_name(list, 'alpha'), "user plugins should still be returned")
  end)

  it("get_plugins() is sorted by name", function()
    require('zpack').setup({
      spec = {
        { 'test/charlie' },
        { 'test/alpha' },
        { 'test/bravo' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local list = require('zpack').get_plugins()
    local names = {}
    for _, info in ipairs(list) do
      table.insert(names, info.name)
    end
    local prev = nil
    for _, name in ipairs(names) do
      if prev ~= nil then
        assert.is_truthy(prev <= name, "get_plugins() must be sorted by name")
      end
      prev = name
    end
  end)

  it("get_plugin tolerates non-string arguments", function()
    require('zpack').setup({
      spec = { { 'test/alpha' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    assert.is_nil(require('zpack').get_plugin(nil), "nil should return nil, not throw")
    assert.is_nil(require('zpack').get_plugin(42), "number should return nil, not throw")
  end)

  it("zpack.api.VERSION is exposed as an integer >= 1", function()
    require('zpack').setup({ spec = {}, defaults = { confirm = false } })
    helpers.flush_pending()

    local version = require('zpack.api').VERSION
    assert.are.equal('number', type(version))
    assert.is_truthy(version >= 1, "VERSION must be >= 1")
  end)

  it("lazy via event trigger reports lazy=true", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', event = 'BufReadPost' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local info = require('zpack').get_plugin('alpha')
    assert.is_not_nil(info, "alpha should be listed")
    assert.are.equal(true, info.lazy)
  end)

  it("lazy flag does not flip across installing → loaded lifecycle", function()
    -- First setup: defer the load callback so alpha surfaces as installing
    -- with an event-triggered spec. The lazy flag must already be true.
    vim.pack.add = function(specs, _opts)
      table.insert(_G.test_state.vim_pack_calls, specs)
      for _, pack_spec in ipairs(specs) do
        local name = pack_spec.name or pack_spec.src:match('[^/]+$')
        pack_spec.name = name
        _G.test_state.registered_pack_specs[name] = pack_spec
      end
    end

    require('zpack').setup({
      spec = { { 'test/alpha', event = 'BufReadPost' } },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local installing = require('zpack').get_plugin('alpha')
    assert.is_not_nil(installing, "installing entry must be findable")
    assert.are.equal('installing', installing.status)
    assert.are.equal(true, installing.lazy)
  end)

  it("force-loaded cond=false plugin reports loaded, not disabled", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha', cond = false },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Pre-condition: alpha is registered and reports disabled.
    assert.are.equal('disabled', require('zpack').get_plugin('alpha').status)

    -- `:ZPack! load alpha` force-loads past the cond gate (used e.g. when a
    -- consumer deliberately wants the plugin loaded despite its cond).
    pcall(vim.cmd, 'ZPack! load alpha')

    assert.are.equal('loaded', require('zpack').get_plugin('alpha').status)
  end)

  it("cond=false dep pulled in by a live parent reports loaded", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = { { 'test/helper', cond = false } },
        },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    -- Parent is eagerly loaded, which pulls helper in as a required dep.
    -- plugin_loader warns that helper has cond=false but loads it anyway,
    -- so derive_status must honor load_status over cond_result.
    local helper = require('zpack').get_plugin('helper')
    assert.is_not_nil(helper, "cond=false dep should still be registered")
    assert.are.equal('loaded', helper.status)
  end)

  it("get_plugin(info.name) round-trips every get_plugins() entry", function()
    require('zpack').setup({
      spec = {
        { 'test/alpha' },
        { 'test/beta', lazy = true },
        { 'test/gamma', cond = false },
        { 'test/delta', event = 'BufReadPost' },
      },
      defaults = { confirm = false },
    })
    helpers.flush_pending()

    local list = require('zpack').get_plugins()
    assert.is_truthy(#list >= 4, "all four plugins should be listed")
    for _, info in ipairs(list) do
      local looked_up = require('zpack').get_plugin(info.name)
      assert.is_not_nil(
        looked_up,
        ("get_plugin(%q) must round-trip get_plugins() entry"):format(info.name)
      )
      assert.are.equal(info.name, looked_up.name)
      assert.are.equal(info.src, looked_up.src)
    end
  end)
end)
