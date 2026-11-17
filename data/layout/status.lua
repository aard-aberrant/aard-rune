-- The status rows (require("data.layout.status")): two Rune bars, status1 and
-- status2, each a one-row container of generic widgets on the modules'
-- data, with each module's processors and formatters (process/<module>.lua,
-- format/<module>.lua).
--   row 1: TCK QST POP 3MN DPS PUP 2XP 2QP; REC at the right end
--   row 2: HP MN MV ALN LVL TNL | AC AOE, the enemy or your state; WLK SCR right
-- A segment whose module isn't loaded shows nothing, its space with it (a
-- widget puts the space before its label).
local theme = require("ui.theme")
require("modules.game")   -- hp, mana, moves, tick, the enemy ...
require("modules.log")    -- log.open (REC)
require("data.layout.screen")      -- the containers
local screen = require("ui.screen")
require("ui.widgets.tenths")      -- panel:tenths (HP MN MV)
require("ui.widgets.countdown")   -- panel:countdown (TCK 2XP 2QP)
require("ui.widgets.value")       -- panel:value (QST POP 3MN ALN LVL TNL, the enemy)
require("ui.widgets.indicator")   -- panel:indicator (REC AC AOE)
require("modules.arrows")         -- walk.on, theme.walk (WLK)
require("ui.widgets.timer")       -- panel:timer (DPS's time)
local containers = screen.containers
local F, P = require("format.generic"), require("process.generic")
local paint, pad = screen.paint, screen.pad
local PQ, FQ = require("process.quest"), require("format.quest")
local PR, FR = require("process.repop"), require("format.repop")
local PM, FM = require("process.moons"), require("format.moons")
local PG, FG = require("process.game"), require("format.game")
local PUP = require("format.pup")
local REC = require("format.log")

-- Row 1 ---------------------------------------------------------------------
local row1 = containers.status1

-- TCK: seconds to the next tick, red under 10; "--" until the first tick
row1:countdown { source = "tick", label = "TCK ", w = 2,
  color = F.rule({ 10 }, { "danger", "value" }),   -- red under 10
  missing = "TCK " .. paint(theme.unavailable, "--") }

-- QST: minutes until you can quest (red under 3), RD, AC (red after the
-- warning), "--"
row1:value { source = { "quest.state", "quest.ready_at", "quest.warn" }, every = 1, label = " QST ", w = 2,
  process = PQ.status, show = FQ.status, color = FQ.status_color }

-- POP: MM:SS to the area's repop, red the last 10 s, gray an estimate
row1:value { source = { "pop.next", "pop.sure" }, every = 1, label = " POP ",
  process = PR.pop, show = FR.pop, color = FR.pop_color }

-- 3MN: the three moons (a Shaman's module), 7 columns
row1:value { source = { "moon.need", "moon.allup", "moon.setleft", "moon.ok", "moon.lo", "moon.len" },
  label = " 3MN ", w = 7, missing = "", process = PM.moons, show = FM.moons, color = FM.moons_color,
  optional = true }   -- moons loads only for a Shaman

-- DPS (modules/dps.lua): " DPS 1234  1:05" - damage a second and combat
-- time, 11 columns after the label: bright while live, gray the last
-- session's after a reset; "--" before any; nothing before the first
-- fight's time. The container's state picks the colors inside it.
-- Updated every 3 s (the user, 2026-11-16); a published change (a fight's
-- start or end, a session's first hit) shows at once
local DPS_EVERY = 3
local dps = row1:container { label = " DPS ", w = 11, every = DPS_EVERY,
  source = { "dps.shown", "dps.secs" }, process = require("process.dps").state,
  alt = { none = paint(theme.unavailable, "--") } }
dps:value { source = "dps.rate", every = DPS_EVERY, w = 5, styles = { live = "on", ["*"] = "muted" },
  missing = paint(theme.unavailable, "--   ") }
dps:widget { text = " " }
dps:timer { source = "dps.secs", every = DPS_EVERY, w = 5, styles = { live = "value", ["*"] = "muted" } }

-- PUP (modules/pup.lua): " PUP 23s / 25s (104)" - the last gap, the
-- average (underlined), the count; 15 columns after the label; gray once
-- the session is over; "--" before the first
local pup = row1:container { label = " PUP ", w = 15, every = 1,
  source = { "pup.live", "pup.last", "pup.avg", "pup.n" }, process = require("process.pup").state,
  alt = { none = paint(theme.unavailable, "--") } }
local LIVE = { live = "on", ["*"] = "muted" }
pup:value { source = "pup.last", styles = LIVE, show = PUP.last }
pup:value { source = "pup.avg", styles = { live = { "on", "emphasis" }, ["*"] = { "muted", "emphasis" } }, show = PUP.avg }
pup:value { source = "pup.n", styles = LIVE, show = PUP.n }

-- 2XP / 2QP: minutes of double experience / quest points left; the label
-- dim while none (theme.double comes with its module: read when drawn)
local function double(label, name, color)
  row1:widget { text = " " }
  local off = pad(paint(theme.unavailable, label), 6)
  row1:countdown { source = name, unit = "m", label = label .. " ", whole = true, w = 2,
    color = F.color_of("double." .. color), zero = off, missing = off }
end
double("2XP", "double.xp", "xp")
double("2QP", "double.qp", "qp")

-- REC (right): a /log open, flashing each second; dim when not logging
row1:indicator { x = -3, source = "log.open", every = 1, text = "REC", process = P.flash,
  colors = { [2] = REC.on, [1] = REC.flash, [0] = theme.off } }

-- Row 2 ---------------------------------------------------------------------
local row2 = containers.status2
-- HP MN MV: a percent to one place - red under 20, yellow under 60 (the
-- label too), green; "HP --", dim, until the maximum is known
local health = F.rule(F.HEALTH, F.HEALTH_COLORS)
local function low(v) return v < F.HEALTH[2] end
local function percent(src, lbl)
  row2:tenths { source = src, process = P.pct, label = lbl .. " ", w = 5, color = health, whole = low,
    missing = pad(paint(theme.unavailable, lbl .. " --"), 8) }
end
percent("hp", "HP")
row2:widget { text = " " }
percent("mana", "MN")
row2:widget { text = " " }
percent("moves", "MV")

-- ALN: red under -875, green over 875; left out until known
row2:value { source = "align", label = " ALN ", w = 5, missing = "",
  color = F.rule({ -875, 876 }, { "danger", "value", "good" }) }
-- LVL: left out at 201 and up
row2:value { source = "level", label = " LVL ", missing = "", process = P.below(201) }
-- TNL: red under 300
row2:value { source = "tnl", label = " TNL ", w = 4, missing = " TNL " .. paint(theme.unavailable, "--  "),
  color = F.rule({ 300 }, { "danger", "value" }) }
row2:widget { text = paint(theme.muted, " | ") }
-- AC: autocast on, dim off
row2:indicator { source = "ac.on", text = "AC", colors = { [true] = theme.on, [false] = theme.off, ["nil"] = theme.off } }
row2:widget { text = " " }
-- AOE: ac aoe, the AoE opener (it casts only while AC is on too), dim off
row2:indicator { source = "ac.aoe", text = "AOE", colors = { [true] = theme.on, [false] = theme.off, ["nil"] = theme.off } }
row2:widget { text = " " }
-- The enemy while fighting (its health, its name cut to 29; green under
-- 20, nearly dead), else your state (no color)
row2:value { source = { "fighting", "enemy_hp", "enemy", "state" },
  process = PG.enemy_or_state, show = FG.enemy_or_state, color = FG.enemy_or_state_color }

-- The right end: WLK SCR. The right side's widgets run on in order (any
-- x < 0), flush right: each always takes its 3 columns (blank when off),
-- so neither light ever moves
-- WLK: the arrow keys walk (modules/arrows.lua)
row2:widget { x = -1, source = "walk.on",
  format = function(on) return on and paint(theme.walk.on, "WLK") or "   " end }
row2:widget { x = -1, text = " " }
-- SCR: the main pane scrolled back - read on every refresh
row2:widget { x = -1, every = 0, process = P.scrolled,
  format = function(on) return on and paint(theme.scrolled, "SCR") or "   " end }

return {}
