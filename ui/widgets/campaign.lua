-- panel:campaign(): modules/campaign.lua's campaign - targets left and the
-- time left (as days/hours or hours/minutes); the area (with "k of n");
-- the room, or "killed - cn for next"; the mob, with (MAZE) for the
-- Partroxis maze and (DEAD) while it hasn't repopped.
local screen = require("ui.screen")
local theme = require("ui.theme")
require("ui.widgets.value")
require("ui.widgets.text")
require("ui.widgets.indicator")
require("ui.widgets.target")
local F, P = require("ui.format"), require("ui.process")
local num, mins_left, floor, fmt = F.num, P.mins_left, math.floor, string.format

return screen.add_widget("campaign", function(p)
  -- count and minutes left in one integer
  p:value { source = { "cp.on", "cp.count", "cp.ends" }, every = 1,
    process = function(on, count, ends, now)
      if on and count and ends then
        local m, nxt = mins_left(ends, now)
        return count * 10000000 + m, nxt
      end
    end,
    show = function(v)
      local m = v % 10000000
      local d, h = floor(m / 1440), floor(m % 1440 / 60)
      local t = d > 0 and fmt("%dd %dh", d, h) or fmt("%dh %dm", h, m % 60)
      return num(floor(v / 10000000)) .. " left, " .. t
    end }
  p:text { y = "next", source = { "cp.on", "cp.area", "cp.area_k", "cp.area_n" }, color = theme.target.area,
    process = function(on, area, k, n)
      if not (on and area) then return nil end
      if n and k then return area .. " (" .. num(k) .. " of " .. num(n) .. ")" end
      return area
    end }
  p:value { y = "next", source = { "cp.on", "cp.killed", "cp.room" },
    process = function(on, killed, room)
      if not on then return nil end
      if killed then return true end
      return room
    end,
    show = function(v) return v == true and "killed - cn for next" or v end,
    color = function(v) return v == true and theme.target.gone or theme.target.room end }
  p:target { on = "cp.on", prefix = "cp", lines = { "mob" } }
  p:indicator { source = { "cp.on", "cp.maze" }, text = " (MAZE)", colors = { [true] = theme.caution },
    process = function(on, m) return on and m or nil end }
  p:indicator { source = { "cp.on", "cp.dead" }, text = " (DEAD)", colors = { [true] = theme.danger },
    process = function(on, d) return on and d or nil end }
end)
