-- Travel: routes over the map (nav/mapper.lua), the walk, and the commands
--   g            the home routine
--   g <area>     an area only (picker if several; runto if the map has no route).
--                From inside it: home, then back to its entrance
--   ga <text>    this area: a label starting with it, else a room name. Nearest,
--                walked - never home or a portal
--   find [text]  anywhere: labels, areas, room names, a vnum. One match goes
--                there; several open a picker. No text: labels and areas.
--   mf [text]    as find, but shows the route instead of walking it
--   gnom         the gnome airship (not on the map)
--   label <word> / unlabel <word> / labels
--   13s, 3e2n ...              speedwalk (sent as one game "run 3e2n")
-- A walk's plain moves go as the game's run ("run 2n3e"): the game shows
-- only the room a run ends in, and stops it after three failed moves
-- ("Too many run errors.") or at a fight - the rest isn't sent from the
-- wrong room. Doors, portals, home and custom exits are sent as they are.
-- For other modules: go_vnum, go_nearest, go_area, go_room, zone_of, where,
-- probe, zones_with_rooms, and areas (target, quest, campaign use them).
-- Data: data/portals.lua, areas.lua, labels.lua (made from tt++ by
-- tools/convert_ttdata.py; Rune's copies are the master now).
--
-- Every route is the cheapest one: a room costs 1, home 1, a portal
-- portal_cost (data/portals.lua). Besides the map's exits, the search can
-- take, from any room the map doesn't mark against it:
--   a portal (one step to its vnum) - not from no-portal rooms (data 1 or 3),
--     only portals your tier level allows, only ones with a vnum. The held
--     default portal costs 1 (it's only "enter")
--   "home" (one step to home_vnum) - not from no-recall rooms (data 2 or 3)
-- Exits flagged avoid (2) are never used.

local util = require("core.util")
local game = require("core.game")         -- tier and level (portals)
local tags = require("core.tags")         -- hiding the rooms a walk passes
local eq = require("gear.eq")             -- g's hidden eqdata (the end of its chores)
local M = require("nav.mapper")          -- the map
local aliases = require("core.aliases")   -- speedwalk lets an alias go first

local T = {}

local say, warn, trim = util.say, util.warn, util.trim

local function split_cmds(s)
  local out = {}
  for raw in (s .. ";"):gmatch("([^;]*);") do
    local c = raw:match("^%s*(.-)%s*$")
    if c ~= "" then out[#out + 1] = c end
  end
  return out
end

-- Data -------------------------------------------------------------------

T.dir = rune.config_dir .. "/data"

local function load_data(name) return util.load_data(T.dir .. "/" .. name .. ".lua") or {} end

T.cfg = load_data("portals")
T.areas = load_data("areas")
T.labels = load_data("labels")
T.cfg.portals = T.cfg.portals or {}
-- An area's full name (as GMCP and the game give it), lowercased -> zone
local zone_by_name = {}
-- Zones that share one full name are one area to qx and the target (soh and
-- sohtwo are both "The School of Horror": GMCP and the quest give only the
-- name). Full name, lowercased -> its zones, for names with more than one
local zones_by_name = {}
for zone, a in pairs(T.areas) do
  if a.name then
    local k = a.name:lower()
    zone_by_name[k] = zone
    zones_by_name[k] = zones_by_name[k] or {}
    table.insert(zones_by_name[k], zone)
  end
end
-- The zones of `zone`'s area: itself and any sharing its name
local function area_zones(zone)
  local a = T.areas[zone]
  return a and a.name and zones_by_name[a.name:lower()] or { zone }
end
-- Whether two zones are the same area (the same zone, or the same name)
function T.same_area(z1, z2)
  if z1 == z2 then return true end
  local a, b = T.areas[z1 or ""], T.areas[z2 or ""]
  return a ~= nil and b ~= nil and a.name ~= nil and a.name == b.name
end
T.cfg.home_cmds = T.cfg.home_cmds or { "home" }

-- Written to a .tmp file, then renamed over labels.lua
function T.save_labels()
  local file = T.dir .. "/labels.lua"
  local fh, err = io.open(file .. ".tmp", "w")
  if not fh then
    util.err("[travel] can't write labels: " .. tostring(err))
    return false
  end
  local names = {}
  for name in pairs(T.labels) do names[#names + 1] = name end
  table.sort(names)
  fh:write("-- Room labels for ga / find: label -> vnums. Rewritten by label / unlabel.\nreturn {\n")
  for _, name in ipairs(names) do
    local v = T.labels[name]
    table.sort(v)
    fh:write(string.format("  [%q] = { %s },\n", name, table.concat(v, ", ")))
  end
  fh:write("}\n")
  fh:close()
  local ok, rerr = os.rename(file .. ".tmp", file)
  if not ok then
    util.err("[travel] can't replace labels.lua: " .. tostring(rerr))
  end
  return ok
end

-- Which portals you can use: tier level = tier * 10 + level (core/game.lua)
local function tier_level() return (game.tier or 0) * 10 + (game.level or 0) end

-- The search -------------------------------------------------------------

local function portal_cmds(obj)
  if obj == T.cfg.default_portal then return { "enter" } end
  local bag = T.cfg.bag or "portalbag"
  return { "get " .. obj .. " " .. bag, "hold " .. obj, "enter", "rem " .. obj,
           "put " .. obj .. " " .. bag, "hold " .. T.cfg.default_portal }
end

-- Portal steps usable now: { { to, name, cmds } }, one per object
local function portal_steps()
  local steps, seen, tl = {}, {}, tier_level()
  local names = {}
  for name in pairs(T.cfg.portals) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local p = T.cfg.portals[name]
    if p.vnum and not seen[p.obj] and tl >= (p.lvl or 0) then
      seen[p.obj] = true
      local cost = p.obj == T.cfg.default_portal and 1 or (T.cfg.portal_cost or 6)
      steps[#steps + 1] = { to = p.vnum, name = "portal " .. name, cmds = portal_cmds(p.obj), cost = cost }
    end
  end
  return steps
end

local function blocks(r, a, b)
  local d = r and r.data or ""
  return d == a or d == b
end

-- Cheapest route from `from` (Dial's algorithm - Dijkstra with whole-number
-- costs kept in buckets). A room costs 1; a portal portal_cost (1 for the
-- held default portal, which is only "enter"); home 1. With
-- `goal(vnum)`, stops at the cheapest room where it's true and returns that
-- vnum; without one, explores everything. `walk_only`: exits only - no
-- home, no portals (ga; gm and the like inside the area you're in, first).
-- Returns found, prev (vnum -> vnum), how (vnum -> { name, cmds }),
-- dist (vnum -> cost), hops (vnum -> steps).
function T.search(from, goal, walk_only)
  local rooms = M.rooms
  local prev, how, dist, hops = { [from] = false }, {}, { [from] = 0 }, { [from] = 0 }
  local portals = walk_only and {} or portal_steps()
  local portals_done, home_done = walk_only, walk_only
  local home = T.cfg.home_vnum
  local done = {}
  local buckets, c, top = { [0] = { from } }, 0, 0
  local v   -- the room being expanded
  -- One step from v (made once, not per room - the search visits tens of
  -- thousands)
  local function step(to, name, cmds, cost)
    local nd = c + cost
    if rooms[to] and not done[to] and (not dist[to] or nd < dist[to]) then
      prev[to], how[to], dist[to], hops[to] = v, { name = name, cmds = cmds }, nd, hops[v] + 1
      local b = buckets[nd]
      if b then b[#b + 1] = to else buckets[nd] = { to } end
      if nd > top then top = nd end
    end
  end
  while c <= top do
    local b = buckets[c]
    local i = 1
    while b and i <= #b do
      v = b[i]
      i = i + 1
      if not done[v] and dist[v] == c then
        done[v] = true
        if goal and goal(v) then return v, prev, how, dist, hops end
        local r = rooms[v]
        if r then
          for name, e in pairs(r.exits) do
            if e.flags ~= "2" then step(e.to, name, e.cmds ~= "" and e.cmds or name, 1) end
          end
          -- Rooms come out cheapest first, so the first room a portal or
          -- home can be used from is the best one to use it from
          if not portals_done and not blocks(r, "1", "3") then
            portals_done = true
            for _, p in ipairs(portals) do step(p.to, p.name, p.cmds, p.cost) end
          end
          if not home_done and home and not blocks(r, "2", "3") then
            home_done = true
            step(home, "home", "home", 1)
          end
        end
      end
    end
    buckets[c] = nil
    c = c + 1
  end
  return nil, prev, how, dist, hops
end

-- The commands to get from the search's start to `to`, the step count, the
-- steps ({ name, cmds }) and the room each step reaches
function T.path(prev, how, to)
  local chain, rooms = {}, {}
  while prev[to] do
    table.insert(chain, 1, how[to])
    table.insert(rooms, 1, to)
    to = prev[to]
  end
  local cmds = {}
  for _, s in ipairs(chain) do
    local c = type(s.cmds) == "table" and s.cmds or split_cmds(s.cmds)
    for _, x in ipairs(c) do cmds[#cmds + 1] = x end
  end
  return cmds, #chain, chain, rooms
end

-- The walk ---------------------------------------------------------------

local function here()
  if not M.here then
    warn("[travel] the game hasn't reported your room yet - asking for it; try again in a moment.")
    rune.gmcp.send("request room")
  end
  return M.here
end

local function describe(chain)
  local used = {}
  for _, s in ipairs(chain) do
    if s.name == "home" or s.name:find("^portal ") then used[#used + 1] = s.name end
  end
  return #used > 0 and (" via " .. table.concat(used, ", ")) or ""
end

-- The walk under way: where it started, its steps and the rooms they should
-- reach, and the rooms GMCP room.info has reported since (one per move) -
-- so a failed step can be named
local plan
local alas = false   -- an "Alas, you cannot go that way." during this walk's run

-- The commands for a route, plain moves run together: each stretch of
-- them is one game "run" ("run 2n3e"), a door, portal, home or custom
-- exit is sent as it is. Also how many of them show a room: a run shows
-- only the room it ends in (the game's, seen live 2026-11-07 - GMCP still
-- sends room.info for every room on the way), any other step its room
local function run_cmds(chain)
  local out, shows = {}, 0
  local run, last, count = "", nil, 0
  local function close_dir()
    if last then run = run .. (count > 1 and count or "") .. last end
    last, count = nil, 0
  end
  local function close_run()
    close_dir()
    if run ~= "" then
      out[#out + 1] = run:match("^[nsewud]$") and run or ("run " .. run)
      shows = shows + 1
      run = ""
    end
  end
  for _, s in ipairs(chain) do
    local c = type(s.cmds) == "string" and s.cmds or nil
    if c and c:match("^[nsewud]$") then
      if c ~= last then close_dir(); last = c end
      count = count + 1
    else
      close_run()
      for _, x in ipairs(type(s.cmds) == "table" and s.cmds or split_cmds(s.cmds)) do out[#out + 1] = x end
      shows = shows + 1
    end
  end
  close_run()
  return out, shows
end
T.run_cmds = run_cmds   -- for the offline tests

-- Send a walk: the steps, the rooms they reach (cmds, from T.path, isn't
-- used: run_cmds rebuilds them from the steps)
local function send_walk(_, chain, rooms, what)
  local n = #chain
  say(string.format("[travel] %s: %d step%s%s", what, n, n == 1 and "" or "s", describe(chain)))
  plan = { from = M.here, chain = chain, rooms = rooms, seen = {} }
  alas = false
  local cmds, shows = run_cmds(chain)
  tags.hide_rooms(shows)   -- show only the room you arrive in; also marks the walk (core/tags.lua)
  rune.send_raw(table.concat(cmds, "\n"))
end

-- Walk to `to` using a finished search from the current room
local function walk(prev, how, to, what)
  local cmds, n, chain, rooms = T.path(prev, how, to)
  if n == 0 then
    say("[travel] already at " .. what .. ".")
    return
  end
  send_walk(cmds, chain, rooms, what)
end

-- g <the area you're in>: home, then the way from home to the area - to
-- its entrance, the room of it nearest home, as from anywhere else
local function walk_from_home(zone, what)
  local r = M.here and M.rooms[M.here]
  if blocks(r, "2", "3") then
    return warn("[travel] g: this room doesn't allow home - walk out of it first.")
  end
  local home = T.cfg.home_vnum
  if not (home and M.rooms[home]) then return warn("[travel] g: home_vnum isn't on the map (data/portals.lua).") end
  local found, prev, how = T.search(home, function(x) return M.rooms[x].area == zone end)
  if not found then return warn("[travel] g: no route from home to " .. what .. " on the map.") end
  local cmds, _, chain, rooms = T.path(prev, how, found)
  table.insert(cmds, 1, "home")
  table.insert(chain, 1, { name = "home", cmds = "home" })
  table.insert(rooms, 1, home)
  send_walk(cmds, chain, rooms, what .. " (" .. found .. ")")
end

-- mf: the route to `to`, printed - not walked. Each step with the room it
-- reaches, then the commands as one line (to type or paste)
local function show(prev, how, to, what)
  local cmds, n, chain, rooms = T.path(prev, how, to)
  if n == 0 then return say("[travel] mf: already at " .. what .. ".") end
  say(string.format("[travel] mf %s: %d step%s%s", what, n, n == 1 and "" or "s", describe(chain)))
  for k, step in ipairs(chain) do
    local c = type(step.cmds) == "table" and table.concat(step.cmds, ";") or step.cmds
    local r = M.rooms[rooms[k]]
    rune.echo(string.format("  %2d %-8s %d %s", k, c, rooms[k],
      r and rune.style.gray(util.strip(r.name) .. ", " .. r.area) or ""))
  end
  rune.echo("  " .. table.concat(cmds, ";"))
end

-- (after nav/mapper.lua's handler, which this file's require ran first)
rune.gmcp.on("room.info", function()
  if not plan then return end
  local v = M.here
  local seen = plan.seen
  if v and v ~= seen[#seen] and v ~= (#seen == 0 and plan.from or nil) then seen[#seen + 1] = v end
  if #seen >= #plan.rooms then plan = nil end   -- arrived (or as many moves as planned)
end, { name = "travel_walk_rooms" })

local function room_desc(v)
  local r = v and M.rooms[v]
  return tostring(v) .. (r and r.name ~= "" and (" (" .. util.strip(r.name) .. ")") or "")
end

-- The first step that didn't go where the map said, as a sentence, or nil
local function bad_step()
  local p = plan
  if not p then return nil end
  for k, want in ipairs(p.rooms) do
    local got = p.seen[k]
    if got ~= want then
      local at = k == 1 and p.from or p.rooms[k - 1]
      local step = p.chain[k]
      local cmd = type(step.cmds) == "table" and table.concat(step.cmds, ";") or step.cmds
      if not got then
        return string.format("step %d of %d, \"%s\" from %s, didn't move you - the map says it leads to %s",
          k, #p.rooms, cmd, room_desc(at), room_desc(want))
      end
      return string.format("step %d of %d, \"%s\" from %s, took you to %s - the map says %s",
        k, #p.rooms, cmd, room_desc(at), room_desc(got), room_desc(want))
    end
  end
end

function T.go_vnum(v, what)
  local from = here()
  if not from then return end
  local found, prev, how = T.search(from, function(x) return x == v end)
  if not found then
    warn("[travel] no route to " .. (what or tostring(v)) .. ".")
    return
  end
  walk(prev, how, found, what or ("room " .. v))
end

-- Nearest room in the set (vnum -> true). `mode`: "only" - exits only (see
-- T.search); "first" - exits only if the map has such a route, else any
function T.go_nearest(set, what, mode)
  local from = here()
  if not from then return end
  local goal = function(x) return set[x] end
  local found, prev, how = T.search(from, goal, mode ~= nil)
  if not found and mode == "first" then found, prev, how = T.search(from, goal) end
  if not found then
    warn("[travel] no route to " .. what .. ".")
    return
  end
  local r = M.rooms[found]
  walk(prev, how, found, what .. " (" .. found .. (r and r.name ~= "" and (" " .. r.name) or "") .. ")")
end

-- A move the room doesn't have, during a walk - while core/tags.lua still expects
-- rooms of it (a failed step always leaves some). The whole route was sent
-- at once, so the rest can't be called back. If the map has that exit here, the
-- map is wrong; if not, an earlier step failed (a mob, a closed door) and the
-- later moves ran from the wrong room.
rune.gmcp.on("room.wrongdir", function(d)
  if not tags.walking() or tags.walk_owner() then return end   -- not ours: its owner reports it
  tags.walk_stopped()   -- print the room the walk stopped in, if it was hidden
  local bad = bad_step()
  plan = nil
  if bad then return warn("[travel] the walk went wrong: " .. bad .. ".") end
  local dir = type(d) == "table" and (d.dir or d[1]) or d
  dir = tostring(dir or "?")
  local r = M.here and M.rooms[M.here]
  if r and r.exits[dir] then
    warn(string.format("[travel] the map has a %s exit from room %d (%s) that the game doesn't. Remove it with: map unlink %s",
      dir, M.here, r.name, dir))
  else
    warn(string.format("[travel] the walk went off course: an earlier step didn't happen, so %s was tried from room %s. The map is fine - clear the way and go again.",
      dir, tostring(M.here)))
  end
end, { name = "travel_wrongdir" })

-- A run stopped: after three failed moves - a wall ("Alas, you cannot go
-- that way."), a room that refuses you ("Only a primary class paladin can
-- enter that room.") - the game gives up on it (seen live 2026-11-07). A
-- fight stops a run too (core/tags.lua shows the room at once). If GMCP's
-- room.wrongdir came first, that reported it and the plan is gone
rune.trigger.exact("Alas, you cannot go that way.", function()
  if plan then alas = true end
end, { name = "travel_run_alas" })
rune.trigger.exact("Too many run errors. Aborting speedwalk.", function()
  local was_alas = alas
  alas = false
  if not plan or tags.walk_owner() then return end
  tags.walk_stopped()
  local bad = bad_step()
  local k = #plan.seen + 1
  local step = plan.chain[k]
  plan = nil
  if not bad then return end
  warn("[travel] the walk stopped: " .. bad .. ".")
  local r = M.here and M.rooms[M.here]
  local dir = step and type(step.cmds) == "string" and step.cmds
  if was_alas and r and dir and r.exits[dir] then
    warn(string.format("[travel] the game says there's no %s exit here - if so, remove the map's: map unlink %s", dir, dir))
  end
end, { name = "travel_run_abort" })

-- Speedwalk, as tt++'s #CONFIG SPEEDWALK ON: a line of only n s e w u d,
-- each with an optional count before it ("13s", "3e2n", "nnw"), is walked.
-- Like tt++, a word of only those letters ("news") is walked too
-- An alias wins, as in tt++: su, dd (core/aliases.lua) are not walks
rune.alias.regex("^((?:[0-9]*[nsewud])+)$", function(m)
  if aliases.run(m[1]) then return end
  local cmds = {}
  for count, dir in tostring(m[1] or ""):gmatch("(%d*)([nsewud])") do
    for _ = 1, math.min(tonumber(count) or 1, 100) do cmds[#cmds + 1] = dir end
  end
  if #cmds == 0 then return end
  -- One game run: it shows only the room it ends in, and stops at a wall
  -- or a fight with its own message. One step (a plain "s") is just a move
  plan = nil   -- not a planned route: no step to name
  rune.send_raw(#cmds == 1 and cmds[1] or ("run " .. m[1]))
end, { name = "travel_speedwalk" })

-- The game refused a recall or home: mark the room no-recall (2, or 3 with
-- no-portal), so routes from it walk out instead. Both wordings seen: the
-- first in tt++ (modules/paths.tin, for recall and home), the second for
-- home in nynewoods 23576 (2026-11-06)
rune.trigger.regex("^You cannot (recall|return home) from this room\\.$", function()
  local r = M.here and M.rooms[M.here]
  if not r then return end
  if r.data == "" or r.data == "0" then r.data = "2"
  elseif r.data == "1" then r.data = "3"
  else return end
  M.dirty = true
  say("[travel] room " .. M.here .. " marked no-recall on the map - routes from it now walk out first.")
end, { name = "travel_norecall" })

-- Matching ---------------------------------------------------------------

local function contains(hay, needle)
  return (hay or ""):lower():find(needle, 1, true) ~= nil
end

-- Labels starting with `text`: { label = { vnum, ... } }
local function labels_matching(text, zone)
  local out, n = {}, 0
  for name, vnums in pairs(T.labels) do
    if name:sub(1, #text) == text then
      for _, v in ipairs(vnums) do
        local r = M.rooms[v]
        if not zone or (r and r.area == zone) then
          out[name] = out[name] or {}
          table.insert(out[name], v)
        end
      end
      if out[name] then n = n + 1 end
    end
  end
  return out, n
end

-- A room's name without colour codes (a few have them). The find first,
-- since this runs for every room on the map
local function plain_name(r)
  return r.name:find("\27", 1, true) and util.strip(r.name) or r.name
end

-- Rooms whose name contains `text` (all rooms if text == ""), in `zone` or
-- anywhere: name -> { [vnum] = true }
local function rooms_matching(text, zone)
  local out = {}
  for v, r in pairs(M.rooms) do
    local name = plain_name(r)
    if name ~= "" and (not zone or r.area == zone) and (text == "" or contains(name, text)) then
      local key = zone and name or (name .. "\t" .. r.area)
      out[key] = out[key] or {}
      out[key][v] = true
    end
  end
  return out
end

local function set_of(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

-- Areas matching `text`: exact zone or keyword first, else part of the
-- zone, keyword or name. Returns a list of zones, and true for an exact match
local function areas_matching(text)
  for zone, a in pairs(T.areas) do
    if zone == text or a.kw == text then return { zone }, true end
  end
  local out = {}
  for zone, a in pairs(T.areas) do
    if contains(zone, text) or contains(a.kw, text) or contains(a.name, text) then
      out[#out + 1] = zone
    end
  end
  table.sort(out)
  return out
end

local function area_label(zone)
  local a = T.areas[zone]
  return a and a.name or zone or "?"
end

-- Choices: { text, desc, what, and set (vnum -> true) or zone }. Measured
-- with one full search from here; unreachable ones are dropped. One goes
-- straight there; several open the picker, nearest first.
-- `act` is walk (the default) or show (mf)
local function choose(title, choices, on_none, act)
  act = act or walk
  local from = here()
  if not from then return end
  local _, prev, how, dist, hops = T.search(from)
  -- Nearest room of every zone, in one pass over what the search reached
  local zbest, zd = {}, {}
  for v, d in pairs(dist) do
    local z = M.rooms[v].area
    if not zd[z] or d < zd[z] then zbest[z], zd[z] = v, d end
  end
  local items, lost = {}, {}
  for _, c in ipairs(choices) do
    local best, bd
    if c.zone then
      best, bd = zbest[c.zone], zd[c.zone]
    else
      for v in pairs(c.set) do
        if dist[v] and (not bd or dist[v] < bd) then best, bd = v, dist[v] end
      end
    end
    if best then
      -- The room you're in is no choice
      if bd > 0 then items[#items + 1] = { c = c, v = best, d = bd } end
    else
      lost[#lost + 1] = c.text
    end
  end
  if #items == 0 and #lost == 0 then
    return say("[travel] " .. title .. ": you're already there.")
  end
  if #items == 0 then
    if on_none then return on_none() end
    table.sort(lost)
    warn("[travel] " .. title .. ": no route from here to " .. table.concat(lost, ", ", 1, math.min(#lost, 5))
      .. (#lost > 5 and ", ..." or "") .. " - not linked to this part of the map. g <area> falls back to the game's runto.")
    return
  end
  table.sort(items, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.c.text < b.c.text
  end)
  local function go(it)
    act(prev, how, it.v, it.c.what .. " (" .. it.v .. ")")
  end
  if #items == 1 then return go(items[1]) end
  local list = {}
  for i, it in ipairs(items) do
    list[i] = { text = it.c.text, desc = it.c.desc .. " - " .. hops[it.v] .. " steps", value = i }
  end
  rune.ui.picker.show({
    title = title,
    items = list,
    match_description = true,
    on_select = function(i)
      -- The picker can sit open while you move; search again from wherever you are
      local it = items[tonumber(i)]
      if not it then return end
      if M.here == from or act ~= walk then go(it) else T.go_vnum(it.v, it.c.what) end
    end,
  })
end

-- Commands ---------------------------------------------------------------

-- ga <text>: a room in this area - a label starting with it, else a room
-- whose name contains it. Nearest
rune.alias.exact("ga", function(args)
  local text = trim(args):lower()
  if text == "" then return warn("[travel] ga <text> - a label or room name in this area.") end
  local from = here()
  if not from then return end
  local r = M.rooms[from]
  local zone = r and r.area ~= "" and r.area or nil
  if not zone then return warn("[travel] ga: this room's area isn't known.") end
  local labs, n = labels_matching(text, zone)
  if n > 0 then
    local set, names = {}, {}
    for name, vnums in pairs(labs) do
      names[#names + 1] = name
      for _, v in ipairs(vnums) do set[v] = true end
    end
    table.sort(names)
    return T.go_nearest(set, "label " .. table.concat(names, "/"), "only")
  end
  local set = {}
  for _, vs in pairs(rooms_matching(text, zone)) do
    for v in pairs(vs) do set[v] = true end
  end
  if next(set) == nil then
    return warn("[travel] ga: no label or room here matches \"" .. text .. "\" - find " .. text .. " searches everywhere.")
  end
  T.go_nearest(set, "\"" .. text .. "\"", "only")
end)

-- find [text] walks there; mf [text] shows the route (tt++ mf)
local function find(args, title, act)
  local text = trim(args):lower()
  local v = tonumber(text)
  if v then
    if not M.rooms[v] then return warn("[travel] room " .. v .. " isn't on the map.") end
    local from = here()
    if not from then return end
    local found, prev, how = T.search(from, function(x) return x == v end)
    if not found then return warn("[travel] " .. title .. ": no route to room " .. v .. ".") end
    return act(prev, how, found, "room " .. v)
  end
  local choices = {}
  for name, vnums in pairs(labels_matching(text)) do
    local r = M.rooms[vnums[1]]
    choices[#choices + 1] = { text = name, desc = "label, " .. area_label(r and r.area),
                              set = set_of(vnums), what = "label " .. name }
  end
  local zones = text == "" and {} or areas_matching(text)
  if text == "" then for zone in pairs(T.areas) do zones[#zones + 1] = zone end end
  for _, zone in ipairs(zones) do
    choices[#choices + 1] = { text = area_label(zone), desc = "area " .. zone,
                              zone = zone, what = "area " .. zone }
  end
  if text ~= "" then
    for key, set in pairs(rooms_matching(text)) do
      local name, area = key:match("^(.*)\t(.*)$")
      choices[#choices + 1] = { text = name, desc = "room, " .. area_label(area), set = set, what = name }
    end
  end
  if #choices == 0 then return warn("[travel] " .. title .. ": nothing matches \"" .. text .. "\".") end
  choose(title, choices, nil, act)
end

rune.alias.exact("find", function(args) find(args, "find", walk) end)
rune.alias.exact("mf", function(args) find(args, "mf", show) end)

-- A limited-use portal (data/portals.lua: zone set, no vnum, so routes never
-- spend it) is tried first by g <its area>, from outside that area: "get" it
-- from the bag, and only on the game's "You get ..." hold and enter it. No
-- such reply within 2 s (none left in the bag): `fallback`, the usual way
local function try_limited(zone, fallback)
  local p
  for _, q in pairs(T.cfg.portals) do
    if q.zone == zone and not q.vnum then p = q end
  end
  local r = M.here and M.rooms[M.here]
  if not p or not r or r.area == zone or blocks(r, "1", "3") or tier_level() < (p.lvl or 0) then
    return fallback()
  end
  local cmds, done = portal_cmds(p.obj), false
  local got = rune.trigger.regex("^You get .* from ", function()
    if done then return end
    done = true
    say("[travel] portal " .. p.obj)
    rune.send_raw(table.concat(cmds, "\n", 2))
  end, { name = "travel_limited", once = true })
  rune.timer.after(2, function()
    if done then return end
    done = true
    got:remove()
    fallback()
  end)
  rune.send_raw(cmds[1])
end

-- The home routine: home's room shows; its chores (gulp, the bank -
-- everything after the first home command) are hidden, then gear/eq.lua's
-- hidden eqdata refreshes what's worn. The game answers in order, so the
-- chores' output is everything between the {/roomchars} tag that ends
-- home's room and the {/eqdata} tag that ends eqdata's reply - found by
-- the tags, not the replies' wording. Already home: no room, but "You are
-- already in your home!" (seen live 2026-11-07), shown, then the same. No
-- room otherwise (home refused): nothing is hidden but eqdata. It ends at {/eqdata}; 10 s if that never comes
local quiet_line = util.group(true)   -- one catch-all, only while it's needed
local quiet = { hiding = false, timer = util.slot() }
quiet_line.add("starts", "", function(_, ctx)
  local clean = ctx.line:clean()
  if clean:find("^{/eqdata}") then
    quiet_line.set(false)
    return   -- gear/eq.lua hides it, and the blank after
  end
  if not quiet.hiding then
    if clean == "{/roomchars}" or clean == "You are already in your home!" then
      quiet.hiding, quiet.first = true, true
    end
    return
  end
  -- The blank line that follows a room shows, as when you walk in
  if quiet.first then
    quiet.first = false
    if util.blank(clean) then return end
  end
  return false
end, { name = "travel_home_quiet", priority = 1 })

local function home_routine()
  quiet.hiding = false
  quiet_line.set(true)
  quiet.timer.start(10, function() quiet_line.set(false) end)
  rune.send_raw(table.concat(T.cfg.home_cmds, "\n"))
  if not eq.check_worn() then quiet_line.set(false) end   -- no {/eqdata} coming: hide nothing
end

-- To one of `zones`, the nearest (a picker if several reach): one zone's
-- limited portal first; no route on the map: home and the game's runto
-- with `rt`. `what` names it in the message. One zone, and you're in it:
-- home, then to it from there
local function go_zones(zones, rt, what)
  local function route()
    local choices = {}
    for _, zone in ipairs(zones) do
      choices[#choices + 1] = { text = area_label(zone), desc = "area " .. zone,
                                zone = zone, what = "area " .. zone }
    end
    choose("g", choices, function()
      warn("[travel] no route to " .. what .. " on the map - going home and using runto.")
      rune.send_raw("home\ndown\nrt " .. rt)
    end)
  end
  if #zones == 1 then
    local r = M.here and M.rooms[M.here]
    if r and r.area == zones[1] then return walk_from_home(zones[1], "area " .. zones[1]) end
    return try_limited(zones[1], route)
  end
  route()
end

-- g: the home routine. g <area>: an area - exact zone or keyword, else part
-- of a name (a picker if several). An area the map can't route to (not
-- mapped, or no mapped way in) falls back to the game's runto, from home
rune.alias.exact("g", function(args)
  local text = trim(args):lower()
  -- (not "return rune.send_raw": an alias's return value is run as a command)
  if text == "" then
    home_routine()
    return
  end
  local zones = areas_matching(text)
  if not zones[1] then
    return warn("[travel] g: no area matches \"" .. text .. "\" - ga for this area, find for anywhere.")
  end
  go_zones(zones, text, "\"" .. text .. "\"")
end)

-- To an area by zone, as g <area> does (for qx, targets/quest.lua)
-- An area of several zones (area_zones) is reached at its nearest room in
-- any of them - a portal into one of them ends the route there
function T.go_area(zone)
  local rt = (T.areas[zone] or {}).kw or zone
  local zones = area_zones(zone)
  if #zones == 1 then return go_zones({ zone }, rt, area_label(zone)) end
  local is, rooms = set_of(zones), {}
  for v, r in pairs(M.rooms) do
    if is[r.area] then rooms[v] = true end
  end
  try_limited(zone, function()
    choose("g", { { text = area_label(zone), desc = "area " .. zone, set = rooms, what = "area " .. zone } },
      function()
        warn("[travel] no route to " .. area_label(zone) .. " on the map - going home and using runto.")
        rune.send_raw("home\ndown\nrt " .. rt)
      end)
  end)
end

-- The zone of an area's full name ("The Amazon Nation"), as GMCP gives it
function T.zone_of(name) return zone_by_name[(name or ""):lower()] end

-- The gnome airship isn't on the map
rune.alias.exact("gnom", function()
  rune.send_raw("home\ndown\nrt gnom\ns\nw\nboard airship")
end)

-- where -----------------------------------------------------------------
-- For targets/target.lua. The where reply (tags where on) is the tag line, ONE
-- answer line - the mob's name in a 30-column field, a space, its room - or
-- "There is no <mob> around here.", then the closing tag. The answer can
-- also come on the tag's own line, the closing tag too. where only covers
-- your own area, and some areas refuse it ("There are too many doors ...").

-- One of `zones`, chosen: each is a choice, measured to its entrance (its
-- room nearest you) - one reachable goes straight there, several open the
-- picker (nearest first, with its steps). It walks to the entrance only;
-- on_pick(zone) runs as the walk is sent. For a campaign room name several
-- areas share (targets/campaign.lua)
function T.go_area_of(zones, title, on_pick)
  local choices = {}
  for _, z in ipairs(zones) do
    choices[#choices + 1] = { text = area_label(z), desc = "area " .. z, zone = z, what = "area " .. z }
  end
  choose(title, choices, nil, function(prev, how, v, w)
    on_pick(M.rooms[v].area)
    walk(prev, how, v, w)
  end)
end

-- To the room named `room` in `zone` - the nearest, if several share it.
-- In the area you're in: walked when the map has a way on foot, else by
-- any route (home, portals)
function T.go_room(zone, room, what)
  local set = {}
  for v, r in pairs(M.rooms) do
    if T.same_area(r.area, zone) and plain_name(r):lower() == room:lower() then set[v] = true end
  end
  if next(set) == nil then
    return warn("[travel] no room named \"" .. room .. "\" in " .. area_label(zone) .. " on the map.")
  end
  local r = M.here and M.rooms[M.here]
  T.go_nearest(set, what, r and T.same_area(r.area, zone) and "first" or nil)
end

-- One where question at a time: T.where(kw, cb) sends "where <kw>" and
-- calls cb(name, room) with the answer, or cb(nil, why), or cb(nil, why,
-- true) when the area refuses where. The answer line is always hidden, and
-- the blank line(s) after it - callers say what came of it
local where_asked, where_cb = 0, nil
local where_got    -- the answer line, held until {/where} closes the reply
local where_timeout = util.slot()   -- 5 s after a where is sent
local where_line = util.group(true)   -- one catch-all, only inside a reply

-- The reply is over: the blank line(s) after it hidden, cb told. The answer
-- goes out only now - cb may ask the next where at once, and this reply's
-- {/where} must not be taken for that one's
local function where_done(clean)
  where_timeout.stop()
  where_line.set(false)
  util.eat_blanks(clean)
  where_asked = 0
  local line, cb = where_got, where_cb
  where_got = nil
  if not line then return cb(nil, "the game gave no answer.") end
  line = line:gsub("{/where}%s*$", "")
  local text = trim(line)
  if text:find("^There is no ") then return cb(nil, text) end
  if text:find("^There are too many ") then return cb(nil, text, true) end
  local name, room = trim(line:sub(1, 30)), trim(line:sub(31))
  if room == "" then return cb(nil, "can't read the where reply \"" .. text .. "\".") end
  cb(name, room)
end

-- The reply's lines after its {where} tag, up to {/where} - all hidden.
-- On only for those few lines (5 s at most)
where_line.add("starts", "", function(_, ctx)
  local clean = ctx.line:clean()
  if clean:find("^{where}") then return end   -- the tag line that turned it on
  if clean:find("^{/where}") then where_done(clean); return false end
  where_got = where_got or clean
  if clean:find("{/where}", 1, true) then where_done(clean) end
  return false
end, { name = "travel_where_line", priority = 5 })

-- Before core/tags.lua cuts the tag out. Only within 5 s of asking. The answer
-- may come on the tag's line, the closing tag too
tags.on("where", function(rest, ctx)
  if os.time() - where_asked > 5 then return end
  where_got = not util.blank(rest) and rest or nil
  if rest:find("{/where}", 1, true) then where_done(ctx.line:clean()); return false end
  where_line.set(true)
  if where_got then return false end   -- else core/tags.lua hides the bare tag
end)

function T.where(kw, cb)
  where_asked, where_cb, where_got = os.time(), cb, nil
  -- No reply in 5 s: cb hears so (else a waiting check would wait forever)
  where_timeout.start(5, function()
    if where_asked == 0 then return end
    where_line.set(false)
    where_asked, where_got = 0, nil
    cb(nil, "no where reply from the game.")
  end)
  rune.send_raw("where " .. kw)
end

-- A where question still waiting for its answer
function T.where_busy() return os.time() - where_asked <= 5 end

-- Probe (tt++ campaign.tin's where plan): finds a mob by its full name.
-- where is asked with `kw` first if given, then each of
-- util.mob_keywords(name). where shows the FIRST mob a keyword fits, so a
-- try only counts when the answer is this mob - names compared lowercased,
-- cut to where's 30 columns. An answer naming another mob means an earlier
-- one holds the keyword: 2.kw, 3.kw ... are asked (to PROBE_MAX) until this
-- mob or no answer (no more mobs with it). Found as N.kw, kw is "N.kw" -
-- where's count, for the area (k strips it: fight/combat.lua). The tries' lines
-- are hidden. cb(kw, room), or cb(nil) when nothing fit or the area
-- refuses where (no more tries). The room may be a same-named mob's
local PROBE_MAX = 15
function T.probe(name, cb, kw)
  local tries = {}
  if kw then tries[1] = kw end
  for _, k in ipairs(util.mob_keywords(name)) do
    if k ~= kw then tries[#tries + 1] = k end
  end
  local want, i, n = trim(name:sub(1, 30):lower()), 0, 1
  local function next_try(other)
    -- another mob answered: the same keyword's next one, else the next keyword
    if other and n < PROBE_MAX and not tries[i]:find("^%d+%.") then
      n = n + 1
    else
      i, n = i + 1, 1
    end
    local k = tries[i]
    if not k then return cb(nil) end
    if n > 1 then k = n .. "." .. k end
    T.where(k, function(got, room, refused)
      if refused then return cb(nil) end
      if got and got:lower() == want then return cb(k, room) end
      next_try(got ~= nil)
    end)
  end
  next_try()
end

-- The zones holding a room of each name: names = { [name] = true }, any
-- case. One pass over the map for them all. Returns name -> { zone, ... }
function T.zones_with_rooms(names)
  local want, out = {}, {}
  for n in pairs(names) do want[n:lower()] = n; out[n] = {} end
  local seen = {}
  for _, r in pairs(M.rooms) do
    local n = want[plain_name(r):lower()]
    if n and not seen[n .. "\t" .. r.area] then
      seen[n .. "\t" .. r.area] = true
      table.insert(out[n], r.area)
    end
  end
  return out
end

-- Labels -----------------------------------------------------------------

rune.alias.exact("label", function(args)
  local name = trim(args):lower()
  if name == "" or name:find("%s") then return warn("[travel] label <one word>") end
  local v = here()
  if not v then return end
  local list = T.labels[name] or {}
  for _, x in ipairs(list) do
    if x == v then return say("[travel] this room is already labelled " .. name .. ".") end
  end
  list[#list + 1] = v
  T.labels[name] = list
  if T.save_labels() then say("[travel] room " .. v .. " labelled " .. name .. ".") end
end)

rune.alias.exact("unlabel", function(args)
  local name = trim(args):lower()
  local v = here()
  if not v or name == "" then return warn("[travel] unlabel <label>") end
  local list = T.labels[name] or {}
  for i, x in ipairs(list) do
    if x == v then
      table.remove(list, i)
      if #list == 0 then T.labels[name] = nil end
      if T.save_labels() then say("[travel] removed label " .. name .. " from room " .. v .. ".") end
      return
    end
  end
  warn("[travel] this room isn't labelled " .. name .. ".")
end)

rune.alias.exact("labels", function()
  local names = {}
  for name in pairs(T.labels) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local where = {}
    for _, v in ipairs(T.labels[name]) do
      local r = M.rooms[v]
      where[#where + 1] = v .. (r and (" " .. r.name .. ", " .. area_label(r.area)) or "")
    end
    rune.echo(string.format("  %-14s %s", name, table.concat(where, "; ")))
  end
end)

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("g", "g [area]", "bare: the home routine; with an area: go there (a picker if several match)")
help.add("ga", "ga <text>", "this area: the nearest room labelled or named <text>, walked")
help.add("find", "find [text]", "anywhere: labels, areas, room names, a vnum - one match goes there, several open a picker")
help.add("mf", "mf [text]", "as find, but shows the route instead of walking it")
help.add("gnom", "gnom", "the gnome airship (not on the map)")
help.add("label", "label <word>", "label this room, for find and ga")
help.add("unlabel", "unlabel <word>", "remove a label from this room")
help.add("labels", "labels", "every room label")
help.add("13s", "13s, 3e2n ...", "speedwalk: a count and a direction letter, run together")

return T
