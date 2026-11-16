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
-- value (nil: nothing). Each item is generic widgets (ui/widgets/) on its
-- module's data, put together below; moving account to a container of
-- its own is a rectangle in ui/layout.lua and account(screen.containers.acct),
-- no module touched.
-- What the pane shows is published as info.shown - an alert counts down
-- only while it shows.
-- infopane: list the items / pin one / reset (see the end).
local util = require("lib.util")
require("ui.layout")
local screen = require("ui.screen")
local theme = require("ui.theme")
local F, P = require("format.generic"), require("process.generic")
require("ui.widgets.block")      -- panel:block (an alert)
require("ui.widgets.text")       -- panel:text
require("ui.widgets.value")      -- panel:value
require("ui.widgets.indicator")  -- panel:indicator
local paint, num, commas, short, round = screen.paint, F.num, F.commas, F.short, P.round
local mins_left, floor, fmt, concat = P.mins_left, math.floor, string.format, table.concat
local rpad, max, rep = screen.rpad, math.max, string.rep

theme.define("target", "Quest and campaign targets (info pane)", {
  { "area",  theme.cyan,    "the area" },
  { "room",  theme.blue,    "the room" },
  { "mob",   theme.magenta, "the mob" },
  { "gone",  theme.red,     "the room, when the target is killed or gone" },
})

-- An alert of a level (modules/alerts.lua's alert.<level>.*): the title,
-- then the text wrapped, flashing each second
local function alert(p, lvl, style, flash)
  p:block { source = { "alert." .. lvl .. ".title", "alert." .. lvl .. ".text" }, style = style, flash = flash }
end

-- infomsg: up to 4 lines of your own text, each cut to the pane's width
local function infomsg(p)
  for k = 1, 4 do p:text { y = "next", source = "infomsg.line" .. k, w = "*" } end
end

-- A quest's or campaign's target, a line each - lines from "area" (cyan),
-- "room" (blue), "mob" (magenta, with its keyword); shown while the data
-- name `on` is true, a missing one left out. The data: prefix .. ".area",
-- ".room", ".mob", ".keyword"
local function target(p, on, pre, lines)
  for _, what in ipairs(lines) do
    if what == "mob" then
      p:text { y = "next", source = { on, pre .. ".mob", pre .. ".keyword" }, color = theme.target.mob,
        process = function(o, mob, kw) if o and mob then return kw and (mob .. " (" .. kw .. ")") or mob end end }
    else
      p:text { y = "next", source = { on, pre .. "." .. what }, color = theme.target[what],
        process = function(o, v) if o then return v end end }
    end
  end
end

-- The quest: the minutes left (red under 5) or "killed, return to QM",
-- then the target (area, room, mob)
local quest_minutes = F.rule({ 5 }, { "danger", "value" })
local function quest(p)
  p:value { source = { "quest.on", "quest.killed", "quest.ends" }, every = 1,
    process = function(on, killed, ends, now)
      if not on then return nil, math.huge end
      if killed then return "K", math.huge end
      return mins_left(ends, now)
    end,
    show = function(v) return v == "K" and "killed, return to QM" or num(v) .. "m left" end,
    color = function(v) return v == "K" and theme.danger or quest_minutes(v) end }
  target(p, "quest.on", "quest", { "area", "room", "mob" })
end

-- The campaign: targets left and the time left (as days/hours or
-- hours/minutes); the area (with "k of n"); the room, or "killed - cn for
-- next"; the mob, with (MAZE) for the Partroxis maze and (DEAD) while it
-- hasn't repopped
local function campaign(p)
  -- count and minutes left in one integer
  p:value { source = { "cp.on", "cp.count", "cp.ends" }, every = 1,
    process = function(on, count, ends, now)
      if on and count and ends then
        local m, nxt = mins_left(ends, now)
        return count * 10000000 + m, nxt
      end
    end,
    show = function(v)
      local m = v % 10000000
      local d, h = floor(m / 1440), floor(m % 1440 / 60)
      local t = d > 0 and fmt("%dd %dh", d, h) or fmt("%dh %dm", h, m % 60)
      return num(floor(v / 10000000)) .. " left, " .. t
    end }
  p:text { y = "next", source = { "cp.on", "cp.area", "cp.area_k", "cp.area_n" }, color = theme.target.area,
    process = function(on, area, k, n)
      if not (on and area) then return nil end
      if n and k then return area .. " (" .. num(k) .. " of " .. num(n) .. ")" end
      return area
    end }
  p:value { y = "next", source = { "cp.on", "cp.killed", "cp.room" },
    process = function(on, killed, room)
      if not on then return nil end
      if killed then return true end
      return room
    end,
    show = function(v) return v == true and "killed - cn for next" or v end,
    color = function(v) return v == true and theme.target.gone or theme.target.room end }
  target(p, "cp.on", "cp", { "mob" })
  p:indicator { source = { "cp.on", "cp.maze" }, text = " (MAZE)", colors = { [true] = theme.caution },
    process = function(on, m) return on and m or nil end }
  p:indicator { source = { "cp.on", "cp.dead" }, text = " (DEAD)", colors = { [true] = theme.danger },
    process = function(on, d) return on and d or nil end }
end

-- Account (modules/account.lua): gold and worth; QP, TP, trains; HR and
-- DR, red under your subclass's minimum; any stat (not int) under the
-- minimum, in red. Only once GMCP char.worth has come (acct.known)
local function account(p)
  local function gated(names, f)   -- nil until acct.worth is known
    table.insert(names, 1, "acct.known")
    return names, function(known, ...) if known then return f(...) end end
  end
  local L = theme.default   -- the labels
  local s, f
  s, f = gated({ "acct.gold" }, function(g) return g and round(g) end)
  p:value { source = s, process = f, label = "Gold ", label_color = L, show = short, w = 9 }
  s, f = gated({ "acct.worth" }, function(w) return w and round(w) end)
  p:value { source = s, process = f, label = "Worth ", label_color = L, show = short }
  s, f = gated({ "acct.qp" }, function(q) return q or 0 end)
  p:value { y = "next", source = s, process = f, label = "QP ", label_color = L, show = commas, w = 11 }
  s, f = gated({ "acct.tp" }, function(t) return t or 0 end)
  p:value { source = s, process = f, label = "TP ", label_color = L, w = 4 }
  s, f = gated({ "acct.trains" }, function(t) return t or "--" end)
  p:value { source = s, process = f, label = "TRN ", label_color = L,
    show = function(t) return type(t) == "number" and num(t) or t end }
  -- HR / DR: the value, and 1 more when under the minimum (both shown or neither)
  local function vs_min(lbl, name, min, width, first)
    s, f = gated({ "acct.hr", "acct.dr", min }, function(hr, dr, m)
      local v = name == "acct.hr" and hr or dr
      if hr and dr then return v * 2 + ((m and v < m) and 1 or 0) end
    end)
    p:value { y = first and "next" or nil, source = s, process = f, label = lbl, label_color = L, w = width,
      show = function(k) return num(floor(k / 2)) end,
      color = function(k) return k % 2 == 1 and theme.danger or theme.value end }
  end
  vs_min("HR ", "acct.hr", "acct.hr_min", 11, true)
  vs_min("DR ", "acct.dr", "acct.dr_min")
  -- the stats under the minimum
  local STATS = { "str", "wis", "con", "dex", "luck" }
  local names = {}
  for k, st in ipairs(STATS) do names[k] = "acct." .. st end
  names[#names + 1] = "acct.stat_min"
  s, f = gated(names, function(...)
    local v = { ... }
    local m, out = v[#STATS + 1], {}
    if not m then return nil end
    for k, st in ipairs(STATS) do
      if v[k] and v[k] < m then out[#out + 1] = (st == "luck" and "LCK" or st:upper()) .. " " .. num(v[k]) end
    end
    if #out > 0 then return concat(out, "\1") end
  end)
  p:widget { y = "next", source = s, process = f,
    format = function(v)
      if not v then return nil end
      local parts = {}
      for x in v:gmatch("[^\1]+") do parts[#parts + 1] = paint(theme.danger, x) end
      return concat(parts, "  ")
    end }
end

-- Black Claw Crag's breath grid (modules/zones/blackclaw.lua's bcc.*
-- data): the last breath and the safe side, then the lair as a grid - a
-- square's seconds left (red, orange at 2, yellow at 1), then dots once
-- clear, green on the safe side; @@ Axaldra's column. Its colors
-- (theme.bcc) come with the zone script
local hot = F.rule({ 2, 3 }, { "bcc.hot1", "bcc.hot2", "bcc.hot3" })
local function bcc(p)
  p:widget { source = { "bcc.dir", "bcc.safe" },
    process = function(dir, safe) return dir and dir .. "|" .. (safe or "") end,
    format = function(v)
      local dir, safe = v:match("^(.-)|(.*)$")
      local B = theme.bcc
      return paint(B.label, "Axaldra: ") .. paint(B.value, dir) .. "  " .. paint(B.label, "safe: ") .. paint(B.safe, safe)
    end }
  local function cell(c)
    p:widget { source = { "bcc.dir", "bcc." .. c, "bcc." .. c .. "_safe" }, every = 1,
      process = function(dir, t, safe, now)
        if not dir then return nil end
        local left = t and max(0, t - now) or 0
        if left > 0 then return left end
        return safe and -1 or -2
      end,
      format = function(v)
        local B = theme.bcc
        if v > 0 then return paint(hot(v), rpad(num(v), 2)) end
        return paint(v == -1 and B.safe or B.quiet, "..")
      end }
  end
  local PAD, GAP = rep(" ", 10), "  "
  for _, row in ipairs({ { "nw", "n", "ne" }, { "w", false, "e" }, { "sw", "s", "se" } }) do
    p:widget { y = "next", text = PAD }
    cell(row[1]); p:widget { text = GAP }
    if row[2] then cell(row[2])
    else p:widget { source = "bcc.dir", format = function(d) return d and paint(theme.bcc.value, "@@") end } end
    p:widget { text = GAP }; cell(row[3])
  end
end

-- The info container: the items, first wins
local PIN = "info_pin"  -- rune.session: the pinned item's name
local pin = rune.session.get(PIN)
if pin == "" then pin = nil end
local pick = screen.containers.info:priority { shown = "info.shown", pin = function() return pin end }
bcc(pick:item { name = "bcc", prio = 10 })
alert(pick:item { name = "alert_crit", prio = 20, keep = true }, "crit", "alert", "danger")
alert(pick:item { name = "alert_warn", prio = 25, keep = true }, "warn", "alert_caution", "caution")
infomsg(pick:item { name = "msg", prio = 40 })
quest(pick:item { name = "quest", prio = 50 })
campaign(pick:item { name = "campaign", prio = 60 })
account(pick:item { name = "account", prio = 90 })

-- infopane: list, pin, reset (see the top)
rune.alias.exact("infopane", function(args)
  local arg = util.trim(args):lower()
  if arg == "" then
    util.say("[info] info pane items (the first with something to show wins):")
    local now = screen.peek(pick)
    for _, it in ipairs(pick.list) do
      local state = it.name == pick.shown and "on the pane" or (now[it.name] and "showing" or "idle")
      rune.echo(string.format("  %-11s %3d  %s%s", it.name, it.prio, state, it.name == pin and "  (pinned)" or ""))
    end
    return
  end
  if arg == "reset" then
    pin = nil
    rune.session.set(PIN, "")
    pick:refresh()
    util.say("[info] info pane: back to the normal order.")
    return
  end
  local hits = {}
  for _, it in ipairs(pick.list) do
    if it.name == arg then hits = { it.name }; break end
    if it.name:sub(1, #arg) == arg then hits[#hits + 1] = it.name end
  end
  if #hits == 0 then util.warn("[info] infopane: nothing called \"" .. arg .. "\" - infopane lists them."); return end
  if #hits > 1 then util.warn("[info] infopane: \"" .. arg .. "\" could be " .. table.concat(hits, ", ") .. "."); return end
  pin = hits[1]
  rune.session.set(PIN, pin)
  pick:refresh()
  util.say("[info] info pane: pinned to " .. pin
    .. (screen.peek(pick)[pin] and "" or ", which has nothing to show yet - it shows when it does")
    .. ". infopane reset to undo.")
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("infopane", "infopane [<name>|reset]", "list what can show in the info pane; <name>: pin one (it shows whenever it has something, beating all but an alert); reset: the normal order again")

return {}
