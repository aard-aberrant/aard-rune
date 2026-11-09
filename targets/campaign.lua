-- Campaigns (tt++ modules/campaign.tin, lean). Each campaign mob is handled
-- like a quest mob: cn makes one the target (src "campaign") and goes
-- (target.go) - to its area, then on a second cn to its room.
-- The list comes from the game's "cp check" reply - there is no GMCP for
-- campaigns - read whenever it arrives, typed or not:
--   You still have to kill * <mob> (<place>)       one per mob
--     <place> is an area, or a room in a room-based campaign; "<area> -
--     Dead" is a mob not repopped yet (its place is always the area)
--   You have D days, H hours and M minutes left to finish this campaign.
-- Area-based: every live mob's place is an area in data/areas.lua. Else
-- room-based: the room's area comes from the map, when only one area has a
-- room of that name; when several do, cn opens a picker of them (nearest
-- first) and walks to the entrance of the one you choose - a second cn
-- goes on to the room, as qx does.
-- Kills come in any order. Only "Congratulations, that was one of your
-- CAMPAIGN mobs!" says one died; which one is the enemy GMCP char.status
-- named, struck off the list at that line (see below). Then, if it was the
-- current mob, the target is cleared and the pane says so; cn takes the
-- next. When the name can't tell, a hidden cp check does: its fresh list
-- replaces the old, and the current mob is dead when fewer of its name are
-- left.
-- The enemy's name: the last GMCP char.status gave, case ignored, used
-- once. Not on the list, or none (a mob killed before GMCP named it, or a
-- GMCP name that isn't the cp check's; debug campaign shows both): the cp
-- check. A strike sends none: the cp check comes at the next cn to another
-- area (aim, below), and puts the list right then - a wrong strike too (an
-- earlier fight's name, at a one-hit kill).

local util = require("core.util")
local game = require("core.game")       -- the area you're in (cn's order)
local info = require("panes.info")       -- the campaign's rows
local target = require("targets.target")   -- cn sets it, a kill drops it
local travel = require("nav.travel")   -- areas, zone_of, the map's room names
local soh = require("targets.soh")     -- a School of Horror mob's keyword, on its row

local say, warn = util.say, util.warn
local dbg = require("core.debug").topic("campaign", "at a campaign kill: GMCP's last enemy and the current cn mob")

local list = {}       -- { mob, place, zone, room, dead }, in cp check order
local reading = false -- inside a cp check reply
local ends            -- os.time() the campaign ends
local cur             -- the current entry (a copy), or nil
local cur_dead = false
local skipped = {}    -- mob names cn next passed over
local queue = {}      -- per cp check not answered yet: true = hide its reply
local hiding = false  -- the reply being read is ours
local notes_until = 0 -- a hidden reply's notes are hidden until then
local reply_until = 0 -- a typed cp command's reply is read until then
local on_cp = false   -- on a campaign: the kill's triggers are on
local last_enemy = "" -- the last enemy GMCP char.status named, lowercased
local REPLY_WAIT = 120   -- tt++'s: the game answers only once a fight is over
-- Both groups exist only while on (util.group)
local reply_trig, live_trig = util.group(), util.group()


-- Each group on or off, as things stand now
local resync = util.slot()   -- the reply window's end
local function sync()
  local now = os.time()
  local until_ = math.max(notes_until, reply_until)
  reply_trig.set(#queue > 0 or reading or hiding or now <= until_)
  live_trig.set(on_cp)
  if #queue == 0 and now <= until_ then   -- off again once the window ends
    resync.start(until_ - now + 1, sync)
  end
end

-- A reply's first line: is it ours?
local function reply_starts() hiding = table.remove(queue, 1) == true end
util.hider(function() return hiding end)

local hide = util.hide

local function count(name)
  local n = 0
  for _, e in ipairs(list) do if e.mob == name then n = n + 1 end end
  return n
end

-- The info pane ----------------------------------------------------------

local CYAN, RED = "\27[36m", "\27[31m"
local tick = util.slot()   -- the info row's minute redraw

local function row()
  -- Nothing until cn has picked a mob: a cp check alone (after cp request,
  -- or at load) leaves the pane to what was there
  if not ends or not cur then return info.set("campaign", 60, nil) end
  local left = math.max(0, math.ceil((ends - os.time()) / 60))
  local d, h, m = math.floor(left / 1440), math.floor(left % 1440 / 60), left % 60
  local time = d > 0 and string.format("%dd %dh", d, h) or string.format("%dh %dm", h, m)
  local first = CYAN .. #list .. " left, " .. time
  local t = target.get()
  local room = cur.room or (t and t.src == "campaign" and t.room) or nil
  -- The area's line counts the campaign mobs still in it (the target's
  -- included, Dead ones too), when there's more than one
  local area = cur.area_name
  if area and cur.zone then
    local n = 0
    for _, e in ipairs(list) do if e.zone == cur.zone then n = n + 1 end end
    if n > 1 then area = area .. " (" .. n .. " left)" end
  end
  -- Listed Dead (not repopped yet) in the last cp check: (DEAD) after its name
  local mob = soh.label(cur.mob, cur.zone)
  for _, e in ipairs(list) do
    if e.mob == cur.mob and e.place == cur.place then
      if e.dead then mob = mob .. " " .. RED .. "(DEAD)" end
      break
    end
  end
  info.set("campaign", 60, info.target_rows(first, area, room, mob,
    cur_dead and "killed - cn for next"))
end

-- The room comes later than cn: targets/target.lua's check finds it
target.on_change(function(t) if cur and (not t or t.src == "campaign") then row() end end)

local function minutely()
  if not ends then return end
  row()
  tick.start(60 - os.time() % 60, minutely)
end

local function reset()
  list, ends, cur, cur_dead, skipped, on_cp = {}, nil, nil, false, {}, false
  tick.stop()
  target.clear("campaign")
  row()
end

-- The reply -------------------------------------------------------------

-- Room name -> the zones holding it, from the map. Kept for the session -
-- each cp check would otherwise scan all the map's rooms again
local room_zones = {}

-- Area or room for every entry, once the list is complete
local function place_all()
  local room_based = false
  for _, e in ipairs(list) do
    e.zone = travel.zone_of(e.place)
    if not e.zone and not e.dead then room_based = true end
  end
  if not room_based then
    for _, e in ipairs(list) do e.area_name = e.place end
    return
  end
  local names, ask = {}, false
  for _, e in ipairs(list) do
    if not e.zone and not room_zones[e.place] then names[e.place] = true; ask = true end
  end
  if ask then   -- one pass over the map, only for names not seen before
    for n, z in pairs(travel.zones_with_rooms(names)) do room_zones[n] = z end
  end
  local zones = room_zones
  for _, e in ipairs(list) do
    if e.zone then
      e.area_name = e.place
    else
      e.room = e.place
      local z = zones[e.place]
      if #z == 1 then e.zone = z[1] end
      e.where = z
      local a = e.zone and travel.areas[e.zone]
      e.area_name = a and a.name or nil
    end
  end
end

local function reply(pat, fn, name, mode)
  reply_trig.add(mode or "regex", pat, fn, { name = name })
end
local function live(pat, fn, name) live_trig.add("regex", pat, fn, { name = name }) end

reply("^You still have to kill (?:\\* )?(.+) \\((.+)\\)$", function(m, ctx)
  if not reading then list, reading, on_cp = {}, true, true; reply_starts() end
  local place, dead = m[2], false
  local area = place:match("^(.+) %- Dead$")
  if area then place, dead = area, true end
  list[#list + 1] = { mob = m[1], place = place, dead = dead }
  if hiding then return hide(ctx) end
end, "cp_target")

reply("^You have (\\d+) days?, (\\d+) hours? and (\\d+) minutes? left to finish this campaign\\.$",
  function(m, ctx)
    reading = false
    ends = os.time() + tonumber(m[1]) * 86400 + tonumber(m[2]) * 3600 + tonumber(m[3]) * 60
    place_all()
    if cur and not cur_dead and count(cur.mob) < cur.n then
      cur_dead = true
      target.clear("campaign")
      say("[campaign] " .. cur.mob .. " killed - cn for the next, " .. #list .. " left.")
    elseif cur and not cur_dead then
      cur.n = count(cur.mob)
    end
    minutely()
    if hiding then
      hiding, notes_until = false, os.time() + 2   -- the notes that follow
      sync()
      return hide(ctx)
    end
    sync()
    say("[campaign] " .. #list .. " left.")
  end, "cp_time")

-- The notes after the list - hidden only after a hidden cp check
reply("^(Note: Dead means |You cannot take another campaign |Wait time will be reset |You have completed \\d+ campaigns? today|You may take another campaign\\.)",
  function(_, ctx)
    -- Hidden in our reply wherever they fall: inside the list, after the
    -- time line, or before the list starts (the next reply due is ours) -
    -- seen live 2026-11-06, the Dead note showed before the time line
    if hiding or os.time() <= notes_until or (not reading and queue[1] == true) then
      return hide(ctx)
    end
  end, "cp_notes")

-- No campaign (a cp check's reply), or it ended
local function over(m, ctx)
  reading = false
  -- only the first is a cp check's reply; the others are news
  if m[1]:find("^You are not") then reply_starts() end
  local was = ends
  reset()
  local hid = hiding
  if hiding then hiding, notes_until = false, os.time() + 2 end   -- its notes follow
  sync()
  if hid then return hide(ctx) end
  if was then say("[campaign] over.") end
end
reply("^(You are not currently on a campaign\\.|Campaign cleared\\.)$", over, "cp_none")
live("^(CONGRATULATIONS! You have completed your campaign\\.)$", over, "cp_done")

-- A campaign begins (cp request), or cp request says you're on one: a
-- hidden cp check reads its mobs, so cn works straight away. The request's
-- reply lists none (log 2026-11-06: "I have selected 18 targets for you to
-- hunt", "Type 'campaign info' ...", "Good luck in your campaign!")
-- (literal matches: the one regex for both cost 600 ns a line - core/util.lua)
local check_quietly
local function started()
  on_cp = true
  check_quietly()
end
reply("tells you 'Good luck in your campaign!'", function(_, ctx)
  if ctx.line:clean():find("tells you 'Good luck in your campaign!'$") then started() end
end, "cp_started", "contains")
reply("You are already on an active campaign!", started, "cp_on_already", "exact")

function check_quietly()
  queue[#queue + 1] = true
  sync()
  rune.send_raw("cp check")
end

-- A typed cp check: its reply shows, and is read. Any other cp command:
-- its reply is read for REPLY_WAIT
local function typed(cmd)
  return function(args)
    args = util.trim(args)
    if args:match("^ch") then queue[#queue + 1] = false
    else reply_until = os.time() + REPLY_WAIT end
    sync()
    rune.send_raw(args ~= "" and (cmd .. " " .. args) or cmd)
  end
end
rune.alias.exact("cp", typed("cp"))
rune.alias.exact("campaign", typed("campaign"))

-- The kill: strike the enemy off the list, else a cp check (see the top)
live("^Congratulations, that was one of your CAMPAIGN mobs!$", function()
  if dbg.on then
    dbg.log(string.format("enemy \"%s\", cn mob \"%s\"", last_enemy, tostring(cur and cur.mob)))
  end
  local killed = last_enemy
  last_enemy = ""
  -- One of its name off the list - the current mob's own entry when it's
  -- the current mob (names repeat across areas)
  local at
  for i, e in ipairs(list) do
    if e.mob:lower() == killed then
      if not at then at = i end
      if cur and e.mob == cur.mob and e.place == cur.place then at = i; break end
    end
  end
  if killed == "" or not at then return check_quietly() end
  local e = table.remove(list, at)
  if cur and not cur_dead and e.mob == cur.mob then
    cur_dead = true
    target.clear("campaign")
    say("[campaign] " .. cur.mob .. " killed - cn for the next, " .. #list .. " left.")
  else
    say("[campaign] " .. e.mob .. " killed, " .. #list .. " left.")
  end
  row()
end, "cp_kill")

-- The enemy's name, without the game's color codes
rune.gmcp.on("char.status", function(d)
  local e = type(d) == "table" and d.enemy
  if type(e) == "string" and e ~= "" then
    last_enemy = util.uncolor(e):lower()
  end
end, { name = "campaign_enemy" })
sync()

-- cn --------------------------------------------------------------------

-- The next entry: areas with no Dead mob first - the one you're in, then
-- the rest in cp check order; then mobs placed only by a room name several
-- areas share (cn opens a picker of them); then areas holding a Dead mob
-- (yours first), the Dead ones last in each; then mobs the map doesn't
-- know. Last of all, the ones cn next skipped
local function pick()
  local here, dead, first = game.room.zone, {}, {}
  for i, e in ipairs(list) do
    local z = e.zone or ("?" .. i)
    if e.dead then dead[z] = true end
    first[z] = first[z] or i
  end
  local best, best_key
  for i, e in ipairs(list) do
    local z = e.zone or ("?" .. i)
    local tier
    if not e.zone then tier = (e.where and #e.where > 1) and 2 or 5
    elseif not dead[z] then tier = e.zone == here and 0 or 1
    else tier = e.zone == here and 3 or 4 end
    if skipped[e.mob] then tier = tier + 10 end
    local key = { tier, first[z], e.dead and 1 or 0, i }
    local better = not best_key
    if not better then
      for k = 1, 4 do
        if key[k] ~= best_key[k] then better = key[k] < best_key[k]; break end
      end
    end
    if better then best, best_key = e, key end
  end
  return best
end

-- Returns true when it sent you on your way itself (the area picker)
local function aim(e)
  cur, cur_dead = e, false
  cur.n = count(e.mob)
  -- To another area: a hidden cp check first. Out of a fight nothing waits
  -- ahead of it, so its reply comes as the walk starts, and puts right
  -- what the strikes guessed (a wrong one, the Dead marks) - and this pick,
  -- if it's dead already: fewer of its name left, "killed"
  if e.zone ~= game.room.zone then check_quietly() end
  if not e.zone and e.where and #e.where > 1 then
    target.clear("campaign")   -- none until you choose its area
    row()
    travel.go_area_of(e.where, e.mob .. ": " .. e.place, function(zone)
      local a = travel.areas[zone]
      e.zone, e.area_name = zone, a and a.name or nil
      target.set({ name = e.mob, zone = zone, room = e.room, src = "campaign" })
      row()
    end)
    return true
  end
  if not e.zone then
    local where = e.where and #e.where > 1 and (" - in " .. table.concat(e.where, ", ")) or ""
    warn("[campaign] " .. e.mob .. ": can't tell the area of \"" .. e.place .. "\"" .. where .. ".")
  end
  target.set({ name = e.mob, zone = e.zone, room = e.room, src = "campaign" })
  if e.dead then warn("[campaign] " .. e.mob .. " is listed Dead - not repopped yet.") end
  row()
end

rune.alias.exact("cn", function(args)
  if #list == 0 then return warn("[campaign] cn: no campaign mobs - cp check first.") end
  local skip = util.trim(args) == "next"
  if skip and cur then skipped[cur.mob] = true end
  if skip or not cur or cur_dead then
    if aim(pick()) then return end
  elseif not cur.zone and cur.where and #cur.where > 1 then
    return aim(cur)   -- the picker again: none chosen yet
  else
    local t = target.get()
    if not (t and t.src == "campaign" and t.name == cur.mob) then
      target.set({ name = cur.mob, zone = cur.zone, room = cur.room, src = "campaign" })
    end
  end
  if cur.zone then target.go() end
end)

-- At login and after a /reload
game.on_login(check_quietly)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("cn", "cn [next]", "go to the current campaign mob, else the next (Dead ones' areas last); next skips it")
help.add("cp", "cp / campaign [args]", "the game's campaign command; its reply also updates cn's list")
