-- The group pane: modules/group.lua's data (aard.group) - the group's name
-- on a band, then a row per member.
--
-- The name: in the game's colors, underlined, centered on a dim band and
-- cut to the pane's width; "not in a group", muted, when not.
-- A member, "M lvl name hp%" (21 columns: marker 1, level 3, name cut and
-- padded to 12, HP 3), lowest HP first and members who aren't here at the
-- bottom, dimmed. Your own name is cyan. HP is green, yellow under 60%,
-- red under 20%. Two columns when the pane is 44 wide: the first holds as
-- many as the pane has rows, the rest go in the second after a 2-space
-- gap. The marker, green: L the leader, F the one you follow, E both.
local screen = require("ui.screen")
local colors = require("ui.colors")
local theme = require("ui.theme")
local F = require("ui.format")
require("ui.layout")
require("modules.group")
require("ui.widgets.banner")   -- panel:banner

theme.define("group", "The group pane", {
  { "marker",      theme.green,             "L / F / E: leader, followed, both" },
  { "title",       theme.yellow,            "the group's name, where the game sets no color" },
  { "title_band",  colors.bg(theme.default), "the name's row background" },
})

-- A member: everything the row shows, in one number - level (0: not
-- known), HP percent, and here / me / leader / followed (one bit each).
-- The name is the row's key
local floor = math.floor
local HERE, ME, LEADER, FOLLOWED = 1, 2, 4, 8
local function member(m)
  local pct = 0
  if m.hp and m.mhp and m.mhp ~= 0 then pct = floor(m.hp * 100 / m.mhp) end
  local flags = (m.here and HERE or 0) + (m.me and ME or 0) + (m.leader and LEADER or 0) + (m.followed and FOLLOWED or 0)
  return ((m.lvl and m.lvl + 1 or 0) * 100000 + pct) * 16 + flags
end

-- here first, then lowest HP; ties in the game's order
local function here_then_hp(v)
  local flags = v % 16
  local pct = floor(v / 16) % 100000
  return (flags % 2 == 1 and 0 or 100000) + pct
end

-- The row from that number
local paint, pad, rpad = screen.paint, screen.pad, screen.rpad
local hp_color = F.rule(F.HEALTH, F.HEALTH_COLORS)
local function row(v, name)
  local flags = v % 16
  local rest = floor(v / 16)
  local pct = rest % 100000
  local lvl = floor(rest / 100000) - 1
  local function has(f) return flags % (2 * f) >= f end
  local mark = has(LEADER) and has(FOLLOWED) and "E" or has(LEADER) and "L" or has(FOLLOWED) and "F"
  mark = mark and paint(theme.group.marker, mark) or " "
  local who = rpad(lvl < 0 and "?" or tostring(lvl), 3) .. " " .. pad(#name > 12 and name:sub(1, 12) or name, 12)
  local hp = rpad(tostring(pct), 3)
  if not has(HERE) then return mark .. paint(theme.unavailable, who .. " " .. hp) end
  if has(ME) then return mark .. paint(theme.self, who) .. " " .. paint(hp_color(pct), hp) end
  return mark .. who .. " " .. paint(hp_color(pct), hp)
end

local p = screen.panels.group
p:banner { source = { "group.in", "group.title" }, style = "group.title", band = "group.title_band",
  missing = "not in a group" }
p:list { source = "group.members", key = "name", w = 21, gap = "  ",
  process = member, format = row, order = here_then_hp }
