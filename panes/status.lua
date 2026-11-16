-- The status rows (require("panes.status")) - PROTOTYPE on ui/screen.lua:
-- two Rune bars, status1 and status2, each a one-row panel of data
-- widgets. A widget: its data, a processor (its result compared - only a
-- change redraws it) and a formatter (the text, colors included).
--   row 1: TCK QST POP 3MN DPS PUP 2XP 2QP; REC at the right end
--   row 2: HP MN MV ALN LVL TNL | AC, the enemy or your state; SCR right
-- A segment whose module isn't loaded shows nothing, its space with it (a
-- formatter puts the space before its label).

local util = require("lib.util")
local colors = require("ui.colors")
local theme = require("ui.theme")
local mix, bg = colors.mix, colors.bg
local T = theme.define("rec", "REC (status bar)", {
  { "on",     mix(theme.black_tc, bg(theme.red)), "REC while a log is open, flashing with rec.flash" },
  { "flash",  theme.red,                          "REC's other flash" },
})
require("modules.game")   -- publishes aard.char (hp, mana, tick ...)
require("ui.layout")      -- the panels
local view = require("ui.view")
local screen = require("ui.screen")
require("ui.widgets.meter")       -- panel:meter (HP MN MV)
require("ui.widgets.countdown")   -- panel:countdown (TCK 2XP 2QP)
require("ui.widgets.value")       -- panel:value (QST POP 3MN ALN LVL TNL, the enemy)
require("ui.widgets.indicator")   -- panel:indicator (REC AC SCR)
require("ui.widgets.dps")         -- panel:dps
require("ui.widgets.pup")         -- panel:pup
local panel = screen.panels
local F, P = require("ui.format"), require("ui.process")
local paint, pad, rpad, width, num, clock = screen.paint, screen.pad, screen.rpad, screen.width, F.num, F.clock

local LOG = view.provides("rune.log", "Rune's /log", {
  ["log.open"] = { "boolean", "a /log file is open" },
})
LOG.set("log.open", rune.log.status() ~= nil)

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
  if ok then LOG.set("log.open", true); LOG.publish() end
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
  if ok then LOG.set("log.open", rune.log.status() ~= nil); LOG.publish() end
  if ok and path then
    rune.clipboard.set(path)
    util.say("[log] path copied to the clipboard.")
  end
  return ok
end


-- Row 1 ---------------------------------------------------------------------
local row1 = panel.status1

-- TCK: seconds to the next tick, red under 10; "--" until the first tick
row1:countdown { source = "tick", label = "TCK ", w = 2,
  color = F.rule({ 10 }, { "danger", "value" }),   -- red under 10
  missing = "TCK " .. paint(theme.unavailable, "--") }

-- QST: minutes until you can quest (red under 3), RD, AC (red after the
-- warning), "--"
-- (theme.quest, .moon and .double come with their modules, after this
-- file: read when drawn)
local qst_minutes = F.rule({ 3 }, { "danger", "value" })   -- red under 3
local QST_COLOR = { RD = function() return theme.quest.ready end, ACW = function() return theme.danger end,
                    AC = function() return theme.quest.active end, ["--"] = function() return theme.unavailable end }
row1:value { source = { "quest.state", "quest.ready_at", "quest.warn" }, every = 1, label = " QST ", w = 2,
  process = function(state, at, warn, now)
    if state == "wait" and at and at > now then return (P.mins_left(at, now)) end
    if state == "wait" or state == "ready" then return "RD" end
    if state == "active" then return warn and "ACW" or "AC" end
    return "--"
  end,
  show = function(k) return k == "ACW" and "AC" or tostring(k) end,
  color = function(k) return type(k) == "number" and qst_minutes(k) or QST_COLOR[k]() end }

-- POP: MM:SS to the area's repop, red the last 10 s, gray an estimate
-- (seconds and the band in one integer; -1: not known)
row1:value { source = { "pop.next", "pop.sure" }, every = 1, label = " POP ",
  process = function(t, sure, now)
    local d = t and t - now
    if not d or d < 0 then return -1 end
    return d * 3 + (d < 11 and 0 or not sure and 1 or 2)
  end,
  show = function(k)
    if k < 0 then return "--   " end
    local d = (k - k % 3) / 3
    return clock(d, true)
  end,
  color = function(k)
    if k < 0 then return theme.unavailable end
    local band = k % 3
    return band == 0 and theme.danger or band == 1 and theme.muted or theme.value
  end }

-- 3MN: the three moons (a Shaman's module), 7 columns: the state's letter,
-- then the text
local MOON_COLOR = { u = "unknown", p = "up", s = "soon" }
row1:value { source = { "moon.need", "moon.allup", "moon.setleft", "moon.ok", "moon.lo", "moon.len" },
  label = " 3MN ", w = 7, missing = "",
  process = function(need, allup, setleft, ok, lo, len)
    if need then return "u??" end
    if allup and setleft and setleft < 0 then return "n--" end
    if allup and setleft then return "p" .. num(setleft + 1) .. "t" end
    if ok == false then return "n--" end
    if lo and len then
      if lo < 1 then return "snow/" .. num(len) .. "t" end
      local l = num(math.min(lo, 999)) .. "t/" .. num(len) .. "t"
      return (lo < 5 and "s" or "l") .. l
    end
  end,
  show = function(k) return k:sub(2) end,
  color = function(k)
    local b = k:sub(1, 1)
    return b == "n" and theme.unavailable or b == "l" and theme.muted or theme.moon[MOON_COLOR[b]]
  end }

-- DPS and PUP (ui/widgets/dps.lua, pup.lua)
row1:dps()
row1:pup()

-- 2XP / 2QP: minutes of double experience / quest points left; the label
-- dim while none
local function double(label, name, color)
  row1:widget { text = " " }
  local off = pad(paint(theme.unavailable, label), 6)
  row1:countdown { source = name, unit = "m", label = label .. " ", whole = true, w = 2,
    color = function() return theme.double[color] end, zero = off, missing = off }
end
double("2XP", "double.xp", "xp")
double("2QP", "double.qp", "qp")

-- REC (right): a /log open, flashing each second; dim when not logging
row1:indicator { x = -3, source = "log.open", every = 1, text = "REC",
  process = function(open, now) return open and (now % 2 == 0 and 2 or 1) or 0 end,
  colors = { [2] = T.on, [1] = T.flash, [0] = theme.off } }

-- Row 2 ---------------------------------------------------------------------
local row2 = panel.status2
row2:meter { source = "hp", label = "HP", w = 8 }
row2:widget { text = " " }
row2:meter { source = "mana", label = "MN", w = 8 }
row2:widget { text = " " }
row2:meter { source = "moves", label = "MV", w = 8 }

-- ALN: red under -875, green over 875; left out until known
row2:value { source = "align", label = " ALN ", w = 5, missing = "",
  color = F.rule({ -875, 876 }, { "danger", "value", "good" }) }
-- LVL: left out at 201 and up
row2:value { source = "level", label = " LVL ", missing = "",
  process = function(l) return l and l < 201 and l or nil end }
-- TNL: red under 300
row2:value { source = "tnl", label = " TNL ", w = 4, missing = " TNL " .. paint(theme.unavailable, "--  "),
  color = F.rule({ 300 }, { "danger", "value" }) }
row2:widget { text = paint(theme.muted, " | ") }
-- AC: autocast on, dim off
row2:indicator { source = "ac.on", text = "AC", colors = { [true] = theme.on, [false] = theme.off, ["nil"] = theme.off } }
row2:widget { text = " " }
-- The enemy while fighting (its health, its name cut to 25; green under
-- 20, nearly dead), else your state (no color): a letter for which, then
-- the text
row2:value { source = { "fighting", "enemy_hp", "enemy", "state" },
  process = function(f, ehp, en, state)
    if f and ehp and en then return (ehp < 20 and "g" or "d") .. rpad(num(ehp), 3) .. " " .. en end
    return state and ("s" .. state) or "s?"
  end,
  show = function(k)
    local s = k:sub(2)
    if k:sub(1, 1) ~= "s" and width(s) > 29 then s = colors.crop(s, 28):gsub("\27%[0m$", "") .. "…" end
    return s
  end,
  color = function(k)
    local b = k:sub(1, 1)
    return b == "g" and theme.good or b == "d" and theme.danger or nil
  end }

-- SCR (right): the main pane scrolled back - nothing says when, so looked
-- at on every refresh
row2:indicator { x = -3, every = 0, text = "SCR", colors = { [true] = theme.scrolled },
  process = function() return rune._state.scroll_mode == "scrolled" end }

return {}
