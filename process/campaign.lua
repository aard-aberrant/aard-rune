-- Campaign processors (require("process.campaign")): modules/campaign.lua's
-- data (cp.*).
local mins_left = require("process.generic").mins_left
local num = require("format.generic").num

local P = {}

-- Targets left and minutes left in one integer: count * 10000000 + minutes
-- (source: cp.on, cp.count, cp.ends)
function P.left(on, count, ends, now)
  if on and count and ends then
    local m, nxt = mins_left(ends, now)
    return count * 10000000 + m, nxt
  end
end

-- The area, with "k of n" when known (source: cp.on, cp.area, cp.area_k,
-- cp.area_n)
function P.area(on, area, k, n)
  if not (on and area) then return nil end
  if n and k then return area .. " (" .. num(k) .. " of " .. num(n) .. ")" end
  return area
end

-- The room, or true once the target is killed (source: cp.on, cp.killed,
-- cp.room)
function P.room(on, killed, room)
  if not on then return nil end
  if killed then return true end
  return room
end

-- MAZE / DEAD: the flag while on (source: cp.on, cp.maze or cp.dead)
function P.flag(on, f) return on and f or nil end

return P
