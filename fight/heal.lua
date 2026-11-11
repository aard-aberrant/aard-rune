-- h - your heal spell (the class file's heal - Priest: regeneration -
-- default incomplete healing; fight/combat.lua), held for the gap between
-- kills (tt++ modules/heal.tin)
--   h [target]   not fighting: cast now. Fighting: queued, and sent at the
--                first GMCP char.status that isn't fighting - the gap after
--                a kill (more mobs may still be on you, so not a death line).
--                ac (fight/autocast.lua) casts nothing in a gap, so the heal goes
--                first. h again replaces a queued one
--   h stop       drop a queued one
-- If the next mob engaged before the heal ran, the game refuses: "You can't
-- concentrate enough to cast '<spell>'." (game text, like
-- autocast's - matched only between our send and 5 s after). While still
-- fighting, it's queued again for the next gap; a refusal for any other
-- reason isn't, so it can't send over and over. A /reload drops a queued one.

local util = require("core.util")
local game = require("core.game")   -- fighting or not
local combat = require("fight.combat")   -- the heal spell

local say, trim = util.say, util.trim

local arg            -- the target, "" for none
local queued = false

local on_refused   -- below

local function cast()
  queued = false
  -- a cast replaces the last one's wait (util.await, by name)
  local spell = combat.heal()
  util.await("exact", "You can't concentrate enough to cast '" .. spell .. "'.", function()
    on_refused()
  end, "heal_refused", 5)
  rune.send_raw("cast '" .. spell .. "'" .. (arg ~= "" and (" " .. arg) or ""))
end

-- The refusal (a one-off trigger, util.await, from the cast for 5 s)
function on_refused()
  if game.state == 8 then
    queued = true
    say("[h] refused - a mob engaged first. Queued for the next gap.")
  end
end

-- The gap: the first status that isn't fighting
rune.gmcp.on("char.status", function()
  if queued and game.state ~= 8 then cast() end
end, { name = "heal_gap" })

rune.alias.exact("h", function(args)
  args = trim(args)
  if args == "stop" then
    if not queued then say("[h] nothing queued."); return end
    queued = false
    say("[h] queued heal dropped.")
    return
  end
  arg = args
  if game.state == 8 then
    queued = true
    say("[h] " .. combat.heal() .. " queued for the next gap between kills (h stop drops it).")
  else
    cast()
  end
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("h", "h [target | stop]", "your heal spell (class file's heal, default incomplete healing): now out of a fight, else queued for the gap after a kill; stop drops a queued one")
