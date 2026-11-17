-- Minimap processors (require("process.minimap")): modules/minimap.lua's
-- data (map.block, map.word, map.note) and modules/game.lua's room.zone /
-- room.num. The map's parts show while no word (RUNNING / FIGHTING /
-- DARKNESS) is up.
local P = {}

-- the block while no word is up
local function shown(block, word) if not word then return block end end

-- "zone | vnum", while there's a map or a word (source: room.zone,
-- room.num, map.word, map.block)
function P.header(zone, num, word, block)
  if not word and not block then return nil end
  local head = zone or ""
  if num and num ~= -1 then head = head .. " | " .. num end
  return head
end

-- The room name's rows (source: map.block, map.word)
function P.name(block, word)
  block = shown(block, word)
  return block and block.name[1] and block.name or nil
end

-- The room's note (source: map.note, map.word, map.block)
function P.note(note, word, block)
  if word or not block or note == "" then return nil end
  return note
end

-- The map block, while it has rows (source: map.block, map.word)
function P.map(block, word)
  block = shown(block, word)
  return block and block.map[1] and block or nil
end

-- The [ Exits: ... ] line (source: map.block, map.word)
function P.exits(block, word)
  block = shown(block, word)
  return block and (block.exits or "") or nil
end

return P
