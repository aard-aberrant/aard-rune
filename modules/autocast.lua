-- ac - cast your attack once a round (tt++ modules/autocast.tin)
--   ac                            toggle it on or off (it says which, and what it sends)
--   ac1                           cast your primary attack (k's: pattack and
--                                 its hit word) - the one at every load
--   ac2                           cast your secondary (kk's: sattack)
--   ac cast <command> | <hit>     send that instead, for this session - <hit>
--                                 is its word after "Your " in its damage line
-- ac1 and ac2 turn ac on too (already on: the next round casts the
-- new one; the same one: nothing). ac cast only changes what's cast. They
-- replace each other.
--   ac aoe                        toggle the AoE opener: as a fight starts
--                                 (not fighting -> fighting), your area
--                                 attack (aa: data/player.lua's paoe) once,
--                                 before the attack - if its cooldown
--                                 (paoe's cooldown, tracked by modules/affects.lua)
--                                 is over; none named: no check. Only while
--                                 ac is on; can be set while it's off.
--                                 Leaving the area it was turned on in
--                                 (GMCP room.info's zone - recall and
--                                 portals too) turns it off, ac stays
-- While on and fighting, a GMCP char.status sends the attack unless one is
-- still pending. A char.status comes just before each block of damage - the
-- melee round and the attack's own hit - so pending (set at the send) skips
-- the hit's status, and the hit line itself clears it. So it casts at each
-- melee round, when the spell lag has just ended: nothing waits in the
-- game's queue, and what you type goes next.
-- This is game text, like modules/dps.lua - GMCP doesn't say which spell landed
-- (a mana drop could be any spell). What clears pending: a line starting
-- "Your <hit> " (a miss reads the same, after an optional "[N] " or "*[N] "),
-- a fizzle ("You lost your concentration "), or "Cast <spell> on whom?" (it
-- ran with nothing left to fight - hidden, it's ac's own leftover). The
-- trigger is only on while a cast is pending. Leaving the fight doesn't
-- clear it: with several mobs the state flips between kills while the
-- cast is still in the game's queue (two "on whom?" lines, seen live in
-- tt++ 2026-11-06). No result 6 s after the send
-- (a cast refused while stunned): it clears, and the next char.status casts.
-- Your k (on pri; kk on sec) counts: a bare one in a fight is skipped (ac
-- is attacking already), any other is a cast pending. The other one, or
-- either with ac cast <command>, is just sent.
-- Off at every load, the opener too. The AC light on status row 2, after
-- "|": AC1 pri, AC2 sec, AC* a command - green on, gray off; AOE after it,
-- the opener, the same.

local util = require("lib.util")
local game = require("modules.game")
local combat = require("modules.combat")   -- the attack, k's hook, paoe
local affects = require("modules.affects") -- the opener's cooldown (affects.ready)

local say, warn, trim = util.say, util.warn, util.trim

local on = false
local aoe = false        -- ac aoe: the opener
local aoe_zone           -- the area it was turned on in ("" not known yet)
local in_fight = false   -- fighting at the last char.status
local cmd, hit        -- ac cast's command and hit word, or nil for pri's or sec's
local pick = "pri"    -- ac1: pri, ac2: sec
local pending = false
local timeout = util.slot()   -- 6 s after a send: give up waiting for its line

-- The command and hit word in use
local function attack()
  if cmd then return cmd, hit end
  if pick == "sec" then return combat.sattack() end
  return combat.pattack()
end

local result

local function clear()
  pending = false
  timeout.stop()
  result:disable()
end

local function mark()
  pending = true
  result:enable()
  timeout.start(6, function() if pending then clear() end end)
end

result = rune.trigger.regex(
  "^(?:\\*?(?:\\[\\d+\\] )?Your (.+)|You lost your concentration |Cast .+ on whom\\?$)",
  function(m, ctx)
    if m[1] then
      local _, w = attack()
      if not w or w == "" or m[1]:sub(1, #w + 1) ~= w .. " " then return end
      clear()
      return
    end
    clear()
    -- "on whom?": ac's cast outlived its mob (the round that sent it killed
    -- it). Nothing to see - hidden, with the blank after it
    local clean = ctx.line:clean()
    if clean:find("^Cast ") then util.eat_blanks(clean); return false end
  end, { name = "autocast_result" })
result:disable()

-- The opener: the area attack, if its cooldown is over
local function opener()
  local c, rec = combat.paoe()
  if not c or (rec and affects.ready(rec) == false) then return end
  rune.send_raw(c)
end

rune.gmcp.on("char.status", function()
  local fighting = game.state == 8
  local starts = fighting and not in_fight
  in_fight = fighting
  if not on or not fighting then return end
  if starts and aoe then opener() end   -- sent first: the game runs it first
  if pending then return end
  local c = attack()
  if not c then return end
  mark()
  rune.send_raw(c)
end, { name = "autocast_status" })

combat.k_hook = function(mob, which)
  if not on or cmd or which ~= pick then return false end
  if mob == "" and game.state == 8 then return true end
  mark()
  return false
end

-- Published (ui/view.lua): ac on or off, the opener - the AC light
local view = require("ui.view")
local A = view.provides("aard.autocast", "autocast (ac)", {
  ["ac.on"]  = { "boolean", "ac is on" },
  ["ac.aoe"] = { "boolean", "ac aoe: ac opens a fight with the area attack" },
  ["ac.attack"] = { "text", "what ac casts: pri, sec, or cast (ac cast <command>)" },
})
A.set("ac.on", on)
A.set("ac.aoe", aoe)
A.set("ac.attack", pick)
local function set_attack()
  A.set("ac.attack", cmd and "cast" or pick)
  A.publish()
end
-- AC on the status row: data/layout/status.lua

-- The opener off on leaving its area: an area attack where you didn't
-- expect it starts on every mob there. A zone not known (empty) is
-- skipped; the first one known is taken as the opener's. Cost: a compare
-- per room change
view.subscribe("room.zone", function(_, z)
  if not aoe or not z or z == "" then return end
  if aoe_zone == "" then aoe_zone = z; return end
  if z == aoe_zone then return end
  aoe = false
  A.set("ac.aoe", aoe)
  A.publish()
  say("[ac] aoe off - left " .. aoe_zone)
end)

local function show()
  local c, w = attack()
  local open = ""
  if aoe then
    local a, rec = combat.paoe()
    open = a and (" + aoe - opens with " .. a .. (rec and (" (when " .. rec .. " is ready)") or "") .. ", then")
      or " + aoe (no area attack for this class) -"
  end
  say(string.format("[ac] %s%s sends %s, hit word %s%s", on and "on" or "off", open ~= "" and open or " -",
    c or "?", w or "(none - only the 6 s timeout)", cmd and " (ac1 / ac2: back to yours)" or (" (" .. pick .. ")")))
end

rune.alias.exact("ac", function(args)
  args = trim(args)
  if args == "" then
    if not on and not attack() then return end   -- it said why
    on = not on
    clear()
    show()
    A.set("ac.on", on)
    A.publish()
  elseif args == "aoe" then
    aoe = not aoe
    aoe_zone = aoe and (game.room.zone or "") or nil
    show()
    A.set("ac.aoe", aoe)
    A.publish()
  elseif args:match("^cast ") then
    local c, w = args:match("^cast (.-)%s*|%s*(.+)$")
    if not c or c == "" then warn("[ac] ac cast <command> | <hit word>"); return end
    cmd, hit = c, w
    clear()
    show()
    set_attack()
  else
    warn("[ac] ac (toggle), ac1, ac2, ac aoe (toggle the opener), ac cast <command> | <hit word>")
  end
end)

-- ac1 / ac2: your primary / secondary attack, ac on (already on: switched;
-- already so: nothing)
local function use(want)
  if on and not cmd and pick == want then return end
  local was_cmd, was_pick = cmd, pick
  cmd, hit, pick = nil, nil, want
  if not attack() then cmd, pick = was_cmd, was_pick; return end   -- it said why
  on = true
  clear()
  show()
  A.set("ac.on", on)
  set_attack()
end
rune.alias.exact("ac1", function() use("pri") end)
rune.alias.exact("ac2", function() use("sec") end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("ac", "ac", "autocast on/off (a toggle): in a fight, the attack set by ac1 / ac2 / ac cast (primary at load) once a round, at the melee round - the AC1 / AC2 / AC* light")
help.add("ac aoe", "ac aoe", "toggle: as a fight starts, ac opens with your area attack (aa) if its cooldown is over - the AOE light; off when you leave the area")
help.add("ac1", "ac1", "ac casts your primary attack (k), turning ac on if it's off - the AC1 light")
help.add("ac2", "ac2", "ac casts your secondary attack (kk), turning ac on if it's off - the AC2 light")
help.add("ac cast", "ac cast <command> | <hit>", "ac casts a command of your own this session (<hit>: its word after \"Your \" in the damage line) - the AC* light; ac1 / ac2 go back")

-- For others (modules/bcc.lua's check before the mist)
return { on = function() return on end }
