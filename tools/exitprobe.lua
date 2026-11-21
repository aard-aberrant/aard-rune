-- One-off: three ways to hold a room's exits, timed on the real map in
-- whichever build runs it. Run in Rune, out of a fight, with
--   /lua dofile(rune.config_dir .. "/tools/exitprobe.lua")
-- The layouts are built in side tables from M.rooms - the rooms aren't
-- touched - and dropped at the end:
--   keyed   r.exits as now: { n = e, ... }
--   slots   six slots, n e s w u d = 1..6, false where none (custom exits
--           left out: 113 of 90,453)
--   list    a dense list of { name = "n", ... }, single-letter names
-- Lookups: the direction of every real exit, once each. Loops: every exit
-- of every room, the way the search reads them. Fastest of 3, ms per pass.
-- Results on screen and added to ~/.local/state/rune/exitprobe.log.
local util = require("lib.util")
local M = require("modules.mapper")

local engine = jit and jit.version or "Lunar"
local DIR = { n = 1, e = 2, s = 3, w = 4, u = 5, d = 6 }

-- the layouts, and the lookups to make (room, direction, its index)
local keyed, slots, list = {}, {}, {}
local qr, qd, qi = {}, {}, {}
for v, r in pairs(M.rooms) do
  local s, l = { false, false, false, false, false, false }, {}
  for name, e in pairs(r.exits) do
    local i = DIR[name]
    if i then
      s[i] = e
      l[#l + 1] = { name = name, to = e.to, flags = e.flags, cmds = e.cmds }
      qr[#qr + 1], qd[#qd + 1], qi[#qi + 1] = v, name, i
    end
  end
  keyed[v], slots[v], list[v] = r.exits, s, l
end
local nq = #qr

local function best(fn)
  collectgarbage("collect")
  local low = math.huge
  for _ = 1, 3 do
    local t0 = os.clock()
    fn()
    local t = os.clock() - t0
    if t < low then low = t end
  end
  return low * 1e3
end

local sink = 0
local cases = {
  { "lookup keyed   r.exits[d]", function()
      for k = 1, nq do local e = keyed[qr[k]][qd[k]]; if e then sink = sink + 1 end end end },
  { "lookup slots   s[DIR[d]]", function()
      for k = 1, nq do local e = slots[qr[k]][DIR[qd[k]]]; if e then sink = sink + 1 end end end },
  { "lookup slots   s[i] (index known)", function()
      for k = 1, nq do local e = slots[qr[k]][qi[k]]; if e then sink = sink + 1 end end end },
  { "lookup list    scan e.name == d", function()
      for k = 1, nq do
        local l, d = list[qr[k]], qd[k]
        for j = 1, #l do if l[j].name == d then sink = sink + 1; break end end
      end end },
  { "loop   keyed   pairs", function()
      for _, x in pairs(keyed) do for _, e in pairs(x) do sink = sink + e.to end end end },
  { "loop   slots   for i = 1, 6", function()
      for _, s in pairs(slots) do for i = 1, 6 do local e = s[i]; if e then sink = sink + e.to end end end end },
  { "loop   list    for j = 1, #l", function()
      for _, l in pairs(list) do for j = 1, #l do sink = sink + l[j].to end end end },
}

local out = {}
for _, c in ipairs(cases) do out[#out + 1] = string.format("%-36s %8.2f ms", c[1], best(c[2])) end
keyed, slots, list, qr, qd, qi = nil, nil, nil, nil, nil, nil
collectgarbage("collect")

util.say(string.format("[exitprobe] %s - %d lookups, %d rooms (fastest of 3):", engine, nq, M.count or 0))
for _, l in ipairs(out) do rune.echo("  " .. l) end
util.append_file(util.state_dir .. "/exitprobe.log",
  os.date("%Y-%m-%d %H:%M ") .. engine .. "\n  " .. table.concat(out, "\n  "), "[exitprobe]")
