-- POP on status row 1: the countdown to this area's next repop (tt++
-- modules/repop.tin, after Areia's MUSHclient repop timer), and pop.
-- Two sources:
--   GMCP comm.repop { zone } - an area just repopped. Repops in an area
--     land a whole number of minutes after the last one, so this gives the
--     seconds
--   the ranger spell sense life (cast by you - nothing is cast for you),
--     tt++'s patterns:
--       You sense that life will return to this area in roughly 4-5 minutes.
--       You sense that life will return to this area in roughly 6 hours and 15 minutes.
--       You sense that life will return to this area within the next 30 seconds.
--     ("within" anything else: a minute)
-- With both, the countdown is exact: yellow (cyan in this status pane's
-- colours, as every value). With sense life alone it's an estimate from the
-- top of its range: grey. Red for the last 10 seconds; 99:99 over 99
-- minutes; "--" with nothing known for this area. An estimate never
-- replaces an exact countdown, and of two estimates the earlier wins (each
-- is an upper bound), so recasting only tightens it - unless the exact time
-- would be later than sense life's own limit: then the seconds are wrong,
-- and the reading is used as an estimate.
--   pop   how the last 5 exact countdowns compared with the repops
-- Per area, by GMCP zone; kept in rune.session, so a /reload keeps it.

local util = require("core.util")
local theme = require("core.theme")
local game = require("core.game")
local status = require("panes.status")   -- POP, first of the row1_end slots

local say, warn = util.say, util.warn

-- zone -> { seen = last repop, next = countdown's end, sure = exact,
-- pred = the last exact prediction (kept after next runs out, to compare a
-- late repop) } - all os.time()
local areas = {}
local function area(zone)
  local a = areas[zone]
  if not a then
    local s = rune.session.get("repop_" .. zone) or ""
    local seen, nxt, sure, pred = s:match("^(%d*),(%d*),(%d),(%d*)$")
    a = { seen = tonumber(seen), next = tonumber(nxt), sure = sure == "1", pred = tonumber(pred) }
    areas[zone] = a
  end
  return a
end
local function save(zone, a)
  rune.session.set("repop_" .. zone, (a.seen or "") .. "," .. (a.next or "") .. ","
    .. (a.sure and "1" or "0") .. "," .. (a.pred or ""))
end

local stats = {}   -- the last 5 checked exact countdowns, as lines

rune.gmcp.on("comm.repop", function(d)
  local zone = type(d) == "table" and d.zone
  if not zone then return end
  local a, now = area(zone), os.time()
  if a.pred then
    local late = now - a.pred
    stats[#stats + 1] = string.format("%s  %-16s %s%d s", os.date("%H:%M:%S", now), zone, late > 0 and "+" or "", late)
    if #stats > 5 then table.remove(stats, 1) end
  end
  a.seen, a.next, a.sure, a.pred = now, nil, false, nil
  save(zone, a)
  rune.ui.refresh_bars()
end, { name = "repop_seen" })

-- A sense life reading: `mins` whole minutes (nil: no range - always an
-- estimate), `secs` sense life's own limit
local function reading(mins, secs)
  local zone = game.room.zone
  if zone == "" then warn("[pop] area unknown (no GMCP room yet) - move a room and cast again."); return end
  local a, now = area(zone), os.time()
  local new, sure, contra = now + secs, false, false
  if mins and a.seen then
    local exact = now + mins * 60 + (60 - (now - a.seen) % 60) % 60
    if exact > new then
      contra = true
      warn("[pop] sense life says sooner than the last repop's seconds allow - using an estimate.")
    else
      new, sure = exact, true
    end
  end
  if not sure and not contra and a.next and a.next > now and (a.sure or a.next < new) then return end
  a.next, a.sure, a.pred = new, sure, sure and new or nil
  save(zone, a)
  rune.ui.refresh_bars()
end

local SENSE = "You sense that life will return to this area "
rune.trigger.starts(SENSE, function(_, ctx)
  local rest = ctx.line:clean():sub(#SENSE + 1)
  local lo, hi = rest:match("^in roughly (%d+)%-(%d+) minutes%.$")
  if lo then reading(tonumber(lo), tonumber(hi) * 60); return end
  local h = rest:match("^in roughly (%d+) hours?")
  if h then
    local m = rest:match("and (%d+) minute") or 0
    reading(nil, (tonumber(h) * 60 + tonumber(m)) * 60)
    return
  end
  if rest:match("^within ") then
    reading(0, rest == "within the next 30 seconds." and 30 or 60)
    return
  end
end, { name = "repop_sense" })

-- POP: MM:SS, 5 columns so the row doesn't shift
table.insert(status.row1_end, 1, function()
  local a = game.room.zone ~= "" and area(game.room.zone)
  local left = a and a.next and a.next - os.time()
  if not left or left < 0 then
    if a and a.next then a.next, a.sure = nil, false end
    return status.field("POP", "--", 5)
  end
  local v = left > 5999 and "99:99" or string.format("%02d:%02d", math.floor(left / 60), left % 60)
  return status.field("POP", v, 5, left <= 10 and theme.danger or not a.sure and theme.muted or nil)
end)

rune.alias.exact("pop", function()
  if #stats == 0 then say("[pop] no exact countdown checked against a repop yet."); return end
  say("[pop] the last " .. #stats .. " exact countdowns (repop minus prediction):")
  for _, l in ipairs(stats) do rune.echo("  " .. l) end
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("pop", "pop", "how the last 5 exact repop countdowns (POP) compared with the repops")
