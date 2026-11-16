-- panel:infomsg(): modules/infomsg.lua's lines.
-- infomsg: up to 4 lines of your own text, each cut to the pane's width
local screen = require("ui.screen")
local theme = require("ui.theme")
require("ui.widgets.text")

return screen.add_widget("infomsg", function(p, t)
  for k = 1, 4 do
    p:text { y = "next", source = "infomsg.line" .. k, w = "*" }
  end
end)
