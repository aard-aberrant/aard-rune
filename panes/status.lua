-- The status pane (require("panes.status")): two rows between the main output and
-- the input, under the layout's divider line, like the tt++ status box. A
-- pane, not a bar, redrawn whole on every change (util.pane - only written
-- when the text differs), and each second.
--   row 1: TCK, [row1 slots: QST (targets/quest.lua)], TNL LVL ALN,
--          [row1_end slots: 3MN (nav/moons.lua)] - later POP 2XP 2QP
--   row 2: HP MN MV, [row2 slots: AC (fight/autocast.lua)], Enemy (its health),
--          [row2_end slots: DPS (fight/dps.lua)] on the left - later PUP; your
--          state, or the enemy's name in red while fighting, on the right
-- Reads core/game.lua's `game`. Features add their own segments: a slot holds
-- functions returning text, called at each draw, and a feature whose text
-- changed calls status.draw(). So this file knows no feature - they
-- require it, never the other way round.
--   status.field(label, value, width, style)   a "LBL value" segment

local util = require("core.util")
local game = require("core.game")
local layout = require("core.layout")   -- the right column's width

local status = { row1 = {}, row1_end = {}, row2 = {}, row2_end = {} }

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
    return rune.style.gray(label .. " --") .. "   "
  end
  local pct = cur * 100 / max
  local num = string.format("%.1f", pct)
  local pad = string.rep(" ", 5 - #num)
  if pct < 20 then return rune.style.red(label .. " " .. num) .. pad end
  if pct < 60 then return rune.style.yellow(label .. " " .. num) .. pad end
  return label .. " " .. rune.style.green(num) .. pad
end

-- Visible width of a styled string: colour codes removed, UTF-8 characters
-- counted once each
local function vlen(s)
  local plain = util.strip(s)
  return select(2, plain:gsub("[^\128-\191]", ""))
end

-- left and right on one row of width w, the gap filled with spaces
local function spread(left, right, w)
  local gap = w - vlen(left) - vlen(right)
  if gap < 1 then gap = 1 end
  return left .. string.rep(" ", gap) .. right
end

-- Status row 1 (tt++ ticking.tin). Each label plain, its value cyan unless
-- marked, padded so the labels never move:
--   TCK  seconds to the next tick (game.tick); red under 10. "--" until the
--        first tick
--   TNL  experience to the next level, red under 300   (char.status)
--   LVL  your level, left out at 201 and up            (char.status)
--   ALN  alignment, red under -875, green over 875     (char.status)
-- Not yet: POP (repop), 3MN (moons), 2XP/2QP (doubles), ALN's lock colour

function status.field(label, value, width, style)
  return label .. " " .. (style or rune.style.cyan)(string.format("%-" .. width .. "s", tostring(value)))
end
local field = status.field

local function status_row1()
  local t = game.tick
  local f = { t and field("TCK", t, 2, t < 10 and rune.style.red or nil) or field("TCK", "--", 2) }
  for _, seg in ipairs(status.row1) do f[#f + 1] = seg() end
  if game.tnl then f[#f + 1] = field("TNL", game.tnl, 4, game.tnl < 300 and rune.style.red or nil) end
  if game.level and game.level < 201 then f[#f + 1] = field("LVL", game.level, 5) end
  if game.align then
    local a = game.align
    f[#f + 1] = field("ALN", a, 5, a < -875 and rune.style.red or a > 875 and rune.style.green or nil)
  end
  for _, seg in ipairs(status.row1_end) do f[#f + 1] = seg() end
  return table.concat(f, " ")
end

-- Each second: TCK counts down (core/game.lua), slots with clocks move on, and
-- SCROLLED shows or clears (rune._state.scroll_mode: "live" or "scrolled" -
-- nothing tells when it changes, so it's looked at here)
rune.timer.every(1, function() status.draw() end, { name = "status_second" })

-- Row 2's Enemy segment (tt++ statusbar.tin): " | Enemy 70 " while fighting,
-- green under 20 (nearly dead), red otherwise; blank at the same width
-- out of a fight, so DPS after it never moves
local function enemy_segment()
  if game.state ~= 8 then return string.rep(" ", 13) end
  local pct = game.enemypct or 0
  local style = pct < 20 and rune.style.green or rune.style.red
  return rune.style.gray(" | ") .. style(string.format("Enemy %-3s", pct)) .. " "
end

local SCROLLED = " SCROLLED - Ctrl+End "

function status.draw()
  local row1 = status_row1()
  local left = meter("HP", game.hp, game.maxhp) .. " "
    .. meter("MN", game.mana, game.maxmana) .. " "
    .. meter("MV", game.moves, game.maxmoves)
  for _, seg in ipairs(status.row2) do left = left .. seg() end
  left = left .. enemy_segment()
  for _, seg in ipairs(status.row2_end) do left = left .. seg() end
  -- Right: your state, or in a fight the enemy's name. GMCP sends the name
  -- with the game's @-colour codes ("@RThe @GRogue"), taken out here
  local scrolled = rune._state.scroll_mode == "scrolled"
  local fighting = game.state == 8 and game.enemy ~= ""
  local right = fighting and (game.enemy:gsub("@x%d%d?%d?", ""):gsub("@.", ""))
    or state_names[game.state or 0] or "?"
  -- Cut to the room the left leaves, so the row never wraps (a wrapped row
  -- pushes row 1 out of the pane): a long mob name ends in "…"
  local room = layout.RIGHT_W - vlen(left) - 1 - (scrolled and #SCROLLED + 1 or 0)
  if #right > room then right = room > 1 and right:sub(1, room - 1) .. "…" or "" end
  if fighting then right = rune.style.red(right) end
  -- The main pane scrolled back: new output is below what you see
  if scrolled then right = "\27[30;43m" .. SCROLLED .. "\27[0m " .. right end
  util.pane("status", row1 .. "\n" .. spread(left, right, layout.RIGHT_W))
end

-- Redraw on whatever changes a field (core/game.lua has already stored it)
for _, pkg in ipairs({ "char.vitals", "char.maxstats", "char.status", "comm.tick" }) do
  rune.gmcp.on(pkg, function() status.draw() end, { name = "status_" .. pkg })
end

return status
