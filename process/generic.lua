-- Processors (require("process.generic")): data -> the value a widget compares,
-- shared so each is written once. Take them into locals at load. A
-- processor of a timed widget (every) may return a second value: the
-- seconds until its value can change (math.huge: only its data changes it).

local ceil, floor, NEVER = math.ceil, math.floor, math.huge

local P = {}

-- n cut to what format/generic.lua's short shows: 2512345 -> 2500000;
-- nil stays nil
function P.round(n)
  if not n then return nil end
  if n >= 1000000 then return floor(n / 100000) * 100000 end
  if n >= 1000 then return floor(n / 1000) * 1000 end
  return n
end

-- A { cur, max } record (hp, mana, moves) as a percent: 87.53; nil while
-- the maximum isn't known (or is 0)
function P.pct(r)
  if r and r.max and r.max ~= 0 then return r.cur * 100 / r.max end
end

-- v while on is true, else nil: process = P.when with source { on, v }
function P.when(on, v) if on then return v end end

-- gate(f) -> a processor: f(...) while the first source is true, else nil
-- (source = { "acct.known", "acct.gold" }, process = P.gate(P.round))
function P.gate(f)
  return function(on, ...) if on then return f(...) end end
end

-- below(n) -> a processor: v while it's under n, else nil (LVL: below(201))
function P.below(n)
  return function(v) if v and v < n then return v end end
end

-- v, or d while it's nil: either(0) shows 0 until known
function P.either(d)
  return function(v) if v == nil then return d end return v end
end

-- flash: 2 and 1 each other second while on, 0 while off (with every = 1)
function P.flash(on, now) return on and (now % 2 == 0 and 2 or 1) or 0 end

-- The main pane scrolled back (Rune's state - nothing says when it
-- changes, so read on every refresh: every = 0)
function P.scrolled() return rune._state.scroll_mode == "scrolled" end

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
