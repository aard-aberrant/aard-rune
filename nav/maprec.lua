-- map record: record what you do to get from one room to the next, then
-- write the exits it needs (require("nav.maprec"); the commands run from
-- nav/minimap.lua's map alias).
--   map record            start recording (on already: the plan so far)
--   map record stop       stop, and show the plan
--   map record cancel     stop, and throw the recording and plan away
--   map plan              show the plan: numbered changes to the map
--   map edit <n> <cmds>   change an entry's commands (";"-separated); the
--                         exit's name is the last one
--   map drop <n|all>      take an entry out of the plan
--   map apply [n ...]     write the plan (or those entries) to the map. An
--                         entry whose room already has other exits to the
--                         same place opens a picker: the exit you choose
--                         sends the commands, the others are removed (a
--                         plain direction is flagged avoid instead - GMCP
--                         would add it back)
--
-- While recording, rune.send_raw is wrapped: every line sent to the game
-- (typed, from an alias, or sent by a module - Rune's own rune.send and
-- the input line call rune.send_raw by name, lua/core/75_input.lua) is
-- kept with the room it was sent from. When GMCP room.info shows a new
-- room, the lines sent in the old one are one move, A -> B, checked
-- against A's exits on the map:
--   - one exit name the map already has going to B: a plain move, nothing
--   - more lines ending in such an exit ("open n", "n"): update that
--     exit to send them all
--   - no lines (a run's middle rooms, pushed, followed): nothing if the
--     map has an exit A -> B, else noted as a move with no command
--   - a run, home or recall: nothing (the route search has its own)
--   - anything else: a custom exit named after the last line, sending
--     all of them ("look field;enter field"); "replaces" if A has an exit
--     of that name going somewhere else
-- Bare "look", "l", "exits", "map", "scan" and blank lines are left out.
-- A line a module sent (a heal, a spell) or a chat can get in: the plan
-- shows every entry's commands, and map edit fixes them before map apply.
-- Rooms with vnum -1 and maze rooms (GMCP details "maze") never get
-- exits, as in nav/mapper.lua.
--
-- A /reload ends the recording and throws it and the plan away: the new
-- Lua state starts with Rune's own send_raw and without the room handler.
-- Cost: no triggers. Nothing at all while not recording; while recording,
-- one Lua call per line sent and one per GMCP room.info.

local util = require("core.util")
local mapper = require("nav.mapper")

local R = {}

local say, warn, trim = util.say, util.warn, util.trim
local dbg = require("core.debug").topic("maprec", "map record: each line recorded and each move")

local IGNORE = { [""] = true, look = true, l = true, exits = true, map = true, scan = true }
local DIRS = { north = "n", south = "s", east = "e", west = "w", up = "u", down = "d" }
local DIRSET = { n = true, s = true, e = true, w = true, u = true, d = true }
local NOROUTE = { home = true, recall = true }

-- The recording: on, the room you're in, the lines sent there since you
-- came in, the plan ({ from, to, name, cmds }) and moves with no command
local S = { on = false, room = nil, lines = {}, plan = {}, notes = {} }

local function room_label(v)
  local r = mapper.rooms[v]
  local name = r and util.strip(r.name or "") or ""
  return tostring(v) .. (name ~= "" and (" " .. name) or "")
end

local function exit_name(cmd)
  local c = trim(cmd):lower()
  return DIRS[c] or c
end

local function split(s)
  local out = {}
  for raw in (s .. ";"):gmatch("([^;]*);") do
    local c = trim(raw)
    if c ~= "" then out[#out + 1] = c end
  end
  return out
end

-- The map has some exit from room a to room b
local function has_way(a, b)
  for _, e in pairs(mapper.rooms[a].exits) do
    if e.to == b then return true end
  end
  return false
end

-- An entry, or the same exit's entry replaced (walked twice)
local function plan_add(entry)
  for i, p in ipairs(S.plan) do
    if p.from == entry.from and p.name == entry.name then
      S.plan[i] = entry
      return
    end
  end
  S.plan[#S.plan + 1] = entry
end

-- One move: the lines sent in room a, then room b
local function move(a, b, lines)
  local r = mapper.rooms[a]
  if not r or not mapper.rooms[b] then return end
  if dbg.on then dbg.log(string.format("move %d -> %d: %s", a, b, table.concat(lines, ";"))) end
  if #lines == 0 then
    if not has_way(a, b) then
      S.notes[#S.notes + 1] = string.format("%s -> %s with no command", room_label(a), room_label(b))
    end
    return
  end
  local last = exit_name(lines[#lines])
  if NOROUTE[last] then return end
  if last:match("^run ") and has_way(a, b) then return end
  local cmds = table.concat(lines, ";")
  local e = r.exits[last]
  if e and e.to == b then
    if #lines == 1 then return end
    if e.cmds:lower() == cmds:lower() then return end
  end
  plan_add({ from = a, to = b, name = last, cmds = cmds })
end

-- The wrapper on rune.send_raw ------------------------------------------

local orig_send = nil

local function record(text)
  if text:find("[\r\n]") then return end   -- send_raw calls itself for each line
  local c = trim(text)
  if IGNORE[c:lower()] then return end
  if dbg.on then dbg.log("sent in " .. tostring(S.room) .. ": " .. c) end
  S.lines[#S.lines + 1] = c
end

local function room_info(d)
  if not S.on or type(d) ~= "table" then return end
  local v = tonumber(d.num)
  if not v or v == -1 or v == S.room then return end
  local a, lines = S.room, S.lines
  S.room, S.lines = v, {}
  if tostring(d.details or ""):find("maze", 1, true) then return end
  if a then move(a, v, lines) end
end

local function hook(on)
  if on and not orig_send then
    orig_send = rune.send_raw
    rune.send_raw = function(text)
      if type(text) == "string" then record(text) end
      return orig_send(text)
    end
    -- after the mapper's (priority 50), so room b is on the map already
    rune.gmcp.on("room.info", room_info, { name = "maprec_room", priority = 60 })
  elseif not on and orig_send then
    rune.send_raw = orig_send
    orig_send = nil
    rune.gmcp.remove("maprec_room")
  end
end

-- The plan ----------------------------------------------------------------

-- The other exits from p.from that also go to p.to, sorted
local function others(p)
  local out = {}
  local r = mapper.rooms[p.from]
  if not r then return out end
  for name, e in pairs(r.exits) do
    if e.to == p.to and name ~= p.name then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local function show_plan()
  if #S.plan == 0 and #S.notes == 0 then
    say("[map] the plan is empty.")
    return
  end
  if #S.plan > 0 then say("[map] plan - map apply writes it, map edit / map drop change it:") end
  for i, p in ipairs(S.plan) do
    local r = mapper.rooms[p.from]
    local e = r and r.exits[p.name]
    local kind = not e and "add" or e.to == p.to and "update" or ("replace (was -> " .. e.to .. ")")
    rune.echo(string.format("  %2d  %s  %s -> %s  exit \"%s\"%s", i, kind, room_label(p.from),
      room_label(p.to), p.name, p.cmds:lower() ~= p.name and ("  sends " .. p.cmds) or ""))
    local o = others(p)
    if #o > 0 then
      rune.echo("        also there from here: " .. table.concat(o, ", ") .. " - map apply asks which one to keep")
    end
  end
  for _, n in ipairs(S.notes) do rune.echo("      not planned: " .. n) end
end

-- The entry numbers in `rest`, highest first (so removing goes from the end)
local function numbers(rest)
  local out, seen = {}, {}
  for n in rest:gmatch("%S+") do
    local i = tonumber(n)
    if not i or not S.plan[i] then return nil, n end
    if not seen[i] then seen[i] = true; out[#out + 1] = i end
  end
  table.sort(out, function(x, y) return x > y end)
  return out
end

local cmd = {}

function cmd.record(rest)
  if rest == "stop" then
    if not S.on then return warn("[map] not recording.") end
    S.on = false
    hook(false)
    say("[map] recording stopped.")
    return show_plan()
  elseif rest == "cancel" then
    S.on = false
    hook(false)
    S.plan, S.notes, S.lines = {}, {}, {}
    return say("[map] recording and plan thrown away.")
  elseif rest ~= "" then
    return warn("map record [stop|cancel]")
  end
  if S.on then
    say(string.format("[map] recording, in %s, %d line(s) sent here.", room_label(S.room), #S.lines))
    return show_plan()
  end
  if not mapper.here then return warn("[map] where you are isn't known yet - move once first.") end
  S.on, S.room, S.lines, S.notes = true, mapper.here, {}, {}
  hook(true)
  say("[map] recording from " .. room_label(S.room) .. ".")
end

function cmd.plan() show_plan() end

function cmd.edit(rest)
  local n, cmds = rest:match("^(%d+)%s+(.+)$")
  local p = S.plan[tonumber(n or "")]
  if not p then return warn("map edit <n> <cmds> - n from map plan, cmds \";\"-separated") end
  local list = split(cmds)
  if #list == 0 then return warn("map edit: no commands.") end
  p.cmds, p.name = table.concat(list, ";"), exit_name(list[#list])
  show_plan()
end

function cmd.drop(rest)
  if rest == "all" then
    S.plan, S.notes = {}, {}
    return say("[map] plan emptied.")
  end
  local list, bad = numbers(rest)
  if not list or #list == 0 then return warn("map drop <n ...|all> - no entry " .. tostring(bad or "")) end
  for _, i in ipairs(list) do table.remove(S.plan, i) end
  show_plan()
end

local function remove_entry(p)
  for i, q in ipairs(S.plan) do
    if q == p then table.remove(S.plan, i); return end
  end
end

-- Write entry p as exit `keep`. Every other exit from that room to the
-- same place goes - except a plain direction, which GMCP lists and the
-- mapper would add again at your next visit: that one is flagged avoid (2)
-- so routes don't take it
local function write(p, keep)
  local msg, ok = mapper.set_exit(p.from, keep, p.to, p.cmds)
  if ok then say(msg) else return warn(msg) end
  local r = mapper.rooms[p.from]
  for name, e in pairs(r.exits) do
    if e.to == p.to and name ~= keep then
      if DIRSET[name] then
        e.flags = "2"
        say(string.format("[map] exit \"%s\" from room %d flagged avoid.", name, p.from))
      else
        r.exits[name] = nil
        say(string.format("[map] exit \"%s\" from room %d removed.", name, p.from))
      end
    end
  end
  mapper.dirty = true
  remove_entry(p)
end

-- Entries whose room already reaches the same place another way, one
-- picker each, in turn. Escape closes a picker without on_select (Rune's
-- picker has no cancel callback): that entry and the ones after it stay
-- in the plan
local function ask(queue, i)
  local p = queue[i]
  if not p then
    if #S.plan > 0 then show_plan() end
    return
  end
  local r = mapper.rooms[p.from]
  local items = { { text = p.name, value = p.name,
                    desc = (r.exits[p.name] and "update" or "new") .. ", sends " .. p.cmds } }
  for _, name in ipairs(others(p)) do
    local e = r.exits[name]
    items[#items + 1] = { text = name, value = name,
      desc = "keep this one, sending " .. p.cmds .. (e.cmds ~= "" and (" (now " .. e.cmds .. ")") or "") }
  end
  rune.ui.picker.show({
    title = string.format("%s -> %s: which exit?", room_label(p.from), room_label(p.to)),
    items = items,
    match_description = true,
    on_select = function(name)
      write(p, name)
      ask(queue, i + 1)
    end,
  })
end

function cmd.apply(rest)
  if #S.plan == 0 then return warn("[map] nothing to apply.") end
  local list, bad
  if rest == "" then
    list = {}
    for i = 1, #S.plan do list[#list + 1] = i end
  else
    list, bad = numbers(rest)
    if not list then return warn("map apply [n ...] - no entry " .. bad) end
  end
  table.sort(list)
  local entries, queue = {}, {}
  for _, i in ipairs(list) do entries[#entries + 1] = S.plan[i] end
  for _, p in ipairs(entries) do
    if not mapper.rooms[p.from] or not mapper.rooms[p.to] or #others(p) == 0 then
      write(p, p.name)
    else
      queue[#queue + 1] = p
    end
  end
  ask(queue, 1)
end

R.subs = { record = true, plan = true, edit = true, drop = true, apply = true }

function R.command(sub, rest)
  cmd[sub](trim(rest or ""))
end

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("map record", "map record [stop|cancel]", "record what you do to get past rooms; stop shows the exits it would write")
help.add("map plan", "map plan", "the exits map record would write")
help.add("map edit", "map edit <n> <cmds>", "change a planned exit's commands (\";\"-separated, the last one names it)")
help.add("map drop", "map drop <n ...|all>", "take entries out of the plan")
help.add("map apply", "map apply [n ...]", "write the plan (or those entries) to the map")

return R
