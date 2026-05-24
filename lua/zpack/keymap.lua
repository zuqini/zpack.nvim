local util = require('zpack.utils')
local state = require('zpack.state')

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

---Wrap `M.map` with pcall + structured notify. Used at every map site so
---one bad key spec never strands siblings or recurs as autocmd-dispatch noise.
---@param lhs string
---@param rhs string|fun()
---@param opts? table
---@param src string Plugin identifier for the failure notify
---@return boolean ok
M.try_map = function(lhs, rhs, opts, src)
  local ok, err = pcall(M.map, lhs, rhs, opts)
  if not ok then
    util.schedule_notify(
      ("Failed to map %s for %s: %s"):format(lhs, src, tostring(err)),
      vim.log.levels.ERROR
    )
  end
  return ok
end

---@param key zpack.KeySpec
---@param src string
local function apply_ft_scoped(key, src)
  local patterns = util.normalize_string_list(key.ft) --[[@as string[] ]]
  util.install_on_ft(patterns, function(buf)
    local opts = vim.tbl_extend('force', {}, key, { buffer = buf })
    M.try_map(key[1], key[2], opts, src)
  end, { group = state.lazy_group })
end

---@param keys zpack.KeySpec|zpack.KeySpec[]|string
---@param src string Plugin identifier for the failure notify
M.apply_keys = function(keys, src)
  local key_list = util.normalize_keys(keys) --[[@as zpack.KeySpec[] ]]

  for _, key in ipairs(key_list) do
    if key[2] ~= nil then
      -- ft scope (lazy.nvim parity): install via FileType autocmd + iterate
      -- already-matching buffers so the real keymap stays buffer-local.
      -- Without this, a global apply_keys could silently overwrite a sibling
      -- plugin that claimed the same lhs under a disjoint ft.
      if util.normalize_ft_scope(key.ft) then
        -- pcall the registration plumbing; per-buffer try_map handles its own throws.
        local ok, err = pcall(apply_ft_scoped, key, src)
        if not ok then
          util.schedule_notify(
            ("Failed to map %s for %s: %s"):format(key[1], src, tostring(err)),
            vim.log.levels.ERROR
          )
        end
      else
        M.try_map(key[1], key[2], key, src)
      end
    end
  end
end

return M
