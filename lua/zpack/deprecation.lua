-- Deprecation and removal notices for zpack.
--
-- This custom layer is kept deliberately rather than migrated to
-- vim.deprecate(); the evaluation:
--   * Legacy :<prefix><Suffix> commands notify on EVERY invocation (see
--     notify_legacy_command) so a notice that scrolled past is not lost.
--     vim.deprecate() routes through vim.notify_once and would dedup it,
--     conflicting with that intent.
--   * `add`/`auto_import` are already removed, not pending removal, so
--     vim.deprecate()'s "will be removed in version X" framing is wrong.
--   * The option notices below carry copy-paste replacement snippets that
--     vim.deprecate()'s single-line `alternative` argument cannot express.
-- Deprecated options actually in use are also surfaced by :checkhealth zpack.

local utils = require('zpack.utils')

local M = {}

-- Every M.removed/M.deprecated entry must carry both `message` and
-- `replacement` strings: notify_removed/notify_deprecated format them
-- unguarded, and :checkhealth zpack splits `replacement` into advice lines.
M.removed = {
  add = {
    message = "zpack.add() has been removed. Pass specs directly to setup():",
    replacement = [[
require('zpack').setup({ { 'user/plugin' } })
require('zpack').setup({ spec = { { 'user/plugin' } } }) -- or via the spec field
]]
  },
  auto_import = {
    message = "auto_import option has been removed. Pass specs directly to setup():",
    replacement = [[
require('zpack').setup({ { 'user/plugin' } })
require('zpack').setup({ spec = { { 'user/plugin' } } }) -- or via the spec field
]]
  },
}

M.deprecated = {
  confirm = {
    message = "opts.confirm is deprecated. Use opts.defaults.confirm instead:",
    replacement = "require('zpack').setup({ defaults = { confirm = false } })",
  },
  disable_vim_loader = {
    message = "opts.disable_vim_loader is deprecated. Use opts.performance.vim_loader instead:",
    replacement = "require('zpack').setup({ performance = { vim_loader = false } })",
  },
  plugins_dir = {
    message = "opts.plugins_dir is deprecated. Use { import = 'dir' } in spec instead:",
    replacement = "require('zpack').setup({ { import = 'plugins' } })",
  },
}

-- setup() option keys that are deprecated or removed, for :checkhealth zpack
-- to report when one is still passed. Kept here as the single authoritative
-- list rather than derived from M.removed/M.deprecated: M.removed also holds
-- `add` (a removed function, not an option key) and `cmd_prefix` has only
-- computed notices with no static entry — so the key set is neither table's
-- keys. Update this list whenever M.removed/M.deprecated gains an option.
M.deprecated_option_keys = {
  'cmd_prefix', 'confirm', 'disable_vim_loader', 'plugins_dir', 'auto_import',
}

M.notify_removed = function(key)
  local entry = M.removed[key]
  if not entry then return end
  utils.schedule_notify(
    ("REMOVED: %s\n\n%s"):format(entry.message, entry.replacement),
    vim.log.levels.WARN
  )
end

M.notify_deprecated = function(key)
  local entry = M.deprecated[key]
  if not entry then return end
  utils.schedule_notify(
    ("DEPRECATED: %s\n\n%s"):format(entry.message, entry.replacement),
    vim.log.levels.WARN
  )
end

-- Warns that a legacy :<prefix><Suffix> command is deprecated in favor of
-- the :<cmd_name> <subcommand> form. Fires on every invocation so the notice
-- is not missed if an earlier one scrolled past.
M.notify_legacy_command = function(legacy_name, cmd_name, sub_name)
  utils.schedule_notify(
    ("DEPRECATED: :%s is deprecated. Use :%s %s instead."):format(legacy_name, cmd_name, sub_name),
    vim.log.levels.WARN
  )
end

-- Computed because it must name the user's resolved cmd_name. Not deduped:
-- the only caller is setup_legacy's invalid-prefix branch, which runs once.
M.notify_cmd_prefix_deprecated = function(cmd_name)
  utils.schedule_notify(
    ("DEPRECATED: opts.cmd_prefix is deprecated. The legacy prefixed commands are "
      .. "deprecated aliases for the :%s subcommands; drop cmd_prefix and use "
      .. ":%s <subcommand> instead."):format(cmd_name, cmd_name),
    vim.log.levels.WARN
  )
end

return M
