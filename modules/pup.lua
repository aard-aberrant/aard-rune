-- Powerup pace (tt++ modules/pups.tin, reworked 2026-11-08): always on, on
-- status row 1 after DPS:
--   PUP 23s / 25s (104)
-- the last gap between two pups, the session's average gap (underlined),
-- and how many gaps the average is over. Dim once the last pup is over a
-- minute old (the session is over); it stays until the next session's
-- first gap replaces it.
-- A session: the first pup is only the baseline; each pup after it within
-- 60 s of the one before adds its gap. A gap over 60 s ends the session -
-- that gap isn't counted - and that pup is the next session's baseline.
--   pup     the sessions, newest first: start, length, pups, average - the
--           one under way first, then the last 5 from the log
--   log     each session, once it's over (61 s with no pup, a /reload, a
--           disconnect), one line in pup.log (util.state_dir:
--           ~/.local/state/rune), tab-separated: start, seconds, pups,
--           average gap
-- The game's line (tt++'s pattern, seen live 2026-11-08):
--   Congratulations, <name>. You have increased your powerups to <n>.
-- Matched anywhere in the line, not only at its start (a starts match
-- never fired live, 2026-11-08 - what came before it isn't known yet).
-- Cost: one literal trigger (contains); the row's
-- segment is a few string operations each redraw.
local util = require("lib.util")

local GAP = 60   -- seconds: a longer gap ends the session

local prev            -- os.time() of the last pup
local sess            -- the latest session: { start, last, n, ends, logged }
local LOG = "pup.log"
local over = util.slot()   -- fires GAP + 1 s after a counted pup: the session is over

local function avg(s) return math.floor((s.ends - s.start) / s.n + 0.5) end
local function live() return prev and os.time() - prev <= GAP end

-- Published (ui/view.lua): the latest session's numbers, and whether it
-- runs on (its last pup the latest, under GAP s ago - from the clock)
local view = require("ui.view")
local P = view.provides("aard.pup", "your powerup pace", {
  ["pup.last"] = { "seconds", "the latest session's last gap" },
  ["pup.avg"]  = { "seconds", "the latest session's average gap, whole" },
  ["pup.n"]    = { "number", "pups in the latest session" },
  ["pup.live"] = { "boolean", "the latest session runs on", time = true,
                   get = function() return sess ~= nil and sess.ends == prev and live() or false end },
})
local touch_live = P.toucher("pup.live")

local function log_it()
  if not sess or sess.logged then return end
  sess.logged = true
  util.append_log(LOG, table.concat({ os.date("%Y-%m-%d %H:%M:%S", sess.start), sess.ends - sess.start,
    sess.n, avg(sess) }, "\t"), "[pup]")
end
rune.hooks.on("reloading", log_it, { name = "pup_log_reload" })
rune.hooks.on("disconnected", log_it, { name = "pup_log_disconnect" })

-- debug pup: each line the trigger takes, as it came
local dbg = require("lib.debug").topic("pup", "each powerup line, and the gap it adds")

rune.trigger.contains("You have increased your powerups to ", function(_, ctx)
  if dbg.on then dbg.log(ctx.line:clean()) end
  local now = os.time()
  local gap = prev and now - prev
  prev = now
  touch_live()
  if not gap or gap > GAP then P.publish(); return end   -- the baseline (a new one dims the row)
  if not sess or sess.ends ~= now - gap then   -- the first gap of a new session
    log_it()
    sess = { start = now - gap, n = 0 }
  end
  sess.n, sess.last, sess.ends = sess.n + 1, gap, now
  over.start(GAP + 1, log_it)
  if dbg.on then dbg.log("gap " .. gap .. "s, " .. sess.n .. " in this session") end
  P.set("pup.last", sess.last); P.set("pup.avg", avg(sess)); P.set("pup.n", sess.n)
  P.publish()
end, { name = "pup_line" })

-- PUP on the status row: panes/status.lua

local clock = util.clock

rune.alias.exact("pup", function()
  local list = {}
  if sess and not sess.logged then
    list[1] = { when = os.date("%Y-%m-%d %H:%M", sess.start), secs = sess.ends - sess.start, n = sess.n,
                avg = avg(sess), now = true }
  end
  for _, line in ipairs(util.log_tail(LOG, 5)) do
    local when, t, n, a = line:match("^(%d+%-%d+%-%d+ %d+:%d+):%d+\t(%d+)\t(%d+)\t(%d+)$")
    if when then list[#list + 1] = { when = when, secs = tonumber(t), n = tonumber(n), avg = tonumber(a) } end
  end
  if not list[1] then util.say("[pup] no sessions yet - two pups within a minute start one."); return end
  util.say("[pup] sessions, newest first:")
  for _, s in ipairs(list) do
    rune.echo(string.format("  %s  %6s  %4d pup%s  %3ds avg%s", s.when, clock(s.secs), s.n,
      s.n == 1 and " " or "s", s.avg, s.now and "  (on now)" or ""))
  end
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("pup", "pup", "powerup sessions, newest first: start, length, pups, average gap (logged to ~/.local/state/rune/pup.log; status row 1 shows the current one)")
