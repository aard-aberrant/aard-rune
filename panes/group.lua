-- The group pane (tt++ modules/group.tin): generic widgets on core/group.lua's
-- data (aard.group) - this file is configuration only.
--
-- One line per member, "M lvl name hp%" (21 columns: marker 1, level 3,
-- name cut and padded to 12, HP 3), lowest HP first and members who aren't
-- here at the bottom, dimmed. Your own name is cyan. HP is green, yellow
-- under 60%, red under 20% (the tt++ group pane, modules/group.tin). Two
-- columns, as tt++: the first holds as many as the pane has rows, the rest
-- go in the second after a 2-space gap - a small group looks like one
-- column. The second only when the pane is 44 wide (layout.left_w());
-- narrower, one column, and what doesn't fit is cut. Above them, the
-- group's title on one row, in its own colors on a dim grey band, cut to
-- the pane's width (the user, 2026-11-09) - it takes a row from the
-- members. "not in a group" when not.
-- The marker (the user's design, 2026-11-08), green, one column:
--   L   the group's leader
--   F   the one you follow
--   E   both: the leader, and you follow them (L and F laid over each other)
-- Drawn only when the group data or the pane's size changed; a member's
-- line is built again only when what it shows changed (core/view.lua's list).
local colors = require("core.colors")
local theme = require("core.theme")
local bg = colors.bg
-- This pane's colors: theme.group.* - /theme lists them, data/theme.lua
-- changes them (core/theme.lua)
theme.define("group", "The group pane", {
  { "marker",      theme.green,       "L / F / E: leader, followed, both" },
  { "title",       theme.yellow,      "the group's name, where the game sets no color" },
  { "title_band",  bg(theme.default), "the name's row background" },
})
local layout = require("core.layout")   -- the pane's size
local view = require("core.view")
local w, h = view.widgets, view.helpers

view.add_styles({
  ["group.marker"] = "group.marker", ["group.title"] = "group.title", ["group.band"] = "group.title_band",
  ["group.self"] = "self", ["group.away"] = "unavailable", ["group.none"] = "muted",
  ["group.hp"] = { { below = 20, "danger" }, { below = 60, "caution" }, "good" },
})

-- A member's line: the marker, then level, name and HP %
local r = view.row("group.members")
local v = {
  lvl = h.either(r.lvl, "?"), name = r.name,
  pct = h.either(h.floor(h.pct(r.hp, r.mhp)), 0),   -- 0 while max HP isn't known
}
local marker = w.cases("", {
  { when = h.all(r.leader, r.followed), "E", style = "group.marker" },   -- L and F on top of each other
  { when = r.leader, "L", style = "group.marker" },
  { when = r.followed, "F", style = "group.marker" },
  { " " },
})
local member = w.cases("", {
  { when = h.no(r.here), "{lvl|rpad:3} {name|cut:12|pad:12} {pct|rpad:3}", vars = v, style = "group.away" },
  { when = r.me, w.join(w.text("{lvl|rpad:3} {name|cut:12|pad:12}", { vars = v, style = "group.self" }),
                        w.text(" {pct|rpad:3|style:group.hp}", { vars = v })) },
  { "{lvl|rpad:3} {name|cut:12|pad:12} {pct|rpad:3|style:group.hp}", vars = v },
})

view.pane("group", {
  size = function() return layout.group_h(), layout.left_w() end,
  w.cases("", { { when = h.eq("group.in", false), "not in a group", style = "group.none" } }),
  w.banner("group.title", { style = "group.title", fill = "group.band" }),
  w.list("group.members", {
    row = w.join(marker, member),
    sort = { h.no(r.here), v.pct },   -- here first, then lowest HP; ties in the game's order
    key = r.name, width = 21, gap = "  ",
  }),
})

return {}
