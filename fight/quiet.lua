-- Fewer lines in a fight (new - tt++ showed these as they came). Game text,
-- matched as in a Rune log of a group fight (~/combat, 2026-11-07): GMCP
-- sends only totals, not what one kill gave.
--
-- A fight's rewards on one line. These are hidden as they come:
--   You receive 87+9 experience points.           (one per kill - the count)
--   You receive 96 bonus experience points to rejoice in ...
--   You receive 75 'rare kill' experience bonus.      (the user's log 2026-11-07)
--   You get 5,767 gold coins from the blasted corpse of ...
--   You share 5,767 gold coins with 2 other members. Your share is 1,923 gold.
--   Scars shares 5,732 gold coins with 2 others. Your share is 1,910 gold.
--   Gigantic Golem Arm crumbles into 2,000 gold pieces.
--   You are taxed 19 gold coins by your clan.     (also "25 gold by")
-- while your GMCP state is fighting (8), and added up. When the state
-- changes, one line shows - the last kill's lines come before the change
-- (debug quiet, live 2026-11-07; the game sends no prompt Rune sees):
--   +1,234 xp, +5,678 gold (4 kills)
-- Gold is what you keep: the coins you got, less what you shared away, plus
-- your share of others', less the clan's tax. Every other line shows as it
-- comes (campaign, banish, an item from the corpse ...), and so do these
-- out of a fight (a sale's tax).
--
-- "You have 38 tells waiting. Type 'replay' ..." - after nearly every kill:
-- shown only when the number changes.
--
-- Skinning, hidden with the blank line after it:
--   Rhuli makes a solid helm skinned from an ettin berserker.
--   Rhuli drops 2 * a pair of boots skinned from a giant assassin.
--   2 * A pair of boots skinned from a giant assassin crumble into dust.
-- (an item in a room - "... skinned from X lies here" - still shows)

local util = require("core.util")

local function num(s) return tonumber((s:gsub(",", ""))) or 0 end
local function commas(n)
  local s, k = tostring(math.floor(n))
  repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

-- Fight rewards -----------------------------------------------------------

local game = require("core.game")   -- fighting or not
local dbg = require("core.debug").topic("quiet", "the fight total: GMCP state changes, reward lines, when it shows")

local t            -- this fight's: { xp, gold, kills } or nil

-- The line: right-justified in the main pane (its width: layout.RIGHT_W),
-- as a powerline-style tab - a left-pointing triangle in the tab's colour,
-- then the text on that colour, up against it:
--                                           <|+314 xp, +13,458 gold (2 kills)
-- The triangle is the powerline glyph U+E0B2, which fills its cell (needs
-- a terminal or font that draws it); "◀" (U+25C0) is the plain stand-in.
-- Colour codes written out - rune.style's end in a reset, which would end
-- the background too
local layout = require("core.layout")
local ESC = string.char(27)
local TRI = "\238\130\178"   -- U+E0B2, one column
local TAB = { 75, 100, 160 }    -- the tab's colour (r, g, b)
local function rgb(kind, c) return string.format("%s[%d;2;%d;%d;%dm", ESC, kind, c[1], c[2], c[3]) end
local XP, GOLD, DIM = rgb(38, { 130, 225, 130 }), rgb(38, { 240, 210, 90 }), rgb(38, { 215, 220, 230 })

local function show()
  if not t then return end
  if dbg.on then dbg.log("show") end
  local parts, plain = {}, {}
  local function part(code, text)
    parts[#parts + 1] = code .. text
    plain[#plain + 1] = text
  end
  if t.xp > 0 then part(XP, "+" .. commas(t.xp) .. " xp") end
  if t.gold ~= 0 then
    if parts[1] then part(DIM, ", ") end
    part(GOLD, (t.gold > 0 and "+" or "") .. commas(t.gold) .. " gold")
  end
  local kills = t.kills
  t = nil
  if not parts[1] then return end
  if kills > 0 then part(DIM, " (" .. kills .. (kills == 1 and " kill)" or " kills)")) end
  local width = 1 + #table.concat(plain)   -- the triangle, the text
  rune.echo(string.rep(" ", math.max(0, layout.RIGHT_W - width))
    .. rgb(38, TAB) .. TRI .. rgb(48, TAB) .. table.concat(parts) .. ESC .. "[0m")
end

local function tot()
  t = t or { xp = 0, gold = 0, kills = 0 }
  return t
end

local function add_xp(s)
  local c = tot()
  for n in s:gmatch("[%d,]+") do c.xp = c.xp + num(n) end
end

-- Each reward line: its pattern on the clean line, and what it adds
local REWARDS = {
  { "^You receive ([%d,+]+) experience points?%.$", function(x) add_xp(x); t.kills = t.kills + 1 end },
  { "^You receive ([%d,]+) bonus experience points?", add_xp },
  { "^You receive ([%d,]+) '[^']+' experience bonus%.$", add_xp },
  { "^You get ([%d,]+) gold coins? from ", function(n) local c = tot(); c.gold = c.gold + num(n) end },
  { "^You share ([%d,]+) gold coins? with .-Your share is ([%d,]+) gold%.$", function(all, mine)
      local c = tot()
      c.gold = c.gold - num(all) + num(mine)
    end },
  { "^%S+ shares [%d,]+ gold coins? with .-Your share is ([%d,]+) gold%.$", function(mine)
      local c = tot()
      c.gold = c.gold + num(mine)
    end },
  { "^.+ crumbles into ([%d,]+) gold pieces%.$", function(n) local c = tot(); c.gold = c.gold + num(n) end },
  -- "gold coins by" or "gold by"
  { "^You are taxed ([%d,]+) gold.- by your clan%.$", function(n) local c = tot(); c.gold = c.gold - num(n) end },
}

local function on_reward(_, ctx)
  if game.state ~= 8 then return end
  local c = ctx.line:clean()
  for _, p in ipairs(REWARDS) do
    local a, b = c:match(p[1])
    if a then
      if dbg.on then dbg.log("reward (state " .. tostring(game.state) .. "): " .. c:sub(1, 40)) end
      p[2](a, b)
      return false
    end
  end
end
-- Cheap prefixes and substrings (Go-side), the line checked in Lua after
rune.trigger.starts("You receive ", on_reward, { name = "quiet_xp" })
rune.trigger.starts("You get ", on_reward, { name = "quiet_get" })
rune.trigger.starts("You are taxed ", on_reward, { name = "quiet_tax" })
rune.trigger.contains(" gold coins with ", on_reward, { name = "quiet_share" })
rune.trigger.contains(" crumbles into ", on_reward, { name = "quiet_crumble" })

-- The fight's over: the total shows
local last_state
rune.gmcp.on("char.status", function()
  if dbg.on and game.state ~= last_state then
    dbg.log("state " .. tostring(last_state) .. " -> " .. tostring(game.state) .. (t and ", total open" or ""))
  end
  last_state = game.state
  if game.state ~= 8 then show() end
end, { name = "quiet_fight_end" })

-- The tells reminder ---------------------------------------------------------

local tells
rune.trigger.starts("You have ", function(_, ctx)
  local n = ctx.line:clean():match("^You have (%d+) tells? waiting%.")
  if not n then return end
  if n == tells then return false end
  tells = n
end, { name = "quiet_tells" })

-- Skinning -------------------------------------------------------------------

rune.trigger.contains(" skinned from ", function(_, ctx)
  local c = ctx.line:clean()
  if c:find("^%S+ makes .+ skinned from .+%.$") or c:find("^%S+ drops .+ skinned from .+%.$")
    or c:find(" skinned from .+ crumbles? into dust%.$") then
    util.eat_blanks(c)
    return false
  end
end, { name = "quiet_skin" })
