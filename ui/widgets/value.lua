-- panel:value { source, process, every, label, label_color, whole, show, w,
--               color, styles, missing, zero, x, y }
-- A label and a value: "TNL 1234".
--   process(v..., now): the value from the data (default: the first
--     source's), rounded to what's shown; nil: not known. It may return a
--     second value, the seconds until it can change (with every)
--   show(v): the value as text (default format/generic.lua's num: 12, 12.5)
--   w: the value padded to w columns
--   color: a theme color, or color(v) -> one, or nil for none (default
--     theme.value)
--   styles: in a nested container, the color by its state: { live = "on",
--     ["*"] = "muted" } - theme names, read when drawn; a list of names
--     puts them together ({ "on", "emphasis" }: bright and underlined);
--     "*" any other state. A state it doesn't name: color as above
--   label_color: the label's own color; whole = true: color covers the
--     label too; whole(v) -> true: the same, for that value only
--   missing: the whole text while the value is nil (default: nothing);
--     zero: the whole text while it's 0 (default: shown as any value)
local screen = require("ui.screen")
local theme = require("ui.theme")
local F = require("format.generic")
local paint, pad, num, color_of = screen.paint, screen.pad, F.num, F.color_of
local concat = table.concat

-- a style: a theme name, or a list of them put together; a function that
-- reads it when drawn
local function style_of(spec)
  if type(spec) ~= "table" then return color_of(spec) end
  local parts = {}
  for k, n in ipairs(spec) do parts[k] = color_of(n) end
  return function()
    local on = {}
    for k = 1, #parts do local c = parts[k](); on[k] = c and c.on or "" end
    return { on = concat(on) }
  end
end

return screen.add_widget("value", function(panel, t)
  local label, show, w, color, missing, zero, whole = t.label or "", t.show or num, t.w, t.color, t.missing, t.zero, t.whole
  if t.label_color then label = paint(t.label_color, label) end
  local pick = type(color) == "function" and color or function() return color or theme.value end
  if t.styles then
    local by, base = {}, pick
    for st, spec in pairs(t.styles) do by[st] = style_of(spec) end
    local other = by["*"]
    pick = function(v)
      local f = by[panel.state] or other
      if f then return f() end
      return base(v)
    end
  end
  return panel:widget { source = t.source, process = t.process, every = t.every, x = t.x, y = t.y,
    format = function(v)
      if v == nil then return missing end
      if v == 0 and zero then return zero end
      local s = show(v)
      if w then s = pad(s, w) end
      local c = pick(v)
      if whole and (whole == true or whole(v)) then s = label .. s; return c and paint(c, s) or s end
      return label .. (c and paint(c, s) or s)
    end }
end)
