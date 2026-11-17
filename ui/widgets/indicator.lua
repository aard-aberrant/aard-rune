-- panel:indicator { source, process, every, text, colors, x, y }
-- A fixed text in a color by state: "AC" bright while on, dim while off.
--   process(v..., now) -> the state (default: the first source's value)
--   colors[state]: the text's color in that state; a state with none
--     shows nothing
local screen = require("ui.screen")
local paint = screen.paint

return screen.add_widget("indicator", function(panel, t)
  local text, colors = t.text, t.colors
  return panel:widget { source = t.source, process = t.process, every = t.every, x = t.x, y = t.y,
    format = function(state)
      local c = colors[state == nil and "nil" or state]
      if c then return paint(c, text) end
    end }
end)
