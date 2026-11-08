-- The group pane (tt++ modules/group.tin), from GMCP group.
local util = require("core.util")
local game = require("core.game")   -- your name, shown cyan
local layout = require("core.layout")   -- the pane's height, for the columns

-- One line per member, "M lvl name hp%" (21 columns: marker 1, level 3,
-- name cut and padded to 12, HP 3), lowest HP
-- first and members who aren't here at the bottom, dimmed. Your own name is
-- cyan. HP is green, yellow under 60%, red under 20% (the tt++ group pane,
-- modules/group.tin). Two columns, as tt++: the first holds as many as the
-- pane has rows, the rest go in the second after a 2-space gap - a small
-- group looks like one column. The second only when the pane is 44 wide
-- (layout.left_w()); narrower, one column, and what doesn't fit is cut.
-- Every line is 21 wide, so they line up.
-- Redrawn whole (util.pane - only when it changed), so no flicker.
--
-- The marker (new - the user's design, 2026-11-08), yellow, one column:
--   L   the group's leader: GMCP group's "leader" field (a guess from
--       Aardwolf's GMCP docs, not yet seen here - "debug group on" shows it)
--   F   the one you follow
--   E   both: the leader, and you follow them (L and F laid over each other)
-- Someone you follow who isn't in the group gets no mark (the user,
-- 2026-11-08). GMCP doesn't say whom you follow,
-- so it's game text, as in the user's log ~/groupinfo (2026-11-08):
--   You start to follow Nalani.      (after "follow nalani")
--   You follow Nalani.               (each step they take - also restores it
--                                     after a /reload)
--   You stop following Rhuli.        (before a new one, and on "follow self")
-- Kept in rune.session, so a /reload keeps it and quitting Rune forgets it.
-- Cost: three literal starts triggers; Lua runs only on those lines.
local FOLLOW = "group_follow"   -- rune.session: the name you follow
local following = rune.session.get(FOLLOW)
if following == "" then following = nil end
local leader                    -- this group's leader, lowercased
local last                      -- the last GMCP group, to redraw on a follow change

local function marker(name)
  name = (name or ""):lower()
  local l = leader and leader == name
  local f = following and following:lower() == name
  if l and f then return rune.style.yellow("E") end   -- L and F on top of each other
  if l then return rune.style.yellow("L") end
  if f then return rune.style.yellow("F") end
  return " "
end

local function group_line(m)
  local info = m.info or {}
  local hp, mhp = tonumber(info.hp) or 0, tonumber(info.mhp) or 0
  local pct = mhp > 0 and math.floor(hp * 100 / mhp) or 0
  local here = tonumber(info.here) == 1 or info.here == true
  local name = string.sub(m.name or "?", 1, 12)
  local lvl_name = string.format("%3s %-12s", tostring(info.lvl or "?"), name)
  local hp_text = string.format("%3d", pct)
  if not here then
    return pct + 1000, marker(m.name) .. rune.style.dim(lvl_name .. " " .. hp_text)
  end
  if (m.name or ""):lower() == game.name then
    lvl_name = rune.style.cyan(lvl_name)
  end
  if pct < 20 then hp_text = rune.style.red(hp_text)
  elseif pct < 60 then hp_text = rune.style.yellow(hp_text)
  else hp_text = rune.style.green(hp_text) end
  return pct, marker(m.name) .. lvl_name .. " " .. hp_text
end

-- debug group: each group message's fields but the member list, and the
-- first member's info fields - what the game sends
local dbg = require("core.debug").topic("group", "each GMCP group message's fields (not the members)")
local function dump(d)
  local keys = {}
  for k, v in pairs(d) do
    if k ~= "members" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  table.sort(keys)
  dbg.log("group: " .. table.concat(keys, " "))
  local m = type(d.members) == "table" and d.members[1]
  if type(m) == "table" then
    local f = {}
    for k, v in pairs(m) do if k ~= "info" then f[#f + 1] = tostring(k) .. "=" .. tostring(v) end end
    for k, v in pairs(type(m.info) == "table" and m.info or {}) do f[#f + 1] = "info." .. tostring(k) .. "=" .. tostring(v) end
    table.sort(f)
    dbg.log("member 1: " .. table.concat(f, " "))
  end
end

local function draw(d)
  if type(d) ~= "table" or type(d.members) ~= "table" then
    leader = nil
    util.pane("group", rune.style.gray("not in a group"))
    return
  end
  leader = type(d.leader) == "string" and d.leader:lower() or nil
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
  if layout.left_w() < 2 * 21 + 2 then h = #rows end   -- two don't fit: one column
  for k = 1, math.min(#rows, h) do
    local second = rows[k + h]
    out[k] = rows[k].text .. (second and ("  " .. second.text) or "")
  end
  util.pane("group", table.concat(out, "\n"))
end

rune.gmcp.on("group", function(d)
  if dbg.on and type(d) == "table" then dump(d) end
  last = d
  draw(d)
end, { name = "aard_group" })

local function follow(name)
  if name == following then return end
  following = name
  rune.session.set(FOLLOW, name or "")
  draw(last)
end

-- "You start to follow Nalani." / "You follow Nalani." / "You stop following Rhuli."
local function named(prefix)
  return function(_, ctx)
    local name = ctx.line:clean():sub(#prefix + 1):match("^(.-)%.$")
    if name and name ~= "" then follow(name) end
  end
end
rune.trigger.starts("You start to follow ", named("You start to follow "), { name = "group_follow_start" })
rune.trigger.starts("You follow ", named("You follow "), { name = "group_follow_step" })
rune.trigger.starts("You stop following ", function(_, ctx)
  local name = ctx.line:clean():match("^You stop following (.-)%.$")
  -- the one you followed: "stop following Rhuli" just before "start to follow Nalani" mustn't clear Nalani
  if name and following and name:lower() == following:lower() then follow(nil) end
end, { name = "group_follow_stop" })
