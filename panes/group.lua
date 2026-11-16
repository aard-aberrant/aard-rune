-- The group pane (tt++ modules/group.tin), from GMCP group.
local util = require("core.util")
local colors = require("core.colors")
local theme = require("core.theme")
local mix, bg = colors.mix, colors.bg
-- This module's colors: theme.group.* - /theme lists them, data/theme.lua
-- changes them (core/theme.lua)
local T = theme.define("group", "The group pane", {
  { "marker",      theme.green,       "L / F / E: leader, followed, both" },
  { "title",       theme.yellow,      "the group's name, where the game sets no color" },
  { "title_band",  bg(theme.default), "the name's row background" },
})
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
-- Every line is 21 wide, so they line up. Above them, the group's title on
-- one row, in its own colors on a dim grey band, cut to the pane's width
-- (the user, 2026-11-09) - it takes a row from the members.
-- The pane is one widget on the published group data (core/view.lua):
-- written whole, only when its text changed, so no flicker; a group
-- message that repeats the last one costs a compare.
--
-- The marker (new - the user's design, 2026-11-08), green, one column:
--   L   the group's leader: GMCP group's "leader" field (a guess from
--       Aardwolf's GMCP docs, not yet seen here - "/debug group on" shows it)
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

-- Published (core/view.lua) - the group as GMCP sent it, no display:
local view = require("core.view")
local G = view.provides("aard.group", "your group, from GMCP group", {
  ["group.in"]        = { "boolean", "in a group; nil until the first GMCP group" },
  ["group.members"]   = { "list", "{ name, lvl, hp, mhp, here } each, in the game's order; nil: not in a group" },
  ["group.title"]     = { "text", "the group's name, with the game's @-color codes; \"\" when none" },
  ["group.leader"]    = { "text", "the leader's name, lowercased; nil when not known" },
  ["group.following"] = { "text", "whom you follow (game text: You follow X.); nil when no one" },
})
G.set("group.following", following)

-- The pane: a widget on that data -------------------------------------------
-- Each member's line is kept and built again only when what it shows
-- changed (hp, level, here, marker, you); the title only when it changed.
-- The sort and the columns are redone at each change (a few members)
local function marker(name, leader, follow)
  local l = leader and leader == name
  local f = follow and follow == name
  if l and f then return T.marker("E") end   -- L and F on top of each other
  if l then return T.marker("L") end
  if f then return T.marker("F") end
  return " "
end

local kept = {}   -- name -> { hp, mhp, lvl, here, mark, me, key, text }: this group's
local function group_line(m, leader, follow, now)
  local lname = (m.name or ""):lower()
  local mark = marker(lname, leader, follow)
  local me = lname == game.name
  local k = kept[m.name or "?"]
  if k and k.hp == m.hp and k.mhp == m.mhp and k.lvl == m.lvl and k.here == m.here and k.mark == mark and k.me == me then
    now[m.name or "?"] = k
    return k.key, k.text
  end
  local hp, mhp = tonumber(m.hp) or 0, tonumber(m.mhp) or 0
  local pct = mhp > 0 and math.floor(hp * 100 / mhp) or 0
  local name = string.sub(m.name or "?", 1, 12)
  local lvl_name = string.format("%3s %-12s", tostring(m.lvl or "?"), name)
  local hp_text = string.format("%3d", pct)
  local key, text
  if not m.here then
    key, text = pct + 1000, mark .. theme.unavailable(lvl_name .. " " .. hp_text)
  else
    if me then lvl_name = theme.self(lvl_name) end
    if pct < 20 then hp_text = theme.danger(hp_text)
    elseif pct < 60 then hp_text = theme.caution(hp_text)
    else hp_text = theme.good(hp_text) end
    key, text = pct, mark .. lvl_name .. " " .. hp_text
  end
  now[m.name or "?"] = { hp = m.hp, mhp = m.mhp, lvl = m.lvl, here = m.here, mark = mark, me = me, key = key, text = text }
  return key, text
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

local title_in, title_w, title_out   -- the title row, kept
local function draw(is_in, members, title, leader, follow)
  if is_in == nil then return nil end   -- no GMCP group yet: the pane stays empty
  if not is_in or not members then return theme.muted("not in a group") end
  follow = follow and follow:lower()
  local rows, now = {}, {}
  for i, m in ipairs(members) do
    local key, text = group_line(m, leader, follow, now)
    rows[#rows + 1] = { key = key, i = i, text = text }
  end
  kept = now   -- members who left are dropped
  table.sort(rows, function(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.i < b.i
  end)
  local h, w, out = layout.group_h(), layout.left_w(), {}
  -- the title row: GMCP group's "groupname" (a guess from Aardwolf's GMCP
  -- docs - "/debug group on" shows the real field), in the game's colors
  -- (theme.group.title where it sets none), cut to the pane's width and centered
  -- in it - an odd column over goes on the right - on theme.group.title_band
  -- across the row (the game's codes set only the text color, so it holds
  -- under them); none, no row
  title = title or ""
  if title ~= "" then
    if title ~= title_in or w ~= title_w then
      local BG = T.title_band.on
      local t = colors.crop(T.title.on .. colors.aard_ansi(title), w)
      local pad = w - colors.width(t)
      local left = math.floor(pad / 2)
      title_in, title_w = title, w
      title_out = BG .. string.rep(" ", left) .. t .. BG .. string.rep(" ", pad - left) .. colors.RESET
    end
    out[1] = title_out
    h = math.max(h - 1, 1)
  end
  if w < 2 * 21 + 2 then h = #rows end   -- two don't fit: one column
  for k = 1, math.min(#rows, h) do
    local second = rows[k + h]
    out[#out + 1] = rows[k].text .. (second and ("  " .. second.text) or "")
  end
  return table.concat(out, "\n")
end
view.pane("group", { view.widgets.custom("group",
  { inputs = { "group.in", "group.members", "group.title", "group.leader", "group.following" } },
  function(_, is_in, members, title, leader, follow) return draw(is_in, members, title, leader, follow) end) })

-- GMCP group: published as plain fields (numbers as the game sent them:
-- tonumber where they're used)
rune.gmcp.on("group", function(d)
  if dbg.on and type(d) == "table" then dump(d) end
  if type(d) ~= "table" or type(d.members) ~= "table" then
    G.set("group.in", false); G.set("group.members", nil); G.set("group.leader", nil); G.set("group.title", nil)
    G.publish()
    return
  end
  -- the same members as last time, field for field: no new list (nothing
  -- to redraw - most group messages repeat it)
  local old = G.get("group.members")
  local same = old and #old == #d.members
  local list = {}
  for i, m in ipairs(d.members) do
    local inf = type(m.info) == "table" and m.info or {}
    local e = { name = m.name, lvl = inf.lvl, hp = inf.hp, mhp = inf.mhp,
                here = tonumber(inf.here) == 1 or inf.here == true }
    list[i] = e
    local o = same and old[i]
    if same and not (o.name == e.name and o.lvl == e.lvl and o.hp == e.hp and o.mhp == e.mhp and o.here == e.here) then
      same = false
    end
  end
  G.set("group.in", true)
  if not same then G.set("group.members", list) end
  G.set("group.leader", type(d.leader) == "string" and d.leader:lower() or nil)
  G.set("group.title", type(d.groupname) == "string" and util.trim(d.groupname) or "")
  G.publish()
end, { name = "aard_group" })

local function follow(name)
  if name == following then return end
  following = name
  rune.session.set(FOLLOW, name or "")
  G.set("group.following", name)
  G.publish()
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
