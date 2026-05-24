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
    -- Proxy is always expr=1 so operator-pending sequences like di` keep the
    -- pending operator alive across the lazy-load trigger (see issue #26).
    assert.are.equal(1, proxy.expr)

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

  -- Regression for issue #26: a non-expr Lua proxy cancelled the pending
  -- operator, so `di`` dropped into Insert and typed a literal backtick.
  it("Lazy proxy preserves operator-pending state for text objects", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = { { 'i', mode = 'o' } },
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'foo `bar` baz' })
    vim.api.nvim_win_set_cursor(0, { 1, 6 })

    vim.api.nvim_feedkeys('di`', 'mx', false)
    helpers.flush_pending()

    local mode = vim.api.nvim_get_mode().mode
    local line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]

    assert.are.equal('n', mode, "should remain in normal mode, not fall into Insert")
    assert.are.equal('foo `` baz', line, "di` should delete the text inside backticks")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Pins natural v:count preservation across the expr proxy callback. The
  -- typed count remains in effect for the re-fed lhs because expr=true with
  -- an empty return doesn't reset v:count, so the real keymap sees the
  -- original count. A future fix that explicitly re-prepends v:count to
  -- feedkeys would double it (55 instead of 5).
  it("Lazy proxy preserves v:count across first press", function()
    local captured = {}
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = { { '<leader>tc' } },
          config = function()
            vim.keymap.set('n', '<leader>tc', function()
              table.insert(captured, vim.v.count)
            end)
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.api.nvim_feedkeys('5 tc', 'mx', false)
    helpers.flush_pending()

    assert.are.equal(5, captured[1], "real keymap should see v:count = 5 on first lazy fire")

    pcall(vim.keymap.del, 'n', '<leader>tc')
  end)

  -- Pins natural v:register preservation, same as count above.
  it("Lazy proxy preserves v:register across first press", function()
    local captured = {}
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = { { '<leader>tr' } },
          config = function()
            vim.keymap.set('n', '<leader>tr', function()
              table.insert(captured, vim.v.register)
            end)
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    vim.api.nvim_feedkeys('"a tr', 'mx', false)
    helpers.flush_pending()

    assert.are.equal('a', captured[1], "real keymap should see v:register = 'a' on first lazy fire")

    pcall(vim.keymap.del, 'n', '<leader>tr')
  end)

  -- Pins natural count-between-operator-and-motion preservation. d3<lhs>
  -- must apply count 3 to the lazy text-object — the expr proxy + <Ignore>
  -- bridge must not eat it.
  it("Lazy proxy preserves v:count between operator and motion", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = { { 'X', mode = 'o' } },
          config = function()
            -- A custom text-object that selects v:count1 chars to the right.
            vim.keymap.set('o', 'X', function()
              vim.cmd('normal! v' .. math.max(vim.v.count1 - 1, 0) .. 'l')
            end)
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'abcdef' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.api.nvim_feedkeys('d3X', 'mx', false)
    helpers.flush_pending()

    local line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    assert.are.equal('def', line, "d3X should delete 3 characters (count preserved across lazy load)")

    vim.api.nvim_buf_delete(buf, { force = true })
    pcall(vim.keymap.del, 'o', 'X')
  end)

  -- Regression: when every plugin claiming an lhs throws on load, the proxy
  -- has already deleted itself and no real keymap replaced it. Re-feeding the
  -- lhs would type it literally into the buffer (e.g. ` ff` for <leader>ff).
  it("Lazy proxy bails on feedkeys when every plugin fails to load", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = { { '<leader>tf' } },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local original_packadd = vim.cmd.packadd
    vim.cmd.packadd = function() error("simulated packadd failure", 0) end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.api.nvim_feedkeys(' tf', 'mx', false)
    helpers.flush_pending()

    vim.cmd.packadd = original_packadd

    local line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    assert.are.equal('', line,
      "lhs must not be typed into the buffer when every claiming plugin failed to load")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Regression: process_spec swallows apply_keys throws so a key-spec failure
  -- can't roll back load_status into a retry that double-runs run_config.
  -- That swallow meant try_process_spec returned ok=true even when the
  -- pressed lhs ended up unmapped (e.g. malformed rhs threw out of
  -- apply_keys). The proxy was already deleted, so feedkeys would type the
  -- lhs literally into the buffer. apply_keys now pcalls per key and the
  -- proxy bails on feedkeys when its own lhs isn't mapped post-load.
  it("Lazy proxy bails on feedkeys when the pressed key's spec is malformed", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            -- Malformed rhs (number): vim.keymap.set raises on this.
            { '<leader>tm', 42 },
            { '<leader>tn', '<cmd>echo "ok"<cr>' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.api.nvim_feedkeys(' tm', 'mx', false)
    helpers.flush_pending()

    local line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    assert.are.equal('', line,
      "malformed-rhs lhs must not be typed into the buffer after load")

    -- Sibling key with a well-formed rhs should still be registered: per-key
    -- pcall in apply_keys protects siblings from a single bad spec.
    local found_sibling = false
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tn' then
        found_sibling = true
        break
      end
    end
    assert.is_true(found_sibling,
      "well-formed sibling key must be registered even when its sibling throws")

    vim.api.nvim_buf_delete(buf, { force = true })
    pcall(vim.keymap.del, 'n', '<leader>tn')
  end)

  -- Bead zpack_nvim-eyo: a <Nop> rhs should install a real <Nop> keymap
  -- (no proxy, no plugin load) so the key acts as a true no-op.
  it("KeySpec with <Nop> rhs installs real keymap and skips proxy", function()
    local state = require('zpack.state')
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tnp', '<Nop>' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_map
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tnp' then
        found_map = map
        break
      end
    end
    assert.is_not_nil(found_map, "Real <Nop> keymap should be installed")
    -- Real keymap has rhs '<Nop>'; the lazy proxy would have a callback instead.
    assert.is_nil(found_map.callback,
      "<Nop> spec must install a non-proxy keymap (no callback)")

    -- Pressing the key must not load the plugin.
    vim.api.nvim_feedkeys(' tnp', 'mx', false)
    helpers.flush_pending()

    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status,
      "Plugin must remain unloaded after pressing a <Nop>-mapped key")
  end)

  -- `<Nop>` rhs must install a literal-string `<Nop>` map; `expr` /
  -- `replace_keycodes` on the KeySpec are stripped so vim does not try to
  -- evaluate the literal `<Nop>` as a vimscript expression.
  it("KeySpec with <Nop> rhs strips expr/replace_keycodes opts", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tne', '<Nop>', expr = true, replace_keycodes = false },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_map
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tne' then
        found_map = map
        break
      end
    end
    assert.is_not_nil(found_map, "Real <Nop> keymap should be installed")
    assert.are_not.equal(1, found_map.expr,
      "<Nop> install must strip expr=true so the rhs isn't evaluated")
  end)

  -- Bead zpack_nvim-eyo: case-insensitive match for `<Nop>`.
  it("KeySpec with <nop> (lowercase) rhs also installs real keymap", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tnl', '<nop>' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_map
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tnl' then
        found_map = map
        break
      end
    end
    assert.is_not_nil(found_map, "Real <nop> keymap should be installed")
    assert.is_nil(found_map.callback,
      "<nop> spec must install a non-proxy keymap (no callback)")
  end)

  -- Bead zpack_nvim-sdu: abbreviation modes (ia/ca/!a) need <C-]> appended
  -- on the re-fed lhs for the abbreviation to actually expand on first press.
  it("Lazy proxy appends <C-]> on re-feed for abbreviation modes", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { 'teh', function() end, mode = 'ia' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local feed_captured
    local original_feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(keys, _, _)
      feed_captured = keys
    end

    -- maparg's {mode} only accepts single-char modes; abbreviations are
    -- queried via {abbr}=true on the underlying base mode ('i' for 'ia').
    local maparg = vim.fn.maparg('teh', 'i', true, true)
    assert.is_not_nil(maparg.callback, "Proxy should be installed as insert-mode abbreviation")
    maparg.callback()

    vim.api.nvim_feedkeys = original_feedkeys

    assert.is_not_nil(feed_captured, "Proxy must call feedkeys on first press")
    local ctrl_close = vim.keycode('<C-]>')
    assert.is_truthy(feed_captured:find(ctrl_close, 1, true),
      "Re-fed string must contain <C-]> for abbreviation modes")
  end)

  -- Bead zpack_nvim-sdu: non-abbrev modes (n/i/v/etc.) must not add <C-]>.
  it("Lazy proxy does not append <C-]> for non-abbreviation modes", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tab', function() end, mode = 'n' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local feed_captured
    local original_feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(keys, _, _)
      feed_captured = keys
    end

    local maparg = vim.fn.maparg(' tab', 'n', false, true)
    assert.is_not_nil(maparg.callback, "Proxy should be installed for n mode")
    maparg.callback()

    vim.api.nvim_feedkeys = original_feedkeys

    assert.is_not_nil(feed_captured)
    local ctrl_close = vim.keycode('<C-]>')
    assert.is_falsy(feed_captured:find(ctrl_close, 1, true),
      "Non-abbreviation modes must not have <C-]> appended")
  end)

  -- Bead zpack_nvim-n3g: ft-scoped keys must not install a global proxy and
  -- must register a FileType autocmd for the requested filetypes.
  it("KeySpec with ft does not install global proxy", function()
    local state = require('zpack.state')

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tfg', function() end, ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_global
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tfg' then
        found_global = map
      end
    end
    assert.is_nil(found_global, "ft-scoped key must not install a global proxy")

    local autocmds = vim.api.nvim_get_autocmds({ group = state.lazy_group })
    local ft_autocmd = helpers.find_autocmd(autocmds, 'FileType', 'lua')
    assert.is_not_nil(ft_autocmd,
      "FileType autocmd must be registered for the ft-scoped key")
  end)

  -- Bead zpack_nvim-n3g: when a buffer enters the requested ft, the proxy
  -- installs buffer-locally.
  it("KeySpec with ft installs buffer-local proxy on matching FileType", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tfb', function() end, ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'
    helpers.flush_pending()

    local found_local
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tfb' then
        found_local = map
      end
    end
    assert.is_not_nil(found_local,
      "Buffer-local proxy should be installed on matching FileType")
    assert.are.equal(buf, found_local.buffer, "Mapping must be buffer-local to buf")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Bead zpack_nvim-n3g: non-matching filetypes must not get the proxy.
  it("KeySpec with ft skips non-matching filetypes", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tfm', function() end, ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'rust'
    helpers.flush_pending()

    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      assert.are_not.equal(' tfm', map.lhs,
        "Non-matching filetype must not receive the proxy")
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Bead zpack_nvim-n3g: pressing the ft-scoped key triggers plugin load.
  -- Invokes the captured proxy callback directly (instead of feedkeys) to
  -- avoid headless-mode feedkeys quirks with buffer-local mappings.
  it("KeySpec with ft loads plugin on buffer-local proxy fire", function()
    local loaded = false
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tfl', function() end, ft = 'lua' },
          },
          config = function() loaded = true end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'
    helpers.flush_pending()

    local proxy
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tfl' then
        proxy = map
      end
    end
    assert.is_not_nil(proxy, "buffer-local proxy should be installed")
    assert.is_not_nil(proxy.callback, "proxy must have a Lua callback")
    proxy.callback()
    helpers.flush_pending()

    assert.is_true(loaded,
      "Plugin must load when ft-scoped buffer-local proxy fires")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- ft-scoped <Nop>: the suppression must be buffer-local to the matching
  -- ft, not global. lazy.nvim honors ft on Nop maps; without scoping, a
  -- `{ '<leader>x', '<Nop>', ft = 'lua' }` would silently mask the key in
  -- every buffer.
  it("KeySpec with <Nop> + ft installs no global keymap", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tnft', '<Nop>', ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      assert.are_not.equal(' tnft', map.lhs,
        "ft-scoped <Nop> must not install a global keymap")
    end
  end)

  it("KeySpec with <Nop> + ft installs buffer-locally on matching FileType", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tnb', '<Nop>', ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'
    helpers.flush_pending()

    local found
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tnb' then
        found = map
      end
    end
    assert.is_not_nil(found,
      "Buffer-local <Nop> should be installed on matching FileType")
    assert.is_nil(found.callback,
      "<Nop> install must be a real keymap (no callback), not a proxy")
    assert.are.equal(buf, found.buffer, "Mapping must be buffer-local to buf")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("KeySpec with <Nop> + ft skips non-matching filetypes", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tnm', '<Nop>', ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'rust'
    helpers.flush_pending()

    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      assert.are_not.equal(' tnm', map.lhs,
        "Non-matching filetype must not receive the <Nop> install")
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- An empty-string rhs is treated as a no-op by `is_nop_rhs` for lazy.nvim
  -- parity; verify it installs a real keymap and skips the proxy.
  it("KeySpec with empty-string rhs installs real keymap and skips proxy", function()
    local state = require('zpack.state')
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tne', '' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_map
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tne' then
        found_map = map
        break
      end
    end
    assert.is_not_nil(found_map, "Empty-string rhs should install a real keymap")
    assert.is_nil(found_map.callback,
      "empty-string rhs must install a non-proxy keymap (no callback)")

    vim.api.nvim_feedkeys(' tne', 'mx', false)
    helpers.flush_pending()

    local src = 'https://github.com/test/plugin'
    assert.are.equal("pending", state.spec_registry[src].load_status,
      "Plugin must remain unloaded after pressing an empty-rhs key")
  end)

  -- Regression: two plugins claiming the same lhs under disjoint ft scopes
  -- must not collide globally. Before apply_keys honored `key.ft`, the second
  -- plugin to load would install a *global* real keymap that silently
  -- overwrote the first plugin's keymap in every buffer (including the first
  -- plugin's own ft buffers).
  it("ft-scoped real keymap stays buffer-local after lazy-load", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tfx', function() _G._test_ft_real_cb = 'A' end, ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'
    helpers.flush_pending()

    local proxy
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tfx' then
        proxy = map
      end
    end
    assert.is_not_nil(proxy, "buffer-local proxy must be installed on FileType lua")
    proxy.callback()
    helpers.flush_pending()

    -- After load, no global keymap should exist — the post-load keymap is
    -- installed via apply_keys's own FileType autocmd, buffer-local only.
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      assert.are_not.equal(' tfx', map.lhs,
        "ft-scoped real keymap must not install globally after load")
    end

    -- A real (non-proxy) keymap should exist in the matching ft buffer.
    local real
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tfx' then real = map end
    end
    assert.is_not_nil(real, "real keymap must be installed buffer-local in matching ft")

    vim.api.nvim_buf_delete(buf, { force = true })
    _G._test_ft_real_cb = nil
  end)

  -- KeySpec.buffer (lazy.nvim parity) must flow through the lazy proxy when
  -- no ft scope is set; previously the proxy hardcoded `buffer = nil` and
  -- silently dropped the user's intent.
  it("KeySpec.buffer scopes the lazy proxy to the requested buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tbb', function() end, buffer = buf },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_local
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tbb' then found_local = map end
    end
    assert.is_not_nil(found_local,
      "Buffer-scoped key must install the proxy in the requested buffer")
    assert.are.equal(buf, found_local.buffer, "Proxy must be buffer-local to buf")

    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      assert.are_not.equal(' tbb', map.lhs,
        "Buffer-scoped key must not also install a global proxy")
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- Two DIFFERENT plugins claiming the same lhs+mode but with disjoint
  -- `buffer` scopes must each get their own buffer-local proxy. Before
  -- create_key_id was buffer-aware, both plugins collapsed into one
  -- `key_to_info` entry, the first plugin's `buffer` won, and the second
  -- plugin's intended buffer never got a proxy (silent miss).
  it("KeySpec.buffer disambiguates the proxy across plugin sources", function()
    local buf_a = vim.api.nvim_create_buf(true, false)
    local buf_b = vim.api.nvim_create_buf(true, false)

    require('zpack').setup({
      spec = {
        {
          'test/plugin-a',
          keys = { { '<leader>tbx', function() end, buffer = buf_a } },
        },
        {
          'test/plugin-b',
          keys = { { '<leader>tbx', function() end, buffer = buf_b } },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local function has_lhs(buf)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
        if m.lhs == ' tbx' then return true end
      end
      return false
    end

    assert.is_true(has_lhs(buf_a),
      "plugin-a's buffer must get its own proxy")
    assert.is_true(has_lhs(buf_b),
      "plugin-b's buffer must get its own proxy (silent-miss regression)")

    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      assert.are_not.equal(' tbx', map.lhs,
        "Buffer-scoped keys must not also install a global proxy")
    end

    vim.api.nvim_buf_delete(buf_a, { force = true })
    vim.api.nvim_buf_delete(buf_b, { force = true })
  end)

  -- ft-scoped lazy proxy must install in buffers that ALREADY match the
  -- filetype at setup() time — their FileType event already fired in the
  -- past, so the autocmd alone never reaches them. Without the sweep,
  -- `:luafile %` (config reload while a matching buffer is current) would
  -- leave the lhs untriggerable in that buffer.
  it("ft-scoped lazy proxy installs in existing matching buffers at setup", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = 'lua'
    helpers.flush_pending()

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tff', function() end, ft = 'lua' },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == ' tff' then found = map end
    end
    assert.is_not_nil(found,
      "Proxy must install in a buffer already at the ft when setup() runs")

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  -- ft = {} normalizes to "no ft scope" — installing an autocmd with an
  -- empty pattern list would silently never match, dropping the key.
  it("KeySpec with empty ft = {} falls back to a global proxy", function()
    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          keys = {
            { '<leader>tfe', function() end, ft = {} },
          },
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()

    local found_global
    for _, map in ipairs(vim.api.nvim_get_keymap('n')) do
      if map.lhs == ' tfe' then found_global = map end
    end
    assert.is_not_nil(found_global,
      "Empty `ft = {}` must not silently disable the key — install globally")
    assert.is_not_nil(found_global.callback,
      "Empty `ft = {}` key should still register as a lazy proxy (callback present)")
  end)
end)
