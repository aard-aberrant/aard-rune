-- lua vit_bench.lua ROOT small|big: one char.vitals + the bar pass, per message
dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local CASE = arg[2]
H.feed("char.maxstats", { maxhp = 88000, maxmana = 40000, maxmoves = 30000 })
H.feed("char.vitals", { hp = 88000, mana = 40000, moves = 30000 })
H.pass()
local N = 20000
local t0 = os.clock()
for i = 1, N do
  local hp
  if CASE == "small" then hp = 69960 + (i % 2) * 30   -- 79.50% / 79.53%: both show 79.5
  elseif CASE == "big" then hp = 70000 - (i % 50) * 500      -- 500 hp steps: the shown value moves
  else hp = 70000 end                                         -- same: no change
  H.feed("char.vitals", { hp = hp, mana = 40000, moves = 30000 })
  H.pass()
end
io.stdout:write(string.format("%s %.2f\n", CASE, (os.clock() - t0) / N * 1e6))
