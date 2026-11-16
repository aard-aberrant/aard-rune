-- Plain-Lua tests for ui/view.lua (the display engine), Rune stubbed.
-- Run from the config folder:  lua tools/view_test.lua
package.path = "./?.lua;" .. package.path

local panes_written, refreshes, warned, bars_reg = {}, 0, {}, {}
rune = {
  ui = {
    refresh_bars = function() refreshes = refreshes + 1 end,
    bar = function(name, fn) bars_reg[name] = fn end,
  },
}
package.preload["lib.util"] = function()
  return {
    pane = function(name, text) panes_written[#panes_written + 1] = { name, text } end,
    warn = function(s) warned[#warned + 1] = s end,
  }
end
package.preload["ui.theme"] = function()
  local c = require("ui.colors")
  return { red = c.red, yellow = c.yellow, green = c.green, bold = c.bold, cyan = c.cyan }
end
package.preload["lib.debug"] = function()
  return { topic = function() return { on = false, log = function() end } end }
end

local view = require("ui.view")
local colors = require("ui.colors")
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
bars_reg.b1()
local row = bars_reg.b1()
eq("bar left", row and row.left, "HP 10")
eq("bar right", row and row.right, "Aberrant")
local same = bars_reg.b1()
check("bar row kept when unchanged", bars_reg.b1() == same)
do
  local n0 = #panes_written
  O2.set("maybe", "again")
  bars_reg.view_flush()
  eq("after a bar: the hidden bar runs no pass", #panes_written, n0)
  bars_reg.b1()
  check("the bar runs it (the panes too)", #panes_written > n0)
end

-- One refresh request per burst
bars_reg.b1()
refreshes = 0
V.set("hp", { cur = 11, max = 200 }); V.set("mana", { cur = 2, max = 100 }); V.set("name", "X")
eq("one refresh_bars per burst", refreshes, 1)
bars_reg.b1()
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
bars_reg.b1(); refreshes = 0
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

-- Custom widgets, slots, clock inputs compared by value --------------------------
local Q = view.provides("t.q", "", { qs = { "text" }, qat = { "timestamp" }, qrec = { "record" } })
Q.set("qs", "wait"); Q.set("qat", now + 150)
view.add_styles({ ["qw.value"] = "red" })
local calls_n = 0
local qw = w.custom("qw", { inputs = { "qs", "qat.left.min" } }, function(st, state, mins)
  calls_n = calls_n + 1
  if state ~= "wait" then return "QST " .. tostring(state) end
  return "QST " .. st("value", tostring(mins))
end)
local qf = view.gen(qw)
eq("custom: renders", qf(), "QST " .. colors.red("3"))
local c0 = calls_n
now = now + 1; qf(); now = now + 1; qf()
eq("custom: clock input same minute, not rebuilt", calls_n, c0)
now = now + 30
eq("custom: next minute, rebuilt", qf(), "QST " .. colors.red("2"))
eq("custom: once", calls_n, c0 + 1)
Q.set("qs", "ready")
eq("custom: data change", qf(), "QST ready")
eq("custom draw = gen", view.draw(qw), "QST ready")
local ticks = 0
local clk = w.custom("clk", { clock = true }, function() ticks = ticks + 1; return "t" .. now end)
local cf = view.gen(clk)
cf(); cf()
eq("clock widget: once a second", ticks, 1)
now = now + 1; cf()
eq("clock widget: next second", ticks, 2)
errs("custom: unknown data", function() w.custom("bad", { inputs = { "nothing.here" } }, function() end) end, "no data named")

local L = {}
view._reset(); bars_reg = {}
local Z = view.provides("t.z", "", { za = { "text" }, zb = { "text" } })
Z.set("za", "A"); Z.set("zb", "B")
view.bar("zb1", { left = { w.slot(L) } })
view.slot_add(L, w.text("{za}"))
eq("slot: one", bars_reg.zb1().left, "A")
view.slot_add(L, w.text("{zb}"), 1)
eq("slot: added later, at the front", bars_reg.zb1().left, "B A")
view.slot_add(L, function() return "F" end)
eq("slot: a function too", bars_reg.zb1().left, "B A F")
Z.set("za", "AA")
eq("slot: data change", bars_reg.zb1().left, "B AA F")
eq("slot draw = gen", view.draw(w.slot(L)), "B AA F")
check("palette: a group member", view.palette("red") ~= nil)
eq("less", view.value(h.less(view.const(3), 5)), true)
eq("less false", view.value(h.less(view.const(7), 5)), false)

-- cases, tests, due, mmss ----------------------------------------------------------
local Q = view.provides("t.cases", "cases test", {
  ["cq.state"] = { "text", "" }, ["cq.warn"] = { "boolean", "" }, ["cq.at"] = { "timestamp", "" },
})
eq("eq: equal", view.value(h.eq("cq.state", "x")), false)
Q.set("cq.state", "x")
eq("eq: now equal", view.value(h.eq("cq.state", "x")), true)
eq("any: one nil", view.value(h.any("cq.warn", h.eq("cq.state", "x"))), true)
eq("all: one nil", view.value(h.all("cq.warn", h.eq("cq.state", "x"))), false)
eq("no: nil", view.value(h.no("cq.warn")), true)
Q.set("cq.at", now + 61)
eq("due", view.value(view.ref("cq.at.due")), 61)
now = now + 62
eq("due: past is nil", view.value(view.ref("cq.at.due")), nil)
eq("left: past is 0", view.value(view.ref("cq.at.left")), 0)
now = now - 62
view.add_styles({ ["cq.on"] = "red", ["cq.none"] = "plain" })
local function mk()
  return w.cases("CQ", {
    { when = h.all(h.eq("cq.state", "wait"), "cq.warn"), "W", style = "cq.on" },
    { when = h.eq("cq.state", "wait"), "{cq.at.due|mmss}" },
    { when = h.any(h.eq("cq.state", "a"), h.eq("cq.state", "b")), "AB" },
    { "--", style = "cq.none" },
  }, { pad = 5 })
end
-- alone (its own clock keys) and as a bar's only changing item (fused: the
-- bar compares the keys its code reads)
local alone, fused = mk(), mk()
view.bar("cqb", { left = { fused } })
local fa = view.gen(alone)
local function both() bars_reg.zb1(); return fa(), bars_reg.cqb() and bars_reg.cqb().left end   -- zb1 hosts the pass
local function case_eq(name, want)
  local a, b = both()
  eq("cases " .. name, a and plain(a), want); eq("cases " .. name .. " (fused)", b and plain(b), want)
  eq("cases " .. name .. " (tree)", plain(view.draw(mk())), want)
end
case_eq("fallback padded", "CQ --   ")
Q.set("cq.state", "a"); case_eq("any", "CQ AB   ")
Q.set("cq.state", "wait"); case_eq("a value", "CQ 01:01")
now = now + 1; case_eq("next second", "CQ 01:00")
now = now + 61; case_eq("past: a nil value moves on", "CQ --   ")
Q.set("cq.warn", true); case_eq("all", "CQ W    ")
check("cases: style applied", (fa()):find("\27[", 1, true) ~= nil)
Q.set("cq.at", now + 7000); Q.set("cq.warn", false); case_eq("mmss cap", "CQ 99:99")
errs("cases: needs a template", function() w.cases("X", { { when = "cq.warn" } }) end, "needs a template")
-- the code holds the styles' codes: a style change builds it again
Q.set("cq.warn", true); bars_reg.zb1()
local red_row = bars_reg.cqb().left
view.add_styles({ ["cq.on"] = "green" }); bars_reg.zb1()
local green_row = bars_reg.cqb().left
check("style change: new codes in built code", green_row ~= red_row and green_row:find(view.palette("green").on, 1, true) ~= nil, green_row)
eq("style change: same text", plain(green_row), "CQ W    ")

-- pads whose width is known when built (a literal, as:, pad: before a
-- style): the spaces written in or left out - the same text as measuring;
-- after:, clock
local PW = view.provides("t.padw", "pad widths test", {
  ["pw.k"] = { "text", "" }, ["pw.n"] = { "number", "" },
})
view.add_styles({ ["pw.s"] = "red" })
local function pw()
  return w.cases("PW", {
    { when = h.eq("pw.k", "lit"), "--", style = "pw.s" },                                  -- exactly 2
    { when = h.eq("pw.k", "as"), "{pw.n|as:none|style:pw.s}" },                             -- exactly 4
    { when = h.eq("pw.k", "wide"), "{pw.n|pad:6|style:pw.s} {pw.n|pad:6}" },                -- at least 13
    { when = h.eq("pw.k", "after"), "{pw.n|after:s|style:pw.s}", width = 4 },               -- not known
    { when = h.eq("pw.k", "clock"), "{pw.n|clock}" },
  }, { pad = 8 })
end
local pwa = pw(); view.bar("pwb", { left = { pwa } })
local function pw_eq(name, want)
  bars_reg.zb1()
  local a, b = bars_reg.pwb().left, view.draw(pw())
  eq("pad widths " .. name, plain(a), want); eq("pad widths " .. name .. " (tree)", plain(b), want)
  eq("pad widths " .. name .. ": built = tree", a, b)
end
PW.set("pw.n", 7)
PW.set("pw.k", "lit"); pw_eq("literal", "PW --      ")
check("pad widths: spaces after the style", (bars_reg.pwb().left):find("\27%[0m      $") ~= nil, bars_reg.pwb().left)
PW.set("pw.k", "as"); pw_eq("as", "PW none    ")
PW.set("pw.k", "wide"); pw_eq("wide enough", "PW 7      7     ")
PW.set("pw.k", "after"); pw_eq("after", "PW 7s      ")
PW.set("pw.n", 1234567); pw_eq("after, wider", "PW 1234567s")
PW.set("pw.k", "clock"); PW.set("pw.n", 125); pw_eq("clock", "PW 2:05    ")
PW.set("pw.n", 6000); pw_eq("clock cap", "PW >100m   ")

-- list, row refs, banner, a sized pane ---------------------------------------
local LS = view.provides("t.list", "list test", {
  ["ls.rows"] = { "list", "rows", fields = { n = "text", v = "number", on = "boolean" } },
  ["ls.title"] = { "block", "title" }, ["ls.mark"] = { "text", "outside a row" },
})
errs("row: not list data", function() view.row("ls.title") end, "isn't list data")
local lr = view.row("ls.rows")
errs("row: no such field", function() return lr.nope end, "have n, on, v")
view.add_styles({ ["ls.v"] = { { below = 10, "red" }, "green" }, ["ls.t"] = "yellow", ["ls.f"] = "plain" })
local lsize = { 1, 17 }
local built = 0
local lv = { n = lr.n, v = lr.v, m = view.ref("ls.mark") }
local lrow = w.cases("", {
  { when = h.no(lr.on), "-{n|pad:4}{v|rpad:3}", vars = lv },
  { w.join(w.text("{n|cut:4|pad:4}", { vars = lv }), w.text("{v|rpad:3|style:ls.v}{m}", { vars = lv })) },
})
view.pane("lp", { size = function() return lsize[1], lsize[2] end,
  w.banner("ls.title", { style = "ls.t", fill = "ls.f" }),
  w.list("ls.rows", { row = lrow, sort = { h.no(lr.on), lr.v }, key = lr.n, width = 8, gap = " " }) })
local function lp()
  bars_reg.zb1()
  for k = #panes_written, 1, -1 do if panes_written[k][1] == "lp" then return panes_written[k][2] end end
end
LS.set("ls.mark", "*")
LS.set("ls.rows", { { n = "a", v = 50, on = true }, { n = "bb", v = 5, on = true }, { n = "c", v = 7, on = false },
                    { n = "ddddd", v = 20, on = true } })
eq("list: sorted, two columns of one row, rest cut", plain(lp()), "bb    5* dddd 20*")
lsize = { 3, 30 }
LS.set("ls.title", "Hi")
eq("list: banner takes a row", plain(lp()), "              Hi              \nbb    5* a    50*\ndddd 20* -c     7")
check("banner: style, fill, reset", lp():find("^\27%[33mHi", 15) ~= nil or lp():find("\27%[33mHi") ~= nil, lp())
LS.set("ls.title", nil); lsize[2] = 10
eq("list: narrow - one column, every row", plain(lp()), "bb    5*\ndddd 20*\na    50*\n-c     7")
LS.set("ls.mark", "!")
eq("list: data outside the row - rebuilt", plain(lp()), "bb    5!\ndddd 20!\na    50!\n-c     7")
LS.set("ls.rows", { { n = "a", v = 1, on = true } })
eq("list: a field changed - rebuilt", plain(lp()), "a     1!")
check("list: style on a value (rules)", lp():find("\27[31m", 1, true) ~= nil, lp())
view.add_styles({ ["ls.v"] = "green" })
check("list: a style change - built again", lp():find(view.palette("green").on, 1, true) ~= nil, lp())
LS.set("ls.rows", {})
eq("list: empty - nothing", lp(), "")

-- later: built at the first pass; data not provided, left out; provided later, shown
local late = w.later(function() return w.text("L {zl.v}") end)
view.bar("lb", { left = { late, "x" } })
bars_reg.zb1()
eq("later: no such data - left out", bars_reg.lb().left, "x")
local ZL = view.provides("t.later", "later test", { ["zl.v"] = { "text", "" } })
ZL.set("zl.v", "here")
bars_reg.zb1()
eq("later: data provided after - shown", bars_reg.lb().left, "L herex")
ZL.set("zl.v", "again"); bars_reg.zb1()
eq("later: follows its data", bars_reg.lb().left, "L againx")

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
