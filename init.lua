-- Rune trial for Aardwolf (2026-11-06)
-- Port of the tt++ setup (aardwolf-tintin), piece by piece. See TODO.md.

-- The same GMCP packages the tt++ setup asks for (modules/gmcp.tin)
for _, pkg in ipairs({ "Char", "Room", "Comm", "Core", "Group" }) do
  rune.gmcp.subscribe(pkg, 1)
end

-- The files, by folder. Each requires only from its own folder or the ones
-- above it in this list, with a note on why (Lua's require: each runs once,
-- and /reload starts a fresh Lua state), and returns its table when others
-- use it:
--   core/      util, game (GMCP state), layout, tags, aliases, login, history, debug, help -
--              core/layout, core/game and core/util require nothing of ours
--   panes/     status, group, chats, info, affects, and timer (which
--              shows in info). Features plug into the panes (status's slots,
--              info.set); a pane never requires a feature
--   gear/      eq, invmon
--   nav/       mapper, travel, minimap (the map's pane), moons (Shaman only), repop
--   targets/   target, and quest and campaign, which set it; doubles, soh
--   fight/     combat, autocast, heal, hunt, dps, rheal, pup, instinct, quiet, bcc
--   host/      spup (hosting spellups)
--   areas/     loader (areas/<zone>.lua while you're in the zone: geniewish,
--              knossos, blackclaw ...) - a script may require anything above
-- Then the per-subclass ones (data/classes/<subclass>.lua's modules), below
-- data/ is settings and game data, map/ the map, tools/ the converters.
-- This file only sets Rune up and lists the features
local util = require("core.util")
require("core.layout")     -- the panes, and the picker wrapper

-- Ctrl+E goes to the end of the input line, as in a shell (Ctrl+A already
-- goes to the start). Rune binds Ctrl+E to "edit the line in $EDITOR" -
-- that moves to Alt+E. set_cursor takes a byte offset, and #text is the
-- line's length in bytes
rune.bind("ctrl+e", function()
  rune.input.set_cursor(#rune.input.get())
end)
rune.bind("alt+e", "input.open_editor")

-- Mouse wheel scrolling (3 lines a tick, the pane under the pointer - our
-- patched Rune; stock Rune scrolls only the main output). While Rune has
-- the mouse, a drag goes to Rune, not to tmux or the terminal, so text can't
-- be selected. F12 switches it: on to scroll with the wheel, off to select
-- and copy. Starts on. Off, a drag is tmux's (mouse on in tmux.conf) and
-- takes whole screen rows; R during the drag makes it a rectangle - one
-- pane (confirmed live 2026-11-07), copied to the clipboard on release
local mouse_on = true
rune.config.set("mouse", mouse_on)
rune.bind("f12", function()
  mouse_on = not mouse_on
  rune.config.set("mouse", mouse_on)
  if mouse_on then
    util.say("[mouse] wheel scrolling on - F12 to select text")
  else
    util.say("[mouse] off - drag to select (R while dragging: one pane only), F12 for wheel scrolling")
  end
end)

-- Sending a command while the main pane is scrolled back jumps it to live
-- output, as Ctrl+End would (Rune's own binding, 95_ui.lua - run through
-- binds._dispatch; scroll_to_bottom on the pane as well, in case). The
-- status line shows SCROLLED meanwhile (panes/status.lua). A pane can't take a
-- background colour - Rune's layout refuses bg/background/style (tried)
rune.hooks.on("input", function()
  if rune._state.scroll_mode ~= "scrolled" then return end
  pcall(rune.pane.scroll_to_bottom, "output")
  pcall(rune.binds._dispatch, "ctrl+end")
end, { name = "jump_on_input" })

-- The features, by folder. Each requires what it uses, so the order
-- doesn't matter
require("core.help")         -- /help and xhelp: every command, registered by its module
require("core.debug")        -- debug [topic] [on|off]: the modules' debug output
require("core.login")        -- answers the login prompts from .env
require("core.history")      -- command history kept in history.txt across restarts
require("core.tags")         -- the game's tag lines, hidden or cut out
require("core.aliases")      -- one-line aliases: su, sq, qs, gh ...
require("panes.group")       -- the group pane
require("panes.chats")       -- the chats pane: channels, tells, remote socials
require("panes.status")      -- the status bars (TCK, HP/MN/MV, Enemy ...)
require("panes.info")        -- the info pane: quest, campaign, alerts, account, infomsg
require("panes.timer")       -- timer
require("panes.affects")     -- the affects pane, saf, affectsreset
require("gear.eq")           -- eqwear, eqsave, eqcheck, eqsets
require("nav.minimap")       -- the minimap pane, from the game's map tag
require("nav.mapper")        -- map/aard.map, kept current from GMCP room.info
require("nav.maprec")        -- map record: custom exits from what you do
require("nav.travel")        -- routes and g, ga, find, label
require("nav.repop")         -- the POP light, pop
require("targets.target")    -- the target: target / t, gm
require("targets.quest")     -- qx
require("targets.campaign")  -- cn
require("targets.doubles")   -- 2XP / 2QP lights, double
require("targets.soh")       -- soh: School of Horror mob keywords
require("fight.combat")      -- k, kk, aa
require("fight.autocast")    -- ac, the AC light
require("fight.heal")        -- h: incomplete healing, held for the gap between kills
require("fight.hunt")        -- autohunt, hqq
require("fight.dps")         -- the DPS meter
require("fight.rheal")       -- rh, sleep, the regen ring on waking
require("fight.pup")         -- pup: powerup pace
require("fight.instinct")    -- inst: instinct above 0 on one line, copied
require("fight.quiet")       -- a fight's xp and gold on one line at its end, tells reminder, skinning hidden
require("fight.bcc")         -- bcc, bcc find: Black Claw Crag (the fight: areas/blackclaw.lua)
require("host.spup")         -- spup, spn, spq: hosting spellups
require("areas.loader")      -- areas/<zone>.lua, only while you're in that zone

-- Per-subclass features: the modules in data/classes/<subclass>.lua's
-- `modules` list (Shaman: nav.moons) load only on that subclass - the ones
-- above load on every one. Last here, so such a module may come from any
-- folder. The subclass comes in GMCP char.base:
--   at the first login after Rune starts, its modules load then. From
--     game.on_login, so the login actions they add still run for this
--     login (game.lua's loop runs ones added while it runs)
--   a /reload loads them at once: the subclass is kept in rune.session
--   a different subclass later (a remort, another character): a /reload
--     (rune.reload) - Lua can't take a module's triggers and slots back out
local game = require("core.game")

-- Weather messages off at every login (config noweather on). nav/moons (a
-- Shaman's) turns them back on: its login action comes later in game.lua's
-- list - registered after this one, at /reload and at the first login
-- alike - so it wins. Registered here, before any per-subclass module can
-- load. The reply's shape is a guess from moons' "## Setting noweather to
-- off." - hidden if it matches, shown as it comes if not
game.on_login(function()
  util.await("exact", "## Setting noweather to on.", function(_, ctx)
    util.eat_blanks(ctx.line:clean())
    return false
  end, "init_noweather_reply")
  rune.gmcp.send("config noweather on")
end)

local class_for = rune.session.get("class_modules")
local function load_class(sub)
  local C = util.load_data(rune.config_dir .. "/data/classes/" .. sub:lower() .. ".lua")
  for _, m in ipairs(C and C.modules or {}) do
    local ok, err = pcall(require, m)
    if not ok then util.err("[init.lua] " .. sub .. "'s " .. m .. " didn't load: " .. tostring(err)) end
  end
end
if class_for then load_class(class_for) end
local function class_check()
  local sub = game.subclass
  if not sub or sub == class_for then return end
  rune.session.set("class_modules", sub)
  local was = class_for
  class_for = sub   -- once: more char.base before the reload ask for none
  if was then
    util.say("[init.lua] subclass now " .. sub .. " - reloading for its modules.")
    rune.timer.after(0, rune.reload)   -- after this handler, not inside it
  else
    load_class(sub)
  end
end
game.on_login(class_check)
rune.gmcp.on("char.base", class_check, { name = "init_class_modules" })

-- /reload starts every table above empty, and the game only sends char.*
-- and group when something changes - ask for both now so the bar and the
-- group pane fill at once (the plain "request group" form, confirmed live).
-- The room too: the mapper and the travel commands need to know where you are
rune.gmcp.send("request char")
rune.gmcp.send("request group")
rune.gmcp.send("request room")
rune.gmcp.send("request quest")   -- QST

util.say("[init.lua] loaded.")
