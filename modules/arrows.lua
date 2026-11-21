-- Walk mode: the arrow keys walk - up n, down s, left w, right e, Shift+Up
-- u, Shift+Down d - in place of their usual jobs (up/down: history;
-- left/right: the cursor; Shift+Up/Down: none, so with text typed nothing).
-- Toward a closed door - the minimap's map block for this room, its exits
-- line ("(W)") - a move opens it first, then goes once it opened (no key: stays). Not known (no map
-- block for this room yet): the plain move. Option+arrow (Option+Shift+
-- Up/Down for u/d): "retreat <direction>". Tab on an
-- empty input line toggles it; with text typed, Tab completes as before.
--   arrows [on|off]   the same, as a command (no word: toggle)
-- WLK on status row 2 while it's on (data/layout/status.lua). Off at load
-- (and /reload). A move is sent as if typed (rune.send: aliases, speedwalk).
-- While on, the arrows walk only on an empty line; with text typed they do
-- their usual job (history, the cursor). An inline picker (Tab
-- completion, /) still takes up/down first.
-- Off puts back what was there: up/down's saved actions (Rune's history
-- binds, read at load - /reload rebuilds Rune's defaults first), and
-- left/right unbound (the cursor is Rune's fallback; a disabled bind
-- would swallow the key). Cost: nothing per line; four binds per toggle
local util = require("lib.util")
local game = require("modules.game")   -- the room (game.room.num)
local colors = require("ui.colors")
local theme = require("ui.theme")
-- This module's color: theme.walk.on - /theme lists it, data/theme.lua
-- changes it (ui/theme.lua)
theme.define("walk", "WLK (status bar)", {
  { "on", colors.mix(theme.black_tc, colors.bg(theme.cyan)), "WLK: the arrow keys walk" },
})

-- Shift+Up / Shift+Down: up and down (only if the terminal tells them from
-- plain Up / Down - Rune's docs: modified arrows depend on the terminal)
local MOVES = { up = "n", down = "s", left = "w", right = "e", ["shift+up"] = "u", ["shift+down"] = "d" }
local WORD = { n = "north", s = "south", w = "west", e = "east", u = "up", d = "down" }
-- Option+arrow: "retreat <direction>" (the terminal sends Option+Left/Right
-- as alt+b/alt+f). Sent only on a key press, never by itself
local RETREATS = { ["alt+up"] = "n", ["alt+down"] = "s", ["alt+b"] = "w", ["alt+f"] = "e",
  ["alt+shift+up"] = "u", ["alt+shift+down"] = "d" }

-- Rune's own actions for these keys, nil where there's no bind
local saved = {}
for _, keys in ipairs({ MOVES, RETREATS }) do
  for key in pairs(keys) do
    local b = rune.binds.get(key)
    saved[key] = b and b:action() or nil
  end
end

-- Published (ui/view.lua): walk mode on or off - the WLK light
local view = require("ui.view")
local V = view.provides("arrows", "walk mode (arrow keys)", {
  ["walk.on"] = { "boolean", "the arrow keys walk" },
})
local on = false
V.set("walk.on", on)

-- A move that way. Toward a closed door: "open <dir>" alone, and the move
-- only once the game says it opened ("You open the door." - or the
-- grating, the stable doors ...: a line starting "You open "; a keyring's
-- "You unlock ..." comes first), or that it was open all along ("The door
-- is already open." - the map block was out of date; the user,
-- 2026-11-20). "You do not have a key for the door.": no move. The first
-- and last from the user's logs (2026-11-17). Any other reply leaves it
-- waiting until the next arrow, which drops it - no timer. Cost: three
-- triggers, on only while a door is waiting
local door_wait = util.group()
local door_dir   -- the move waiting for its door
local function door_done(go)
  door_wait.set(false)
  local dir = door_dir
  door_dir = nil
  if go and dir then rune.send(dir) end
end
door_wait.add("starts", "You open ", function() door_done(true) end, { name = "arrows_door_opened" })
door_wait.add("exact", "The door is already open.", function() door_done(true) end, { name = "arrows_door_was_open" })
door_wait.add("exact", "You do not have a key for the door.", function() door_done(false) end, { name = "arrows_door_no_key" })

-- A closed door that way? From the minimap's last map block, if it's this
-- room's (map.block.room): its exits line, "[ Exits: N E S (W) U D ]" (seen
-- live 2026-11-17) - a direction in parentheses, by its first letter (so
-- "(west)" too). Read only here, at the key: nothing with WLK off. Not
-- known (no block for this room yet, no exits line): no
local function closed(dir)
  local b = view.get("map.block")
  if not (b and b.exits and b.room and b.room == game.room.num) then return false end
  local inner = colors.strip(b.exits):match("%[%s*Exits:%s*(.-)%s*%]")
  for w in (inner or ""):gmatch("%((%a+)%)") do
    if w:sub(1, 1):lower() == dir then return true end
  end
  return false
end

local function move(dir)
  door_done(false)   -- a door still waiting: dropped
  if closed(dir) then
    door_dir = dir
    door_wait.set(true)
    rune.send("open " .. WORD[dir])
  else
    rune.send(dir)
  end
end

-- With text typed, the arrows' usual job: up/down Rune's saved action
-- (history); left/right the cursor by one character (Rune's offsets are
-- UTF-8 bytes: a character's continuation bytes, 0x80-0xBF, are stepped over)
local function cursor(step)
  local text, pos = rune.input.get(), rune.input.get_cursor()
  repeat
    pos = pos + step
    local b = text:byte(pos + 1)
  until pos <= 0 or pos >= #text or not (b and b >= 0x80 and b < 0xC0)
  rune.input.set_cursor(math.max(0, math.min(pos, #text)))
end
-- A word back or forward (Option+Left/Right with text typed): past any
-- spaces, then past the word
local function word(step)
  local text, pos = rune.input.get(), rune.input.get_cursor()
  local n = #text
  local function at(p) return text:sub(p, p) end   -- the character after offset p-1
  if step < 0 then
    while pos > 0 and at(pos):match("%s") do pos = pos - 1 end
    while pos > 0 and not at(pos):match("%s") do pos = pos - 1 end
  else
    while pos < n and at(pos + 1):match("%s") do pos = pos + 1 end
    while pos < n and not at(pos + 1):match("%s") do pos = pos + 1 end
  end
  rune.input.set_cursor(pos)
end
local USUAL = { left = function() cursor(-1) end, right = function() cursor(1) end,
  ["alt+b"] = function() word(-1) end, ["alt+f"] = function() word(1) end }

local function retreat(dir)
  door_done(false)
  rune.send("retreat " .. WORD[dir])
end

local function bind_keys(keys, act)
  for key, dir in pairs(keys) do
    if on then
      local usual = type(saved[key]) == "function" and saved[key] or USUAL[key]
      rune.bind(key, function()
        if rune.input.get() == "" then act(dir) elseif usual then usual() end
      end)
    elseif saved[key] then
      rune.bind(key, saved[key])
    else
      rune.unbind(key)
    end
  end
end

local function set(want)
  if want == on then return end
  on = want
  bind_keys(MOVES, move)
  bind_keys(RETREATS, retreat)
  V.set("walk.on", on)
  V.publish()
  util.say("[arrows] " .. (on and "walking - arrows move n s w e" or "editing - arrows as usual"))
end

-- Tab: toggle on an empty line, else Rune's completion
local complete = rune.binds.get("tab")
complete = complete and complete:action()
rune.bind("tab", function()
  if rune.input.get() == "" or not complete then set(not on) else complete() end
end)

rune.alias.exact("arrows", function(args)
  args = util.trim(args)
  if args == "on" then set(true)
  elseif args == "off" then set(false)
  elseif args == "" then set(not on)
  else util.warn("[arrows] arrows [on|off]") end
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("arrows", "arrows [on|off]", "walk mode: on an empty line the arrow keys move n s w e, Shift+Up/Down u d - toward a closed door (minimap's exits line) opening it first, moving once it opens; Option+arrow (Option+Shift+Up/Down) retreats that way (WLK lit); with text typed they work as usual; Tab on an empty line toggles it too")

return {}
