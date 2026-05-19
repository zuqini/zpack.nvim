local helpers = require('helpers')

describe("Lazy Loading - Keymaps", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("KeySpec supports string shorthand", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = '<leader>tk',
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tk' then
        found = true
        break
      end
    end
    assert.is_truthy(found, "String key should create keymap")
  end)

  it("KeySpec supports table format with desc", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>td', function() end, desc = 'Test description' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found_with_desc = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' td' and map.desc == 'Test description' then
        found_with_desc = true
        break
      end
    end
    assert.is_truthy(found_with_desc, "KeySpec should create keymap with description")
  end)

  it("KeySpec supports custom modes", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tv', function() end, mode = { 'n', 'v' } },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local normal_maps = vim.api.nvim_get_keymap('n')
    local visual_maps = vim.api.nvim_get_keymap('v')

    local found_in_normal = false
    local found_in_visual = false

    for _, map in ipairs(normal_maps) do
      if map.lhs == ' tv' then
        found_in_normal = true
        break
      end
    end

    for _, map in ipairs(visual_maps) do
      if map.lhs == ' tv' then
        found_in_visual = true
        break
      end
    end

    assert.is_truthy(found_in_normal, "KeySpec should create keymap in normal mode")
    assert.is_truthy(found_in_visual, "KeySpec should create keymap in visual mode")
  end)

  it("lazy keys plugin does not load at startup", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = '<leader>tl',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status)
  end)

  it("KeySpec forwards expr=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>te', function() return 'foo' end, expr = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' te' then
        found = true
        assert.are.equal(1, map.expr)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("KeySpec expr=true: rhs return value is fed as keys", function()
    local target_hits = 0
    vim.keymap.set('n', 'gxxq', function() target_hits = target_hits + 1 end)

    local rhs_called = 0
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            -- remap=true so the returned 'gxxq' goes through the target mapping below.
            { 'gxxe', function() rhs_called = rhs_called + 1; return 'gxxq' end, expr = true, remap = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.api.nvim_feedkeys('gxxe', 'mx', false)
    assert.are.equal(1, rhs_called)
    assert.are.equal(1, target_hits)

    pcall(vim.keymap.del, 'n', 'gxxe')
    pcall(vim.keymap.del, 'n', 'gxxq')
  end)

  it("KeySpec forwards silent=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>ts', function() end, silent = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' ts' then
        found = true
        assert.are.equal(1, map.silent)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("KeySpec forwards noremap=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>tn', function() end, noremap = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tn' then
        found = true
        assert.are.equal(1, map.noremap)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  -- vim.keymap.set ignores `noremap` and derives it from `remap`. Without the
  -- alias translation in keymap.lua, the keymap below would still come out
  -- non-remappable (noremap=1) because `remap` defaults to false.
  it("KeySpec forwards noremap=false (lazy.nvim alias for remap=true)", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>tnf', function() end, noremap = false },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tnf' then
        found = true
        assert.are.equal(0, map.noremap)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  -- Explicit `remap` should win over `noremap` when both are set.
  it("KeySpec: explicit remap takes precedence over noremap alias", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>tnp', function() end, remap = true, noremap = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tnp' then
        found = true
        assert.are.equal(0, map.noremap)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("KeySpec forwards replace_keycodes=true with expr", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>tr', function() return '<Esc>' end, expr = true, replace_keycodes = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tr' then
        found = true
        assert.are.equal(1, map.expr)
        assert.are.equal(1, map.replace_keycodes)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("Lazy proxy keymap is not expr", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tx', function() return 'foo' end, expr = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tx' then
        found = true
        assert.are.equal(0, map.expr)
        break
      end
    end
    assert.is_truthy(found, "Lazy proxy keymap should be installed")
  end)

  it("KeySpec forwards remap=true alone", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>tra', function() end, remap = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tra' then
        found = true
        assert.are.equal(0, map.noremap)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("KeySpec defaults replace_keycodes to true when expr=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>trd', function() return '<Esc>' end, expr = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' trd' then
        found = true
        assert.are.equal(1, map.expr)
        assert.are.equal(1, map.replace_keycodes)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("Lazy proxy keymap forwards nowait=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tw', function() end, nowait = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tw' then
        found = true
        assert.are.equal(1, map.nowait)
        break
      end
    end
    assert.is_truthy(found, "Lazy proxy keymap should be installed")
  end)

  it("Lazy proxy keymap forwards silent=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tsl', function() end, silent = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tsl' then
        found = true
        assert.are.equal(1, map.silent)
        break
      end
    end
    assert.is_truthy(found, "Lazy proxy keymap should be installed")
  end)

  it("KeySpec preserves explicit replace_keycodes=false override", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>tro', function() return '<Esc>' end, expr = true, replace_keycodes = false },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' tro' then
        found = true
        assert.are.equal(1, map.expr)
        assert.are.equal(0, map.replace_keycodes)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap")
  end)

  it("Lazy proxy keymap forwards remap=true", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>txr', function() end, remap = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' txr' then
        found = true
        assert.are.equal(0, map.noremap)
        break
      end
    end
    assert.is_truthy(found, "Lazy proxy keymap should be installed")
  end)

  it("Lazy proxy keymap translates noremap=false alias", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>txn', function() end, noremap = false },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' txn' then
        found = true
        assert.are.equal(0, map.noremap)
        break
      end
    end
    assert.is_truthy(found, "Lazy proxy keymap should be installed")
  end)

  -- vim.keymap.set raises if replace_keycodes is set without expr. The opts
  -- whitelist used to forward replace_keycodes unconditionally, which would
  -- crash apply_keys for a user spec like { lhs, rhs, replace_keycodes = true }.
  it("KeySpec drops replace_keycodes when expr is unset", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          lazy = false,
          keys = {
            { '<leader>trk', function() end, replace_keycodes = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local keymaps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(keymaps) do
      if map.lhs == ' trk' then
        found = true
        assert.are.equal(0, map.expr)
        assert.are.equal(0, map.replace_keycodes)
        break
      end
    end
    assert.is_truthy(found, "Eager KeySpec should create keymap without crashing")
  end)

  -- Covers the post-trigger apply_keys path (plugin_loader.lua → apply_keys),
  -- which the eager `lazy = false` tests above don't exercise. After the proxy
  -- fires and the plugin loads, the real keymap must carry the user's opts.
  it("Lazy proxy load handoff: real keymap forwards silent and noremap alias", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tlh', function() end, silent = true, noremap = false },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local function find_map(lhs)
      for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
        if map.lhs == lhs then return map end
      end
      return nil
    end

    vim.api.nvim_feedkeys(' tlh', 'mx', false)
    helpers.flush_pending()

    local real = find_map(' tlh')
    assert.is_not_nil(real, "Real keymap should exist after lazy proxy fires")
    assert.are.equal(1, real.silent)
    assert.are.equal(0, real.noremap)
  end)

  it("Lazy proxy load handoff installs the real expr keymap", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>txp', function() return '' end, expr = true },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local function find_map(lhs)
      for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
        if map.lhs == lhs then return map end
      end
      return nil
    end

    local proxy = find_map(' txp')
    assert.is_not_nil(proxy, "Proxy keymap should be installed")
    assert.are.equal(0, proxy.expr)

    vim.api.nvim_feedkeys(' txp', 'mx', false)
    helpers.flush_pending()

    local real = find_map(' txp')
    assert.is_not_nil(real, "Real keymap should exist after lazy proxy fires")
    assert.are.equal(1, real.expr)
  end)

  -- Regression for the 'i'-mode feedkeys behavior documented in keys.lua.
  it("Lazy proxy preserves typeahead order for multi-key sequences", function()
    local order = {}
    vim.keymap.set('n', 'zb', function() table.insert(order, 'b') end)

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = { { 'zi' } },
          config = function()
            vim.keymap.set('n', 'zi', function() table.insert(order, 'i') end)
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.api.nvim_feedkeys('zizb', 'mx', false)
    helpers.flush_pending()

    assert.are.equal('ib', table.concat(order))

    pcall(vim.keymap.del, 'n', 'zi')
    pcall(vim.keymap.del, 'n', 'zb')
  end)
end)
