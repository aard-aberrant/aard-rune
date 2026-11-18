-- One-line aliases (tt++ conf/aliases.tin). Each sends its commands to the
-- game as they are - none goes through another alias. %0 is everything
-- typed after the alias, %1 %2 %3 its words. {key} is your character's
-- value from data/player.lua, {get key} "get <item> <medkit>" for a
-- consumable (modules/player.lua; the keys declared below) - one missing:
-- a warning, nothing sent. aa, kk (modules/combat.lua), d1-d6
-- (modules/eq.lua) and sleep (modules/rheal.lua) are elsewhere. modules/travel.lua's speedwalk
-- hands these over first: su and dd are made of direction letters.

local util = require("lib.util")
local player = require("modules.player")   -- {key}: your things; su per subclass

player.needs("modules.aliases", {
  medkit = "qa qs sq qd get the item from it (\"\": from your inventory)",
  heal = "qa: the verb, then the item (eat fugu)",
  mana = "qs and sq: the verb, then the item",
  moves = "qd: the verb, then the item",
  light = "tend: uncurse, then wear it",
})
player.needs("modules.aliases", {
  su = { "su: this subclass's own spellups, in place of the shared one", optional = true },
}, { subclass = true })

local A = {
  gh     = "home",
  su     = "spellup luck %0;spellup int %0;spellup %0",   -- autoassist kept as it was: aliases.su below
  sq     = "spellup;{get mana};{mana}",
  dd     = "c 'dispel magic' %0",
  hh     = "c 'party heal'",
  cc     = "c 'cure blind' %0",
  cv     = "c 57;heighten",          -- night vision, psionic blast
  qa     = "{get heal};{heal}",
  qs     = "{get mana};{mana}",
  qd     = "{get moves};{moves}",
  ll     = "rlook %1 %2 %3;map",
  donate = "gdonate %0",
  tend   = "uncurse;wear {light}",
  f      = "finger %0",
}

local aliases = {}

-- A subclass's own version of an alias: a field of the same name in your
-- subclass's section of data/player.lua (priest's su)
local function class_body(name)
  local C = player.class()
  return C and type(C[name]) == "string" and C[name] or nil
end

-- Alias name's commands with what was typed after it, one per line; nil if
-- name isn't one, false if a {key} is missing (player.fill said which).
-- A command left empty ({get heal} with no medkit) is dropped
local function expand(name, args)
  local body = A[name] and (class_body(name) or A[name])
  if not body then return nil end
  body = player.fill(body)
  if not body then return false end
  args = (args or ""):match("^%s*(.-)%s*$")
  local w = {}
  for word in args:gmatch("%S+") do w[#w + 1] = word end
  local cmds = {}
  for part in body:gmatch("[^;]+") do
    local cmd = part:gsub("%%0", function() return args end)
                    :gsub("%%(%d)", function(n) return w[tonumber(n)] or "" end)
    cmd = cmd:match("^%s*(.-)%s*$")
    if cmd ~= "" then cmds[#cmds + 1] = cmd end
  end
  return table.concat(cmds, "\n")
end

-- Run alias name with what was typed after it. Returns true if name is one
function aliases.run(name, args)
  local cmds = expand(name, args)
  if cmds == nil then return false end
  if cmds then rune.send_raw(cmds) end
  return true
end

-- su: the spellups with autoassist left as it was. Autoassist is toggled
-- first and its reply tells what it was: "Autoassist removed." - it was on:
-- the spellups, then on again; "You will now assist when needed." - it was
-- off: off again at once, then the spellups. No reply in 5 s: nothing more
-- sent, a warning (it may have been toggled). tail: commands sent after
-- the spellups (spup's vis). Cost: two exact triggers, on only while
-- waiting for that reply
local SU_WAIT = 5
local su_wait = util.group()
local su_pending, su_timer
local function su_reply(was_on)
  su_wait.set(false)
  if su_timer then su_timer:cancel(); su_timer = nil end
  local p = su_pending
  su_pending = nil
  if not p then return end
  if was_on then rune.send_raw(p.cmds .. "\nautoassist on" .. p.tail)
  else rune.send_raw("autoassist off\n" .. p.cmds .. p.tail) end
end
su_wait.add("exact", "Autoassist removed.", function() su_reply(true) end, { name = "su_assist_was_on" })
su_wait.add("exact", "You will now assist when needed.", function() su_reply(false) end, { name = "su_assist_was_off" })
function aliases.su(args, tail)
  if su_pending then util.warn("[su] still waiting for autoassist's reply."); return end
  local cmds = expand("su", args)
  if not cmds then return end
  su_pending = { cmds = cmds, tail = tail and ("\n" .. tail) or "" }
  su_wait.set(true)
  rune.send_raw("autoassist")
  su_timer = rune.timer.after(SU_WAIT, function()
    su_timer = nil
    if not su_pending then return end
    su_pending = nil
    su_wait.set(false)
    util.warn("[su] no reply to autoassist in " .. SU_WAIT .. " s - it may have been toggled; no spellups sent.")
  end)
end

-- #N {a;b}: the group, N times (a;b;a;b ...), as tt++ did. Rune's own #N
-- repeats one command only - it splits at ; first. Run here, not as a
-- rewrite: Rune would echo and keep in history the whole expanded line.
-- Echoed and kept as typed instead; after history_typed (modules/history.lua,
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

-- Each in /help (lib/help.lua) as what it sends - no list to
-- keep: a new one here gets its help too
local help = require("lib.help")
for name, body in pairs(A) do
  local su = name == "su"
  rune.alias.exact(name, su and function(args) aliases.su(args) end or function(args) aliases.run(name, args) end)
  local usage = name .. (body:find("%%[0-9]") and " [args]" or "")
  help.add(name, usage, "sends: " .. body:gsub("%%0", "<args>"):gsub("%%(%d)", "<arg%1>"):gsub(";", "; ")
    .. (body:find("{", 1, true) and " ({...}: yours, from data/player.lua - /player)" or "")
    .. (su and " (unless your subclass's section of data/player.lua has its own su)" or "")
    .. (su and "; autoassist is toggled first and left as it was" or ""))
end

return aliases
