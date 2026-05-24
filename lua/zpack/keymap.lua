local util = require('zpack.utils')

local M = {}

local SUPPORTED_OPTS = { 'desc', 'remap', 'nowait', 'expr', 'silent', 'replace_keycodes', 'buffer' }

---@param lhs string
---@param rhs string|fun()
---@param opts? zpack.KeySpec|zpack.KeymapOpts
M.map = function(lhs, rhs, opts)
  opts = opts or {}
  local set_opts = {}
  for _, k in ipairs(SUPPORTED_OPTS) do
    set_opts[k] = opts[k]
  end
  -- lazy.nvim compat: noremap is the inverse of remap. Explicit `remap` wins;
  -- the alias is consulted only when remap is unset.
  if set_opts.remap == nil and opts.noremap ~= nil then
    set_opts.remap = not opts.noremap
  end
  if set_opts.expr then
    -- Mirror Neovim's documented expr→replace_keycodes default so zpack owns the contract.
    if set_opts.replace_keycodes == nil then
      set_opts.replace_keycodes = true
    end
  else
    -- vim.keymap.set raises when replace_keycodes is set without expr.
    set_opts.replace_keycodes = nil
  end
  vim.keymap.set(opts.mode or { 'n' }, lhs, rhs, set_opts)
end

---@param keys zpack.KeySpec|zpack.KeySpec[]|string
---@param src string Plugin identifier for the failure notify
M.apply_keys = function(keys, src)
  local key_list = util.normalize_keys(keys) --[[@as zpack.KeySpec[] ]]

  for _, key in ipairs(key_list) do
    if key[2] ~= nil then
      -- pcall per key so one malformed spec doesn't strand its siblings.
      -- lazy_trigger/keys.lua's post-load maparg gate ensures an unmapped
      -- lhs doesn't fall through to bare keystrokes typed in the buffer.
      local ok, err = pcall(M.map, key[1], key[2], key)
      if not ok then
        util.schedule_notify(
          ("Failed to map %s for %s: %s"):format(key[1], src, tostring(err)),
          vim.log.levels.ERROR
        )
      end
    end
  end
end

return M
