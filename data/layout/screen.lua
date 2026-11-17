-- The screen (require("data.layout.screen")): the containers' rectangles
-- and the sizes the layout files use. Same arrangement as the tt++ tmux
-- layout (bin/tmuxit.sh):
--   left column    group (what's left over), info (INFO_H), then a row of
--                  minimap (MINIMAP_W x MINIMAP_H) beside affects (the rest)
--   right column   RIGHT_W wide: chats (CHATS_H), the main output, the status
--                  bars (2 rows, data/layout/status.lua), the input
-- What goes in each container: data/layout/<name>.lua.
-- No container has a frame: a side between two is drawn as Rune's divider
-- line, so there's no line around the screen's edge. A divider is one
-- column.
-- The input is one row: at 3 rows or more Rune draws a rule above and below
-- it, and only a fixed size = 1 drops the one below. While a picker is open
-- it sizes itself instead (ui/picker.lua).

local layout = {
  RIGHT_W = 100,      -- the right column (data/layout/status.lua spreads its rows over it)
  CHATS_H = 12,
  INFO_H = 4,
  MINIMAP_W = 31,     -- longer map lines are cut
  MINIMAP_H = 22,
}

-- The containers (ui/screen.lua): rectangles, in cells. Negative x / y
-- count from the right / bottom edge; a negative w / h ends that far from
-- it; no w / h takes the rest. A border is inside the rectangle; a side
-- between two containers is drawn as Rune's divider line. The right column
-- is RIGHT_W wide; the left column the rest, its right border the line
-- between them
local screen = require("ui.screen")
local R, LEFT = layout.RIGHT_W, -(layout.RIGHT_W)   -- the left column ends where the right begins
local below = layout.INFO_H + 1 + layout.MINIMAP_H  -- info and the minimap row, under the group pane
screen:container { name = "group",   x = 0, y = 0, w = LEFT, h = -below, border = "right bottom" }
screen:container { name = "info",    x = 0, y = -below, w = LEFT, h = layout.INFO_H + 1, border = "right bottom" }
screen:container { name = "minimap", x = 0, y = -layout.MINIMAP_H, w = layout.MINIMAP_W + 1, border = "right" }
screen:container { name = "affects", x = layout.MINIMAP_W + 1, y = -layout.MINIMAP_H, w = LEFT, border = "right" }
screen:container { name = "chats",   x = -R, y = 0, h = layout.CHATS_H + 1, border = "bottom" }
screen:output { x = -R, y = layout.CHATS_H + 1, h = -4, border = "bottom" }
screen:container { name = "status1", x = -R, y = -4, h = 1 }
screen:container { name = "status2", x = -R, y = -3, h = 2, border = "bottom" }
screen:input { x = -R, y = -1 }

require("ui.picker")
screen.apply(false)

return layout
