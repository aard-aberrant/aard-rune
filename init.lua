-- Rune trial for Aardwolf (2026-11-06)
-- Port of the tt++ setup (aardwolf-tintin), piece by piece. See TODO.md.

-- The same GMCP packages the tt++ setup asks for (modules/gmcp.tin)
for _, pkg in ipairs({ "Char", "Room", "Comm", "Core", "Group" }) do
  rune.gmcp.subscribe(pkg, 1)
end

-- The files, by folder (organized by module, 2026-11-15). Lua's require
-- runs each once, and /reload starts a fresh Lua state. A file returns its
-- table when others use it; requires never go in a circle:
--   lib/       util, debug, help, profile - game-agnostic, the framework;
--              they require nothing of the modules
--   ui/        colors, theme, view (the data), screen (the display engine),
--              widgets/ (the generic widgets) - framework
--   process/, format/  processors and formatters: generic.lua, and one
--              file per module for its data (affects, quest, group ...)
--   data/layout/  the screen (screen.lua: the containers' rectangles) and
--              what each container shows (status, group, chats, info,
--              affects, minimap): generic widgets on the modules' data
--   modules/   everything that does something in the game or knows Aardwolf:
--              game (GMCP state), tags, group, mapper, travel, quest, dps ...
--              a module requires the libraries and the modules it uses
--   modules/zones/  loader (modules/zones/<zone>.lua while you're in the
--              zone: geniewish, knossos, blackclaw ...) - a script may
--              require anything
-- Then the per-subclass ones (data/classes/<subclass>.lua's modules), below
-- data/ is settings, game data and the layout, map/ the map, tools/ the
-- converters and benchmarks.
-- This file only sets Rune up and lists the features
local util = require("lib.util")
-- /profile (lib/profile.lua). After /profile startup, it times every
-- require from here to startup_end() below; otherwise both do nothing
local profile = require("lib.profile")
profile.startup_begin()
require("data.layout.screen")  -- the containers (and ui/picker.lua)

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
-- status line shows SCROLLED meanwhile (data/layout/status.lua). A pane can't take a
-- background colour - Rune's layout refuses bg/background/style (tried)
rune.hooks.on("input", function()
  if rune._state.scroll_mode ~= "scrolled" then return end
  pcall(rune.pane.scroll_to_bottom, "output")
  pcall(rune.binds._dispatch, "ctrl+end")
end, { name = "jump_on_input" })

-- The features, by folder. Each requires what it uses, so the order
-- doesn't matter
require("lib.help")             -- /help: every command, registered by its module
require("lib.debug")            -- debug [topic] [on|off]: the modules' debug output
require("ui.view")              -- the display engine: modules publish data, widgets show it
require("modules.login")        -- answers the login prompts from .env
require("modules.history")      -- command history kept in history.txt across restarts
require("modules.tags")         -- the game's tag lines, hidden or cut out
require("modules.aliases")      -- one-line aliases: su, sq, qs, gh ...
require("modules.copy")         -- /copy <n>: the last n lines of the main pane to the clipboard
require("modules.act")          -- /act, /unact: ad hoc triggers, kept in acts.txt
require("modules.group")        -- your group, from GMCP group (the group pane shows it)
require("modules.alerts")       -- alerts: a title and text, crit or warn (the info pane flashes them)
require("modules.account")      -- gold, points and stats, from GMCP (the info pane shows them)
require("modules.infomsg")      -- infomsg: your own text on the info pane
require("data.layout.status")  -- the status bars (TCK, HP/MN/MV, the enemy ...) - before the
                                -- group pane: its first bar runs the engine's pass (no extra bar)
require("data.layout.group")    -- the group pane
require("data.layout.chats")    -- the chats pane: channels, tells, remote socials
require("data.layout.info")     -- the info pane: bcc, alerts, infomsg, quest, campaign, account; infopane
require("modules.timer")        -- timer
require("data.layout.affects")  -- the affects pane, saf, affectsreset
require("modules.eq")           -- eqwear, eqsave, eqcheck, eqsets
require("data.layout.minimap")  -- the minimap pane (modules/minimap.lua: the game's map tag)
require("modules.mapper")       -- map/aard.map, kept current from GMCP room.info
require("modules.maprec")       -- map record: custom exits from what you do
require("modules.travel")       -- routes and g, ga, find, label
require("modules.arrows")       -- arrows: walk mode, the arrow keys move (WLK); Tab toggles
require("modules.repop")        -- the POP light, pop
require("modules.target")       -- the target: target / t, gm
require("modules.quest")        -- qx
require("modules.campaign")     -- cn
require("modules.soh")          -- soh: School of Horror mob keywords
require("modules.combat")       -- k, kk, aa
require("modules.autocast")     -- ac, the AC light
require("modules.heal")         -- h: incomplete healing, held for the gap between kills
require("modules.hunt")         -- autohunt, hqq
require("modules.dps")          -- the DPS meter
require("modules.rheal")        -- rh, sleep, the regen ring on waking
require("modules.pup")          -- pup: powerup pace
require("modules.doubles")      -- 2XP / 2QP lights, double
require("modules.instinct")     -- inst: instinct above 0 on one line, copied
require("modules.quiet")        -- a fight's xp and gold on one line at its end, tells reminder, skinning hidden
require("modules.bcc")          -- bcc, bcc find: Black Claw Crag (the fight: modules/zones/blackclaw.lua)
require("modules.spup")         -- spup, spn, spq: hosting spellups
require("modules.zones.loader") -- modules/zones/<zone>.lua, only while you're in that zone

-- Per-subclass features: the modules in data/classes/<subclass>.lua's
-- `modules` list (Shaman: modules.moons) load only on that subclass - the ones
-- above load on every one. Last here, so such a module may come from any
-- folder. The subclass comes in GMCP char.base:
--   at the first login after Rune starts, its modules load then. From
--     game.on_login, so the login actions they add still run for this
--     login (game.lua's loop runs ones added while it runs)
--   a /reload loads them at once: the subclass is kept in rune.session
--   a different subclass later (a remort, another character): a /reload
--     (rune.reload) - Lua can't take a module's triggers and slots back out
local game = require("modules.game")

-- Weather messages off at every login (config noweather on). modules/moons (a
-- Shaman's) turns them back on: its login action comes later in game.lua's
-- list - registered after this one, at /reload and at the first login
-- alike - so it wins. Registered here, before any per-subclass module can
-- load. The reply's shape is a guess from moons' "## Setting noweather to
-- off." - hidden if it matches, shown as it comes if not
game.on_login(function()
  util.await("exact", "## Setting noweather to on.", function(_, ctx)
    return util.hide(ctx)
  end, "init_noweather_reply")
  rune.gmcp.send("config noweather on")
end)

local class_for = rune.session.get("class_modules")
local function load_class(sub)
  local C = util.class_data(sub)
  for _, m in ipairs(C and C.modules or {}) do
    local ok, err = pcall(require, m)
    if not ok then util.err("[init] " .. sub .. "'s " .. m .. " didn't load: " .. tostring(err)) end
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
    util.say("[init] subclass now " .. sub .. " - reloading for its modules.")
    rune.timer.after(0, rune.reload)   -- after this handler, not inside it
  else
    load_class(sub)
  end
end
game.on_login(class_check)
rune.gmcp.on("char.base", class_check, { name = "init_class_modules" })

profile.startup_end()   -- the requires above, timed after /profile startup

-- /reload starts every table above empty, and the game only sends char.*
-- and group when something changes - ask for both so the bar and the group
-- pane fill at once (the plain "request group" form, confirmed live). The
-- room too: the mapper and the travel commands need to know where you are.
-- char now: its char.base is what fires game.on_login after a /reload. The
-- rest at each login (and so after a /reload too): sent at load on a fresh
-- start they went out before you were in the game, and no room came until
-- you moved (2026-11-13: qx after a login found no room)
rune.gmcp.send("request char")
game.on_login(function()
  rune.gmcp.send("request group")
  rune.gmcp.send("request room")
  rune.gmcp.send("request quest")   -- QST
end)

util.say("[init] loaded.")
