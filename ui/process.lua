-- Processors (require("ui.process")): data -> the value a widget compares,
-- shared so each is written once. Take them into locals at load. A
-- processor of a timed widget (every) may return a second value: the
-- seconds until its value can change (math.huge: only its data changes it).

local ceil, floor, NEVER = math.ceil, math.floor, math.huge

local P = {}

-- n cut to what ui/format.lua's short shows: 2512345 -> 2500000
function P.round(n)
  if n >= 1000000 then return floor(n / 100000) * 100000 end
  if n >= 1000 then return floor(n / 1000) * 1000 end
  return n
end

-- A { cur, max } record (hp, mana, moves) as a percent: 87.53; nil while
-- the maximum isn't known (or is 0)
function P.pct(r)
  if r and r.max and r.max ~= 0 then return r.cur * 100 / r.max end
end

-- Whole seconds left until the moment `at` (an os.time), never below 0;
-- nil while it isn't known. Then the seconds until that changes
function P.secs_left(at, now)
  if not at then return nil, NEVER end
  local s = at - now
  if s <= 0 then return 0, NEVER end
  return s, 1
end

-- Minutes left, rounded up (59 s: 1), never below 0; nil while not known.
-- Then the seconds until that changes
function P.mins_left(at, now)
  if not at then return nil, NEVER end
  local s = at - now
  if s <= 0 then return 0, NEVER end
  local m = ceil(s / 60)
  return m, s - (m - 1) * 60
end

return P
