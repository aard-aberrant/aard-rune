-- The info pane (require("panes.info")), tt++ modules/info.tin. Several things want
-- the 4-line pane but only one can have it: each sets its text with
--   info.set(name, prio, text)   -- text nil = nothing to show
-- and the one with the lowest prio wins. The pane is only redrawn when the
-- winner's text changes, so a provider may call set as often as it likes.
-- Priorities: alert_crit 20, alert_warn 25, quest 50, campaign 60,
-- account 90 (leave gaps).
-- Alerts: info.alert("crit"|"warn", secs, TITLE, text) flashes the pane
-- (black on red, with a beep / black on yellow) for secs seconds - counted only while it
-- is on the pane, so a crit covering a warn doesn't eat the warn's time. A
-- second alert with the same title replaces the text of the first. Within a
-- level they play in turn. The 1 s timer runs only while one is up.
-- info.alert_clear(TITLE) takes one off.
-- Account is the fallback (account.tin): gold, worth, QP, TP, trains, HR/DR
-- and any stat but int under STAT_MIN, from GMCP char.worth / char.stats.
-- infopane (tt++ modules/info.tin - the user's choice, 2026-11-08; not
-- "info", the game's own info channel):
--   infopane          list the providers: priority, showing or idle, which
--                     is on the pane, which is pinned
--   infopane <name>   pin one (any unique start of its name): it shows
--                     instead of the normal winner whenever it has something
--                     to show, beating all but an alert flashing; with
--                     nothing to show it waits and the normal winner shows
--   infopane reset    unpin - back to the normal order
-- The pin is kept in rune.session: a /reload keeps it, quitting Rune
-- forgets it.

local util = require("core.util")
local colors = require("core.colors")
local theme = require("core.theme")
-- This module's colors: theme.target.* - /theme lists them, data/theme.lua
-- changes them (core/theme.lua)
local T = theme.define("target", "Quest and campaign targets (info pane)", {
  { "area",  theme.cyan,    "the area" },
  { "room",  theme.blue,    "the room" },
  { "mob",   theme.magenta, "the mob" },
  { "gone",  theme.red,     "the room, when the target is killed or gone" },
})
local game = require("core.game")       -- char.worth, char.stats (account)
local layout = require("core.layout")   -- the pane's width

local info = {}
-- Below these, the account view shows red. The defaults (conf/equipment.tin);
-- a subclass's file (data/classes/<subclass>.lua) may set its own: hr_min,
-- dr_min, stat_min. Read again when the subclass changes
local DEF_HR, DEF_DR, DEF_STAT = 1600, 2000, 600
local HR_MIN, DR_MIN, STAT_MIN = DEF_HR, DEF_DR, DEF_STAT
local mins_for   -- the subclass they were read for

local prov = {}         -- name -> { prio, text }
local PIN = "info_pin"  -- rune.session: the pinned provider's name
local pin = rune.session.get(PIN)
if pin == "" then pin = nil end

local function refresh()
  local best
  for _, p in pairs(prov) do
    if p.text and (not best or p.prio < best.prio) then best = p end
  end
  -- the pinned one, if it has something - unless an alert is flashing
  local pinned = pin and prov[pin]
  local alert = (prov.alert_crit and prov.alert_crit.text) or (prov.alert_warn and prov.alert_warn.text)
  if pinned and pinned.text and not alert then best = pinned end
  local text = best and best.text or ""
  util.pane("info", text)
  return best
end

function info.set(name, prio, text)
  local p = prov[name]
  if p then p.prio, p.text = prio, text else prov[name] = { prio = prio, text = text } end
  refresh()
end

-- A target's view, shared by quest and campaign: the first line as given,
-- then area (cyan), room (blue, or `gone` in red instead), mob (magenta).
-- Missing ones are left out
local C = { area = T.area.on, room = T.room.on, mob = T.mob.on, gone = T.gone.on }
function info.target_rows(first, area, room, mob, gone)
  local rows = { first }
  if area then rows[#rows + 1] = C.area .. area end
  if gone then rows[#rows + 1] = C.gone .. gone
  elseif room then rows[#rows + 1] = C.room .. room end
  if mob then rows[#rows + 1] = C.mob .. mob end
  return table.concat(rows, colors.RESET .. "\n") .. colors.RESET
end

-- Alerts ----------------------------------------------------------------

-- Flashing, a second each: black text (24-bit - plain 30 shows grey) on
-- red, then red text; on yellow, then yellow text for a warn
local LEVEL = {
  crit = { prio = 20, on = theme.alert.on, off = theme.danger.on },
  warn = { prio = 25, on = theme.alert_caution.on, off = theme.caution.on },
}
local queue = { crit = {}, warn = {} }   -- level -> list of { title, text, left }
local ticking = false

-- An alert's lines fill the pane's width, so the background is a block
local function alert_text(lvl, a)
  local w = layout.left_w()
  local function pad(s) return #s < w and s .. string.rep(" ", w - #s) or s:sub(1, w) end
  local col = os.time() % 2 == 0 and LEVEL[lvl].on or LEVEL[lvl].off
  local body = util.wrap(a.text, w)
  local rows = { a.title }
  if #body < 3 then rows[2] = "" end
  for i = 1, math.min(#body, 3) do rows[#rows + 1] = body[i] end
  for i, r in ipairs(rows) do rows[i] = col .. pad(r) .. colors.RESET end
  return table.concat(rows, "\n")
end

local function draw_alerts()
  for lvl, q in pairs(queue) do
    info.set("alert_" .. lvl, LEVEL[lvl].prio, q[1] and alert_text(lvl, q[1]) or nil)
  end
end

local function tick()
  local best = refresh()
  -- count down only the alert on the pane
  for lvl, q in pairs(queue) do
    if q[1] and best == prov["alert_" .. lvl] then
      q[1].left = q[1].left - 1
      if q[1].left <= 0 then table.remove(q, 1) end
    end
  end
  draw_alerts()
  if queue.crit[1] or queue.warn[1] then
    rune.timer.after(1, tick)
  else
    ticking = false
  end
end

function info.alert(lvl, secs, title, text)
  local q = queue[lvl]
  for _, a in ipairs(q) do
    if a.title == title then a.text = text; draw_alerts(); return end
  end
  q[#q + 1] = { title = title, text = text, left = secs }
  if lvl == "crit" then util.beep() end
  draw_alerts()
  if not ticking then
    ticking = true
    rune.timer.after(1, tick)
  end
end

function info.alert_clear(title)
  for _, q in pairs(queue) do
    for i, a in ipairs(q) do
      if a.title == title then table.remove(q, i); draw_alerts(); return true end
    end
  end
  return false
end

-- Account (the fallback) ------------------------------------------------

local function short(n)
  if n >= 1000000 then return string.format("%.1fM", math.floor(n / 100000) / 10) end
  if n >= 1000 then return math.floor(n / 1000) .. "K" end
  return tostring(n)
end

local commas = util.commas

local LABEL, VALUE, RED = theme.default.on, theme.value.on, theme.danger.on

local function account()
  local w, s = game.worth, game.stats
  local gold, bank = w and tonumber(w.gold), w and tonumber(w.bank)
  if not (gold and bank) then info.set("account", 90, nil); return end
  local function f(label, v, width)
    v = tostring(v)
    return LABEL .. label .. " " .. VALUE .. (width and v .. string.rep(" ", width - #v) or v)
  end
  local rows = {
    f("Gold", short(gold), 9) .. f("Worth", short(gold + bank)),
    f("QP", commas(tonumber(w.qp) or 0), 11) .. f("TP", w.tp or 0, 4) .. f("TRN", w.trains or "--"),
  }
  local hr, dr = s and tonumber(s.hr), s and tonumber(s.dr)
  if hr and dr then
    rows[3] = LABEL .. "HR " .. (hr < HR_MIN and RED or VALUE) .. string.format("%-11s", hr)
      .. LABEL .. "DR " .. (dr < DR_MIN and RED or VALUE) .. dr
  end
  local low = {}
  for _, k in ipairs({ "str", "wis", "con", "dex", "luck" }) do
    local v = s and tonumber(s[k])
    if v and v < STAT_MIN then low[#low + 1] = (k == "luck" and "LCK" or k:upper()) .. " " .. v end
  end
  if #low > 0 then rows[#rows + 1] = RED .. table.concat(low, "  ") end
  info.set("account", 90, table.concat(rows, colors.RESET .. "\n") .. colors.RESET)
end

for _, pkg in ipairs({ "char.worth", "char.stats" }) do
  rune.gmcp.on(pkg, account, { name = "info_" .. pkg })
end

-- A new subclass (core/game.lua has stored char.base already): its minimums
rune.gmcp.on("char.base", function()
  local sub = game.subclass
  if not sub or sub == mins_for then return end
  mins_for = sub
  local C = util.class_data(sub) or {}
  HR_MIN, DR_MIN, STAT_MIN = C.hr_min or DEF_HR, C.dr_min or DEF_DR, C.stat_min or DEF_STAT
  account()
end, { name = "info_class_mins" })

-- infomsg ----------------------------------------------------------------
-- infomsg [-t secs] text: your own text on the pane, priority 40 - over
-- quest, campaign and account, under the alerts. | starts a new line (4 at
-- most, each cut at the pane's width). -t: gone after that many seconds. Bare: cleared

local msg_clear = util.slot()   -- an infomsg's time up

function info.msg(text, secs)
  msg_clear.stop()
  if not text then info.set("msg", 40, nil); return end
  local rows = {}
  for l in (text .. "|"):gmatch("(.-)|") do
    if #rows < 4 then rows[#rows + 1] = l:sub(1, layout.left_w()) end
  end
  info.set("msg", 40, table.concat(rows, "\n"))
  if secs then
    msg_clear.start(secs, function() info.msg(nil) end)
  end
end

rune.alias.exact("infomsg", function(args)
  local text = util.trim(args)
  if text == "" then info.msg(nil); return end
  local secs, rest = text:match("^%-t%s+(%d+)%s+(.+)$")
  if text:match("^%-t") and not secs then
    util.warn("[info] infomsg [-t seconds] [text] - | starts a new line.")
    return
  end
  info.msg(rest or text, tonumber(secs))
end)

-- infopane: list, pin, reset (see the top)
local function names()
  local n = {}
  for name in pairs(prov) do n[#n + 1] = name end
  table.sort(n, function(a, b) return prov[a].prio < prov[b].prio end)
  return n
end

rune.alias.exact("infopane", function(args)
  local arg = util.trim(args):lower()
  if arg == "" then
    local best = refresh()
    util.say("[info] info pane providers (lowest priority wins):")
    for _, name in ipairs(names()) do
      local p = prov[name]
      local state = p == best and "on the pane" or (p.text and "showing" or "idle")
      rune.echo(string.format("  %-11s %3d  %s%s", name, p.prio, state, name == pin and "  (pinned)" or ""))
    end
    return
  end
  if arg == "reset" then
    pin = nil
    rune.session.set(PIN, "")
    refresh()
    util.say("[info] info pane: back to the normal order.")
    return
  end
  local hits = {}
  for _, name in ipairs(names()) do
    if name == arg then hits = { name }; break end
    if name:sub(1, #arg) == arg then hits[#hits + 1] = name end
  end
  if #hits == 0 then util.warn("[info] infopane: nothing called \"" .. arg .. "\" - infopane lists them."); return end
  if #hits > 1 then util.warn("[info] infopane: \"" .. arg .. "\" could be " .. table.concat(hits, ", ") .. "."); return end
  pin = hits[1]
  rune.session.set(PIN, pin)
  refresh()
  util.say("[info] info pane: pinned to " .. pin
    .. (prov[pin].text and "" or ", which has nothing to show yet - it shows when it does")
    .. ". infopane reset to undo.")
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("infopane", "infopane [<name>|reset]", "list what can show in the info pane; <name>: pin one (it shows whenever it has something, beating all but an alert); reset: the normal order again")
help.add("infomsg", "infomsg [-t secs] [text]", "your own text on the info pane (| starts a line, 4 lines); -t: gone after secs; bare clears it")

return info
