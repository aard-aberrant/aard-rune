-- DPS processors (require("process.dps")): modules/dps.lua's data.
local P = {}

-- The DPS container's state: "live", "last" (the last session's, after a
-- reset), "none" (none yet); nil before the first fight's time
-- (source: dps.shown, dps.secs)
function P.state(shown, secs)
  if shown == "none" then return "none" end
  if not secs then return nil end
  return shown == "live" and "live" or "last"
end

return P
