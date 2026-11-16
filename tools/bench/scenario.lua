-- Drives every status segment through its states. Snapshots to stdout
-- (mode "snap") or timings (mode "bench"). arg: ROOT snap|bench
dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local MODE = arg[2] or "snap"
local function ctx(text) return { line = { clean = function() return text end, raw = function() return text end } } end
local function line(text)
  for _, t in ipairs(H.triggers) do
    local hit
    if t.kind == "starts" then hit = text:sub(1, #t.pat) == t.pat
    elseif t.kind == "contains" then hit = text:find(t.pat, 1, true)
    elseif t.kind == "exact" then hit = text == t.pat end
    if hit then t.fn(nil, ctx(text)) end
  end
end
local function hit(n)   -- a DPS damage line
  for _, t in ipairs(H.triggers) do
    if t.kind == "regex" and t.pat:find("Your (.*)", 1, true) and t.pat:find("^\\*?", 1, true) then
      t.fn({ "slash hits a goblin", tostring(n) }, ctx("Your slash hits a goblin [" .. n .. "]"))
    end
  end
end
local snaps = {}
local function snap(tag) snaps[#snaps + 1] = "-- " .. tag .. "\n" .. H.pass() end
local steps = {
  { "empty", function() end },
  { "logged in", function()
    H.feed("char.vitals", { hp = "880", mana = "100", moves = "50" })
    H.feed("char.maxstats", { maxhp = "1000", maxmana = "1000", maxmoves = "60" })
    H.feed("char.status", { state = "3", level = "150", tnl = "250", align = "-900", enemy = "", enemypct = "" })
    H.feed("room.info", { num = "100", zone = "goblins", name = "A cave" })
    H.feed("comm.tick", nil)
    local ok, err = pcall(require, "modules.moons")   -- a Shaman's: loads at login, after the first pass
    if not ok then print("LOAD modules.moons: " .. tostring(err)) end
  end },
  { "quest wait 5", function() H.feed("comm.quest", { action = "status", wait = "5" }) end },
  { "repop seen", function() H.feed("comm.repop", { zone = "goblins" }) end },
  { "sense life 4-5", function() H.now = H.now + 20; line("You sense that life will return to this area in roughly 4-5 minutes.") end },
  { "2xp", function() line("For the next 15 minutes experience is doubled in honor of the new superhero.") end },
  { "fight", function()
    H.feed("char.status", { state = "8", level = "150", tnl = "250", align = "-900", enemy = "a goblin", enemypct = "90" })
    hit(120); H.now = H.now + 1; hit(80)
  end },
  { "fight +6s", function() for _ = 1, 6 do H.now = H.now + 1; hit(100) end
    H.feed("char.vitals", { hp = "500", mana = "90", moves = "50" }) end },
  { "pups", function()
    line("Congratulations, Aberrant. You have increased your powerups to 10.")
    H.now = H.now + 20; line("Congratulations, Aberrant. You have increased your powerups to 11.")
    H.now = H.now + 25; line("Congratulations, Aberrant. You have increased your powerups to 12.")
  end },
  { "fight over", function() H.feed("char.status", { state = "3", level = "150", tnl = "100", align = "-900", enemy = "", enemypct = "" }) end },
  { "quest minute 2", function() H.now = H.now + 140 end },
  { "pop last 10s", function() H.now = H.now + 80 end },
  { "logging", function() rune.log.start("y") end },
  { "logging +1s, scrolled", function() H.now = H.now + 1; rune._state.scroll_mode = "scrolled" end },
  { "quest ready", function() H.now = H.now + 200 end },
  { "quest active warn", function() H.feed("comm.quest", { action = "start", targ = "a rat" }); H.feed("comm.quest", { action = "warning" }) end },
  { "pup over, 2xp gone, area change", function() H.now = H.now + 1000; H.feed("room.info", { num = "5", zone = "town", name = "Square" }) end },
  { "log stopped", function() rune.log.stop() end },
}
for _, s in ipairs(steps) do s[2](); snap(s[1]) end
if MODE == "snap" then print(table.concat(snaps, "\n")) return end
if MODE == "prof" then
  H.feed("char.status", { state = "8", level = "150", tnl = "100", align = "-900", enemy = "a goblin", enemypct = "90" })
  local counts, N = {}, 3000
  local function run(k) H.now = H.now + 1; hit(100); H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }); H.pass() end
  for k = 1, 50 do run(k) end
  debug.sethook(function() local i = debug.getinfo(2, "Sl"); local key = i.short_src:match("[^/]*$") .. ":" .. (i.currentline or 0); counts[key] = (counts[key] or 0) + 1 end, "l")
  for k = 1, N do run(k) end
  debug.sethook()
  local byfile, tot = {}, 0
  for k, v in pairs(counts) do local fl = k:match("^[^:]+"); byfile[fl] = (byfile[fl] or 0) + v; tot = tot + v end
  print("lines per pass " .. tot / N)
  local l = {}; for k, v in pairs(byfile) do l[#l + 1] = { k, v / N } end
  table.sort(l, function(a, b) return a[2] > b[2] end)
  for _, e in ipairs(l) do print(string.format("  %-22s %.0f", e[1], e[2])) end
  local fl = {}; for k, v in pairs(counts) do fl[#fl + 1] = { k, v / N } end
  table.sort(fl, function(a, b) return a[2] > b[2] end)
  for n = 1, 400 do if fl[n] then print(string.format("    %-26s %.1f", fl[n][1], fl[n][2])) end end
  return
end
-- bench: the same pass costs under each kind of moment
local N = 20000
local clock = os.clock
local function bench(name, setup)
  local t = clock()
  for k = 1, N do setup(k); H.pass() end
  print(string.format("%-34s %6.2f us", name, (clock() - t) / N * 1e6))
end
bench("idle (same second)", function() end)
bench("each pass a new second", function() H.now = H.now + 1 end)
bench("vitals change, same second", function(k) H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }) end)
H.feed("char.status", { state = "8", level = "150", tnl = "100", align = "-900", enemy = "a goblin", enemypct = "90" })
bench("fight: hit + vitals + new second", function(k) H.now = H.now + 1; hit(100); H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }) end)
bench("fight: 4 passes a second", function(k) if k % 4 == 0 then H.now = H.now + 1 end end)
do
  local M = 20000
  local t = clock()
  for k = 1, M do H.now = H.now + 1; hit(100); H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }) end
  local feed = (clock() - t) / M * 1e6
  t = clock()
  for k = 1, M do H.now = H.now + 1; hit(100); H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }); H.pass() end
  local both = (clock() - t) / M * 1e6
  print(string.format("%-34s %6.2f us  (events %5.2f, pass %5.2f)", "split: hit + vitals + new second", both, feed, both - feed))
end
do
  local M = 20000
  local function ev(k) H.now = H.now + 1; for _ = 1, 5 do hit(100) end; H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }) end
  local t = clock()
  for k = 1, M do ev(k) end
  local feed = (clock() - t) / M * 1e6
  t = clock()
  for k = 1, M do ev(k); H.pass() end
  local both = (clock() - t) / M * 1e6
  print(string.format("%-34s %6.2f us  (events %5.2f, pass %5.2f)", "split: 5 hits + vitals + new second", both, feed, both - feed))
end
-- One fight second as Rune would run it: each event its own pass, plus the
-- 4 polls. Reported per second (8 passes), not per pass
do
  local M = 5000
  local t = clock()
  for k = 1, M do
    H.now = H.now + 1; H.pass()
    hit(100); H.pass()
    hit(90); H.pass()
    H.feed("char.vitals", { hp = tostring(400 + k % 50), mana = "90", moves = "50" }); H.pass()
    H.feed("char.status", { state = "8", level = "150", tnl = "100", align = "-900", enemy = "a goblin", enemypct = tostring(90 - k % 80) }); H.pass()
    H.pass(); H.pass(); H.pass()
  end
  print(string.format("%-34s %6.2f us per second", "fight second (8 passes)", (clock() - t) / M * 1e6))
  t = clock()
  for k = 1, M do
    H.now = H.now + 1; H.pass(); H.pass(); H.pass(); H.pass()
  end
  print(string.format("%-34s %6.2f us per second", "quiet second (4 polls)", (clock() - t) / M * 1e6))
end
