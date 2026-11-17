-- Repop formatters (require("format.repop")): POP as MM:SS - red the last
-- 10 s, gray an estimate; "--" not known.
local theme = require("ui.theme")
local clock = require("format.generic").clock

local M = {}

function M.pop(k)
  if k < 0 then return "--   " end
  return clock((k - k % 3) / 3, true)
end

function M.pop_color(k)
  if k < 0 then return theme.unavailable end
  local band = k % 3
  return band == 0 and theme.danger or band == 1 and theme.muted or theme.value
end

return M
