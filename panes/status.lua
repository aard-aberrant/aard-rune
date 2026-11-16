-- The status rows (require("panes.status")): two rows between the main output
-- and the input, under the layout's divider line, like the tt++ status box.
-- Two native Rune bars, status1 and status2 (rune.ui.bar; core/layout.lua
-- places them): Rune calls their renderers every 250 ms on its own steady
-- clock, lines up each row's left and right parts, and redraws only a row
-- whose text changed (ui/tui/widget/bar.go).
--   row 1, timers and running measures: TCK, [row1 slots: QST (targets/quest.lua)],
--          [row1_end slots: POP (nav/repop.lua), 3MN (nav/moons.lua), DPS
--          (fight/dps.lua), PUP (fight/pup.lua), 2XP 2QP (targets/doubles.lua)];
--          REC (Rune's /log) at the right end
--   row 2, you: HP MN MV ALN LVL TNL | [row2 slots: AC (fight/autocast.lua)]
--          and the enemy (name and health) - your state out of a fight
-- A slot's segment is its text alone; the row puts the spaces between.
-- Features add their own segments with status.add(slot, widget[, pos]) - a
-- widget on the data the feature publishes (core/view.lua), rebuilt only
-- when that data changes. A plain function still works (called on every
-- pass). So this file knows no feature - they require it, never the other
-- way round; the segments' styles are set below, by name.
--   status.add("row1" | "row1_end" | "row2", widget, pos)
--   status.field(label, value, width, style)   a "LBL value" segment

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

local status = { row1 = {}, row1_end = {}, row2 = {} }
function status.add(slot, item, pos) view.slot_add(status[slot], item, pos) end

-- Rune's /log open (REC): set by the wrappers of rune.log.start/stop below
local LOG = view.provides("rune.log", "Rune's /log", {
  ["log.open"] = { "boolean", "a /log file is open" },
})
LOG.set("log.open", rune.log.status() ~= nil)

-- The rows are built from the engine's widgets on aard.char's data (the
-- modular display plan, phase 2): each piece is rebuilt only when what it
-- shows changed. The segments other modules add (row1, row1_end, row2) are
-- still functions, called on every pass as before, until they publish data
-- too. The styles below are the layout's - by role, so data/theme.lua
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
  ["qst.value"] = "value", ["qst.low"] = "danger", ["qst.ready"] = "quest.ready",
  ["qst.active"] = "quest.active", ["qst.warn"] = "danger", ["qst.none"] = "unavailable",
  ["pop.value"] = "value", ["pop.low"] = "danger", ["pop.guess"] = "muted", ["pop.none"] = "unavailable",
  ["moon.unknown"] = "moon.unknown", ["moon.up"] = "moon.up", ["moon.none"] = "unavailable",
  ["moon.soon"] = "moon.soon", ["moon.later"] = "muted",
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
-- then the row1 slots (QST) and the row1_end slots (POP 3MN DPS PUP 2XP
-- 2QP - in load order, init.lua), a space between each
--
-- status.field: a value of "--" is always theme.unavailable, whatever
-- style is passed - so every placeholder looks the same without each
-- segment asking

function status.field(label, value, width, style)
  value = tostring(value)
  if value == "--" then style = theme.unavailable end
  return label .. " " .. (style or theme.value)(string.format("%-" .. width .. "s", value))
end
local field = status.field

-- Row 1: TCK (seconds to the next tick, from the clock on every pass; red
-- under 10; "--" until the first tick), then the row1 and row1_end slots
local row1_left = w.spaced(
  w.first(w.text("TCK {tick.left|pad:2|style:tck}"), w.join("TCK ", w.lit("--", "unavailable"))),
  w.slot(status.row1), w.slot(status.row1_end))

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
-- then " | ", the row2 slots (AC) and the enemy, a space between each.
-- Not yet: ALN's lock colour
local row2_left = w.join(
  w.spaced(meter("HP", "hp"), meter("MN", "mana"), meter("MV", "moves"),
    w.text("ALN {align|pad:5|style:aln}"),
    w.text("LVL {lvl|style:value}", { vars = { lvl = h.below(ref("level"), 201) } }),
    w.first(w.text("TNL {tnl|pad:4|style:tnl}"), w.join("TNL ", w.lit("--  ", "unavailable")))),
  w.lit(" | ", "muted"),
  w.spaced(w.slot(status.row2), enemy))

local SCROLLED = "SCR"   -- right-aligned under row 1's REC

-- REC at row 1's right end (tt++ ticking.tin): Rune's /log open - it flashes
-- each second, black on red, then bright red (the terminal's blink didn't
-- show in tt++); dim when not logging. log.open is set at load from
-- rune.log.status() (the open log's path or nil) and by the start/stop
-- wrappers below - /log goes through them. Rebuilt each second
local rec = w.custom("rec", { inputs = { "log.open" }, clock = true }, function(st, open)
  if not open then return st("off", "REC"), false end   -- no log: nothing flashes
  if os.time() % 2 == 0 then return st("on", "REC") end
  return st("flash", "REC")
end)

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
