-- lua min_drive.lua ROOT [bench] > out: the minimap pane after each step of
-- one scenario (map blocks, room.info, runs, fights, darkness), and the
-- hidden commands sent. Old tree: modules.minimap draws; new: panes.minimap
-- LAYOUT(name): data/layout/<name> on this tree, else an older tree's panes/<name> (ui/layout for "screen")
LAYOUT = LAYOUT or function(n) local new = "data.layout." .. n; if package.searchpath(new, package.path) then return require(new) end return require(n == "screen" and "ui.layout" or "panes." .. n) end
local ROOT, MODE = arg[1], arg[2]
package.path = ROOT .. "/?.lua;" .. package.path
H = { handlers = {}, aliases = {}, after = {}, every = {}, trig = {}, tags = {}, now = 1000000, sess = {}, sent = {} }
os.time = function() return H.now end
local function stub(name)
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == "number" then return nil end
      local v = stub(name .. "." .. tostring(k)); rawset(t, k, v); return v
    end,
    __call = function() return stub(name .. "()") end,
  })
end
rune = stub("rune")
rune.config_dir = ROOT
rune.echo = function() end
rune.send_raw = function(c) H.sent[#H.sent + 1] = c end
rune.session = { get = function(k) return H.sess[k] end, set = function(k, v) H.sess[k] = v end }
rune.gmcp = { on = function(pkg, fn) H.handlers[pkg] = H.handlers[pkg] or {}; table.insert(H.handlers[pkg], fn); return stub("g") end,
              send = function() end, subscribe = function() end }
local function trig(kind)
  return function(pat, fn, opts)
    local t = { kind = kind, pat = pat, fn = fn, on = true }
    H.trig[#H.trig + 1] = t
    return { disable = function() t.on = false end, enable = function() t.on = true end, remove = function() t.on = false end }
  end
end
rune.trigger = { regex = trig("regex"), starts = trig("starts"), exact = trig("exact"), contains = trig("contains"),
                 ends = trig("ends"), list = function() return {} end }
rune.alias = { exact = function(n, fn) H.aliases[n] = fn; return stub("alias") end,
               regex = function() return stub("alias") end, starts = function() return stub("alias") end }
rune.ui = stub("ui")
rune.ui.bar = function() end
rune.ui.refresh_bars = function() end
rune.store = { get = function() return nil end, set = function() end, delete = function() end }
rune._state = { scroll_mode = "live" }
rune.timer = {
  after = function(secs, fn)
    local t = { at = H.now + secs, fn = fn }
    H.after[#H.after + 1] = t
    return { cancel = function() t.dead = true end }
  end,
  every = function(secs, fn) H.every[#H.every + 1] = fn; return stub("timer") end,
}
H.panes = {}
rune.pane = { replace = function(n, text) H.panes[n] = text end }

rune.hooks = { on = function() return stub("hook") end }
package.loaded["modules.mapper"] = { rooms = {} }
package.loaded["modules.maprec"] = { subs = {} }
local layout = LAYOUT("screen")
rune._state.width = 44 + layout.RIGHT_W + 1; rune._state.height = 50
local util = require("lib.util")
util.say, util.warn, util.err = function() end, function() end, function() end
require("modules.game")
local NEW = io.open(ROOT .. "/data/layout/minimap.lua") ~= nil or io.open(ROOT .. "/panes/minimap.lua") ~= nil
if NEW then LAYOUT("minimap") else require("modules.minimap") end
local SCR = package.loaded["ui.screen"]
local mapper = package.loaded["modules.mapper"]

local function feed(pkg, d) for _, fn in ipairs(H.handlers[pkg] or {}) do fn(d) end end
local E = "\27["
local function strip(s) return (s:gsub("\27%[[%d;]*m", "")) end
local function L(s) return { clean = function() return strip(s) end, raw = function() return s end } end
local function line(s)
  for _, t in ipairs(H.trig) do
    if t.on and t.kind == "regex" and t.pat:match("darkness") and strip(s):match("^You see nothing but darkness") then t.fn({}, { line = L(s) }) end
  end
end
local function block(rows)
  local ls = { L("<MAPSTART>") }
  for _, r in ipairs(rows) do ls[#ls + 1] = L(r) end
  ls[#ls + 1] = L("<MAPEND>")
  for _, t in ipairs(H.trig) do
    if t.kind == "exact" and t.pat == "<MAPSTART>" then t.fn(nil, { line = ls[1], lines = ls }) end
  end
end
local function room(num, zone) feed("room.info", { num = num, zone = zone, name = "x" }) end
local function state(s) feed("char.status", { state = tostring(s) }) end
local function draw() if SCR then SCR.pass() end end
local step = 0
local function snap(label)
  draw()
  step = step + 1
  io.stdout:write("@@ " .. step .. " " .. label .. "  sent: " .. table.concat(H.sent, ";") .. "\n"
    .. (H.panes.minimap or "") .. "\n")
  H.sent = {}
end

local function map(name, me_row, extra)
  local rows = { "", E .. "1;36m" .. name, "" }
  for r = 1, 9 do
    local s = E .. "0;32m" .. string.rep(".", 3) .. E .. "0;37m-" .. E .. "1;33m[" .. E .. "0;37m"
    if r == me_row then s = s .. E .. "1;35m#" else s = s .. E .. "0;37m " end
    s = s .. E .. "1;33m]" .. E .. "0;37m-"
    if r == 3 then s = s .. E .. "1;31m*" .. E .. "0;37m" end
    if r == 5 then s = s .. "<>" .. string.rep("~", 30) end
    rows[#rows + 1] = s
  end
  for _, x in ipairs(extra or {}) do rows[#rows + 1] = x end
  rows[#rows + 1] = ""
  rows[#rows + 1] = E .. "0;37m[ Exits: north east " .. E .. "1;32mdown" .. E .. "0;37m ]"
  rows[#rows + 1] = ""
  return rows
end

snap("empty")
feed("char.base", { name = "Seth", subclass = "Shaman" })
state(3)
snap("login")
room(1001, "aylor"); snap("room.info first")
block(map("The Grand City of Aylor", 5)); snap("block")
room(1002, "aylor"); block(map("A Busy Street", 4)); snap("step: info then block")
block(map("Another Street", 6)); room(1003, "aylor"); snap("step: block then info")
mapper.rooms[1003] = { note = "a note that is long enough to wrap onto a second line and a third one too" }
room(1003, "aylor"); snap("look same room (kept)")
block(map("Another Street", 6)); snap("block same room: note shows")
state(12); room(1004, "aylor"); snap("running")
room(1005, "aylor"); snap("running 2")
state(3); block(map("Arrival", 5)); room(1006, "aylor"); snap("arrived")
line("You see nothing but darkness..."); snap("darkness")
room(1007, "aylor"); snap("room.info in the dark")
block(map("Lit Room", 5)); snap("block: lit")
state(12); room(1008, "midgaard"); snap("run 2")
state(8); snap("fight breaks the run")
room(1008, "midgaard"); snap("look mid-fight")
state(3); snap("fight over: map asked")
block(map("After the fight", 5)); snap("map block")
feed("room.wrongdir", {}); snap("wrongdir, nothing stale")
local long = { E .. "1;36mA Room With A Name So Long", "That It Wraps", "" }
for r = 1, 26 do long[#long + 1] = E .. "0;37m" .. string.rep("-", r % 40) .. (r == 7 and E .. "1;35m#" or "") end
room(1009, "big"); block(long); snap("no exits, long map")
local ex = map("Tall Map", 5, {})
for r = 1, 12 do table.insert(ex, 6, E .. "0;34m" .. r .. string.rep("=", 35)) end
room(1010, "tall"); block(ex); snap("tall map with exits")
room(-1, "maze"); block(map("Maze", 5)); snap("maze -1")
-- live 2026-11-16 (minimap-a.log): 10s with one room south, then a wall
state(3); room(1300, "aylor"); block(map("Start", 5)); snap("start room")
room(1301, "aylor"); snap("south: room.info at 3, no block")
state(12); feed("room.wrongdir", {}); feed("room.wrongdir", {}); feed("room.wrongdir", {}); snap("state 12, three wrongdirs")
room(1301, "aylor"); snap("same room.info again at 12: map asked")
state(3); snap("state 3")
block(map("Cavern", 5)); snap("its map block")
if arg[2] ~= "bench" then return end

local A, B = map("Street One", 5), map("Street Two", 6)
local N = 20000
local t = os.clock()
for k = 1, N do room(2000 + k % 2, "aylor"); block(k % 2 == 0 and A or B); draw() end
local step = (os.clock() - t) / N * 1e6
t = os.clock()
for k = 1, N do block(k % 2 == 0 and A or B); room(3000 + k % 2, "aylor"); draw() end
local step2 = (os.clock() - t) / N * 1e6
t = os.clock()
for k = 1, N do room(3001, "aylor"); draw() end
local look = (os.clock() - t) / N * 1e6
state(12)
t = os.clock()
for k = 1, N do room(4000 + k, "aylor"); draw() end
local run = (os.clock() - t) / N * 1e6
print(string.format("step, room.info then block: %6.2f us", step))
print(string.format("step, block then room.info: %6.2f us", step2))
print(string.format("look, same room: %6.2f us", look))
print(string.format("running room: %6.2f us", run))
