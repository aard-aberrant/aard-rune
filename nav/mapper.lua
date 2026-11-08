-- Mapper core (phase 2): the Aardwolf room map in Lua.
-- require("nav.mapper") returns it; travel and minimap use it.
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
-- disconnect, and by "mapsave".
-- Always on - tt++'s $mapping switch was never used by hand, so it's gone.

local util = require("core.util")

local M = {}

M.file = rune.config_dir .. "/map/aard.map"
M.rooms = {}        -- vnum -> { area, terrain, data, note, name, exits = { [exit] = { to, flags, cmds } } }
M.count = 0
M.here = nil        -- current vnum
M.dirty = false

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

-- Written to a .tmp file first, then renamed over the map, so a failed
-- write never leaves half a map
function M.save()
  local tmp = M.file .. ".tmp"
  local fh, err = io.open(tmp, "w")
  if not fh then
    util.err("[map] can't write " .. tmp .. ": " .. tostring(err))
    return false
  end
  local vnums = {}
  for v in pairs(M.rooms) do vnums[#vnums + 1] = v end
  table.sort(vnums)
  for _, v in ipairs(vnums) do
    local r = M.rooms[v]
    fh:write(table.concat({ "R", v, clean(r.area), clean(r.terrain), clean(r.data),
                            clean(r.note), clean(r.name) }, "\t"), "\n")
    for name, e in pairs(r.exits) do
      fh:write(table.concat({ "X", v, e.to, clean(name), clean(e.flags), clean(e.cmds) }, "\t"), "\n")
    end
  end
  fh:close()
  local ok, rerr = os.rename(tmp, M.file)
  if not ok then
    util.err("[map] can't replace " .. M.file .. ": " .. tostring(rerr))
    return false
  end
  M.dirty = false
  return true
end

local function placeholder(v)
  local r = { area = "", terrain = "", data = "", note = "", name = "", exits = {} }
  M.rooms[v] = r
  M.count = M.count + 1
  M.dirty = true
  return r
end

function M.room_info(d)
  local v = tonumber(d.num)
  if not v or v == -1 then return end
  M.here = v
  local r = M.rooms[v] or placeholder(v)
  if r.name == "" then
    r.name, r.area, r.terrain = clean(d.name), clean(d.zone), clean(d.terrain)
    M.dirty = true
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
  if dbg.on then dbg.log(tostring(d.num) .. " " .. tostring(d.zone) .. " " .. util.strip(tostring(d.name))) end
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
    util.strip(M.rooms[to].name), cmds ~= "" and (" sends " .. cmds) or "",
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

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("map info", "map info", "where you are on the map: room, area, exits, and the map's state")
help.add("mapsave", "mapsave", "save the map now (it saves itself every 60 s and on disconnect)")

return M
