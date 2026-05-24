local util = require('zpack.utils')
local state = require('zpack.state')
local keymap = require('zpack.keymap')
local loader = require('zpack.plugin_loader')

local M = {}

---@param ft any
---@return string
local ft_key_part = function(ft)
  if type(ft) ~= 'string' and type(ft) ~= 'table' then
    return ''
  end
  local ft_list = util.normalize_string_list(ft) --[[@as string[] ]]
  local sorted = { unpack(ft_list) }
  table.sort(sorted)
  return '-ft:' .. table.concat(sorted, ',')
end

---Create a unique key identifier from lhs, mode, and (optional) ft scope.
---@param lhs string The key mapping (e.g., "<leader>ff")
---@param mode string The mode (e.g., "n", "v")
---@param ft string|string[]|nil Optional filetype scope
---@return string Unique identifier
local create_key_id = function(lhs, mode, ft)
  return lhs .. '-' .. mode .. ft_key_part(ft)
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
---@param buf? integer
local install_proxy = function(key_info, buf)
  local lhs = key_info.key_spec[1]
  local key_spec = key_info.key_spec
  keymap.map(lhs, function()
    -- Mirror the install scope: a global proxy must delete the global
    -- mapping; a buffer-local proxy must delete the buffer-local one
    -- (otherwise vim.keymap.del finds nothing and the stale buffer-local
    -- proxy fires forever on the re-fed lhs).
    if buf then
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
    buffer = buf,
  })
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

---Install a (buffer-local when `buf` is non-nil) real `<Nop>` keymap from
---the user's KeySpec. `expr` is stripped so vim does not eval the literal
---string `<Nop>` as an expression; `keymap.map` nulls `replace_keycodes`
---when `expr` is unset, so it does not need a separate strip.
---@param key zpack.KeySpec
---@param src string
---@param buf? integer
local function install_nop(key, src, buf)
  local nop_opts = vim.deepcopy(key)
  nop_opts.expr = nil
  nop_opts.buffer = buf
  local ok, err = pcall(keymap.map, key[1], '<Nop>', nop_opts)
  if not ok then
    util.schedule_notify(
      ("Failed to map %s for %s: %s"):format(key[1], src, tostring(err)),
      vim.log.levels.ERROR
    )
  end
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

        -- Only string/table ft is honored as a scope; anything else is a
        -- type error best treated as "no ft" so the proxy/nop stays global.
        local ft_scope = (type(key.ft) == 'string' or type(key.ft) == 'table') and key.ft or nil
        local src = pack_spec.name or pack_spec.src

        -- <Nop> rhs never needs the proxy: install as a real no-op so the
        -- key acts as a true no-op without loading the plugin. ft-scoped
        -- <Nop> installs buffer-locally on matching FileType so the
        -- suppression is scoped, matching lazy.nvim's ft-on-Nop behavior.
        if is_nop_rhs(key[2]) then
          if ft_scope then
            util.autocmd("FileType", function(ev)
              install_nop(key, src, ev.buf)
            end, {
              group = state.lazy_group,
              pattern = util.normalize_string_list(ft_scope),
            })
          else
            install_nop(key, src, nil)
          end
        else
          for _, m in ipairs(modes) do
            local key_id = create_key_id(lhs, m, ft_scope)
            if not key_to_info[key_id] then
              key_to_info[key_id] = {
                split_mode = m,
                pack_specs = {},
                key_spec = key,
                ft = ft_scope,
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
      -- ft-scoped: install the proxy buffer-locally each time a matching
      -- buffer enters the filetype. Once every claiming plugin has loaded,
      -- the autocmd no-ops; the global keymap from apply_keys handles
      -- subsequent presses.
      util.autocmd("FileType", function(ev)
        if not any_pack_pending(key_info) then
          return
        end
        install_proxy(key_info, ev.buf)
      end, {
        group = state.lazy_group,
        pattern = util.normalize_string_list(key_info.ft),
      })
    else
      install_proxy(key_info, nil)
    end
  end
end

return M
