-- Quest processors (require("process.quest")): modules/quest.lua's data.
local mins_left = require("process.generic").mins_left
local NEVER = math.huge

local P = {}

-- The quest's time: minutes left, or "K" once the target is killed; nil
-- while there's no quest. (source: quest.on, quest.killed, quest.ends)
function P.left(on, killed, ends, now)
  if not on then return nil, NEVER end
  if killed then return "K", NEVER end
  return mins_left(ends, now)
end

-- QST (status bar): minutes until you can quest, "RD" ready, "AC" on one
-- ("ACW" after the warning), "--" not known. (source: quest.state,
-- quest.ready_at, quest.warn)
function P.status(state, at, warn, now)
  if state == "wait" and at and at > now then return (mins_left(at, now)) end
  if state == "wait" or state == "ready" then return "RD" end
  if state == "active" then return warn and "ACW" or "AC" end
  return "--"
end

-- The target's mob with its keyword, "a goblin (goblin)"; nil while not
-- on. The campaign's target has the same shape (source: <prefix>.on,
-- .mob, .keyword)
function P.mob(on, mob, kw)
  if on and mob then return kw and (mob .. " (" .. kw .. ")") or mob end
end

return P
