-- Black Claw Crag epic, the always-loaded part (tt++ areas/bcc_find.tin).
-- The fight helper - Axaldra's breath grid, rr, rrs - is areas/blackclaw.lua,
-- loaded only while you're in the blackclaw zone. Ported from Castiel's
-- BlackClawHelper MUSHclient plugin (github.com/AardMadrox/aardwolf-plugins).
--   bcc find      go to room 25035 (travel's route, as vf), walk the mist
--                 path until the mist line shows, walk back the steps sent
--                 past it, enter mist. Warns if your alignment isn't
--                 neutral or autocast is on
--   bcc stop      cancel a find
--   bcc           the state
-- The walk keeps LOOKAHEAD steps in flight - the next goes out at each
-- GMCP room.info for a new room - so it stops soon after the mist. The
-- room text and GMCP aren't guaranteed to arrive in order, which is why it
-- doesn't stop dead on the mist line: it can overshoot by up to LOOKAHEAD
-- rooms, then walks those back.
--
-- Run count: leaving the zone (areas/blackclaw.lua's unload) watches 20 s
-- for "You hear a faint whisper in your ear, warning you not to return for
-- N minutes." and counts the run in home's room note (the mapper's, shown
-- on the minimap) as "bcc runs N DD-Mon HHMM". A note that isn't a count
-- is left alone.
--
-- Cost: nothing between finds - the mist trigger (one contains) and the
-- room.info handler exist only while a find walks.

local util = require("core.util")
local game = require("core.game")          -- align, the room
local mapper = require("nav.mapper")       -- home's room note
local travel = require("nav.travel")       -- the route to the start, home_vnum
local autocast = require("fight.autocast") -- on or off

local say, warn, err, trim = util.say, util.warn, util.err, util.trim

local START = 25035
local LOOKAHEAD = 2
local PATH = {}
for d in ("s;e;e;e;n;e;s;s;s;w;n;w;w;w;s;s;s;s;w;s;e;e;e;e;s;e;s;e;w;s;w;w;n;e;n;w;w;w;w"):gmatch("[^;]+") do
  PATH[#PATH + 1] = d
end
local OPP = { n = "s", s = "n", e = "w", w = "e", u = "d", d = "u" }

local M = {}

-- bcc find ----------------------------------------------------------------

local phase          -- nil, "goto", "walk" or "found"
local i, n, back = 0, 0, 0   -- steps sent, in flight, to walk back
local room           -- the last room GMCP reported during the find
local watch = util.slot()
local walking = util.group()   -- the mist line, only while a find walks
local room_h                    -- the room.info handler, likewise

local function walk_end()
  watch.stop()
  walking.set(false)
  if room_h then room_h:remove(); room_h = nil end
  phase, i, n, back = nil, 0, 0, 0
end

-- kind: "stall" or "done" (the whole path walked)
local function arm(secs, kind)
  watch.start(secs, function()
    if not phase then return end
    if kind == "done" then
      warn("[bcc] walked the whole path, no mist found.")
    else
      err(string.format("[bcc] find stalled, stopped (phase %s, step %d of %d, room %s). bcc find to try again.",
        phase, i, #PATH, tostring(game.room and game.room.num)))
    end
    walk_end()
  end)
end

local function fill()
  while n < LOOKAHEAD and i < #PATH do
    i, n = i + 1, n + 1
    rune.send_raw(PATH[i])   -- raw, so an alias named after a direction can't get in the way
  end
  arm(4, "stall")
end

local function begin_walk()
  phase = "walk"
  rune.send_raw("look")
  fill()
end

local function enter()
  walk_end()
  rune.send_raw("enter mist")
end

local function back_and_enter()
  for j = i, i - back + 1, -1 do rune.send_raw(OPP[PATH[j]]) end
  enter()
end

local function checks()
  local al = game.align
  if al and (al < -874 or al > 874) then err("[bcc] alignment " .. al .. " isn't neutral (-874 to 874).") end
  if autocast.on() then err("[bcc] autocast is on - ac to switch it off") end
end

local function on_room(d)
  local v = tonumber(d and d.num)
  if not phase or not v or v == room then return end
  room = v
  if phase == "goto" then
    if v == START then begin_walk() else arm(20, "stall") end
    return
  end
  if n > 0 then n = n - 1 end
  if phase == "walk" then
    fill()
    if n == 0 then arm(1.5, "done") end
  elseif n == 0 then
    back_and_enter()
  else
    arm(4, "stall")
  end
end

walking.add("contains", "A thick layer of mist is obscuring your vision.", function()
  if phase ~= "walk" then return end
  say(string.format("[bcc] mist found (after step %d of %d)", i, #PATH))
  checks()
  if n > 0 then   -- already stepped past it: wait for those to land, then undo them
    phase, back = "found", n
    arm(4, "stall")
  else
    enter()
  end
end, { name = "bcc_mist" })

local function find()
  if phase then say("[bcc] find is already walking - bcc stop to cancel it."); return end
  i, n, back = 0, 0, 0
  room = game.room and game.room.num
  walking.set(true)
  room_h = rune.gmcp.on("room.info", on_room, { name = "bcc_find_room" })
  if room == START then
    begin_walk()
  else
    phase = "goto"
    arm(20, "stall")
    travel.go_vnum(START, "the bcc start (" .. START .. ")")
  end
end

-- The run count -------------------------------------------------------------

local function count_run()
  local home = travel.cfg.home_vnum
  local r = home and mapper.rooms[home]
  if not r then warn("[bcc] home_vnum isn't on the map - run not counted."); return end
  local runs = r.note == "" and 0 or tonumber(r.note:match("^bcc runs (%d+)"))
  if not runs then err("[bcc] home's room note isn't a run count, not updated: " .. r.note); return end
  runs = runs + 1
  local when = os.date("%d-%b %H%M")
  r.note = "bcc runs " .. runs .. " " .. when
  mapper.dirty = true
  mapper.save()
  say("[bcc] run " .. runs .. " counted in home's room note (" .. when .. ").")
end

-- From areas/blackclaw.lua, as you leave the zone
function M.watch_whisper()
  util.await("starts", "You hear a faint whisper in your ear, warning you not to return for ", function(_, ctx)
    if ctx.line:clean():find("not to return for %d+ minutes?%.$") then count_run() end
  end, "bcc_whisper", 20)
end

-- The command -----------------------------------------------------------------

rune.alias.exact("bcc", function(args)
  args = trim(args)
  if args == "find" then
    find()
  elseif args == "stop" then
    if not phase then say("[bcc] find isn't walking."); return end
    walk_end()
    say("[bcc] find stopped.")
  else
    say(string.format("[bcc] find is %s. bcc find, bcc stop",
      phase and (phase .. ", step " .. i .. " of " .. #PATH) or "idle"))
  end
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("bcc", "bcc [find|stop]", "Black Claw Crag epic. find: go to room 25035, walk the mist path, back up to the mist and enter it (warns if alignment isn't neutral or autocast is on); stop: cancel a find; bare: the state. In the crag, the breath grid shows in the info pane, and rr / rrs move you")

return M
