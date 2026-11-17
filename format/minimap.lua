-- Minimap formatters (require("format.minimap")): the header, the note,
-- the map and the word, from process/minimap.lua's values. Its colors:
-- theme.map.* - /theme lists them, data/theme.lua changes them.
local util = require("lib.util")
local colors = require("ui.colors")
local theme = require("ui.theme")
local T = theme.define("map", "The minimap", {
  { "header",  theme.yellow,   "zone | vnum" },
  { "word",    theme.bold,     "RUNNING / FIGHTING / DARKNESS" },
  { "note",    theme.cyan,     "the room's note" },
  { "me",      theme.green_tc, "your dot" },
  { "player",  theme.red,      "another player's square" },
})
local MAP_NOTE = 2      -- most lines a room note may take
local crop, concat, floor, rep = colors.crop, table.concat, math.floor, string.rep

local M = {}

-- zone | vnum, in yellow
function M.header(h) if h then return T.header(h) end end

-- The note, wrapped to the width, at most MAP_NOTE lines, in cyan
function M.note(note, w)
  if not note then return nil end
  local out = {}
  for k, l in ipairs(util.wrap(note, w)) do
    if k > MAP_NOTE then break end
    out[k] = T.note(l)
  end
  return concat(out, "\n")
end

-- The map as sent: your # a dot, other players' * a square, < and >
-- arrows; each row cut to the width.
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
function M.map(b, w)
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
end

-- RUNNING / FIGHTING / DARKNESS, centered in the width
function M.word(word, w)
  if word then return rep(" ", floor((w - #word) / 2)) .. T.word(word) end
end

return M
