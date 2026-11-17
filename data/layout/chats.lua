-- The chats pane: modules/chats.lua's chat lines (chat.line), each
-- appended as it comes (format/chats.lua: its time first, then the line).
require("data.layout.screen")
require("modules.chats")
require("ui.screen").containers.chats:append { source = "chat.line", format = require("format.chats").line }

-- Scrolling the chats pane. PgUp/PgDn and Ctrl+Home/Ctrl+End scroll the
-- main output (Rune's defaults); the same keys with Alt scroll chats, and
-- Alt+End goes back to live tailing. Shift too - but most terminals keep
-- Shift+PgUp for their own scrollback (Shift didn't scroll chats live
-- 2026-11-07 - the terminal, presumably). The mouse wheel scrolls the pane
-- under the pointer - with our patched Rune (branch scrolling-panes on the
-- aard-aberrant fork, PR'd upstream); stock Rune 5d808d6 sends every wheel
-- tick to the main output
local function up() rune.pane.scroll_up("chats", 10) end
local function down() rune.pane.scroll_down("chats", 10) end
local function live() rune.pane.scroll_to_bottom("chats") end
for _, mod in ipairs({ "alt", "shift" }) do
  rune.bind(mod .. "+pgup", up)
  rune.bind(mod .. "+pgdown", down)
  rune.bind(mod .. "+end", live)
end
