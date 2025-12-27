local helpers = require('helpers')

-- Clean state before running any tests
package.loaded['zpack.state'] = nil
package.loaded['zpack.init'] = nil

local test_modules = {
  'setup_test',
  'lazy_cmd_test',
  'lazy_keys_test',
  'lazy_event_test',
  'lazy_ft_test',
  'lifecycle_test',
  'priority_test',
  'conditional_test',
  'plugin_data_test',
}

print("\n" .. string.rep("=", 60))
print("Running zpack.nvim Test Suite")
print(string.rep("=", 60))

helpers.reset()

for _, module_name in ipairs(test_modules) do
  local success, test_fn = pcall(require, module_name)
  if success and type(test_fn) == 'function' then
    test_fn()
  else
    print(string.format("Failed to load test module: %s", module_name))
    if not success then
      print(string.format("Error: %s", test_fn))
    end
  end
end

local all_passed = helpers.summary()

if all_passed then
  print("\n✓ All tests passed!")
  vim.cmd('qall!')
else
  print("\n✗ Some tests failed")
  vim.cmd('cquit!') -- Exit with error code 1
end
