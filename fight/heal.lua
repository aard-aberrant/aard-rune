-- h - incomplete healing, held for the gap between kills (tt++ modules/heal.tin)
--   h [target]   not fighting: cast now. Fighting: queued, and sent at the
--                first GMCP char.status that isn't fighting - the gap after
--                a kill (more mobs may still be on you, so not a death line).
--                ac (fight/autocast.lua) casts nothing in a gap, so the heal goes
--                first. h again replaces a queued one
--   h stop       drop a queued one
-- If the next mob engaged before the heal ran, the game refuses: "You can't
-- concentrate enough to cast 'incomplete healing'." (game text, like
-- autocast's - matched only between our send and 5 s after). While still
-- fighting, it's queued again for the next gap; a refusal for any other
-- reason isn't, so it can't send over and over. A /reload drops a queued one.

local util = require("core.util")
local game = require("core.game")   -- fighting or not

local say, trim = util.say, util.trim

local arg            -- the target, "" for none
local queued = false
local gen = 0

local refused

local function cast()
  queued = false
  gen = gen + 1
  local g = gen
  refused:enable()
  rune.timer.after(5, function() if g == gen then refused:disable() end end)
  rune.send_raw(arg ~= "" and ("cast 'incomplete healing' " .. arg) or "cast 'incomplete healing'")
end

refused = rune.trigger.regex("^You can't concentrate enough to cast 'incomplete healing'\\.$", function()
  refused:disable()
  gen = gen + 1
  if game.state == 8 then
    queued = true
    say("[h] refused - a mob engaged first. Queued for the next gap.")
  end
end, { name = "heal_refused" })
refused:disable()

-- The gap: the first status that isn't fighting
rune.gmcp.on("char.status", function()
  if queued and game.state ~= 8 then cast() end
end, { name = "heal_gap" })

rune.alias.exact("h", function(args)
  args = trim(args)
  if args == "stop" then
    if not queued then return say("[h] nothing queued.") end
    queued = false
    return say("[h] queued heal dropped.")
  end
  arg = args
  if game.state == 8 then
    queued = true
    say("[h] incomplete healing queued for the next gap between kills (h stop drops it).")
  else
    cast()
  end
end)
