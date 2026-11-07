-- qx: go to the quest target (tt++ modules/quest.tin's qx). Makes the quest
-- mob the target - name, area and room, as the quest gives them - and goes
-- (target.go): to its area, then on a second qx to its room. The room is
-- the quest's own, never where's (a same-named mob may answer). The
-- keyword k needs is found by targets/target.lua's check on arriving in the area.
-- The quest comes from GMCP comm.quest: "start" (and the "status" reply on
-- a reload) gives targ (the mob), room and area (the full name, "The
-- Amazon Nation" - matched to a zone in data/areas.lua). The mob dying, or
-- the quest ending, drops the target - only if qx set it.
-- Also the quest's view on the info pane (row, below), QST on the status
-- pane, qc, and tt++'s line for each quest event (comm.quest action):
--   start    [Quest Requested]: Target=a rogue. Room=Hall. Area=The Amazon Nation.
--   comp     [Quest Completed] [Qp: 34] 412 secs [Bonus: 2 prac, 1 train, 1 tp]
--   timeout  {-=Quest Timed Out=-}
--   fail     {-=Quest Failed=-}
--   ready    {-=Quest Time=-}, with the terminal bell
-- comp's time is from the quest's start, kept in rune.store so a /reload
-- doesn't lose it.

local util = require("core.util")
local status = require("panes.status")   -- QST, in a row-1 slot
local info = require("panes.info")       -- the quest's rows
local target = require("targets.target")   -- qx sets it, a kill or the end drops it
local travel = require("nav.travel")   -- qx goes; an area's zone from its name
local soh = require("targets.soh")     -- a School of Horror mob's keyword, on its row

local warn = util.warn

local q   -- { targ, room, area, ends, killed } while on a quest
local START_KEY = "quest_start"   -- os.time() the quest began
local tick = util.slot()   -- the info row's minute redraw

-- The info pane (panes/info.lua), priority 50: time left (red under 5 minutes, or
-- "killed, return to QM"), area, room, mob. Redrawn each minute
local CYAN, RED = "\27[36m", "\27[31m"
local function row()
  if not q then return info.set("quest", 50, nil) end
  local first
  if q.killed then
    first = RED .. "killed, return to QM"
  else
    local left = math.max(0, math.ceil((q.ends - os.time()) / 60))
    first = (left < 5 and RED or CYAN) .. left .. "m left"
  end
  info.set("quest", 50, info.target_rows(first, q.area, q.room, soh.label(q.targ, travel.zone_of(q.area))))
end

local function minutely()
  if not q or q.killed then return end
  row()
  local wait = (q.ends - os.time()) % 60
  tick.start(wait > 0 and wait or 60, minutely)
end

-- QST (tt++ quest.tin), status row 1: minutes until you can quest again
-- (red under 3), RD when you can, AC on a quest (red once the game warns
-- time is running out); "--" until known - asked for at load and each tick.
-- From comm.quest: "status" is the reply to "request quest" - on a quest
-- (its target alive - targ - or dead - target = "killed"), ready, or a
-- wait in minutes. The wait comes in whole minutes, so one number is only
-- good to a minute (seen live: the game was ready while QST still showed
-- 1). So during a wait "request quest" goes out each tick (GMCP, nothing
-- shows): when the answer drops (3 to 2), a minute has just turned, and the
-- countdown is reset from it - good to a tick. The game's "ready" wins
local qst = { state = nil, ready_at = 0, warn = false, last = nil }   -- state: nil, "wait", "ready", "active"
local QST_RD = "\27[30;42mRD\27[0m"              -- black on green
local QST_AC = "\27[38;2;255;204;170mAC\27[0m"   -- peach

table.insert(status.row1, function()
  if qst.state == "wait" then
    local mins = math.ceil((qst.ready_at - os.time()) / 60)
    if mins <= 0 then qst.state = "ready"
    else return status.field("QST", mins, 2, mins < 3 and rune.style.red or nil) end
  end
  if qst.state == "ready" then return "QST " .. QST_RD end
  if qst.state == "active" then return "QST " .. (qst.warn and rune.style.red("AC") or QST_AC) end
  return status.field("QST", "--", 2)
end)

local function qst_update(d)
  local function wait(m, polled)
    m = tonumber(m) or 0
    qst.warn = false
    if m <= 0 then qst.state, qst.last = "ready", nil; return end
    local at = os.time() + m * 60
    -- No drop since the last answer: it can only bring the estimate forward
    if polled and qst.state == "wait" and not (qst.last and m < qst.last) then
      at = math.min(at, qst.ready_at)
    end
    qst.state, qst.ready_at, qst.last = "wait", at, m
  end
  local a = d.action
  if a == "start" then
    qst.state, qst.warn = "active", false
  elseif a == "warning" then
    qst.warn = true
  elseif a == "timeout" or a == "fail" or a == "comp" then
    wait(d.wait)
  elseif a == "ready" then   -- the game's word wins over our countdown (seen live: it came at 1)
    wait(0)
  elseif a == "status" then
    if ((d.targ or "") ~= "" and d.targ ~= "killed") or d.target == "killed" then
      qst.state = "active"
    elseif d.status == "ready" then
      wait(0)
    elseif d.wait then
      wait(d.wait, true)
    end
  end
  status.draw()
end

rune.gmcp.on("comm.tick", function()
  if not qst.state or qst.state == "wait" then rune.gmcp.send("request quest") end
end, { name = "quest_tick" })

-- The event lines (tt++ quest.tin, its colours: red brackets and numbers,
-- yellow words, white labels)
local R, Y, W, X = "\27[31m", "\27[33m", "\27[37m", "\27[0m"
local function banner(text) rune.echo(W .. "{-=" .. R .. text .. W .. "=-}" .. X) end

local function started(d)
  rune.echo(Y .. "[" .. R .. "Quest Requested" .. Y .. "]" .. X .. ": "
    .. Y .. "Target" .. X .. "=" .. R .. (d.targ or "?") .. X .. ". "
    .. Y .. "Room" .. X .. "=" .. R .. (d.room or "?") .. X .. ". "
    .. Y .. "Area" .. X .. "=" .. R .. (d.area or "?") .. X .. ".")
end

local function completed(d)
  local ok, start = pcall(rune.store.get, START_KEY)
  local secs = ok and tonumber(start) and (os.time() - start) or nil
  local bonus = {}
  for _, k in ipairs({ { "pracs", "prac" }, { "trains", "train" }, { "tp", "tp" } }) do
    local n = tonumber(d[k[1]]) or 0
    if n ~= 0 then bonus[#bonus + 1] = R .. n .. " " .. k[2] end
  end
  rune.echo(R .. "[" .. Y .. "Quest Completed" .. R .. "] " .. Y .. "[" .. W .. "Qp: " .. R .. (d.totqp or "?")
    .. Y .. "]" .. X .. (secs and (" " .. secs .. " secs") or "")
    .. (#bonus > 0 and (" " .. Y .. "[" .. W .. "Bonus: " .. table.concat(bonus, W .. ", ") .. Y .. "]" .. X) or ""))
end

rune.gmcp.on("comm.quest", function(d)
  if type(d) ~= "table" then return end
  qst_update(d)
  local a = d.action
  if a == "start" then pcall(rune.store.set, START_KEY, os.time()) end
  if a == "start" then started(d)
  elseif a == "comp" then completed(d)
  elseif a == "timeout" then banner("Quest Timed Out")
  elseif a == "fail" then banner("Quest Failed")
  elseif a == "ready" then banner("Quest Time"); util.beep() end
  if a == "comp" or a == "fail" or a == "timeout" then pcall(rune.store.delete, START_KEY) end
  if a == "start" or (a == "status" and (d.targ or "") ~= "" and d.targ ~= "killed") then
    q = { targ = d.targ, room = d.room, area = d.area,
          ends = os.time() + (tonumber(d.timer) or 0) * 60 }
    minutely()
    return
  end
  if a == "killed" or (a == "status" and d.target == "killed") then
    q = q or {}
    q.killed = true
  elseif a == "comp" or a == "fail" or a == "timeout" or a == "status" then
    q = nil
  else
    return
  end
  target.clear("quest")
  row()
end, { name = "quest_target" })

rune.alias.exact("qx", function()
  if not q or q.killed or (q.room or "") == "" then return warn("[quest] qx: no quest target.") end
  local zone = travel.zone_of(q.area)
  if not zone then
    return warn("[quest] qx: area \"" .. tostring(q.area) .. "\" isn't in data/areas.lua - "
      .. q.targ .. " is in " .. q.room .. ".")
  end
  local t = target.get()
  -- Already this quest's target: keep it (and the keyword it learned)
  if not (t and t.src == "quest" and t.name == q.targ and t.room == q.room) then
    target.set({ name = q.targ, zone = zone, room = q.room, src = "quest" })
  end
  target.go()
end)

-- qc: home, quest complete, gulp (tt++ modules/paths.tin). The quest's reply
-- shows; gulp's is hidden. Its reply has no tag, so it is sent between two
-- eqdata, and everything from the first {eqdata} to the second {/eqdata}
-- is hidden, then the blank line(s) after it (the one before stays as the
-- break). Off again after 10 s whatever came
local qc_closes = nil   -- nil: not hiding; else {/eqdata} lines still to come
local qc_line = util.group(true)   -- one catch-all, only while qc runs
qc_line.add("starts", "", function(_, ctx)
  local clean = ctx.line:clean()
  if not qc_closes then
    if clean == "{eqdata}" then qc_closes = 2; return false end
    return
  end
  if clean == "{/eqdata}" then
    qc_closes = qc_closes - 1
    if qc_closes == 0 then
      qc_line.set(false)
      qc_closes = nil
      util.eat_blanks(clean)
    end
  end
  return false
end, { name = "quest_qc_quiet", priority = 1 })

local qc_timeout = util.slot()
rune.alias.exact("qc", function()
  qc_closes = nil
  qc_line.set(true)
  qc_timeout.start(10, function() qc_line.set(false); qc_closes = nil end)
  rune.send_raw("home\nquest complete\neqdata\ngulp\neqdata")
end)

