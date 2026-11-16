-- The status rows (require("panes.status")): two rows between the main output
-- and the input, under the layout's divider line, like the tt++ status box.
-- Two native Rune bars, status1 and status2 (rune.ui.bar; core/layout.lua
-- places them): Rune calls their renderers every 250 ms on its own steady
-- clock, lines up each row's left and right parts, and redraws only a row
-- whose text changed (ui/tui/widget/bar.go).
--   row 1, timers and running measures: TCK QST [row1] POP 3MN DPS PUP 2XP
--          2QP [row1_end]; REC (Rune's /log) at the right end
--   row 2, you: HP MN MV ALN LVL TNL | AC [row2] and the enemy (name and
--          health) - your state out of a fight
-- Each segment is a generic widget (core/view.lua) on data a module
-- publishes - quest, repop, moons, dps, pup, doubles, autocast know nothing
-- of this file; the configuration here binds them (to move to the user's
-- layout file, phase 5). A module's data not there (not loaded): its
-- segment is left out. The [slots] take more: status.add(slot, widget[,
-- pos]), the segment's text alone - the row puts the spaces between.
--   status.add("row1" | "row1_end" | "row2", widget, pos)

local util = require("core.util")
local colors = require("core.colors")
local theme = require("core.theme")
local mix, bg = colors.mix, colors.bg
-- This module's colors: theme.rec.* - /theme lists them, data/theme.lua
-- changes them (core/theme.lua)
local T = theme.define("rec", "REC (status bar)", {
  { "on",     mix(theme.black_tc, bg(theme.red)), "REC while a log is open, flashing with rec.flash" },
  { "flash",  theme.red,                          "REC's other flash" },
})
require("core.game")   -- publishes aard.char (hp, mana, tick ...) to the engine
local view = require("core.view")
local w, h, ref = view.widgets, view.helpers, view.ref
local eq, any, all, no, above, below = h.eq, h.any, h.all, h.no, h.above, h.below

local status = { row1 = {}, row1_end = {}, row2 = {} }
function status.add(slot, item, pos) view.slot_add(status[slot], item, pos) end

-- Rune's /log open (REC): set by the wrappers of rune.log.start/stop below
local LOG = view.provides("rune.log", "Rune's /log", {
  ["log.open"] = { "boolean", "a /log file is open" },
})
LOG.set("log.open", rune.log.status() ~= nil)

-- The rows are built from the engine's widgets on the modules' data (the
-- modular display plan): each piece is rebuilt only when what it shows
-- changed. The styles below are the layout's - by role, so data/theme.lua
-- still applies - and move to the user's layout file in phase 5.
view.add_styles({
  value = "value", unavailable = "unavailable", muted = "muted",
  -- HP MN MV: under 60 label and number together yellow, red under 20;
  -- 60 and up a plain label and a green number (tt++ util.tin's ||pct_color)
  meter_label = { { below = 20, "danger" }, { below = 60, "caution" } },
  meter_value = { { below = 60, "plain" }, "good" },   -- the number: under 60 meter_label colors it
  tck = { { below = 10, "danger" }, "value" },
  aln = { { below = -875, "danger" }, { above = 875, "good" }, "value" },
  tnl = { { below = 300, "danger" }, "value" },
  enemy = { { below = 20, "good" }, "danger" },   -- nearly dead: green
  -- The segments other modules add: "<widget>.<slot>" (each module's
  -- widget names its slots); their own color groups as "quest.ready"
  ["rec.off"] = "off", ["rec.on"] = "rec.on", ["rec.flash"] = "rec.flash",
  ["qst.mins"] = { { below = 3, "danger" }, "value" }, ["qst.ready"] = "quest.ready",
  ["qst.active"] = "quest.active", ["qst.warn"] = "danger", ["qst.none"] = "unavailable",
  ["pop.value"] = "value", ["pop.low"] = "danger", ["pop.guess"] = "muted", ["pop.none"] = "unavailable",
  ["moon.unknown"] = "moon.unknown", ["moon.up"] = "moon.up", ["moon.none"] = "unavailable",
  ["moon.soon"] = "moon.soon", ["moon.later"] = "muted",
  ["pup.avg"] = "emphasis",
  ["dps.rate"] = "on", ["dps.time"] = "value", ["dps.last"] = "muted", ["dps.none"] = "unavailable",
  ["pup.on"] = "on", ["pup.over"] = "muted", ["pup.none"] = "unavailable",
  ["dxp.on"] = "double.xp", ["dxp.off"] = "unavailable", ["dqp.on"] = "double.qp", ["dqp.off"] = "unavailable",
  ["ac.on"] = "on", ["ac.off"] = "off",
})

-- "HP 88.2" - the percentage with one decimal, padded after the number to 5
-- so the labels never move (the tt++ status row, modules/statusbar.tin);
-- under 60 label and number in one color span; "HP --" faint until max is
-- known
local function meter(label, name)
  return w.first(
    w.pad(w.text(label .. " {" .. name .. ".pct|fixed:1|style:meter_value}",
      { style = "meter_label", by = name .. ".pct" }), #label + 6),
    w.join(w.lit(label .. " --", "unavailable"), "   "))
end

-- Status row 1 (tt++ ticking.tin): timers and running measures - clocks
-- and countdowns (TCK QST POP 3MN 2XP 2QP), the fight's measures (DPS PUP)
-- and REC. Each label plain, its value cyan unless marked, padded so the
-- labels never move; a segment with nothing running shows a gray "--",
-- padded to its usual width (DPS, PUP):
--   TCK  seconds to the next tick (game.tick()); red under 10. "--" until the
--        first tick
-- then the segments below, a space between each

-- QST (targets/quest.lua's aard.quest): minutes until you can quest again,
-- red under 3 - RD once the wait has run out (before the game says so) or
-- the game says ready - AC on a quest (red after the game's warning) - "--"
-- not known. Built at the first pass (later): the quest module loads after
-- this file; not loaded, no QST
local qst = w.later(function() return w.cases("QST", {
  { when = all(eq("quest.state", "wait"), above(ref("quest.ready_at.left.min"), 0)),
    "{quest.ready_at.left.min|pad:2|style:qst.mins}" },
  { when = any(eq("quest.state", "wait"), eq("quest.state", "ready")), "RD", style = "qst.ready" },
  { when = all(eq("quest.state", "active"), "quest.warn"), "AC", style = "qst.warn" },
  { when = eq("quest.state", "active"), "AC", style = "qst.active" },
  { "--", style = "qst.none" },
}) end)

-- POP (nav/repop.lua's aard.repop): MM:SS to this area's next repop, red
-- for the last 10 s, gray when an estimate; "--" once past or not known.
-- 5 columns so the row doesn't shift
local pop = w.later(function() return w.cases("POP", {
  { when = below(ref("pop.next.due"), 11), "{pop.next.due|mmss}", style = "pop.low" },
  { when = no("pop.sure"), "{pop.next.due|mmss}", style = "pop.guess" },
  { "{pop.next.due|mmss}", style = "pop.value" },
  { "--   ", style = "pop.none" },
}) end)

-- 3MN (nav/moons.lua's aard.moons): the three moons, 7 columns - "??" a
-- weather reading owed; all up: ticks until one sets ("--" not known);
-- else ticks until all are up and for how long ("now/3t", "12t/3t"), soon
-- (4 or fewer) colored, later gray; "--" not known
local moon = w.later(function()
  local function c(t) t.width = 7; return t end
  local lo = h.min(ref("moon.lo"), 999)
  return w.cases("3MN", {
    c{ when = "moon.need", "??", style = "moon.unknown" },
    c{ when = all("moon.allup", below(ref("moon.setleft"), 0)), "--", style = "moon.none" },
    c{ when = "moon.allup", "{n}t", style = "moon.up", vars = { n = h.sum(ref("moon.setleft"), 1) } },
    c{ when = eq("moon.ok", false), "--", style = "moon.none" },
    c{ when = below(ref("moon.lo"), 1), "now/{moon.len}t", style = "moon.soon" },
    c{ when = below(ref("moon.lo"), 5), "{lo}t/{moon.len}t", style = "moon.soon", vars = { lo = lo } },
    c{ "{lo}t/{moon.len}t", style = "moon.later", vars = { lo = lo } },
  })
end)

-- DPS (fight/dps.lua's aard.dps): damage per second and combat time,
-- 11 columns - the rate "--" under 5 s; after a reset the last session's,
-- gray, until new damage; "--" before any
local dps = w.later(function() return w.cases("DPS", {
  { when = eq("dps.shown", "none"), "--", style = "dps.none" },
  { when = eq("dps.shown", "live"), "{dps.rate|pad:5|style:dps.rate} {dps.secs|clock|pad:5|style:dps.time}" },
  { when = eq("dps.shown", "live"), "{dps.secs|as:--|pad:5|style:dps.none} {dps.secs|clock|pad:5|style:dps.time}" },
  { when = eq("dps.shown", "last"), "{dps.rate|pad:5|style:dps.last} {dps.secs|clock|pad:5|style:dps.last}" },
  { "{dps.secs|as:--|pad:5|style:dps.none} {dps.secs|clock|pad:5|style:dps.last}" },
}, { pad = 11 }) end)

-- PUP (fight/pup.lua's aard.pup): "23s / 25s (104)" - the last gap, the
-- average (underlined), the count; gray once the session is over; "--"
-- before the first. 15 columns
local pup = w.later(function() return w.cases("PUP", {
  { when = "pup.live", "{pup.last}s / {pup.avg|after:s|style:pup.avg} ({pup.n})", style = "pup.on" },
  { "{pup.last}s / {pup.avg|after:s|style:pup.avg} ({pup.n})", style = "pup.over" },
  { "--", style = "pup.none" },
}, { pad = 15 }) end)

-- 2XP / 2QP (targets/doubles.lua's aard.doubles): minutes of double
-- experience / quest points left, dim when none
local function double(label, name, key)
  return w.later(function() return w.cases("", {
    { when = above(ref(name .. ".left.min"), 0), label .. " {" .. name .. ".left.min|pad:2}", style = key .. ".on" },
    { label, style = key .. ".off" },
  }, { pad = 6 }) end)
end

-- Row 1: TCK (seconds to the next tick, from the clock on every pass; red
-- under 10; "--" until the first tick), QST, the row1 slot, POP, 3MN, DPS,
-- PUP, 2XP, 2QP, the row1_end slot
local row1_left = w.spaced(
  w.first(w.text("TCK {tick.left|pad:2|style:tck}"), w.join("TCK ", w.lit("--", "unavailable"))),
  qst, w.slot(status.row1), pop, moon, dps, pup,
  double("2XP", "double.xp", "dxp"), double("2QP", "double.qp", "dqp"), w.slot(status.row1_end))

-- Row 2's last field (tt++ statusbar.tin): the enemy while fighting - its
-- health, padded to 3 so the name never moves, then its name cut to 25
-- with a "…"; green under 20 (nearly dead), red otherwise. Out of a fight
-- your state ("standing")
local enemy = w.first(
  w.text("{ehp|rpad:3} {en|ell:25}", { style = "enemy", by = "enemy_hp", vars = {
    ehp = h.when(ref("enemy_hp"), ref("fighting")), en = h.when(ref("enemy"), ref("fighting")) } }),
  w.text("{state}"), "?")

-- Row 2: you. HP MN MV (meter, above), then
--   ALN  alignment, red under -875, green over 875
--   LVL  your level, left out at 201 and up
--   (ALN padded after to 5, room for the minus sign: "ALN 2500  TNL",
--   "ALN -2500 TNL". LVL unpadded - it changes width seldom)
--   TNL  experience to the next level, red under 300
-- then " | ", AC (fight/autocast.lua's aard.autocast: autocast on, dim
-- off), the row2 slots and the enemy, a space between each.
-- Not yet: ALN's lock colour
local row2_left = w.join(
  w.spaced(meter("HP", "hp"), meter("MN", "mana"), meter("MV", "moves"),
    w.text("ALN {align|pad:5|style:aln}"),
    w.text("LVL {lvl|style:value}", { vars = { lvl = h.below(ref("level"), 201) } }),
    w.first(w.text("TNL {tnl|pad:4|style:tnl}"), w.join("TNL ", w.lit("--  ", "unavailable")))),
  w.lit(" | ", "muted"),
  w.spaced(w.later(function() return w.cases("", {
    { when = "ac.on", "AC", style = "ac.on" }, { "AC", style = "ac.off" } }) end),
    w.slot(status.row2), enemy))

local SCROLLED = "SCR"   -- right-aligned under row 1's REC

-- REC at row 1's right end (tt++ ticking.tin): Rune's /log open - it flashes
-- each second, black on red, then bright red (the terminal's blink didn't
-- show in tt++); dim when not logging. log.open is set at load from
-- rune.log.status() (the open log's path or nil) and by the start/stop
-- wrappers below - /log goes through them. Rebuilt each second while open
local rec = w.cases("", {
  { when = all(h.even(), "log.open"), "REC", style = "rec.on" },
  { when = "log.open", "REC", style = "rec.flash" },
  { "REC", style = "rec.off" },
})

-- /log's files (Rune's /log start [raw] [file]): in util.state_dir's
-- userlogs/ (~/.local/state/rune/userlogs), not Rune's config_dir/logs.
-- The path is taken as if userlogs/ were the root (a chroot): "/tmp/x"
-- and "tmp/x" both give userlogs/tmp/x.log, "~/y" userlogs/y.log, and ".."
-- goes up only as far as userlogs/ ("../../etc/passwd" is
-- userlogs/etc/passwd.log). "\\" splits as "/" does; leading dots go from
-- every part (no hidden files). No name left: <date>_<time>.log; .log
-- added if the name has no extension; says whether the file is new or
-- being appended to (Rune opens it to append). The folder must exist - Rune's Go
-- side would make it, so a missing one is refused here first, an error
-- /log shows. Rune's /log calls rune.log.start, so wrapping it covers both
local log_start = rune.log.start
function rune.log.start(path, opts)
  local parts = {}
  for part in tostring(path or ""):gmatch("[^/\\]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif not (part == "~" and #parts == 0) then
      local p = part:gsub("^%.+", "")
      if p ~= "" then parts[#parts + 1] = p end
    end
  end
  if #parts == 0 then parts[1] = os.date("%Y-%m-%d_%H-%M-%S") end
  if not parts[#parts]:find(".", 1, true) then parts[#parts] = parts[#parts] .. ".log" end
  local rel = table.concat(parts, "/")   -- what the message shows: the path under userlogs/
  local file = table.remove(parts)
  local dir = util.state_dir .. "/userlogs" .. (parts[1] and ("/" .. table.concat(parts, "/")) or "")
  if not util.dir_exists(dir) then return nil, dir .. " doesn't exist - make it first (mkdir -p)." end
  local path = dir .. "/" .. file
  local fh = io.open(path, "r")
  if fh then fh:close() end
  local ok, err = log_start(path, opts)
  if ok then LOG.set("log.open", true) end
  if ok then util.say("[log] " .. (fh and "appending to the existing " or "new file ") .. "userlogs/" .. rel .. ".") end
  return ok, err
end

-- At /log stop, the file's path goes to the clipboard (the user,
-- 2026-11-11), to paste where it's wanted. rune.log.stop is what /log
-- stop calls, so wrapping it covers it
local log_stop = rune.log.stop
function rune.log.stop()
  local path = rune.log.status()
  local ok = log_stop()
  if ok then LOG.set("log.open", rune.log.status() ~= nil) end
  if ok and path then
    rune.clipboard.set(path)
    util.say("[log] path copied to the clipboard.")
  end
  return ok
end

-- Row 1: the fields on the left, REC at the right end
view.bar("status1", { left = { row1_left }, right = { rec } })

-- Row 2. Right: SCR, when the main pane is scrolled back (new output is
-- below what you see) - looked at on each pass (rune._state.scroll_mode:
-- "live" or "scrolled" - nothing tells when it changes). No refresh hooks
-- here any more: aard.char's set asks for the pass itself
view.bar("status2", { left = { row2_left }, right = { w.calls({ function()
  return rune._state.scroll_mode == "scrolled" and theme.scrolled(SCROLLED) or nil
end }) } })

return status
