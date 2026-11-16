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
-- Published to the display engine (core/view.lua) as module aard.char:
--   hp, mana, moves   ratio { cur, max } once both are known
--   align, level, tnl number;  state text ("standing", "fighting" ...),
--   fighting boolean;  enemy text (the game's @-codes taken out, "" when
--   none), enemy_hp number;  tick timestamp - when the next tick is due
-- Requires only the engine: every module that wants game state requires this.

local game = { room = { num = nil, zone = "", name = "" } }
local view = require("core.view")
local colors = require("core.colors")   -- uncolor: the enemy's name without the game's codes

local V = view.provides("aard.char", "your character, from Aardwolf GMCP char.* and comm.tick", {
  hp       = { "ratio",     "hit points", standard = true },
  mana     = { "ratio",     "mana", standard = true },
  moves    = { "ratio",     "moves", standard = true },
  align    = { "number",    "alignment, -2500 to 2500" },
  level    = { "number",    "your level", standard = true },
  tnl      = { "number",    "experience to the next level" },
  state    = { "text",      "what you're doing: standing, fighting, sleeping ...", standard = true },
  fighting = { "boolean",   "in a fight (state 8)", standard = true },
  enemy    = { "text",      "who you're fighting, \"\" when no one", standard = true },
  enemy_hp = { "number",    "the enemy's health, percent" },
  tick     = { "timestamp", "when the next tick is due (30 s after the last)", standard = true },
})
local STATE_NAMES = {
  [1] = "login", [2] = "motd", [3] = "standing", [4] = "afk", [5] = "note",
  [6] = "building", [7] = "paging", [8] = "fighting", [9] = "sleeping",
  [11] = "resting", [12] = "running",
}
game.state_names = STATE_NAMES
local function ratio(cur, max) if cur and max then return { cur = cur, max = max } end end
local function vitals()
  V.set("hp", ratio(game.hp, game.maxhp))
  V.set("mana", ratio(game.mana, game.maxmana))
  V.set("moves", ratio(game.moves, game.maxmoves))
  V.publish()
end

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
  V.set("state", STATE_NAMES[game.state or 0] or "?")
  V.set("fighting", game.state == 8)
  V.set("level", game.level)
  V.set("tnl", game.tnl)
  V.set("align", game.align)
  V.set("enemy", colors.uncolor(game.enemy))
  V.set("enemy_hp", game.enemypct or 0)
  V.publish()
end)

on("char.vitals", function(d)
  game.hp, game.mana, game.moves = tonumber(d.hp), tonumber(d.mana), tonumber(d.moves)
  vitals()
end)

on("char.maxstats", function(d)
  game.maxhp, game.maxmana, game.maxmoves = tonumber(d.maxhp), tonumber(d.maxmana), tonumber(d.maxmoves)
  vitals()
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
if tick_at then V.set("tick", tick_at + 30) end
rune.gmcp.on("comm.tick", function()
  tick_at = os.time()
  rune.session.set("game_tick_at", tostring(tick_at))
  V.set("tick", tick_at + 30)
  V.publish()
end, { name = "game_comm.tick", priority = 1 })
function game.tick()
  return tick_at and math.max(0, 30 - (os.time() - tick_at)) or nil
end

on("char.worth", function(d) game.worth = d end)
on("char.stats", function(d) game.stats = d end)

return game
