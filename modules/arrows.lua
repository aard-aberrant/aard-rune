-- Walk mode: the arrow keys walk - up n, down s, left w, right e, Shift+Up
-- u, Shift+Down d - and Option+arrow opens that way's door and steps
-- through (Option+Shift+Up/Down: up, down), in place of their usual jobs (up/down: history;
-- left/right: the cursor; Option+Left/Right: a word; the rest: none, so
-- with text typed nothing). Tab on an
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
local colors = require("ui.colors")
local theme = require("ui.theme")
-- This module's color: theme.walk.on - /theme lists it, data/theme.lua
-- changes it (ui/theme.lua)
theme.define("walk", "WLK (status bar)", {
  { "on", colors.mix(theme.black_tc, colors.bg(theme.cyan)), "WLK: the arrow keys walk" },
})

-- Shift+Up / Shift+Down: up and down (only if the terminal tells them from
-- plain Up / Down - Rune's docs: modified arrows depend on the terminal)
-- Option (alt) with them opens a door that way and goes through (both
-- sent at once: no door, or a locked one, and the step just fails). The user's terminal
-- (macterm, libghostty, under tmux) sends Option+Left / Option+Right as
-- alt+b / alt+f (checked live 2026-11-17 with echo binds), so those are bound
-- for them - Option+B / Option+F open doors too
local MOVES = {
  up = "n", down = "s", left = "w", right = "e", ["shift+up"] = "u", ["shift+down"] = "d",
  ["alt+up"] = "open north;n", ["alt+down"] = "open south;s",
  ["alt+b"] = "open west;w", ["alt+f"] = "open east;e",
  ["alt+shift+up"] = "open up;u", ["alt+shift+down"] = "open down;d",
}

-- Rune's own actions for the arrows, nil where there's no bind (left/right)
local saved = {}
for key in pairs(MOVES) do
  local b = rune.binds.get(key)
  saved[key] = b and b:action() or nil
end

-- Published (ui/view.lua): walk mode on or off - the WLK light
local view = require("ui.view")
local V = view.provides("arrows", "walk mode (arrow keys)", {
  ["walk.on"] = { "boolean", "the arrow keys walk" },
})
local on = false
V.set("walk.on", on)

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
-- A word left / right, for Option+Left / Right with text typed (Rune's own
-- word moves are UI actions, not callable from Lua): over the spaces, then
-- the word - to its start going left, its end going right
local function word(step)
  local text, pos = rune.input.get(), rune.input.get_cursor()
  -- the character the cursor would pass over: before it going left, after it going right
  local function next_char()
    local i = step < 0 and pos or pos + 1
    if i < 1 or i > #text then return nil end
    return text:sub(i, i)
  end
  while next_char() and next_char():match("%s") do pos = pos + step end
  while next_char() and next_char():match("%S") do pos = pos + step end
  rune.input.set_cursor(pos)
end
local USUAL = {
  left = function() cursor(-1) end, right = function() cursor(1) end,
  ["alt+b"] = function() word(-1) end, ["alt+f"] = function() word(1) end,
}

local function set(want)
  if want == on then return end
  on = want
  for key, dir in pairs(MOVES) do
    if on then
      local usual = type(saved[key]) == "function" and saved[key] or USUAL[key]
      rune.bind(key, function()
        if rune.input.get() == "" then rune.send(dir) elseif usual then usual() end
      end)
    elseif saved[key] then
      rune.bind(key, saved[key])
    else
      rune.unbind(key)
    end
  end
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
help.add("arrows", "arrows [on|off]", "walk mode: on an empty line the arrow keys move n s w e, Shift+Up/Down u d, Option+arrow opens that door and goes through (Option+Shift+Up/Down: up, down) (WLK lit); with text typed they work as usual; Tab on an empty line toggles it too")

return {}
