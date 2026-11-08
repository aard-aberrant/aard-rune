-- The screen layout and every pane's size (require("core.layout")). Same
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

-- The left column's width (the info pane's), from the terminal's
function layout.left_w()
  return math.max((rune._state.width or 0) - layout.RIGHT_W - 1, 20)
end

-- The group pane's height: what info, the minimap row and their two
-- dividers leave
function layout.group_h()
  return math.max((rune._state.height or 0) - layout.INFO_H - layout.MINIMAP_H - 2, 1)
end

-- The affects pane's width: the left column less the minimap and a divider
function layout.affects_w()
  return math.max(layout.left_w() - layout.MINIMAP_W - 1, 10)
end

local function apply(picking)
  rune.ui.layout({
    type = "row",
    dividers = true,
    children = {
      {
        type = "column",
        dividers = true,
        children = {
          { type = "pane", name = "group", border = "none" },
          { type = "pane", name = "info", size = layout.INFO_H, border = "none" },
          {
            type = "row",
            size = layout.MINIMAP_H,
            dividers = true,
            children = {
              { type = "pane", name = "minimap", size = layout.MINIMAP_W, border = "none" },
              { type = "pane", name = "affects", border = "none" },
            },
          },
        },
      },
      {
        type = "column",
        size = layout.RIGHT_W,
        dividers = true,
        children = {
          { type = "pane", name = "chats", size = layout.CHATS_H, border = "none" },
          { type = "pane", name = "output", border = "none" },
          -- the status rows: two native bars (panes/status.lua), in a column
          -- of their own so no divider comes between them
          {
            type = "column",
            size = 2,
            children = {
              { type = "bar", name = "status1" },
              { type = "bar", name = "status2" },
            },
          },
          { type = "input", size = not picking and 1 or nil },
        },
      },
    },
  })
end

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
