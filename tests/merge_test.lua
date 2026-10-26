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

  it("resolve_opts concatenates opts_extend lists across specs", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'ensure_installed' }, opts = { ensure_installed = { 'bash', 'c', 'diff' } } },
      { opts = { ensure_installed = { 'rust', 'ron' } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 'bash', 'c', 'diff', 'rust', 'ron' }, result.ensure_installed)
  end)

  it("resolve_opts applies opts_extend declared on a later spec to earlier lists", function()
    local merge = require('zpack.merge')

    -- lazy.nvim only extends from the declaring spec onward and would drop
    -- 'a'; zpack unions every spec's opts_extend so the result does not
    -- hinge on the order plugin files are imported.
    local specs = {
      { opts = { ensure_installed = { 'a' } } },
      { opts = { ensure_installed = { 'b' } } },
      { opts_extend = { 'ensure_installed' }, opts = { ensure_installed = { 'c' } } },
      { opts = { ensure_installed = { 'd' } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 'a', 'b', 'c', 'd' }, result.ensure_installed)
  end)

  it("resolve_opts applies opts_extend declared on a spec without opts", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts = { list = { 'a' } } },
      { opts_extend = { 'list' } },
      { opts = { list = { 'b' } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 'a', 'b' }, result.list)
  end)

  it("resolve_opts never drops a key another spec's opts_extend names", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'first', 'second' }, opts = { first = { 1 }, second = { 1 } } },
      { opts_extend = { 'first' }, opts = { first = { 2 }, second = { 2 } } },
      { opts_extend = {}, opts = { first = { 3 }, second = { 3 } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 1, 2, 3 }, result.first)
    assert.are.same({ 1, 2, 3 }, result.second)
  end)

  it("resolve_opts deep-merges an opts_extend key that holds a dict", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'servers' }, opts = { servers = { lua_ls = { cmd = 'lua' } } } },
      { opts = { servers = { pyright = { cmd = 'py' } } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ lua_ls = { cmd = 'lua' }, pyright = { cmd = 'py' } }, result.servers)
  end)

  it("resolve_opts keeps sibling keys when opts_extend names a dict and a list inside it", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'a', 'a.b' }, opts = { a = { b = { 1 }, keep = true } } },
      { opts = { a = { b = { 2 } } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ b = { 1, 2 }, keep = true }, result.a)
  end)

  it("resolve_opts skips non-string opts_extend keys instead of throwing", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 1, { 'x' }, 'list' }, opts = { list = { 'a' } } },
      { opts = { list = { 'b' } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 'a', 'b' }, result.list)
  end)

  it("resolve_opts follows dotted opts_extend keys into nested lists", function()
    local merge = require('zpack.merge')

    local specs = {
      {
        opts_extend = { 'sources.default' },
        opts = { sources = { default = { 'lsp', 'path' }, providers = { lsp = { name = 'LSP' } } } },
      },
      { opts = { sources = { default = { 'snippets' }, providers = { snippets = { name = 'Snip' } } } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 'lsp', 'path', 'snippets' }, result.sources.default)
    assert.are.equal('LSP', result.sources.providers.lsp.name)
    assert.are.equal('Snip', result.sources.providers.snippets.name)
  end)

  it("resolve_opts still replaces lists not named in opts_extend", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'extended' }, opts = { extended = { 1 }, replaced = { 1 } } },
      { opts = { extended = { 2 }, replaced = { 2 } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 1, 2 }, result.extended)
    assert.are.same({ 2 }, result.replaced)
  end)

  it("resolve_opts without opts_extend merges like vim.tbl_deep_extend", function()
    local merge = require('zpack.merge')

    local a = { list = { 1, 2 }, dict = { x = 1, nested = { y = 1 } }, empty = {}, mixed = { 1, k = 'a' }, s = 'a' }
    local b = { list = { 3 }, dict = { nested = { z = 2 } }, empty = { q = 1 }, mixed = { 9 }, s = 'b', new = { 1 } }
    local result = merge.resolve_opts({ { opts = a }, { opts = b } }, {})

    assert.are.same(vim.tbl_deep_extend('force', a, b), result)
  end)

  it("resolve_opts extends onto the table a function-form opts returns", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'list' }, opts = { list = { 'a' } } },
      {
        opts = function(_, acc)
          table.insert(acc.list, 'b')
          return acc
        end,
      },
      { opts = { list = { 'c' } } },
    }
    local result = merge.resolve_opts(specs, {})

    assert.are.same({ 'a', 'b', 'c' }, result.list)
  end)

  it("resolve_opts with opts_extend leaves spec opts untouched across resolves", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts_extend = { 'top', 'nested.list' }, opts = { top = { 'a' }, nested = { list = { 'x' } } } },
      { opts = { top = { 'b' }, nested = { list = { 'y' } } } },
      { opts = { top = { 'c' }, nested = { list = { 'z' } } } },
    }
    local first = merge.resolve_opts(specs, {})
    local second = merge.resolve_opts(specs, {})

    assert.are.same({ 'a', 'b', 'c' }, second.top)
    assert.are.same({ 'x', 'y', 'z' }, second.nested.list)
    assert.are.same(first, second)
    assert.are.same({ top = { 'a' }, nested = { list = { 'x' } } }, specs[1].opts)
    assert.are.same({ top = { 'b' }, nested = { list = { 'y' } } }, specs[2].opts)
    assert.are.same({ top = { 'c' }, nested = { list = { 'z' } } }, specs[3].opts)
  end)

  it("resolve_opts keeps function-form opts from editing a spec's opts_extend lists", function()
    local merge = require('zpack.merge')

    local specs = {
      {
        opts_extend = { 'ensure_installed', 'sources.default' },
        opts = { ensure_installed = { 'bash' }, sources = { default = { 'lsp' } } },
      },
      {
        opts = function(_, opts)
          vim.list_extend(opts.ensure_installed, { 'lua' })
          table.insert(opts.sources.default, 'path')
        end,
      },
      { opts = { ensure_installed = { 'rust' } } },
    }
    merge.resolve_opts(specs, {})
    local second = merge.resolve_opts(specs, {})

    assert.are.same({ 'bash', 'lua', 'rust' }, second.ensure_installed)
    assert.are.same({ 'lsp', 'path' }, second.sources.default)
    assert.are.same({ ensure_installed = { 'bash' }, sources = { default = { 'lsp' } } }, specs[1].opts)
  end)

  it("resolve_opts keeps function-form opts from editing a spec's other tables", function()
    local merge = require('zpack.merge')

    local specs = {
      { opts = { sections = { lualine_x = { 'encoding' } } } },
      { opts = function(_, opts) table.insert(opts.sections.lualine_x, 'copilot') end },
    }
    merge.resolve_opts(specs, {})
    local second = merge.resolve_opts(specs, {})

    assert.are.same({ 'encoding', 'copilot' }, second.sections.lualine_x)
    assert.are.same({ sections = { lualine_x = { 'encoding' } } }, specs[1].opts)
  end)

  it("resolve_opts result can be edited without reaching a lone spec's opts", function()
    local merge = require('zpack.merge')

    local specs = { { opts = { nested = { list = { 1 } } } } }
    local result = merge.resolve_opts(specs, {})
    table.insert(result.nested.list, 2)

    assert.are.same({ nested = { list = { 1 } } }, specs[1].opts)
  end)

  it("resolve_opts keeps functions, objects and cycles intact", function()
    local merge = require('zpack.merge')

    local fn = function() end
    local object = setmetatable({}, { __index = {} })
    local cyclic = { name = 'c' }
    cyclic.self = cyclic
    local specs = { { opts = { fn = fn, object = object, empty = vim.empty_dict(), cyclic = cyclic } } }
    local result = merge.resolve_opts(specs, {})

    assert.are.equal(fn, result.fn)
    assert.are.equal(object, result.object)
    assert.are.equal(getmetatable(vim.empty_dict()), getmetatable(result.empty))
    assert.are_not.equal(cyclic, result.cyclic)
    assert.are.equal(result.cyclic, result.cyclic.self)
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
