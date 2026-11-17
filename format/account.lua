-- Account formatters (require("format.account")): process/account.lua's
-- values.
local screen = require("ui.screen")
local theme = require("ui.theme")
local num = require("format.generic").num
local paint, floor, concat = screen.paint, math.floor, table.concat

local M = {}

-- TRN: the number, or "--" until known
function M.trains(t) return type(t) == "number" and num(t) or t end

-- HR / DR: the value, red when under the minimum
function M.vs_min(k) return num(floor(k / 2)) end
function M.vs_min_color(k) return k % 2 == 1 and theme.danger or theme.value end

-- The low stats, red, two spaces apart
function M.low_stats(v)
  if not v then return nil end
  local parts = {}
  for x in v:gmatch("[^\1]+") do parts[#parts + 1] = paint(theme.danger, x) end
  return concat(parts, "  ")
end

return M
