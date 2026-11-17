-- The info pane (tt++ modules/info.tin).
-- Several things want the 4-line pane but only one can have it: a
-- priority container shows the first item with something to show:
--   bcc         10  Black Claw Crag's breath grid (modules/zones/blackclaw.lua)
--   alert_crit  20  an alert (modules/alerts.lua), flashing black on red
--   alert_warn  25  the same, black on yellow
--   msg         40  your own text (infomsg, modules/infomsg.lua)
--   quest       50  the quest's target (modules/quest.lua)
--   campaign    60  the campaign's (modules/campaign.lua)
--   account     90  gold, worth, QP, TP, trains, HR/DR, low stats (modules/account.lua)
-- An item has something while one of its widgets' processor returns a
-- value (nil: nothing). Each item is generic widgets on its module's data,
-- with that module's processors and formatters (process/<module>.lua,
-- format/<module>.lua); moving account to a container of its own is a
-- rectangle in data/layout/screen.lua and account(screen.containers.acct), no
-- module touched.
-- What the pane shows is published as info.shown - an alert counts down
-- only while it shows.
-- infopane: list the items / pin one / reset (ui/pin.lua).
require("data.layout.screen")
local screen = require("ui.screen")
local theme = require("ui.theme")
require("ui.widgets.block")      -- panel:block (an alert)
require("ui.widgets.text")       -- panel:text
require("ui.widgets.value")      -- panel:value
require("ui.widgets.indicator")  -- panel:indicator
local G = require("process.generic")
local FG = require("format.generic")
local short, commas = FG.short, FG.commas
local PQ, FQ = require("process.quest"), require("format.quest")
local PC, FC = require("process.campaign"), require("format.campaign")
local PA, FA = require("process.account"), require("format.account")
local PB, FB = require("process.bcc"), require("format.bcc")

-- An alert of a level (modules/alerts.lua's alert.<level>.*): the title,
-- then the text wrapped, flashing each second
local function alert(p, lvl, style, flash)
  p:block { source = { "alert." .. lvl .. ".title", "alert." .. lvl .. ".text" }, style = style, flash = flash }
end

-- infomsg: up to 4 lines of your own text, each cut to the pane's width
local function infomsg(p)
  for k = 1, 4 do p:text { y = "next", source = "infomsg.line" .. k, w = "*" } end
end

-- A quest's or campaign's target, a line each: "area" (cyan), "room"
-- (blue), "mob" (magenta, with its keyword); shown while <prefix>.on
local function target(p, pre, lines)
  local on = pre .. ".on"
  for _, what in ipairs(lines) do
    if what == "mob" then
      p:text { y = "next", source = { on, pre .. ".mob", pre .. ".keyword" }, color = theme.target.mob, process = PQ.mob }
    else
      p:text { y = "next", source = { on, pre .. "." .. what }, color = theme.target[what], process = G.when }
    end
  end
end

-- The quest: the minutes left (red under 5) or "killed, return to QM",
-- then the target
local function quest(p)
  p:value { source = { "quest.on", "quest.killed", "quest.ends" }, every = 1,
    process = PQ.left, show = FQ.left, color = FQ.left_color }
  target(p, "quest", { "area", "room", "mob" })
end

-- The campaign: targets and time left; the area ("k of n"); the room, or
-- "killed - cn for next"; the mob, with (MAZE) for the Partroxis maze and
-- (DEAD) while it hasn't repopped
local function campaign(p)
  p:value { source = { "cp.on", "cp.count", "cp.ends" }, every = 1, process = PC.left, show = FC.left }
  p:text { y = "next", source = { "cp.on", "cp.area", "cp.area_k", "cp.area_n" }, color = theme.target.area,
    process = PC.area }
  p:value { y = "next", source = { "cp.on", "cp.killed", "cp.room" }, process = PC.room,
    show = FC.room, color = FC.room_color }
  target(p, "cp", { "mob" })
  p:indicator { source = { "cp.on", "cp.maze" }, text = " (MAZE)", colors = { [true] = theme.caution }, process = PC.flag }
  p:indicator { source = { "cp.on", "cp.dead" }, text = " (DEAD)", colors = { [true] = theme.danger }, process = PC.flag }
end

-- Account: gold and worth; QP, TP, trains; HR and DR, red under your
-- subclass's minimum; any stat (not int) under the minimum, in red. Only
-- once GMCP char.worth has come (acct.known)
local function account(p)
  local L = theme.default   -- the labels
  local function known(names) table.insert(names, 1, "acct.known"); return names end
  p:value { source = known { "acct.gold" }, process = G.gate(G.round), label = "Gold ", label_color = L, show = short, w = 9 }
  p:value { source = known { "acct.worth" }, process = G.gate(G.round), label = "Worth ", label_color = L, show = short }
  p:value { y = "next", source = known { "acct.qp" }, process = G.gate(G.either(0)), label = "QP ", label_color = L,
    show = commas, w = 11 }
  p:value { source = known { "acct.tp" }, process = G.gate(G.either(0)), label = "TP ", label_color = L, w = 4 }
  p:value { source = known { "acct.trains" }, process = G.gate(G.either("--")), label = "TRN ", label_color = L,
    show = FA.trains }
  p:value { y = "next", source = known { "acct.hr", "acct.dr", "acct.hr_min" }, process = G.gate(PA.vs_min("hr")),
    label = "HR ", label_color = L, w = 11, show = FA.vs_min, color = FA.vs_min_color }
  p:value { source = known { "acct.hr", "acct.dr", "acct.dr_min" }, process = G.gate(PA.vs_min("dr")),
    label = "DR ", label_color = L, show = FA.vs_min, color = FA.vs_min_color }
  local stats = {}
  for k, st in ipairs(PA.STATS) do stats[k] = "acct." .. st end
  stats[#stats + 1] = "acct.stat_min"
  p:widget { y = "next", source = known(stats), process = G.gate(PA.low_stats), format = FA.low_stats }
end

-- Black Claw Crag's breath grid: the last breath and the safe side, then
-- the lair, a square's seconds left; @@ Axaldra's column
local function bcc(p)
  p:widget { source = { "bcc.dir", "bcc.safe" }, process = PB.head, format = FB.head }
  local function cell(c)
    p:widget { source = { "bcc.dir", "bcc." .. c, "bcc." .. c .. "_safe" }, every = 1, process = PB.cell, format = FB.cell }
  end
  for _, row in ipairs(PB.GRID) do
    p:widget { y = "next", text = "          " }
    cell(row[1]); p:widget { text = "  " }
    if row[2] then cell(row[2]) else p:widget { source = "bcc.dir", format = FB.axaldra } end
    p:widget { text = "  " }; cell(row[3])
  end
end

-- The info container: the items, first wins
local pins = require("ui.pin").new { key = "info_pin", command = "infopane", tag = "info", what = "info pane",
  help = "list what can show in the info pane; <name>: pin one (it shows whenever it has something, beating all but an alert); reset: the normal order again" }
local pick = screen.containers.info:priority { shown = "info.shown", pin = pins.get }
bcc(pick:item { name = "bcc", prio = 10 })
alert(pick:item { name = "alert_crit", prio = 20, keep = true }, "crit", "alert", "danger")
alert(pick:item { name = "alert_warn", prio = 25, keep = true }, "warn", "alert_caution", "caution")
infomsg(pick:item { name = "msg", prio = 40 })
quest(pick:item { name = "quest", prio = 50 })
campaign(pick:item { name = "campaign", prio = 60 })
account(pick:item { name = "account", prio = 90 })
pins.attach(pick)

return {}
