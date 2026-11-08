-- ac - cast your primary attack once a round (tt++ modules/autocast.tin)
--   ac [on|off]                   on, off; bare: the state
--   ac cast <command> | <hit>     send that instead, for this session - <hit>
--                                 is its word after "Your " in its damage line
--   ac cast reset                 back to k's attack (pattack, pattack_hit)
-- While on and fighting, a GMCP char.status sends the attack unless one is
-- still pending. A char.status comes just before each block of damage - the
-- melee round and the attack's own hit - so pending (set at the send) skips
-- the hit's status, and the hit line itself clears it. So it casts at each
-- melee round, when the spell lag has just ended: nothing waits in the
-- game's queue, and what you type goes next.
-- This is game text, like fight/dps.lua - GMCP doesn't say which spell landed
-- (a mana drop could be any spell). What clears pending: a line starting
-- "Your <hit> " (a miss reads the same, after an optional "[N] " or "*[N] "),
-- a fizzle ("You lost your concentration "), or "Cast <spell> on whom?" (it
-- ran with nothing left to fight - hidden, it's ac's own leftover). The
-- trigger is only on while a cast is pending. Leaving the fight doesn't
-- clear it: with several mobs the state flips between kills while the
-- cast is still in the game's queue (two "on whom?" lines, seen live in
-- tt++ 2026-11-06). No result 6 s after the send
-- (a cast refused while stunned): it clears, and the next char.status casts.
-- Your k counts: a bare k in a fight is skipped (ac is attacking already),
-- any other k is a cast pending.
-- Off at every load. The AC light on status row 2: green on, gray off.

local util = require("core.util")
local game = require("core.game")
local status = require("panes.status")   -- the AC light, in a row-2 slot
local combat = require("fight.combat")   -- the attack, and k's hook

local say, warn, trim = util.say, util.warn, util.trim

local on = false
local cmd, hit        -- ac cast's command and hit word, or nil for pattack's
local pending = false
local timeout = util.slot()   -- 6 s after a send: give up waiting for its line

-- The command and hit word in use
local function attack()
  if cmd then return cmd, hit end
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
      return clear()
    end
    clear()
    -- "on whom?": ac's cast outlived its mob (the round that sent it killed
    -- it). Nothing to see - hidden, with the blank after it
    local clean = ctx.line:clean()
    if clean:find("^Cast ") then util.eat_blanks(clean); return false end
  end, { name = "autocast_result" })
result:disable()

rune.gmcp.on("char.status", function()
  if not on or pending or game.state ~= 8 then return end
  local c = attack()
  if not c then return end
  mark()
  rune.send_raw(c)
end, { name = "autocast_status" })

combat.k_hook = function(mob)
  if not on then return false end
  if mob == "" and game.state == 8 then return true end
  mark()
  return false
end

table.insert(status.row2, function()
  return rune.style.gray(" | ") .. (on and rune.style.green("AC") or rune.style.gray("AC"))
end)

local function show()
  local c, w = attack()
  say(string.format("[ac] %s - sends %s, hit word %s%s", on and "on" or "off",
    c or "?", w or "(none - only the 6 s timeout)", cmd and " (ac cast reset for k's)" or ""))
end

rune.alias.exact("ac", function(args)
  args = trim(args)
  if args == "on" or args == "off" then
    if args == "on" and not attack() then return end   -- it said why
    on = args == "on"
    clear()
    say("[ac] autocast " .. args .. ".")
    rune.ui.refresh_bars()
  elseif args == "cast reset" then
    cmd, hit = nil, nil
    show()
  elseif args:match("^cast ") then
    local c, w = args:match("^cast (.-)%s*|%s*(.+)$")
    if not c or c == "" then return warn("[ac] ac cast <command> | <hit word>, or ac cast reset") end
    cmd, hit = c, w
    show()
  elseif args == "" then
    show()
  else
    warn("[ac] ac [on|off|cast <command> | <hit word>|cast reset]")
  end
end)

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("ac", "ac [on|off]", "autocast: in a fight, your primary attack (k) once a round, at the melee round; bare: the state")
help.add("ac cast", "ac cast <command> | <hit> | reset", "autocast something else this session (<hit>: its word after \"Your \" in the damage line); reset: back to k's")

-- For others (fight/bcc.lua's check before the mist)
return { on = function() return on end }
