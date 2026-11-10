-- Help for our commands (require("core.help"); tt++ modules/xhelp.tin). A
-- module registers each command it makes, next to the alias:
--   local help = require("core.help")
--   help.add("inst", "inst", "every skill with instinct above 0 on one line, copied")
--   help.remove(name)   -- a command that's gone (an area script's, on leaving)
-- Shown by Rune's own /help, which is wrapped (the way Rune's docs wrap
-- /quit - reference/api/command.md): its list of slash commands as before,
-- then ours.
--   /help          Rune's commands, then ours, by name
--   /help <text>   both, only those whose name, usage or description holds
--                  the text (any case) - Rune's own /help ignores what follows
-- tt++'s xhelp (ours alone) went 2026-11-09: /help covers it. Plain "help"
-- goes to the game, as ever. Costs nothing per line: a table filled at
-- load, read when asked.
local util = require("core.util")
local theme = require("core.theme")

local M = {}
local entries = {}   -- name -> { usage, desc }

function M.add(name, usage, desc) entries[name] = { usage = usage, desc = desc } end
function M.remove(name) entries[name] = nil end

local function hit(q, ...)
  if q == "" then return true end
  return table.concat({ ... }, " "):lower():find(q, 1, true) ~= nil
end

-- Ours, sorted by name; true if any shown
local function ours(q)
  local names = {}
  for name, e in pairs(entries) do
    if hit(q, name, e.usage, e.desc) then names[#names + 1] = name end
  end
  table.sort(names)
  if not names[1] then return false end
  rune.echo(theme.heading("[Aardwolf commands]") .. theme.muted(" (" .. #names .. ")"))
  for _, name in ipairs(names) do
    local e = entries[name]
    rune.echo("  " .. theme.value(e.usage) .. theme.muted(" - ") .. e.desc)
  end
  return true
end

-- Rune's, the same way its /help prints them (lua/core/55_commands.lua)
local function runes(q)
  local cmds = {}
  for _, c in ipairs(rune.command.list()) do
    if hit(q, c.name, c.description or "") then cmds[#cmds + 1] = c end
  end
  if not cmds[1] then return false end
  rune.echo(theme.heading("[Rune commands]") .. theme.muted(" (" .. #cmds .. ")"))
  for _, c in ipairs(cmds) do
    rune.echo(string.format("  %-12s %s%s", "/" .. c.name, c.description or "",
      c.enabled and "" or (" " .. theme.danger("[off]"))))
  end
  return true
end

local rune_help = rune.command.get("help")
rune_help = rune_help and rune_help:action()

rune.command.add("help", function(args)
  local q = util.trim(args):lower()
  if q == "" and rune_help then
    rune_help("")
    ours("")
    return
  end
  local a = runes(q)
  local b = ours(q)
  if not (a or b) then util.warn("[help] nothing matches \"" .. q .. "\".") end
end, "Show available commands - Rune's and ours; /help <text> searches")

return M
