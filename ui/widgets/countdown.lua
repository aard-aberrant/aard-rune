-- panel:countdown { source, unit, ...value's options }
-- The time left until a moment (a data name holding an os.time): whole
-- seconds (unit "s", the default) or minutes rounded up (unit "m"), never
-- below 0; nil while the moment isn't known. Shown as panel:value shows a
-- number (label, w, color, missing, zero ... - ui/widgets/value.lua).
-- Processed only when the number shown changes: each second, or at each
-- minute's turn - at 0 not again until the moment changes.
local screen = require("ui.screen")
local P = require("process.generic")
require("ui.widgets.value")
local seconds, minutes = P.secs_left, P.mins_left

return screen.add_widget("countdown", function(panel, t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  o.process, o.every, o.unit = t.unit == "m" and minutes or seconds, 1, nil
  return panel:value(o)
end)
