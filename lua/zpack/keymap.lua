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

---@param key zpack.KeySpec
---@param buf integer
---@param src string
local function install_buffer_local(key, buf, src)
  local opts = vim.tbl_extend('force', {}, key, { buffer = buf })
  local ok, err = pcall(M.map, key[1], key[2], opts)
  if not ok then
    util.schedule_notify(
      ("Failed to map %s for %s: %s"):format(key[1], src, tostring(err)),
      vim.log.levels.ERROR
    )
  end
end

---@param key zpack.KeySpec
---@param src string
local function apply_ft_scoped(key, src)
  local patterns = util.normalize_string_list(key.ft) --[[@as string[] ]]
  local pat_set = {}
  for _, p in ipairs(patterns) do pat_set[p] = true end
  -- Catch future matching buffers.
  vim.api.nvim_create_autocmd("FileType", {
    group = state.lazy_group,
    pattern = patterns,
    callback = function(ev)
      install_buffer_local(key, ev.buf, src)
    end,
  })
  -- Install in currently-matching buffers — their FileType has already
  -- fired, so the autocmd above won't reach them.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and pat_set[vim.bo[buf].filetype] then
      install_buffer_local(key, buf, src)
    end
  end
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
      local has_ft = type(key.ft) == 'string'
          or (type(key.ft) == 'table' and next(key.ft --[[@as table]]) ~= nil)
      if has_ft then
        apply_ft_scoped(key, src)
      else
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
end

return M
