-- Campaign formatters (require("format.campaign")): process/campaign.lua's
-- values as value widgets' show and color.
local theme = require("ui.theme")
require("format.quest")   -- theme.target
local num, floor, fmt = require("format.generic").num, math.floor, string.format

local M = {}

-- "3 left, 2d 4h" / "3 left, 5h 12m"
function M.left(v)
  local m = v % 10000000
  local d, h = floor(m / 1440), floor(m % 1440 / 60)
  local t = d > 0 and fmt("%dd %dh", d, h) or fmt("%dh %dm", h, m % 60)
  return num(floor(v / 10000000)) .. " left, " .. t
end

-- the room (blue), or "killed - cn for next" (red)
function M.room(v) return v == true and "killed - cn for next" or v end
function M.room_color(v) return v == true and theme.target.gone or theme.target.room end

return M
