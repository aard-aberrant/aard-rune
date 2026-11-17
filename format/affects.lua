-- Affects formatters (require("format.affects")): the affects pane's text
-- from process/affects.lua's values (which it unpacks).
local theme = require("ui.theme")
local P = require("process.affects")
-- The pane's own colors: theme.affects.* - /theme lists them,
-- data/theme.lua changes them (ui/theme.lua)
local T = theme.define("affects", "The affects pane", {
  { "totem_area",  theme.cyan, "the totem's area" },
})

local CFG, by_gen = P.cfg, P.by_gen
local ICONS = CFG.totem_icons or {}
local RED, GRN, GRAY, CYAN = theme.danger, theme.good, theme.muted, T.totem_area
local alert = theme.alert
local OFF = theme.unavailable   -- off: a spell not up, a bad one not on you, an empty timer band, no totem
local STYLE = { RED, theme.caution, GRN, GRAY }   -- by band (process/affects.lua)

local rep, floor, max = string.rep, math.floor, math.max
local function rjust(s, w) s = tostring(s); return rep(" ", w - #s) .. s end

local F = {}

-- An empty line
function F.blank() return "" end

-- Row i (P.row): the good label with its time or state (green, yellow at
-- 2 min, red at 1; off gray, black on red when important), and the bad
-- light at the right edge (gray, black on red while on you)
function F.row(i)
  return function(v, width)
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
  end
end

-- sk: N            sp: good/bad (P.counts), across the width
function F.counts(v, width)
  local sk, good, bad = floor(v / 1e6), floor(v / 1000) % 1000, v % 1000
  local gap = max((width or 0) - #("sk: " .. sk) - #("sp: " .. good .. "/" .. bad), 1)
  return GRAY("sk:") .. " " .. GRN(sk) .. rep(" ", gap) .. GRAY("sp:") .. " " .. GRN(good) .. GRAY("/") .. RED(bad)
end

-- One of the next to run out: its name, capitalized, in its band's color
function F.timer(b, name, cols)
  return STYLE[b]((name:sub(1, 1):upper() .. name:sub(2)):sub(1, cols))
end

-- The totem (P.totem): its icon (or type), minutes left and area; or
-- "totem ready in Nm", "totem ready", "no totem"
function F.totem(v, width)
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
end

return F
