-- The group pane: modules/group.lua's data (aard.group) - the group's name
-- on a band, then a row per member (process/group.lua, format/group.lua).
--
-- The name: in the game's colors, underlined, centered on a dim band and
-- cut to the pane's width; "not in a group", muted, when not.
-- The members: lowest HP first and members who aren't here at the bottom.
-- Two columns when the pane is 44 wide: the first holds as many as the
-- pane has rows, the rest go in the second after a 2-space gap.
local screen = require("ui.screen")
require("data.layout.screen")
require("modules.group")
require("ui.widgets.banner")   -- panel:banner
local P = require("process.group")
local F = require("format.group")

local p = screen.containers.group
p:banner { source = { "group.in", "group.title" }, style = "group.title", band = "group.title_band",
  missing = "not in a group" }
p:list { source = "group.members", key = "name", w = 21, gap = "  ",
  process = P.member, format = F.member, order = P.here_then_hp }
