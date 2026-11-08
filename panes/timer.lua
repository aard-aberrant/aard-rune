-- One countdown timer (tt++ modules/timer.tin).
--   timer <time> <message>  time: 5m30, 5m30s, 5m, 45 or 45s
--   timer / timer check     time left
--   timer clear             cancel it
-- When it runs out the message shows in the main window and the info pane
-- flashes it black on red for FLASH seconds, with a beep (info.alert crit, title
-- TIMER). Nothing
-- shows while it counts down. A running timer survives /reload (rune.store).
-- Not ported: timer repop (not wanted, 2026-11-07).

local util = require("core.util")
local info = require("panes.info")   -- the alert

local say, warn = util.say, util.warn

local FLASH = 10
local KEY = "timer"
local t       -- { ends, msg } while counting down
local due = util.slot()   -- the countdown's end

local function store(v)
  if v then pcall(rune.store.set, KEY, v) else pcall(rune.store.delete, KEY) end
end

local function mmss(secs)
  local m, s = math.floor(secs / 60), secs % 60
  return m > 0 and (m .. "m" .. s .. "s") or (s .. "s")
end

local function fire()
  if not t then return end
  local msg = t.msg
  t = nil
  store(false)
  util.err("[timer] " .. msg)
  info.alert("crit", FLASH, "TIMER", msg)
end

local function start(ends, msg)
  t = { ends = ends, msg = msg }
  store({ ends = ends, msg = msg })
  due.start(math.max(0, ends - os.time()), fire)
end

rune.alias.exact("timer", function(args)
  local text = util.trim(args)
  if text == "" or text == "check" then
    if not t then return say("[timer] none running.") end
    return say("[timer] " .. mmss(math.max(0, t.ends - os.time())) .. " left: " .. t.msg)
  end
  if text == "clear" then
    if not t and not info.alert_clear("TIMER") then return say("[timer] none running.") end
    due.stop()
    t = nil
    store(false)
    info.alert_clear("TIMER")
    return say("[timer] cleared.")
  end
  local when, msg = text:match("^(%S+)%s+(.+)$")
  local secs
  if when then
    local m, s = when:match("^(%d+)m(%d*)s?$")
    if m then secs = tonumber(m) * 60 + (tonumber(s) or 0)
    else secs = tonumber(when:match("^(%d+)s?$")) end
  end
  if not secs or secs <= 0 then
    return warn("[timer] timer <5m30 | 5m | 45> <message>, timer check, timer clear.")
  end
  start(os.time() + secs, msg)
  say("[timer] " .. mmss(secs) .. ": " .. msg)
end)

-- A timer that was running before /reload
local ok, saved = pcall(rune.store.get, KEY)
if ok and type(saved) == "table" and tonumber(saved.ends) and saved.msg then
  start(tonumber(saved.ends), saved.msg)
end

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("timer", "timer [<time> <message> | check | clear]", "one countdown (5m30, 5m, 45s): the message flashes on the info pane when it ends")
