-- Autocast formatters (require("format.autocast")): the AC light - AC1 the
-- primary attack, AC2 the secondary, AC* a command of your own; green on,
-- gray off.
local theme = require("ui.theme")
local paint = require("ui.screen").paint

local M = {}
local TEXT = { pri = "AC1", sec = "AC2", cast = "AC*" }

function M.light(v)
  local state, attack = v:match("^(%a+):(%a+)$")
  return paint(state == "on" and theme.on or theme.off, TEXT[attack] or "AC?")
end

return M
