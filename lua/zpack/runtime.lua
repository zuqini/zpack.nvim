if jit then jit.off(true, true) end

local util = require('zpack.utils')

local M = {}

---Batch form of `:packadd!`: one 'runtimepath' write instead of one per plugin,
---which is what dominates startup with many eager plugins. Mirrors
---add_pack_dir_to_rtp() in runtime.c, including the reversed order its repeated
---inserts produce. Layouts it does not cover are left to `:packadd!`.
---@param paths string[] plugin dirs under one pack root, in `:packadd!` call order
---@return boolean added
M.add_packs_to_rtp = function(paths)
  local rtp = vim.go.rtp
  -- A trailing comma's empty entry sits differently in runtime.c
  if #paths == 0 or rtp:find('\\', 1, true) or rtp:sub(-1) == ',' then
    return false
  end

  local fold_case = vim.go.fileignorecase and string.lower or function(path) return path end
  local function resolve(path)
    return fold_case(vim.uv.fs_realpath(path) or path)
  end

  local parent = vim.fs.dirname(paths[1])
  local root = paths[1]
  for _ = 1, 4 do
    root = vim.fs.dirname(root)
  end
  root = resolve(root)

  local entries = vim.split(rtp, ',', { plain = true })
  local active = {}
  local insert_at, first_after
  for i, entry in ipairs(entries) do
    active[fold_case(entry)] = true
    if not first_after then
      -- runtime.c only tests the first "after" in an entry
      local s = entry:find('after', 1, true)
      if s and entry:sub(s - 1, s - 1) == '/' and (s + 5 > #entry or entry:sub(s + 5, s + 5) == '/') then
        first_after = i
      elseif not insert_at then
        -- runtime.c prefixes the cwd to relative and empty entries before resolving them
        if entry:sub(1, 1) ~= '/' then
          return false
        end
        -- runtime.c prefix-matches resolved paths, so a sibling like <root>2 may or may not match
        local resolved = resolve(entry)
        if resolved:sub(1, #root) == root then
          if (resolved .. '/'):sub(#root + 1, #root + 1) ~= '/' then
            return false
          end
          insert_at = i
        end
      end
    end
  end
  if not insert_at then
    return false
  end

  local dirs, after_dirs = {}, {}
  for i = #paths, 1, -1 do
    local path = paths[i]
    -- Whether runtime.c sees `<path>/` as active differs across Neovim versions.
    -- An "after" in the path changes which inserted entries mark the first after dir.
    -- A plugin name with a slash gives that plugin a different pack root.
    if path:find(',', 1, true) or path:find('after', 1, true) or active[fold_case(path) .. '/']
        or vim.fs.dirname(path) ~= parent then
      return false
    end
    if not active[fold_case(path)] then
      dirs[#dirs + 1] = path
      local after = path .. '/after'
      local stat = vim.uv.fs_stat(after)
      if stat and stat.type == 'directory' then
        after_dirs[#after_dirs + 1] = after
      end
    end
  end

  if #dirs == 0 then
    return true
  end

  local res = {}
  vim.list_extend(res, entries, 1, insert_at)
  vim.list_extend(res, dirs)
  vim.list_extend(res, entries, insert_at + 1, first_after and first_after - 1 or #entries)
  vim.list_extend(res, after_dirs)
  vim.list_extend(res, entries, first_after or #entries + 1, #entries)
  vim.api.nvim_set_option_value('runtimepath', table.concat(res, ','), {})
  return true
end

---Native sourcing order: the .vim files, then the .lua ones, ignoring 'wildignore'.
---@param dir string
---@param pattern string under `dir`, without the extension
---@return string[]
local function vim_lua_files(dir, pattern)
  if not vim.uv.fs_stat(dir) then
    return {}
  end
  -- One glob split by extension costs half of a glob per extension, in the same order.
  local vim_files, lua_files = {}, {}
  for _, file in ipairs(vim.fn.glob(dir .. '/' .. pattern .. '.{vim,lua}', true, true)) do
    table.insert(file:sub(-4):lower() == '.vim' and vim_files or lua_files, file)
  end
  return vim.list_extend(vim_files, lua_files)
end

---Per-file pcall so one broken file doesn't skip its siblings.
---@param files string[]
---@param augroup? string
local function source_each(files, augroup)
  for _, file in ipairs(files) do
    -- Separate commands: an `augroup END` chained after a throwing `source` wouldn't run.
    if augroup then vim.cmd.augroup(augroup) end
    local ok, err = pcall(vim.cmd.source, vim.fn.fnameescape(file))
    if augroup then vim.cmd.augroup('END') end
    if not ok then
      util.schedule_notify(("Failed to source %s: %s"):format(file, tostring(err)), vim.log.levels.ERROR)
    end
  end
end

---Track which plugin paths have had their after/plugin/ files sourced
---@type { [string]: true }
local sourced_plugin_paths = {}

---Source after/plugin/ files for a plugin.
---:packadd sources plugin/ files but never after/plugin/ files, and native
---startup only does for what reaches the rtp before v:vim_did_init.
---@param plugin_path string
M.source_after_plugin_files = function(plugin_path)
  if sourced_plugin_paths[plugin_path] or (vim.v.vim_did_init == 0 and vim.o.loadplugins) then
    return
  end
  source_each(vim_lua_files(plugin_path .. '/after/plugin', '**/*'))
  sourced_plugin_paths[plugin_path] = true
end

---Plugin paths whose ftdetect/ files zpack sourced
---@type { [string]: true }
local sourced_ftdetect_paths = {}

---`:packadd` and then after/plugin/, which it never sources, for a plugin that loads
---after startup sourced everything, as lazy.nvim's Loader.packadd does. lazy.nvim
---parity: an error in a plugin/ script is reported and doesn't fail the load, and
---the plugin's other scripts are still sourced. Only `:packadd!` raising, which
---sources nothing, means the plugin itself couldn't be added.
---@param name string
---@param path string
M.packadd_sourcing = function(name, path)
  -- :packadd would source an ftdetect/ zpack sourced already, so a `set filetype=`
  -- there would fire FileType twice. The rest is what :packadd sources.
  if sourced_ftdetect_paths[path] then
    vim.cmd.packadd({ name, bang = true })
    source_each(vim_lua_files(path .. '/plugin', '**/*'))
  else
    local ok, err = pcall(vim.cmd.packadd, { name })
    if not ok then
      vim.cmd.packadd({ name, bang = true })
      util.schedule_notify(("Failed to source plugin/ of %s: %s"):format(name, tostring(err)), vim.log.levels.ERROR)
    end
  end
  M.source_after_plugin_files(path)
end

---Source ftdetect/ files for a lazy plugin so its filetype rules are in
---place before any file is opened. Without this a plugin specced as
---`ft = 'rust'` would never load on `:edit foo.rs`, because the rules that
---set `&ft = 'rust'` live in the plugin's un-sourced `ftdetect/rust.vim`.
---@param plugin_path string
M.source_ftdetect_files = function(plugin_path)
  if sourced_ftdetect_paths[plugin_path] then
    return
  end
  local files = vim_lua_files(plugin_path .. '/ftdetect', '*')
  if #files == 0 then
    return
  end
  -- Before sourcing, so a script there that loads the plugin doesn't source them again here.
  sourced_ftdetect_paths[plugin_path] = true
  -- In `filetypedetect`, as native sourcing does, so the autocmds land there.
  source_each(files, 'filetypedetect')
end

return M
