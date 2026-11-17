-- Pickers and a one-row input (require("ui.picker")): pickers (find, g's
-- area list, Ctrl+R history, the / command list) draw inside the input's
-- area, so a one-row input leaves them no room (tried live). While one is
-- open the input sizes itself again - it grows to fit, with its rules -
-- and goes back to one row when it closes (ui/screen.lua's apply). Every
-- picker, Rune's own too, opens through rune.ui.picker.show, and Rune calls
-- rune.ui.picker._settle (internal) when one closes, chosen or Esc - Rune
-- source, lua/core/00_init.lua. Not output search (Ctrl+F): Lua isn't told
-- when it closes
local apply = require("ui.screen").apply
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
return {}
