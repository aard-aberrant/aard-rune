-- rh - rest and heal to above 95% HP (tt++ modules/rheal.tin), and the
-- regen ring around sleep.
--   rh        put on the regen ring (from the eq bag), then each second:
--             cast incomplete healing while the tick (game.tick) is
--             6 s or more away, sleep at 2, wake a second after the tick.
--             HP above 95%: the ring(s) it replaced go back on, the regen
--             ring back in the bag
--   rh stop   stop now - the regen ring stays on
--   sleep     the regen ring on, then sleep
-- Waking however you do (GMCP state leaving 9, asleep) with the regen ring
-- on and rh not running: it comes off, what it replaced goes back on (else
-- WAKE_RING), and it goes back in the bag.
-- Driven by GMCP and invmon, no game text: a cast worked when char.vitals
-- shows HP going up within 5 s (HP only rises on a tick or a heal, and rh
-- never casts near a tick); mana down but HP not is a fizzle - cast again;
-- neither moving, or a fight, stops it. Out of mana: stops when mana is
-- below what the last cast cost. What the regen ring replaced is kept in
-- rune.store, so a /reload doesn't lose it.

local util = require("core.util")
local game = require("core.game")       -- HP, mana, state, the tick
local invmon = require("gear.invmon")   -- the regen ring on or off
local eq = require("gear.eq")           -- the eq bag

local say, warn = util.say, util.warn

local REGEN = "3194918450"   -- the regen ring
local WAKE_RING = "flux"     -- put on when what it replaced isn't known
local KEY = "rheal_removed"

local state = "idle"         -- idle, ring, heal, sleep
local gen = 0                -- per run, so old timers stop
local pending                -- a cast out: { at, hp, mana }
local next_at = 0            -- no cast before this
local cost                   -- mana the last cast took

local function hp_pct()
  return game.maxhp and game.maxhp > 0 and game.hp and game.hp * 100 / game.maxhp or 0
end

-- The ring --------------------------------------------------------------

local capture = false        -- what comes off now is what the regen ring replaced
local replaced = {}
do
  local ok, saved = pcall(rune.store.get, KEY)
  if ok and type(saved) == "table" then replaced = saved end
end
local function keep() pcall(rune.store.set, KEY, replaced) end

local wearing_cb             -- waiting for the regen ring to go on

invmon.on(function(action, id)
  if action == 1 and capture and id ~= REGEN then
    replaced[#replaced + 1] = id
    keep()
  elseif action == 2 and id == REGEN and wearing_cb then
    local cb = wearing_cb
    wearing_cb, capture = nil, false
    cb(true)
  end
end)

-- The regen ring on, then cb(ok). Already on: what it replaced is kept
local function regen_on(cb)
  if invmon.where(REGEN) then return cb(true) end
  replaced, capture, wearing_cb = {}, true, cb
  keep()
  rune.timer.after(3, function()
    if wearing_cb == cb then wearing_cb, capture = nil, false; cb(false) end
  end)
  rune.send_raw("get " .. REGEN .. " " .. eq.bag .. "\nwear " .. REGEN)
end

-- The regen ring off and in the bag, what it replaced back on
local function regen_off()
  local cmds = { "remove " .. REGEN }
  if #replaced == 0 then cmds[#cmds + 1] = "wear " .. WAKE_RING end
  for _, id in ipairs(replaced) do cmds[#cmds + 1] = "wear " .. id end
  cmds[#cmds + 1] = "put " .. REGEN .. " " .. eq.bag
  replaced = {}
  keep()
  rune.send_raw(table.concat(cmds, "\n"))
end

-- rh --------------------------------------------------------------------

local last_state             -- GMCP state at the last char.status

local function stop()
  state, pending, gen = "idle", nil, gen + 1
end

local function fail(why)
  stop()
  warn("[rh] stopped - " .. why .. ". The regen ring is still on.")
end

local function finish()
  stop()
  regen_off()
  say(string.format("[rh] done - HP %d%%.", hp_pct()))
end

local function cast()
  if cost and (game.mana or 0) < cost then return fail("out of mana") end
  pending = { at = os.time(), hp = game.hp or 0, mana = game.mana or 0 }
  rune.send_raw("cast 'incomplete healing'")
end

local function second(g)
  if g ~= gen or state == "idle" then return end
  rune.timer.after(1, function() second(g) end)
  if state ~= "heal" then return end
  if game.state == 8 then return fail("you're fighting") end
  local now = os.time()
  if pending then
    if now - pending.at < 5 then return end
    if (game.mana or 0) < pending.mana then   -- mana spent, no heal: a fizzle
      pending, next_at = nil, now
    else
      return fail("no heal after the cast (out of mana?)")
    end
  end
  if hp_pct() > 95 then return finish() end
  local ticks = game.tick
  if ticks and ticks <= 2 then
    state = "sleep"
    return rune.send_raw("sleep")
  end
  if (not ticks or ticks >= 6) and now >= next_at then cast() end
end

-- A cast worked: HP went up. The spell lag comes after - 2 s more
rune.gmcp.on("char.vitals", function()
  if pending and (game.hp or 0) > pending.hp then
    local spent = pending.mana - (game.mana or pending.mana)
    if spent > 0 then cost = spent end
    pending, next_at = nil, os.time() + 2
  end
end, { name = "rheal_vitals" })

-- Asleep at the tick: a second for its heal to count, then wake
rune.gmcp.on("comm.tick", function()
  if state ~= "sleep" then return end
  local g = gen
  rune.timer.after(1, function()
    if g ~= gen or state ~= "sleep" then return end
    last_state = nil   -- rh's own wake - not "you woke up" below
    rune.send_raw("wake")
    if hp_pct() > 95 then return finish() end
    state, next_at = "heal", os.time() + 1
  end)
end, { name = "rheal_tick" })

-- Woke up with the regen ring on, rh not running
rune.gmcp.on("char.status", function()
  local s = game.state
  if last_state == 9 and s ~= 9 and state == "idle" and invmon.where(REGEN) then
    regen_off()
    say("[rh] awake - regen ring off.")
  end
  last_state = s
end, { name = "rheal_woke" })

rune.alias.exact("rh", function(args)
  if util.trim(args) == "stop" then
    if state == "idle" then return say("[rh] not running.") end
    stop()
    return say("[rh] stopped. The regen ring is still on.")
  end
  if state ~= "idle" then return warn("[rh] already running - rh stop to end it.") end
  if game.state == 8 then return warn("[rh] you're fighting - not starting.") end
  stop()
  state = "ring"
  local g = gen
  regen_on(function(ok)
    if g ~= gen then return end
    if not ok then return fail("couldn't put on the regen ring") end
    state = "heal"
    say("[rh] healing to above 95%. rh stop to end.")
    second(g)
  end)
end)

rune.alias.exact("sleep", function()
  regen_on(function() rune.send_raw("sleep") end)
end)
