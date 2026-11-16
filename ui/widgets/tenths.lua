-- panel:tenths { source, process, ...value's options }
-- A number to one decimal place: 87.5, 100.0 - any number.
--   process(v..., now) -> the number (default: the first source's); nil:
--     not known. It is rounded to tenths before it is compared, so only a
--     change you'd see redraws it
-- Shown as panel:value shows a value (label, w, color, styles, missing,
-- zero, whole ... - ui/widgets/value.lua); color(v) gets the rounded
-- number. HP as a percent: source = "hp", process = P.pct (ui/process.lua).
local screen = require("ui.screen")
local floor, fmt = math.floor, string.format
require("ui.widgets.value")

local function show(v) return fmt("%.1f", v) end
local function first(v) return v end

return screen.add_widget("tenths", function(panel, t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  local f = t.process or first
  o.process = function(...)
    local v, nxt = f(...)
    if v ~= nil then return floor(v * 10 + 0.5) / 10, nxt end
    return nil, nxt
  end
  o.show = show
  return panel:value(o)
end)
