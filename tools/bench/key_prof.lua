dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
H.feed("char.maxstats", { maxhp = 88000, maxmana = 40000, maxmoves = 30000 })
H.feed("char.vitals", { hp = 69960, mana = 40000, moves = 30000 }); H.pass()
H.feed("char.vitals", { hp = 69990, mana = 40000, moves = 30000 }); H.pass()
local view = require("ui.view")
local function find(f, want) for n = 1, 300 do local k, v = debug.getupvalue(f, n); if not k then return end; if k == want then return v end end end
local mw = find(view.provides, "mark_watchers")
local W = find(mw, "watchers")
local i = next(W.hp)
local N = 100000
local game = require("modules.game")
local function t(label, f) local t0 = os.clock(); for _ = 1, N do f() end; print(string.format("%-30s %.3f us", label, (os.clock() - t0) / N * 1e6)) end
t("mark_watchers(hp)", function() mw("hp") end)

local r = view.ref("hp.pct")
t("value(hp.pct)", function() view.value(r) end)
t("string.format %.1f", function() string.format("%.1f", 79.53) end)
t("view.style(meter_value)", function() view.style("meter_value", "79.5", 79.53) end)
t("view.style(meter_label,'')", function() view.style("meter_label", "", 79.53) end)
t("pcall(empty)", function() pcall(function() end) end)
