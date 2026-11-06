local helpers = require('helpers')
local fuzz = require('prune_fuzz_helpers')

local SEEDS = 1000
-- A deliberate change to what resolve_all decides updates it.
local DIGEST = 'd8d660bdbcf8f8240ed9f8db073a2111ce5b38fc053849962aa1201e2a7ccc3f'

describe('resolve_all on random specs', function()
  local root

  before_each(function()
    helpers.setup_test_env()
    root = fuzz.fixture()
  end)

  after_each(function()
    vim.fn.delete(root, 'rf')
    helpers.cleanup_test_env()
  end)

  it('decides what it always has, running each function-form enabled at most once', function()
    local outcomes, max_calls = {}, 0
    for seed = 1, SEEDS do
      local outcome, calls = fuzz.run(seed, root)
      outcomes[seed] = outcome
      max_calls = math.max(max_calls, calls)
    end
    assert.are.equal(1, max_calls)
    assert.are.equal(DIGEST, vim.fn.sha256(table.concat(outcomes, '\n')))
  end)
end)
