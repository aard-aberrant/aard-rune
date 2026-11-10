-- Black Claw Crag solo epic, the fight helper (tt++ areas/bcc.tin). Only
-- while you're in the blackclaw zone (areas/loader.lua); "bcc find" is
-- fight/bcc.lua, always loaded. Ported from Castiel's
-- BlackClawHelper MUSHclient plugin (its run/loot/retreat stats aren't).
--
-- Strategy - how the fight is played (the user's, from tt++):
--   1. Touch the crystal, then drop a bear totem (c 'gaias totem' bear) in
--      the room you land in.
--   2. Watch for Axaldra to fly, then get right behind her in a middle room
--      - the side she has just left, since she goes round clockwise.
--   3. As soon as her room is safe, rr into it and dispel the whelp's
--      sanctuary. Keep at it, side by side, until none of the 4 middle
--      whelps (n, e, s, w) is sanced any more.
--   4. Then pick one middle whelp and just kill it.
--   5. Then the whelp on the opposite side, the same way.
--
-- 1. Axaldra's breath. Each "Axaldra, the Eternal One lifts off from her
--    perch and flies <dir>." makes the three rooms on that side of the 3x3
--    lair burn for 16 s. The info pane (priority 10, over quest and the
--    rest) shows the last breath and the safe side, and the lair as a grid:
--    a cell's seconds left (red, orange at 2, yellow at 1), then dots once
--    clear - green on the safe side. @@ in the middle is Axaldra's column.
--    3 s after a breath, "The direction X is now safe!".
--    She goes north, east, south, west, round again (tt++ log/bcc2). A
--    breath on your side starts rr by itself, backing you out; her next
--    side being yours gives MOVE MOVE MOVE 5 s later - moving is up to you.
--    The fight ends (the pane given back, rr stopped) at "Deciding you're
--    not worth the trouble ...", the epic's last line "A mortally wounded
--    adventurer says, "Thank... you..."", "You die.", or leaving the zone.
-- 2. rr - to the middle of the next side clockwise (n 55000, e 55002,
--    s 55004, w 55006): 2 to 4, 4 to 6, 6 to 8, 8 to 2, a corner to the
--    middle after it. One step at a time, from the room GMCP last reported:
--    plan, send one step, wait for its room.info, plan again. Retreat while
--    fighting (GMCP state 8), a plain move otherwise - the game's answer
--    overrides the state once. Never from a clear room into a burning one
--    (it stops); from a burning room, out counterclockwise to the safe
--    side's middle, through hot rooms if it must. At the goal KILL KILL
--    KILL, or MOVE MOVE MOVE if a breath on the way made it her next side.
--    rr while rr moves you: the goal moves on one more side. The dragon
--    hitting you (engulfed, or the lingering flames) stops rr and keeps a
--    breath from starting one for 16 s (tt++ 2026-10-24: the backout kept
--    retreating into rooms still burning).
--    rrs - stop rr, ask GMCP for the room, and report it.
--
-- Cost: only in this zone - 11 starts/exact triggers (Go-side matches;
-- Lua runs on their lines only), one room.info handler, a 1 s redraw
-- timer only while a cell counts down.
local A = ...
local util = require("core.util")
local colors = require("core.colors")
local theme = require("core.theme")
local mix, bg = colors.mix, colors.bg
-- This module's colors: theme.bcc.* - /theme lists them, data/theme.lua
-- changes them (core/theme.lua)
local T = theme.define("bcc", "Blackclaw", {
  { "safe",   theme.green,                   "a safe square, the safe direction" },
  { "quiet",  theme.dark,                    "an empty square" },
  { "hot1",   theme.yellow,                  "a square's count: 1" },
  { "hot2",   theme.orange_tc,               "2" },
  { "hot3",   theme.red,                     "3 and up" },
  { "label",  theme.gray,                    "Axaldra: / safe:" },
  { "value",  mix(theme.bold, theme.white),  "the direction, the center" },
  { "note",   theme.cyan,                    "\"The direction ... is now safe!\"" },
  { "move",   mix(theme.bold, theme.yellow), "MOVE MOVE MOVE" },
  { "kill",   mix(theme.bold, theme.red),    "KILL KILL KILL" },
})
local game = require("core.game")   -- room, state
local info = require("panes.info")  -- the grid
local bcc = require("fight.bcc")    -- the run count

local say, err = util.say, util.err

-- The lair --------------------------------------------------------------------

local CELLS = { north = { "nw", "n", "ne" }, east = { "ne", "e", "se" },
                south = { "se", "s", "sw" }, west = { "sw", "w", "nw" } }
local SAFE_OF = { north = "west", east = "north", south = "east", west = "south" }
local NEXT_OF = { north = "east", east = "south", south = "west", west = "north" }
local ALL = { "nw", "n", "ne", "w", "e", "sw", "s", "se" }
local OPP = { n = "s", s = "n", e = "w", w = "e" }

-- The ring of 8 rooms round Axaldra's column (no middle room), clockwise
-- from the northwest corner (tt++ map/map-all.tt, checked against "To the
-- <dir> lies a massive column" in log/bcc2-4). cw: the exit to the next
local RING = {
  { cell = "nw", vnum = 54999, cw = "e" }, { cell = "n", vnum = 55000, cw = "e" },
  { cell = "ne", vnum = 55001, cw = "s" }, { cell = "e", vnum = 55002, cw = "s" },
  { cell = "se", vnum = 55003, cw = "w" }, { cell = "s", vnum = 55004, cw = "w" },
  { cell = "sw", vnum = 55005, cw = "n" }, { cell = "w", vnum = 55006, cw = "n" },
}
local AT = {}
for k, p in ipairs(RING) do AT[p.vnum] = k end
local MID = { north = 2, east = 4, south = 6, west = 8 }

local function on_side(side, cell)
  for _, c in ipairs(CELLS[side] or {}) do if c == cell then return true end end
  return false
end

-- Breath state ------------------------------------------------------------------

local hot = {}        -- cell -> os.time() its burning ends
local dir, safe       -- the last breath's side and the safe one; nil: no fight
local noauto_until = 0
local tick = util.slot()        -- the grid's 1 s redraw
local safe_note = util.slot()
local move_note = util.slot()
local function clear_hot() for _, c in ipairs(ALL) do hot[c] = 0 end end
clear_hot()

local RED, ORANGE, YELLOW = T.hot3.on, T.hot2.on, T.hot1.on
local GREEN, DIM, GRAY, WHITE, R = T.safe.on, T.quiet.on, T.label.on, T.value.on, colors.RESET
local PAD = string.rep(" ", 10)
local last_key

local function draw()
  if not dir then last_key = nil; return info.set("bcc", 10, nil) end
  local now = os.time()
  local left, key, counting = {}, dir, false
  for _, c in ipairs(ALL) do
    local r = math.max(0, hot[c] - now)
    left[c] = r
    key = key .. "|" .. r
    if r > 0 then counting = true end
  end
  if counting then tick.start(1, draw) end
  if key == last_key then return end
  last_key = key
  local o = {}
  for _, c in ipairs(ALL) do
    local r = left[c]
    if r == 0 then o[c] = (on_side(safe, c) and GREEN or DIM) .. ".."
    else o[c] = (r >= 3 and RED or r == 2 and ORANGE or YELLOW) .. string.format("%2d", r) end
  end
  info.set("bcc", 10, table.concat({
    GRAY .. "Axaldra: " .. WHITE .. dir .. R .. "  " .. GRAY .. "safe: " .. GREEN .. safe .. R,
    PAD .. o.nw .. "  " .. o.n .. "  " .. o.ne .. R,
    PAD .. o.w .. "  " .. WHITE .. "@@  " .. o.e .. R,
    PAD .. o.sw .. "  " .. o.s .. "  " .. o.se .. R,
  }, "\n"))
end

-- rr ------------------------------------------------------------------------------

-- on, phase ("step" or nil), from/expect (the waiting step's rooms), stuck
-- (steps in a row that didn't move you), force ("plain"/"retreat" for the
-- next step, from the game's answer), goal (ring position), escape (the
-- goal is the way out of a breath), here_hot, v, c (room and position), d
local rr = { on = false, stuck = 0 }
local rrs_wait = false
local STEP_WAIT = 15   -- never re-sent on a timeout: the game queues a retreat behind spell lag
local MAX_STUCK = 10
local rr_watch = util.slot()

local function rr_stop()
  rr.on, rr.phase = false, nil
  rr_watch.stop()
end

local function where()
  rr.v = game.room and game.room.num
  rr.c = AT[rr.v] or 0
end

local plan   -- forward: plan, send and go call each other

local function arrive()
  local cell = RING[rr.c].cell
  if dir and on_side(NEXT_OF[dir], cell) then
    rune.echo(T.move("MOVE MOVE MOVE"))
  else
    rune.echo(T.kill("KILL KILL KILL"))   -- in the safe room: the cue to fight
  end
end

local function go()
  rr.from, rr.phase = rr.v, "step"
  rr.stuck = rr.stuck + 1
  local how = rr.force or (game.state == 8 and "retreat" or "plain")
  rr.force = nil
  rune.send_raw(how == "retreat" and ("retreat " .. rr.d) or rr.d)
  rr_watch.start(STEP_WAIT, function()
    if not rr.on then return end
    rr_stop()
    err("[rr] no answer to the move in " .. STEP_WAIT .. " seconds, stopped. rr to go on.")
  end)
end

-- One step from position rr.c toward rr.goal: clockwise, or the shorter way
-- if something carried you off (clockwise on a tie); always counterclockwise
-- backing out of a breath
local function send()
  local n_cw = (rr.goal - rr.c + 8) % 8
  local ccw = rr.escape or (8 - n_cw) < n_cw
  local to
  if ccw then
    to = (rr.c + 6) % 8 + 1                -- counterclockwise from i: the reverse of clockwise from i-1
    rr.d = OPP[RING[to].cw]
  else
    to = rr.c % 8 + 1
    rr.d = RING[rr.c].cw
  end
  rr.expect = RING[to].vnum
  local h = hot[RING[to].cell] - os.time()
  if h > 0 and rr.here_hot <= 0 then
    rr_stop()
    return err(string.format("[rr] the next room (%s) is in the breath for %ds more - not moving you.", RING[to].cell, h))
  end
  go()
end

function plan()
  rr.phase = nil
  where()
  if rr.c == 0 then
    rr_stop()
    return err("[rr] room " .. tostring(rr.v) .. " isn't on the dragon nest ring, stopped.")
  end
  rr.here_hot = hot[RING[rr.c].cell] - os.time()
  if rr.here_hot > 0 and not rr.escape and safe then
    rr.escape, rr.goal = true, MID[safe]
    err("[rr] breath on your side - backing you out to " .. safe .. ".")
  end
  if not rr.goal then   -- even (a middle): 2 on; odd (a corner): 1 on
    rr.goal = rr.c + 2 - rr.c % 2
    if rr.goal > 8 then rr.goal = rr.goal - 8 end
  end
  if rr.c == rr.goal then
    rr_stop()
    return arrive()
  end
  if rr.stuck >= MAX_STUCK then
    rr_stop()
    return err("[rr] " .. rr.stuck .. " tries without moving, stopped.")
  end
  send()
end

local function rr_begin()
  rr_stop()
  rr.on, rr.goal, rr.escape, rr.stuck, rr.force = true, nil, false, 0, nil
  plan()
end

-- The answers to a step that aren't a room change: still here, so plan again
local function still_here()
  if rr.on and rr.phase == "step" then rr_watch.stop(); plan() end
end
local function force(how)
  if rr.on and rr.phase == "step" then rr.force = how end
  still_here()
end

-- Every room.info: rr's step landing, rrs's report
A.gmcp.on("room.info", function(d)
  local v = tonumber(d and d.num)
  if rr.on and rr.phase == "step" and v and v ~= rr.from then
    rr_watch.stop()
    if v == rr.expect then
      rr.stuck = 0
      plan()
    else   -- a move typed by hand still queued, or the game moved you
      rr_stop()
      err("[rr] landed in " .. v .. ", not where I was heading - stopped. rr to go on.")
    end
  end
  if rrs_wait then
    rrs_wait = false
    local k = AT[v]
    if k then say("[rrs] room " .. tostring(v) .. " (" .. RING[k].cell .. " on the ring). rr to go on.")
    else say("[rrs] room " .. tostring(v) .. " - not on the dragon nest ring.") end
  end
end, { name = "blackclaw_room" })   -- after core/game.lua's (priority 1) has set game.room

-- Not "You failed." - that's a failed dd (dampening field, tt++ log/bcc2)
A.trigger.exact("You FAIL to retreat!", still_here, { name = "blackclaw_fail" })
A.trigger.exact("Alas, you cannot go that way.", still_here, { name = "blackclaw_alas" })
A.trigger.exact("You aren't fighting anyone.", function() force("plain") end, { name = "blackclaw_notfighting" })
A.trigger.exact("Not while you are fighting!", function() force("retreat") end, { name = "blackclaw_fighting" })
A.trigger.exact("You cannot retreat in that direction!", function()
  if rr.on and rr.phase == "step" then
    rr_stop()
    err("[rr] the game says you can't go " .. rr.d .. " from here - stopped. rr to go on.")
  end
end, { name = "blackclaw_baddir" })

A.alias.exact("rr", function()
  if not rr.on then return rr_begin() end
  if rr.escape then return say("[rr] getting you out of the breath first.") end
  rr.goal = rr.goal + 2
  if rr.goal > 8 then rr.goal = rr.goal - 8 end
  say("[rr] queued - now going on to room " .. rr.goal .. " (" .. RING[rr.goal].cell .. ").")
end)

A.alias.exact("rrs", function()
  rr_stop()
  rrs_wait = true
  say("[rr] stopped - checking where you are...")
  rune.gmcp.send("request room")
end)

-- The breath ----------------------------------------------------------------------

local function fight_off()
  if rr.on then rr_stop(); say("[rr] stopped - the fight is over.") end
  clear_hot()
  dir, safe = nil, nil
  tick.stop(); safe_note.stop(); move_note.stop()
  draw()
end

-- Standing on the side she just flew to (a corner is on two): rr backs you
-- out (staying put killed you - tt++ log/bcc6), unless the dragon hit you.
-- On her next side: MOVE MOVE MOVE 5 s on
local function move_check(side)
  local k = AT[game.room and game.room.num]
  if not k then return end
  local cell = RING[k].cell
  if on_side(side, cell) then
    if noauto_until > os.time() then
      err("[bcc] breath on your side - not moving you (the dragon hit you). rr to move.")
    else
      rr_begin()
    end
  elseif on_side(NEXT_OF[side], cell) then
    move_note.start(5, function() rune.echo(T.move("MOVE MOVE MOVE")) end)
  end
end

A.trigger.starts("Axaldra, the Eternal One lifts off from her perch and flies ", function(_, ctx)
  local side = ctx.line:clean():match("flies (%a+)%.")
  if not side or not SAFE_OF[side] then return end
  dir, safe = side, SAFE_OF[side]
  local untl = os.time() + 16
  for _, c in ipairs(CELLS[side]) do hot[c] = untl end
  safe_note.start(3, function()
    if safe then rune.echo(T.note.on .. "The direction " .. GREEN .. safe .. T.note.on .. " is now safe!" .. R) end
  end)
  if not rr.on then move_check(side) end   -- a moving rr sees the hot room at its next plan
  draw()
end, { name = "blackclaw_breath" })

A.trigger.starts("Deciding you're not worth the trouble of feeding to her young, Axaldra, the", fight_off, { name = "blackclaw_drop" })
A.trigger.starts("A mortally wounded adventurer says, \"Thank... you...\"", fight_off, { name = "blackclaw_won" })
A.trigger.exact("You die.", fight_off, { name = "blackclaw_die" })

-- Hurt by the dragon: rr stops, and no breath starts one for 16 s
local function dragon_hit(what)
  noauto_until = os.time() + 16
  if rr.on then
    rr_stop()
    err("[rr] " .. what .. " hit you - not moving you. rr to move.")
  end
end
A.trigger.exact("You are engulfed in an inferno of flames!", function() dragon_hit("breath") end, { name = "blackclaw_engulf" })
A.trigger.exact("The lingering flames lick at your skin, burning you!", function() dragon_hit("lingering flames") end, { name = "blackclaw_flames" })

-- Leaving the crag ----------------------------------------------------------------

A.on_unload(function()
  theme.undefine("bcc")   -- its colors go with it
  bcc.watch_whisper()   -- the run count
  rr_stop()
  rrs_wait = false
  fight_off()
end)

A.help("rr", "rr", "Black Claw Crag: to the middle of the next side clockwise (2 to 4, 4 to 6, 6 to 8, 8 to 2; a corner to the middle after it), one retreat or move at a time, then KILL KILL KILL (or MOVE MOVE MOVE if it's her next side). Won't step from a clear room into a burning one; from a burning one backs you out counterclockwise to the safe side. Starts by itself when a breath lands on your side, unless the dragon hit you in the last 16 s. rr again while moving: one side further")
A.help("rrs", "rrs", "Black Claw Crag: stop rr, and report the room you're in (from the game)")
