-- panel:meter { source, label, low, mid, w, x, y }
-- A value and its maximum ({ cur, max }: hp, mana, moves) as a percent to
-- one place: "HP 87.5" - red under low (20), yellow under mid (60), green
-- from there; "HP --", dim, until the maximum is known.
-- Processed: tenths of a percent and the color band in one integer, so
-- only a change you'd see redraws it.
local screen = require("ui.screen")
local theme = require("ui.theme")
local F = require("ui.format")
local paint, floor, fmt = screen.paint, math.floor, string.format

return screen.add_widget("meter", function(panel, t)
  local label = t.label or ""
  local level = F.level({ t.low or F.HEALTH[1], t.mid or F.HEALTH[2] })
  local colors = {}
  for i, c in ipairs(F.HEALTH_COLORS) do colors[i] = F.color_of(c) end
  local lead = label ~= "" and label .. " " or ""
  return panel:widget { source = t.source, w = t.w, x = t.x, y = t.y,
    process = function(r)
      if not r or r.max == 0 then return -1 end
      local pct = r.cur * 100 / r.max
      return floor(pct * 10 + 0.5) * 3 + level(pct) - 1
    end,
    format = function(k)
      if k < 0 then return paint(theme.unavailable, lead .. "--") end
      local band = k % 3
      local s = fmt("%.1f", (k - band) / 30)
      if band == 2 then return lead .. paint(colors[3](), s) end
      return paint(colors[band + 1](), lead .. s)
    end }
end)
