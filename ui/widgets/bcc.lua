-- panel:bcc(): Black Claw Crag's breath grid (modules/zones/blackclaw.lua's
-- bcc.* data): the last breath and the safe side, then the lair as a
-- grid - a square's seconds left (red, orange at 2, yellow at 1), then
-- dots once clear, green on the safe side; @@ Axaldra's column. Its colors
-- (theme.bcc) come with the zone script
local screen = require("ui.screen")
local theme = require("ui.theme")
local F = require("ui.format")
local paint, rpad, num = screen.paint, screen.rpad, F.num
local max, rep = math.max, string.rep
-- a square's seconds left: red under 2, orange under 3, then yellow
local hot = F.rule({ 2, 3 }, { "bcc.hot1", "bcc.hot2", "bcc.hot3" })

return screen.add_widget("bcc", function(p, t)
  p:widget { source = { "bcc.dir", "bcc.safe" },
    process = function(dir, safe) return dir and dir .. "|" .. (safe or "") end,
    format = function(v)
      local dir, safe = v:match("^(.-)|(.*)$")
      local B = theme.bcc
      return paint(B.label, "Axaldra: ") .. paint(B.value, dir) .. "  " .. paint(B.label, "safe: ") .. paint(B.safe, safe)
    end }
  local function cell(c)
    p:widget { source = { "bcc.dir", "bcc." .. c, "bcc." .. c .. "_safe" }, every = 1,
      process = function(dir, t, safe, now)
        if not dir then return nil end
        local left = t and max(0, t - now) or 0
        if left > 0 then return left end
        return safe and -1 or -2
      end,
      format = function(v)
        local B = theme.bcc
        if v > 0 then return paint(hot(v), rpad(num(v), 2)) end
        return paint(v == -1 and B.safe or B.quiet, "..")
      end }
  end
  local PAD, GAP = rep(" ", 10), "  "
  for _, row in ipairs({ { "nw", "n", "ne" }, { "w", false, "e" }, { "sw", "s", "se" } }) do
    p:widget { y = "next", text = PAD }
    cell(row[1]); p:widget { text = GAP }
    if row[2] then cell(row[2])
    else p:widget { source = "bcc.dir", format = function(d) return d and paint(theme.bcc.value, "@@") end } end
    p:widget { text = GAP }; cell(row[3])
  end
end)
