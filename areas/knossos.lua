-- The Knossos area quest (tt++ areas/knossos.tin). Only while you're in the
-- knossos zone (areas/loader.lua).
--   knossos   the whole quest, from the portal's landing room 28193 ("Before
--             a great city" - where g knossos lands you). Refused anywhere
--             else: every step is a fixed move
local A = ...
local util = require("core.util")
local game = require("core.game")   -- the room you're in

local START = 28193
local STEPS = {
  "open n", "n", "e", "s", "buy steak",
  "n", "w", "w", "n", "buy silver",
  "s", "s", "w", "n", "enter shack", "give steak hobo",
  "e", "s", "e", "n", "e", "e", "n", "w", "w", "enter crack", "give silver rat",
  "e", "e", "n", "n", "n", "n", "w", "n", "give id guard", "give pass guard",
}

A.help("knossos", "knossos", "the whole Knossos area quest, from the portal's landing room 28193 (knossos)")
A.alias.exact("knossos", function()
  if game.room.num ~= START then
    return util.warn("[knossos] start in room " .. START .. ", Before a great city (you're in "
      .. tostring(game.room.num) .. ") - g knossos takes you there.")
  end
  rune.send_raw(table.concat(STEPS, "\n"))
end)
