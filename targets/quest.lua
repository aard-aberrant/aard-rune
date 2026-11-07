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
-- pane, and qc.

local util = require("core.util")
local status = require("panes.status")   -- QST, in a row-1 slot
local info = require("panes.info")       -- the quest's rows
local target = require("targets.target")   -- qx sets it, a kill or the end drops it
local travel = require("nav.travel")   -- qx goes; an area's zone from its name

local warn = util.warn

local q   -- { targ, room, area, ends, killed } while on a quest
local gen = 0   -- bumped per quest, so an old minute timer stops

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
  info.set("quest", 50, info.target_rows(first, q.area, q.room, q.targ))
end

local function minutely(g)
  if g ~= gen or not q or q.killed then return end
  row()
  local wait = (q.ends - os.time()) % 60
  rune.timer.after(wait > 0 and wait or 60, function() minutely(g) end)
end

-- QST (tt++ quest.tin), status row 1: minutes until you can quest again
-- (red under 3), RD when you can, AC on a quest (red once the game warns
-- time is running out); "--" until known - asked for at load and each tick.
-- From comm.quest: "status" is the reply to "request quest" - on a quest
-- (its target alive - targ - or dead - target = "killed"), ready, or a
-- wait in minutes
local qst = { state = nil, ready_at = 0, warn = false }   -- nil, "wait", "ready", "active"
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
  local function wait(m)
    m = tonumber(m) or 0
    qst.warn = false
    if m <= 0 then qst.state = "ready"
    else qst.state, qst.ready_at = "wait", os.time() + m * 60 end
  end
  local a = d.action
  if a == "start" then
    qst.state, qst.warn = "active", false
  elseif a == "warning" then
    qst.warn = true
  elseif a == "timeout" or a == "fail" or a == "comp" then
    wait(d.wait)
  elseif a == "status" then
    if ((d.targ or "") ~= "" and d.targ ~= "killed") or d.target == "killed" then
      qst.state = "active"
    elseif d.status == "ready" then
      wait(0)
    elseif d.wait then
      wait(d.wait)
    end
  end
  status.draw()
end

rune.gmcp.on("comm.tick", function()
  if not qst.state then rune.gmcp.send("request quest") end
end, { name = "quest_tick" })

rune.gmcp.on("comm.quest", function(d)
  if type(d) ~= "table" then return end
  qst_update(d)
  local a = d.action
  if a == "start" or (a == "status" and (d.targ or "") ~= "" and d.targ ~= "killed") then
    gen = gen + 1
    q = { targ = d.targ, room = d.room, area = d.area,
          ends = os.time() + (tonumber(d.timer) or 0) * 60 }
    minutely(gen)
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
local qc_line
qc_line = rune.trigger.starts("", function(_, ctx)
  local clean = ctx.line:clean()
  if not qc_closes then
    if clean == "{eqdata}" then qc_closes = 2; return false end
    return
  end
  if clean == "{/eqdata}" then
    qc_closes = qc_closes - 1
    if qc_closes == 0 then
      qc_line:disable()
      qc_closes = nil
      util.eat_blanks(clean)
    end
  end
  return false
end, { name = "quest_qc_quiet", priority = 1 })
qc_line:disable()

local qc_gen = 0
rune.alias.exact("qc", function()
  qc_closes, qc_gen = nil, qc_gen + 1
  local g = qc_gen
  qc_line:enable()
  rune.timer.after(10, function()
    if g == qc_gen then qc_line:disable(); qc_closes = nil end
  end)
  rune.send_raw("home\nquest complete\neqdata\ngulp\neqdata")
end)

