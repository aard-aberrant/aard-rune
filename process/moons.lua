-- Moon processors (require("process.moons")): modules/moons.lua's data.
local num = require("format.generic").num
local min = math.min

local P = {}

-- 3MN: the state's letter, then the text - u?? not known, n-- no window,
-- p<N>t all up for N more ticks, s soon (under 5 ticks) / l later:
-- "<ticks>t/<length>t" (snow/<length>t: now). nil while the module has
-- nothing (source: moon.need, moon.allup, moon.setleft, moon.ok, moon.lo,
-- moon.len)
function P.moons(need, allup, setleft, ok, lo, len)
  if need then return "u??" end
  if allup and setleft and setleft < 0 then return "n--" end
  if allup and setleft then return "p" .. num(setleft + 1) .. "t" end
  if ok == false then return "n--" end
  if lo and len then
    if lo < 1 then return "snow/" .. num(len) .. "t" end
    local l = num(min(lo, 999)) .. "t/" .. num(len) .. "t"
    return (lo < 5 and "s" or "l") .. l
  end
end

return P
