-- Quest formatters (require("format.quest")): process/quest.lua's values
-- as value widgets' show and color.
local theme = require("ui.theme")
local F = require("format.generic")
local num = F.num

-- The target lines' colors, the quest's and the campaign's
theme.define("target", "Quest and campaign targets (info pane)", {
  { "area",  theme.cyan,    "the area" },
  { "room",  theme.blue,    "the room" },
  { "mob",   theme.magenta, "the mob" },
  { "gone",  theme.red,     "the room, when the target is killed or gone" },
})

local M = {}

-- The quest's time: "12m left" (red under 5), "killed, return to QM"
local minutes = F.rule({ 5 }, { "danger", "value" })
function M.left(v) return v == "K" and "killed, return to QM" or num(v) .. "m left" end
function M.left_color(v) return v == "K" and theme.danger or minutes(v) end

-- QST: minutes (red under 3), RD, AC (red after the warning), "--"
-- (theme.quest comes with its module: read when drawn)
local qst_minutes = F.rule({ 3 }, { "danger", "value" })
local COLOR = { RD = function() return theme.quest.ready end, ACW = function() return theme.danger end,
                AC = function() return theme.quest.active end, ["--"] = function() return theme.unavailable end }
function M.status(k) return k == "ACW" and "AC" or tostring(k) end
function M.status_color(k) return type(k) == "number" and qst_minutes(k) or COLOR[k]() end

return M
