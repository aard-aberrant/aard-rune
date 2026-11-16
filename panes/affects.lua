-- The affects pane: modules/affects.lua's data, drawn by ui/widgets/affects.lua
-- (the tracked affects, sk/sp, the expiry histogram, the next three, the
-- totem).
local screen = require("ui.screen")
require("ui.layout")
require("modules.affects")
require("ui.widgets.affects")   -- panel:affects

screen.containers.affects:affects()
