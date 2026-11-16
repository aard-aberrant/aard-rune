-- The info pane (tt++ modules/info.tin): generic widgets on the modules'
-- data - this file is configuration only. Several things want the 4-line
-- pane but only one can have it: the first in the list with something to
-- show wins (a pick):
--   bcc         10  Black Claw Crag's breath grid (modules/zones/blackclaw.lua)
--   alert_crit  20  an alert (modules/alerts.lua), flashing black on red
--   alert_warn  25  the same, black on yellow
--   msg         40  your own text (infomsg, modules/infomsg.lua)
--   quest       50  the quest's target (modules/quest.lua)
--   campaign    60  the campaign's (modules/campaign.lua)
--   account     90  gold, worth, QP, TP, trains, HR/DR, low stats (modules/account.lua)
-- The numbers are only for the listing; the list's order decides. What it
-- shows is published as info.shown - an alert counts down only while it
-- shows, so a crit covering a warn doesn't eat the warn's time.
-- infopane (tt++ modules/info.tin - the user's choice, 2026-11-08; not
-- "info", the game's own info channel):
--   infopane          list them: priority, showing or idle, which is on
--                     the pane, which is pinned
--   infopane <name>   pin one (any unique start of its name): it shows
--                     instead of the normal winner whenever it has something
--                     to show, beating all but an alert; with nothing to
--                     show it waits and the normal winner shows
--   infopane reset    unpin - back to the normal order
-- The pin is kept in rune.session: a /reload keeps it, quitting Rune
-- forgets it.
local util = require("lib.util")
local theme = require("ui.theme")
-- This pane's colors: theme.target.* - /theme lists them, data/theme.lua
-- changes them (ui/theme.lua)
theme.define("target", "Quest and campaign targets (info pane)", {
  { "area",  theme.cyan,    "the area" },
  { "room",  theme.blue,    "the room" },
  { "mob",   theme.magenta, "the mob" },
  { "gone",  theme.red,     "the room, when the target is killed or gone" },
})
local layout = require("ui.layout")   -- the pane's size
local view = require("ui.view")
local w, h = view.widgets, view.helpers
local ref = view.ref
local unpack = table.unpack or unpack

view.add_styles({
  ["target.area"] = "target.area", ["target.room"] = "target.room",
  ["target.mob"] = "target.mob", ["target.gone"] = "target.gone",
  ["info.label"] = "default", ["info.value"] = "value",
  ["info.danger"] = "danger", ["info.caution"] = "caution",
  ["info.left"] = { { below = 5, "danger" }, "value" },   -- a quest's minutes left
  -- alerts flash, a second each: black (24-bit - plain 30 shows grey) on
  -- red, then red text; on yellow, then yellow text for a warn
  ["alert.crit.on"] = "alert", ["alert.crit.off"] = "danger",
  ["alert.warn.on"] = "alert_caution", ["alert.warn.off"] = "caution",
  -- the breath grid: theme.bcc, defined by the zone script while you're there
  ["bcc.label"] = "bcc.label", ["bcc.value"] = "bcc.value", ["bcc.safe"] = "bcc.safe",
  ["bcc.quiet"] = "bcc.quiet",
  ["bcc.hot"] = { { below = 2, "bcc.hot1" }, { below = 3, "bcc.hot2" }, "bcc.hot3" },
})

-- Black Claw Crag: the last breath and the safe side, then the lair as a
-- grid - a square's seconds left (red, orange at 2, yellow at 1), then
-- dots once clear, green on the safe side; @@ Axaldra's column
local function bcc()
  local function cell(c)
    local left = ref("bcc." .. c .. ".left")
    return w.cases("", {
      { when = h.above(left, 0), "{v|rpad:2}", vars = { v = left }, by = left, style = "bcc.hot" },
      { when = "bcc." .. c .. "_safe", "..", style = "bcc.safe" },
      { "..", style = "bcc.quiet" },
    })
  end
  local PAD, GAP = string.rep(" ", 10), "  "
  return w.cases("", { { when = "bcc.dir", w.textlines(
    w.join(w.lit("Axaldra: ", "bcc.label"), w.text("{bcc.dir}", { style = "bcc.value" }), GAP,
           w.lit("safe: ", "bcc.label"), w.text("{bcc.safe}", { style = "bcc.safe" })),
    w.join(PAD, cell("nw"), GAP, cell("n"), GAP, cell("ne")),
    w.join(PAD, cell("w"), GAP, w.lit("@@", "bcc.value"), GAP, cell("e")),
    w.join(PAD, cell("sw"), GAP, cell("s"), GAP, cell("se"))) } })
end

-- An alert: title, then the text wrapped, across the pane on a flashing block
local function alert(lvl)
  local t, x = "alert." .. lvl .. ".title", "alert." .. lvl .. ".text"
  return w.cases("", {
    { when = h.even(), w.panel(t, x, { style = "alert." .. lvl .. ".on" }) },
    { w.panel(t, x, { style = "alert." .. lvl .. ".off" }) },
  })
end

local function msg()
  local l = {}
  for k = 1, 4 do l[k] = w.text("{infomsg.line" .. k .. "|fit}") end
  return w.textlines(unpack(l))
end

-- A target's view, quest and campaign: a first line, then area (cyan),
-- room (blue, or the kill in red instead), mob (magenta); missing ones
-- are left out
local function mob_line(p)
  return w.cases("", {
    { when = p .. ".keyword", "{" .. p .. ".mob} ({" .. p .. ".keyword})", style = "target.mob" },
    { "{" .. p .. ".mob}", style = "target.mob" },
  })
end

local function quest()
  local left = ref("quest.ends.left.min")
  return w.cases("", { { when = "quest.on", w.textlines(
    w.cases("", {
      { when = "quest.killed", "killed, return to QM", style = "info.danger" },
      { "{m}m left", vars = { m = left }, by = left, style = "info.left" },
    }),
    w.text("{quest.area}", { style = "target.area" }),
    w.text("{quest.room}", { style = "target.room" }),
    mob_line("quest")) } })
end

local function campaign()
  return w.cases("", { { when = "cp.on", w.textlines(
    w.text("{cp.count} left, {cp.ends.left.min|dhm}", { style = "info.value" }),
    w.cases("", {
      { when = "cp.area_n", "{cp.area} ({cp.area_k} of {cp.area_n})", style = "target.area" },
      { "{cp.area}", style = "target.area" },
    }),
    w.cases("", {
      { when = "cp.killed", "killed - cn for next", style = "target.gone" },
      { "{cp.room}", style = "target.room" },
    }),
    w.join(mob_line("cp"),
      w.cases("", { { when = "cp.maze", " (MAZE)", style = "info.caution" } }),     -- the Partroxis maze
      w.cases("", { { when = "cp.dead", " (DEAD)", style = "info.danger" } }))) } })  -- not repopped yet
end

-- Account: gold and worth; QP, TP, trains; HR and DR, red under your
-- subclass's minimum; any stat (not int) under the minimum, in red
local function account()
  local function label(s) return w.lit(s, "info.label") end
  local function value(tpl, vars) return w.text(tpl, { vars = vars, style = "info.value" }) end
  local function vs_min(name, min, tpl)
    return w.cases("", {
      { when = h.lt(name, min), tpl, style = "info.danger" },
      { tpl, style = "info.value" },
    })
  end
  local low = {}
  for k, s in ipairs({ "str", "wis", "con", "dex", "luck" }) do
    local name = s == "luck" and "LCK" or s:upper()
    low[k] = w.cases("", { { when = h.lt("acct." .. s, "acct.stat_min"), name .. " {acct." .. s .. "}", style = "info.danger" } })
  end
  return w.cases("", { { when = "acct.worth", w.textlines(
    w.join(label("Gold "), value("{acct.gold|short|pad:9}"), label("Worth "), value("{acct.worth|short}")),
    w.join(label("QP "), value("{qp|commas|pad:11}", { qp = h.either(ref("acct.qp"), 0) }),
           label("TP "), value("{tp|pad:4}", { tp = h.either(ref("acct.tp"), 0) }),
           label("TRN "), value("{trn}", { trn = h.either(ref("acct.trains"), "--") })),
    w.cases("", { { when = h.all("acct.hr", "acct.dr"), w.join(
      label("HR "), vs_min("acct.hr", "acct.hr_min", "{acct.hr|pad:11}"),
      label("DR "), vs_min("acct.dr", "acct.dr_min", "{acct.dr}")) } }),
    w.separated("  ", unpack(low))) } })
end

-- Built at the first pass (later): the modules load after this pane, and
-- the breath grid's data only exists in Black Claw Crag
local PIN = "info_pin"  -- rune.session: the pinned item's name
local pin = rune.session.get(PIN)
if pin == "" then pin = nil end
local pick = w.pick({
  { name = "bcc",        prio = 10, w.later(bcc) },
  { name = "alert_crit", prio = 20, w.later(function() return alert("crit") end), keep = true },
  { name = "alert_warn", prio = 25, w.later(function() return alert("warn") end), keep = true },
  { name = "msg",        prio = 40, w.later(msg) },
  { name = "quest",      prio = 50, w.later(quest) },
  { name = "campaign",   prio = 60, w.later(campaign) },
  { name = "account",    prio = 90, w.later(account) },
}, { pin = function() return pin end, shown = "info.shown" })

view.pane("info", {
  size = function() return layout.INFO_H, layout.left_w() end,
  pick,
})

-- infopane: list, pin, reset (see the top)
rune.alias.exact("infopane", function(args)
  local arg = util.trim(args):lower()
  if arg == "" then
    util.say("[info] info pane items (the first with something to show wins):")
    local now = pick.peek()
    for _, it in ipairs(pick.items) do
      local state = it.name == pick.shown and "on the pane" or (now[it.name] ~= nil and "showing" or "idle")
      rune.echo(string.format("  %-11s %3d  %s%s", it.name, it.prio, state, it.name == pin and "  (pinned)" or ""))
    end
    return
  end
  if arg == "reset" then
    pin = nil
    rune.session.set(PIN, "")
    view.request()
    util.say("[info] info pane: back to the normal order.")
    return
  end
  local hits = {}
  for _, it in ipairs(pick.items) do
    if it.name == arg then hits = { it.name }; break end
    if it.name:sub(1, #arg) == arg then hits[#hits + 1] = it.name end
  end
  if #hits == 0 then util.warn("[info] infopane: nothing called \"" .. arg .. "\" - infopane lists them."); return end
  if #hits > 1 then util.warn("[info] infopane: \"" .. arg .. "\" could be " .. table.concat(hits, ", ") .. "."); return end
  pin = hits[1]
  rune.session.set(PIN, pin)
  view.request()
  util.say("[info] info pane: pinned to " .. pin
    .. (pick.peek()[pin] ~= nil and "" or ", which has nothing to show yet - it shows when it does")
    .. ". infopane reset to undo.")
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("infopane", "infopane [<name>|reset]", "list what can show in the info pane; <name>: pin one (it shows whenever it has something, beating all but an alert); reset: the normal order again")

return {}
