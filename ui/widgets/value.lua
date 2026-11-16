-- panel:value { source, process, every, label, label_color, whole, show, w,
--               color, missing, zero, x, y }
-- A label and a value: "TNL 1234".
--   process(v..., now): the value from the data (default: the first
--     source's), rounded to what's shown; nil: not known. It may return a
--     second value, the seconds until it can change (with every)
--   show(v): the value as text (default ui/format.lua's num: 12, 12.5)
--   w: the value padded to w columns
--   color: a theme color, or color(v) -> one, or nil for none (default
--     theme.value)
--   label_color: the label's own color; whole = true: color covers the
--     label too
--   missing: the whole text while the value is nil (default: nothing);
--     zero: the whole text while it's 0 (default: shown as any value)
local screen = require("ui.screen")
local theme = require("ui.theme")
local paint, pad, num = screen.paint, screen.pad, require("ui.format").num

return screen.add_widget("value", function(panel, t)
  local label, show, w, color, missing, zero, whole = t.label or "", t.show or num, t.w, t.color, t.missing, t.zero, t.whole
  if t.label_color then label = paint(t.label_color, label) end
  local pick = type(color) == "function" and color or function() return color or theme.value end
  return panel:widget { source = t.source, process = t.process, every = t.every, x = t.x, y = t.y,
    format = function(v)
      if v == nil then return missing end
      if v == 0 and zero then return zero end
      local s = show(v)
      if w then s = pad(s, w) end
      local c = pick(v)
      if whole then s = label .. s; return c and paint(c, s) or s end
      return label .. (c and paint(c, s) or s)
    end }
end)
