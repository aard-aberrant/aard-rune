-- Autocast processors (require("process.autocast")): modules/autocast.lua's data.
local P = {}

-- The AC light: on or off and what's cast, in one string - "on:pri",
-- "off:sec", "on:cast" ... (source: ac.on, ac.attack)
function P.light(on, attack)
  return (on and "on:" or "off:") .. (attack or "pri")
end

return P
