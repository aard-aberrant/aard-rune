-- Account processors (require("process.account")): modules/account.lua's
-- data (acct.*). The info pane gates them on acct.known (process/
-- generic.lua's gate).
local floor = math.floor

local P = {}

-- HR or DR with its minimum, in one number: the value * 2, + 1 when under
-- the minimum; nil until both HR and DR are known (both shown or neither).
-- which: "hr" or "dr". (source: acct.hr, acct.dr, acct.hr_min or dr_min)
function P.vs_min(which)
  local hr_side = which == "hr"
  return function(hr, dr, m)
    local v = hr_side and hr or dr
    if hr and dr then return v * 2 + ((m and v < m) and 1 or 0) end
  end
end

-- The stats (not int) under the minimum: "STR 20\1LCK 18"; nil when none
-- (source: acct.str, wis, con, dex, luck, then acct.stat_min)
P.STATS = { "str", "wis", "con", "dex", "luck" }
local STATS, NS = P.STATS, #P.STATS
local num = require("format.generic").num
function P.low_stats(...)
  local v = { ... }
  local m, out = v[NS + 1], {}
  if not m then return nil end
  for k, st in ipairs(STATS) do
    if v[k] and v[k] < m then out[#out + 1] = (st == "luck" and "LCK" or st:upper()) .. " " .. num(v[k]) end
  end
  if #out > 0 then return table.concat(out, "\1") end
end

return P
