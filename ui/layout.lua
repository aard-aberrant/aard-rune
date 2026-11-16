-- The screen layout and every pane's size (require("ui.layout")). Same
-- arrangement as the tt++ tmux layout (bin/tmuxit.sh):
--   left column    group (what's left over), info (INFO_H), then a row of
--                  minimap (MINIMAP_W x MINIMAP_H) beside affects (the rest)
--   right column   RIGHT_W wide: chats (CHATS_H), the main output, the status
--                  bars (2 rows, panes/status.lua), the input
-- No pane has a border: dividers = true draws lines between panes only, so
-- there's no frame around the screen's edge. Sizes are the content, since
-- nothing has a border to count. A divider is one column.
-- The input is one row: at 3 rows or more Rune draws a rule above and below
-- it, and only a fixed size = 1 drops the one below. While a picker is open
-- it sizes itself instead - see the picker wrapper below.
-- Requires nothing: the panes' modules ask it for their sizes.

local layout = {
  RIGHT_W = 100,      -- the right column (panes/status.lua spreads its rows over it)
  CHATS_H = 12,
  INFO_H = 4,
  MINIMAP_W = 31,     -- longer map lines are cut
  MINIMAP_H = 22,
}

-- The panels (ui/screen.lua): rectangles, in cells. Negative x / y count
-- from the right / bottom edge; a negative w / h ends that far from it; no
-- w / h takes the rest. A border is inside the rectangle; a side between
-- two panels is drawn as Rune's divider line. The right column is RIGHT_W
-- wide; the left column the rest, its right border the line between them
local screen = require("ui.screen")
local R, LEFT = layout.RIGHT_W, -(layout.RIGHT_W)   -- the left column ends where the right begins
local below = layout.INFO_H + 1 + layout.MINIMAP_H  -- info and the minimap row, under the group pane
screen:panel { name = "group",   x = 0, y = 0, w = LEFT, h = -below, border = "right bottom" }
screen:panel { name = "info",    x = 0, y = -below, w = LEFT, h = layout.INFO_H + 1, border = "right bottom" }
screen:panel { name = "minimap", x = 0, y = -layout.MINIMAP_H, w = layout.MINIMAP_W + 1, border = "right" }
screen:panel { name = "affects", x = layout.MINIMAP_W + 1, y = -layout.MINIMAP_H, w = LEFT, border = "right" }
screen:panel { name = "chats",   x = -R, y = 0, h = layout.CHATS_H + 1, border = "bottom" }
screen:output { x = -R, y = layout.CHATS_H + 1, h = -4, border = "bottom" }
screen:panel { name = "status1", x = -R, y = -4, h = 1 }
screen:panel { name = "status2", x = -R, y = -3, h = 2, border = "bottom" }
screen:input { x = -R, y = -1 }
local apply = screen.apply

-- Pickers (find, g's area list, Ctrl+R history, the / command list) draw
-- inside the input's area, so a one-row input leaves them no room (tried
-- live). While one is open the input sizes itself again - it grows to fit,
-- with its rules - and goes back to one row when it closes. Every picker,
-- Rune's own too, opens through rune.ui.picker.show, and Rune calls
-- rune.ui.picker._settle (internal) when one closes, chosen or Esc - Rune
-- source, lua/core/00_init.lua. Not output search (Ctrl+F): Lua isn't told
-- when it closes
local picker_show, picker_settle = rune.ui.picker.show, rune.ui.picker._settle
local pickers_open = 0
function rune.ui.picker.show(opts)
  pickers_open = pickers_open + 1
  if pickers_open == 1 then apply(true) end
  local ok, err = pcall(picker_show, opts)
  if not ok then
    pickers_open = pickers_open - 1
    if pickers_open == 0 then apply(false) end
    error(err, 2)
  end
end
function rune.ui.picker._settle(id, accepted, value)
  pickers_open = math.max(0, pickers_open - 1)
  if pickers_open == 0 then apply(false) end
  return picker_settle(id, accepted, value)
end

apply(false)

return layout
