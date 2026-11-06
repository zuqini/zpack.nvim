if jit then jit.off(true, true) end

local state = require('zpack.state')
local hooks = require('zpack.hooks')
local runtime = require('zpack.runtime')
local util = require('zpack.utils')
local loader = require('zpack.plugin_loader')
local module_loader = require('zpack.module_loader')

local M = {}

---Topological sort for startup plugins respecting dependencies
---Returns sorted packs and a set of lazy dependency srcs that need loading
---@param packs vim.pack.Spec[]
---@return vim.pack.Spec[] sorted_packs
---@return { [string]: string[] } lazy_deps_map (startup_src -> list of lazy dep srcs)
local function toposort_startup_packs(packs)
  local src_to_pack = {}
  for _, pack in ipairs(packs) do
    src_to_pack[pack.src] = pack
  end

  local in_progress = {}
  local done = {}
  local result = {}
  local lazy_deps_map = {}

  local function visit(pack)
    if done[pack.src] then return end

    if in_progress[pack.src] then
      util.schedule_notify(
        ("Circular dependency detected in startup plugins involving: %s"):format(pack.src),
        vim.log.levels.WARN
      )
      return
    end

    in_progress[pack.src] = true

    for _, dep_src in ipairs(util.sorted_dependencies(pack.src)) do
      local dep_pack = src_to_pack[dep_src]
      if dep_pack then
        visit(dep_pack)
      elseif state.src_to_pack_spec[dep_src] then
        loader.warn_if_cond_false(dep_src, pack.src)
        lazy_deps_map[pack.src] = lazy_deps_map[pack.src] or {}
        table.insert(lazy_deps_map[pack.src], dep_src)
      end
    end

    in_progress[pack.src] = nil
    done[pack.src] = true
    result[#result + 1] = pack
  end

  table.sort(packs, util.compare_priority)

  for _, pack in ipairs(packs) do
    visit(pack)
  end

  return result, lazy_deps_map
end

---Add every pack to 'runtimepath' in one write. A pack the batch can't verify
---leaves the whole list to `:packadd!`, whose order in 'runtimepath' follows the
---load order, and which reports the plugin an init hook removed.
---@param packs vim.pack.Spec[]
---@return vim.pack.Spec[] remaining packs that still need `:packadd`
local function add_installed_to_rtp(packs)
  local paths = {}
  for i, pack_spec in ipairs(packs) do
    local entry = state.spec_registry[pack_spec.src]
    local path = entry and entry.plugin and entry.plugin.path
    local stat = path and vim.uv.fs_stat(path)
    if not stat or stat.type ~= 'directory' then
      return packs
    end
    paths[i] = path
  end
  return runtime.add_packs_to_rtp(paths) and {} or packs
end

---@param ctx zpack.ProcessContext
M.process_all = function(ctx)
  table.sort(ctx.src_with_init, util.compare_priority)

  for _, src in ipairs(ctx.src_with_init) do
    hooks.try_call_hook(src, 'init')
  end

  local sorted_packs, lazy_deps_map = toposort_startup_packs(ctx.registered_startup_packs)

  -- Batched plugins are already on 'runtimepath'. pcall packadd for the rest
  -- so one broken plugin doesn't strand every later one. Track failures so
  -- the config loop skips them — otherwise the failed plugin would be marked
  -- loaded and hidden from :ZPack load / :checkhealth.
  local failed_packs = {}
  local to_add = sorted_packs
  if not ctx.load then
    -- `:packadd!` and its batch form put each plugin ahead of the last in
    -- 'runtimepath', the order native startup sources plugin/ in, so add
    -- dependencies last to source them first.
    local reversed = {}
    for i = #sorted_packs, 1, -1 do
      reversed[#reversed + 1] = sorted_packs[i]
      -- An init that required its module has put it on 'runtimepath' already.
      -- Off again, so it comes back in its place.
      local entry = state.spec_registry[sorted_packs[i].src]
      if entry and entry.load_status == "loaded" and entry.plugin then
        vim.opt.rtp:remove(entry.plugin.path)
        vim.opt.rtp:remove(entry.plugin.path .. '/after')
      end
    end
    to_add = add_installed_to_rtp(reversed)
  end
  for _, pack_spec in ipairs(to_add) do
    local entry = state.spec_registry[pack_spec.src]
    local ok, err = pcall(function()
      -- Sourcing now, so lazy dependencies have to come first too. On
      -- 'runtimepath' before them, as in plugin_loader.process_spec.
      if ctx.load and lazy_deps_map[pack_spec.src] and entry.load_status ~= "loaded" then
        vim.cmd.packadd({ pack_spec.name, bang = true })
        for _, dep_src in ipairs(lazy_deps_map[pack_spec.src]) do
          local dep_pack = state.src_to_pack_spec[dep_src]
          if dep_pack then
            loader.try_process_spec(dep_pack)
          end
        end
      end
      -- Sourced already if an init, a script sourced before it, or one of its lazy
      -- dependencies required its module.
      if ctx.load and entry.load_status == "loaded" then
        return
      end
      if ctx.load then
        -- What its scripts load meanwhile, listing it as a dependency, finds it sourced.
        entry.load_status = "sourced"
        runtime.packadd_sourcing(pack_spec.name, entry.plugin.path)
      else
        vim.cmd.packadd({ pack_spec.name, bang = true })
      end
    end)
    if not ok then
      if entry and entry.load_status == "sourced" then
        entry.load_status = "pending"
      end
      failed_packs[pack_spec.src] = true
      util.schedule_notify(("Failed to packadd %s: %s"):format(pack_spec.name or pack_spec.src, tostring(err)), vim.log.levels.ERROR)
    end
  end
  -- Once filetype detection is on, Neovim sources no eager plugin's ftdetect/.
  if not ctx.load and vim.g.did_load_filetypes then
    for _, pack_spec in ipairs(sorted_packs) do
      local entry = state.spec_registry[pack_spec.src]
      -- One an init loaded got its ftdetect/ then, from zpack or Neovim's `filetype on`.
      if not failed_packs[pack_spec.src] and entry.load_status ~= "loaded" then
        runtime.source_ftdetect_files(entry.plugin.path)
      end
    end
  end
  -- On 'runtimepath' now, where require finds their modules first.
  module_loader.initialize_cache(ctx.registered_lazy_packs)

  -- A lazy plugin loading here can list an eager one under its dependencies. That
  -- runs the eager plugin's config and keys, so what it left loaded is finished,
  -- and each plugin here is marked loaded before its config for the same reason.
  local to_bind = {}
  for _, pack_spec in ipairs(sorted_packs) do
    local entry = state.spec_registry[pack_spec.src]
    if not failed_packs[pack_spec.src] and entry.load_status ~= "loaded" then
      for _, dep_src in ipairs(lazy_deps_map[pack_spec.src] or {}) do
        local dep_pack = state.src_to_pack_spec[dep_src]
        if dep_pack then
          loader.try_process_spec(dep_pack, { bang = true })
        end
      end

      if entry.load_status ~= "loaded" then
        local spec = entry.merged_spec --[[@as zpack.Spec]]
        entry.load_status = "loaded"
        if spec.config or entry.has_opts then
          loader.run_config(pack_spec.src, entry.plugin)
        end
        to_bind[#to_bind + 1] = pack_spec
      end
    end
  end

  for _, pack_spec in ipairs(to_bind) do
    loader.bind_keys(state.spec_registry[pack_spec.src], pack_spec.name or pack_spec.src)
  end
end

return M
