-- DPS meter (tt++ modules/dps.tin, which matched the MUSHclient
-- cirrus_data_tracker plugin):
--   damage    every "Your ... [N]" line - optionally "[3] " or "*[8] " in
--             front - except your group's combined attack and damage to
--             yourself (" you." / " you!" before the number)
--   time      combat time: every second GMCP char.status says you're
--             fighting (state 8), plus one second for each second you land
--             a hit while it doesn't - a first blow before the fight is
--             reported, a kill in one hit. Walking, looting and resting
--             count nothing. Whole seconds (os.time): a fight's share comes
--             out right on average
--   DPS       damage / time, "--" until there are 5 s of combat time
--   reset     on moving into another area (GMCP room.info zone), with a
--             line saying so; or "dps reset"
--   dps       the sessions, newest first, as pup lists its own: start,
--             length, DPS, damage, hits, area - the one under way first, then
--             the last 5 from the log
--   log       each session, when it ends (a reset, /reload, disconnect), one
--             line in dps.log (util.state_dir: ~/.local/state/rune),
--             tab-separated: start, seconds, damage, hits, area
-- On status row 1, after 3MN (panes/status.lua): "DPS 1234  1:23",
-- always shown (a gray "--" before any damage, as PUP's, no clock; after a
-- reset the last session's numbers, dimmed, until the next damage).

local util = require("lib.util")
local game = require("modules.game")        -- fighting (char.status state)

-- debug dps: each solo second counted, and the fight clock going on and off
local dbg = require("lib.debug").topic("dps", "the fight clock on and off, and each hit second counted outside a fight")

local dps = {}
-- secs: combat time so far, not counting the fight under way (since: when
-- it began, or nil); solo: the last second a hit was counted outside a fight;
-- start: os.time() of the session's first damage
local d = { damage = 0, hits = 0, secs = 0, since = nil, solo = 0, area = nil, start = nil }
local last   -- the last session reset { start, secs, damage, hits, area }, dimmed on the row

local function secs()
  return d.secs + (d.since and (os.time() - d.since) or 0)
end

local function value(damage, t)
  if t < 5 then return "--" end
  return tostring(math.floor(damage / t))
end

local clock = util.clock

local function session()
  return { start = d.start, secs = secs(), damage = d.damage, hits = d.hits, area = d.area }
end

local LOG = "dps.log"

-- Published (ui/view.lua): what DPS shows - this session once it has
-- damage, else the last one (before a reset) until new damage, else none.
-- Read when drawn (getters - nothing built at each hit); rate and secs
-- from the clock too (a fight's time runs on), compared each second;
-- touched at a hit outside a fight and the session's first, fight start or
-- end, and reset
local function shown()
  if d.damage > 0 then return "live" end
  if last then return "last" end
  return "none"
end
local function shown_secs()
  if d.damage > 0 then return secs() end
  return last and last.secs or nil
end
local view = require("ui.view")
local P = view.provides("aard.dps", "your damage per second, this area's session", {
  ["dps.shown"] = { "text", "live (this session), last (the one before a reset, until new damage) or none",
                    get = shown },   -- changes only when published, not with the clock
  ["dps.rate"]  = { "number", "the shown session's damage per second, whole; nil under 5 s", time = true,
                    get = function()
                      local t = shown_secs()
                      if not t or t < 5 then return nil end
                      return math.floor((d.damage > 0 and d.damage or last.damage) / t)
                    end },
  ["dps.secs"]  = { "seconds", "the shown session's combat time", get = shown_secs, time = true },
})
local touches = { P.toucher("dps.shown"), P.toucher("dps.rate"), P.toucher("dps.secs") }
local function publish()
  for _, t in ipairs(touches) do t() end
end

local function zero()
  if d.damage > 0 then
    last = session()
    util.append_log(LOG, table.concat({ os.date("%Y-%m-%d %H:%M:%S", last.start), last.secs,
      last.damage, last.hits, tostring(last.area or "?") }, "\t"), "[dps]")
  end
  d.damage, d.hits, d.secs, d.solo, d.start = 0, 0, 0, 0, nil
  if d.since then d.since = os.time() end   -- a fight under way counts on from now
  publish()
end

rune.trigger.regex("^\\*?(?:\\[\\d+\\] )?Your (.*) \\[(\\d+)\\]$", function(m)
  local text = m[1]
  if text:find("^group's combined attack") or text:find(" you[.!]$") then return end
  -- outside a fight GMCP knows of: this second counts, once
  local now = os.time()
  if not d.since and now ~= d.solo then
    d.secs, d.solo = d.secs + 1, now
    if dbg.on then dbg.log("hit outside a GMCP fight: +1 s") end
  end
  if d.damage == 0 then d.start = now end
  d.damage = d.damage + (tonumber(m[2]) or 0)
  d.hits = d.hits + 1
  -- in a fight the widget's clock shows it, once a second; outside one
  -- (a hit GMCP calls no fight) and the session's first damage, at once
  if not d.since or d.hits == 1 then publish() end
end, { name = "dps_hit" })

-- The fight's clock: on at state 8, off when it ends. A hit's second
-- already counted (a first blow just before) isn't counted twice. Run
-- when aard.char's fighting changes (modules/game.lua publishes it in its
-- char.status handler - the same moment), not on each char.status
view.subscribe("fighting", function()
  local now = os.time()
  if game.state == 8 and not d.since then
    d.since = now
    if d.solo == now then d.secs = d.secs - 1 end
    if dbg.on then dbg.log("fight on" .. (d.solo == now and ", this second's hit taken back" or "")) end
  elseif game.state ~= 8 and d.since then
    if dbg.on then dbg.log("fight off after " .. (now - d.since) .. " s") end
    d.secs, d.since = d.secs + (now - d.since), nil
  else
    return
  end
  publish()
end)

rune.gmcp.on("room.info", function(r)
  if type(r) ~= "table" or not r.zone or r.zone == "" or r.zone == d.area then return end
  if d.area and d.damage > 0 then
    util.say("[dps] area changed to " .. r.zone .. " - reset after " .. clock(secs()) .. " of combat.")
  end
  zero()
  d.area = r.zone
end, { name = "dps_area" })

-- A /reload or a disconnect ends the session: logged, as at a reset
rune.hooks.on("reloading", zero, { name = "dps_log_reload" })
rune.hooks.on("disconnected", zero, { name = "dps_log_disconnect" })

-- DPS on the status row: panes/status.lua
publish()

rune.alias.exact("dps", function(args)
  if (args or ""):match("^%s*reset%s*$") then
    zero()
    util.say("[dps] reset.")
    return
  end
  local list = {}
  if d.damage > 0 then
    local s = session()
    s.when, s.now = os.date("%Y-%m-%d %H:%M", s.start), true
    list[1] = s
  end
  for _, line in ipairs(util.log_tail(LOG, 5)) do
    local when, t, dmg, hits, area = line:match("^(%d+%-%d+%-%d+ %d+:%d+):%d+\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
    if when then
      list[#list + 1] = { when = when, secs = tonumber(t), damage = tonumber(dmg), hits = tonumber(hits), area = area }
    end
  end
  if not list[1] then util.say("[dps] no sessions yet - your first hit starts one."); return end
  util.say("[dps] sessions, newest first:")
  for _, s in ipairs(list) do
    rune.echo(string.format("  %s  %6s  %5s dps  %7d dmg  %4d hit%s  %s%s", s.when,
      clock(s.secs), value(s.damage, s.secs), s.damage, s.hits, s.hits == 1 and " " or "s",
      tostring(s.area or "?"), s.now and "  (on now)" or ""))
  end
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("dps", "dps [reset]", "damage per second: the sessions, newest first - start, length, DPS, damage, hits, area (logged to ~/.local/state/rune/dps.log); reset starts over (moving to another area resets too)")

return dps
