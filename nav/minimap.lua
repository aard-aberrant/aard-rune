-- The minimap pane (require("nav.minimap")). Not drawn from a map file: with
-- "tags map" on, the game sends its own ASCII map with every room, between
-- <MAPSTART> and <MAPEND>
-- (modules/map.tin does the same in tt++). The lines in between are hidden
-- from the main output and kept, colours and all, by one Rune span
-- trigger (nothing looks at other lines). At <MAPEND> the pane is redrawn
-- whole:
--   zone | vnum (GMCP room.info, from game.room), in yellow
--   the room name: every line before the first whitespace-only one (the
--     game wraps a long name onto a second line, then sends blank lines)
--   the room's note (rmsg) from the mapper, in cyan, at most 2 lines
--   the rest of the block exactly as sent - its own blank lines, then the
--     map. The game keeps your # on the same row and column every time
--     (84 of 88 blocks in a /log capture, 2026-11-06), so nothing is
--     shifted or trimmed; trimming blank rows was what made it move
--   the [ Exits: ... ] line, on the row above the pane's bottom one, which
--     stays blank
-- Every line is cut at the pane's width (layout.MINIMAP_W). Down and up exits (< and >) become arrows,
-- as in map.tin, your # becomes MAP_ME and other players' * MAP_PLAYER.
--
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

local util = require("core.util")
local game = require("core.game")       -- the room's zone and vnum
local mapper = require("nav.mapper")   -- the room's note
local maprec = require("nav.maprec")   -- map record / plan / edit / drop / apply
local layout = require("core.layout")   -- the pane's size

local minimap = {}
local W, H = layout.MINIMAP_W, layout.MINIMAP_H
local MAP_NOTE = 2      -- most lines a room note may take
-- drawn in place of your #: pure green as 24-bit colour (00ff00) - bold
-- bright green (1;92) looked white. rune.style has only the basic colours,
-- so the code is written out, with a reset after it
local MAP_ME = "\27[38;2;0;255;0m●\27[0m"
-- drawn in place of another player's *: a red square (ff0000), the user's
-- pick - the game's own red * was too hard to see
local MAP_PLAYER = "\27[38;2;255;0;0m■\27[0m"

local map_buf = {}   -- { raw = ..., clean = ... } for each line of the block
local show_next = false   -- the next block answers a map you typed: show it
local quiet_next = false  -- the next block answers the login map: hide a blank after it
local dark = false        -- in a room you can't see: DARKNESS until the next block

local function blank(line) return util.blank(line.clean) end

-- Split a raw line into colour codes and characters (one UTF-8 character
-- each). Calls f(kind, text) with kind "esc" or "char"
local function each_token(raw, f)
  local i = 1
  while i <= #raw do
    local esc = raw:match("^\27%[[%d;]*m", i)
    if esc then
      f("esc", esc)
      i = i + #esc
    else
      local ch = raw:match("^[\1-\127\194-\244][\128-\191]*", i) or raw:sub(i, i)
      f("char", ch)
      i = i + #ch
    end
  end
end

-- Cut a raw line to w visible columns, keeping its colour codes. A line
-- that fits - every map row (the game's map is 29 wide, the pane 31) - is
-- only counted, by two native gsubs (codes out, then UTF-8 continuation
-- bytes), not walked a character at a time in Lua. Measured on lunar
-- (2026-11-09, real blocks): ~37 us a map block, was ~220 us; a line too
-- long (a long room name) still costs its walk, ~20 us each
local function crop(raw, w)
  local vis = raw:gsub("\27%[[%d;]*m", "")
  vis = vis:gsub("[\128-\191]", "")
  if #vis <= w then return raw .. "\27[0m" end
  local out, cols = {}, 0
  each_token(raw, function(kind, t)
    if kind == "esc" then
      out[#out + 1] = t
    elseif cols < w then
      out[#out + 1] = t
      cols = cols + 1
    end
  end)
  return table.concat(out) .. "\27[0m"
end

-- Your #, by its colour code (the game's help map key, and raw map blocks
-- /logged 2026-11-09): a bold magenta #, \27[1;35m#, the only one on the
-- map (the user). The code comes right in front of it - the game sends a
-- code before nearly every coloured character - so a plain find for code
-- and character does it, and the swap puts the code back after the dot.
-- Measured on lunar (2026-11-09, real blocks): ~6 us a map block; the old
-- walk, a Lua step per character, cost ~340 us. Another player
-- is a bold red *, \27[1;31m* (shops' and forests' * are other colours):
-- per row a plain find, and a gsub only on a row that has one (~1 us a row)
local ME_CODE = "\27[1;35m#"
local ME_SWAP = "\27[1;35m" .. MAP_ME .. "\27[1;35m"
local PLAYER_CODE, PLAYER_PAT = "\27[1;31m*", "\27%[1;31m%*"
local PLAYER_SWAP = "\27[1;31m" .. MAP_PLAYER .. "\27[1;31m"

-- The last colour code in a raw line, or nil if it has none. The game sets
-- a colour once and lets it run on into the next line, as a terminal would
-- (a wrapped room name's second line has no code of its own), but crop ends
-- every line with a reset - so the colour still on at the end of one line
-- is put in front of the next
local function last_sgr(raw)
  local found = nil
  for esc in raw:gmatch("\27%[[%d;]*m") do found = esc end
  return found
end

-- The header: zone | vnum, in yellow
local function header()
  local room = game.room
  local head = room.zone or ""
  if room.num and room.num ~= -1 then head = head .. " | " .. room.num end
  return rune.style.yellow(head)
end

-- On a run: the header, and RUNNING in the middle of the pane (FIGHTING
-- when a fight broke the run, DARKNESS in a room you can't see)
local stale = false   -- RUNNING or FIGHTING is up: no map block for this room yet
local block_seen = false   -- a map block came since the last room.info
local function word_layout(word)
  stale = word ~= "DARKNESS"
  local out = { header() }
  local mid = math.floor(H / 2)
  while #out < mid do out[#out + 1] = "" end
  out[#out + 1] = string.rep(" ", math.floor((W - #word) / 2)) .. rune.style.bold(word)
  util.pane("minimap", table.concat(out, "\n"))
end

-- The map block, made into the pane's rows once, at the block: the room
-- name, the map (your # marked) and the exits row, each cropped. Drawing
-- (draw_map) adds the header and note - those come from GMCP room.info,
-- which can come after the block, and then only they are redone
local parts   -- { name = { row, ... }, map = { row, ... }, exits = row or nil }

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
    p.name[#p.name + 1] = crop(raw, W)
    i = i + 1
  end
  -- the exits line, if any, is the last non-blank line
  local last = n
  while last >= i and blank(lines[last]) do last = last - 1 end
  if last >= i and lines[last].clean:match("^%s*%[ Exits:") then
    p.exits = crop(lines[last].raw, W)
    last = last - 1
  end
  while last >= i and blank(lines[last]) do last = last - 1 end
  -- the map as sent (as many rows as fit are drawn), your # and other
  -- players marked
  local marked = false
  for k = i, last do
    if #p.map >= H then break end
    local raw = carry .. lines[k].raw
    carry = last_sgr(raw) or carry
    if not marked then
      local h = raw:find(ME_CODE, 1, true)
      if h then
        raw, marked = raw:sub(1, h - 1) .. ME_SWAP .. raw:sub(h + #ME_CODE), true
      end
    end
    if raw:find(PLAYER_CODE, 1, true) then raw = raw:gsub(PLAYER_PAT, PLAYER_SWAP) end
    p.map[#p.map + 1] = crop((raw:gsub("<", "▼"):gsub(">", "▲")), W)
  end
  parts = p
end

local function draw_map()
  local p = parts
  local out = { header() }
  for _, r in ipairs(p.name) do out[#out + 1] = r end
  -- the room's note (rmsg, from the mapper)
  local room = game.room
  local mr = room.num and mapper.rooms[room.num]
  if mr and mr.note ~= "" then
    for k, l in ipairs(util.wrap(mr.note, W)) do
      if k > MAP_NOTE then break end
      out[#out + 1] = rune.style.cyan(l)
    end
  end
  -- the map, as many rows as fit above the exits row
  for _, r in ipairs(p.map) do
    if #out >= H - 2 then break end
    out[#out + 1] = r
  end
  if p.exits then
    while #out < H - 2 do out[#out + 1] = "" end
    out[#out + 1] = p.exits
    out[#out + 1] = ""   -- a blank bottom row under the exits
  end
  util.pane("minimap", table.concat(out, "\n"))
end

-- debug minimap: the run check, in the order things come - each state
-- change, each map block (its room name) and each room.info with the
-- state then and what it drew (map or RUNNING). Made to check state 12
-- (the header note); kept for when the minimap looks wrong
local dbg = require("core.debug").topic("minimap", "the run check: state changes, map blocks, each room.info and what it drew")
-- No redraw when the state leaves 12: run 10w's state went back before
-- its map block came, so a redraw then showed the start room's map a moment
local prev_state
rune.gmcp.on("char.status", function()
  if not dbg.on then return end
  local s = game.state
  if s == prev_state then return end
  dbg.log("state " .. tostring(prev_state) .. " -> " .. tostring(s))
  prev_state = s
end, { name = "minimap_debug_state" })

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
  draw_map()
  if dbg.on then
    dbg.log("map block: " .. util.trim(util.strip(parts.name[1] or "?")) .. " (state " .. tostring(game.state) .. ")")
  end
end, { name = "aard_map", priority = 10, gag = true, span = { to = "^<MAPEND>$", max = 120 } })

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
  if game.state ~= 12 then word_layout("DARKNESS") end
end, { name = "minimap_dark" })

-- The header and note come from GMCP room.info, which can arrive after the
-- map block: drawn again then, so they never show the room you just left
-- (core/game.lua has stored it already). Running (state 12): RUNNING
-- Fighting (state 8) with no block since the last room.info: FIGHTING. A
-- fight that breaks a run on its first step (seen live 2026-11-09: 3 to 8,
-- no 12, two room.info at 8 and no map block) drew the new header over the
-- old map. If the block comes after its room.info (a plain step into an
-- aggressive mob), it replaces FIGHTING with the map at once. Nothing is
-- sent mid-fight (the user: a command can queue and disrupt the fight);
-- the fight's end asks for the map (minimap_stale_fight)
rune.gmcp.on("room.info", function()
  local s = game.state
  local fighting = s == 8 and not block_seen
  block_seen = false
  local word = s == 12 and "RUNNING" or dark and "DARKNESS" or fighting and "FIGHTING" or nil
  if dbg.on then
    dbg.log(string.format("room.info %s %s (state %s) -> %s", tostring(game.room.num),
      tostring(game.room.name), tostring(s), word or "map"))
  end
  if word then
    word_layout(word)
  elseif parts then
    draw_map()
  end
end, { name = "minimap_room" })

-- map: the game's map, shown in the main output too (the minimap takes
-- every map block, so a typed map showed nothing). Also the map editing
-- commands (nav/mapper.lua):
--   map info                   where you are on the map (nav/mapper.lua)
--   map unlink <exit>          remove a wrong exit from this room
--   map exit <vnum> <command>  add an exit GMCP doesn't list (custom exits)
--   map record, plan, edit, drop, apply   record a way past a room (nav/maprec.lua)
rune.alias.exact("map", function(args)
  args = util.trim(args)
  local sub, rest = args:match("^(%S+)%s*(.-)$")
  if sub == "info" and rest == "" then
    mapper.info()
    return
  elseif sub == "unlink" then
    local msg, ok = mapper.unlink(rest)
    return (ok and util.say or util.warn)(msg)
  elseif sub == "exit" then
    local v, cmd = rest:match("^(%d+)%s+(.+)$")
    local msg, ok = mapper.add_exit(tonumber(v), cmd)
    return (ok and util.say or util.warn)(msg)
  elseif maprec.subs[sub] then
    maprec.command(sub, rest)
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
-- Cost: one compare per char.status
local fight_prev
rune.gmcp.on("char.status", function()
  local s, was = game.state, fight_prev
  fight_prev = s
  if stale and s == 8 and was ~= 8 then
    word_layout("FIGHTING")
  elseif stale and was == 8 and s ~= 8 then
    if dbg.on then dbg.log("fight over (8 -> " .. tostring(s) .. ") with the pane stale: silent map") end
    minimap.refresh()
  end
end, { name = "minimap_stale_fight" })

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("map", "map", "the game's map, in the main output too")
help.add("map exit", "map exit <vnum> <command>", "add a custom exit from this room to <vnum>, taken by <command>")
help.add("map unlink", "map unlink <exit>", "remove a wrong exit from this room")

return minimap
