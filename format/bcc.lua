-- Black Claw Crag formatters (require("format.bcc")): process/bcc.lua's
-- values. Its colors (theme.bcc) come with the zone script: read when drawn.
local screen = require("ui.screen")
local theme = require("ui.theme")
local F = require("format.generic")
local paint, rpad, num = screen.paint, screen.rpad, F.num

local M = {}

-- "Axaldra: <dir>  safe: <side>"
function M.head(v)
  local dir, safe = v:match("^(.-)|(.*)$")
  local B = theme.bcc
  return paint(B.label, "Axaldra: ") .. paint(B.value, dir) .. "  " .. paint(B.label, "safe: ") .. paint(B.safe, safe)
end

-- A square: its seconds left (red under 2, orange under 3, then yellow),
-- or dots once clear (green on the safe side)
local hot = F.rule({ 2, 3 }, { "bcc.hot1", "bcc.hot2", "bcc.hot3" })
function M.cell(v)
  local B = theme.bcc
  if v > 0 then return paint(hot(v), rpad(num(v), 2)) end
  return paint(v == -1 and B.safe or B.quiet, "..")
end

-- Axaldra's column: @@ while there's a breath
function M.axaldra(d) return d and paint(theme.bcc.value, "@@") end

return M
