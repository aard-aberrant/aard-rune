-- panel:quest(): modules/quest.lua's quest - the minutes left (red under
-- 5) or "killed, return to QM", then the target (area, room, mob).
local screen = require("ui.screen")
local theme = require("ui.theme")
require("ui.widgets.value")
require("ui.widgets.target")
local F, P = require("ui.format"), require("ui.process")
local num, mins_left = F.num, P.mins_left
local minutes = F.rule({ 5 }, { "danger", "value" })   -- red under 5

return screen.add_widget("quest", function(p)
  p:value { source = { "quest.on", "quest.killed", "quest.ends" }, every = 1,
    process = function(on, killed, ends, now)
      if not on then return nil, math.huge end
      if killed then return "K", math.huge end
      return mins_left(ends, now)
    end,
    show = function(v) return v == "K" and "killed, return to QM" or num(v) .. "m left" end,
    color = function(v) return v == "K" and theme.danger or minutes(v) end }
  p:target { on = "quest.on", prefix = "quest", lines = { "area", "room", "mob" } }
end)
