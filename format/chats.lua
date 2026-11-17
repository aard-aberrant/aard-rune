-- Chat formatters (require("format.chats")): a chat line as the chats
-- pane, /copy chat and the log show it - its time first (HH:MM, dim),
-- then the line in the game's colors.
local theme = require("ui.theme")
local M = {}
function M.line(e) return theme.muted(os.date("%H:%M", e.time)) .. " " .. e.text end
return M
