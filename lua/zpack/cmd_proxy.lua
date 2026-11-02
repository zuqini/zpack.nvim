if jit then jit.off(true, true) end

local M = {}

---The proxy commands of each lazy plugin, by source.
---@type { [string]: string[] }
local proxies_of = {}
---The sources still waiting on each live proxy command.
---@type { [string]: { [string]: true } }
local claimants_of = {}

M.DESC = 'zpack: load the plugin that provides this command'

---Record a proxy that was just created, for the plugins it loads.
---@param cmd string
---@param pack_specs vim.pack.Spec[]
M.claim = function(cmd, pack_specs)
  claimants_of[cmd] = {}
  for _, pack_spec in ipairs(pack_specs) do
    claimants_of[cmd][pack_spec.src] = true
    proxies_of[pack_spec.src] = proxies_of[pack_spec.src] or {}
    table.insert(proxies_of[pack_spec.src], cmd)
  end
end

---@param cmd string
M.drop = function(cmd)
  if claimants_of[cmd] then
    claimants_of[cmd] = nil
    pcall(vim.api.nvim_del_user_command, cmd)
  end
end

---Drop the proxies only `src` still waits on. Another pending plugin keeps its
---trigger, and a real command that replaced the proxy stays.
---@param src string
M.release = function(src)
  for _, cmd in ipairs(proxies_of[src] or {}) do
    local claimants = claimants_of[cmd]
    if claimants then
      claimants[src] = nil
      if next(claimants) == nil then
        claimants_of[cmd] = nil
        local info = vim.api.nvim_get_commands({})[cmd] --[[@as table?]]
        -- v0.12.0 reports a desc as `definition`.
        if info and (info.desc or info.definition) == M.DESC then
          pcall(vim.api.nvim_del_user_command, cmd)
        end
      end
    end
  end
end

return M
