-- One-line aliases (tt++ conf/aliases.tin). Each sends its commands to the
-- game as they are - none goes through another alias. %0 is everything
-- typed after the alias, %1 %2 %3 its words. aa, kk (fight/combat.lua), d1-d6
-- (gear/eq.lua) and sleep (fight/rheal.lua) are elsewhere. nav/travel.lua's speedwalk
-- hands these over first: su and dd are made of direction letters.

local util = require("core.util")

local MEDKIT = "medkit"

local A = {
  gh     = "home",
  su     = "autoassist off;spellup luck %0;spellup int %0;spellup %0;autoassist on",
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

-- A subclass's own version of an alias: a field of the same name in its
-- data/classes file (priest's su). Read once per subclass, when first used
local game = require("core.game")
local class_cache = {}   -- subclass -> its class data (false: no file)
local function class_body(name)
  local sub = game.subclass
  if not sub then return nil end
  local C = class_cache[sub]
  if C == nil then
    C = util.class_data(sub) or false
    class_cache[sub] = C
  end
  return C and type(C[name]) == "string" and C[name] or nil
end

-- Run alias name with what was typed after it. Returns true if name is one
function aliases.run(name, args)
  local body = A[name] and (class_body(name) or A[name])
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

-- #N {a;b}: the group, N times (a;b;a;b ...), as tt++ did. Rune's own #N
-- repeats one command only - it splits at ; first. Run here, not as a
-- rewrite: Rune would echo and keep in history the whole expanded line.
-- Echoed and kept as typed instead; after history_typed (core/history.lua,
-- priority 50), so history.log has it as typed too
local MAX_REPEAT = 100
rune.hooks.on("input", function(text, ctx)
  if ctx.mode ~= "command" then return end
  local n, group = text:match("^%s*#(%d+)%s*{(.*)}%s*$")
  if not n then return end
  n = tonumber(n)
  if n < 1 or n > MAX_REPEAT then
    util.warn("[alias] #N {...}: N from 1 to " .. MAX_REPEAT .. ".")
    return false
  end
  local echo, show = rune.hooks.call("echo", text)
  if show then rune.echo(echo) end
  rune.history.add(text)
  local reps = {}
  for i = 1, n do reps[i] = group end
  rune.send(table.concat(reps, rune.config.get("command_separator")))
  return false
end, { name = "alias_repeat_group", priority = 60 })

-- Each in /help (core/help.lua) as what it sends - no list to
-- keep: a new one here gets its help too
local help = require("core.help")
for name, body in pairs(A) do
  rune.alias.exact(name, function(args) aliases.run(name, args) end)
  local usage = name .. (body:find("%%[0-9]") and " [args]" or "")
  help.add(name, usage, "sends: " .. body:gsub("%%0", "<args>"):gsub("%%(%d)", "<arg%1>"):gsub(";", "; ")
    .. " (unless data/classes/<subclass>.lua has its own " .. name .. ")")
end

return aliases
