-- One-line aliases (tt++ conf/aliases.tin). Each sends its commands to the
-- game as they are - none goes through another alias. %0 is everything
-- typed after the alias, %1 %2 %3 its words. aa, kk (fight/combat.lua), d1-d6
-- (gear/eq.lua) and sleep (fight/rheal.lua) are elsewhere. nav/travel.lua's speedwalk
-- hands these over first: su and dd are made of direction letters.

local MEDKIT = "medkit"

local A = {
  gh     = "home",
  su     = "autoassist;spellup luck %0;spellup int %0;spellup %0;autoassist",
  sq     = "spellup;get lotus " .. MEDKIT .. ";quaff lotus",
  dd     = "c 'dispel magic' %0",
  hh     = "c 'party heal'",
  cc     = "c 'cure blind' %0",
  cv     = "c 57;heighten",          -- night vision, psionic blast
  qa     = "get fugu " .. MEDKIT .. ";eat fugu",
  qs     = "get lotus " .. MEDKIT .. ";quaff lotus",
  qd     = "get refresh " .. MEDKIT .. ";quaff refresh",
  ll     = "rlook %1 %2 %3;map",
  donate = "gdonate %0",
  tend   = "uncurse;wear beacon",
  f      = "finger %0",
}

local aliases = {}

-- Run alias name with what was typed after it. Returns true if name is one
function aliases.run(name, args)
  local body = A[name]
  if not body then return false end
  args = (args or ""):match("^%s*(.-)%s*$")
  local w = {}
  for word in args:gmatch("%S+") do w[#w + 1] = word end
  local cmds = {}
  for part in body:gmatch("[^;]+") do
    local cmd = part:gsub("%%0", function() return args end)
                    :gsub("%%(%d)", function(n) return w[tonumber(n)] or "" end)
    cmds[#cmds + 1] = cmd:match("^%s*(.-)%s*$")
  end
  rune.send_raw(table.concat(cmds, "\n"))
  return true
end

-- Each in /help (core/help.lua) as what it sends - no list to
-- keep: a new one here gets its help too
local help = require("core.help")
for name, body in pairs(A) do
  rune.alias.exact(name, function(args) aliases.run(name, args) end)
  local usage = name .. (body:find("%%[0-9]") and " [args]" or "")
  help.add(name, usage, "sends: " .. body:gsub("%%0", "<args>"):gsub("%%(%d)", "<arg%1>"):gsub(";", "; "))
end

return aliases
