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
-- A slot's segment is its text alone; the row puts the spaces between
-- Reads core/game.lua's `game`. Features add their own segments: a slot holds
-- functions returning text, called at each draw, and a feature whose text
-- changed calls rune.ui.refresh_bars() to show it at once rather than at the
-- next 250 ms. So this file knows no feature - they
-- require it, never the other way round.
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
local game = require("core.game")

local status = { row1 = {}, row1_end = {}, row2 = {} }

local state_names = {
  [1] = "login", [2] = "motd", [3] = "standing", [4] = "afk", [5] = "note",
  [6] = "building", [7] = "paging", [8] = "fighting", [9] = "sleeping",
  [11] = "resting", [12] = "running",
}

-- "HP 88.2" - the percentage with one decimal, padded after the number to 5
-- so the labels never move (the tt++ status row, modules/statusbar.tin).
-- 60 and up: plain label, green value. Under 60 the label and value are
-- coloured together - yellow, red under 20 (util.tin's ||pct_color)
local function meter(label, cur, max)
  if not cur or not max or max == 0 then
    return theme.unavailable(label .. " --") .. "   "
  end
  local pct = cur * 100 / max
  local num = string.format("%.1f", pct)
  local pad = string.rep(" ", 5 - #num)
  if pct < 20 then return theme.danger(label .. " " .. num) .. pad end
  if pct < 60 then return theme.caution(label .. " " .. num) .. pad end
  return label .. " " .. theme.good(num) .. pad
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

local function status_row1()
  local t = game.tick()
  local f = { t and field("TCK", t, 2, t < 10 and theme.danger or nil) or field("TCK", "--", 2) }
  for _, seg in ipairs(status.row1) do f[#f + 1] = seg() end
  for _, seg in ipairs(status.row1_end) do f[#f + 1] = seg() end
  return table.concat(f, " ")
end

-- Row 2's last field (tt++ statusbar.tin): the enemy while fighting - its
-- health, padded to 3 so the name never moves, then its name (GMCP sends it
-- with the game's @-colour codes, taken out) cut to ENEMY_W; green under 20
-- (nearly dead), red otherwise. Out of a fight your state ("standing")
local ENEMY_W = 25
local function enemy_segment()
  if game.state ~= 8 then return state_names[game.state or 0] or "?" end
  local pct = game.enemypct or 0
  local style = pct < 20 and theme.good or theme.danger
  local name = colors.uncolor(game.enemy or "")
  if #name > ENEMY_W then name = name:sub(1, ENEMY_W - 1) .. "…" end
  return style(string.format("%3s ", pct) .. name)
end

-- Row 2: you. HP MN MV (meter, above), then from char.status
--   ALN  alignment, red under -875, green over 875
--   LVL  your level, left out at 201 and up
--   (ALN padded after to 5, room for the minus sign: "ALN 2500  TNL",
--   "ALN -2500 TNL". LVL unpadded - it changes width seldom)
--   TNL  experience to the next level, red under 300
-- then " | ", the row2 slots (AC) and the enemy, a space between each.
-- Not yet: ALN's lock colour
local function status_row2()
  local f = { meter("HP", game.hp, game.maxhp), meter("MN", game.mana, game.maxmana),
              meter("MV", game.moves, game.maxmoves) }
  if game.align then
    local a = game.align
    f[#f + 1] = field("ALN", a, 5, a < -875 and theme.danger or a > 875 and theme.good or nil)
  end
  if game.level and game.level < 201 then f[#f + 1] = field("LVL", game.level, 1) end
  local tnl = game.tnl
  f[#f + 1] = tnl and field("TNL", tnl, 4, tnl < 300 and theme.danger or nil) or field("TNL", "--", 4)
  local right = {}
  for _, seg in ipairs(status.row2) do right[#right + 1] = seg() end
  right[#right + 1] = enemy_segment()
  return table.concat(f, " ") .. theme.muted(" | ") .. table.concat(right, " ")
end

local SCROLLED = "SCR"   -- right-aligned under row 1's REC

-- REC at row 1's right end (tt++ ticking.tin): Rune's /log open - it flashes
-- each second, black on red, then bright red (the terminal's blink didn't
-- show in tt++); dim when not logging. rune.log.status() is the open log's
-- path or nil
local function rec()
  if not rune.log.status() then return theme.off("REC") end
  if os.time() % 2 == 0 then return T.on("REC") end
  return T.flash("REC")
end

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
  if ok and path then
    rune.clipboard.set(path)
    util.say("[log] path copied to the clipboard.")
  end
  return ok
end

-- Row 1: the fields on the left, REC at the right end
rune.ui.bar("status1", function()
  return { left = status_row1(), right = rec() }
end)

-- Row 2. SCR is looked at on each render (rune._state.scroll_mode:
-- "live" or "scrolled" - nothing tells when it changes)
rune.ui.bar("status2", function()
  local left = status_row2()
  -- Right: SCR, when the main pane is scrolled back (new output is
  -- below what you see)
  local right = rune._state.scroll_mode == "scrolled" and theme.scrolled(SCROLLED) or ""
  return { left = left, right = right }
end)

-- Shown at once on whatever changes a field (core/game.lua has already
-- stored it), not at the next 250 ms
for _, pkg in ipairs({ "char.vitals", "char.maxstats", "char.status", "comm.tick" }) do
  rune.gmcp.on(pkg, function() rune.ui.refresh_bars() end, { name = "status_" .. pkg })
end

return status
