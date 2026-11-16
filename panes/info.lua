-- The info pane (tt++ modules/info.tin) - PROTOTYPE on ui/screen.lua.
-- Several things want the 4-line pane but only one can have it: a
-- priority panel shows the first item with something to show:
--   bcc         10  Black Claw Crag's breath grid (modules/zones/blackclaw.lua)
--   alert_crit  20  an alert (modules/alerts.lua), flashing black on red
--   alert_warn  25  the same, black on yellow
--   msg         40  your own text (infomsg, modules/infomsg.lua)
--   quest       50  the quest's target (modules/quest.lua)
--   campaign    60  the campaign's (modules/campaign.lua)
--   account     90  gold, worth, QP, TP, trains, HR/DR, low stats (modules/account.lua)
-- An item has something while one of its widgets' processor returns a
-- value (nil: nothing). Each kind of content is a widget (ui/widgets/),
-- for an item here or a panel of its own: moving account to its own
-- panel is a rectangle in ui/layout.lua and screen.panels.acct:account(),
-- no module touched.
-- What the pane shows is published as info.shown - an alert counts down
-- only while it shows.
-- infopane: list the items / pin one / reset (see the end).
local util = require("lib.util")
require("ui.layout")
local screen = require("ui.screen")
require("ui.widgets.bcc")        -- panel:bcc
require("ui.widgets.alert")      -- panel:alert
require("ui.widgets.infomsg")    -- panel:infomsg
require("ui.widgets.quest")      -- panel:quest
require("ui.widgets.campaign")   -- panel:campaign
require("ui.widgets.account")    -- panel:account

-- The info panel: the items, first wins
local PIN = "info_pin"  -- rune.session: the pinned item's name
local pin = rune.session.get(PIN)
if pin == "" then pin = nil end
local pick = screen.panels.info:priority { shown = "info.shown", pin = function() return pin end }
pick:item { name = "bcc", prio = 10 }:bcc()
pick:item { name = "alert_crit", prio = 20, keep = true }:alert { level = "crit" }
pick:item { name = "alert_warn", prio = 25, keep = true }:alert { level = "warn" }
pick:item { name = "msg", prio = 40 }:infomsg()
pick:item { name = "quest", prio = 50 }:quest()
pick:item { name = "campaign", prio = 60 }:campaign()
pick:item { name = "account", prio = 90 }:account()

-- infopane: list, pin, reset (see the top)
rune.alias.exact("infopane", function(args)
  local arg = util.trim(args):lower()
  if arg == "" then
    util.say("[info] info pane items (the first with something to show wins):")
    local now = screen.peek(pick)
    for _, it in ipairs(pick.list) do
      local state = it.name == pick.shown and "on the pane" or (now[it.name] and "showing" or "idle")
      rune.echo(string.format("  %-11s %3d  %s%s", it.name, it.prio, state, it.name == pin and "  (pinned)" or ""))
    end
    return
  end
  if arg == "reset" then
    pin = nil
    rune.session.set(PIN, "")
    pick:refresh()
    util.say("[info] info pane: back to the normal order.")
    return
  end
  local hits = {}
  for _, it in ipairs(pick.list) do
    if it.name == arg then hits = { it.name }; break end
    if it.name:sub(1, #arg) == arg then hits[#hits + 1] = it.name end
  end
  if #hits == 0 then util.warn("[info] infopane: nothing called \"" .. arg .. "\" - infopane lists them."); return end
  if #hits > 1 then util.warn("[info] infopane: \"" .. arg .. "\" could be " .. table.concat(hits, ", ") .. "."); return end
  pin = hits[1]
  rune.session.set(PIN, pin)
  pick:refresh()
  util.say("[info] info pane: pinned to " .. pin
    .. (screen.peek(pick)[pin] and "" or ", which has nothing to show yet - it shows when it does")
    .. ". infopane reset to undo.")
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("infopane", "infopane [<name>|reset]", "list what can show in the info pane; <name>: pin one (it shows whenever it has something, beating all but an alert); reset: the normal order again")

return {}
