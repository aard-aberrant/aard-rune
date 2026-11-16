-- The minimap (require("modules.minimap")): what the minimap pane shows,
-- as data (panes/minimap.lua draws it). Not drawn from a map file: with
-- "tags map" on, the game sends its own ASCII map with every room, between
-- <MAPSTART> and <MAPEND> (modules/map.tin does the same in tt++). The lines
-- in between are hidden from the main output and kept, colors and all, by
-- one Rune span trigger (nothing looks at other lines).
-- Data (ui/view.lua):
--   map.block   the last block: { name = rows, map = rows, exits = row or
--               nil }, raw (the game's colors; a color left on at a line's
--               end put in front of the next):
--                 name: every line before the first whitespace-only one
--                   (the game wraps a long name onto a second line, then
--                   sends blank lines)
--                 map: the rest as sent, its own blank lines too, at most
--                   MINIMAP_H rows. The game keeps your # on the same row
--                   and column every time (84 of 88 blocks in a /log
--                   capture, 2026-11-06), so nothing is shifted or trimmed
--                 exits: the [ Exits: ... ] line
--   map.word    RUNNING / FIGHTING / DARKNESS in place of the map; nil: the map
--   map.note    the shown room's note (rmsg) from the mapper, "" for none
-- The header (zone | vnum) is modules/game.lua's room.zone and room.num.
-- Running (the user, 2026-11-08): a run - the game's run, runto - sends no
-- map block for the rooms it passes, while GMCP room.info still comes for
-- every room, so the map stood still under a changing header. The rule:
-- a room.info while GMCP char.status says running (state 12) shows the
-- header and RUNNING in place of the map; every map block draws the map.
-- Checked live 2026-11-09 (debug minimap): rt, g's runto, run 5s, a plain
-- 5s and run 10w all went to 12 - just after the first room passed (it
-- shows the last map a moment) - and back to 3 around the arrival's map
-- block; plain steps, g home and looks never did. It replaced a guess (a
-- room.info with no map block since the last one), which a look in the
-- dark, then heighten, set off while standing still. A run that ends with
-- no room shown (a fight, a wall, "Too many run errors.") leaves RUNNING
-- up: a failed step or the fight's end asks for a map (minimap_stale below).
-- Cost: nothing per line - one state read at each room.info.

local util = require("lib.util")
local colors = require("ui.colors")
local game = require("modules.game")       -- the room's zone and vnum
local view = require("ui.view")       -- fighting and state changes (aard.char)
local mapper = require("modules.mapper")   -- the room's note
local maprec = require("modules.maprec")   -- map record / plan / edit / drop / apply
local layout = require("ui.layout")   -- the most map rows kept

local minimap = {}
local H = layout.MINIMAP_H

local V = view.provides("aard.minimap", "the game's map block, and what the minimap shows in its place", {
  ["map.block"] = { "record", "the last map block: name (rows), map (rows), exits (a row or nil) - raw, the game's colors" },
  ["map.word"]  = { "text",   "RUNNING, FIGHTING or DARKNESS in place of the map; nil: the map" },
  ["map.note"]  = { "text",   "the shown room's note from the mapper, \"\" for none" },
})

local map_buf = {}   -- { raw = ..., clean = ... } for each line of the block
local show_next = false   -- the next block answers a map you typed: show it
local quiet_next = false  -- the next block answers the login map: hide a blank after it
local dark = false        -- in a room you can't see: DARKNESS until the next block

local function blank(line) return util.blank(line.clean) end

-- The last color code in a raw line, or nil if it has none. The game sets
-- a color once and lets it run on into the next line, as a terminal would
-- (a wrapped room name's second line has no code of its own) - so the
-- color still on at the end of one line is put in front of the next
local last_sgr = colors.last

-- A word in place of the map (RUNNING when running, FIGHTING when a fight
-- broke the run, DARKNESS in a room you can't see)
local stale = false   -- RUNNING or FIGHTING is up: no map block for this room yet
local block_seen = false   -- a map block came since the last room.info
local map_num   -- the room whose map is shown; nil while a word is up
local parts     -- the last block (map.block)
local function show_word(word)
  stale, map_num = word ~= "DARKNESS", nil
  V.set("map.word", word)
  V.publish()
end

-- The map block, split once, at the block: the room name, the map and the
-- exits row
local function build_map()
  local lines = map_buf
  local i, n = 1, #lines
  while i <= n and blank(lines[i]) do i = i + 1 end
  local p = { name = {}, map = {} }
  -- the room name: up to the first whitespace-only line
  local carry = ""
  while i <= n and not blank(lines[i]) do
    local raw = carry .. lines[i].raw
    carry = last_sgr(raw) or carry
    p.name[#p.name + 1] = raw
    i = i + 1
  end
  -- the exits line, if any, is the last non-blank line
  local last = n
  while last >= i and blank(lines[last]) do last = last - 1 end
  if last >= i and lines[last].clean:match("^%s*%[ Exits:") then
    p.exits = lines[last].raw
    last = last - 1
  end
  while last >= i and blank(lines[last]) do last = last - 1 end
  -- the map as sent
  for k = i, last do
    if #p.map >= H then break end
    local raw = carry .. lines[k].raw
    carry = last_sgr(raw) or carry
    p.map[#p.map + 1] = raw
  end
  parts = p
  V.set("map.block", p)
end

-- The map shown: no word, the room's note
local function show_map()
  local room = game.room
  local mr = room.num and mapper.rooms[room.num]
  V.set("map.word", nil)
  V.set("map.note", mr and mr.note or "")
  V.publish()
end

-- debug minimap: the run check, in the order things come - each state
-- change, each map block (its room name) and each room.info with the
-- state then and what it drew (map or RUNNING). Made to check state 12
-- (the header note); kept for when the minimap looks wrong
local dbg = require("lib.debug").topic("minimap", "the run check: state changes, map blocks, each room.info and what it drew")
-- No redraw when the state leaves 12: run 10w's state went back before
-- its map block came, so a redraw then showed the start room's map a moment.
-- Run when aard.char's state changes, not on each char.status (two state
-- numbers modules/game.lua has no name for both read "?": a change between
-- them isn't logged)
local prev_state
view.subscribe("state", function()
  if not dbg.on then return end
  local s = game.state
  if s == prev_state then return end
  dbg.log("state " .. tostring(prev_state) .. " -> " .. tostring(s))
  prev_state = s
end)

-- The block is one Rune span, <MAPSTART> to <MAPEND>, all of it hidden
-- (gag): the action runs once at <MAPEND> with its lines. A block that
-- answers a typed map is echoed to the main output as well
rune.trigger.exact("<MAPSTART>", function(_, ctx)
  local lines = ctx.lines
  map_buf = {}
  for i = 2, #lines do
    local clean = lines[i]:clean()
    if clean ~= "<MAPEND>" then map_buf[#map_buf + 1] = { raw = lines[i]:raw(), clean = clean } end
  end
  if show_next then
    show_next = false
    for _, l in ipairs(map_buf) do rune.echo(l.raw) end
  elseif quiet_next then
    quiet_next = false
    util.eat_blanks("<MAPEND>")
  end
  dark, stale, block_seen = false, false, true
  build_map()
  show_map()
  map_num = game.room.num
  if dbg.on then
    dbg.log("map block: " .. util.trim(colors.strip(parts.name[1] or "?")) .. " (state " .. tostring(game.state) .. ")")
  end
end, { name = "aard_map", priority = 10, gag = true, span = { to = "^<MAPEND>$", max = 120 } })

-- TEMPORARY probe (2026-11-11, slope jets): with debug minimap on, every
-- line holding MAPSTART, MAPEND or {rname} - hidden or not, any shape -
-- shown raw (codes as \27). Remove once the jets question is settled
for _, s in ipairs({ "MAPSTART", "MAPEND", "{rname}" }) do
  rune.trigger.contains(s, function(_, ctx)
    if dbg.on then dbg.log("probe " .. s .. ": " .. ctx.line:raw():gsub("\27", "\\27")) end
  end, { name = "minimap_probe_" .. s, priority = 1 })
end

-- A room you can't see (heighten senses off) shows "You see nothing but
-- darkness..." and sends no map block (seen live 2026-11-09), so the last
-- room's map stayed up. That line blanks the pane to DARKNESS until the
-- next map block; a room.info in between keeps DARKNESS
rune.trigger.regex("^You see nothing but darkness\\.\\.\\.\\s*$", function()
  dark = true
  if dbg.on then
    dbg.log(string.format("darkness line in %s %s (state %s)", tostring(game.room.num),
      tostring(game.room.name), tostring(game.state)))
  end
  if game.state ~= 12 then show_word("DARKNESS") end
end, { name = "minimap_dark" })

-- The header and note come from GMCP room.info, which can arrive after the
-- map block: drawn again then, so they never show the room you just left
-- (modules/game.lua has stored it already). Running (state 12): RUNNING
-- Fighting (state 8) with no block since the last room.info: FIGHTING. A
-- fight that breaks a run on its first step (seen live 2026-11-09: 3 to 8,
-- no 12, two room.info at 8 and no map block) drew the new header over the
-- old map. If the block comes after its room.info (a plain step into an
-- aggressive mob), it replaces FIGHTING with the map at once. Nothing is
-- sent mid-fight (the user: a command can queue and disrupt the fight);
-- the fight's end asks for the map (minimap_stale_fight).
-- A look mid-fight sends room.info but no map block (seen live 2026-11-11:
-- the second look in a fight blanked the map) - the same room as the map
-- shown, so the pane is left as it is. A room with no vnum (-1) never
-- counts as the same
rune.gmcp.on("room.info", function()
  local s, num = game.state, game.room.num
  local same = num ~= nil and num ~= -1 and num == map_num
  local fresh = block_seen
  block_seen = false
  local fighting = s == 8 and not fresh and not same
  local word = s == 12 and "RUNNING" or dark and "DARKNESS" or fighting and "FIGHTING" or nil
  local keep = not word and same and not fresh   -- the map shown is already this room's
  if dbg.on then
    dbg.log(string.format("room.info %s %s (state %s) -> %s", tostring(num),
      tostring(game.room.name), tostring(s), word or keep and "kept" or "map"))
  end
  if word then
    show_word(word)
  elseif parts and not keep then
    show_map()
    map_num = num
  end
end, { name = "minimap_room" })

-- map: the game's map, shown in the main output too (the minimap takes
-- every map block, so a typed map showed nothing). Also the map editing
-- commands (modules/mapper.lua):
--   map info                   where you are on the map (modules/mapper.lua)
--   map unlink <exit>          remove a wrong exit from this room
--   map avoid <exit>           routes never take this exit (unavoid: they may again)
--   map renames [apply <vnum|all>]  rooms the game now names differently (modules/mapper.lua)
--   map label <word> / unlabel <word> / labels   room labels, for find and ga (modules/mapper.lua)
--   map note <text> / unnote   this room's note, on the minimap (modules/mapper.lua)
--   map exit <vnum> <command>  add an exit GMCP doesn't list (custom exits)
--   map record, plan, edit, drop, apply   record a way past a room (modules/maprec.lua)
rune.alias.exact("map", function(args)
  args = util.trim(args)
  local sub, rest = args:match("^(%S+)%s*(.-)$")
  if sub == "info" and rest == "" then
    mapper.info()
    return
  elseif sub == "unlink" then
    local msg, ok = mapper.unlink(rest)
    return (ok and util.say or util.warn)(msg)
  elseif sub == "renames" then
    mapper.renames(rest)
    return
  elseif sub == "avoid" or sub == "unavoid" then
    local msg, ok = mapper.avoid(rest:lower(), sub == "avoid")
    if ok then util.say(msg) else util.warn(msg) end
    return
  elseif sub == "exit" then
    local v, cmd = rest:match("^(%d+)%s+(.+)$")
    local msg, ok = mapper.add_exit(tonumber(v), cmd)
    return (ok and util.say or util.warn)(msg)
  elseif maprec.subs[sub] then
    maprec.command(sub, rest)
    return
  elseif sub == "label" then
    mapper.label(rest)
    return
  elseif sub == "unlabel" then
    mapper.unlabel(rest)
    return
  elseif sub == "labels" then
    mapper.list_labels()
    return
  elseif sub == "note" then
    if rest == "" then util.warn("[map] map note <text> (map unnote removes it)") else mapper.note(rest) end
    return
  elseif sub == "unnote" and rest == "" then
    mapper.note("")
    return
  end
  show_next = true
  rune.send_raw(args ~= "" and ("map " .. args) or "map")
end)

-- At login and after a /reload, a silent map: the pane is filled straight
-- away, not at your first move (the game sends the map only with a room).
-- Its block is hidden as every one is, and a blank line after it with it
-- (a guess - the bare map reply's shape isn't seen yet; nothing if none)
function minimap.refresh()
  quiet_next = true
  rune.send_raw("map")
end
game.on_login(minimap.refresh)

-- A run that stops with no room shown leaves RUNNING up (seen live
-- 2026-11-09: a run stopped at a lamia, and the steps typed after it hit a
-- wall). The rule (the user, 2026-11-09): with RUNNING up, a failed step
-- asks for a silent map - by GMCP room.wrongdir, not the wall's text (each
-- failed step of a run sends one: 2n into a wall, seen live 2026-11-09). Not
-- counted to the game's three ("Too many run errors."): the first one does
-- it, and the next room.info at 12 brings RUNNING back if the run goes on.
-- Cost: one flag check per room.wrongdir
rune.gmcp.on("room.wrongdir", function()
  if not stale or game.state == 8 then return end   -- mid-fight: the fight's end asks
  stale = false
  if dbg.on then dbg.log("room.wrongdir with RUNNING up: silent map") end
  minimap.refresh()
end, { name = "minimap_stale" })

-- A fight that breaks a run ("Your journey was broken by the need to
-- defend yourself.", seen live 2026-11-09) sends no map block. RUNNING up
-- when the fight starts (12 to 8) becomes FIGHTING. Nothing is sent during
-- the fight (the user, 2026-11-09: a command can queue and disrupt it):
-- the moment it ends (8 to anything else), still no block, a silent map.
-- Run when aard.char's fighting changes (modules/game.lua's char.status
-- handler publishes it), not on each char.status
local fight_prev
view.subscribe("fighting", function()
  local s, was = game.state, fight_prev
  fight_prev = s
  if stale and s == 8 and was ~= 8 then
    show_word("FIGHTING")
  elseif stale and was == 8 and s ~= 8 then
    if dbg.on then dbg.log("fight over (8 -> " .. tostring(s) .. ") with the pane stale: silent map") end
    minimap.refresh()
  end
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("map", "map", "the game's map, in the main output too")
help.add("map exit", "map exit <vnum> <command>", "add a custom exit from this room to <vnum>, taken by <command>")
help.add("map unlink", "map unlink <exit>", "remove a wrong exit from this room")
help.add("map avoid", "map avoid <exit>", "routes never take this exit from this room (avoid the exits into a room to keep routes out of it)")
help.add("map unavoid", "map unavoid <exit>", "routes may take this exit from this room again")
help.add("map renames", "map renames [apply <vnum|all>]", "rooms the game now names differently from the map (map/mapnames.log); apply takes the game's name")

return minimap
