-- panel:pup { x, y }: modules/pup.lua's powerup gaps, " PUP 23s / 25s (104)"
-- - the last gap, the average (underlined), the count; 15 columns after
-- the label; gray once the run is over; "--" before the first.
local screen = require("ui.screen")
local theme = require("ui.theme")
local paint, pad, num = screen.paint, screen.pad, require("ui.format").num

return screen.add_widget("pup", function(panel, t)
  return panel:widget { source = { "pup.live", "pup.last", "pup.avg", "pup.n" }, every = 1, x = t and t.x, y = t and t.y,
    process = function(live, last, avg, n)
      if not (last and avg and n) then return "-" end
      return (live and "L" or "O") .. num(last) .. "s / " .. num(avg) .. "s (" .. num(n) .. ")"
    end,
    format = function(k)
      if k == "-" then return " PUP " .. pad(paint(theme.unavailable, "--"), 15) end
      local e = theme.emphasis
      local text = k:sub(2):gsub("/ (%d+s)", function(a) return "/ " .. e.on .. a .. e.off end, 1)
      return " PUP " .. pad(paint(k:sub(1, 1) == "L" and theme.on or theme.muted, text), 15)
    end }
end)
