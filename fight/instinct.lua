-- inst (tt++ modules/instinct.tin): sends "instinct", hides its table and
-- prints one line of every skill with instinct above 0, in the game's
-- order, and copies that line to the clipboard to paste:
--   [Dual wield: 30] [Enhanced damage: 77] [Gaias revenge: 50] ...
-- The reply (tt++'s log/shamanstats, 2026-10-18) has no tags:
--                                                        ---- Next Cost ----
--              Skill name             Sn  Learned Instinct Trains         Gold
--   ---------- ---------------------- --- ------- -------- ------ ------------
--   Level 1  : Accelerate             258     85%        0    200    2,000,000 (Uses ...)
--              Dodge                  214    100%        0    200    2,000,000
--   (blank lines between levels) ... a dashed rule, then
--   You have 46 trains available for instinct.
--
--   You have 4,344,493 gold available for instinct.
-- A row is "Level N : " or spaces, the name, Sn, Learned%, Instinct,
-- Trains, Gold. One gagged span from the title to the gold line collects
-- it; a line that isn't part of the table (a tell, combat) is shown again.
-- The trigger exists only while your inst is out (10 s), so a typed
-- "instinct" shows the table as usual. Copied with Rune's own
-- rune.clipboard.set (OSC 52 - the terminal sets the clipboard); tt++ wrote
-- log/instinct.txt and went through tmux's paste buffer instead, not needed
-- here.

local util = require("core.util")
local theme = require("core.theme")

local NAME = "instinct_table"
local expire = util.slot()

local function stop()
  expire.stop()
  rune.trigger.remove(NAME)
end

-- Table lines that aren't rows: blank, the title, the column header, rules,
-- the two "You have ..." lines
local function frame(c)
  return util.blank(c) or c:find("^%s*%-+ Next Cost %-+")
    or c:find("^%s+Skill name%s+Sn%s+Learned") or c:find("^[%s%-]+$")
    or c:find("^You have .* available for instinct%.$")
end

local function done(_, ctx)
  stop()
  local out = {}
  for _, l in ipairs(ctx.lines) do
    local c = l:clean()
    local name, inst = c:gsub("^Level%s+%d+%s*:", "", 1)
      :match("^%s+(.-)%s+%d+%s+%d+%%%s+(%d+)%s+%d+%s+[%d,]+")
    if name then
      if tonumber(inst) > 0 then out[#out + 1] = "[" .. name .. ": " .. inst .. "]" end
    elseif not frame(c) then
      rune.echo(l:raw())   -- not ours: shown as it came
    end
  end
  util.eat_blanks(ctx.lines[#ctx.lines]:clean())
  if #out == 0 then rune.echo(theme.muted("[inst] no instinct above 0")); return end
  local line = table.concat(out, " ")
  rune.echo(line)
  rune.clipboard.set(line)
  rune.echo(theme.muted("[inst] copied to the clipboard as one line"))
end

rune.alias.exact("inst", function()
  stop()
  rune.trigger.regex("^ +-+ Next Cost -+", done, { name = NAME, gag = true,
    span = { to = "^You have .* gold available for instinct\\.$", max = 120 } })
  expire.start(10, function() rune.trigger.remove(NAME) end)
  rune.send_raw("instinct")
end)

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("inst", "inst", "every skill with instinct above 0 on one line, copied to the clipboard")
