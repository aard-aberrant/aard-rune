-- Your character and room as GMCP last reported them (require("core.game")). The
-- handlers here run first (priority 1), so every other handler of the same
-- message - the status pane's, fight/combat.lua's - reads the new values. Aardwolf
-- may send numbers as strings, so they go through tonumber. nil until known.
--   char.base     name (lowercase), tier, subclass
--   char.status   state (8 = fighting), level, tnl, align, enemy, enemypct
--   char.vitals   hp, mana, moves
--   char.maxstats maxhp, maxmana, maxmoves
--   char.worth    worth = the message as sent (gold, bank, qp, tp, trains)
--   char.stats    stats = the message as sent (str ... luck, hr, dr)
--   room.info     room = { num, zone, name } (num can be -1 in a maze)
--   comm.tick     tick() = seconds to the next tick (30 at a tick), nil before
--                 the first (panes/status.lua's TCK, fight/rheal.lua, nav/moons.lua)
--   game.on_login(fn)  fn() once you're in the game: at the first char.base
--                 after this loaded (after a /reload: init.lua asks for
--                 char) and after each reconnect. Not at "connected" - Rune
--                 connects at the name and password prompts, where a
--                 command sent would be taken as your name or password
-- Requires nothing: every module that wants game state requires this.

local game = { room = { num = nil, zone = "", name = "" } }

local function on(pkg, fn)
  rune.gmcp.on(pkg, function(d)
    if type(d) == "table" then fn(d) end
  end, { name = "game_" .. pkg, priority = 1 })
end

local login_fns, logged_in = {}, false
function game.on_login(fn) login_fns[#login_fns + 1] = fn end
rune.hooks.on("disconnected", function() logged_in = false end, { name = "game_logged_out" })

on("char.base", function(d)
  if d.name then game.name = d.name:lower() end
  game.tier = tonumber(d.tier) or game.tier
  game.subclass = d.subclass or game.subclass
  if not logged_in then
    logged_in = true
    for _, fn in ipairs(login_fns) do fn() end
  end
end)

on("char.status", function(d)
  game.state = tonumber(d.state)
  game.level = tonumber(d.level)
  game.tnl = tonumber(d.tnl)
  game.align = tonumber(d.align)
  game.enemy = d.enemy or ""
  game.enemypct = tonumber(d.enemypct)
end)

on("char.vitals", function(d)
  game.hp, game.mana, game.moves = tonumber(d.hp), tonumber(d.mana), tonumber(d.moves)
end)

on("char.maxstats", function(d)
  game.maxhp, game.maxmana, game.maxmoves = tonumber(d.maxhp), tonumber(d.maxmana), tonumber(d.maxmoves)
end)

on("room.info", function(d)
  game.room = { num = tonumber(d.num), zone = d.zone or "", name = d.name or "" }
end)

-- (comm.tick may come with no table). Worked out from the clock when asked,
-- not counted down by a timer: Rune's repeating timers slip (each is re-armed
-- from when it fired) and drop a tick when Rune is busy (timer/service.go),
-- so a count lost seconds. The tick's time is kept in rune.session, so a
-- /reload doesn't lose it
local tick_at = tonumber(rune.session.get("game_tick_at") or nil)
rune.gmcp.on("comm.tick", function()
  tick_at = os.time()
  rune.session.set("game_tick_at", tostring(tick_at))
end, { name = "game_comm.tick", priority = 1 })
function game.tick()
  return tick_at and math.max(0, 30 - (os.time() - tick_at)) or nil
end

on("char.worth", function(d) game.worth = d end)
on("char.stats", function(d) game.stats = d end)

return game
