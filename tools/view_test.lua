-- Plain-Lua tests for ui/view.lua (the data: provides, set, touch, emit,
-- publish, subscribe), Rune stubbed. The display (ui/screen.lua) is checked
-- by the drives in tools/bench.
-- Run from the config folder:  lua tools/view_test.lua
package.path = "./?.lua;" .. package.path

local refreshes, warned = 0, {}
rune = { ui = { refresh_bars = function() refreshes = refreshes + 1 end } }
package.preload["lib.util"] = function()
  return { warn = function(s) warned[#warned + 1] = s end }
end
package.preload["lib.debug"] = function()
  return { topic = function() return { on = false, log = function() end } end }
end

local view = require("ui.view")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then passed = passed + 1
  else failed = failed + 1; print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "")) end
end
local function eq(name, got, want) check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function errs(name, fn, pattern)
  local ok, err = pcall(fn)
  check(name, not ok and tostring(err):find(pattern, 1, true) ~= nil, ok and "no error" or err)
end

-- the hooks ui/screen.lua sets: what each was told
local changes, publishes, emits, provides = {}, 0, {}, 0
view._on_change = function(name) changes[#changes + 1] = name end
view._on_publish = function() publishes = publishes + 1 end
view._on_emit = function(name, ev) emits[#emits + 1] = name .. ":" .. tostring(ev) end
view._on_provide = function() provides = provides + 1 end
local function told() local s = table.concat(changes, ","); changes = {}; return s end

-- Declaring ------------------------------------------------------------------
local held = { cur = 1, max = 2 }
local V = view.provides("t.vitals", "test vitals", {
  hp     = { "ratio", "hit points", standard = true },
  name   = { "text", "your name" },
  tick   = { "timestamp", "next tick" },
  dps    = { "number", "damage a second", get = function() return held.cur end },
  line   = { "stream", "chat lines" },
})
eq("provide hook told", provides, 1)
local d = view.data("hp")
eq("catalog: shape", d.shape, "ratio")
eq("catalog: module", d.module, "t.vitals")
check("catalog: standard", d.standard == true)
eq("modules: names sorted", table.concat(view.modules()["t.vitals"].names, ","), "dps,hp,line,name,tick")
errs("duplicate provider", function() view.provides("t.other", "", { hp = { "ratio" } }) end,
  "hp is provided by both t.vitals and t.other")
errs("unknown shape", function() view.provides("t.bad", "", { x = { "blob" } }) end, "unknown shape \"blob\"")
errs("a module twice", function() view.provides("t.vitals", "", {}) end, "already provides")
errs("set what another module provides", function()
  local O = view.provides("t.o", "", { o = { "number" } }); O.set("hp", 1) end, "t.o doesn't provide hp")
errs("set a getter's data", function() V.set("dps", 3) end, "has a getter")
errs("touch plain data", function() V.touch("name") end, "no getter data name")
errs("toucher of plain data", function() V.toucher("name") end, "no getter data name")
changes = {}

-- Setting ---------------------------------------------------------------------
V.set("name", "Aberrant")
eq("set: stored", view.get("name"), "Aberrant")
eq("set: change told", told(), "name")
V.set("name", "Aberrant")
eq("same value: nothing told", told(), "")
V.set("hp", { cur = 50, max = 200 })
V.set("hp", { cur = 50, max = 200 })
eq("a new ratio table, same cur and max: told once", told(), "hp")
local set_tick = V.setter("tick")
set_tick(1030)
eq("setter: stored", view.get("tick"), 1030)
eq("setter: told", told(), "tick")
errs("setter of what isn't provided", function() V.setter("nope") end, "doesn't provide nope")

-- Getters and touch -----------------------------------------------------------
eq("getter read", view.get("dps"), 1)
held.cur = 9
eq("getter read again: the live value", view.get("dps"), 9)
V.touch("dps")
local touch = V.toucher("dps")
touch(); touch()
eq("touch and toucher tell each time", told(), "dps,dps,dps")

-- Streams -----------------------------------------------------------------------
V.emit("line", "hello")
eq("emit: to the hook", emits[1], "line:hello")
eq("emit: no change told", told(), "")
eq("emit: nothing stored", view.get("line"), nil)

-- Publish and subscribe -----------------------------------------------------------
local got = {}
view.subscribe("name", function(n, v) got[#got + 1] = n .. "=" .. v end)
publishes = 0
V.set("name", "Z"); V.set("name", "Q")
V.publish()
eq("publish hook told", publishes, 1)
eq("subscriber once per publish", #got, 1)
eq("subscriber sees the value", got[1], "name=Q")
V.publish()
eq("nothing pending: no call", #got, 1)
V.set("hp", { cur = 1, max = 2 }); V.publish()
eq("no subscriber of it: no call", #got, 1)
local C = view.provides("t.loop", "", { loop = { "number" } })
local loops = 0
view.subscribe("loop", function() loops = loops + 1; C.set("loop", loops); C.publish() end)
C.set("loop", 0); C.publish()
check("cascade cut", loops <= 4, loops)
local B = view.provides("t.boom", "", { boom = { "number" } })
view.subscribe("boom", function() error("bang") end)
warned = {}
B.set("boom", 1); B.publish()
check("a failing subscriber warns, publish goes on", warned[1] and warned[1]:find("subscriber of boom", 1, true), warned[1])

-- Dev mode shape check, unprovide -------------------------------------------------
view.dev = true
warned = {}
V.set("hp", "lots")
check("dev mode warns on a wrong shape", warned[1] and warned[1]:find("not a ratio", 1, true), warned[1])
warned = {}
set_tick("soon")
check("a child shape checked by its parent's check", warned[1] and warned[1]:find("not a timestamp", 1, true), warned[1])
view.dev = false
refreshes = 0
view.unprovide("t.boom")
eq("unprovided: gone from the catalog", view.data("boom"), nil)
eq("unprovided: no value", view.get("boom"), nil)
eq("unprovided: a pass asked", refreshes, 1)
local B2 = view.provides("t.boom", "", { boom = { "number" } })
B2.set("boom", 2)
eq("provided again", view.get("boom"), 2)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
