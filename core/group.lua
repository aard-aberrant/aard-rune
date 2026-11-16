-- Your group (require("core.group")), from GMCP group - data only: the
-- group pane (panes/group.lua) shows it.
--
-- Each member: name, level, HP and max HP as numbers, whether they're here,
-- and three marks - you, the group's leader, the one you follow:
--   leader     GMCP group's "leader" field (a guess from Aardwolf's GMCP
--              docs, not yet seen here - "/debug group on" shows it)
--   followed   whom you follow. GMCP doesn't say, so it's game text, as in
--              the user's log ~/groupinfo (2026-11-08):
--                You start to follow Nalani.   (after "follow nalani")
--                You follow Nalani.            (each step they take - also
--                                               restores it after a /reload)
--                You stop following Rhuli.     (before a new one, and on
--                                               "follow self")
--              Kept in rune.session, so a /reload keeps it and quitting
--              Rune forgets it.
--   me         your own name (core/game.lua's, from GMCP char.base)
-- Someone you follow who isn't in the group gets no mark (the user,
-- 2026-11-08).
-- Cost: three literal starts triggers; Lua runs only on those lines. A
-- group message that repeats the last one sets nothing new.
local util = require("core.util")
local colors = require("core.colors")
local game = require("core.game")   -- your name

local FOLLOW = "group_follow"   -- rune.session: the name you follow
local following = rune.session.get(FOLLOW)
if following == "" then following = nil end

-- Published (core/view.lua):
local view = require("core.view")
local G = view.provides("aard.group", "your group, from GMCP group", {
  ["group.in"]        = { "boolean", "in a group; nil until the first GMCP group" },
  ["group.members"]   = { "list", "the members, in the game's order; nil: not in a group",
                          fields = { name = "text", lvl = "number", hp = "number", mhp = "number",
                                     here = "boolean", me = "boolean", leader = "boolean", followed = "boolean" } },
  ["group.title"]     = { "block", "the group's name in the game's colors; nil when none" },
  ["group.leader"]    = { "text", "the leader's name, lowercased; nil when not known" },
  ["group.following"] = { "text", "whom you follow (game text: You follow X.); nil when no one" },
})
G.set("group.following", following)

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

-- A member as published: numbers as numbers (the game sends strings), and
-- the marks. Names lowercased once each
local lower = setmetatable({}, { __index = function(t, k) local v = k:lower(); t[k] = v; return v end })
local leader
local function member(name, lvl, hp, mhp, here, follow)
  local lname = lower[name]
  return { name = name, lvl = lvl, hp = hp, mhp = mhp, here = here, me = lname == game.name,
           leader = lname == leader, followed = lname == follow }
end
local function same_member(a, b)
  return a.name == b.name and a.lvl == b.lvl and a.hp == b.hp and a.mhp == b.mhp and a.here == b.here
    and a.me == b.me and a.leader == b.leader and a.followed == b.followed
end

-- GMCP group: a new member list only when something in it differs from the
-- published one (most group messages repeat it: nothing to redraw); the
-- title from the game's @-codes to ANSI
rune.gmcp.on("group", function(d)
  if dbg.on and type(d) == "table" then dump(d) end
  if type(d) ~= "table" or type(d.members) ~= "table" then
    leader = nil
    G.set("group.in", false); G.set("group.members", nil); G.set("group.leader", nil); G.set("group.title", nil)
    G.publish()
    return
  end
  leader = type(d.leader) == "string" and d.leader:lower() or nil
  local follow = following and lower[following]
  local old = G.get("group.members")
  local list, same = {}, old and #old == #d.members
  for i, m in ipairs(d.members) do
    local inf = type(m.info) == "table" and m.info or {}
    local e = member(m.name or "?", tonumber(inf.lvl), tonumber(inf.hp) or 0, tonumber(inf.mhp) or 0,
                     tonumber(inf.here) == 1 or inf.here == true, follow)
    list[i] = e
    if same and not same_member(old[i], e) then same = false end
  end
  G.set("group.in", true)
  if not same then G.set("group.members", list) end
  G.set("group.leader", leader)
  local title = type(d.groupname) == "string" and util.trim(d.groupname) or ""
  G.set("group.title", title ~= "" and colors.aard_ansi(title) or nil)
  G.publish()
end, { name = "aard_group" })

local function follow(name)
  if name == following then return end
  following = name
  rune.session.set(FOLLOW, name or "")
  G.set("group.following", name)
  local old = G.get("group.members")   -- marked again: a new list
  if old then
    local follow, list = name and lower[name], {}
    for i, e in ipairs(old) do list[i] = member(e.name, e.lvl, e.hp, e.mhp, e.here, follow) end
    G.set("group.members", list)
  end
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

return {}
