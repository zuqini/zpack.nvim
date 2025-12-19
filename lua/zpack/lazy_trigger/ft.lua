local util = require('zpack.utils')
local state = require('zpack.state')
local loader = require('zpack.loader')

local M = {}

---@param pack_spec vim.pack.Spec
---@param spec Spec
M.setup = function(pack_spec, spec)
  local filetypes = util.normalize_string_list(spec.ft)

  util.autocmd("FileType", function(ev)
    loader.process_spec(pack_spec)

    -- Re-trigger events for the buffer that triggered loading to ensure LSP/Treesitter attach
    vim.schedule(function()
      local bufnr = ev.buf
      vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })
      vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
      vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
    end)
  end, { group = state.lazy_group, pattern = filetypes, once = true })
end

return M
