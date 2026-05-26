---Input validation for zpack.
---
---Malformed `setup()` options or plugin specs otherwise surface as cryptic
---downstream errors (a `vim.tbl_extend` crash, a nil index deep in the
---loader). This module turns them into actionable, field-named messages.
---
---Each field check runs |vim.validate()| wrapped in `pcall`, so a failure
---is collected as a message string instead of thrown. Callers decide what to
---do with the collected errors — `setup()` aborts on config errors, `import`
---warns on spec errors, and `health` reports them. This module is a leaf
---(no `require`s) so |zpack.health| can reuse it freely.

local M = {}

---@alias zpack.validate.Type string|string[]

---Run one vim.validate check, appending a message to `errors` on failure.
---@param errors string[]
---@param name string Field path, e.g. 'defaults.confirm'
---@param value any
---@param validator zpack.validate.Type
local function check(errors, name, value, validator)
  -- optional = true: every config/spec field is optional (nil means unset).
  local ok, err = pcall(vim.validate, name, value, validator, true)
  if not ok then
    errors[#errors + 1] = err
  end
end

---Validate the options table passed to `zpack.setup()`.
---
---Validates the raw `opts` (rather than the post-merge config) because the
---per-section `vim.tbl_extend('force', ...)` merges in `setup()` themselves
---throw when handed a non-table — validation has to run first. It is also
---safe to call on a merged `zpack.Config`: the legacy/`spec` fields are
---simply absent and pass as optional, which is how |zpack.health| reuses it.
---
---`cmd_name`/`cmd_prefix` are intentionally excluded: `zpack.commands`
---validates them (type *and* naming rule) and degrades gracefully, so
---re-checking here would only double up the notification.
---@param opts any The table passed to `zpack.setup()`
---@return string[] errors Field-path messages; empty when valid
function M.validate_config(opts)
  if type(opts) ~= 'table' then
    return { ('zpack.setup: expected table, got %s'):format(type(opts)) }
  end

  local errors = {}
  check(errors, 'spec', opts.spec, 'table')
  check(errors, 'defaults', opts.defaults, 'table')
  check(errors, 'performance', opts.performance, 'table')
  check(errors, 'profiling', opts.profiling, 'table')
  check(errors, 'dev', opts.dev, 'table')

  if type(opts.dev) == 'table' then
    check(errors, 'dev.path', opts.dev.path, 'string')
    check(errors, 'dev.fallback', opts.dev.fallback, 'boolean')
  end

  if type(opts.defaults) == 'table' then
    check(errors, 'defaults.cond', opts.defaults.cond, { 'boolean', 'function' })
    check(errors, 'defaults.confirm', opts.defaults.confirm, 'boolean')
    check(errors, 'defaults.lazy', opts.defaults.lazy, 'boolean')
    -- `boolean` accepts `version = false`, the no-default opt-out handled in utils.normalize_version.
    check(errors, 'defaults.version', opts.defaults.version, { 'string', 'table', 'boolean' })
  end
  if type(opts.performance) == 'table' then
    check(errors, 'performance.vim_loader', opts.performance.vim_loader, 'boolean')
  end
  if type(opts.profiling) == 'table' then
    check(errors, 'profiling.loader', opts.profiling.loader, 'boolean')
    check(errors, 'profiling.require', opts.profiling.require, 'boolean')
  end

  -- Legacy options: deprecated but still honored, so still type-checked.
  check(errors, 'confirm', opts.confirm, 'boolean')
  check(errors, 'disable_vim_loader', opts.disable_vim_loader, 'boolean')
  check(errors, 'plugins_dir', opts.plugins_dir, 'string')

  return errors
end

---Expected type for each named `zpack.Spec` field. Polymorphic fields (event,
---cmd, ft, keys, version, dependencies) are checked loosely against the union
---of their base types — enough to catch `event = 123` without false positives
---on the function/table forms. The positional `[1]` source is checked
---separately in `validate_spec` so this table stays string-keyed.
---@type table<string, zpack.validate.Type>
local SPEC_FIELD_TYPES = {
  src = 'string',
  dir = 'string',
  url = 'string',
  name = 'string',
  main = 'string',
  import = { 'string', 'function' },
  sem_version = 'string',
  branch = 'string',
  tag = 'string',
  commit = 'string',
  lazy = 'boolean',
  module = 'boolean',
  priority = 'number',
  init = 'function',
  enabled = { 'boolean', 'function' },
  cond = { 'boolean', 'function' },
  build = { 'string', 'function', 'table', 'boolean' },
  config = { 'function', 'boolean' },
  opts = { 'table', 'function' },
  event = { 'string', 'table', 'function' },
  cmd = { 'string', 'table', 'function' },
  ft = { 'string', 'table', 'function' },
  keys = { 'string', 'table', 'function' },
  pattern = { 'string', 'table' },
  version = { 'string', 'table', 'boolean' },
  dependencies = { 'string', 'table' },
  specs = 'table',
  pin = 'boolean',
  optional = 'boolean',
  dev = 'boolean',
  deactivate = 'function',
}

---`SPEC_FIELD_TYPES` keys in a stable sort order, so a spec with several bad
---fields reports them deterministically. The sort is invariant — done once.
local SORTED_SPEC_FIELDS = vim.tbl_keys(SPEC_FIELD_TYPES)
table.sort(SORTED_SPEC_FIELDS)

---Validate a single plugin spec.
---@param spec any A `zpack.Spec` entry
---@return string[] errors Field-named messages; empty when valid
function M.validate_spec(spec)
  if type(spec) ~= 'table' then
    return { ('expected spec table, got %s'):format(type(spec)) }
  end

  local errors = {}
  check(errors, '[1]', spec[1], 'string')
  for _, field in ipairs(SORTED_SPEC_FIELDS) do
    check(errors, field, spec[field], SPEC_FIELD_TYPES[field])
  end

  -- Every field above is optional, so a spec with no source at all passes
  -- every type check yet cannot be loaded — `import.normalize_source` would
  -- otherwise fail and the spec would silently never import. An `import`
  -- spec recurses into a directory and legitimately carries no source.
  if spec.import == nil and spec[1] == nil and spec.src == nil
      and spec.url == nil and spec.dir == nil then
    errors[#errors + 1] = 'spec has no plugin source — set one of [1], src, url, dir, or import'
  end

  return errors
end

---Best-effort human-readable identifier for a spec, for error messages.
---@param spec table
---@return string
function M.spec_label(spec)
  return spec[1] or spec.src or spec.url or spec.dir or spec.name or spec.import or '<unknown>'
end

return M
