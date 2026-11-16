-- panel:minimap(): the minimap - widgets on modules/minimap.lua's data
-- (map.block, map.word, map.note) and modules/game.lua's room.zone / room.num:
--   zone | vnum, in yellow
--   the room name (as many lines as the game sent)
--   the room's note (rmsg) from the mapper, in cyan, at most 2 lines
--   the map as sent - your # becomes a dot (theme.map.me), other players'
--     * a square (theme.map.player), down and up exits (< and >) arrows
--   the [ Exits: ... ] line, on the row above the pane's bottom one
-- or, in place of all but the header, RUNNING / FIGHTING / DARKNESS in the
-- middle of the pane. Every line is cut at the pane's width.

local screen = require("ui.screen")
require("ui.widgets.text")   -- panel:text (the room name, the exits)
local util = require("lib.util")
local colors = require("ui.colors")
local theme = require("ui.theme")
local layout = require("ui.layout")
-- This pane's colors: theme.map.* - /theme lists them, data/theme.lua
-- changes them (ui/theme.lua)
local T = theme.define("map", "The minimap", {
  { "header",  theme.yellow,   "zone | vnum" },
  { "word",    theme.bold,     "RUNNING / FIGHTING / DARKNESS" },
  { "note",    theme.cyan,     "the room's note" },
  { "me",      theme.green_tc, "your dot" },
  { "player",  theme.red,      "another player's square" },
})
local MAP_NOTE = 2      -- most lines a room note may take
local crop, concat, floor, rep = colors.crop, table.concat, math.floor, string.rep

-- Your #, by its color code (colors.game.me): a bold magenta #, the only
-- one on the map (the user). The code comes right in front of it - the
-- game sends a code before nearly every colored character - so a plain
-- find for code and character does it, and the swap puts the code back
-- after the dot. Measured on lunar (2026-11-09, real blocks): ~6 us a map
-- block; the old walk, a Lua step per character, cost ~340 us. Another
-- player is a bold red * (colors.game.player; shops' and forests' * are
-- other colors): per row a plain find, and a gsub only on a row that has
-- one (~1 us a row). The dot and square: the user's picks - the game's
-- own red * was too hard to see
local ME, PLAYER = colors.game.me, colors.game.player
local ME_CODE = ME .. "#"
local ME_SWAP = ME .. T.me("●") .. ME
local PLAYER_CODE, PLAYER_PAT = PLAYER .. "*", colors.pattern(PLAYER .. "*")
local PLAYER_SWAP = PLAYER .. T.player("■") .. PLAYER

return screen.add_widget("minimap", function(p)
local BLOCK = { "map.block", "map.word" }
-- the map's parts: the block while no word is up
local function map_shown(block, word) if not word then return block end end

-- zone | vnum, while there's a map or a word
p:widget {
  source = { "room.zone", "room.num", "map.word", "map.block" },
  process = function(zone, num, word, block)
    if not word and not block then return nil end
    local head = zone or ""
    if num and num ~= -1 then head = head .. " | " .. num end
    return head
  end,
  format = function(h) if h then return T.header(h) end end,
}

-- the room name
p:text {
  y = "next", w = "*", source = BLOCK,
  process = function(block, word)
    block = map_shown(block, word)
    return block and block.name[1] and block.name or nil
  end,
}

-- the room's note
p:widget {
  y = "next", w = "*", source = { "map.note", "map.word", "map.block" },
  process = function(note, word, block)
    if word or not block or note == "" then return nil end
    return note
  end,
  format = function(note, w)
    if not note then return nil end
    local out = {}
    for k, l in ipairs(util.wrap(note, w)) do
      if k > MAP_NOTE then break end
      out[k] = T.note(l)
    end
    return concat(out, "\n")
  end,
}

-- the map: your dot, other players, the arrows
p:widget {
  y = "next", w = "*", source = BLOCK,
  process = function(block, word)
    block = map_shown(block, word)
    return block and block.map[1] and block or nil
  end,
  format = function(b, w)
    if not b then return nil end
    local out, marked = {}, false
    for k, raw in ipairs(b.map) do
      if not marked then
        local h = raw:find(ME_CODE, 1, true)
        if h then raw, marked = raw:sub(1, h - 1) .. ME_SWAP .. raw:sub(h + #ME_CODE), true end
      end
      if raw:find(PLAYER_CODE, 1, true) then raw = raw:gsub(PLAYER_PAT, PLAYER_SWAP) end
      out[k] = crop((raw:gsub("<", "▼"):gsub(">", "▲")), w)
    end
    return concat(out, "\n")
  end,
}

-- the exits, on the row above the bottom one (the map above cut to fit)
p:text {
  y = -2, w = "*", source = BLOCK,
  process = function(block, word)
    block = map_shown(block, word)
    return block and (block.exits or "") or nil
  end,
}

-- RUNNING / FIGHTING / DARKNESS, in the middle of the pane
p:widget {
  y = floor(layout.MINIMAP_H / 2), w = "*", source = "map.word",
  format = function(word, w)
    if word then return rep(" ", floor((w - #word) / 2)) .. T.word(word) end
  end,
}
end)
