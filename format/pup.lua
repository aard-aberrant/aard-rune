-- PUP formatters (require("format.pup")): "23s / 25s (104)" - the last
-- gap, the average, the count.
local num = require("format.generic").num

local M = {}
function M.last(v) return num(v) .. "s / " end
function M.avg(v) return num(v) .. "s" end
function M.n(v) return " (" .. num(v) .. ")" end
return M
