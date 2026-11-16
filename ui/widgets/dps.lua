-- panel:dps { x, y }: modules/dps.lua's damage per second and combat time,
-- " DPS 1234  1:05", 11 columns after the label: bright while fighting,
-- gray the last session's after a reset; "--" before any. Nothing while
-- the module isn't loaded.
local screen = require("ui.screen")
local theme = require("ui.theme")
local F = require("ui.format")
local paint, pad, num, clock = screen.paint, screen.pad, F.num, F.clock

return screen.add_widget("dps", function(panel, t)
  return panel:widget { source = { "dps.shown", "dps.rate", "dps.secs" }, every = 1, x = t and t.x, y = t and t.y,
    -- rate, time (capped) and the mode in one integer
    process = function(shown, rate, secs)
      local mode
      if shown == "none" then return 0 end
      if not secs then return nil end
      if shown == "live" then mode = rate and 1 or 2
      elseif shown == "last" and rate then mode = 3
      else mode = 4 end
      return ((rate or 0) * 6001 + math.min(secs, 6000)) * 5 + mode
    end,
    format = function(k)
      if not k then return "" end
      if k == 0 then return " DPS " .. pad(paint(theme.unavailable, "--"), 11) end
      local mode = k % 5
      local r = (k - mode) / 5
      local secs = r % 6001
      local rate = (r - secs) / 6001
      local tm = pad(clock(secs), 5)
      local s
      if mode == 1 then s = paint(theme.on, pad(num(rate), 5)) .. " " .. paint(theme.value, tm)
      elseif mode == 2 then s = paint(theme.unavailable, "--   ") .. " " .. paint(theme.value, tm)
      elseif mode == 3 then s = paint(theme.muted, pad(num(rate), 5)) .. " " .. paint(theme.muted, tm)
      else s = paint(theme.unavailable, "--   ") .. " " .. paint(theme.muted, tm) end
      return " DPS " .. pad(s, 11)
    end }
end)
