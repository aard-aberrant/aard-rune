-- Formatters (require("ui.format")): the pieces widgets build their text
-- from, shared so each rule is written once. Take them into locals at
-- load (local num = F.num) - a call is then a plain local call.

local theme = require("ui.theme")
local floor, fmt = math.floor, string.format

local F = {}

-- Numbers ----------------------------------------------------------------

-- 12 -> "12", 12.5 -> "12.5": whole numbers as they are, others to one place
function F.num(v)
  if v == floor(v) then return tostring(floor(v)) end
  return fmt("%.1f", v)
end

-- 1234567 -> "1,234,567"
function F.commas(v)
  local s = fmt("%.0f", v)
  local sign, int = s:match("^(-?)(%d+)$")
  if not int then return s end
  return sign .. int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- 2512345 -> "2.5M", 15400 -> "15K" (ui/process.lua's round: a number cut
-- to what this shows)
function F.short(n)
  if n >= 1000000 then return fmt("%.1fM", floor(n / 100000) / 10) end
  if n >= 1000 then return floor(n / 1000) .. "K" end
  return tostring(n)
end

-- Time -------------------------------------------------------------------

-- Seconds as minutes and seconds: "1:05", ">100m" from 100 minutes;
-- wide: "01:05", "99:99" from 100 minutes
function F.clock(s, wide)
  if wide then return s > 5999 and "99:99" or fmt("%02d:%02d", floor(s / 60), s % 60) end
  if s >= 6000 then return ">100m" end
  return fmt("%d:%02d", floor(s / 60), s % 60)
end

-- Color rules ------------------------------------------------------------

-- level(cuts) -> a function: v under cuts[1] is 1, under cuts[2] is 2 ...,
-- the rest #cuts + 1. Fast for one or two cuts (a processor's band)
function F.level(cuts)
  local a, b, n = cuts[1], cuts[2], #cuts
  if n == 1 then return function(v) return v < a and 1 or 2 end end
  if n == 2 then return function(v) if v < a then return 1 elseif v < b then return 2 end return 3 end end
  return function(v)
    for i = 1, n do if v < cuts[i] then return i end end
    return n + 1
  end
end

-- A theme color by name, looked up when drawn (a module's group, such as
-- theme.bcc, comes with its module): "danger", "bcc.hot1"
local function color_of(c)
  if type(c) ~= "string" then return function() return c end end
  local g, k = c:match("^([^.]+)%.(.+)$")
  if g then return function() local t = theme[g]; return t and t[k] end end
  return function() return theme[c] end
end
F.color_of = color_of

-- rule(cuts, colors) -> color(v): the color of v's level (colors one more
-- than cuts). rule({ 10 }, { "danger", "value" }): red under 10
function F.rule(cuts, colors)
  local lv, get = F.level(cuts), {}
  for i, c in ipairs(colors) do get[i] = color_of(c) end
  return function(v) return get[lv(v)]() end
end

-- Health: red under 20 %, yellow under 60, green (meter, the group's HP)
F.HEALTH = { 20, 60 }
F.HEALTH_COLORS = { "danger", "caution", "good" }

return F
