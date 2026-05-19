-- Lint configuration for zpack.nvim.
-- Warning reference: https://luacheck.readthedocs.io/en/stable/warnings.html

std = "luajit"
codes = true

-- zpack runs inside Neovim; `vim` is an injected global.
read_globals = { "vim" }

-- The project has no line-length convention (no stylua/editorconfig). luacheck
-- here guards correctness — unused/shadowed vars, undefined globals — not
-- formatting, so the line-length check is left off.
max_line_length = false

-- The suite runs under busted (describe/it/assert globals). The harness also
-- stubs vim.* (vim.notify, vim.pack.add, ...) and threads shared state
-- through the _G.test_state table, so under tests/ `vim` is written to and
-- `_G` is used directly. Test files also carry documentary callback args and
-- assertion-scaffolding locals; their unused-variable hygiene (2xx/23x) is
-- intentionally not linted.
files["tests"] = {
  std = "luajit+busted",
  globals = { "vim", "_G" },
  ignore = { "21", "23" },
}
