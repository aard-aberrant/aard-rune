-- Alerts (require("modules.alerts")) - data only: the info pane
-- (panes/info.lua) flashes them.
--   alerts.alert("crit"|"warn", secs, TITLE, text)   up for secs seconds
--   alerts.clear(TITLE)                              taken off; true if it was up
-- A crit beeps. A second alert with the same title replaces the text of
-- the first. Within a level they play in turn, one published at a time.
-- An alert's seconds count only while it is on the pane (data info.shown,
-- the info pane's pick: "alert_crit" / "alert_warn"), so a crit covering a
-- warn doesn't eat the warn's time; no info pane: they always count. The
-- 1 s timer runs only while one is up.
local util = require("lib.util")
local view = require("ui.view")

local alerts = {}

local A = view.provides("aard.alerts", "alerts: a title and text, crit or warn", {
  ["alert.crit.title"] = { "text", "the crit alert's title (TIMER); nil: none" },
  ["alert.crit.text"]  = { "text", "its text" },
  ["alert.warn.title"] = { "text", "the warn alert's title (2XP, MOONS); nil: none" },
  ["alert.warn.text"]  = { "text", "its text" },
})

local queue = { crit = {}, warn = {} }   -- level -> list of { title, text, left }
local ticking = false

local function publish()
  for lvl, q in pairs(queue) do
    A.set("alert." .. lvl .. ".title", q[1] and q[1].title)
    A.set("alert." .. lvl .. ".text", q[1] and q[1].text)
  end
  A.publish()
end

local function tick()
  -- count down only the alert on the pane (any, when nothing says)
  local known = view.data("info.shown") ~= nil
  local shown = known and view.get("info.shown")
  for lvl, q in pairs(queue) do
    if q[1] and (not known or shown == "alert_" .. lvl) then
      q[1].left = q[1].left - 1
      if q[1].left <= 0 then table.remove(q, 1) end
    end
  end
  publish()
  if queue.crit[1] or queue.warn[1] then
    rune.timer.after(1, tick)
  else
    ticking = false
  end
end

function alerts.alert(lvl, secs, title, text)
  local q = queue[lvl]
  for _, a in ipairs(q) do
    if a.title == title then a.text = text; publish(); return end
  end
  q[#q + 1] = { title = title, text = text, left = secs }
  if lvl == "crit" then util.beep() end
  publish()
  if not ticking then
    ticking = true
    rune.timer.after(1, tick)
  end
end

function alerts.clear(title)
  for _, q in pairs(queue) do
    for i, a in ipairs(q) do
      if a.title == title then table.remove(q, i); publish(); return true end
    end
  end
  return false
end

return alerts
