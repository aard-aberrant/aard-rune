-- Game formatters (require("format.game")): the enemy (its health and
-- name, cut to 29 columns) - green nearly dead, else red - or your state
-- (no color).
local theme = require("ui.theme")
local colors = require("ui.colors")
local width = require("ui.screen").width

local M = {}

function M.enemy_or_state(k)
  local s = k:sub(2)
  if k:sub(1, 1) ~= "s" and width(s) > 29 then s = colors.crop(s, 28):gsub("\27%[0m$", "") .. "…" end
  return s
end

function M.enemy_or_state_color(k)
  local b = k:sub(1, 1)
  return b == "g" and theme.good or b == "d" and theme.danger or nil
end

return M
