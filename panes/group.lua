-- The group pane (tt++ modules/group.tin), from GMCP group.
local util = require("core.util")
local game = require("core.game")   -- your name, shown cyan
local layout = require("core.layout")   -- the pane's height, for the columns

-- One line per member, "lvl name hp%" (20 columns: level 3, name cut and
-- padded to 12, HP 3), lowest HP
-- first and members who aren't here at the bottom, dimmed. Your own name is
-- cyan. HP is green, yellow under 60%, red under 20% (the tt++ group pane,
-- modules/group.tin). Two columns, as tt++: the first holds as many as the
-- pane has rows, the rest go in the second after a 2-space gap - a small
-- group looks like one column. Every line is 20 wide, so they line up.
-- Redrawn whole (util.pane - only when it changed), so no flicker.
local function group_line(m)
  local info = m.info or {}
  local hp, mhp = tonumber(info.hp) or 0, tonumber(info.mhp) or 0
  local pct = mhp > 0 and math.floor(hp * 100 / mhp) or 0
  local here = tonumber(info.here) == 1 or info.here == true
  local name = string.sub(m.name or "?", 1, 12)
  local lvl_name = string.format("%3s %-12s", tostring(info.lvl or "?"), name)
  local hp_text = string.format("%3d", pct)
  if not here then
    return pct + 1000, rune.style.dim(lvl_name .. " " .. hp_text)
  end
  if (m.name or ""):lower() == game.name then
    lvl_name = rune.style.cyan(lvl_name)
  end
  if pct < 20 then hp_text = rune.style.red(hp_text)
  elseif pct < 60 then hp_text = rune.style.yellow(hp_text)
  else hp_text = rune.style.green(hp_text) end
  return pct, lvl_name .. " " .. hp_text
end

rune.gmcp.on("group", function(d)
  if type(d) ~= "table" or type(d.members) ~= "table" then
    util.pane("group", rune.style.gray("not in a group"))
    return
  end
  local rows = {}
  for i, m in ipairs(d.members) do
    local key, text = group_line(m)
    rows[#rows + 1] = { key = key, i = i, text = text }
  end
  table.sort(rows, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.i < b.i
  end)
  local h, out = layout.group_h(), {}
  for k = 1, math.min(#rows, h) do
    local second = rows[k + h]
    out[k] = rows[k].text .. (second and ("  " .. second.text) or "")
  end
  util.pane("group", table.concat(out, "\n"))
end, { name = "aard_group" })
