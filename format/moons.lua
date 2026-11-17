-- Moon formatters (require("format.moons")): 3MN's text and color by its
-- state's letter (theme.moon comes with the module: read when drawn).
local theme = require("ui.theme")

local M = {}
local COLOR = { u = "unknown", p = "up", s = "soon" }

function M.moons(k) return k:sub(2) end
function M.moons_color(k)
  local b = k:sub(1, 1)
  return b == "n" and theme.unavailable or b == "l" and theme.muted or theme.moon[COLOR[b]]
end

return M
