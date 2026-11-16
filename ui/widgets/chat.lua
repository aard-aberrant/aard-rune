-- panel:chat(): panes/chats.lua's chat lines (chat.line), each appended
-- as it comes - its time first (HH:MM, dim), then the line in the game's
-- colors.
local screen = require("ui.screen")
local theme = require("ui.theme")

return screen.add_widget("chat", function(p)
  return p:append { source = "chat.line",
    format = function(e) return theme.muted(os.date("%H:%M", e.time)) .. " " .. e.text end }
end)
