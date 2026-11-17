-- Affects processors (require("process.affects")): modules/affects.lua's
-- data -> what the affects pane's widgets compare. Each takes the pane's
-- sources (subclass, affects) and now, and returns its value and the
-- seconds until that can change (math.huge: only the data changes it).
-- One summary of the data is made per change (affects.n) and subclass,
-- and once a second, shared by them all.
--
-- Values are packed into one number where a row shows several things, so
-- comparing them is one ~= (format/affects.lua unpacks them).
local util = require("lib.util")
local level = require("format.generic").level
local ceil, max, min = math.ceil, math.max, math.min
local NEVER = math.huge

local P = {}

-- data/affects.lua: the tracked affects, recoveries, totem icons ...
local CFG = util.load_data(rune.config_dir .. "/data/affects.lua") or { track = {} }
P.cfg = CFG
local BAD_EXTRA = CFG.bad_extra or {}

-- Minutes left, rounded up
local function mins(secs) return ceil(secs / 60) end
P.mins = mins
-- Seconds until "Nm" (minutes rounded up) shows one less, or "1m" turns
-- "30s", or (30 s or less) it runs out
local function till_minute(left)
  if left > 30 and left <= 60 then return left - 30 end
  return left - (mins(left) - 1) * 60
end
-- Seconds until the band changes (at 120 and 60 s left), or it runs out
local function till_band(left)
  if left > 120 then return left - 120 elseif left > 60 then return left - 60 end
  return left
end
-- Seconds left -> the color band: 1 red to 1 min, 2 yellow to 2, 3 green
local band = level({ 61, 121 })

-- A subclass's lists (data/affects.lua's `only`): the tracked good and bad
-- ids (by number), the recovery labels, the label widths, also-name -> id.
-- gen: the subclass's number here, carried in a row's processed value
-- (P.by_gen[gen]: its lists again, for the formatter)
local by_sub, by_gen = {}, {}
P.by_gen = by_gen
local function lists(sub)
  local L = by_sub[sub or ""]
  if L then return L end
  local function mine(d)
    if not d.only then return true end
    for _, s in ipairs(d.only) do if s == sub then return true end end
    return false
  end
  -- recs: the rows' labels; rec_at: each row's place in A.recs (which has
  -- every recovery of the subclass); lines: the ones on a line of their own
  L = { good = {}, bad = {}, also = {}, recs = {}, rec_at = {}, lines = {}, good_w = 0, bad_w = 0, gen = #by_gen + 1 }
  for id, d in pairs(CFG.track) do
    if mine(d) then
      if d.good then
        L.good[#L.good + 1] = id
        L.good_w = max(L.good_w, #d.label)
      else
        L.bad[#L.bad + 1] = id
        L.bad_w = max(L.bad_w, #d.label)
        for _, name in ipairs(d.also or {}) do L.also[name] = id end
      end
    end
  end
  table.sort(L.good)
  table.sort(L.bad)
  local n = 0
  for _, d in ipairs(CFG.recoveries or {}) do
    if mine(d) then
      n = n + 1
      if d.line then
        L.lines[#L.lines + 1] = { word = d.line, at = n }
      else
        L.recs[#L.recs + 1] = d.label
        L.rec_at[#L.recs] = n
        L.good_w = max(L.good_w, #d.label)
      end
    end
  end
  by_sub[sub or ""], by_gen[L.gen] = L, L
  return L
end

-- The summary, once per change (affects.n) and subclass: the lit bad
-- lights, the counts, and the timed good affects not tracked, by end
-- (soonest first - the order time keeps), and their ends alone (moments,
-- for the histogram). Then once a second: the ones not run out yet (a list
-- kept until that changes)
local S = { n = -1, lit = {}, ends = {} }
local function base(sub, A)
  if S.n == A.n and S.sub == sub then return S end
  S.n, S.sub, S.now = A.n, sub, nil
  local L, up, spell = lists(sub), A.up, A.spells
  local lit = {}
  for _, id in ipairs(L.bad) do lit[id] = up[id] ~= nil end
  local tracked = {}
  for _, id in ipairs(L.good) do tracked[id] = true end
  for _, r in ipairs(A.recs) do if r.d.sn then tracked[r.d.sn] = true end end
  local sk, sp, bad, ends = 0, 0, 0, {}
  for sn, e in pairs(up) do
    local s = spell[sn]
    if s then   -- one not learned yet is left out until the slist comes
      local id = L.also[s.name]
      if id then lit[id] = true end
      local is_bad = s.target == 1 or BAD_EXTRA[s.name]
      if is_bad then sp, bad = sp + 1, bad + 1
      elseif s.type == 2 then sk = sk + 1
      else sp = sp + 1 end
      if not is_bad and e > 0 and not tracked[sn] then ends[#ends + 1] = { e = e, name = s.name } end
    end
  end
  table.sort(ends, function(a, b) return a.e < b.e end)
  local moments = {}
  for k = 1, #ends do moments[k] = ends[k].e end
  S.lit, S.ends, S.moments, S.sk, S.sp, S.bad, S.first = lit, ends, moments, sk, sp, bad, nil
  return S
end
local function summary(sub, A, now)
  local s = base(sub, A)
  if s.now == now then return s end
  s.now = now
  local ends, i0 = s.ends, 1
  while ends[i0] and ends[i0].e <= now do i0 = i0 + 1 end
  if i0 ~= s.first then   -- the ones not run out yet
    s.first = i0
    local t = {}
    for k = i0, #ends do t[#t + 1] = ends[k] end
    s.timers = t
  end
  return s
end

-- The rows: as many as could be tracked (data/affects.lua); P.row(i) is
-- row i's processor - a good affect or recovery (left), a bad light (right
-- edge), packed: (gen * 1000 + good) * 3 + bad - good 0 none, 1 off, 2 off
-- and important, 3 up with no time, 10 + band * 100 + minutes (0 = 30s)
-- for a timed one (band 4: a recovery recovering); bad 0 none, 1 off, 2 lit
local nrows = #(CFG.recoveries or {})
for _ in pairs(CFG.track) do nrows = nrows + 1 end
P.nrows = nrows
local function timed(st, left)
  return 10 + st * 100 + (left <= 30 and 0 or min(max(mins(left), 0), 99))
end
function P.row(i)
  return function(sub, A, now)
    local L = lists(sub)
    local ng, up = #L.good, A.up
    if i > max(ng + #L.recs, #L.bad) then return nil end
    local g, id, nxt = 0, L.good[i], NEVER
    if id then
      local e = up[id]
      if not e then g = CFG.track[id].important and 2 or 1
      elseif e == 0 then g = 3
      else
        local left = e - now
        g = timed(band(left), left)
        if left > 0 then nxt = min(till_minute(left), till_band(left)) end
      end
    else
      local r = A.recs[L.rec_at[i - ng]]
      if r then
        local e = r.d.sn and up[r.d.sn]
        if e == 0 then g = 3
        elseif e and e > now then
          local left = e - now
          g, nxt = timed(band(left), left), min(till_minute(left), till_band(left))
        elseif r.ends > now then g, nxt = timed(4, r.ends - now), till_minute(r.ends - now)
        else g = 1 end
      end
    end
    local b, bid = 0, L.bad[i]
    if bid then b = base(sub, A).lit[bid] and 2 or 1 end
    return (L.gen * 1000 + g) * 3 + b, nxt
  end
end

-- sk: N  sp: good/bad, packed: (sk * 1000 + good) * 1000 + bad; nil until
-- the first slist
function P.counts(sub, A, now)
  if not A.seen then return nil end
  local s = summary(sub, A, now)
  return (s.sk * 1000 + s.sp - s.bad) * 1000 + s.bad
end

-- true once there's anything to show (the first slist); nil before
function P.seen(_, A) return A.seen or nil end

-- The histogram's numbers: the untracked timed ones' ends, soonest first
function P.moments(sub, A)
  if not A.seen then return nil, NEVER end
  return base(sub, A).moments
end

-- 1 while any untracked timed one hasn't run out (the gap above them)
function P.any_timers(sub, A, now)
  local t = A.seen and summary(sub, A, now).timers[1]
  if not t then return nil, NEVER end
  return 1, t.e - now
end

-- The untracked timed ones not run out yet, soonest first ({ e, name });
-- the next change: the first three's band, or the first running out
function P.timers(sub, A, now)
  if not A.seen then return nil, NEVER end
  local t, nxt = summary(sub, A, now).timers, NEVER
  for k = 1, min(3, #t) do nxt = min(nxt, till_band(t[k].e - now)) end
  return t, nxt
end

-- One of those: its color band
function P.timer_band(t, now) return band(t.e - now) end

-- The totem (Shaman): placed, with minutes left (a), without (b); Create
-- Totem recovering (c), ready (d); none (e) - fields split by \1:
-- "a\1type\1minutes\1band\1area", "b\1type\1area", "c\1minutes"
function P.totem(sub, A, now)
  if sub ~= "Shaman" then return nil, NEVER end
  local t = A.totem
  if t.type and not (t.ends > 0 and t.ends <= now) then
    if t.ends > 0 then
      local left = t.ends - now
      return "a\1" .. t.type .. "\1" .. mins(left) .. "\1" .. (left <= 120 and 2 or 3) .. "\1" .. t.area,
        min(till_minute(left), left > 120 and left - 120 or NEVER)
    end
    return "b\1" .. t.type .. "\1" .. t.area, NEVER
  end
  if t.rec_end > now then return "c\1" .. mins(t.rec_end - now), till_minute(t.rec_end - now) end
  if t.ready or t.rec_end > 0 then return "d", NEVER end
  if t.none then return "e", NEVER end
  return nil, NEVER
end

-- 1 while the totem line shows (the gap above it)
function P.any_totem(sub, A, now)
  local v, nxt = P.totem(sub, A, now)
  return A.seen and v and 1 or nil, nxt
end

-- A recovery on a line of its own (data/affects.lua's line), the i-th of
-- the subclass's: "word\1secs" - secs left (0: ready), next change in 1 s
-- while counting. nil (no line) when it has fewer
local lines_max = 0
for _, d in ipairs(CFG.recoveries or {}) do if d.line then lines_max = lines_max + 1 end end
P.nlines = lines_max
function P.cooldown(i)
  return function(sub, A, now)
    local c = lists(sub).lines[i]
    local r = c and A.recs[c.at]
    if not r then return nil, NEVER end
    local left = r.ends - now
    if left > 0 then return c.word .. "\1" .. left, 1 end
    return c.word .. "\1" .. 0, NEVER
  end
end

-- 1 while any such line shows (the gap above them)
function P.any_cooldown(sub, A)
  return A.seen and lists(sub).lines[1] and 1 or nil, NEVER
end

return P
