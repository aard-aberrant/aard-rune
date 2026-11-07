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
-- room of that name.
-- Kills come in any order: "Congratulations, that was one of your CAMPAIGN
-- mobs!" sends a hidden cp check, and the fresh list replaces the old - the
-- current mob is dead when fewer of its name are left. Then the target is
-- cleared and the pane says so; cn takes the next.
--   cn        the current campaign mob, else the next: this area's first,
--             then areas with only live mobs, then mixed ones, Dead
--             ones, and mobs whose area can't be told last
--   cn next   skip the current one for the next
-- The info pane (panes/info.lua), priority 60, from the first cn on: time left
-- and mobs left, area, room, mob. On load a hidden cp check rebuilds the
-- list.
-- The game answers in order, and a kill's cp check can wait behind spells
-- still queued: so no timeout - each cp check sent is queued (hidden: ours;
-- shown: one you type), and each reply takes the first (as panes/affects.lua's
-- slist). The notes (the Dead note and the like) are hidden wherever they
-- fall in our reply; after its time line, for 2 s - they come with it.
-- The triggers are on only while they can matter (tt++'s two groups):
--   the reply's   while a cp check is unanswered, its notes' 2 s, and for
--                 REPLY_WAIT after any other cp/campaign command you type
--                 (request, quit ...)
--   the kill's    while you're on a campaign - from a cp check listing
--                 mobs, "Good luck in your campaign!" or "You are already on
--                 an active campaign!" (tt++'s lines; either sends a hidden
--                 cp check, so cn has the mobs at once) to its end

local util = require("core.util")
local game = require("core.game")       -- the area you're in (cn's order)
local info = require("panes.info")       -- the campaign's rows
local target = require("targets.target")   -- cn sets it, a kill drops it
local travel = require("nav.travel")   -- areas, zone_of, the map's room names

local say, warn = util.say, util.warn

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
local REPLY_WAIT = 120   -- tt++'s: the game answers only once a fight is over
-- Both groups exist only while on (util.group)
local reply_trig, live_trig = util.group(), util.group()

local function set(group, on) group.set(on) end

-- Each group on or off, as things stand now
local resync = util.slot()   -- the reply window's end
local function sync()
  local now = os.time()
  local until_ = math.max(notes_until, reply_until)
  set(reply_trig, #queue > 0 or reading or hiding or now <= until_)
  set(live_trig, on_cp)
  if #queue == 0 and now <= until_ then   -- off again once the window ends
    resync.start(until_ - now + 1, sync)
  end
end

-- A reply's first line: is it ours?
local function reply_starts() hiding = table.remove(queue, 1) == true end
util.hider(function() return hiding end)

local function hide(ctx)
  util.eat_blanks(ctx.line:clean())
  return false
end

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
  info.set("campaign", 60, info.target_rows(first, cur.area_name, room, cur.mob,
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
-- each kill's cp check would otherwise scan all the map's rooms again
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

live("^Congratulations, that was one of your CAMPAIGN mobs!$", function()
  check_quietly()
end, "cp_kill")
sync()

-- cn --------------------------------------------------------------------

-- The next entry: this area's live mobs, then its Dead ones, then areas
-- with only live mobs, mixed areas (live first), then Dead-only areas -
-- each in cp check order. Then mobs whose area is unknown, and last the
-- ones cn next skipped
local function pick()
  local here, live, dead, first = game.room.zone, {}, {}, {}
  for i, e in ipairs(list) do
    local z = e.zone or ("?" .. i)
    if e.dead then dead[z] = true else live[z] = true end
    first[z] = first[z] or i
  end
  local best, best_key
  for i, e in ipairs(list) do
    local z = e.zone or ("?" .. i)
    local tier
    if not e.zone then tier = 5   -- can't be walked to
    elseif e.zone == here then tier = e.dead and 1 or 0
    elseif not dead[z] then tier = 2
    elseif live[z] then tier = 3
    else tier = 4 end
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

local function aim(e)
  cur, cur_dead = e, false
  cur.n = count(e.mob)
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
    aim(pick())
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
