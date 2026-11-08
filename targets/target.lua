-- The target: the one mob you're after, shared by everything (tt++
-- modules/target.tin). At heart an area and a keyword; the name and room
-- come along when the source knows them. Any of them can be missing:
--   name   the mob's full name ("an amazon warrior") - checks where's answers
--   kw     a keyword the game takes for it - k attacks by it (fight/combat.lua)
--   zone   its area (GMCP zone)
--   room   its room's name - walked to as given, never guessed
--   src    who set it: "manual" (target, gm), "quest" (qx)
-- Commands:
--   target          shows it
--   target <kw>     sets it: that keyword, area unknown
--   target clear    drops it
--   gm              goes to it: to its area if that's elsewhere, else to
--                   its room - the known one, else the one where gives
--   gm <mob>        target <mob>, then gm
-- On entering the target's area - any area, while its area is unknown -
-- and on setting one, once a walk has ended, where checks whether the mob
-- is here: by name when there is one (travel.probe, which also finds a
-- keyword), else by keyword. Found with no area set: this is its area.
-- The check's lines are hidden; it says the room where found it in (and
-- the keyword, when that's new), or that where can't find it in its area.
-- A quest target is cleared by GMCP when it dies (targets/quest.lua); any other
-- stays until target clear - nothing else says reliably that it died.
-- target.on_change(fn): fn(t) whenever it's set, cleared, or learns its
-- room, keyword or area (targets/campaign.lua's pane row shows the room)

local util = require("core.util")
local game = require("core.game")       -- the area you're in
local tags = require("core.tags")       -- no check while a walk is running
local travel = require("nav.travel")   -- where, probe, go_area, go_room, areas
local soh = require("targets.soh")     -- School of Horror mobs' hidden keywords

-- The keyword: a School of Horror mob's saved one when none is given (its
-- names aren't its keywords) - set with the target, so k has it at once,
-- and tried first by the check
local function first_kw(t) return t.kw or soh.for_mob(t.name, t.zone or game.room.zone) end

local target = {}

local say, warn, trim = util.say, util.warn, util.trim

local cur        -- the target, or nil
local pending    -- a check is owed (new area, or a new target)
local checking   -- a check's where is out
local last_zone  -- the area you were last in

local function label(t) return t.name or t.kw or "?" end

local function area_name(zone)
  local a = zone and travel.areas[zone]
  return a and a.name or zone
end

local listeners = {}
function target.on_change(fn) listeners[#listeners + 1] = fn end
local function changed() for _, fn in ipairs(listeners) do fn(cur) end end

function target.get() return cur end

function target.set(t)
  t.kw = first_kw(t)
  cur = t
  pending = true
  say("[target] " .. label(t) .. (t.zone and (" in " .. area_name(t.zone)) or "") .. ".")
  changed()
end

-- Drops the target - with `src`, only one that source set
function target.clear(src)
  if cur and (not src or cur.src == src) then cur, pending = nil, false; changed() end
end

-- Is the mob here? See the top. Learns kw, and zone/room/name when unset
local function check()
  local t, zone = cur, game.room.zone
  checking = true
  local function found(kw, name, room)
    checking = false
    if cur ~= t then return end
    if not room then
      -- Not found: said only in its own area - while the area is unknown
      -- the check runs in every area you enter
      if travel.same_area(t.zone, zone) then warn("[target] " .. label(t) .. ": where can't find it in this area.") end
      return
    end
    local news = { "in " .. room }   -- where it is now, as where says
    if not t.zone then t.zone = zone end
    t.room = t.room or room
    if not t.kw then
      t.kw = kw
      news[#news + 1] = "keyword " .. kw
    end
    t.name = t.name or name
    say("[target] " .. label(t) .. ": " .. table.concat(news, ", ") .. ".")
    changed()
  end
  if t.name then
    travel.probe(t.name, function(kw, room) found(kw, t.name, room) end, first_kw(t))
  else
    travel.where(t.kw, function(name, room) found(t.kw, name, name and room) end)
  end
end

rune.gmcp.on("room.info", function()
  if game.room.zone ~= "" and game.room.zone ~= last_zone then
    last_zone = game.room.zone
    pending = true
  end
end, { name = "target_area" })

-- A check waits for the walk to end and for where to be free
rune.timer.every(1, function()
  if not (pending and cur) or checking or tags.walking() or travel.where_busy() then return end
  local zone = game.room.zone
  if zone == "" then return end
  pending = false
  if cur.zone and not travel.same_area(cur.zone, zone) then return end   -- not its area
  check()
end, { name = "target_check" })

function target.go()
  local t = cur
  if not t then return warn("[target] no target - target <kw>, gm <mob> or qx.") end
  local here = game.room.zone
  if t.zone and not travel.same_area(t.zone, here) then return travel.go_area(t.zone) end
  if t.room then return travel.go_room(t.zone or here, t.room, "target " .. label(t)) end
  -- No room: ask where, once it's free
  if checking or travel.where_busy() then
    rune.timer.after(1, function() if cur == t then target.go() end end)
    return
  end
  checking = true
  local function walk(kw, name, room)
    checking = false
    if cur ~= t then return end
    if not name then return warn("[target] " .. (room or (label(t) .. " isn't in this area."))) end
    t.kw, t.name, t.zone, t.room = t.kw or kw, t.name or name, here, room
    changed()
    travel.go_room(here, room, "target " .. label(t))
  end
  if t.kw then
    travel.where(t.kw, function(name, room) walk(t.kw, name, room) end)
  else   -- a name only (campaign, quest): find a keyword that fits
    travel.probe(t.name, function(kw, room) walk(kw, kw and t.name, room) end, first_kw(t))
  end
end

local function target_cmd(args)
  local text = trim(args)
  if text == "clear" then
    target.clear()
    return say("[target] cleared.")
  end
  if text ~= "" then
    target.set({ kw = text, src = "manual" })
    return
  end
  if not cur then return say("[target] none.") end
  say(string.format("[target] %s - keyword %s, %s, room %s (%s)", label(cur), cur.kw or "?",
    cur.zone and area_name(cur.zone) or "area ?", cur.room or "?", cur.src or "?"))
end

rune.alias.exact("target", target_cmd)
rune.alias.exact("t", target_cmd)

rune.alias.exact("gm", function(args)
  local text = trim(args)
  if text ~= "" then target.set({ kw = text, src = "manual" }) end
  target.go()
end)

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("target", "target / t [kw | clear]", "show the target, set it by keyword, or drop it")
help.add("gm", "gm [mob]", "go to the target (its area, then its room); with a mob: target it first")

return target
