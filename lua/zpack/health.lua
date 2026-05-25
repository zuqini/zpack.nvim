---:checkhealth zpack — diagnostics for a zpack setup.
---
---Surfaces, in the editor, what a misconfigured setup otherwise only reveals
---as a runtime error: an unsupported Neovim version, a missing `vim.pack`,
---`setup()` never being called, malformed config, deprecated options still
---in use, or specs that never resolved.
---
---Discovered automatically by `:checkhealth zpack` — nothing registers it.

local state = require('zpack.state')

local M = {}

local ISSUES_URL = 'https://github.com/zuqini/zpack.nvim/issues'

local MINIMAL_CONFIG = table.concat({
  "require('zpack').setup({",
  '  spec = {',
  "    { 'user/plugin' },",
  '  },',
  '})',
}, '\n')

local function check_environment()
  vim.health.start('Environment')

  if vim.fn.has('nvim-0.12') == 1 then
    vim.health.ok('Neovim ' .. tostring(vim.version()) .. ' (>= 0.12.0 required)')
  else
    vim.health.error('Neovim 0.12.0+ is required; zpack will not load on this version')
  end

  if type(vim.pack) == 'table' and type(vim.pack.add) == 'function' then
    vim.health.ok('vim.pack is available')
  else
    vim.health.error('vim.pack is not available — zpack is a thin layer over it', {
      'Build or install a Neovim that ships vim.pack (0.12.0+).',
    })
  end
end

local function check_setup()
  vim.health.start('Setup')

  if state.is_setup then
    vim.health.ok('setup() has been called')
  else
    vim.health.warn('setup() has not been called — zpack is inactive', {
      'Call it from your config:',
      MINIMAL_CONFIG,
    })
  end
end

local function check_config()
  vim.health.start('Configuration')

  if not state.is_setup or not state.config then
    vim.health.info('No configuration to check (setup() has not run)')
    return
  end

  local errors = require('zpack.validate').validate_config(state.config)
  if #errors == 0 then
    vim.health.ok('setup() options are valid')
  else
    for _, err in ipairs(errors) do
      vim.health.error('Invalid option: ' .. err)
    end
  end

  if #state.deprecations == 0 then
    vim.health.ok('No deprecated options in use')
  else
    local deprecation = require('zpack.deprecation')
    -- A replacement snippet can span several lines; split it so each renders
    -- as its own advice line instead of one bullet with embedded newlines.
    local function advice(entry)
      local lines = { entry.message }
      vim.list_extend(lines, vim.split(entry.replacement, '\n', { trimempty = true }))
      return lines
    end
    for _, key in ipairs(state.deprecations) do
      local removed = deprecation.removed[key]
      local deprecated = deprecation.deprecated[key]
      if removed then
        vim.health.warn(('Removed option still passed: %s'):format(key), advice(removed))
      elseif deprecated then
        vim.health.warn(('Deprecated option in use: %s'):format(key), advice(deprecated))
      else
        -- cmd_prefix is in deprecated_option_keys but has no static
        -- removed/deprecated entry (its notice is computed) — warn bare.
        vim.health.warn(('Deprecated option in use: %s'):format(key))
      end
    end
  end
end

local function check_plugins()
  vim.health.start('Plugins')

  if not state.is_setup then
    vim.health.info('No plugins registered (setup() has not run)')
    return
  end

  local plugins = require('zpack.api').get_plugins()
  if #plugins == 0 then
    vim.health.warn('No plugins registered', {
      'If you expected plugins here, check that lua/plugins/ contains spec',
      'files, or that you passed spec = { ... } to setup().',
    })
    return
  end

  local counts = { loaded = 0, loading = 0, pending = 0, disabled = 0, installing = 0 }
  local lazy_count = 0
  for _, plugin in ipairs(plugins) do
    counts[plugin.status] = (counts[plugin.status] or 0) + 1
    if plugin.lazy then
      lazy_count = lazy_count + 1
    end
  end

  vim.health.ok(('%d plugin(s) registered'):format(#plugins))
  -- Status counts partition #plugins; lazy is orthogonal (a lazy plugin is
  -- also loaded/pending/...), so it is reported on its own line below.
  vim.health.info(('loaded: %d   pending: %d'):format(counts.loaded, counts.pending))

  if counts.loading > 0 then
    vim.health.info(('loading: %d'):format(counts.loading))
  end
  if counts.installing > 0 then
    local cmd_name = (state.config and state.config.cmd_name) or 'ZPack'
    vim.health.warn(('installing: %d — not yet on disk'):format(counts.installing), {
      ('Restart Neovim, or run :%s update, once installation finishes.'):format(cmd_name),
    })
  end
  if counts.disabled > 0 then
    vim.health.info(('disabled by cond: %d'):format(counts.disabled))
  end
  if lazy_count > 0 then
    vim.health.info(('lazy: %d'):format(lazy_count))
  end

  local dev_count = 0
  for _, entry in pairs(state.spec_registry) do
    if entry.merged_spec and entry.merged_spec.dev then
      dev_count = dev_count + 1
    end
  end
  if dev_count > 0 then
    local dev = state.config.dev or {}
    vim.health.info(('dev: %d plugin(s) → %s (fallback: %s)'):format(
      dev_count, dev.path or '~/projects', tostring(dev.fallback or false)))
  end
end

local function check_bug_report()
  vim.health.start('Reporting a bug')
  vim.health.info(table.concat({
    'Reproduce with a minimal config, then open an issue at',
    ISSUES_URL .. ' including:',
    '  - the minimal config below (edited to trigger the bug)',
    '  - the full :checkhealth zpack output',
    '  - your Neovim version (nvim --version)',
    '',
    'Minimal config — save as repro.lua, run with: nvim -u repro.lua',
    '',
    MINIMAL_CONFIG,
  }, '\n'))
end

---Entry point for `:checkhealth zpack`.
function M.check()
  check_environment()
  check_setup()
  check_config()
  check_plugins()
  check_bug_report()
end

return M
