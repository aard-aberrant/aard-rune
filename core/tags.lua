-- The game's inline tags (tags roomnames, roomdescs, exits, roomchars,
-- spellups, where, and config invmon). The tags stay on in the game, since
-- ported features will read them (decided 2026-11-06); this file keeps them
-- out of sight. A raw room block, from a tt++ log:
--   {rname}Hall of Champions (G)      tag, then text: the tag is cut out
--   {rdesc}                           a tag alone: the line is hidden
--     ...the description...
--   {/rdesc}
--   (the map block, which init.lua's minimap takes)
--   {exits}[ Exits: south ]
--   {roomchars}
--   Before you stands an outcast of an old holy order.
--   {/roomchars}
-- where: {where} alone, {where}<answer> or {/where}. The data tags
-- ({affon}154,2610, {invmon}2,123,-1,-1 and the rest) are always hidden.
-- Only these names are touched: the game's map data is full of {n},
-- {inside} and the like.
-- Features read tags through tags.on(name, fn), not triggers of their own:
-- this file's one trigger already looks at every tag line, so each extra
-- trigger would only be one more regex tried on every line of output.
-- fn(rest, ctx) runs first; returning false hides the line, nil lets this
-- file treat it as usual. Names may hold a word: "spellheaders affected".
-- Also here: hiding the rooms a walk passes through (tags.hide_rooms, below).

local util = require("core.util")
local colors = require("core.colors")
local game = require("core.game")   -- fighting (a fight ends a walk's hiding)

local tags = {}

local handlers = {}   -- tag name -> { fn, ... }, in the order registered

function tags.on(name, fn)
  local list = handlers[name] or {}
  list[#list + 1] = fn
  handlers[name] = list
end

-- name -> true for a tag that may come before text, "data" for one whose
-- line is always hidden
local TAGS = {
  rname = true, exits = true, where = true, ["/where"] = true,
  rdesc = true, ["/rdesc"] = true, roomchars = true, ["/roomchars"] = true,
  affon = "data", affoff = "data", sfail = "data", recon = "data",
  recoff = "data", invmon = "data", invitem = "data",
}

local blank = util.blank

-- The description often ends with a blank line of its own, and the game
-- sends another after {/rdesc}: with {/rdesc} hidden they would show as a
-- double blank. So when the description's last line was blank, the blank
-- after {/rdesc} is hidden. The description is a Rune span (not hidden):
-- its action runs once, at {/rdesc}, with the block's lines - nothing
-- looks at the lines in between
rune.trigger.exact("{rdesc}", function(_, ctx)
  local lines = ctx.lines
  local last = #lines >= 3 and lines[#lines - 1]
  if last and blank(last:clean()) and lines[#lines]:clean() == "{/rdesc}" then
    util.eat_blanks("{/rdesc}")
  end
end, { name = "tags_desc", priority = 90, span = { to = "^\\{/rdesc\\}$", max = 100 } })

-- Walks ------------------------------------------------------------------
-- A walk sends every step at once (nav/travel.lua), so the game shows every
-- room on the way. nav/travel.lua calls tags.hide_rooms(n) as it sends a walk of
-- n rooms: every room but the last is hidden, from {rname} to {/roomchars}
-- and the blank line after it - you see where you arrive. The minimap still
-- follows each room (a hidden line still reaches later triggers). A step
-- is one room (a portal or home step too); a count that's off only means
-- one room more or less shows.
-- The hider (a catch-all) exists only while a walk runs - added by
-- hide_rooms, removed when the walk ends - and between hidden rooms it lets
-- lines through. The room being hidden is kept. If the walk stops short - a wrong exit
-- (tags.walk_stopped, from nav/travel.lua), a fight, a closed door - it's
-- printed after all: at once for a wrong exit or a fight (an aggressive mob
-- on the way - GMCP char.status says fighting), else 5 s after the last
-- room came in. No look is sent.
-- The game's runto sends a bare name line for each room it passes,
-- "{rname}Whitewind Avenue (G) (5882)" - those are always hidden, with the
-- blank line(s) after each.
local rooms_left = 0   -- rooms of the walk still to come
local held = {}        -- the last hidden room's lines, as they would show
local hiding = false   -- inside a hidden room: {rname} to the blank after {/roomchars}
local in_map = false   -- inside a hidden room's map block
local eating = false   -- after {/roomchars}: hide one blank line
local watch            -- the 5 s watchdog's timer

local room_line = util.group(true)
room_line.add("starts", "", function(_, ctx)
  if not hiding then return end
  local clean = ctx.line:clean()
  if eating then
    eating, hiding = false, false
    if blank(clean) then return false end
    return
  end
  if clean:find("^{rname}") then return false end   -- the line that turned it on
  if clean == "<MAPSTART>" then in_map = true end
  if in_map then
    if clean == "<MAPEND>" then in_map = false end
    return false
  end
  if clean == "{/roomchars}" then
    eating = true
    return false
  end
  local tag = clean:match("^{(/?[a-z]+)}")
  if not (tag and TAGS[tag]) then held[#held + 1] = ctx.line:raw() end
  return false
end, { name = "tags_room_hide", priority = 95 })   -- after the tag rewrites

-- Print the held room - the walk stopped in it. Doubled blank lines are
-- squeezed (the hidden blank after {/rdesc} was kept too)
local function show_held()
  local prev_blank = false
  for _, raw in ipairs(held) do
    local b = blank(colors.strip(raw))
    if not (b and prev_blank) then rune.echo(raw) end
    prev_blank = b
  end
  held = {}
end

-- A walk is running while rooms of it are still to come - nav/travel.lua's
-- wrong-exit message is only for a walk
function tags.walking() return rooms_left > 0 end

-- Who started the walk: nil for nav/travel.lua's own (g, speedwalks), else
-- the owner given to hide_rooms ("maze": areas/partroxis.lua) - travel's
-- wrong-exit message leaves those walks to their owner
local owner
function tags.walk_owner() return rooms_left > 0 and owner or nil end

-- Stop hiding: the walk is over - the catch-all goes, whatever state it
-- was in. A hidden room whose {/roomchars} never came (a walk cut short, a
-- fight in the block) would otherwise hide every line after it
local function stop_hiding()
  room_line.set(false)
  hiding, in_map, eating = false, false, false
  if watch then watch:cancel(); watch = nil end
end

function tags.walk_stopped()
  stop_hiding()
  if rooms_left == 0 and #held == 0 then return end
  rooms_left = 0
  show_held()
end

-- A fight during a walk stops it where you are: that room shows at once,
-- before the fight's lines, not 5 s into them (seen live 2026-11-07: it
-- looked like a stray look). Moves sent after it show their rooms, if any run
rune.gmcp.on("char.status", function()
  if game.state == 8 and (rooms_left > 0 or #held > 0) then tags.walk_stopped() end
end, { name = "tags_walk_fight" })

local function watchdog()
  if watch then watch:cancel() end
  watch = rune.timer.after(5, function() watch = nil; tags.walk_stopped() end)
end

function tags.hide_rooms(n, who)
  rooms_left, held, owner = n, {}, who
  room_line.set(true)
  watchdog()
end

-- A room name during a walk: hide this room, or show it - the last one.
-- Returns true to hide the {rname} line
local function room_starts(name_raw)
  if rooms_left > 1 then
    rooms_left = rooms_left - 1
    held, hiding, in_map, eating = { name_raw }, true, false, false
    watchdog()
    return true
  end
  stop_hiding()   -- the last room shows, even if the one before never closed
  rooms_left, held = 0, {}
  return false
end

-- Every tag line --------------------------------------------------------

rune.trigger.regex("^\\{(/?[a-z]+(?: [a-z]+)?)\\}(.*)$", function(m, ctx)
  local tag, rest = m[1], m[2]
  local list = handlers[tag]
  if list then
    local hide = false
    for i = 1, #list do if list[i](rest, ctx) == false then hide = true end end
    if hide then return false end
  end
  local kind = TAGS[tag]
  if not kind then return end
  -- A failed cast's {sfail} has a blank line after it, which would show as
  -- a double blank (tt++ affects.tin, seen live): hidden with it
  if tag == "sfail" then util.eat_blanks(ctx.line:clean()); return false end
  if kind == "data" or blank(rest) then return false end
  -- Cut the tag out of the raw line, so the colours stay
  local raw = ctx.line:raw()
  local s, e = raw:find("{" .. tag .. "}", 1, true)
  local line = s and (raw:sub(1, s - 1) .. raw:sub(e + 1)) or rest
  -- A where answer on one line carries its closing tag too: cut that as well
  if tag == "where" then
    local c1, c2 = line:find("{/where}", 1, true)
    if c1 then line = line:sub(1, c1 - 1) .. line:sub(c2 + 1) end
  end
  if tag == "rname" then
    if rest:find("%(%d+%)%s*$") then   -- a runto hop, and the blank line(s) after it
      util.eat_blanks(ctx.line:clean())
      return false
    end
    if room_starts(line) then return false end
  end
  return line
end, { name = "tags_lines", priority = 10 })

return tags
