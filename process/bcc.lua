-- Black Claw Crag processors (require("process.bcc")): modules/zones/
-- blackclaw.lua's breath grid (bcc.*).
local max = math.max

local P = {}

-- The last breath and the safe side: "dir|safe"; nil while no breath
-- (source: bcc.dir, bcc.safe)
function P.head(dir, safe) return dir and dir .. "|" .. (safe or "") end

-- A square: seconds left (> 0), then -1 clear on the safe side, -2 clear;
-- nil while no breath (source: bcc.dir, bcc.<square>, bcc.<square>_safe)
function P.cell(dir, t, safe, now)
  if not dir then return nil end
  local left = t and max(0, t - now) or 0
  if left > 0 then return left end
  return safe and -1 or -2
end

-- The grid's squares, a row at a time; false: Axaldra's column
P.GRID = { { "nw", "n", "ne" }, { "w", false, "e" }, { "sw", "s", "se" } }

return P
