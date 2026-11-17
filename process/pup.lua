-- PUP processors (require("process.pup")): modules/pup.lua's data.
local P = {}

-- The PUP container's state: "live", "over" (the session is over), "none"
-- before the first (source: pup.live, pup.last, pup.avg, pup.n)
function P.state(live, last, avg, n)
  if not (last and avg and n) then return "none" end
  return live and "live" or "over"
end

return P
