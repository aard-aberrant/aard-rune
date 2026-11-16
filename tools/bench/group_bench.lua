dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local MODE = arg[2] or "bench"
local layout = require("ui.layout")
layout.group_h = function() return 8 end
layout.left_w = function() return 44 end
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
layout.left_w = function() return 30 end
H.feed("group", grp(6, 11, "narrow", "zed")); snap("narrow pane")
layout.left_w = function() return 44 end
H.feed("group", {}); snap("left the group")
if MODE == "snap" then print(table.concat(snaps, "\n")); return end
local N = 20000
local g0 = grp(5, 8, "@RThe @YBig @GGroup", "Nalani")
local pk = {}; for k = 1, N do pk[k] = grp(k, 8, "@RThe @YBig @GGroup", "Nalani") end
local t = os.clock(); for k = 1, N do H.pass() end
local pass = (os.clock() - t) / N * 1e6
t = os.clock(); for k = 1, N do H.feed("group", pk[k]); H.pass() end
local chg = (os.clock() - t) / N * 1e6 - pass
t = os.clock(); for k = 1, N do H.feed("group", grp(5, 8, "@RThe @YBig @GGroup", "Nalani")) ; H.pass() end
local same = (os.clock() - t) / N * 1e6 - pass
t = os.clock(); for k = 1, N do grp(5, 8, "@RThe @YBig @GGroup", "Nalani") end
same = same - (os.clock() - t) / N * 1e6
local function grp_all(k)
  local m = {}
  for i = 1, 8 do
    m[i] = { name = names[i], info = { hp = tostring(100 + (k * 7 + i * 113) % 900), mhp = "1000", lvl = tostring(100 + i), here = 1 } }
  end
  return { groupname = "@RThe @YBig @GGroup", leader = "Nalani", members = m }
end
local pa = {}; for k = 1, N do pa[k] = grp_all(k) end
t = os.clock(); for k = 1, N do H.feed("group", pa[k]); H.pass() end
local all = (os.clock() - t) / N * 1e6 - pass
print(string.format("group packet, all 8 hp changed: %6.2f us", all))
print(string.format("group packet, one hp changed: %6.2f us", chg))
print(string.format("group packet, nothing changed: %6.2f us", same))
