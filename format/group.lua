-- Group formatters (require("format.group")): a member's row from
-- process/group.lua's number - "M lvl name hp%", 21 columns: marker 1,
-- level 3, name cut and padded to 12, HP 3. The marker, green: L the
-- leader, F the one you follow, E both. Your own name is cyan; HP green,
-- yellow under 60%, red under 20%; a member not here dimmed.
local screen = require("ui.screen")
local colors = require("ui.colors")
local theme = require("ui.theme")
local F = require("format.generic")
local P = require("process.group")

theme.define("group", "The group pane", {
  { "marker",      theme.green,             "L / F / E: leader, followed, both" },
  { "title",       theme.yellow,            "the group's name, where the game sets no color" },
  { "title_band",  colors.bg(theme.default), "the name's row background" },
})

local floor = math.floor
local HERE, ME, LEADER, FOLLOWED = P.HERE, P.ME, P.LEADER, P.FOLLOWED
local paint, pad, rpad = screen.paint, screen.pad, screen.rpad
local hp_color = F.rule(F.HEALTH, F.HEALTH_COLORS)

local M = {}

function M.member(v, name)
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

return M
