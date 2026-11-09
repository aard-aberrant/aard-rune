-- Double XP / double QP (tt++ modules/doubles.tin): the 2XP and 2QP lights
-- at the end of status row 1 (init.lua loads this after fight/pup) -
-- "2XP 15" bright yellow / "2QP 15" bright red
-- with minutes left (rounded up), a dim label when off, always 6 columns.
-- A bonus going from off to on flashes the info pane yellow for FLASH s
-- (info.alert warn, titles 2XP / 2QP). The end times are kept in
-- rune.session, so a /reload keeps the lights and its resync doesn't flash.
--   double    the game's command; its reply also sets both lights
-- At login (and /reload) a hidden double resyncs both.
-- There's no GMCP for this - game text (tt++'s patterns; seen in its logs
-- unless marked):
--   For the next 15 minutes experience is doubled in honor of the new superhero.
--   Double experience for 10 minutes courtesy of Daimyo.
--   [ N minutes of double exp started courtesy of ... ]       (not in a log)
--   Aardwolf rejoices in the death of another MILLION monsters.  60 min (not in a log)
--   INFO: 5 minutes of bonus experience remaining.  /  INFO: 1 minute of ...
--   INFO: Bonus experience has now expired.
--   INFO: Double experience is running ... - N minutes left.  (not in a log)
--   INFO: N minutes of double quest points remaining.         (not in a log)
--   INFO: Double quest points bonus is running ... - N minutes left. (not in a log)
--   INFO: Double quest points bonus has now expired.          (not in a log)
-- INFO lines came as text in tt++'s logs; in case they come as the GMCP info
-- channel here, comm.channel's are read too (unverified).
-- The double reply, as logged:
--   Double exp will expire in roughly 3 minutes.
--   Double exp is running in honor of Rimondo reaching superhero.
-- and, tt++'s guesses: "Double exp is not currently running.", "Double
-- quest points will expire in roughly N minute(s).", "Double QP is not
-- currently running." The reply is read as every line starting "Double "
-- up to the first that doesn't (hidden only for ours, with the blank after).
local util = require("core.util")
local game = require("core.game")      -- on_login
local status = require("panes.status") -- the lights (row1_end slots, last)
local info = require("panes.info")     -- the flash

local FLASH = 3
local MINS = { dxp = "Double experience for %d minutes", dqp = "Double quest points for %d minutes" }
local TITLE = { dxp = "2XP", dqp = "2QP" }

local function load(k) return tonumber(rune.session.get(k) or "") or 0 end
local ends = { dxp = load("dxp_until"), dqp = load("dqp_until") }

local function set(k, mins)
  local now = os.time()
  if mins > 0 and ends[k] <= now then info.alert("warn", FLASH, TITLE[k], string.format(MINS[k], mins)) end
  ends[k] = mins > 0 and now + mins * 60 or 0
  rune.session.set(k .. "_until", tostring(ends[k]))
  rune.ui.refresh_bars()
end

-- The lights ---------------------------------------------------------------

local function light(k, label, style)
  return function()
    local left = ends[k] - os.time()
    if left <= 0 then return rune.style.gray(label) .. "   " end
    return style(string.format("%s %-2d", label, math.ceil(left / 60)))
  end
end
-- 24-bit, as tt++'s <FFFFF00> / <FFF0000>
local function rgb(r, g, b) return function(t) return string.format("\27[38;2;%d;%d;%dm", r, g, b) .. t .. "\27[0m" end end
table.insert(status.row1_end, light("dxp", "2XP", rgb(255, 255, 0)))
table.insert(status.row1_end, light("dqp", "2QP", rgb(255, 0, 0)))

-- The game's lines -------------------------------------------------------------

local function n(s) return tonumber(s) end

rune.trigger.starts("For the next ", function(_, ctx)
  local c = ctx.line:clean()
  local m = c:match("^For the next (%d+) minutes")
  if m and c:find("experience is doubled", 1, true) then set("dxp", n(m)) end
end, { name = "doubles_superhero" })

rune.trigger.starts("Double experience for ", function(_, ctx)
  local m = ctx.line:clean():match("^Double experience for (%d+) minutes courtesy of")
  if m then set("dxp", n(m)) end
end, { name = "doubles_courtesy" })

rune.trigger.contains(" minutes of double exp started courtesy of", function(_, ctx)
  local m = ctx.line:clean():match("^%[%s*(%d+) minutes of double exp started")
  if m then set("dxp", n(m)) end
end, { name = "doubles_started" })

rune.trigger.exact("Aardwolf rejoices in the death of another MILLION monsters.", function()
  set("dxp", 60)
end, { name = "doubles_million" })

local function info_line(c)
  local m = c:match("^INFO: (%d+) minutes? of bonus experience remaining%.")
    or c:match("^INFO: Double experience is running .- %- (%d+) minutes left%.")
  if m then return set("dxp", n(m)) end
  if c:find("^INFO: Bonus experience has now expired%.") then return set("dxp", 0) end
  m = c:match("^INFO: (%d+) minutes? of double quest points remaining%.")
    or c:match("^INFO: Double quest points bonus is running .- %- (%d+) minutes left%.")
  if m then return set("dqp", n(m)) end
  if c:find("^INFO: Double quest points bonus has now expired%.") then return set("dqp", 0) end
end
rune.trigger.starts("INFO: ", function(_, ctx) info_line(ctx.line:clean()) end, { name = "doubles_info" })
rune.gmcp.on("comm.channel", function(d)
  if type(d) == "table" and d.chan == "info" and d.msg then info_line(util.uncolor(util.strip(d.msg))) end
end, { name = "doubles_info_chan" })

-- double: the reply, read while it's expected ---------------------------------

local q = {}         -- per double sent, not answered yet: true = hide
local reader = nil

local function reply_line(c)
  local m = c:match("^Double exp will expire in roughly (%d+) minute")
  if m then return set("dxp", n(m)) end
  if c:find("^Double exp is not currently running") then return set("dxp", 0) end
  m = c:match("^Double quest points will expire in roughly (%d+) minute")
    or c:match("^Double QP will expire in roughly (%d+) minute")
  if m then return set("dqp", n(m)) end
  if c:find("^Double QP is not currently running") or c:find("^Double quest points is not currently running") then
    return set("dqp", 0)
  end
end

local reader_timeout = util.slot()
local function stop()
  if reader then reader:remove(); reader = nil end
  reader_timeout.stop()
end

local function send(hidden)
  q[#q + 1] = hidden
  if not reader then
    local seen = false
    reader = rune.trigger.starts("", function(_, ctx)
      local c = ctx.line:clean()
      -- "in honor of <name> reaching superhero." / "courtesy of ...": a
      -- "running" line's wrapped end (tt++'s note)
      if c:find("^Double ") or (seen and (c:find("^in honor of ") or c:find("^courtesy of "))) then
        seen = true
        reply_line(c)
        if q[1] then return false end
        return
      end
      if not seen then return end
      -- the reply is over
      local hid = table.remove(q, 1)
      seen = false
      if #q == 0 then stop() end
      if hid and util.blank(c) then util.eat_blanks(c); return false end
    end, { name = "doubles_reply", priority = 5 })
    reader_timeout.start(15, function() q = {}; stop() end)
  end
  rune.send_raw("double")
end

rune.alias.exact("double", function() send(false) end)
game.on_login(function() send(true) end)

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("double", "double", "the game's double; its reply also sets the 2XP and 2QP lights")
