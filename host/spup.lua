-- Hosting spellups (tt++ modules/spuphost.tin).
--   spup on       a session: walk to Muranooyashiro (ROOM, north and up from
--                 recall), su + vis, gossip on, announce, then everyone who
--                 smiles at you is queued once and done in turn. Last call
--                 after 2 minutes, done 30 s after that (each once nobody is
--                 waiting), 10 s later gossip back off if spup turned it on,
--                 then g (home, gulp, bank). A walk that never arrives, or
--                 spup off before the announcement, leaves you where you are
--   spup off      end now: the queue is cleared, the one being done is
--                 finished, then the done gossip
--   spup resume   carry on after running out of mana potions
--   spup          the phase, who's waiting, about how long until it's over
--   spup test [off]  test mode, on at every load: the three gossips are
--                 only shown here, not sent (the channel is still toggled)
--   spn           spellup next: a fresh look; sitting: cast cancel (at most
--                 CANCEL_MAX, until one of its three ending lines); then
--                 spellup <name> and smile <name>
--   spq [clear]   the queue, or empty it
-- Before each person: su + vis (so you're up yourself), and under 20% mana
-- qs until 60% ("You do not have that item." pauses: spup resume).
-- Game text, all of it (tt++'s patterns; cancel's "The magic on X cannot
-- be cancelled." confirmed live there). Each reader exists only while it's
-- waiting - added, then removed:
--   <Name> smiles at you.                        queued (session only)
--   {roomchars} ... <Name> ... is sitting here. {/roomchars}   spn's look
--   <Name> is not affected by any spells.        cancel's three ends
--   The magic on <Name> cannot be cancelled.
--   <Name> is not affected by anything that can be cancelled.
--   Turning ON/OFF the gossip channel.           gossip's toggle (hidden),
--   You can also turn off a channel temporarily...  after OFF (hidden)
-- The greeting goes by the game's clock, US Eastern - taken as EST (UTC-5)
-- all year: morning 2-12, afternoon 12-18, else evening.
-- These gossips are the only channel messages a script here sends - only
-- because you typed spup on.
local util = require("core.util")
local game = require("core.game")      -- name, mana, room
local tags = require("core.tags")      -- spn's look: the room's people
local travel = require("nav.travel")   -- the walk there

local say, warn, trim = util.say, util.warn, util.trim

local ROOM = 15852
local CANCEL_MAX = 5
local LOW, FULL = 20, 60     -- mana %: qs below LOW, until FULL

local test = true
local queue, cur = {}, nil   -- names in arrival order; the one being done
local S = { on = false, phase = nil, paused = false, quaffing = false,
            gos_changed = false, tod = "day", due = 0 }
-- phase: walk, gossip, run, last, ending

local function me() return game.name or "me" end
local function mana_pct()
  if not (game.mana and game.maxmana and game.maxmana > 0) then return 100 end
  return game.mana * 100 / game.maxmana
end

-- A gossip, with Aardwolf's color codes as written (@Y bright yellow, @G
-- bright green, @r dark red, @w back to white - a guess that white is
-- what follows in a gossip). Test mode shows it in those colors
local function gossip(msg)
  if test then say("[spup test] would gossip: "); rune.echo("  " .. util.aard_ansi(msg))
  else rune.send_raw("gossip " .. msg) end
end

-- A session timer: cancelled when the session ends (or a new one starts)
local session_timers = {}
local function later(secs, fn)
  local h
  h = rune.timer.after(secs, function() session_timers[h] = nil; fn() end)
  session_timers[h] = true
end
local function cancel_session_timers()
  for h in pairs(session_timers) do h:cancel() end
  session_timers = {}
end

-- A temporary catch-all: fn(clean, ctx) sees every line until stop()
local function reader(fn, name)
  local t
  t = rune.trigger.starts("", function(_, ctx) return fn(ctx.line:clean(), ctx) end,
    { name = name, priority = 5 })
  return function() if t then t:remove(); t = nil end end
end

local drain   -- below

-- The queue ---------------------------------------------------------------

local function queued(name)
  for _, n in ipairs(queue) do if n == name then return true end end
  return false
end

local smile_trig
local function smiles(on)
  if on and not smile_trig then
    smile_trig = rune.trigger.contains(" smiles at you.", function(_, ctx)
      local name = ctx.line:clean():match("^(%a+) smiles at you%.$")
      if not name or name == cur or queued(name) then return end
      queue[#queue + 1] = name
      say("[spellups] " .. name .. " queued - " .. #queue .. " waiting.")
      drain()
    end, { name = "spup_smile" })
  elseif not on and smile_trig then
    smile_trig:remove(); smile_trig = nil
  end
end

rune.alias.exact("spq", function(args)
  if trim(args) == "clear" then
    queue = {}
    return say("[spellups] queue cleared.")
  end
  if #queue == 0 then return say("[spellups] nobody queued.") end
  say("[spellups] queue:")
  for i, n in ipairs(queue) do rune.echo("  " .. i .. ". " .. n) end
end)

-- spn ---------------------------------------------------------------------

local function finish()
  rune.send_raw("spellup " .. cur .. "\nsmile " .. cur)
  cur = nil
  say("[spellups] done - " .. #queue .. " still waiting.")
  later(1, drain)
end

-- Cancel: one cast, then 4 s for an ending line; none - cast again
local cancel_n, stop_cancel = 0, nil
local cancel_wait = util.slot()
local function cancel_done()
  cancel_wait.stop()
  if stop_cancel then stop_cancel(); stop_cancel = nil end
  finish()
end
local function cancel_try()
  if cancel_n >= CANCEL_MAX then return cancel_done() end
  cancel_n = cancel_n + 1
  rune.send_raw("cast 'cancel' " .. cur)
  cancel_wait.start(4, cancel_try)
end
local function cancel_start()
  cancel_n = 0
  local lc = cur:lower()
  stop_cancel = reader(function(clean)
    local who = clean:match("^(%a+) is not affected by any spells%.$")
      or clean:match("^The magic on (%a+) cannot be cancelled%.$")
      or clean:match("^(%a+) is not affected by anything that can be cancelled%.$")
    if who and who:lower() == lc then cancel_done() end
  end, "spup_cancel")
  cancel_try()
end

-- spn's look: the room's people, between {roomchars} and {/roomchars}. A
-- long entry can wrap ("<name> ... is" / "sitting here."), so the lines
-- are joined and split again at each "here."
local look_wait, chars, stop_chars = false, nil, nil
local look_timeout = util.slot()
local function sitting(name, text)
  for entry in (text .. " "):gmatch("(.-here%.)") do
    if entry:find(name, 1, true) and entry:find("is sitting here%.$") then return true end
  end
  return false
end
local function after_look()
  look_wait = false
  look_timeout.stop()
  if stop_chars then stop_chars(); stop_chars = nil end
  local text = table.concat(chars or {}, " ")
  chars = nil
  if sitting(cur, text) then cancel_start() else finish() end
end
tags.on("roomchars", function(rest)
  if not look_wait then return end
  chars = { rest }
  if stop_chars then stop_chars() end
  stop_chars = reader(function(clean)
    if not clean:find("^{") then chars[#chars + 1] = util.strip(clean) end
  end, "spup_chars")
end)
tags.on("/roomchars", function()
  if look_wait and chars then after_look() end
end)

local function spn()
  if cur then return warn("[spellups] still working on " .. cur .. ".") end
  if #queue == 0 then return say("[spellups] nobody queued.") end
  cur = table.remove(queue, 1)
  look_wait = true
  rune.send_raw("look")
  look_timeout.start(30, function() if look_wait then after_look() end end)
end
rune.alias.exact("spn", function() spn() end)

-- The session ---------------------------------------------------------------

-- Gossip toggles: send it, read which way it went (hidden); the wrong way
-- means it was that way already - once more. Only a first toggle on is
-- spup's change. then() runs when the channel is the way wanted
local stop_gos
local function gossip_set(want, then_fn)
  if stop_gos then stop_gos() end
  local second = false
  local function done(ctx)
    stop_gos(); stop_gos = nil
    util.eat_blanks(ctx.line:clean())
    if then_fn then then_fn(second) end
  end
  stop_gos = reader(function(clean, ctx)
    local way = clean:match("^Turning (%u+) the gossip channel%.$")
    if way then
      way = way:lower()
      if way ~= want and not second then
        second = true
        rune.send_raw("gossip")
      elseif way == want and want == "on" then
        done(ctx)
      end
      return false
    end
    if clean:find("^You can also turn off a channel temporarily") then
      if want == "off" then done(ctx) end
      return false
    end
  end, "spup_gossip")
  -- not a session timer: the off toggle is sent as the session ends
  rune.timer.after(10, function() if stop_gos then stop_gos(); stop_gos = nil end end)
  rune.send_raw("gossip")
end

local clock = util.slot()   -- the session's next step
local function at(secs, fn)
  S.due = os.time() + secs
  clock.start(secs, fn)
end

local function idle() return #queue == 0 and not cur and not S.quaffing end

local stop_qs   -- below
local function session_end()
  cancel_session_timers()
  clock.stop()
  S.on, S.phase, S.paused, S.quaffing = false, nil, false, false
  smiles(false)
  if stop_qs then stop_qs() end
  say("[spup] session over.")
end

local function wind_down()
  if S.phase ~= "ending" then return end
  if S.gos_changed then gossip_set("off") end
  session_end()
  rune.send("g")
end

local function done()
  S.phase = "ending"
  smiles(false)
  gossip("Spellups done for the moment. Have a good " .. S.tod .. "!")
  at(10, wind_down)
end

local function check_done()
  if S.phase ~= "last" then return end
  if idle() then done() else at(30, check_done) end
end

local function check_last()
  if S.phase ~= "run" then return end
  if idle() then
    gossip("Last call for spellups in the @r-=Masaki=-@w clan hall, n u from recall. I don't know you're here if you don't smile at me ('@Gsmile "
      .. me() .. "@w').")
    S.phase = "last"
    at(30, check_done)
  else
    at(30, check_last)
  end
end

local function open()
  if S.phase ~= "gossip" then return end
  S.phase = "run"
  local h = tonumber(os.date("!%H", os.time() - 5 * 3600))
  S.tod = (h >= 2 and h < 12) and "morning" or (h >= 12 and h < 18) and "afternoon" or "evening"
  gossip("Good " .. S.tod .. "! Spellups in the @r-=Masaki=-@w clan hall (n u from recall) for the next couple of minutes. "
    .. "Sit for cancel, smile at me when ready. @YYou MUST@w '@Gsmile " .. me() .. "@w'.")
  at(120, check_last)
  drain()
end

local function arrived()
  S.phase = "gossip"
  rune.send("su")
  rune.send_raw("vis")
  gossip_set("on", function(second)
    S.gos_changed = not second
    open()
  end)
end

-- qs, then a look at mana 2 s later: under FULL another, else on
local function quaff()
  S.quaffing = true
  if not stop_qs then
    local t = rune.trigger.exact("You do not have that item.", function()
      S.quaffing, S.paused = false, true
      stop_qs()
      warn("[spup] out of mana potions - paused, the queue is kept. Get more, then spup resume.")
    end, { name = "spup_qs" })
    stop_qs = function() t:remove(); stop_qs = nil end
  end
  rune.send("qs")
  later(2, function()
    if not S.quaffing then return end
    if mana_pct() < FULL then return quaff() end
    S.quaffing = false
    if stop_qs then stop_qs() end
    drain()
  end)
end

function drain()
  if not S.on or not (S.phase == "run" or S.phase == "last") then return end
  if S.paused or S.quaffing or cur or #queue == 0 then return end
  if mana_pct() < LOW then return quaff() end
  rune.send("su")
  rune.send_raw("vis")
  spn()
end

local walk_hook
local function start()
  if S.on then return warn("[spup] already on.") end
  cancel_session_timers()
  S.on, S.phase, S.paused, S.quaffing, S.gos_changed = true, "walk", false, false, false
  queue = {}
  smiles(true)
  if game.room and game.room.num == ROOM then return arrived() end
  say("[spup] heading to Muranooyashiro.")
  walk_hook = true
  later(30, function()
    if S.phase == "walk" then
      walk_hook = false
      warn("[spup] didn't reach Muranooyashiro (" .. ROOM .. ") - stopped, nothing announced.")
      session_end()
    end
  end)
  travel.go_vnum(ROOM, "Muranooyashiro")
end
rune.gmcp.on("room.info", function()
  if walk_hook and S.phase == "walk" and game.room.num == ROOM then
    walk_hook = false
    arrived()
  end
end, { name = "spup_walk" })

local function stop()
  if not S.on then return say("[spup] not on.") end
  queue = {}
  if S.phase == "run" or S.phase == "last" then return done() end
  if S.phase == "ending" then return end
  walk_hook = false
  if S.gos_changed then gossip_set("off") end
  session_end()
end

local function status()
  local left = math.max(S.due - os.time(), 0)
  if S.phase == "run" then left = left + 40
  elseif S.phase == "last" then left = left + 10
  elseif S.phase ~= "ending" then left = 160 end
  local t = string.format("%d:%02d", math.floor(left / 60), left % 60)
  if #queue > 0 then
    say("[spup] on (" .. S.phase .. ") - " .. #queue .. " waiting - over in about " .. t .. " once they're done.")
  else
    say("[spup] on (" .. S.phase .. ") - nobody waiting - over in about " .. t .. ".")
  end
end

rune.alias.exact("spup", function(args)
  local a, b = trim(args):match("^(%S*)%s*(%S*)")
  if a == "on" then return start() end
  if a == "off" then return stop() end
  if a == "resume" then
    if not S.paused then return say("[spup] not paused.") end
    S.paused = false
    say("[spup] resumed.")
    return drain()
  end
  if a == "test" then
    test = b ~= "off"
    if test then return say("[spup] test mode on - gossips are only shown here.") end
    return warn("[spup] test mode off - gossips are sent for real.")
  end
  if S.on then return status() end
  say("[spup] off. spup on starts a session.")
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("spup", "spup [on | off | resume | test [off]]", "a spellup session at Muranooyashiro: walk, announce, spell up everyone who smiles; bare: its state; test: gossips only shown")
help.add("spn", "spn", "spellup next: the first in the queue")
help.add("spq", "spq [clear]", "the spellup queue, or empty it")
