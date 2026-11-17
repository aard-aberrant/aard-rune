-- The minimap pane: generic widgets on modules/minimap.lua's data (map.block,
-- map.word, map.note) and modules/game.lua's room.zone / room.num, with
-- process/minimap.lua and format/minimap.lua:
--   zone | vnum, in yellow
--   the room name (as many lines as the game sent)
--   the room's note (rmsg) from the mapper, in cyan, at most 2 lines
--   the map as sent - your # becomes a dot (theme.map.me), other players'
--     * a square (theme.map.player), down and up exits (< and >) arrows
--   the [ Exits: ... ] line, on the row above the pane's bottom one
-- or, in place of all but the header, RUNNING / FIGHTING / DARKNESS in the
-- middle of the pane. Every line is cut at the pane's width.
local screen = require("ui.screen")
local layout = require("data.layout.screen")
require("modules.minimap")
require("ui.widgets.text")   -- panel:text (the room name, the exits)
local P = require("process.minimap")
local F = require("format.minimap")

local p = screen.containers.minimap
local BLOCK = { "map.block", "map.word" }
p:widget { source = { "room.zone", "room.num", "map.word", "map.block" }, process = P.header, format = F.header }
p:text { y = "next", w = "*", source = BLOCK, process = P.name }
p:widget { y = "next", w = "*", source = { "map.note", "map.word", "map.block" }, process = P.note, format = F.note }
p:widget { y = "next", w = "*", source = BLOCK, process = P.map, format = F.map }
-- the exits, on the row above the bottom one (the map above cut to fit)
p:text { y = -2, w = "*", source = BLOCK, process = P.exits }
-- the word, in the middle of the pane
p:widget { y = math.floor(layout.MINIMAP_H / 2), w = "*", source = "map.word", format = F.word }
