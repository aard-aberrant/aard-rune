-- Helpers shared by every file (require("core.util")).

local util = {}

-- Messages: cyan for news, yellow for a problem, red for an error
function util.say(s) rune.echo(rune.style.cyan(s)) end
function util.warn(s) rune.echo(rune.style.yellow(s)) end
function util.err(s) rune.echo(rune.style.red(s)) end

-- Replace a pane's text - only when it differs from what was last put
-- there, so a redraw that changes nothing costs one string compare
local shown = {}
-- Triggers, from Rune's source (lua/core/50_triggers.lua, matcher.go) and
-- benchmarks of this config (2026-11-06): every registered trigger is
-- matched in Go against every line, DISABLED ONES TOO - enabled is checked
-- only after a match. So: a catch-all is starts("") (a string compare; a
-- regex ".*" costs ~0.5 us more a line); a pattern that can't be anchored
-- with a literal start (^.+, (\w+) ..., an alternation) is contains/starts
-- plus a check in Lua - those ran 600-1300 ns a line, anchored ones 10-90.
-- Removing and re-adding instead of disabling rebuilds the matcher (~32
-- us+): worth it only for triggers off for more than ~50 lines at a time.

function util.pane(name, text)
  if shown[name] == text then return end
  shown[name] = text
  rune.pane.replace(name, text)
end

-- The terminal bell. Straight to the terminal - rune.echo drops it (tried)
function util.beep() io.write("\7"); io.flush() end

-- Text without leading and trailing spaces ("" for nil)
function util.trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- Text without its colour codes. A few room names in the converted map carry
-- tt++'s escaped form ("\27[1\;32m"), so a backslash is allowed in the code
function util.strip(s) return (s:gsub("\27%[[%d;\\]*m", "")) end

-- Nothing but spaces
function util.blank(s) return s:match("^%s*$") ~= nil end

-- Hide the blank line(s) the game sends after a line a trigger has just
-- hidden (tt++ ||gag_line). `clean` is that line's text, so the eater skips
-- it if it sees it. Off again at the first line that isn't blank
local eat_skip, eater
eater = rune.trigger.starts("", function(_, ctx)
  local clean = ctx.line:clean()
  if clean == eat_skip then eat_skip = nil; return end
  if util.blank(clean) then return false end
  eater:disable()
end, { name = "util_eat_blanks", priority = 5 })
eater:disable()
function util.eat_blanks(clean) eat_skip = clean; eater:enable() end

-- Plain text word-wrapped to lines of at most w characters; a word longer
-- than w is cut
function util.wrap(text, w)
  local lines, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif #cur + 1 + #word <= w then
      cur = cur .. " " .. word
    else
      lines[#lines + 1] = cur
      cur = word
    end
    while #cur > w do
      lines[#lines + 1] = cur:sub(1, w)
      cur = cur:sub(w + 1)
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

-- A data file (a .lua file that returns a table), or nil after an error line
function util.load_data(path)
  local ok, t = pcall(dofile, path)
  if ok and type(t) == "table" then return t end
  util.err("can't load " .. path .. ": " .. tostring(t))
  return nil
end

-- A mob's likely keywords from its full name, best first, for where, k and
-- the like (tt++ campaign.tin). The article and small words go, commas too
-- ("a hatchling of the wyrm" -> "hatchling wyrm"); then come its leading
-- words from the first one up, then each later word alone from the last.
-- "big red dragon": big red dragon, big, big red, dragon, red. The game
-- only matches a mob's real keywords, so each is a guess - travel.probe
-- tries them with where until one names the mob
local STOP = { of = 1, the = 1, ["and"] = 1, ["in"] = 1, on = 1, at = 1, to = 1,
               ["for"] = 1, de = 1, la = 1, a = 1, as = 1 }

function util.mob_keywords(name)
  local words = {}
  for w in name:gsub(",", ""):gmatch("%S+") do words[#words + 1] = w end
  if words[1] and ({ a = 1, an = 1, the = 1 })[words[1]:lower()] and #words > 1 then
    table.remove(words, 1)
  end
  local kept = {}
  for i, w in ipairs(words) do
    if i == 1 or i == #words or not STOP[w:lower()] then kept[#kept + 1] = w end
  end
  local tries = { table.concat(kept, " ") }
  for n = 1, #kept - 1 do tries[#tries + 1] = table.concat(kept, " ", 1, n) end
  if #kept > 1 then
    for i = #kept, 2, -1 do tries[#tries + 1] = kept[i] end
  end
  return tries
end

return util
