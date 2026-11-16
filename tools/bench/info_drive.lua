-- lua info_drive.lua ROOT old|new > out: the info pane after each step of
-- one scenario (real inputs: GMCP, commands, timers)
local ROOT, MODE = arg[1], arg[2]
package.path = ROOT .. "/?.lua;" .. package.path
H = { handlers = {}, aliases = {}, timers = {}, now = 1000000, sess = {}, panes = {} }
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
rune.session = { get = function(k) return H.sess[k] end, set = function(k, v) H.sess[k] = v end }
rune.gmcp = { on = function(pkg, fn) H.handlers[pkg] = H.handlers[pkg] or {}; table.insert(H.handlers[pkg], fn); return stub("g") end,
              send = function() end, subscribe = function() end }
local function trig() return function() return stub("trigger") end end
rune.trigger = { regex = trig(), starts = trig(), exact = trig(), contains = trig(), ends = trig(), list = function() return {} end }
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
    H.timers[#H.timers + 1] = t
    return { cancel = function() t.dead = true end }
  end,
  every = function() return stub("timer") end,
}
rune.pane = { replace = function(n, text) H.panes[n] = text end }
io.write = function() end   -- the beep
local layout = require("ui.layout")
rune._state.width = 44 + layout.RIGHT_W + 1
local util = require("lib.util")
util.say, util.warn, util.err = function() end, function() end, function() end

require("modules.game")
local info = require("panes.info")
require("modules.quest")
local alert
if MODE == "new" then
  require("modules.alerts"); require("modules.account"); require("modules.infomsg")
  alert = require("modules.alerts").alert
else
  alert = info.alert
end
local view = MODE == "new" and require("ui.view")

local function flush()   -- the display pass: ui/screen.lua's, or an older tree's view.flush
  local scr = package.loaded["ui.screen"]
  if scr then scr.pass() elseif view and view.flush then view.flush() end
end
local function run_timers()
  local again = true
  while again do
    again = false
    for k, t in ipairs(H.timers) do
      if not t.dead and t.at <= H.now then t.dead = true; again = true; t.fn(); break end
    end
  end
end
local function advance(n)
  for _ = 1, n do H.now = H.now + 1; run_timers(); flush() end
end
local step = 0
local function snap(label)
  flush()
  step = step + 1
  io.stdout:write("@@ " .. step .. " " .. label .. "\n" .. (H.panes.info or "") .. "\n")
end
local function feed(pkg, d) for _, fn in ipairs(H.handlers[pkg] or {}) do fn(d) end end
local function cmd(name, args) H.aliases[name](args or "") end

snap("empty")
local game = require("modules.game")
feed("char.base", { name = "Seth", class = "Mage", subclass = "Necromancer", level = 201 })
feed("char.worth", { gold = 523, bank = 12000, qp = 1234567, tp = 12, trains = 3 })
snap("worth only")
feed("char.stats", { hr = 1500, dr = 2100, str = 500, wis = 700, con = 590, dex = 650, luck = 300, int = 100 })
snap("stats low hr, low stats")
feed("char.worth", { gold = 2500000, bank = 999999999, qp = 5, tp = 0 })
snap("big gold, no trains")
feed("char.stats", { hr = 1700, dr = 1900, str = 700, wis = 700, con = 700, dex = 700, luck = 700 })
snap("low dr only")

feed("comm.quest", { action = "start", targ = "a rogue", room = "The Hall", area = "The Amazon Nation", timer = 7 })
snap("quest 7m")
for _, s in ipairs({ 30, 30, 60, 60, 59, 1, 60 }) do advance(s); snap("quest +" .. s) end
feed("comm.quest", { action = "killed" })
snap("quest killed")

cmd("infomsg", "hello|world||four|five")
snap("infomsg 5 lines")
cmd("infomsg", "a very long message line that is longer than forty four columns for sure|x")
snap("infomsg long")
cmd("infomsg", "-t 3 brief|")
snap("infomsg -t")
advance(3); snap("infomsg gone")

alert("warn", 3, "MOONS", "All three moons are up, for 4 ticks and a bit more so that it wraps across lines")
snap("warn"); advance(1); snap("warn +1"); advance(1); snap("warn +2")
alert("crit", 3, "TIMER", "tea")
snap("crit over warn")
for _ = 1, 4 do advance(1); snap("crit tick") end
advance(1); snap("after"); advance(2); snap("after2")

cmd("infopane", "acc")
snap("pin account")
alert("warn", 2, "2XP", "Double xp for 30 minutes")
snap("warn beats pin")
advance(3); snap("pin again")
cmd("infopane", "quest")
snap("pin quest")
cmd("infopane", "reset")
snap("reset")
feed("comm.quest", { action = "comp", qp = 30 })
snap("quest done")
feed("char.stats", { hr = 1700, dr = 2100, str = 700, wis = 700, con = 700, dex = 700, luck = 700 })
snap("all good")
