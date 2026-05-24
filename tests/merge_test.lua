local helpers = require('helpers')

describe("Spec Merging", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("duplicate specs are merged", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', opts = { a = 1 } },
        { 'test/plugin', opts = { b = 2 } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'

    assert.are.equal(2, #state.spec_registry[src].specs)
    assert.is_not_nil(state.spec_registry[src].merged_spec, "should have merged_spec")
  end)

  it("opts are deep merged", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        { 'test/plugin', opts = { a = 1, nested = { x = 1 } } },
        {
          'test/plugin',
          opts = { b = 2, nested = { y = 2 } },
          config = function(plugin, opts)
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts, "config should receive merged opts")
    assert.are.equal(1, received_opts.a)
    assert.are.equal(2, received_opts.b)
    assert.are.equal(1, received_opts.nested.x)
    assert.are.equal(2, received_opts.nested.y)
  end)

  it("override fields use last value", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', priority = 10, main = 'first' },
        { 'test/plugin', priority = 20, main = 'second' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec

    assert.are.equal(20, spec.priority)
    assert.are.equal('second', spec.main)
  end)

  it("list fields are extended uniquely", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', event = 'BufReadPre', cmd = 'Cmd1' },
        { 'test/plugin', event = { 'BufWritePost', 'BufReadPre' }, cmd = 'Cmd2' },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local spec = state.spec_registry[src].merged_spec

    assert.are.equal(2, #spec.event)
    assert.are.equal(2, #spec.cmd)
  end)

  it("config function uses last declared", function()
    local config_count = 0
    local which_config = nil

    require('zpack').setup({
      spec = {
        {
          'test/plugin',
          config = function()
            config_count = config_count + 1
            which_config = 'first'
          end,
        },
        {
          'test/plugin',
          config = function()
            config_count = config_count + 1
            which_config = 'second'
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.are.equal(1, config_count)
    assert.are.equal('second', which_config)
  end)

  it("function-based opts receives accumulated opts", function()
    local received_accumulated = nil

    require('zpack').setup({
      spec = {
        { 'test/plugin', opts = { base = true } },
        {
          'test/plugin',
          opts = function(plugin, accumulated)
            received_accumulated = accumulated
            return vim.tbl_extend('force', accumulated, { added = true })
          end,
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_accumulated, "should receive accumulated opts")
    assert.are.equal(true, received_accumulated.base)
  end)

  it("standalone specs have priority over dependency specs", function()
    local received_opts = nil

    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = {
            { 'test/dep', opts = { from_dep = true, conflict = 'dep' } },
          },
        },
        {
          'test/dep',
          opts = { from_standalone = true, conflict = 'standalone' },
          config = function(plugin, opts)
            received_opts = opts
          end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    assert.is_not_nil(received_opts)
    assert.are.equal(true, received_opts.from_dep)
    assert.are.equal(true, received_opts.from_standalone)
    assert.are.equal('standalone', received_opts.conflict)
  end)

  it("standalone branch is not overridden by nil dependency branch", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = {
            'test/dep',
          },
        },
        {
          'test/dep',
          branch = 'main',
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/dep'

    local merged_spec = state.spec_registry[src].merged_spec
    assert.are.equal('main', merged_spec.branch)

    local pack_spec = state.src_to_pack_spec[src]
    assert.are.equal('main', pack_spec.version)
  end)

  it("dependency branch is used when standalone has no branch", function()
    require('zpack').setup({
      spec = {
        {
          'test/parent',
          dependencies = {
            { 'test/dep', branch = 'develop' },
          },
        },
        {
          'test/dep',
          config = function() end,
        },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/dep'

    local merged_spec = state.spec_registry[src].merged_spec
    assert.are.equal('develop', merged_spec.branch)

    local pack_spec = state.src_to_pack_spec[src]
    assert.are.equal('develop', pack_spec.version)
  end)
end)

describe("Merge Module Unit Tests", function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  it("merge_specs skips opts (resolved lazily by resolve_opts)", function()
    local merge = require('zpack.merge')

    -- opts is intentionally not collapsed by merge_specs. It is resolved
    -- at load time by resolve_opts so function-form opts compose correctly
    -- with a single authoritative code path. See merge.lua field_strategies
    -- comment. Callers that need the deep-merged value should invoke
    -- merge.resolve_opts(sorted_specs, plugin).
    local base = { opts = { a = 1, nested = { x = 1 } } }
    local incoming = { opts = { b = 2, nested = { y = 2 } } }
    local result = merge.merge_specs(base, incoming)

    assert.is_nil(result.opts, "merge_specs must never populate opts")

    -- resolve_opts is the authoritative path and deep-merges table-form opts.
    local resolved = merge.resolve_opts({ base, incoming }, {})
    assert.are.equal(1, resolved.a)
    assert.are.equal(2, resolved.b)
    assert.are.equal(1, resolved.nested.x)
    assert.are.equal(2, resolved.nested.y)
  end)

  it("merge_specs extends list fields uniquely", function()
    local merge = require('zpack.merge')

    local base = { event = { 'A', 'B' } }
    local incoming = { event = { 'B', 'C' } }
    local result = merge.merge_specs(base, incoming)

    assert.are.equal(3, #result.event)
  end)

  it("merge_specs uses AND logic for cond", function()
    local merge = require('zpack.merge')

    local base = { cond = true }
    local incoming = { cond = false }
    local result = merge.merge_specs(base, incoming)

    assert.are.equal(false, result.cond)
  end)

  it("merge_and for enabled: function returning false composes to false", function()
    local merge = require('zpack.merge')
    local utils = require('zpack.utils')

    local base = { enabled = function() return false end }
    local incoming = { enabled = true }
    local result = merge.merge_specs(base, incoming)

    assert.are.equal("function", type(result.enabled))
    assert.is_falsy(
      utils.check_enabled(result),
      "enabled fn returning false must propagate through merge, not collapse via ternary"
    )
  end)

  it("merge_and for cond: function returning false composes to false", function()
    local merge = require('zpack.merge')
    local utils = require('zpack.utils')

    local base = { cond = function() return false end }
    local incoming = { cond = true }
    local result = merge.merge_specs(base, incoming)

    assert.are.equal("function", type(result.cond))
    assert.is_falsy(
      utils.check_cond(result, {}),
      "cond fn returning false must propagate through merge, not collapse via ternary"
    )
  end)

  it("merge_and_enabled: merged function is called with no arguments", function()
    local merge = require('zpack.merge')
    local utils = require('zpack.utils')

    local received_arg
    local base = { enabled = function(...) received_arg = select('#', ...); return true end }
    local incoming = { enabled = function() return true end }
    local result = merge.merge_specs(base, incoming)
    utils.check_enabled(result)

    assert.are.equal(0, received_arg)
  end)

  it("sort_specs puts dependencies before standalone", function()
    local merge = require('zpack.merge')

    local specs = {
      { _is_dependency = true, _import_order = 0 },
      { _is_dependency = false, _import_order = 1 },
      { _is_dependency = true, _import_order = 2 },
    }
    local sorted = merge.sort_specs(specs)

    assert.is_truthy(sorted[1]._is_dependency, "first should be dependency")
    assert.is_truthy(sorted[2]._is_dependency, "second should be dependency")
    assert.is_falsy(sorted[3]._is_dependency, "last should be standalone (wins)")
  end)

  it("resolve_opts accumulates through function opts", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts = { a = 1 } },
      {
        opts = function(plugin, acc)
          return vim.tbl_extend('force', acc, { b = 2 })
        end,
      },
      { opts = { c = 3 } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.equal(1, result.a)
    assert.are.equal(2, result.b)
    assert.are.equal(3, result.c)
  end)

  it("keys with different modes are not deduplicated", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>a', mode = 'n', desc = 'normal' } } },
        { 'test/plugin', keys = { { '<leader>a', mode = 'v', desc = 'visual' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(2, #merged.keys)
  end)

  it("keys with same lhs and mode are deduplicated", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>a', mode = 'n', desc = 'first' } } },
        { 'test/plugin', keys = { { '<leader>a', mode = 'n', desc = 'second' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(1, #merged.keys)
    assert.are.equal('first', merged.keys[1].desc)
  end)

  it("keys with same modes in different order are deduplicated", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>a', mode = { 'n', 'v' }, desc = 'first' } } },
        { 'test/plugin', keys = { { '<leader>a', mode = { 'v', 'n' }, desc = 'second' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(1, #merged.keys)
  end)

  -- Two specs declaring the same lhs/mode but disjoint ft scopes are NOT
  -- duplicates — the user wants both keys, scoped to different filetypes.
  -- get_unique_key must include ft so the second spec survives merge and
  -- reaches lazy_trigger/keys.lua's ft-aware dedup.
  it("keys with same lhs/mode but different ft scopes both survive merge", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>a', '<cmd>Lua<cr>', ft = 'lua' } } },
        { 'test/plugin', keys = { { '<leader>a', '<cmd>Rust<cr>', ft = 'rust' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(2, #merged.keys,
      "Both ft-scoped keys should survive merge")
  end)

  it("keys with ft as list in different order are deduplicated", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>a', ft = { 'lua', 'rust' }, desc = 'first' } } },
        { 'test/plugin', keys = { { '<leader>a', ft = { 'rust', 'lua' }, desc = 'second' } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(1, #merged.keys,
      "Ft lists with same members in different order should dedup")
  end)

  -- Symmetric with the ft case above: two specs declaring the same lhs/mode
  -- but disjoint `buffer` scopes are NOT duplicates — get_unique_key must
  -- include buffer so the second spec survives merge.
  it("keys with same lhs/mode but different buffer scopes both survive merge", function()
    local buf_a = vim.api.nvim_create_buf(true, false)
    local buf_b = vim.api.nvim_create_buf(true, false)

    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>b', '<cmd>A<cr>', buffer = buf_a } } },
        { 'test/plugin', keys = { { '<leader>b', '<cmd>B<cr>', buffer = buf_b } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(2, #merged.keys,
      "Both buffer-scoped keys should survive merge")

    vim.api.nvim_buf_delete(buf_a, { force = true })
    vim.api.nvim_buf_delete(buf_b, { force = true })
  end)

  -- lazy.nvim parity: `buffer = true` and `buffer = 0` both mean "current
  -- buffer at registration time", so they MUST collapse to one entry —
  -- otherwise a user toggling between the two forms gets a duplicate.
  it("keys with buffer = true and buffer = 0 are deduplicated", function()
    require('zpack').setup({
      spec = {
        { 'test/plugin', keys = { { '<leader>c', '<cmd>A<cr>', buffer = true } } },
        { 'test/plugin', keys = { { '<leader>c', '<cmd>B<cr>', buffer = 0 } } },
      },
      defaults = { confirm = false },
    })

    helpers.flush_pending()
    local state = require('zpack.state')
    local src = 'https://github.com/test/plugin'
    local merged = state.spec_registry[src].merged_spec

    assert.are.equal(1, #merged.keys,
      "buffer = true and buffer = 0 should hash to the same entry")
  end)
end)
