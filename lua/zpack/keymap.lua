if jit then jit.off(true, true) end

local util = require('zpack.utils')
local state = require('zpack.state')

local M = {}

local SUPPORTED_OPTS = { 'desc', 'remap', 'nowait', 'expr', 'silent', 'replace_keycodes', 'buffer' }

---A table starting with a string is one KeySpec when it has a field, a
---non-string rhs, or a second string that can only be an rhs (empty, `<Nop>`,
---`<cmd>...`, `<Plug>...`, `:...`, `...<CR>`). `{ '<a>', '<b>' }`
---is a list of two keys, as in lazy.nvim, and so is any list holding a table.
---@param keys table
---@return boolean
local function is_single_key(keys)
  if type(keys[1]) ~= "string" then
    return false
  end
  local single = #keys == 1
  for k, v in pairs(keys) do
    if type(k) == "number" and type(v) == "table" then
      return false
    end
    if type(k) ~= "number" or type(v) ~= "string" then
      single = true
    end
  end
  if single then
    return true
  end
  local rhs = #keys == 2 and keys[2]:lower()
  return rhs ~= false and (M.is_nop_rhs(rhs)
    or rhs:find("^<cmd>") ~= nil or rhs:find("^<plug>") ~= nil or rhs:find("^:") ~= nil
    -- `<CR>` and `<C-x><CR>` are keys someone may map; text before `<CR>` is a command.
    or (rhs:find(".<cr>$") ~= nil and rhs:find("^<[^<>]*><cr>$") == nil))
end

---Normalize keys to a list of KeySpec tables
---@param keys zpack.KeySpec|zpack.KeySpec[]|string|string[]
---@return zpack.KeySpec[]
M.normalize_keys = function(keys)
  if type(keys) ~= "string" and type(keys) ~= "table" then
    return {}
  end
  local key_list = (type(keys) == "string" or is_single_key(keys))
      and { keys }
      or keys --[[@as string[]|zpack.KeySpec[] ]]

  local result = {}
  for _, key in ipairs(key_list) do
    if type(key) == "string" then
      table.insert(result, { key })
    elseif type(key) == "table" then
      table.insert(result, key)
    end
  end
  return result
end

---@param rhs any
---@return boolean
M.is_nop_rhs = function(rhs)
  return type(rhs) == "string" and (rhs == "" or rhs:lower() == "<nop>")
end

---`maparg()` for one of `vim.keymap.set`'s modes: it takes abbreviations as a flag
---and reads `!` as normal mode, so ask for insert mode, which `!` maps too.
---@param lhs string
---@param mode string
---@return table map Empty when `lhs` isn't mapped
M.maparg = function(lhs, mode)
  local abbr = mode:sub(-1) == 'a'
  local base = abbr and mode:sub(1, -2) or mode
  return vim.fn.maparg(lhs, base == '!' and 'i' or base, abbr, true)
end

---What makes two keys the same mapping. lazy.nvim parity: `buffer = true` and
---`buffer = 0` both mean "current buffer".
---@param lhs string
---@param mode string
---@param ft string|string[]|nil
---@param buffer integer|boolean|nil
---@return string
M.key_id = function(lhs, mode, ft, buffer)
  local scope = M.normalize_ft_scope(ft)
  if scope then
    scope = vim.list_slice(scope)
    table.sort(scope)
  end
  return table.concat({
    vim.api.nvim_replace_termcodes(lhs, true, true, true),
    mode,
    scope and table.concat(scope, ",") or "",
    tostring(buffer == true and 0 or buffer or ""),
  }, "\0")
end

---Claim a key's lhs, ft and buffer in each of its modes.
---@param key zpack.KeySpec
---@param claimed { [string]: true }
---@return string[] kept The modes no later key had claimed
---@return integer total How many modes the key has
local function claim_key_modes(key, claimed)
  local modes = util.normalize_string_list(key.mode or "n")
  local kept = {}
  for _, mode in ipairs(modes) do
    local id = M.key_id(key[1], mode, key.ft, key.buffer)
    if not claimed[id] then
      claimed[id] = true
      kept[#kept + 1] = mode
    end
  end
  return kept, #modes
end

---Later keys replace earlier ones with the same lhs, mode, ft and buffer, one
---mode at a time (lazy.nvim's Keys.resolve). A key that loses only some of its
---modes is copied with the ones left. A malformed key is kept as it is, for the
---keys trigger to report against its plugin, since this also runs mid-merge.
---@param key_list zpack.KeySpec[]
---@return zpack.KeySpec[]
M.dedupe_keys = function(key_list)
  local claimed, reversed = {}, {}
  for i = #key_list, 1, -1 do
    local key = key_list[i]
    local ok, kept, total = pcall(claim_key_modes, key, claimed)
    if not ok or #kept == total then
      reversed[#reversed + 1] = key
    elseif #kept > 0 then
      reversed[#reversed + 1] = vim.tbl_extend("force", {}, key, { mode = kept })
    end
  end
  local result = {}
  for i = #reversed, 1, -1 do
    result[#result + 1] = reversed[i]
  end
  return result
end

---@param lhs any
---@return boolean
local function has_lhs(lhs)
  if type(lhs) ~= 'table' then
    return type(lhs) == 'string' and lhs ~= ''
  end
  for _, item in ipairs(lhs) do
    if type(item) == 'string' and item ~= '' then
      return true
    end
  end
  return false
end

---`''` is a real map-mode: normal, visual and operator-pending.
---@param mode any
---@return boolean
local function has_mode(mode)
  if type(mode) ~= 'table' then
    return mode == nil or type(mode) == 'string'
  end
  for _, item in ipairs(mode) do
    if type(item) == 'string' then
      return true
    end
  end
  return false
end

---@class zpack.ParsedKeys
---@field keys zpack.KeySpec[] What to map: deduped, and without the ones a spec disabled with a `false` or vim.NIL rhs
---@field usable boolean Disabled keys count, so a spec can turn off a plugin's keys and leave it lazy

---@param value any
---@return zpack.ParsedKeys?
M.parse = function(value)
  if not value then
    return nil
  end
  local normalized = M.normalize_keys(value)
  local parsed = { keys = {}, usable = false }
  for _, key in ipairs(normalized) do
    if has_lhs(key[1]) and has_mode(key.mode) then
      parsed.usable = true
      break
    end
  end
  for _, key in ipairs(M.dedupe_keys(normalized)) do
    if key[2] ~= false and key[2] ~= vim.NIL then
      parsed.keys[#parsed.keys + 1] = key
    end
  end
  return parsed
end

---Returns the normalized pattern list (nil when unscoped) for a KeySpec's
---`ft`. Shared by keys.lua's proxy install + keymap.lua's apply_ft_scoped.
---@param ft any
---@return string[]? patterns nil when `ft` is not an effective scope
M.normalize_ft_scope = function(ft)
  if type(ft) == 'string' and ft ~= '' then
    return { ft }
  end
  if type(ft) == 'table' and next(ft) ~= nil then
    return ft
  end
  return nil
end

---Register a `FileType` autocmd + synchronously call `installer(buf)` for
---already-loaded matching buffers. Installer must catch its own throws —
---a throwing installer strands the autocmd in the caller's group. The
---sweep runs before the id is returned, so callers' self-deleting closures
---can rely on `autocmd_id` still being nil during the sweep. Sweep matches
---by literal filetype; globs (`markdown.*`) work in the autocmd path but
---skip the sweep.
---@param patterns string[]
---@param installer fun(buf: integer)
---@param opts? table Extra opts merged into the autocmd (group, etc.)
---@return integer autocmd_id
M.install_on_ft = function(patterns, installer, opts)
  local pat_set = {}
  local deduped = {}
  for _, p in ipairs(patterns) do
    if not pat_set[p] then
      pat_set[p] = true
      table.insert(deduped, p)
    end
  end
  local autocmd_opts = vim.tbl_extend("force", opts or {}, {
    pattern = deduped,
    callback = function(ev) installer(ev.buf) end,
  })
  local id = vim.api.nvim_create_autocmd("FileType", autocmd_opts)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and pat_set[vim.bo[buf].filetype] then
      installer(buf)
    end
  end
  return id
end

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
  M.install_on_ft(patterns, function(buf)
    local opts = vim.tbl_extend('force', {}, key, { buffer = buf })
    M.try_map(key[1], key[2], opts, src)
  end, { group = state.lazy_group })
end

---@param keys zpack.KeySpec[] As `parse` gives them
---@param src string Plugin identifier for the failure notify
M.apply_keys = function(keys, src)
  for _, key in ipairs(keys) do
    if key[2] ~= nil then
      -- ft scope (lazy.nvim parity): install via FileType autocmd + iterate
      -- already-matching buffers so the real keymap stays buffer-local.
      -- Without this, a global apply_keys could silently overwrite a sibling
      -- plugin that claimed the same lhs under a disjoint ft.
      if M.normalize_ft_scope(key.ft) then
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
