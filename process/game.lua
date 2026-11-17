-- Game processors (require("process.game")): modules/game.lua's character
-- data.
local rpad = require("ui.screen").rpad
local num = require("format.generic").num

local P = {}

-- The enemy while fighting, else your state: a letter for which, then
-- the text - g the enemy under 20% (nearly dead), d over, s your state
-- (source: fighting, enemy_hp, enemy, state)
function P.enemy_or_state(f, ehp, en, state)
  if f and ehp and en then return (ehp < 20 and "g" or "d") .. rpad(num(ehp), 3) .. " " .. en end
  return state and ("s" .. state) or "s?"
end

return P
