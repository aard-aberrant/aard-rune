-- panel:timer { source, process, every, w, color, styles, missing, label, x, y }
-- A length of time in seconds, as m:ss ("1:05"; ">100m" from 100 minutes,
-- ui/format.lua's clock). The same options as panel:value (ui/widgets/
-- value.lua) - a value shown as a time.
local screen = require("ui.screen")
local clock = require("ui.format").clock
require("ui.widgets.value")

local function show(s) return clock(s) end

return screen.add_widget("timer", function(panel, t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  o.show = show
  return panel:value(o)
end)
