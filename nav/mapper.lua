-- Mapper core (phase 2): the Aardwolf room map in Lua - the world's data:
-- rooms and exits (map/aard.map), areas (data/areas.lua) and room labels
-- (data/labels.lua). require("nav.mapper") returns it; travel, minimap and
-- the target modules use it. It requires nothing of theirs.
--
-- The map file is map/aard.map, made from the tt++ map by
-- tools/convert_ttmap.py. Plain text, one record per line, TAB-separated:
--   R  vnum  area  terrain  data  note  name
--   X  from  to    exit     flags cmds
-- data: 1 no portal, 2 no recall, 3 both. note: the rmsg room message.
-- flags: 2 = avoid. cmds: what to send for the exit, ";"-joined, empty when
-- it's just the exit name.
--
-- Updated from GMCP room.info as you walk, with the tt++ automapper's rules
-- (modules/gmcp.tin's ||gmcp_hook_room_info):
--   - vnum -1 is skipped
--   - a room not on the map is added; its name, area and terrain are filled
--     in only while it is a placeholder (no name - an exit's unvisited end)
--   - only NEW exits are added, never changed; a destination not on the map
--     becomes a placeholder
--   - a maze room (details contain "maze") gets its name, area and terrain
--     but no exits - GMCP lists every maze exit as -1
-- Saved a minute after a change (checked every 60 s), before /reload, on
-- disconnect, and by "mapsave". Rooms by vnum and each room's exits by name,
-- so an unchanged map saves byte for byte the same (a diff shows only what
-- changed; before 2026-11-10 exits came out in pairs() order)
-- Always on - tt++'s $mapping switch was never used by hand, so it's gone.

local util = require("core.util")
local colors = require("core.colors")

local M = {}

M.file = rune.config_dir .. "/map/aard.map"
M.rooms = {}        -- vnum -> { area, terrain, data, note, name, exits = { [exit] = { to, flags, cmds } } }
M.count = 0
M.here = nil        -- current vnum
M.dirty = false

-- Areas and labels (the user, 2026-11-11: the world's data lives here,
-- nav/travel.lua moves through it). Both are plain tables in data/:
--   M.areas    zone slug (a room's area) -> { name, kw, from, to, lock }
--   M.labels   label -> { vnum, ... }   (map label / unlabel / labels)
local DATA = rune.config_dir .. "/data"
M.areas = util.load_data(DATA .. "/areas.lua") or {}
M.labels = util.load_data(DATA .. "/labels.lua") or {}

-- An area's full name (as GMCP and the game give it), lowercased -> zone
local zone_by_name = {}
-- Zones that share one full name are one area to qx and the target (soh and
-- sohtwo are both "The School of Horror": GMCP and the quest give only the
-- name). Full name, lowercased -> its zones, for names with more than one
local zones_by_name = {}
for zone, a in pairs(M.areas) do
  if a.name then
    local k = a.name:lower()
    zone_by_name[k] = zone
    zones_by_name[k] = zones_by_name[k] or {}
    table.insert(zones_by_name[k], zone)
  end
end

-- The zones of `zone`'s area: itself and any sharing its name
function M.area_zones(zone)
  local a = M.areas[zone]
  return a and a.name and zones_by_name[a.name:lower()] or { zone }
end

-- Whether two zones are the same area (the same zone, or the same name)
function M.same_area(z1, z2)
  if z1 == z2 then return true end
  local a, b = M.areas[z1 or ""], M.areas[z2 or ""]
  return a ~= nil and b ~= nil and a.name ~= nil and a.name == b.name
end

-- The zone of an area's full name ("The Amazon Nation"), as GMCP gives it
function M.zone_of(name) return zone_by_name[(name or ""):lower()] end

-- An area's full name, else its zone
function M.area_label(zone)
  local a = M.areas[zone]
  return a and a.name or zone or "?"
end

function M.load()
  local t0 = os.clock()
  local fh, err = io.open(M.file, "r")
  if not fh then
    util.err("[map] can't read " .. M.file .. ": " .. tostring(err))
    return false
  end
  -- One pattern per line, captures straight into the room or exit - no
  -- table per line (1.7x faster than splitting on tabs, measured). A
  -- missing field reads as ""
  local rooms, n, x = {}, 0, 0
  local match, sub = string.match, string.sub
  for line in fh:lines() do
    local k = sub(line, 1, 2)
    if k == "X\t" then
      local from, to, exit, rest = match(line, "^X\t(%d+)\t(%-?%d+)\t([^\t]*)(.*)$")
      local r = from and rooms[tonumber(from)]
      if r then
        local flags, cmds = match(rest, "^\t?([^\t]*)\t?([^\t]*)")
        r.exits[exit] = { to = tonumber(to), flags = flags, cmds = cmds }
        x = x + 1
      end
    elseif k == "R\t" then
      local v, area, terrain, data, note, name =
        match(line, "^R\t(%d+)\t([^\t]*)\t?([^\t]*)\t?([^\t]*)\t?([^\t]*)\t?([^\t]*)")
      if v then
        rooms[tonumber(v)] = { area = area, terrain = terrain, data = data, note = note,
                               name = name, exits = {} }
        n = n + 1
      end
    end
  end
  fh:close()
  M.rooms, M.count, M.dirty = rooms, n, false
  util.say(string.format("[map] %d rooms, %d exits loaded in %.2f s",
    n, x, os.clock() - t0))
  return true
end

local function clean(s)
  return (tostring(s or ""):gsub("[\t\r\n]", " "))
end

function M.save()
  local vnums = {}
  for v in pairs(M.rooms) do vnums[#vnums + 1] = v end
  table.sort(vnums)
  local ok = util.write_file(M.file, function(fh)
    local names = {}   -- one room's exit names, sorted: the file comes out the same every save
    for _, v in ipairs(vnums) do
      local r = M.rooms[v]
      fh:write(table.concat({ "R", v, clean(r.area), clean(r.terrain), clean(r.data),
                              clean(r.note), clean(r.name) }, "\t"), "\n")
      for i = #names, 1, -1 do names[i] = nil end
      for name in pairs(r.exits) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        local e = r.exits[name]
        fh:write(table.concat({ "X", v, e.to, clean(name), clean(e.flags), clean(e.cmds) }, "\t"), "\n")
      end
    end
  end, "[map]")
  if ok then M.dirty = false end
  return ok
end

local function placeholder(v)
  local r = { area = "", terrain = "", data = "", note = "", name = "", exits = {} }
  M.rooms[v] = r
  M.count = M.count + 1
  M.dirty = true
  return r
end

-- A named room whose name GMCP now sends differently (the user, 2026-11-11:
-- the map keeps what the game sent first, as tt++'s did). Never changed
-- here - a line in map/mapnames.log, beside the map, once per room per
-- session: date, vnum, area, the map's name, the game's, TAB-separated.
-- "map renames" lists them, "map renames apply" takes them (below).
-- Cost: one string compare per room.info
M.names_log = rune.config_dir .. "/map/mapnames.log"
local name_logged = {}   -- vnum -> the game's name logged this session
local function check_name(v, r, sent)
  if sent == nil or sent == r.name then return end
  sent = clean(sent)
  if sent == "" or sent == r.name or name_logged[v] == sent then return end
  name_logged[v] = sent
  util.append_file(M.names_log, table.concat({ os.date("%Y-%m-%d %H:%M"), v, r.area, r.name, sent }, "\t"), "[map]")
end

function M.room_info(d)
  local v = tonumber(d.num)
  if not v or v == -1 then return end
  M.here = v
  local r = M.rooms[v] or placeholder(v)
  if r.name == "" then
    r.name, r.area, r.terrain = clean(d.name), clean(d.zone), clean(d.terrain)
    M.dirty = true
  else
    check_name(v, r, d.name)
  end
  if tostring(d.details or ""):find("maze", 1, true) then return end
  if type(d.exits) ~= "table" then return end
  for dir, dest in pairs(d.exits) do
    local to = tonumber(dest)
    if to and to ~= -1 and not r.exits[dir] then
      r.exits[dir] = { to = to, flags = "", cmds = "" }
      if not M.rooms[to] then placeholder(to) end
      M.dirty = true
    end
  end
end

-- debug rooms: each GMCP room.info and room.wrongdir as it comes - what
-- the game's "run" sends (one room.info per room - seen live 2026-11-07)
local dbg = require("core.debug").topic("rooms", "each GMCP room.info (vnum, zone, name) and room.wrongdir as it comes")

rune.gmcp.on("room.info", function(d)
  if type(d) ~= "table" then return end
  if dbg.on then dbg.log(tostring(d.num) .. " " .. tostring(d.zone) .. " " .. colors.strip(tostring(d.name))) end
  M.room_info(d)
end, { name = "aard_mapper" })
rune.gmcp.on("room.wrongdir", function(d)
  if dbg.on then dbg.log("wrongdir " .. (type(d) == "table" and tostring(d.dir or d[1]) or tostring(d))) end
end, { name = "aard_mapper_wrongdir" })

rune.timer.every(60, function()
  if M.dirty then M.save() end
end, { name = "aard_map_save" })

-- Also saved before /reload and when the connection closes, so a change
-- inside the minute isn't lost
rune.hooks.on("reloading", function()
  if M.dirty then M.save() end
end, { name = "aard_map_save_reload" })
rune.hooks.on("disconnected", function()
  if M.dirty then M.save() end
end, { name = "aard_map_save_disconnect" })

-- Editing (nav/minimap.lua's map command: map unlink, map exit) ---------------

-- Remove exit `dir` from the room you're in. Returns a message, ok
function M.unlink(dir)
  local r = M.here and M.rooms[M.here]
  if not r or dir == "" or not r.exits[dir] then
    return "map unlink <exit>: no exit \"" .. dir .. "\" from this room on the map.", false
  end
  r.exits[dir] = nil
  M.dirty = true
  return "[map] removed exit " .. dir .. " from room " .. M.here .. " - walking it again lets GMCP add the real one.", true
end

-- Flag exit `dir` from the room you're in avoid (on) or not: routes
-- (nav/travel.lua) never take an avoided exit. To keep routes out of a
-- room, avoid the exits into it. Returns a message, ok
function M.avoid(dir, on)
  local r = M.here and M.rooms[M.here]
  local e = r and dir ~= "" and r.exits[dir]
  local cmd = on and "map avoid" or "map unavoid"
  if not e then
    return cmd .. " <exit>: no exit \"" .. dir .. "\" from this room on the map.", false
  end
  local flags = on and "2" or ""
  if e.flags == flags then
    return "[map] exit " .. dir .. " from room " .. M.here .. (on and " is avoided already." or " isn't avoided."), true
  end
  e.flags = flags
  M.dirty = true
  return "[map] exit " .. dir .. " from room " .. M.here .. (on and " avoided - routes won't take it." or " no longer avoided."), true
end

-- Exit `name` from room `from` to room `to`, taken by sending `cmds`
-- (";"-joined; "" or the same as the name means just the name). Replaces
-- an exit of the same name, keeping its flags (avoid) if it went to the
-- same room. Both rooms must be on the map. Returns a message, ok.
-- Used by map exit (below) and map apply (nav/maprec.lua)
function M.set_exit(from, name, to, cmds)
  local r = from and M.rooms[from]
  if not r then return "[map] room " .. tostring(from) .. " isn't on the map.", false end
  if not to or not M.rooms[to] then
    return "[map] room " .. tostring(to) .. " isn't on the map - visit it once first.", false
  end
  name = util.trim(name or ""):lower()
  if name == "" then return "[map] an exit needs a name.", false end
  cmds = util.trim(cmds or "")
  if cmds:lower() == name then cmds = "" end
  local old = r.exits[name]
  local flags = old and old.to == to and old.flags or ""
  r.exits[name] = { to = to, flags = flags, cmds = cmds }
  M.dirty = true
  return string.format("[map] exit \"%s\" from room %d to %d (%s)%s %s.", name, from, to,
    colors.strip(M.rooms[to].name), cmds ~= "" and (" sends " .. cmds) or "",
    old and "replaced" or "added"), true
end

-- An exit from the room you're in that GMCP doesn't list - a custom exit
-- ("exits" shows them as Custom, with a Name), or one you only find by
-- trying. Taking it sends `cmd`. Replaces an exit of the same name
function M.add_exit(v, cmd)
  if not v or not M.here or not cmd or cmd == "" then
    return "map exit <vnum> <command> - stand in the room the exit leaves from.", false
  end
  return M.set_exit(M.here, cmd, v, "")
end

rune.alias.exact("mapsave", function()
  if M.save() then util.say("[map] saved, " .. M.count .. " rooms.") end
end)

-- Labels (nav/minimap.lua's map command: map label, unlabel, labels) ------
-- Rewritten whole at each change

local function save_labels()
  local names = {}
  for name in pairs(M.labels) do names[#names + 1] = name end
  table.sort(names)
  return util.write_file(DATA .. "/labels.lua", function(fh)
    fh:write("-- Room labels for ga / find: label -> vnums. Rewritten by map label / map unlabel.\nreturn {\n")
    for _, name in ipairs(names) do
      local v = M.labels[name]
      table.sort(v)
      fh:write(string.format("  [%q] = { %s },\n", name, table.concat(v, ", ")))
    end
    fh:write("}\n")
  end, "[map]")
end

-- The room you're in, or nil (and asked for) if GMCP hasn't said yet
local function here()
  if not M.here then
    util.warn("[map] the game hasn't reported your room yet - asking for it; try again in a moment.")
    rune.gmcp.send("request room")
  end
  return M.here
end

--   map label <word>    label the room you're in
function M.label(args)
  local name = util.trim(args):lower()
  if name == "" or name:find("%s") then util.warn("[map] map label <one word>"); return end
  local v = here()
  if not v then return end
  local list = M.labels[name] or {}
  for _, x in ipairs(list) do
    if x == v then util.say("[map] this room is already labelled " .. name .. "."); return end
  end
  list[#list + 1] = v
  M.labels[name] = list
  if save_labels() then util.say("[map] room " .. v .. " labelled " .. name .. ".") end
end

--   map unlabel <word>  remove a label from the room you're in
function M.unlabel(args)
  local name = util.trim(args):lower()
  if name == "" then util.warn("[map] map unlabel <label>"); return end
  local v = here()
  if not v then return end
  local list = M.labels[name] or {}
  for i, x in ipairs(list) do
    if x == v then
      table.remove(list, i)
      if #list == 0 then M.labels[name] = nil end
      if save_labels() then util.say("[map] removed label " .. name .. " from room " .. v .. ".") end
      return
    end
  end
  util.warn("[map] this room isn't labelled " .. name .. ".")
end

--   map labels          every label, its rooms and their areas
function M.list_labels()
  local names = {}
  for name in pairs(M.labels) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local where = {}
    for _, v in ipairs(M.labels[name]) do
      local r = M.rooms[v]
      where[#where + 1] = v .. (r and (" " .. r.name .. ", " .. M.area_label(r.area)) or "")
    end
    rune.echo(string.format("  %-14s %s", name, table.concat(where, "; ")))
  end
end

-- map renames (nav/minimap.lua's map command): the rooms map/mapnames.log
-- says the game names differently, where the map still has the name the
-- log saw (the latest line for a room wins) - so one renamed since, or
-- applied, drops out. Read only when asked. Returns { v, area, old, new }s, by vnum
local function renames()
  local fh = io.open(M.names_log, "r")
  if not fh then return {} end
  local by = {}
  for line in fh:lines() do
    local _, v, area, old, new = line:match("^([^\t]*)\t(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    v = tonumber(v)
    local r = v and M.rooms[v]
    if r and r.name == old and new ~= old then by[v] = { v = v, area = area, old = old, new = new } end
  end
  fh:close()
  local out = {}
  for _, e in pairs(by) do out[#out + 1] = e end
  table.sort(out, function(a, b) return a.v < b.v end)
  return out
end

-- A name quoted, so a trailing space shows
local function quoted(s) return "\"" .. s .. "\"" end

--   map renames                 list them
--   map renames apply <vnum>    take the game's name for that room
--   map renames apply all       for all of them
function M.renames(args)
  local list = renames()
  local what = util.trim(args)
  if what == "" then
    if not list[1] then util.say("[map] renames: none - the map matches every name logged."); return end
    util.say("[map] renames: " .. #list .. " room" .. (#list == 1 and "" or "s")
      .. " the game names differently - map renames apply <vnum|all>:")
    for _, e in ipairs(list) do
      rune.echo(string.format("  %-6d %-11s map %s  game %s", e.v, e.area, quoted(e.old), quoted(e.new)))
    end
    return
  end
  local which = what:match("^apply%s+(%S+)$")
  if not which then util.warn("[map] map renames [apply <vnum|all>]"); return end
  local n = 0
  for _, e in ipairs(list) do
    if which == "all" or tonumber(which) == e.v then
      M.rooms[e.v].name = e.new
      n = n + 1
    end
  end
  if n == 0 then util.warn("[map] renames: nothing to apply for " .. which .. " - map renames lists them."); return end
  M.dirty = true
  util.say("[map] renames: " .. n .. " room name" .. (n == 1 and "" or "s") .. " taken from the game - saved with the map.")
end

-- map info (nav/minimap.lua's map command): where you are on the map, and
-- the map's state
function M.info()
  local r = M.here and M.rooms[M.here]
  if not r then
    util.warn("[map] current room " .. tostring(M.here) .. " isn't on the map.")
  else
    local ex = {}
    for name, e in pairs(r.exits) do
      ex[#ex + 1] = name .. "->" .. e.to .. (e.cmds ~= "" and (" [" .. e.cmds .. "]") or "")
        .. (e.flags == "2" and " (avoid)" or "")
    end
    table.sort(ex)
    util.say(string.format("[map] %d %s (%s, %s)%s%s",
      M.here, r.name, r.area, r.terrain,
      r.data ~= "" and (" data=" .. r.data) or "",
      r.note ~= "" and (" note: " .. r.note) or ""))
    rune.echo("      exits: " .. table.concat(ex, "  "))
  end
  rune.echo(string.format("      %d rooms, %s", M.count,
    M.dirty and "unsaved changes" or "saved"))
end

M.load()

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("map info", "map info", "where you are on the map: room, area, exits, and the map's state")
help.add("map label", "map label <word>", "label this room, for find and ga")
help.add("map unlabel", "map unlabel <word>", "remove a label from this room")
help.add("map labels", "map labels", "every room label")
help.add("mapsave", "mapsave", "save the map now (it saves itself every 60 s and on disconnect)")

return M
