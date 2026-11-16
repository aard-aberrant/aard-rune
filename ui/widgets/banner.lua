-- panel:banner { source, style, band, missing, missing_style, x, y }
-- A line of text centered on a band, cut to the width (an odd column over
-- on the right). The text may carry the game's own colors: its resets
-- (ESC[0m, ESC[0;37m) would end the band and the style, so they're put
-- back after each one, then the game's color.
--   source: a data name (the text), or two: { on, text } - on false shows
--     missing
--   style, band: theme names ("group.title", "group.title_band"), read
--     when drawn - style the text's own, band the row's background
--   missing: shown when the value is false (on false, or the one source
--     false), in missing_style (a theme name, default "muted"), on the band
-- nil or "" shows nothing (no row).
local screen = require("ui.screen")
local colors = require("ui.colors")
local F = require("ui.format")
local floor, rep = math.floor, string.rep
local RESET = colors.RESET

-- the game's resets: put on back after each, then the game's color; any
-- other code starting 0 (ESC[01;33m: bold) is not a reset - left as it is
local function keep_style(v, on)
  return (v:gsub("\27%[0([%d;]*)m", function(rest)
    if rest == "" then return RESET .. on end
    if rest:sub(1, 1) == ";" then return RESET .. on .. "\27[" .. rest:sub(2) .. "m" end
  end))
end

return screen.add_widget("banner", function(panel, t)
  local style, band = F.color_of(t.style), F.color_of(t.band)
  local missing, mstyle = t.missing, F.color_of(t.missing_style or "muted")
  local src, process = t.source, nil
  if type(src) == "table" and #src == 2 then
    process = function(on, v) if on == false then return false end return v end
  end
  local function on_of(c) local s = c(); return s and s.on or "" end
  return panel:widget { source = src, process = process, w = "*", x = t.x, y = t.y,
    format = function(v, wd)
      if v == nil or v == "" or (v == false and not missing) then return nil end
      local b = on_of(band)
      local text
      if v == false then
        text = b .. on_of(mstyle) .. missing
      else
        local on = b .. on_of(style)
        text = on .. keep_style(v, on)
      end
      local s = colors.crop(text, wd)
      local gap = wd - colors.width(s)
      local left = floor(gap / 2)
      return b .. rep(" ", left) .. s .. b .. rep(" ", gap - left) .. RESET
    end }
end)
