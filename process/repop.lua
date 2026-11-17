-- Repop processors (require("process.repop")): modules/repop.lua's data.
local P = {}

-- POP: seconds to the area's repop and its band in one integer - seconds
-- * 3 + 0 the last 10 s, 1 an estimate, 2 sure; -1 not known
-- (source: pop.next, pop.sure)
function P.pop(t, sure, now)
  local d = t and t - now
  if not d or d < 0 then return -1 end
  return d * 3 + (d < 11 and 0 or not sure and 1 or 2)
end

return P
