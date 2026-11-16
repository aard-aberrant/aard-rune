dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local MODE = arg[2] or "bench"
local layout = require("ui.layout")
rune._state.height = 36   -- the group pane 8 rows: 36 less info, the minimap row and dividers
rune._state.width = 44 + layout.RIGHT_W + 1
local util = require("lib.util")
local panes = {}
util.pane = function(n, t) if panes[n] ~= t then panes[n] = t end end
require("modules.group"); require("panes.group")
local snaps = {}
local function snap(tag) H.pass(); snaps[#snaps + 1] = "-- " .. tag .. "\n" .. tostring(panes.group) end
local function ctx(text) return { line = { clean = function() return text end } } end
local function line(text)
  for _, t in ipairs(H.triggers) do
    if t.kind == "starts" and text:sub(1, #t.pat) == t.pat then t.fn(nil, ctx(text)) end
  end
end
local names = { "Aberrant", "Nalani", "Rhuli", "Zed", "Mortimer", "Quixotic", "Bo", "Elspeth", "Ann", "Bob", "Cy" }
local function grp(k, n, title, leader)
  local m = {}
  for i = 1, n or 8 do
    local hp = (i == 2) and (600 + (k % 300)) or (i == 3 and 150 or 1000)
    m[i] = { name = names[i], info = { hp = tostring(hp), mhp = "1000", lvl = tostring(100 + i), here = (i == 8) and 0 or 1 } }
  end
  return { groupname = title, leader = leader, members = m }
end
snap("nothing yet")
H.feed("char.base", { name = "Aberrant", tier = "1", subclass = "x" })
H.feed("group", grp(0, 8, "@RThe @YBig @GGroup", "Nalani")); snap("group")
H.feed("group", grp(250, 8, "@RThe @YBig @GGroup", "Nalani")); snap("hp change")
line("You follow Nalani."); snap("follow leader")
line("You start to follow Rhuli."); snap("follow other")
line("You stop following Rhuli."); snap("stop")
H.feed("group", grp(5, 11, "", nil)); snap("11, no title, no leader")
H.feed("group", grp(5, 3, "A very long group title that is longer than the pane is wide", "zed")); snap("long title")
rune._state.width = 30 + layout.RIGHT_W + 1
H.feed("group", grp(6, 11, "narrow", "zed")); snap("narrow pane")
rune._state.width = 44 + layout.RIGHT_W + 1
H.feed("group", {}); snap("left the group")
if MODE == "snap" then print(table.concat(snaps, "\n")); return end
local N = 20000
local function t(label, f) local t0 = os.clock(); for k = 1, N do f(k) end; print(string.format("%-34s %.2f", label, (os.clock() - t0) / N * 1e6)) end
local g5 = grp(5, 8, "@RThe @YBig @GGroup", "Nalani")
H.feed("group", g5); H.pass(); H.pass()
t("pass, nothing asked", function() H.pass() end)
t("same packet: handler only", function() H.feed("group", grp(5, 8, "@RThe @YBig @GGroup", "Nalani")) end)
t("same packet + pass", function() H.feed("group", grp(5, 8, "@RThe @YBig @GGroup", "Nalani")); H.pass() end)
t("building the packet", function() grp(5, 8, "@RThe @YBig @GGroup", "Nalani") end)
local view = require("ui.view")
local n = 0; local orig = rune.ui.refresh_bars; rune.ui.refresh_bars = function() n = n + 1 end
H.feed("group", grp(5, 8, "@RThe @YBig @GGroup", "Nalani"))
print("pass requested by a same packet: " .. n)
