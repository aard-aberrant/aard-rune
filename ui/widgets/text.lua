-- panel:text { source, process, color, w, x, y }
-- Text from the data: a string, or a list of rows (a line each); nil shows
-- nothing.
--   process(v..., now): the text from the data (default: the first
--     source's)
--   color: a theme color for all of it (none: as it comes - the game's
--     own colors kept)
--   w = "*": each row cut to the rest of the line (colors kept); a number:
--     padded / cut to it
local screen = require("ui.screen")
local paint, crop, concat = screen.paint, screen.crop, table.concat

return screen.add_widget("text", function(panel, t)
  local color, cut = t.color, t.w == "*"
  local function row(s, w)
    if color then s = paint(color, s) end
    if cut then s = crop(s, w) end
    return s
  end
  return panel:widget { source = t.source, process = t.process, w = t.w, x = t.x, y = t.y,
    format = function(v, w)
      if v == nil then return nil end
      if type(v) ~= "table" then return row(v, w) end
      local out = {}
      for k = 1, #v do out[k] = row(v[k], w) end
      return concat(out, "\n")
    end }
end)
