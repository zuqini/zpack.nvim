local helpers = require('helpers')
local pack_update_tests = require('pack_update_test_helpers')

describe('ZPack restore', function()
  before_each(helpers.setup_test_env)
  after_each(helpers.cleanup_test_env)

  for _, case in ipairs(pack_update_tests.cases({
    command = 'ZPack restore',
    expected_opts = { target = 'lockfile' },
    error_prefix = 'Restore failed',
    supports_bang = true,
  })) do
    it(case.name, case.fn)
  end
end)
