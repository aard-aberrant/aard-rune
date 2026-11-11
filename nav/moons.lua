-- The three moons (tt++ modules/moons.tin, after Galaban's MUSHclient
-- plugin): the 3MN light on status row 1, an info alert when all three come
-- up, and the moons command.
-- Each moon runs through a cycle of game ticks and is up for its first part:
-- white 60 (up 1-16), black 48 (up 1-13), grey 28 (up 1-8) - tt++'s numbers,
-- measured from its moons-trace log 2026-11-06. Each moon keeps every phase
-- it could still be in (cand). A tick (GMCP comm.tick) moves them all on
-- one; a rise or fall message fixes the phase; a weather reply keeps the
-- phases that agree with it (a moon listed is up, one not listed is down).
-- The game's lines (tt++'s patterns; weather-change messages need the game's
-- noweather config off, which login sets over GMCP):
--   You see the <moon> moon rise in the <east|west>.            phase 1
--   You notice the <moon> moon starting to fall to the <dir>.   last up phase
--   << As the ice age passes, life starts to return to normal.  (reboot:
--      every moon unknown again)
--   weather: The temperature is ... . / wind / sky / blank / one
--      "The <moon> moon is standing in the sky." per moon up / blank
-- Rise, fall and the other weather notices tt++ knew ("It starts to rain a
-- little.", "A ... blows from the <dir>.") are hidden, with the blank after.
-- A reading is owed after login and a reboot, and while a moon is unknown:
-- a quiet weather goes out at login wherever you are, and otherwise when
-- you stand in your home room (outdoors on purpose; nav/travel.lua's
-- home_vnum), not walking, 30 s after the last. Ours is hidden; a weather
-- you type shows, and is read the same. The state survives a /reload.
-- 3MN light (ticks, not minutes; 11 columns so the row doesn't shift):
--   3MN ??        yellow: a reading is owed - type weather outdoors
--   3MN 5t        bright: all three up, ticks left (counting this one)
--   3MN 80t/2t    the next alignment in 80 ticks, lasting 2 - cyan when 4
--                 or fewer away, else dim. "--" while too many phases are
--                 possible to tell (over 30 combinations)
-- Not ported: tt++'s trace log and its edge check (debug aids).
local util = require("core.util")
local theme = require("core.theme")
local colors = require("core.colors")
local mix, bg = colors.mix, colors.bg
-- This module's colors: theme.moon.* - /theme lists them, data/theme.lua
-- changes them (core/theme.lua)
local T = theme.define("moon", "3MN, the moons (status bar)", {
  { "soon",     theme.cyan,                    "a three-moon window soon" },
  { "up",       mix(theme.bold, theme.yellow), "all three up now" },
  { "unknown",  theme.yellow,                  "??: not known yet" },
})
local game = require("core.game")       -- state, room, tick, at login
local tags = require("core.tags")       -- no reading while walking
local status = require("panes.status")  -- the 3MN light (a row1_end slot)
local info = require("panes.info")      -- the all-up alert
local travel = require("nav.travel")    -- home_vnum

-- First: weather messages on at every login (config noweather off) - rises,
-- falls and weather replies are what this reads. init.lua turns them off
-- for everyone at login; this login action is registered after that one,
-- so it runs after it and wins. Its "## Setting ..." reply is hidden, by a
-- trigger that exists only until it comes (or 10 s)
game.on_login(function()
  util.await("exact", "## Setting noweather to off.", function(_, ctx)
    return util.hide(ctx)
  end, "moons_cfg_reply")
  rune.gmcp.send("config noweather off")
end)

local say = util.say

local MOONS = { "white", "grey", "black" }
local LEN = { white = 60, grey = 28, black = 48 }
local UP = { white = 16, grey = 8, black = 13 }
local KEY = "moons"

local cand = {}       -- moon -> { phase, ... }
local set_at = {}     -- moon -> os.time() of its last rise/fall message
local st, ex = {}, {} -- moon -> "up"/"down"/"unk"; exact phase or 0
local wx_at, wx_up, reboot_at, ask_at = 0, "", 0, 0
local owed = true
local allup, setleft = false, -1
local span = { ok = false, lo = -1, hi = -1, len = 0, n = 0 }

local function range(m, a, b)
  local t = {}
  for p = a, b do t[#t + 1] = p end
  cand[m] = t
end

local function reset_all()
  for _, m in ipairs(MOONS) do range(m, 1, LEN[m]); set_at[m] = 0 end
end

-- Ticks after this one before the first of three up phases sets
local function left(w, g, b)
  return math.min(UP.white - w, UP.grey - g, UP.black - b)
end

-- The next 3-moon alignment over every combination of candidates (at most
-- 30): ok, earliest and latest start in ticks from now (0 = now), and how
-- long the earliest lasts. Leapfrogs: while a moon is down, nothing can
-- align before its next rise. None within the joint cycle (1680): none
local function find_span()
  local s = { ok = false, lo = -1, hi = -1, len = 0, n = #cand.white * #cand.grey * #cand.black }
  if s.n > 30 then return s end
  s.ok = true
  for _, cw in ipairs(cand.white) do
    for _, cg in ipairs(cand.grey) do
      for _, cb in ipairs(cand.black) do
        local t, found, qw, qg, qb = 0, nil
        while not found and t <= 1680 do
          qw = (cw - 1 + t) % LEN.white + 1
          qg = (cg - 1 + t) % LEN.grey + 1
          qb = (cb - 1 + t) % LEN.black + 1
          if qw > UP.white then t = t + LEN.white - qw + 1
          elseif qg > UP.grey then t = t + LEN.grey - qg + 1
          elseif qb > UP.black then t = t + LEN.black - qb + 1
          else found = t end
        end
        if not found then s.ok = false; return s end
        if s.lo < 0 or found < s.lo then s.lo, s.len = found, left(qw, qg, qb) + 1 end
        if found > s.hi then s.hi = found end
      end
    end
  end
  return s
end

local function need()
  if owed then return true end
  for _, m in ipairs(MOONS) do if st[m] == "unk" then return true end end
  return false
end

-- "Nm" under an hour, else "HhMM"; something n ticks away (counting the
-- one under way) as "1h20 (161t)"
local function dur(secs)
  local mins = math.ceil(secs / 60)
  if mins < 60 then return mins .. "m" end
  return string.format("%dh%02d", math.floor(mins / 60), mins % 60)
end
local function both(n)
  return dur((game.tick() or 30) + (n - 1) * 30) .. " (" .. n .. "t)"
end

-- After any change: each moon's state and exact phase, all up, the span.
-- A moon with a short candidate list (no longer than its up time) keeps the
-- state it showed until every candidate disagrees; a longer list shows what
-- three quarters of it agree on, else unknown
local function recalc(quiet)
  local was = allup
  local allex = true
  allup = true
  for _, m in ipairs(MOONS) do
    local n, nup = #cand[m], 0
    for _, p in ipairs(cand[m]) do if p <= UP[m] then nup = nup + 1 end end
    if nup == n then
      st[m] = "up"
    else
      allup = false
      local keep = false
      if nup == 0 then st[m], keep = "down", true end
      if nup > 0 and n <= UP[m] and (st[m] == "up" or st[m] == "down") then keep = true end
      if not keep then
        st[m] = nup * 4 >= n * 3 and "up" or (n - nup) * 4 >= n * 3 and "down" or "unk"
      end
    end
    if n == 1 then ex[m] = cand[m][1] else ex[m], allex = 0, false end
  end
  setleft = (allex and allup) and left(ex.white, ex.grey, ex.black) or -1
  span = find_span()
  if allup and not was and not quiet then
    info.alert("warn", 3, "MOONS", setleft >= 0 and ("All three moons are up, for " .. both(setleft + 1))
      or "All three moons are up")
  end
end

-- The state across a /reload ----------------------------------------------

rune.hooks.on("reloading", function()
  pcall(rune.store.set, KEY, { at = os.time(), tick = game.tick(), cand = cand, set_at = set_at,
    st = st, wx_at = wx_at, wx_up = wx_up, reboot_at = reboot_at, ask_at = ask_at,
    owed = owed, allup = allup })
end, { name = "moons_save" })

local ok, saved = pcall(rune.store.get, KEY)
if ok and type(saved) == "table" and saved.cand and os.time() - (saved.at or 0) < 60 then
  cand, set_at, st = saved.cand, saved.set_at or {}, saved.st or {}
  wx_at, wx_up, reboot_at, ask_at = saved.wx_at or 0, saved.wx_up or "", saved.reboot_at or 0, saved.ask_at or 0
  owed, allup = saved.owed, saved.allup
  for _, m in ipairs(MOONS) do set_at[m] = set_at[m] or 0 end
  -- a tick that fell in the reload's gap
  if saved.tick and os.time() - saved.at >= saved.tick then
    for _, m in ipairs(MOONS) do
      for i, p in ipairs(cand[m]) do cand[m][i] = p % LEN[m] + 1 end
    end
  end
else
  reset_all()
end
pcall(rune.store.delete, KEY)
recalc(true)

-- Weather -----------------------------------------------------------------

local queue = {}      -- per weather sent, not answered yet: true = ours, hidden
local cap             -- the reply being read: { state, hdr, seen, bad, quiet, gen }
local line_trig       -- the reply's lines; exists only while one is read
local fail_trig = {}  -- our weather's two failure replies; exist while one is owed

local hide = util.hide

local function fails(on)
  if on and #fail_trig == 0 then
    local function fail(_, ctx)
      local mine = table.remove(queue, 1)
      if #queue == 0 then fails(false) end
      if mine then return hide(ctx) end
    end
    fail_trig[1] = rune.trigger.exact("You need to be outside to check the weather.", fail, { name = "moons_wx_out" })
    fail_trig[2] = rune.trigger.exact("There is no weather to see here.", fail, { name = "moons_wx_none" })
  elseif not on and #fail_trig > 0 then
    for _, t in ipairs(fail_trig) do t:remove() end
    fail_trig = {}
  end
end

-- The reply is over: each moon keeps the candidates that agree; none
-- agree, the tracking was wrong - it starts again from the reading
local function wx_end()
  if line_trig then line_trig:remove(); line_trig = nil end
  local c = cap
  cap = nil
  if not c or c.state ~= "list" or c.bad then return end
  local up = {}
  for _, m in ipairs(MOONS) do
    local keep = {}
    for _, p in ipairs(cand[m]) do
      if (c.seen[m] and p <= UP[m]) or (not c.seen[m] and p > UP[m]) then keep[#keep + 1] = p end
    end
    if #keep > 0 then cand[m] = keep
    elseif c.seen[m] then range(m, 1, UP[m])
    else range(m, UP[m] + 1, LEN[m]) end
    if c.seen[m] then up[#up + 1] = m end
  end
  wx_at, wx_up, owed = os.time(), table.concat(up, " "), false
  recalc()
end

local function on_line(_, ctx)
  local c = cap
  if not c then return end
  local clean = ctx.line:clean()
  local function out() if c.quiet then return false end end
  if clean:match("^%s*$") then
    if c.state == "hdr" then c.state = "list"; return out() end
    local r = out()
    wx_end()
    return r
  end
  if c.state == "hdr" then
    c.hdr = c.hdr + 1
    if c.hdr > 2 then c.bad = true; wx_end(); return end   -- not a weather reply
    return out()
  end
  local m = clean:match("^The (%a+) moon is standing in the sky%.$")
  if m and LEN[m] then c.seen[m] = true; return out() end
  if clean:match("^The %a+ moon ") then c.bad = true; return out() end   -- a wording not known
  wx_end()
end

rune.trigger.regex("^The temperature is .*\\.$", function(_, ctx)
  if cap then return end
  local mine = table.remove(queue, 1)
  if #queue == 0 then fails(false) end
  cap = { state = "hdr", hdr = 0, seen = {}, quiet = mine == true }
  local c = cap
  line_trig = rune.trigger.starts("", on_line, { name = "moons_wx_line", priority = 5 })
  rune.timer.after(1, function() if cap == c then wx_end() end end)
  if c.quiet then return false end
end, { name = "moons_wx_start" })

-- One quiet weather, at most every 10 s
local function ask()
  if os.time() - ask_at < 10 then return end
  ask_at = os.time()
  queue[#queue + 1] = true
  fails(true)
  rune.send_raw("weather")
end

-- A typed weather: its reply shows, and is read
rune.alias.exact("weather", function(args)
  queue[#queue + 1] = false
  fails(true)
  args = util.trim(args)
  rune.send_raw(args ~= "" and ("weather " .. args) or "weather")
end)

-- Owed: at home, standing, not walking, 30 s after the last
local function ready()
  if not need() then return end
  if game.state == 3 and game.room.num == travel.cfg.home_vnum and not tags.walking()
     and os.time() - ask_at >= 30 then
    ask()
  end
end
for _, pkg in ipairs({ "room.info", "char.status" }) do
  rune.gmcp.on(pkg, ready, { name = "moons_ready_" .. pkg })
end

-- Login: a reading owed, one asked for at once
game.on_login(function()
  owed = true
  ask_at = 0
  ask()
end)

-- Ticks, rises, falls, reboots --------------------------------------------

-- GMCP and the game's text aren't ordered, so a moon set in the last 2 s
-- is on this tick already
rune.gmcp.on("comm.tick", function()
  local now = os.time()
  for _, m in ipairs(MOONS) do
    if now - set_at[m] > 2 then
      for i, p in ipairs(cand[m]) do cand[m][i] = p % LEN[m] + 1 end
    end
  end
  recalc()
  ready()
end, { name = "moons_tick" })

local function set(m, p)
  cand[m] = { p }
  set_at[m] = os.time()
  recalc()
end

rune.trigger.regex("^You see the (white|grey|black) moon rise in the (?:east|west)\\.$", function(m, ctx)
  set(m[1], 1)
  return hide(ctx)
end, { name = "moons_rise" })

rune.trigger.regex("^You notice the (white|grey|black) moon starting to fall to the (?:east|west)\\.$", function(m, ctx)
  set(m[1], UP[m[1]])
  return hide(ctx)
end, { name = "moons_fall" })

rune.trigger.regex("^\\s*<< As the ice age passes, life starts to return to normal\\.", function()
  reboot_at, owed = os.time(), true
  reset_all()
  recalc()
end, { name = "moons_ice_age" })

-- The other weather notices (tt++'s; add wordings as they turn up). The
-- wind line has the same shape as one in the weather reply, which shows
rune.trigger.exact("It starts to rain a little.", function(_, ctx) return hide(ctx) end,
  { name = "moons_notice_rain" })
rune.trigger.regex("^A .+ blows from the (?:north|south|east|west|northeast|northwest|southeast|southwest)\\.$",
  function(_, ctx) if not cap then return hide(ctx) end end, { name = "moons_notice_wind" })

-- The 3MN light -----------------------------------------------------------
-- Second in row1_end, after POP: this loads last (a Shaman's module,
-- init.lua), so appending would put it after 2XP 2QP

table.insert(status.row1_end, math.min(2, #status.row1_end + 1), function()
  if need() then return status.field("3MN", "??", 7, T.unknown) end
  if allup then
    return status.field("3MN", setleft >= 0 and ((setleft + 1) .. "t") or "--", 7,
      T.up)
  end
  if not span.ok then return status.field("3MN", "--", 7, theme.unavailable) end
  local soon = span.lo <= 4
  local v = (span.lo > 0 and (math.min(span.lo, 999) .. "t") or "now") .. "/" .. span.len .. "t"
  return status.field("3MN", v, 7, soon and T.soon or theme.muted)
end)

-- The command -------------------------------------------------------------

local function when(n) return n <= 0 and "now" or ("in " .. both(n)) end

rune.alias.exact("moons", function()
  say("[moons]")
  if wx_at > 0 then
    say("  Last weather reading " .. (os.time() - wx_at) .. "s ago: " ..
      (wx_up == "" and "no moons up" or ("up - " .. wx_up)))
  else
    say("  No weather reading yet")
  end
  for _, m in ipairs(MOONS) do
    local name = string.format("%-6s", m)
    local p = ex[m]
    if p > 0 then
      local what = p <= UP[m] and ("up, sets in " .. both(UP[m] - p + 1))
        or ("down, rises in " .. both(LEN[m] - p + 1))
      local note = reboot_at > set_at[m] and ", not confirmed since the reboot" or ""
      say(string.format("  %s %s (phase %d of %d%s)", name, what, p, LEN[m], note))
    else
      local what = st[m] == "up" and "up" or st[m] == "down" and "down" or "up or down"
      if #cand[m] <= 8 then
        say(string.format("  %s %s, phase is one of %s of %d (up is 1-%d)", name, what,
          table.concat(cand[m], " "), LEN[m], UP[m]))
      else
        say(string.format("  %s %s, timing not known (%d possible phases of %d)", name, what, #cand[m], LEN[m]))
      end
    end
  end
  if allup then
    say("  All three moons are up now" .. (setleft >= 0 and (", for " .. both(setleft + 1) .. " more.") or "."))
  elseif span.ok and span.lo == span.hi then
    say(string.format("  Next three moons %s, lasting about %s (%dt).", when(span.lo), dur(span.len * 30), span.len))
  elseif span.ok then
    say("  Next three moons: earliest " .. when(span.lo) .. ", latest " .. when(span.hi) .. ".")
  else
    say("  Next three moons: not known yet (" .. span.n .. " possible combinations of phases, at most 30 are"
      .. " worked out). A rise or fall message fixes a moon's phase, and each weather narrows it.")
  end
  if need() then say("  A reading is owed - type weather outdoors, or it's taken next time you're home.") end
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("moons", "moons", "each moon's state and timing, and when all three are next up")
help.add("weather", "weather [args]", "the game's weather; its reply also sets the moons")
