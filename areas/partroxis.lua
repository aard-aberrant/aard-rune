-- Partroxis (tt++ areas/partroxis.tin, Maze Navigator v5 + Grax keys). Only
-- while you're in the partroxis zone (areas/loader.lua).
--
-- The maze: 40 rooms in a straight line - room N's way on is to N+1, except
-- 11 "oops" rooms with two exits listing the same name, one of them a real
-- exit that drops you in an earlier room. Rooms 14, 29 and 40 are gates
-- (enter gate). Where you are is GMCP's vnum: room N = vnum 5763 + N (names
-- repeat - "The Forest" is 3, 5, 15 and 23). GMCP lists every maze exit as
-- -1, so the way on comes from a hidden exits: the exit naming the next
-- room that isn't marked wrong from here. A good direction is kept; a wrong
-- one is marked, and the way back to the oops room is speedrun along the
-- kept ones (the rooms hidden, as g does), and the other exit taken.
-- Walking into room 1 from outside starts a new run (a repop remaps the
-- exits). Data stops at room 40.
--   mazenext          one step (or resume a speedrun a fight cut short)
--   mazerun <mob>     auto-run to that mob's room (exact name, else a part,
--                     case ignored; several matches: a picker of them)
--   mazerun           on to the target a fight stopped, else a picker of
--                     the rooms ahead
--   mazeabort         stop an auto-run and forget its target
--   mazehere [n]      show or set the room number (from the vnum without n)
--   mazeexit          hunt elf, buy rock, drop rock
-- Never moves while fighting (GMCP char.status). A fight stops an auto-run
-- and nothing is sent after it - you hide/invis yourself, then mazerun.
-- (tt++ protected and went on by itself, and counted "is attacking you!" /
-- "is dead! R.I.P." lines; GMCP's state covers both.)
--
-- Grax keys: graxkeys from Grax's room (5814) - the three-key quest, all in
-- this zone. It walks to each kill and stops; you fight (autoloot on), and
-- the looted item's line takes it on to Grax and the next. Each move waits
-- for GMCP to show its room before the next (tt++'s confirm-move: moves sent
-- back to back raced it). The dwarf's room (5830) is a best guess.
local A = ...
local util = require("core.util")
local game = require("core.game")      -- room, fighting
local tags = require("core.tags")      -- a speedrun's rooms hidden
local travel = require("nav.travel")   -- graxkeys' walks (tt++'s vf)

local say, warn, trim = util.say, util.warn, util.trim

-- Rooms: name, oops (the room the wrong exit drops you in), gate, note
local ROOMS = {
  { "In the mountains" }, { "Through the Woods" }, { "The Forest" },
  { "Swampy Path", oops = 3, note = "Wear a shield vs groups. Recast invis/sneak after being attacked." },
  { "The Forest" }, { "Along the River" }, { "The Desert" }, { "The Desert" }, { "The Wheat Fields" },
  { "In the Mountains" }, { "In the Mountains" }, { "A Cave", oops = 9 }, { "The Wheat Fields", oops = 9 },
  { "The Wheat Fields", gate = true }, { "The Forest" }, { "The Swamp" }, { "The Swamp" },
  { "River of Blood" }, { "A small Cave" }, { "A small Cave" },
  { "Through the Passage of Time", note = "Reality Check detects invis/hide - recast after the fight." },
  { "The Swamp", oops = 3 }, { "The Forest" }, { "The Wheat Fields", oops = 9 }, { "The Wheat Fields" },
  { "In the Mountains", oops = 25 }, { "The Wheat Fields", oops = 6 }, { "Along the River" },
  { "The Wheat Field", gate = true }, { "In the Mountains", oops = 11 }, { "In the Mountains" },
  { "The Desert", oops = 16 }, { "The Swamp", oops = 32 }, { "The Desert" }, { "The Wheat Field", oops = 12 },
  { "A Cave" }, { "A Cave", oops = 10 }, { "In the Mountains" }, { "In the Mountains" },
  { "A vast Expanse of Plains", gate = true, last = true },
}
local MOBS = {
  "A Mountain of Rock", "The Rabid Tiger-man", "The man-eating wolfen", "The Buck-Toothed Lizard-Man",
  "The Living Tree", "The Furious Flying Fish Man", "The Quicksand", "The Flesh Eating Ants",
  "The Living Vines", "The Gigantic Bulette", "A Bird of Prey", "The Otherworld Assassin",
  "Vision of a False Portal", "The Hungry Dragon", "A Bloodthirsty Tiger-Man", "The Cold Hearted Lizard-Man",
  "The Insane Cheryb", "Flowing Blood", "A collapsing cave", "The Dream Eater", "Reality Check",
  "Blood Sucking Vines", "The Golden Haired Assassin", "Mass of Flying Dismembered Body Parts",
  "Bloodthirsty Killer Gerbils", "A Monster Bulette", "The Thing", "The Big and Deadly Dragon",
  "Soul of the Damned", "Lesser Chitryn", "Delusions of Hope", "Swarm of Blood Sucking Bio-chemical Gnats",
  "It", "Your Worst Nightmare", "Walking Suit of Armor", "Lesser Otherworld Dragon", "Insane Cheryb",
  "Otherworld Dragon", "Hell Hound Behemoths", "Chitryn",
}
local BASE = 5763   -- room N = vnum BASE + N
local GATE = "enter gate"
local PROTECT = "hide\nsneak\ncast invis"
local HUNT_OUT = "elf"
local DIRS = { North = "n", South = "s", East = "e", West = "w", Up = "u", Down = "d",
               Northeast = "ne", Northwest = "nw", Southeast = "se", Southwest = "sw" }

local room          -- the maze room you're in (1-40), or nil
local good, failed = {}, {}   -- good[N] = the way on from N; failed[N][dir]
local auto, target = false, nil
local step          -- the step that's out: { from, dir }
local speed_to      -- the oops room a speedrun back is heading for
local prev          -- the room before the last landing
local exits_timer   -- the 15 s wait for the exits reply
local exits_line    -- the exits reply's catch-all, while ours is out

local function fighting() return game.state == 8 end
local function protect() rune.send_raw(PROTECT) end

local function stop_moving()
  auto, step, speed_to = false, nil, nil
end
local function reset_route()
  good, failed = {}, {}
  stop_moving()
end

local function exits_end()
  if exits_line then exits_line:remove(); exits_line = nil end
  if exits_timer then exits_timer:cancel(); exits_timer = nil end
end

local mazenext   -- below

local function auto_continue()
  if not auto then return end
  if room == target then
    say("[maze] arrived: #" .. room .. " (" .. MOBS[room] .. ").")
    auto, target = false, nil
  elseif not fighting() then
    mazenext()
  end
end

-- Speedrun from here to room `to` along the kept directions, sent at once.
-- `extra`: rooms whose text is still to come before the run's (the trap
-- room you were just dropped in)
local function speed_start(to, extra)
  speed_to = to
  local ok = room and room < to
  if ok then for i = room, to - 1 do if not good[i] then ok = false end end end
  if not ok then
    say("[maze] no recorded route from #" .. tostring(room) .. " to #" .. to .. " - stopped. mazenext walks on room by room.")
    stop_moving()
    return
  end
  local cmds = {}
  for i = room, to - 1 do cmds[#cmds + 1] = good[i] end
  say("[maze] speedrun back to #" .. to .. " (" .. #cmds .. (#cmds == 1 and " room)." or " rooms)."))
  tags.hide_rooms(#cmds + (extra or 0), "maze")
  rune.send_raw(table.concat(cmds, "\n"))
end

local function step_landed()
  local from, took = step.from, step.dir
  step = nil
  if room == from + 1 then
    good[from] = took
    say("[maze] room " .. room .. (ROOMS[room].note and (" - " .. ROOMS[room].note) or ""))
    protect()
    auto_continue()
    return
  end
  failed[from] = failed[from] or {}
  failed[from][took] = true
  local oops = ROOMS[from].oops
  say("[maze] wrong exit '" .. took .. "' from #" .. from .. " - dropped in #" .. room
    .. (room == oops and "." or (", not the listed trap (" .. tostring(oops) .. ").")))
  protect()
  speed_start(from, 1)
end

local function speed_landed()
  if room ~= prev + 1 then
    good[prev] = nil
    say("[maze] speedrun went off the route from #" .. prev .. " (landed in #" .. room
      .. ") - stopped. Moves already sent still run; mazenext once they're done.")
    stop_moving()
    tags.walk_stopped()
  elseif room == speed_to then
    speed_to = nil
    say("[maze] room " .. room .. " - back at the oops room, taking the other exit.")
    protect()
    mazenext()
  end
end

A.gmcp.on("room.info", function()
  local v = game.room.num
  local n = v and v > BASE and v <= BASE + #ROOMS and v - BASE or nil
  if not n then
    if step or speed_to then say("[maze] left the maze (room " .. tostring(v) .. ") - stopped."); stop_moving() end
    room = nil
    return
  end
  if not room and n == 1 then
    reset_route()
    say("[maze] room 1 - new run, the last run's route and wrong exits are cleared.")
  end
  if n == room then return end   -- a look
  prev, room = room, n
  if step then step_landed() elseif speed_to then speed_landed() end
end)

A.gmcp.on("room.wrongdir", function()
  if step then
    failed[step.from] = failed[step.from] or {}
    failed[step.from][step.dir] = true
    say("[maze] no '" .. step.dir .. "' exit from #" .. step.from .. " - stopped. mazenext reads the exits again.")
    stop_moving()
  elseif speed_to then
    if room then good[room] = nil end
    say("[maze] speedrun hit a missing exit at #" .. tostring(room) .. " - stopped. Moves already sent still run; mazenext once they're done.")
    stop_moving()
    tags.walk_stopped()
  end
end)

-- A fight stops an auto-run; the target stays for a bare mazerun. Its end
-- (in the maze): a reminder to hide/invis again
local was_fighting = false
A.gmcp.on("char.status", function()
  local now = fighting()
  if auto and now then
    auto = false
    say("[maze] fight - auto-run stopped at #" .. tostring(room) .. ". mazerun goes on to #" .. target .. ".")
  elseif was_fighting and not now and room then
    warn("[maze] fight over - cast invis and hide" .. (target and (", then mazerun to go on to #" .. target) or "") .. ".")
  end
  was_fighting = now
end)

-- The way on: a hidden exits, then the exit naming the next room ----------

local function walk(d)
  if fighting() then return say("[maze] in combat - not moving. Step cancelled at #" .. room .. ".") end
  step = { from = room, dir = d }
  rune.send_raw(d)
end

local function decide(map, order)
  if fighting() then return say("[maze] in combat - not moving. Step cancelled at #" .. room .. ".") end
  local want = ROOMS[room + 1][1]
  for _, d in ipairs(order) do
    if map[d] == want and not (failed[room] and failed[room][d]) then return walk(d) end
  end
  say("[maze] none of the exits from #" .. room .. " (" .. ROOMS[room][1] .. ") lists '" .. want
    .. "' (or every one is marked wrong). Re-check the exits or the table.")
  auto = false
end

-- The reply (tt++'s, seen live):
--   Obvious exits from [ In the Mountains ]:
--    North          : In the Mountains
-- It's over at the first line after the header that isn't an exit; that
-- line is hidden too when blank. Waits behind lag; 15 s with none: stop
local function ask_exits()
  exits_end()
  local seen, map, order = false, {}, {}
  exits_line = A.trigger.starts("", function(_, ctx)
    local clean = ctx.line:clean()
    if not seen then
      if clean:find("^Obvious exits from") then seen = true; return false end
      return
    end
    local word, name = clean:match("^ (%a+)%s+: (.-)%s*$")
    if word and DIRS[word] then
      map[DIRS[word]] = name
      order[#order + 1] = DIRS[word]
      return false
    end
    exits_end()
    decide(map, order)
    if clean:match("^%s*$") then return false end
  end, { name = "maze_exits", priority = 5 })
  exits_timer = A.timer.after(15, function()
    exits_timer = nil
    exits_end()
    auto = false
    say("[maze] no reply to exits in 15 seconds - stopped. mazenext to try again.")
  end)
  rune.send_raw("exits")
end

function mazenext()
  if fighting() then
    return say("[maze] in combat - not moving. Step cancelled at #" .. tostring(room) .. ".")
  end
  step = nil
  if not room then return say("[maze] current room unknown - mazehere <number> first.") end
  if speed_to then return speed_start(speed_to) end
  if ROOMS[room].last then
    auto = false
    return say("[maze] no data past room #" .. room .. ". Get the rest of the table before continuing.")
  end
  if ROOMS[room].gate then
    step = { from = room, dir = GATE }
    return rune.send_raw(GATE)
  end
  ask_exits()
end

-- Commands -------------------------------------------------------------------

local function mazehere(args)
  local n = tonumber(trim(args))
  if not n then
    local v = game.room.num
    if not v then return say("[maze] no room vnum from GMCP - mazehere <room number>.") end
    if v <= BASE or v > BASE + #ROOMS then
      return say("[maze] vnum " .. v .. " isn't a maze room (" .. (BASE + 1) .. "-" .. (BASE + #ROOMS) .. "). mazehere <room number>.")
    end
    n = v - BASE
  end
  if not ROOMS[n] then return warn("[maze] mazehere 1-" .. #ROOMS) end
  room = n
  if n == 1 then reset_route() else stop_moving() end
  say("[maze] current room set to #" .. n .. " (" .. ROOMS[n][1] .. ").")
end

A.help("mazenext", "mazenext", "maze: one step on (or resume a speedrun a fight cut short) (partroxis)")
A.help("mazerun", "mazerun [mob]", "maze: auto-run to that mob's room (a picker if several); bare: on to the target, or a picker (partroxis)")
A.help("mazeabort", "mazeabort", "maze: stop an auto-run and forget its target (partroxis)")
A.help("mazehere", "mazehere [n]", "maze: show or set the room number (partroxis)")
A.help("mazeexit", "mazeexit", "maze: hunt elf, buy rock, drop rock (partroxis)")
A.help("graxkeys", "graxkeys", "Grax's three-key quest, from Grax's room 5814 (partroxis)")
A.alias.exact("mazenext", function() mazenext() end)
A.alias.exact("mazehere", mazehere)
local function run_to(n)
  if not room then return say("[maze] current room unknown - mazehere <number> first.") end
  if n == room then return say("[maze] already at #" .. room .. " - that's where " .. MOBS[room] .. " is.") end
  if n < room then return say("[maze] #" .. n .. " (" .. MOBS[n] .. ") is behind you (#" .. room .. ") - the maze only runs forward.") end
  target = n
  say("[maze] target: #" .. n .. " (" .. MOBS[n] .. "). Auto-running from #" .. room .. ". mazeabort to stop.")
  auto = true
  auto_continue()
end

-- A picker of these rooms (all ahead of you if nil)
local function pick(list)
  local items = {}
  for n = 1, #MOBS do
    if (list and list[n]) or (not list and n > room) then
      items[#items + 1] = { text = MOBS[n], desc = "#" .. n .. " " .. ROOMS[n][1], value = tostring(n) }
    end
  end
  if #items == 0 then return say("[maze] no rooms ahead of #" .. room .. ".") end
  rune.ui.picker.show({ title = "mazerun", items = items, match_description = true,
                        on_select = function(v) run_to(tonumber(v)) end })
end

-- mazerun: on to the target a fight stopped, else a picker of the rooms
-- ahead. mazerun <mob>: an exact name, else a part of one (case ignored); a
-- part matching several opens a picker of them
A.alias.exact("mazerun", function(args)
  if not room then return say("[maze] current room unknown - mazehere <number> first.") end
  local q = trim(args):gsub("^[{\"'](.*)[}\"']$", "%1"):lower()   -- tt++ habit: {Insane Cheryb}
  if q == "" then
    if target then return run_to(target) end
    return pick()
  end
  local hits, n_hits = {}, 0
  for n, mob in ipairs(MOBS) do if mob:lower() == q then return run_to(n) end end
  for n, mob in ipairs(MOBS) do
    if mob:lower():find(q, 1, true) then hits[n] = true; n_hits = n_hits + 1 end
  end
  if n_hits == 0 then return say("[maze] no room's mob matches '" .. q .. "'.") end
  if n_hits == 1 then return run_to(next(hits)) end
  pick(hits)
end)

A.alias.exact("mazeabort", function()
  auto, target = false, nil
  say("[maze] auto-run cancelled.")
end)

A.alias.exact("mazeexit", function()
  say("[maze] exiting: hunt " .. HUNT_OUT .. ", buy rock, drop it.")
  rune.send_raw("hunt " .. HUNT_OUT)
  A.timer.after(2, function()
    rune.send_raw("buy rock")
    A.timer.after(1, function() rune.send_raw("drop rock") end)
  end)
end)

-- Grax keys -------------------------------------------------------------------

-- A run is a list of steps, each one of:
--   { "cmd", to = vnum }   send cmd, wait for room `to` (no to: any new room)
--   { vf = vnum }          walk there (nav/travel.lua), wait for it
--   { say = "cmd" }        send, no wait (give, uncurse, open)
--   { wait = "name", msg } stop: the item's loot line starts the next run
local RUNS = {
  start = {
    { "enter part" }, { "enter foothills" }, { vf = 5859 },
    { wait = "hendry", msg = "Kill Hendry for his dagger - make sure autoloot is on. I'll go on once you loot it." },
  },
  hendry = {
    { say = "uncurse" }, { vf = 5815 }, { "enter partroxis" }, { "enter ocean" }, { "enter partroxis" },
    { say = "give dagger grax" }, { "enter partroxis" }, { "enter tree" }, { say = "open n" }, { "n" }, { "n" }, { "u" },
    { wait = "elf", msg = "Kill the elf for the map. I'll go on once you loot it." },
  },
  elf = {
    { vf = 5824 }, { "enter partroxis" }, { "enter ocean" }, { "enter partroxis" },
    { say = "give map grax" }, { "enter partroxis" }, { "enter canyon", to = 5816 }, { vf = 5828 },
    { say = "open n" }, { "n" }, { vf = 5830 },
    { wait = "dwarf", msg = "Kill the dwarf for the vision (the room's a best guess - move if needed). I'll go on once you loot it." },
  },
  dwarf = {
    { vf = 5816 }, { "enter partroxis" }, { "enter ocean" }, { "enter partroxis" }, { say = "give vision grax" },
    { done = true },
  },
}
local waiting_for     -- the kill a run stopped at: "hendry", "elf", "dwarf"
local move            -- the move that's out: { to, from, gen, after }
local move_timer   -- the wait for the move's room

local function run(list, i)
  i = i or 1
  local s = list[i]
  if not s then return end
  local function after() run(list, i + 1) end
  if s.say then rune.send_raw(s.say); return after() end
  if s.wait then
    waiting_for = s.wait
    warn("[graxkeys] " .. s.msg)
    return util.beep()
  end
  if s.done then return say("[graxkeys] done - Grax's Trust, Hope and Ambition all turned in.") end
  move = { to = s.vf or s.to, from = game.room.num, after = after }
  local secs = s.vf and 10 or 3
  if move_timer then move_timer:cancel() end
  move_timer = A.timer.after(secs, function()
    move_timer = nil
    if move then
      move = nil
      warn("[graxkeys] no arrival after " .. (s.vf and ("walking to " .. s.vf) or ("\"" .. s[1] .. "\""))
        .. ". Sort out your position and re-run graxkeys, or the step, by hand.")
    end
  end)
  if s.vf then travel.go_vnum(s.vf, "graxkeys " .. s.vf) else rune.send_raw(s[1]) end
end

A.gmcp.on("room.info", function()
  local m = move
  if not m then return end
  local num = game.room.num
  if (m.to and num == m.to) or (not m.to and num ~= m.from) then
    move = nil
    if move_timer then move_timer:cancel(); move_timer = nil end
    m.after()
  end
end)

A.alias.exact("graxkeys", function()
  if game.room.num ~= 5814 then
    return warn("[graxkeys] start in room 5814 (you're in " .. tostring(game.room.num) .. ") - not starting.")
  end
  waiting_for = nil
  run(RUNS.start)
end)

-- The loot lines, by the item's name (each corpse also drops gold, whose
-- line names the corpse too - tt++ ran everything twice matching that)
local function looted(item, kill)
  A.trigger.contains(item, function(_, ctx)
    if waiting_for ~= kill then return end
    if kill == "hendry" and not ctx.line:clean():find("You get .*The Accursed Dagger") then return end
    waiting_for = nil
    say("[graxkeys] " .. item .. " looted - going on.")
    run(RUNS[kill])
  end)
end
looted("The Accursed Dagger", "hendry")
looted("Map of the Viewing Chamber", "elf")
looted("Strange Vision", "dwarf")

A.on_unload(function()
  stop_moving()
  exits_end()
  move = nil
end)

-- Loaded by the zone's first room.info, which the handlers above missed
do
  local v = game.room.num
  if v and v > BASE and v <= BASE + #ROOMS then room = v - BASE end
end

say("[maze] navigator loaded - walk into room 1, then mazerun <mob> or mazenext. graxkeys from room 5814.")
