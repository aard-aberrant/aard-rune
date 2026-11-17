-- Log colors (require("format.log")): REC on the status bar, flashing
-- while a /log is open (theme.rec).
local colors = require("ui.colors")
local theme = require("ui.theme")
local mix, bg = colors.mix, colors.bg
return theme.define("rec", "REC (status bar)", {
  { "on",     mix(theme.black_tc, bg(theme.red)), "REC while a log is open, flashing with rec.flash" },
  { "flash",  theme.red,                          "REC's other flash" },
})
