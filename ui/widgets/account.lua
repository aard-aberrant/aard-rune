-- panel:account(): modules/account.lua's data.
-- Account: gold and worth; QP, TP, trains; HR and DR, red under your
-- subclass's minimum; any stat (not int) under the minimum, in red. Only
-- once GMCP char.worth has come (acct.known)
local screen = require("ui.screen")
local theme = require("ui.theme")
local F, P = require("ui.format"), require("ui.process")
local num, commas, short, round = F.num, F.commas, F.short, P.round
local paint, floor = screen.paint, math.floor
require("ui.widgets.value")

return screen.add_widget("account", function(p, t)
  local function gated(names, f)   -- nil until acct.worth is known
    table.insert(names, 1, "acct.known")
    return names, function(known, ...) if known then return f(...) end end
  end
  local L = theme.default   -- the labels
  local s, f
  s, f = gated({ "acct.gold" }, function(g) return g and round(g) end)
  p:value { source = s, process = f, label = "Gold ", label_color = L, show = short, w = 9 }
  s, f = gated({ "acct.worth" }, function(w) return w and round(w) end)
  p:value { source = s, process = f, label = "Worth ", label_color = L, show = short }
  s, f = gated({ "acct.qp" }, function(q) return q or 0 end)
  p:value { y = "next", source = s, process = f, label = "QP ", label_color = L, show = commas, w = 11 }
  s, f = gated({ "acct.tp" }, function(t) return t or 0 end)
  p:value { source = s, process = f, label = "TP ", label_color = L, w = 4 }
  s, f = gated({ "acct.trains" }, function(t) return t or "--" end)
  p:value { source = s, process = f, label = "TRN ", label_color = L,
    show = function(t) return type(t) == "number" and num(t) or t end }
  -- HR / DR: the value, and 1 more when under the minimum (both shown or neither)
  local function vs_min(lbl, name, min, width, first)
    s, f = gated({ "acct.hr", "acct.dr", min }, function(hr, dr, m)
      local v = name == "acct.hr" and hr or dr
      if hr and dr then return v * 2 + ((m and v < m) and 1 or 0) end
    end)
    p:value { y = first and "next" or nil, source = s, process = f, label = lbl, label_color = L, w = width,
      show = function(k) return num(floor(k / 2)) end,
      color = function(k) return k % 2 == 1 and theme.danger or theme.value end }
  end
  vs_min("HR ", "acct.hr", "acct.hr_min", 11, true)
  vs_min("DR ", "acct.dr", "acct.dr_min")
  -- the stats under the minimum
  local STATS = { "str", "wis", "con", "dex", "luck" }
  local names = {}
  for k, st in ipairs(STATS) do names[k] = "acct." .. st end
  names[#names + 1] = "acct.stat_min"
  s, f = gated(names, function(...)
    local v = { ... }
    local m, out = v[#STATS + 1], {}
    if not m then return nil end
    for k, st in ipairs(STATS) do
      if v[k] and v[k] < m then out[#out + 1] = (st == "luck" and "LCK" or st:upper()) .. " " .. num(v[k]) end
    end
    if #out > 0 then return table.concat(out, "\1") end
  end)
  p:widget { y = "next", source = s, process = f,
    format = function(v)
      if not v then return nil end
      local parts = {}
      for x in v:gmatch("[^\1]+") do parts[#parts + 1] = paint(theme.danger, x) end
      return table.concat(parts, "  ")
    end }
end)
