-- Powerup pace (tt++ modules/pups.tin, without its status segment): average
-- seconds per powerup, timed from the first pup after pup track.
--   pup track   on (waiting for the next pup, which starts the clock) / off
--   pup reset   start over, on
--   pup         report: N s/pup | N pups | M:SS
-- The pace is worked out only when a pup lands, so it holds steady between
-- pups. The game's line (tt++'s pattern):
--   Congratulations, <name>. You have increased your powerups to <n>.
-- Its trigger exists only while tracking is on - added on, removed off
-- (core/util.lua's note on triggers: off for long, so removed, not disabled).
-- A /reload turns tracking off.
local util = require("core.util")

local say = util.say

local state = "off"   -- "off", "armed" (waiting for the first pup), "running"
local count, start, secs = 0, 0, 0
local trig

local function each() return count > 0 and math.floor(secs / count) or nil end

local function report(off)
  if count == 0 then return false end
  say(string.format("[pup] %ds/pup | %d pup%s | %d:%02d%s", each(), count, count == 1 and "" or "s",
    math.floor(secs / 60), secs % 60, off and " (off)" or ""))
  return true
end

local function on_pup(m)
  if state == "armed" then
    state, count, start, secs = "running", 0, os.time(), 0
    say("[pup] timer started at " .. m[2] .. ".")
  elseif state == "running" then
    count = count + 1
    secs = os.time() - start
  end
end

local function track(on)
  if on and not trig then
    trig = rune.trigger.regex("^Congratulations, (\\w+)\\. You have increased your powerups to (\\d+)\\.$",
      on_pup, { name = "pup_line" })
  elseif not on and trig then
    trig:remove()
    trig = nil
  end
end

rune.alias.exact("pup", function(args)
  local a = util.trim(args)
  if a == "reset" or (a == "track" and state == "off") then
    state, count, secs = "armed", 0, 0
    track(true)
    say("[pup] tracking on; the timer starts at your next powerup.")
  elseif a == "track" then
    state = "off"
    track(false)
    say("[pup] tracking off.")
    report(true)
  elseif a ~= "" then
    util.warn("[pup] pup [track|reset]")
  elseif state == "running" then
    if not report() then say("[pup] timer running; no pups since it started.") end
  elseif state == "armed" then
    say("[pup] tracking armed; waiting for your next powerup.")
  elseif not report(true) then
    say("[pup] tracking is off - pup track to start.")
  end
end)
