-- DPS meter (tt++ modules/dps.tin, which matched the MUSHclient
-- cirrus_data_tracker plugin):
--   damage    every "Your ... [N]" line - optionally "[3] " or "*[8] " in
--             front - except your group's combined attack and damage to
--             yourself (" you." / " you!" before the number)
--   time      on each damage line, the whole seconds since the previous one,
--             only if that gap is 1-10 s; a longer gap adds nothing
--   DPS       damage / time, "--" until there are 5 s of combat time
--   reset     on moving into another area (GMCP room.info zone), with a
--             line saying so; or "dps reset"
--   dps       prints the totals, and the last 5 sessions reset (newest first)
-- On status row 2, after Enemy (a row2_end slot): " | DPS 1234  1:23  ",
-- blank at the same width when there's no damage yet.

local util = require("core.util")
local status = require("panes.status")   -- the DPS segment's slot

local dps = {}
local d = { damage = 0, hits = 0, secs = 0, last = 0, area = nil }
local hist = {}

local function value()
  if d.secs < 5 then return "--" end
  return tostring(math.floor(d.damage / d.secs))
end

local function clock()
  return string.format("%d:%02d", math.floor(d.secs / 60), d.secs % 60)
end

local function report()
  return string.format("DPS: %s | %d dmg | %d hits | %s", value(), d.damage, d.hits, clock())
end

local function zero()
  if d.damage > 0 then
    table.insert(hist, 1, report() .. " | " .. tostring(d.area))
    hist[6] = nil
  end
  d.damage, d.hits, d.secs, d.last = 0, 0, 0, 0
end

rune.trigger.regex("^\\*?(?:\\[\\d+\\] )?Your (.*) \\[(\\d+)\\]$", function(m)
  local text = m[1]
  if text:find("^group's combined attack") or text:find(" you[.!]$") then return end
  local now = os.time()
  if d.last > 0 then
    local gap = now - d.last
    if gap > 0 and gap <= 10 then d.secs = d.secs + gap end
  end
  d.last = now
  d.damage = d.damage + (tonumber(m[2]) or 0)
  d.hits = d.hits + 1
end, { name = "dps_hit" })

rune.gmcp.on("room.info", function(r)
  if type(r) ~= "table" or not r.zone or r.zone == "" or r.zone == d.area then return end
  if d.area and d.damage > 0 then
    util.say("Area changed to " .. r.zone .. ". DPS meter reset (" .. clock() .. " of combat discarded).")
  end
  zero()
  d.area = r.zone
end, { name = "dps_area" })

-- 19 columns either way, so the row doesn't shift (the status pane redraws
-- each second, so it keeps up without being told)
function dps.segment()
  if d.damage == 0 then return string.rep(" ", 19) end
  return rune.style.gray(" | ") .. "DPS " .. rune.style.green(string.format("%-5s", value()))
    .. " " .. rune.style.cyan(string.format("%-6s", clock()))
end

table.insert(status.row2_end, dps.segment)

rune.alias.exact("dps", function(args)
  if (args or ""):match("^%s*reset%s*$") then
    zero()
    util.say("DPS meter reset.")
    return
  end
  util.say(d.damage > 0 and report() or "DPS: no damage since the last reset.")
  if hist[1] then
    rune.echo(rune.style.gray("--------------"))
    for i, h in ipairs(hist) do rune.echo(rune.style.gray(i .. ": " .. h)) end
  end
end)

return dps
