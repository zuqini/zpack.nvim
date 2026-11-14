if jit then jit.off(true, true) end

local M = {}

local triggers = {
  FileType = "BufReadPost",
  BufReadPost = "BufReadPre",
}

-- Events matched by literal pattern (not buffer state) must be re-fired
-- with `pattern = <matched value>`; buffer dispatch never matches a
-- literal-pattern autocmd (e.g. `User LspAttach` handlers).
local PATTERN_DISPATCH_EVENTS = {
  User = true,
  Signal = true,
  OptionSet = true,
  CmdUndefined = true,
  ColorScheme = true,
  RemoteReply = true,
  ChanInfo = true,
  ChanOpen = true,
  MenuPopup = true,
  SourcePre = true,
  SourcePost = true,
  SourceCmd = true,
  TermResponse = true,
  ModeChanged = true,
  DirChanged = true,
  DirChangedPre = true,
  CmdlineEnter = true,
  CmdlineLeave = true,
  CmdlineChanged = true,
  RecordingEnter = true,
  RecordingLeave = true,
  QuickFixCmdPre = true,
  QuickFixCmdPost = true,
}

---@param event string
---@return string[]
local function build_chain(event)
  local chain = {}
  local current = event
  while current do
    table.insert(chain, 1, current)
    current = triggers[current]
  end
  return chain
end

---@param event string
---@return table<string, table<number, boolean>?>
M.snapshot = function(event)
  local chain = build_chain(event)
  local snap = {}
  for _, ev in ipairs(chain) do
    if ev ~= "FileType" then
      local existing = {}
      for _, au in ipairs(vim.api.nvim_get_autocmds({ event = ev })) do
        if au.group then
          existing[au.group] = true
        end
      end
      snap[ev] = existing
    end
  end
  return snap
end

---@param ev string
---@param target table `{ buffer = buf }` or `{ pattern = pat }` — mutually exclusive in `nvim_exec_autocmds`
---@param ev_data? any
---@param snap table<string, table<number, boolean>?>
local function fire_new_groups(ev, target, ev_data, snap)
  local pre_existing = snap[ev]
  if pre_existing == nil then
    pcall(vim.api.nvim_exec_autocmds, ev, vim.tbl_extend('force', target, {
      data = ev_data,
      modeline = false,
    }))
    return
  end

  -- Dedup by augroup id: `nvim_exec_autocmds` with `group = X` fires every
  -- autocmd in X, so only dispatch once per group. Ungrouped autocmds are
  -- skipped — Neovim exposes no stable per-handler identity to dedup
  -- against, and plugins are expected to use their own augroup.
  local fired = {}
  for _, au in ipairs(vim.api.nvim_get_autocmds({ event = ev })) do
    if au.group and not pre_existing[au.group] and not fired[au.group] then
      fired[au.group] = true
      pcall(vim.api.nvim_exec_autocmds, ev, vim.tbl_extend('force', target, {
        group = au.group_name,
        data = ev_data,
        modeline = false,
      }))
    end
  end
end

---Re-fire autocmds the loaded plugin registered, plus chained predecessor
---events (e.g. FileType triggers BufReadPost/BufReadPre).
---@param ev table The autocmd callback's event arg (`.event`, `.buf`, `.data`, `.match`)
---@param snapshot table<string, table<number, boolean>?>
M.exec = function(ev, snapshot)
  local chain = build_chain(ev.event)

  for i, chain_ev in ipairs(chain) do
    local is_origin = (i == #chain)
    if is_origin and PATTERN_DISPATCH_EVENTS[chain_ev] then
      -- Fall back to '*' so `User '*'` handlers fire when the trigger came
      -- through with no pattern (e.g. `nvim_exec_autocmds('User', {})`).
      local pat = (ev.match ~= nil and ev.match ~= '') and ev.match or '*'
      fire_new_groups(chain_ev, { pattern = pat }, ev.data, snapshot)
    elseif vim.api.nvim_buf_is_valid(ev.buf) then
      fire_new_groups(chain_ev, { buffer = ev.buf }, is_origin and ev.data or nil, snapshot)
    end
  end
end

return M
