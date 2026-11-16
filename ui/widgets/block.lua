-- panel:block { source, process, style, flash, x, y }
-- A heading and a body across the panel, every row filled to the panel's
-- width on a style: the heading, an empty row when there is room for it,
-- then the body wrapped to the width and cut to the rows left. Nothing
-- while the heading is nil.
--   source: the data names; process(v..., now) -> heading, body (default:
--     the first two sources)
--   style: a theme name (format/generic.lua's color_of: "alert", "bcc.hot1");
--     flash: a second one - the two swap each second
local screen = require("ui.screen")
local util = require("lib.util")
local color_of = require("format.generic").color_of
local RESET = require("ui.colors").RESET
local rep, min, max, concat, select = string.rep, math.min, math.max, table.concat, select

local function two(h, b) return h, b end

return screen.add_widget("block", function(panel, t)
  local on, off = color_of(t.style), t.flash and color_of(t.flash)
  local f = t.process or two
  local src = type(t.source) == "table" and t.source or { t.source }
  local n = #src
  return panel:widget { source = t.source, every = off and 1 or nil, w = "*", x = t.x, y = t.y,
    process = function(...)
      local heading, body = f(...)
      if heading == nil then return nil end
      local lit = not off or select(n + 1, ...) % 2 == 0
      return (lit and "1" or "0") .. heading .. "\1" .. (body or "")
    end,
    format = function(v, wd, room)
      local heading, body = v:sub(2):match("^(.-)\1(.*)$")
      local c = (v:sub(1, 1) == "1" and on or off)()
      c = c and c.on or ""
      local function fill(x) return #x < wd and x .. rep(" ", wd - #x) or x:sub(1, wd) end
      local lines = util.wrap(body, wd)
      local most = max(room - 1, 0)
      local rows = { heading }
      if #lines < most then rows[2] = "" end
      for k = 1, min(#lines, most) do rows[#rows + 1] = lines[k] end
      for k, row in ipairs(rows) do rows[k] = c .. fill(row) .. RESET end
      return concat(rows, "\n")
    end }
end)
