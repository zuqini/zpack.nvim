local project_root = vim.fn.getcwd()

-- Add lua/ for zpack modules and tests/ for test modules
package.path = project_root .. '/lua/?.lua;'
  .. project_root .. '/lua/?/init.lua;'
  .. project_root .. '/tests/?.lua;'
  .. package.path

require('run_all')
vim.cmd('qa!')
