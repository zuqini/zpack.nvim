-- Random spec sets for prune_fuzz_test.lua: nested dependencies and specs,
-- shared tables, function-form enabled, module, function and owner imports.
-- Not discovered as a spec, since its filename doesn't end in _test.lua.
local M = {}

local OWNERS = { 'own1', 'own2' }
local MODULE_COUNT = 3

---@return string root Holds the modules the generated imports can find.
function M.fixture()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/config/lua/fz', 'p')
  for i = 1, MODULE_COUNT do
    vim.fn.writefile({}, ('%s/config/lua/fz/m%d.lua'):format(root, i))
  end
  for _, owner in ipairs(OWNERS) do
    vim.fn.mkdir(('%s/own/%s/lua/%s'):format(root, owner, owner), 'p')
    vim.fn.writefile({}, ('%s/own/%s/lua/%s/plugins.lua'):format(root, owner, owner))
  end
  return root
end

---Its own generator, since math.random's sequence isn't a promise across builds.
local function generator(seed)
  local x = seed % 2147483646 + 1
  local function rng(a, b)
    x = x * 16807 % 2147483647
    return a + x % (b - a + 1)
  end
  for _ = 1, 8 do
    rng(1, 2)
  end
  return rng
end

local function generate(seed, calls)
  local rng = generator(seed)
  local modules = {}
  local fn_id = 0

  local function enabled_value()
    if rng(1, 2) == 1 then
      return rng(1, 2) == 1
    end
    fn_id = fn_id + 1
    local id, outcome = fn_id, rng(1, 6)
    return function()
      calls[id] = (calls[id] or 0) + 1
      if outcome == 1 then
        error('boom ' .. id, 0)
      end
      return outcome <= 4
    end
  end

  local gen

  local function import_spec(depth, level)
    local kind = rng(1, 6)
    local spec = {}
    if kind == 1 and level < MODULE_COUNT then
      spec.import = 'fz.m' .. rng(level + 1, MODULE_COUNT)
    elseif kind == 2 then
      spec.import = 'fz.none'
    elseif kind == 3 then
      local specs = gen(depth + 1, level)
      local outcome = rng(1, 6)
      spec.import = function()
        if outcome == 1 then
          error('import boom', 0)
        end
        return outcome == 2 and 'not a table' or specs
      end
    else
      local owner = OWNERS[rng(1, #OWNERS)]
      spec[1] = 'u/' .. owner
      spec.import = owner .. '.plugins'
    end
    if rng(1, 5) == 1 then
      spec.enabled = enabled_value()
    end
    return spec
  end

  gen = function(depth, level)
    local list = {}
    for _ = 1, depth == 0 and rng(4, 9) or rng(0, 3) do
      if depth < 3 and rng(1, 9) == 1 then
        list[#list + 1] = import_spec(depth, level)
      else
        local id = rng(1, 7)
        local form = rng(1, 12)
        local spec = { form == 1 and ('p' .. id) or form == 2 and ('other/p' .. id) or ('u/p' .. id) }
        if rng(1, 5) == 1 then spec.enabled = enabled_value() end
        if rng(1, 7) == 1 then spec.optional = true end
        if rng(1, 8) == 1 then spec.url = 'https://fork/p' .. id end
        if rng(1, 10) == 1 then spec.name = 'n' .. rng(1, 3) end
        if rng(1, 4) == 1 then spec.opts = { a = id, l = { id } } end
        if rng(1, 12) == 1 then spec.opts_extend = { 'l' } end
        if rng(1, 5) == 1 then spec.cmd = 'C' .. id end
        if rng(1, 9) == 1 then spec.keys = { { '<F' .. id .. '>', 'x' } } end
        if rng(1, 12) == 1 then spec.lazy = rng(1, 2) == 1 end
        if rng(1, 12) == 1 then spec.priority = rng(1, 3) * 50 end
        if rng(1, 15) == 1 then spec.dev = true end
        if depth < 3 and rng(1, 2) == 1 then spec.dependencies = gen(depth + 1, level) end
        if depth < 3 and rng(1, 3) == 1 then spec.specs = gen(depth + 1, level) end
        list[#list + 1] = spec
      end
      if #list > 1 and rng(1, 12) == 1 then
        list[#list + 1] = list[rng(1, #list - 1)]
      end
    end
    return list
  end

  for i = MODULE_COUNT, 1, -1 do
    modules['fz.m' .. i] = gen(1, i)
  end
  for _, owner in ipairs(OWNERS) do
    modules[owner .. '.plugins'] = gen(1, MODULE_COUNT)
  end
  return gen(0, 0), modules
end

local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end

local function show(value)
  return vim.inspect(value, { newline = '', indent = '' })
end

local function describe_entry(src, entry, state)
  local specs = {}
  for _, spec in ipairs(entry.sorted_specs or {}) do
    specs[#specs + 1] = spec._import_order .. (spec._is_dependency and 'd' or 't')
  end
  local merged = entry.merged_spec
  local plugin = { name = merged.name, spec = merged }
  local deps = {}
  for _, dep in ipairs(sorted_keys(state.dependency_graph[src] or {})) do
    deps[#deps + 1] = dep .. '@' .. tostring(state.dependency_order[src][dep])
  end
  return table.concat({
    src,
    'specs=' .. table.concat(specs, ','),
    'name=' .. tostring(merged.name),
    'enabled=' .. tostring(entry.enabled_result),
    'has_opts=' .. tostring(entry.has_opts),
    'lazy=' .. tostring(require('zpack.lazy').is_lazy(entry, nil, src)),
    'fields=' .. show({ merged.lazy, merged.cmd, merged.keys, merged.opts_extend, merged.priority }),
    'opts=' .. show(require('zpack.opts').resolve_opts(entry.sorted_specs, plugin, merged.opts_extend)),
    'deps=' .. table.concat(deps, '|'),
    'rdeps=' .. table.concat(sorted_keys(state.reverse_dependency_graph[src] or {}), '|'),
  }, ' ')
end

---Import and resolve one seed's specs, with nothing installed.
---@param seed integer
---@param root string From M.fixture
---@return string outcome Everything resolve_all decided, without its notifications' wording
---@return integer max_calls The most times one function-form `enabled` ran
function M.run(seed, root)
  local state = require('zpack.state')
  local import_run = require('zpack.import_run')
  local merge = require('zpack.merge')
  local utils = require('zpack.utils')

  local calls = {}
  local specs, modules = generate(seed, calls)

  local saved = {
    add = vim.pack.add,
    schedule = vim.schedule,
    stdpath = vim.fn.stdpath,
    notify = utils.notify,
    path = package.path,
  }
  vim.pack.add = function(packs, opts)
    for _, pack in ipairs(packs) do
      opts.load({ spec = pack, path = root .. '/own/' .. pack.name })
    end
  end
  vim.schedule = function(fn) fn() end
  vim.fn.stdpath = function(what) return root .. '/' .. what end
  utils.notify = function() end
  for name, module in pairs(modules) do
    package.loaded[name] = module
  end

  state.config = { defaults = {}, dev = { path = root .. '/dev', fallback = true } }
  state.reset_specs()

  local lines = { 'seed ' .. seed }
  local ok, packs = pcall(function()
    local imported = import_run.import_all(specs, {})
    return merge.resolve_all(imported.graph, imported.enabled_results)
  end)
  lines[#lines + 1] = ok and 'ok' or ('error ' .. tostring(packs))

  if ok then
    for _, src in ipairs(sorted_keys(state.spec_registry)) do
      lines[#lines + 1] = describe_entry(src, state.spec_registry[src], state)
    end
    for _, pack in ipairs(packs) do
      lines[#lines + 1] = ('pack %s %s %s'):format(pack.name, pack.src, tostring(pack.version))
    end
    for _, name in ipairs(sorted_keys(state.name_to_src)) do
      lines[#lines + 1] = ('name %s %s'):format(name, state.name_to_src[name])
    end
  end

  local max_calls = 0
  for _, id in ipairs(sorted_keys(calls)) do
    lines[#lines + 1] = ('enabled %d ran %d'):format(id, calls[id])
    max_calls = math.max(max_calls, calls[id])
  end

  vim.pack.add, vim.schedule, vim.fn.stdpath = saved.add, saved.schedule, saved.stdpath
  utils.notify, package.path = saved.notify, saved.path
  for name in pairs(modules) do
    package.loaded[name] = nil
  end

  return (table.concat(lines, '\n'):gsub(vim.pesc(root), '<root>')), max_calls
end

return M
