-- One-off: Lunar vs LuaJIT, the same work in each build. Run in Rune, out
-- of a fight, with
--   /lua dofile(rune.config_dir .. "/tools/jitprobe.lua")
-- Each case: GC first, then the fastest of 5 runs of N calls, in us per
-- call (os.clock: Rune's other threads count too, so compare the two
-- builds run the same way, not against other numbers). The results show
-- on screen and are added to ~/.local/state/rune/jitprobe.log.
-- The vitals cases feed made-up HP to the real handlers and screen; your
-- real vitals are put back at the end.
local util = require("lib.util")
local screen = require("ui.screen")
local game = require("modules.game")

local engine = jit and jit.version or "Lunar"
local N = 2000

local function best(fn)
  collectgarbage("collect")
  local low = math.huge
  for _ = 1, 5 do
    local t0 = os.clock()
    for i = 1, N do fn(i) end
    local t = (os.clock() - t0) / N * 1e6
    if t < low then low = t end
  end
  return low
end

local hp, mana, moves = game.hp or 1000, game.mana or 1000, game.moves or 1000
local function vitals(h)
  rune.gmcp._dispatch("char.vitals", { hp = tostring(h), mana = tostring(mana), moves = tostring(moves) }, "")
end

local cases = {
  { "pure Lua (string and table work)", function(i)
      local t = {}
      for k = 1, 20 do t[k] = ("x%d"):format(i + k) end
      return table.concat(t, ","):gsub("x", "y")
    end },
  { "screen pass, nothing changed", function() screen.pass() end },
  { "vitals, HP unchanged + pass", function() vitals(hp); screen.pass() end },
  { "vitals, HP changes + pass", function(i) vitals(hp - (i % 2) * 100); screen.pass() end },
}

local out = {}
for _, c in ipairs(cases) do
  out[#out + 1] = string.format("%-34s %8.2f us", c[1], best(c[2]))
end
vitals(hp)   -- your real HP back
screen.pass()

util.say("[jitprobe] " .. engine .. " (fastest of 5 x " .. N .. "):")
for _, l in ipairs(out) do rune.echo("  " .. l) end
util.append_file(util.state_dir .. "/jitprobe.log",
  os.date("%Y-%m-%d %H:%M ") .. engine .. "\n  " .. table.concat(out, "\n  "), "[jitprobe]")
