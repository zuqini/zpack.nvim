local util = require('zpack.utils')
local state = require('zpack.state')
local keymap = require('zpack.keymap')
local loader = require('zpack.plugin_loader')

local M = {}

---@param ft any
---@return string
local ft_key_part = function(ft)
  local ft_list = util.normalize_ft_scope(ft)
  if not ft_list then
    return ''
  end
  local sorted = vim.list_slice(ft_list)
  table.sort(sorted)
  return '-ft:' .. table.concat(sorted, ',')
end

---@param buffer any
---@return string
local buffer_key_part = function(buffer)
  if buffer == nil then
    return ''
  end
  -- lazy.nvim parity: `buffer = true` and `buffer = 0` both mean "current
  -- buffer" — coerce so they share an entry.
  local b = buffer == true and 0 or buffer
  return '-buf:' .. tostring(b)
end

---@param lhs string
---@param mode string
---@param ft string|string[]|nil
---@param buffer integer|boolean|nil
---@return string
local create_key_id = function(lhs, mode, ft, buffer)
  return lhs .. '-' .. mode .. ft_key_part(ft) .. buffer_key_part(buffer)
end

---@param rhs any
---@return boolean
local is_nop_rhs = function(rhs)
  return type(rhs) == 'string' and (rhs == '' or rhs:lower() == '<nop>')
end

---Check whether a mapping for `lhs` is currently installed in `mode`.
---Abbreviation modes (ia/ca/!a) are queried via maparg's {abbr}=true on the
---base mode, since maparg's {mode} arg does not accept the 'a' suffix.
---@param lhs string
---@param mode string
---@return boolean
local mapping_present = function(lhs, mode)
  if mode:sub(-1) == 'a' then
    local base = mode:sub(1, -2)
    local m = vim.fn.maparg(lhs, base, true, true)
    return type(m) == 'table' and next(m) ~= nil
  end
  return vim.fn.maparg(lhs, mode) ~= ''
end

---Install a (buffer-local when `buf` is non-nil) proxy that lazy-loads the
---plugins claiming this lhs on first press.
---@param key_info table
---@param src string
---@param buf? integer
local install_proxy = function(key_info, src, buf)
  local lhs = key_info.key_spec[1]
  local key_spec = key_info.key_spec
  -- ft path forces buffer-local in `buf`; otherwise honor the user's
  -- `key_spec.buffer` (lazy.nvim parity for unscoped buffer-local keys).
  local proxy_buffer = buf or key_spec.buffer
  keymap.try_map(lhs, function()
    -- Mirror the install scope: a global proxy must delete the global
    -- mapping; a buffer-local proxy must delete the buffer-local one
    -- (otherwise vim.keymap.del finds nothing and the stale buffer-local
    -- proxy fires forever on the re-fed lhs).
    if proxy_buffer then
      pcall(vim.keymap.del, key_info.split_mode, lhs, { buffer = 0 })
    else
      pcall(vim.keymap.del, key_info.split_mode, lhs)
    end
    local any_ok = false
    for _, pack_spec in ipairs(key_info.pack_specs) do
      if loader.try_process_spec(pack_spec) then
        any_ok = true
      end
    end
    -- Proxy already self-deleted; if no plugin loaded, feeding lhs would
    -- type it literally into the buffer.
    if not any_ok then
      return
    end
    -- A malformed key spec is pcall-swallowed by apply_keys, so the lhs
    -- may end up unmapped. Skip the re-feed unless the spec expected a
    -- real keymap — a nil-rhs spec (e.g. `{ 'i', mode = 'o' }`) is the
    -- "load + fall through to native binding" pattern and must still feed.
    if key_info.key_spec[2] ~= nil
      and not mapping_present(lhs, key_info.split_mode) then
      return
    end
    -- Abbreviation modes (ia/ca/!a) need <C-]> appended on the re-fed lhs
    -- to actually expand the abbreviation on the first triggering press.
    local feed_lhs = key_info.split_mode:sub(-1) == 'a' and (lhs .. '<C-]>') or lhs
    -- 'i' prepends to typeahead so queued keys (e.g. trailing 'b' in 'vib')
    -- still run after the re-fed lhs. <Ignore> bridges the expr/typeahead
    -- boundary without disturbing operator-pending state.
    vim.api.nvim_feedkeys(vim.keycode('<Ignore>' .. feed_lhs), 'i', false)
  end, {
    desc = key_spec.desc,
    mode = key_info.split_mode,
    -- expr is forced on regardless of key_spec.expr so the proxy preserves
    -- operator-pending state across the lazy-load trigger (issue #26). The
    -- real keymap installed on load honors the user's key_spec.expr.
    -- Tradeoff: expr callbacks run under textlock, so configs that mutate
    -- text/windows synchronously during the first triggering press hit
    -- E565 and must defer with vim.schedule().
    expr = true,
    nowait = key_spec.nowait,
    silent = key_spec.silent,
    remap = key_spec.remap,
    noremap = key_spec.noremap,
    buffer = proxy_buffer,
  }, src)
end

---@param key_info table
local function any_pack_pending(key_info)
  for _, pack_spec in ipairs(key_info.pack_specs) do
    local entry = state.spec_registry[pack_spec.src]
    if entry and entry.load_status == 'pending' then
      return true
    end
  end
  return false
end

---Install a (buffer-local when `buf` is non-nil) real `<Nop>` keymap.
---`expr`/`replace_keycodes` are stripped (vim.keymap.set raises when
---`replace_keycodes` is set without `expr`).
---@param key zpack.KeySpec
---@param src string
---@param buf? integer
local function install_nop(key, src, buf)
  local nop_opts = vim.deepcopy(key)
  nop_opts.expr = nil
  nop_opts.replace_keycodes = nil
  -- ft path forces `buf`; otherwise leave the user's `key.buffer` intact
  -- so e.g. `{ 'X', '<Nop>', buffer = true }` stays scoped.
  if buf then
    nop_opts.buffer = buf
  end
  keymap.try_map(key[1], '<Nop>', nop_opts, src)
end

---@param registered_pack_specs vim.pack.Spec[]
M.setup = function(registered_pack_specs)
  local key_to_info = {}
  for _, pack_spec in ipairs(registered_pack_specs) do
    local registry_entry = state.spec_registry[pack_spec.src]
    local spec = registry_entry.merged_spec --[[@as zpack.Spec]]
    local plugin = registry_entry.plugin

    local keys_value = util.try_resolve_field(spec.keys, plugin, pack_spec.name or pack_spec.src, 'keys')
    if keys_value then
      local keys = util.normalize_keys(keys_value) --[[@as zpack.KeySpec[] ]]
      for _, key in ipairs(keys) do
        local lhs = key[1]
        local mode = key.mode or 'n'
        local modes = util.normalize_string_list(mode) --[[@as string[] ]]

        -- Empty ft → no scope, so the autocmd doesn't register an
        -- unmatchable empty pattern list and silently drop the key.
        local ft_patterns = util.normalize_ft_scope(key.ft)
        local src = pack_spec.name or pack_spec.src

        -- <Nop> rhs never needs the proxy: install as a real no-op so the
        -- key acts as a true no-op without loading the plugin. ft-scoped
        -- <Nop> installs buffer-locally on matching FileType so the
        -- suppression is scoped, matching lazy.nvim's ft-on-Nop behavior.
        if is_nop_rhs(key[2]) then
          if ft_patterns then
            util.install_on_ft(ft_patterns, function(buf)
              install_nop(key, src, buf)
            end, { group = state.lazy_group })
          else
            install_nop(key, src, nil)
          end
        else
          for _, m in ipairs(modes) do
            local key_id = create_key_id(lhs, m, ft_patterns, key.buffer)
            if not key_to_info[key_id] then
              key_to_info[key_id] = {
                split_mode = m,
                pack_specs = {},
                key_spec = key,
                src = src,
                ft = ft_patterns,
              }
            end
            table.insert(key_to_info[key_id].pack_specs, pack_spec)
          end
        end
      end
    end
  end

  -- Create keymaps
  for _, key_info in pairs(key_to_info) do
    if key_info.ft then
      -- Proxy self-deletes once every claiming plugin has loaded —
      -- apply_keys's own FileType autocmd takes over for future buffers.
      -- During the sweep all packs are still `pending`, so the self-delete
      -- branch never fires before `autocmd_id` is assigned.
      local autocmd_id
      autocmd_id = util.install_on_ft(
        key_info.ft,
        function(buf)
          if not any_pack_pending(key_info) then
            if autocmd_id then
              pcall(vim.api.nvim_del_autocmd, autocmd_id)
              autocmd_id = nil
            end
            return
          end
          install_proxy(key_info, key_info.src, buf)
        end,
        { group = state.lazy_group }
      )
    else
      install_proxy(key_info, key_info.src, nil)
    end
  end
end

return M
