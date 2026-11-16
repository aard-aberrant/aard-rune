local root, MODE = arg[1], arg[2] or "check"
package.path = root .. "/?.lua;" .. package.path
dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local view = require("ui.view")
local w, h, ref = view.widgets, view.helpers, view.ref
local B = view.provides("bench.data", "bench", {
  ["bq.state"] = { "text", "" }, ["bq.ready_at"] = { "timestamp", "" }, ["bq.warn"] = { "boolean", "" },
  ["bp.next"] = { "timestamp", "" }, ["bp.sure"] = { "boolean", "" },
})
view.add_styles({ ["bq.value"] = { { below = 3, "danger" }, "value" }, ["qst.value"] = "value", ["qst.low"] = "danger" })
-- today's widgets (copied from targets/quest.lua and nav/repop.lua)
local qst_custom = w.custom("qst", { inputs = { "bq.state", "bq.ready_at.left.min", "bq.warn" } },
  function(st, state, mins, warn)
    if state == "wait" and mins and mins > 0 then
      return "QST " .. st(mins < 3 and "low" or "value", string.format("%-2s", mins), mins)
    end
    if state == "wait" or state == "ready" then return "QST " .. st("ready", "RD") end
    if state == "active" then return "QST " .. st(warn and "warn" or "active", "AC") end
    return "QST " .. st("none", "--")
  end)
local pop_custom = w.custom("pop", { inputs = { "bp.next", "bp.sure" }, clock = true },
  function(st, nxt, sure)
    local left = nxt and nxt - os.time()
    if not left or left < 0 then return "POP " .. st("none", "--   "), false end
    local v = left > 5999 and "99:99" or string.format("%02d:%02d", math.floor(left / 60), left % 60)
    return "POP " .. st(left <= 10 and "low" or not sure and "guess" or "value", v)
  end)
-- the same as cases
local eq, any, all, no, above, below = h.eq, h.any, h.all, h.no, h.above, h.below
local qst_cases = w.cases("QST", {
  { when = all(eq("bq.state", "wait"), above(ref("bq.ready_at.left.min"), 0)), "{bq.ready_at.left.min|pad:2|style:bq.value}" },
  { when = any(eq("bq.state", "wait"), eq("bq.state", "ready")), "RD", style = "qst.ready" },
  { when = all(eq("bq.state", "active"), "bq.warn"), "AC", style = "qst.warn" },
  { when = eq("bq.state", "active"), "AC", style = "qst.active" },
  { "--", style = "qst.none" },
})
local pop_cases = w.cases("POP", {
  { when = below(ref("bp.next.due"), 11), "{bp.next.due|mmss}", style = "pop.low" },
  { when = no("bp.sure"), "{bp.next.due|mmss}", style = "pop.guess" },
  { "{bp.next.due|mmss}", style = "pop.value" },
  { "--   ", style = "pop.none" },
})
view.bar("bench_a", { left = { qst_custom }, right = { pop_custom } })
view.bar("bench_b", { left = { qst_cases }, right = { pop_cases } })
local A, Bb = H.bars.bench_a, H.bars.bench_b
local function both()
  local a1 = H.bars[H.bar_order[1]]()   -- the host bar runs the pass
  local a, b = A(), Bb()
  return a, b
end
local function show(t) return type(t) == "table" and (tostring(t.left) .. " | " .. tostring(t.right)) or tostring(t) end
if MODE == "check" then
  local bad, n = 0, 0
  local function step(tag)
    local a, b = both()
    n = n + 1
    if show(a) ~= show(b) then bad = bad + 1; print("DIFF " .. tag .. "\n  custom: " .. show(a) .. "\n  cases:  " .. show(b)) end
  end
  step("nothing")
  B.set("bq.state", "active"); B.publish(); step("active")
  B.set("bq.warn", true); B.publish(); step("warn")
  B.set("bq.state", "wait"); B.set("bq.warn", false); B.set("bq.ready_at", H.now + 185); B.publish(); step("wait")
  for s = 1, 200 do H.now = H.now + 1; step("wait +" .. s) end
  B.set("bq.state", "ready"); B.publish(); step("ready")
  B.set("bp.next", H.now + 25); B.set("bp.sure", false); B.publish(); step("pop guess")
  for s = 1, 30 do H.now = H.now + 1; step("pop +" .. s) end
  B.set("bp.next", H.now + 7000); B.set("bp.sure", true); B.publish(); step("pop long")
  B.set("bp.next", H.now + 61); B.publish(); step("pop sure")
  for s = 1, 70 do H.now = H.now + 1; step("pop sure +" .. s) end
  print(n .. " steps, " .. bad .. " differ")
  return
end
-- bench: changing cases only - each pass a new second (POP counts, QST's
-- minutes turn every 60), and a quest state change
local N = 100000
local function bench(fn)
  B.set("bq.state", "wait"); B.set("bq.ready_at", H.now + 1e7); B.set("bp.next", H.now + 1e7); B.set("bp.sure", true); B.publish()
  fn(); local t = os.clock()
  for k = 1, N do H.now = H.now + 1; fn() end
  local sec = (os.clock() - t) / N * 1e6
  local states = { "active", "wait", "ready" }
  t = os.clock()
  for k = 1, N do B.set("bq.state", states[k % 3 + 1]); fn() end
  return sec, (os.clock() - t) / N * 1e6
end
view.flush()
local fq1, fp1, fq2, fp2 = view.gen(qst_custom), view.gen(pop_custom), view.gen(qst_cases), view.gen(pop_cases)
local s1, c1 = bench(function() fq1(); fp1() end)
local s2, c2 = bench(function() fq2(); fp2() end)
print(string.format("new second (POP counts down)   custom %.3f  cases %.3f us", s1, s2))
print(string.format("quest state change            custom %.3f  cases %.3f us", c1, c2))
