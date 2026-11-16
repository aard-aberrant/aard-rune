-- panel:barchart { source, values, labels, colors, zero, scale, cells, every }
-- A row per label: the label (right-aligned), a bar, the count.
--   values(v..., now) -> the counts, one per label (nil: no chart), and
--     optionally the seconds until one can change (ui/screen.lua's timed
--     widgets)
--   scale: counts per full cell (the bar in eighths of a cell); cells: the
--     bar's width (10) - more than fits ends in an arrow
--   colors[k]: row k's color; zero: a row whose count is 0
-- A list (ui/screen.lua): each row compared on its own, only a changed one
-- formatted.
local screen = require("ui.screen")
local rep, bar, rpad = string.rep, screen.bar, screen.rpad

return screen.add_widget("barchart", function(panel, t)
  local labels, colors, zero = t.labels, t.colors or {}, t.zero
  local scale, cells, lw = t.scale or 1, t.cells or 10, 0
  for _, l in ipairs(labels) do if #l > lw then lw = #l end end
  return panel:list {
    source = t.source, every = t.every, records = t.values,
    format = function(n, k)
      local text = rep(" ", lw - #labels[k]) .. labels[k] .. " " .. bar(n, scale, cells) .. " " .. rpad(tostring(n), 2)
      local c = n == 0 and zero or colors[k]
      return c and c(text) or text
    end,
  }
end)
