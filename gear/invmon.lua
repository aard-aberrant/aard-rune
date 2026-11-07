-- What you're wearing, kept current from the game's invmon tag (tt++
-- modules/invmon.tin). "{invmon}<action>,<id>,<location>,<container>" -
-- action 2 is an item put on (at that wear location), 1 one taken off; the
-- others (inventory and containers) aren't used. core/tags.lua hides the lines.
--   invmon.worn            id (string) -> wear location
--   invmon.on(fn)          fn(action, id, loc) for every invmon line
--   invmon.seed(worn)      replace worn from an eqdata reply (gear/eq.lua does it
--                          at load: nothing is worn as far as this knows
--                          until then)

local tags = require("core.tags")   -- the invmon tag

local invmon = { worn = {} }
local listeners = {}

function invmon.on(fn) listeners[#listeners + 1] = fn end

function invmon.seed(worn) invmon.worn = worn end

-- The location an id is worn at, or nil
function invmon.where(id) return invmon.worn[tostring(id)] end

tags.on("invmon", function(rest)
  local action, id, loc = rest:match("^(%d+),(%d+),(%-?%d+),")
  if not action then return end
  action, loc = tonumber(action), tonumber(loc)
  if action == 2 then invmon.worn[id] = loc
  elseif action == 1 then invmon.worn[id] = nil end
  for _, fn in ipairs(listeners) do fn(action, id, loc) end
end)

return invmon
