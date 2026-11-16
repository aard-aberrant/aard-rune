-- panel:alert { level = "crit" | "warn" }: modules/alerts.lua's alert of that
-- level.
-- An alert: the title, then the text wrapped, across the pane on a block
-- that flashes each second (black on red / red text; yellow for a warn)
local screen = require("ui.screen")
local theme = require("ui.theme")
local paint = screen.paint
local max, rep = math.max, string.rep
local util = require("lib.util")
local RESET = require("ui.colors").RESET

return screen.add_widget("alert", function(p, t)
  local lvl = t.level
  local on, off = lvl == "crit" and "alert" or "alert_caution", lvl == "crit" and "danger" or "caution"
  p:widget { source = { "alert." .. lvl .. ".title", "alert." .. lvl .. ".text" }, every = 1, w = "*",
    process = function(title, text, now)
      if title == nil then return nil end
      return (now % 2 == 0 and "1" or "0") .. title .. "\1" .. (text or "")
    end,
    format = function(v, wd, room)
      local title, text = v:sub(2):match("^(.-)\1(.*)$")
      local c = theme[v:sub(1, 1) == "1" and on or off].on
      local function fill(x) return #x < wd and x .. rep(" ", wd - #x) or x:sub(1, wd) end
      local body = util.wrap(text, wd)
      local most = max(room - 1, 0)
      local rows = { title }
      if #body < most then rows[2] = "" end
      for k = 1, math.min(#body, most) do rows[#rows + 1] = body[k] end
      for k, row in ipairs(rows) do rows[k] = c .. fill(row) .. RESET end
      return table.concat(rows, "\n")
    end }
end)
