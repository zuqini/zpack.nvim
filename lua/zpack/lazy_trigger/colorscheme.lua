if jit then jit.off(true, true) end

local state = require('zpack.state')
local loader = require('zpack.plugin_loader')

local M = {}

---@param name string
---@return boolean
local function on_runtimepath(name)
  return #vim.api.nvim_get_runtime_file('colors/' .. name .. '.vim', false) > 0
      or #vim.api.nvim_get_runtime_file('colors/' .. name .. '.lua', false) > 0
end

---@param pack_specs vim.pack.Spec[]
---@param name string
---@return vim.pack.Spec?
local function holder(pack_specs, name)
  for _, pack_spec in ipairs(pack_specs) do
    local entry = state.spec_registry[pack_spec.src]
    local path = entry and entry.load_status == 'pending' and entry.plugin and entry.plugin.path
    if path and (vim.uv.fs_stat(path .. '/colors/' .. name .. '.lua')
          or vim.uv.fs_stat(path .. '/colors/' .. name .. '.vim')) then
      return pack_spec
    end
  end
end

---lazy.nvim parity: `:colorscheme` loads the pending plugin holding the scheme first.
---'packpath' alone finds its colors/ file, but not the autoload/ or lua/ that file uses.
---An eager one is on 'runtimepath' before its config, which lazy.nvim's isn't, so the name there doesn't stop it.
---@param eager_packs vim.pack.Spec[] Ahead of lazy ones: they load anyway, so a lazy one holding the same scheme stays lazy
---@param lazy_packs vim.pack.Spec[]
M.setup = function(eager_packs, lazy_packs)
  vim.api.nvim_create_autocmd('ColorSchemePre', {
    group = state.lazy_group,
    callback = function(ev)
      local pack_spec = holder(eager_packs, ev.match) or not on_runtimepath(ev.match) and holder(lazy_packs, ev.match)
      if pack_spec then
        loader.try_process_spec(pack_spec, { bang = true })
      end
    end,
  })
end

return M
