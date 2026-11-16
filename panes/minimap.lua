-- The minimap pane: modules/minimap.lua's data, drawn by ui/widgets/minimap.lua
-- (zone | vnum, the room name and note, the map, the exits; RUNNING /
-- FIGHTING / DARKNESS in its place).
local screen = require("ui.screen")
require("ui.layout")
require("modules.minimap")
require("ui.widgets.minimap")   -- panel:minimap

screen.containers.minimap:minimap()
