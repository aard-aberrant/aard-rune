-- panel:affects(): your affects - widgets on modules/affects.lua's data:
--   the tracked affects (data/affects.lua): good ones on the left with
--     minutes left - green, yellow at 2 min, red at 1; off: gray, or black
--     on red for an important one - and bad ones as lights on the right,
--     gray, black on red while on you
--   sk: N  sp: good/bad - everything that's up
--   the expiry histogram - how many good spells and skills (not the tracked
--     ones, which have their own times) run out within 30s, 1m, 2m, 5m, 10m
--   the next three of them to run out, by name, colored by how soon
--   recoveries (data/affects.lua, by subclass) under the good affects: while
--     the spell is up, bright with its time left (as a good affect); while
--     it recovers, gray with minutes until ready; ready, the label in gray
--   Shaman: the totem - type, minutes left, area; then Create Totem's
--     recovery, "totem ready"
-- Each row, line and band is a widget; the ones that follow the clock are
-- processed once a second, all of them from one summary of the data (made
-- once per change or second).

local util = require("lib.util")
local theme = require("ui.theme")
local screen = require("ui.screen")
require("ui.widgets.barchart")   -- panel:barchart (the histogram)
-- This pane's colors: theme.affects.* - /theme lists them, data/theme.lua
-- changes them (ui/theme.lua)
local T = theme.define("affects", "The affects pane", {
  { "totem_area",  theme.cyan, "the totem's area" },
})

local CFG = util.load_data(rune.config_dir .. "/data/affects.lua") or { track = {} }
local PER_BLOCK = CFG.per_block or 2
local ICONS = CFG.totem_icons or {}
local BAD_EXTRA = CFG.bad_extra or {}

local RED, YEL, GRN, GRAY, CYAN =
  theme.danger, theme.caution, theme.good, theme.muted, T.totem_area
local alert = theme.alert
local OFF = theme.unavailable   -- off: a spell not up, a bad one not on you, an empty timer band, no totem
local STYLE = { RED, YEL, GRN, GRAY }

local rep, floor, ceil, max, min = string.rep, math.floor, math.ceil, math.max, math.min
local function mins(secs) return ceil(secs / 60) end
local function rjust(s, w) s = tostring(s); return rep(" ", w - #s) .. s end
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
local NEVER = math.huge   -- only a change of the data changes it
-- Seconds left -> the style's number (STYLE): red to 1 min, yellow to 2
local band = require("ui.format").level({ 61, 121 })

-- A subclass's lists (data/affects.lua's `only`): the tracked good and bad
-- ids (by number), the recovery labels, the label widths, also-name -> id.
-- gen: the subclass's number here, carried in a row's processed value
local by_sub, by_gen = {}, {}
local function lists(sub)
  local L = by_sub[sub or ""]
  if L then return L end
  local function mine(d)
    if not d.only then return true end
    for _, s in ipairs(d.only) do if s == sub then return true end end
    return false
  end
  L = { good = {}, bad = {}, also = {}, recs = {}, good_w = 0, bad_w = 0, gen = #by_gen + 1 }
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
  for _, d in ipairs(CFG.recoveries or {}) do
    if mine(d) then
      L.recs[#L.recs + 1] = d.label
      L.good_w = max(L.good_w, #d.label)
    end
  end
  by_sub[sub or ""], by_gen[L.gen] = L, L
  return L
end

-- The summary, once per change (affects.n) and subclass: the lit bad
-- lights, the counts, and the timed good affects not tracked, by end
-- (soonest first - the order time keeps). Then once a second: the ones not
-- run out yet (a list kept until that changes), the histogram's counts
-- (bands up to 30 s, 1, 2, 5, 10 min; minutes rounded up, so exactly 60 s
-- left is 1m)
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
  S.lit, S.ends, S.sk, S.sp, S.bad, S.first = lit, ends, sk, sp, bad, nil
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
  -- each in the first band its time fits (minutes rounded up, so exactly
  -- 60 s left is 1m); hist_next: seconds until one moves down a band
  local c1, c2, c3, c4, c5, nxt = 0, 0, 0, 0, 0, NEVER
  for k = i0, #ends do
    local u = ends[k].e - now - 1
    local lower
    if u < 30 then c1, lower = c1 + 1, -1
    elseif u < 60 then c2, lower = c2 + 1, 29
    elseif u < 120 then c3, lower = c3 + 1, 59
    elseif u < 300 then c4, lower = c4 + 1, 119
    elseif u < 600 then c5, lower = c5 + 1, 299
    else lower = 599 end
    if u - lower < nxt then nxt = u - lower end
    if lower == 599 then break end   -- (sorted: the rest are later still)
  end
  s.hist_next = nxt
  local h = s.hist   -- a new list only when a count changed
  if not h or h[1] ~= c1 or h[2] ~= c2 or h[3] ~= c3 or h[4] ~= c4 or h[5] ~= c5 then s.hist = { c1, c2, c3, c4, c5 } end
  return s
end

return screen.add_widget("affects", function(p)
local SRC = { "subclass", "affects" }
-- a line of its own, the panel's width; a nil processed value shows nothing
local function line(t)
  local f = t.format
  t.y, t.source, t.w = "next", SRC, "*"
  t.format = function(v, w) if v ~= nil then return f(v, w) end end
  return p:widget(t)
end

-- The rows: a good affect or recovery (left), a bad light (right edge).
-- Processed: (gen * 1000 + good) * 3 + bad - good 0 none, 1 off, 2 off
-- and important, 3 up with no time, 10 + style * 100 + minutes (0 = 30s)
-- for a timed one; bad 0 none, 1 off, 2 lit
local function timed(st, left)
  return 10 + st * 100 + (left <= 30 and 0 or min(max(mins(left), 0), 99))
end
local nrows = #(CFG.recoveries or {})
for _ in pairs(CFG.track) do nrows = nrows + 1 end
for i = 1, nrows do
  line {
    every = 1,
    process = function(sub, A, now)
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
        local r = A.recs[i - ng]
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
    end,
    format = function(v, width)
      local b = v % 3
      v = floor(v / 3)
      local g, L = v % 1000, by_gen[floor(v / 1000)]
      local gw, s = L.good_w + 4
      if g == 0 then
        s = rep(" ", gw)
      else
        local id = L.good[i]
        local label = rjust(id and CFG.track[id].label or L.recs[i - #L.good], L.good_w)
        if g == 1 then s = OFF(label) .. "    "
        elseif g == 2 then s = alert(label) .. "    "
        elseif g == 3 then s = GRN(label) .. "    "
        else
          local t = (g - 10) % 100
          s = STYLE[floor((g - 10) / 100)](label .. " " .. (t == 0 and "30s" or rjust(t, 2) .. "m"))
        end
      end
      if b == 0 then return s end
      local label = rjust(CFG.track[L.bad[i]].label, L.bad_w)
      return s .. rep(" ", max((width or 0) - gw - L.bad_w, 1)) .. (b == 2 and alert(label) or OFF(label))
    end,
  }
end

-- sk: N            sp: good/bad - (sk * 1000 + good) * 1000 + bad
line {
  process = function(sub, A, now)
    if not A.seen then return nil end
    local s = summary(sub, A, now)
    return (s.sk * 1000 + s.sp - s.bad) * 1000 + s.bad
  end,
  format = function(v, width)
    local sk, good, bad = floor(v / 1e6), floor(v / 1000) % 1000, v % 1000
    local gap = max((width or 0) - #("sk: " .. sk) - #("sp: " .. good .. "/" .. bad), 1)
    return GRAY("sk:") .. " " .. GRN(sk) .. rep(" ", gap) .. GRAY("sp:") .. " " .. GRN(good) .. GRAY("/") .. RED(bad)
  end,
}
local function blank() return "" end
line { process = function(_, A) return A.seen or nil end, format = blank }

-- The histogram: a bar per band, its count
p:barchart {
  source = SRC, every = 1, scale = PER_BLOCK, cells = 10,
  labels = { "30s", "1m", "2m", "5m", "10m" }, colors = { RED, RED, YEL, GRN, GRN }, zero = OFF,
  values = function(sub, A, now)
    if not A.seen then return nil, NEVER end
    local s = summary(sub, A, now)
    return s.hist, s.hist_next
  end,
}

-- The next three to run out: a list keyed by name, each row its color band
line { every = 1, format = blank,
  process = function(sub, A, now)
    local t = A.seen and summary(sub, A, now).timers[1]
    if not t then return nil, NEVER end
    return 1, t.e - now
  end }
p:list {
  source = SRC, every = 1, max = 3,
  records = function(sub, A, now)   -- (the next change: a row's band, the first running out)
    if not A.seen then return nil, NEVER end
    local t, nxt = summary(sub, A, now).timers, NEVER
    for k = 1, min(3, #t) do nxt = min(nxt, till_band(t[k].e - now)) end
    return t, nxt
  end,
  key = function(t) return t.name end,
  process = function(t, now) return band(t.e - now) end,
  format = function(b, name, cols)
    return STYLE[b]((name:sub(1, 1):upper() .. name:sub(2)):sub(1, cols))
  end,
}

-- The totem (Shaman): placed, with minutes left (a), without (b); Create
-- Totem recovering (c), ready (d); none (e) - fields split by \1
local function totem(sub, A, now)
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
line { every = 1, format = blank,
  process = function(sub, A, now)
    local v, nxt = totem(sub, A, now)
    return A.seen and v and 1 or nil, nxt
  end }
line {
  every = 1,
  process = totem,
  format = function(v, width)
    local k = v:sub(1, 1)
    if k == "d" then return GRN("totem ready") end
    if k == "e" then return OFF("no totem") end
    local f = {}
    for x in (v:sub(3) .. "\1"):gmatch("([^\1]*)\1") do f[#f + 1] = x end
    if k == "c" then return OFF("totem ready in " .. f[1] .. "m") end
    local icon = ICONS[f[1]]
    local area = f[#f]
    area = CYAN(area:sub(1, max((width or 0) - (icon and 2 or #f[1]) - 5, 0)))
    if k == "b" then return GRN(icon or f[1]) .. "     " .. area end
    return STYLE[tonumber(f[3])]((icon or f[1]) .. " " .. rjust(f[2], 2) .. "m") .. " " .. area
  end,
}
end)
