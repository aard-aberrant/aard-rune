-- panel:target { on, prefix, lines }: a quest's or campaign's target, a
-- line each - lines from "area" (cyan), "room" (blue), "mob" (magenta,
-- with its keyword); shown while the data name `on` is true, a missing one
-- left out. The data: prefix .. ".area", ".room", ".mob", ".keyword".
-- The colors (theme.target) are shared with the campaign's own lines.
local screen = require("ui.screen")
local theme = require("ui.theme")
require("ui.widgets.text")
theme.define("target", "Quest and campaign targets (info pane)", {
  { "area",  theme.cyan,    "the area" },
  { "room",  theme.blue,    "the room" },
  { "mob",   theme.magenta, "the mob" },
  { "gone",  theme.red,     "the room, when the target is killed or gone" },
})

return screen.add_widget("target", function(p, t)
  local on, pre = t.on, t.prefix
  for _, what in ipairs(t.lines) do
    if what == "mob" then
      p:text { y = "next", source = { on, pre .. ".mob", pre .. ".keyword" }, color = theme.target.mob,
        process = function(o, mob, kw) if o and mob then return kw and (mob .. " (" .. kw .. ")") or mob end end }
    else
      p:text { y = "next", source = { on, pre .. "." .. what }, color = theme.target[what],
        process = function(o, v) if o then return v end end }
    end
  end
end)
