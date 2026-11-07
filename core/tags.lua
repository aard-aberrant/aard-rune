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
-- double blank. So the description's last line is noted, and when it was
-- blank, the blank after {/rdesc} is hidden. Both catch-alls are only on
-- for those few lines
local desc_last_blank = false

local desc_watch = rune.trigger.starts("", function(_, ctx)
  local clean = ctx.line:clean()
  if clean ~= "{/rdesc}" then desc_last_blank = blank(clean) end
end, { name = "tags_desc_watch", priority = 90 })
desc_watch:disable()

local eat_blank
eat_blank = rune.trigger.starts("", function(_, ctx)
  local clean = ctx.line:clean()
  if clean == "{/rdesc}" then return end   -- the line that turned it on
  eat_blank:disable()
  if blank(clean) then return false end
end, { name = "tags_eat_blank", priority = 5 })
eat_blank:disable()

-- Walks ------------------------------------------------------------------
-- A walk sends every step at once (nav/travel.lua), so the game shows every
-- room on the way. nav/travel.lua calls tags.hide_rooms(n) as it sends a walk of
-- n rooms: every room but the last is hidden, from {rname} to {/roomchars}
-- and the blank line after it - you see where you arrive. The minimap still
-- follows each room (a hidden line still reaches later triggers). A step
-- is one room (a portal or home step too); a count that's off only means
-- one room more or less shows.
-- The room being hidden is kept. If the walk stops short - a wrong exit
-- (tags.walk_stopped, from nav/travel.lua), a fight, a closed door - it's
-- printed after all: at once for a wrong exit, else 5 s after the last
-- room came in. No look is sent.
-- The game's runto sends a bare name line for each room it passes,
-- "{rname}Whitewind Avenue (G) (5882)" - those are always hidden, with the
-- blank line(s) after each.
local rooms_left = 0   -- rooms of the walk still to come
local held = {}        -- the last hidden room's lines, as they would show
local in_map = false   -- inside a hidden room's map block
local eating = false   -- after {/roomchars}: hide one blank line
local gen = 0          -- bumped by every hidden room, for the 5 s watchdog

local room_line
room_line = rune.trigger.starts("", function(_, ctx)
  local clean = ctx.line:clean()
  if eating then
    eating = false
    room_line:disable()
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
room_line:disable()

-- Print the held room - the walk stopped in it. Doubled blank lines are
-- squeezed (the hidden blank after {/rdesc} was kept too)
local function show_held()
  local prev_blank = false
  for _, raw in ipairs(held) do
    local b = blank(util.strip(raw))
    if not (b and prev_blank) then rune.echo(raw) end
    prev_blank = b
  end
  held = {}
end

-- A walk is running while rooms of it are still to come - nav/travel.lua's
-- wrong-exit message is only for a walk
function tags.walking() return rooms_left > 0 end

-- Stop hiding: the catch-all goes off whatever state it was in. A hidden
-- room whose {/roomchars} never came (a walk cut short, a fight in the
-- block) left it on, hiding every line after it - your own echo too
local function stop_hiding()
  room_line:disable()
  in_map, eating = false, false
end

function tags.walk_stopped()
  stop_hiding()
  if rooms_left == 0 and #held == 0 then return end
  rooms_left = 0
  show_held()
end

local function watchdog()
  gen = gen + 1
  local mine = gen
  rune.timer.after(5, function()
    if mine == gen then tags.walk_stopped() end
  end)
end

function tags.hide_rooms(n)
  rooms_left, held = n, {}
  watchdog()
end

-- A room name during a walk: hide this room, or show it - the last one.
-- Returns true to hide the {rname} line
local function room_starts(name_raw)
  if rooms_left > 1 then
    rooms_left = rooms_left - 1
    held, in_map, eating = { name_raw }, false, false
    room_line:enable()
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
  if tag == "rdesc" then
    desc_last_blank = false
    desc_watch:enable()
  elseif tag == "/rdesc" then
    desc_watch:disable()
    if desc_last_blank then eat_blank:enable() end
  end
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
