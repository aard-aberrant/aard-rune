-- Plain-Lua tests for core/view.lua (the display engine), Rune stubbed.
-- Run from the config folder:  lua tools/view_test.lua
package.path = "./?.lua;" .. package.path

local panes_written, refreshes, warned, bars_reg = {}, 0, {}, {}
rune = {
  ui = {
    refresh_bars = function() refreshes = refreshes + 1 end,
    bar = function(name, fn) bars_reg[name] = fn end,
  },
}
package.preload["core.util"] = function()
  return {
    pane = function(name, text) panes_written[#panes_written + 1] = { name, text } end,
    warn = function(s) warned[#warned + 1] = s end,
  }
end
package.preload["core.theme"] = function()
  local c = require("core.colors")
  return { red = c.red, yellow = c.yellow, green = c.green, bold = c.bold, cyan = c.cyan }
end
package.preload["core.debug"] = function()
  return { topic = function() return { on = false, log = function() end } end }
end

local view = require("core.view")
local colors = require("core.colors")
local w, h = view.widgets, view.helpers

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
local plain = colors.strip

local now = 1000
view.clock = function() return now end

-- Shapes and data -----------------------------------------------------------
local V = view.provides("t.vitals", "test vitals", {
  hp   = { "ratio", "hit points", standard = true },
  mana = { "ratio", "mana" },
  name = { "text", "your name" },
  tick = { "timestamp", "next tick", time = true },
  spells = { "list", "spells" },
})
V.set("hp", { cur = 50, max = 200 })
V.set("mana", { cur = 90, max = 100 })
V.set("name", "Aberrant")
V.set("tick", 1030)

eq("ratio pct", view.value(view.ref("hp").pct), 25)
eq("ratio frac", view.value(view.ref("hp.frac")), "50/200")
eq("ratio cur via string", view.value(view.ref("hp.cur")), 50)
eq("timestamp left", view.value(view.ref("tick.left")), 30)
eq("seconds min from timestamp left", view.value(view.ref("tick.left.min")), 1)
check("tick.left follows the clock", view.follows_clock(view.ref("tick.left")))
check("hp.pct doesn't", not view.follows_clock(view.ref("hp.pct")))
errs("unknown field lists the valid ones", function() return view.ref("hp").percent end, "it has cur, frac, max, pct")
errs("unknown data", function() return view.ref("nope") end, "no data named \"nope\"")
errs("duplicate provider", function() view.provides("t.other", "", { hp = { "ratio" } }) end,
  "hp is provided by both t.vitals and t.other")
errs("unknown shape", function() view.provides("t.bad", "", { x = { "blob" } }) end, "unknown shape \"blob\"")
errs("set what another module provides", function()
  local O = view.provides("t.o", "", { o = { "number" } }); O.set("hp", 1) end, "t.o doesn't provide hp")

-- Helpers ------------------------------------------------------------------
eq("pct helper", view.value(h.pct(view.ref("hp.cur"), view.ref("hp.max"))), 25)
eq("sum helper", view.value(h.sum(view.ref("hp.cur"), 5)), 55)
eq("round helper", view.value(h.round(h.pct(1, 3), 1)), 33.3)
errs("pct on text", function() h.pct(view.ref("name"), 1) end, "pct: argument 1 (name) is a text, needs a number")

-- rag and its forms ----------------------------------------------------------
view.styles({ ["rag.red"] = "red", ["rag.amber"] = "yellow", ["rag.green"] = "green" })
local health = w.rag(20, 60)
local a = health(view.ref("hp"))            -- ratio -> 25 -> amber
local b = health(view.ref("hp.cur"), view.ref("hp.max"))
local c = health(view.ref("hp.pct"))
local d = health(40)
eq("rag on ratio", view.draw(a), colors.yellow("25"))
eq("rag on cur, max", view.draw(b), colors.yellow("25"))
eq("rag on pct", view.draw(c), colors.yellow("25"))
eq("rag on a literal", view.draw(d), colors.yellow("40"))
eq("rag green", view.draw(health(view.ref("mana"))), colors.green("90"))
eq("rag one threshold", view.draw(w.rag(10)(5)), colors.red("5"))
errs("rag on a list", function() health(view.ref("spells")) end, "rag can't take spells (list)")
errs("rag on text", function() health(view.ref("name")) end, "it takes: number | ratio | number, number")
errs("rag needs a number", function() w.rag("x") end, "rag: the first threshold must be a number")

-- Styles -------------------------------------------------------------------
view.styles({ s1 = "red", s2 = { "bold", "red" }, s3 = { { below = 20, "red" }, { below = 60, "yellow" }, "green" } })
eq("style fixed", view.style("s1", "x"), colors.red("x"))
eq("style mixed", view.style("s2", "x"), colors.bold.on .. colors.red.on .. "x" .. colors.RESET)
eq("style rule low", view.style("s3", "x", 10), colors.red("x"))
eq("style rule mid", view.style("s3", "x", 30), colors.yellow("x"))
eq("style rule fallback", view.style("s3", "x", 90), colors.green("x"))
eq("no such style: unstyled", view.style("nope", "x"), "x")
view.add_styles({ s4 = "plain", s5 = { { below = 60, "plain" }, "green" } })
eq("plain: no codes", view.style("s4", "x"), "x")
eq("plain rule", view.style("s5", "x", 10), "x")
eq("plain rule fallback", view.style("s5", "x", 90), colors.green("x"))
eq("rag with no styles set: unstyled", view.draw(w.rag(20)(5)), "5")

-- text templates -----------------------------------------------------------
local t1 = w.text("HP {hp.pct|num:1} of {hp.max|commas} ({name})")
eq("text template", view.draw(t1), "HP 25 of 200 (Aberrant)")
eq("text filters", view.draw(w.text("[{name|pad:10}][{name|rpad:10}][{name|cut:3}]")),
  "[Aberrant  ][  Aberrant][Abe]")
view.add_styles({ s1 = "red" })
eq("ell inside a line style", view.draw(w.text("{name|ell:4}", { style = "s1" })), colors.red("Abe…"))
eq("ell on colored text keeps … in", view.draw(w.text("{c|ell:4}", { vars = { c = view.const(colors.red("Aberrant")) } })),
  colors.red.on .. "Abe…" .. colors.RESET)
eq("text dur", view.draw(w.text("{tick.left|dur}")), "30s")
eq("text style filter on value", plain(view.draw(w.text("{hp.pct|style:s3}"))), "25")
check("text style filter colors", view.draw(w.text("{hp.pct|style:s3}")):find(colors.yellow.on, 1, true) ~= nil)
local O2 = view.provides("t.maybe", "", { maybe = { "text", "sometimes nil" } })
eq("text with a nil value is nil", view.draw(w.text("x {maybe}")), nil)
errs("unknown filter", function() w.text("{name|shout}") end, "text: unknown filter \"shout\"")
errs("template naming unknown data", function() w.text("{ghost}") end, "no data named \"ghost\"")

-- pad / cut wrappers
eq("pad a widget", plain(view.draw(w.pad(health(40), 5))), "40   ")
eq("cut a widget", plain(view.draw(w.cut(w.text("{name}"), 3))), "Abe")

-- Caching: rebuilt only when an input changed --------------------------------
view.styles({ ["rag.red"] = "red", ["rag.amber"] = "yellow", ["rag.green"] = "green" })
local cached = health(view.ref("hp"))
view.draw(cached)
local n0 = cached.rebuilt
view.draw(cached)
eq("unchanged: not rebuilt", cached.rebuilt, n0)
V.set("mana", { cur = 1, max = 100 })
view.draw(cached)
eq("other data changed: not rebuilt", cached.rebuilt, n0)
V.set("hp", { cur = 10, max = 200 })
eq("hp changed: rebuilt, red", view.draw(cached), colors.red("5"))
eq("rebuilt once", cached.rebuilt, n0 + 1)

local tck = w.text("TCK {tick.left}")
eq("clock value", view.draw(tck), "TCK 30")
local r0 = tck.rebuilt
view.draw(tck)
eq("same second: not rebuilt", tck.rebuilt, r0)
now = now + 1
eq("next second: rebuilt", view.draw(tck), "TCK 29")
eq("one rebuild per change", tck.rebuilt, r0 + 1)

-- A style change redraws what was saved in the old colors
local restyle = w.rag(20)(5)
eq("before restyle", view.draw(restyle), colors.red("5"))
view.styles({ ["rag.red"] = "cyan" })
eq("after restyle", view.draw(restyle), colors.cyan("5"))

-- Panes, bars, the pass -------------------------------------------------------
view.styles({})
panes_written = {}
view.pane("p1", { w.text("{name}"), "literal", w.text("{maybe}") })
view.pane("p2", { pick = "priority", w.text("{maybe}"), w.text("second {name}") })
check("flush bar registered", bars_reg.view_flush ~= nil)
check("flush bar shows nothing", bars_reg.view_flush() == nil)
eq("stack pane", panes_written[1] and panes_written[1][2], "Aberrant\nliteral")
eq("priority pane", panes_written[2] and panes_written[2][2], "second Aberrant")
local count = #panes_written
bars_reg.view_flush()
eq("nothing changed: no pane write", #panes_written, count)
O2.set("maybe", "now")
bars_reg.view_flush()
eq("priority switches", panes_written[#panes_written][2], "now")
eq("stack grows", panes_written[#panes_written - 1][2], "Aberrant\nliteral\nnow")

view.pane("p3", { refresh = "every", every = 5, w.text("{tick.left}") })
local before = #panes_written
bars_reg.view_flush()
local after_first = #panes_written
now = now + 1; bars_reg.view_flush()
eq("every 5: not redrawn after 1 s", #panes_written, after_first)
now = now + 4; bars_reg.view_flush()
eq("every 5: redrawn after 5 s", #panes_written, after_first + 1)
check("every pane drew at first", after_first == before + 1)
errs("every without seconds", function() view.pane("bad", { refresh = "every" }) end, "needs every = seconds")

view.bar("b1", { left = { "HP ", w.text("{hp.cur}") }, right = { w.text("{name}") } })
bars_reg.view_flush()
local row = bars_reg.b1()
eq("bar left", row and row.left, "HP 10")
eq("bar right", row and row.right, "Aberrant")
local same = bars_reg.b1()
bars_reg.view_flush()
check("bar row kept when unchanged", bars_reg.b1() == same)

-- One refresh request per burst
bars_reg.view_flush()
refreshes = 0
V.set("hp", { cur = 11, max = 200 }); V.set("mana", { cur = 2, max = 100 }); V.set("name", "X")
eq("one refresh_bars per burst", refreshes, 1)
bars_reg.view_flush()
V.set("name", "Y")
eq("a new burst asks again", refreshes, 2)

-- Publish and subscribe -------------------------------------------------------
local got = {}
view.subscribe("name", function(n, v) got[#got + 1] = n .. "=" .. v end)
V.set("name", "Z"); V.set("name", "Q")
V.publish()
eq("subscriber once per publish", #got, 1)
eq("subscriber sees the value", got[1], "name=Q")
V.publish()
eq("nothing pending: no call", #got, 1)
local C = view.provides("t.loop", "", { loop = { "number" } })
local loops = 0
view.subscribe("loop", function() loops = loops + 1; C.set("loop", loops); C.publish() end)
C.set("loop", 0); C.publish()
check("cascade cut", loops <= 4, loops)

-- Dirty marks: only what shows changed data is rebuilt ----------------------------
local hpw, namew = w.text("{hp.cur}"), w.text("{name}")
view.draw(hpw); view.draw(namew)
local h0, n0w = hpw.rebuilt, namew.rebuilt
V.set("hp", { cur = 77, max = 200 })
view.draw(hpw); view.draw(namew)
eq("dirty: hp widget rebuilt", hpw.rebuilt, h0 + 1)
eq("clean: name widget not", namew.rebuilt, n0w)
V.set("hp", { cur = 77, max = 200 })
view.draw(hpw)
eq("same ratio again: no rebuild", hpw.rebuilt, h0 + 1)
local parent = w.spaced(w.text("{hp.cur}"), namew)
view.draw(parent)
local p0 = parent.rebuilt
V.set("name", "Mu")
eq("parent of a dirty child redraws", plain(view.draw(parent)), "77 Mu")
eq("once", parent.rebuilt, p0 + 1)
bars_reg.view_flush(); refreshes = 0
V.set("name", "Mu")
eq("same value: no refresh asked", refreshes, 0)

-- Dev mode shape check, unprovide -----------------------------------------------
view.dev = true
warned = {}
V.set("hp", "lots")
check("dev mode warns on a wrong shape", warned[1] and warned[1]:find("not a ratio", 1, true), warned[1])
view.dev = false
view.unprovide("t.maybe")
errs("unprovided data is gone", function() view.ref("maybe.x") end, "no data named")

-- A bar hosts the pass when it's the first thing registered ----------------------
view._reset(); bars_reg = {}
local H = view.provides("t.host", "", { n = { "number" } })
H.set("n", 1)
view.bar("first", { left = { w.text("n {n}") } })
view.bar("second", { left = { w.text("m {n}") } })
check("no hidden bar when a bar is first", bars_reg.view_flush == nil)
eq("first bar runs the pass", bars_reg.first() and bars_reg.first().left, "n 1")
eq("second bar finds its row", bars_reg.second() and bars_reg.second().left, "m 1")
H.set("n", 2)
bars_reg.second()
eq("only the host runs the pass", bars_reg.second().left, "m 1")
bars_reg.first()
eq("after the host's pass", bars_reg.second().left, "m 2")

-- Generated code: the same text as the tree draw ---------------------------------
check("generated code on in plain Lua", view.gen_on)
local G = view.provides("t.gen", "", { g = { "ratio" }, gt = { "timestamp" }, gs = { "text" } })
view.add_styles({ glow = { { below = 50, "red" }, "plain" }, gv = { { below = 50, "plain" }, "green" } })
G.set("g", { cur = 30, max = 100 }); G.set("gt", now + 12); G.set("gs", "a long name here")
local list = { function() return "SEG" end }
local function sample()
  return w.spaced(
    w.first(w.pad(w.text("G {g.pct|fixed:1|style:gv}", { style = "glow", by = "g.pct" }), 9), w.lit("G --", "unavailable")),
    w.text("T {gt.left|pad:2}"), w.text("{gs|ell:6}", { style = "glow", by = "g.pct" }),
    w.calls(list), w.rag(20, 60)(view.ref("g")), w.cut(w.text("{gs}"), 4), "lit")
end
local tree, genf = sample(), view.gen(sample())
eq("generated = tree", genf(), view.draw(tree))
G.set("g", { cur = 80, max = 100 }); now = now + 3
eq("generated = tree after a change", genf(), view.draw(tree))
G.set("g", nil)
eq("generated = tree with nil data", genf(), view.draw(tree))
local gt0 = genf
local gi = w.text("{g.cur}")
local gf = view.gen(gi)
G.set("g", { cur = 5, max = 10 }); gf()
local r0 = gi.rebuilt
gf(); gf()
eq("generated: clean, no rebuild", gi.rebuilt, r0)
G.set("g", { cur = 6, max = 10 })
eq("generated: dirty, rebuilt", gf(), "6")

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
