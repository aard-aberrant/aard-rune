-- Fewer lines in a fight (new - tt++ showed these as they came). Game text,
-- matched as in a Rune log of a group fight (~/combat, 2026-11-07): GMCP
-- sends only totals, not what one kill gave.
--
-- A kill's rewards on one line. These are hidden as they come:
--   You receive 87+9 experience points.
--   You receive 96 bonus experience points to rejoice in ...
--   You receive 75 'rare kill' experience bonus.      (the user's log 2026-11-07)
--   You get 5,767 gold coins from the blasted corpse of ...
--   You share 5,767 gold coins with 2 other members. Your share is 1,923 gold.
--   Scars shares 5,732 gold coins with 2 others. Your share is 1,910 gold.
--   Gigantic Golem Arm crumbles into 2,000 gold pieces.
--   You are taxed 19 gold coins by your clan.     (also "25 gold by"; only after
--                                                   a kill's gold - a sale's shows)
-- and at the game's prompt (GA/EOR-confirmed), or 1 s after the last one if
-- no prompt comes, one line shows:
--   +267 xp (87+9+96 bonus+75 rare), +1,891 gold
-- The xp total first, then its parts: the experience line's (87+9), the
-- bonus, and each quoted one by its first word ('rare kill': rare). Gold is
-- what you keep: the coins you got, less what you shared away, plus your
-- share of others', less the clan's tax. A second experience line starts the next kill's.
-- Every other line shows as it comes (campaign, banish, an item from the
-- corpse ...) - no list of the lines that can come between: the summary
-- follows the round's lines, just before the prompt.
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
local style = rune.style

local function num(s) return tonumber((s:gsub(",", ""))) or 0 end
local function commas(n)
  local s, k = tostring(math.floor(n))
  repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

-- Kill rewards -------------------------------------------------------------

local r            -- this kill's: { xp, bonus, gold, tax } or nil
local watch = util.group()   -- the prompt that ends a kill's lines
local idle = util.slot()     -- or 1 s after the last of them

local function flush()
  idle.stop()
  watch.set(false)
  if not r then return end
  local total, parts = 0, {}
  if r.xp then
    for n in r.xp:gmatch("[%d,]+") do total = total + num(n) end
    parts[#parts + 1] = r.xp
  end
  if r.bonus > 0 then total = total + r.bonus; parts[#parts + 1] = commas(r.bonus) .. " bonus" end
  for _, k in ipairs(r.kinds or {}) do
    total = total + k[2]
    parts[#parts + 1] = commas(k[2]) .. " " .. (k[1]:match("^%S+") or k[1])
  end
  local out = {}
  if parts[1] then
    out[#out + 1] = style.green("+" .. commas(total) .. " xp") .. style.gray(" (" .. table.concat(parts, "+") .. ")")
  end
  local gold = r.gold - r.tax
  if r.gold ~= 0 or r.tax > 0 then
    out[#out + 1] = style.yellow((gold >= 0 and "+" or "") .. commas(gold) .. " gold")
  end
  r = nil
  if out[1] then rune.echo(table.concat(out, style.gray(", "))) end
end

local function cur()
  r = r or { bonus = 0, gold = 0, tax = 0 }
  return r
end

-- Each reward line: its pattern on the clean line, and what it adds
local REWARDS = {
  { "^You receive ([%d,+]+) experience points?%.$", function(x)
      if r and r.xp then flush() end   -- the next kill's
      cur().xp = x
    end },
  { "^You receive ([%d,]+) bonus experience points?", function(n) cur().bonus = cur().bonus + num(n) end },
  { "^You receive ([%d,]+) '([^']+)' experience bonus%.$", function(n, kind)
      local c = cur()
      c.kinds = c.kinds or {}
      c.kinds[#c.kinds + 1] = { kind, num(n) }
    end },
  { "^You get ([%d,]+) gold coins? from ", function(n) cur().gold = cur().gold + num(n) end },
  { "^You share ([%d,]+) gold coins? with .-Your share is ([%d,]+) gold%.$", function(all, mine)
      cur().gold = cur().gold - num(all) + num(mine)
    end },
  { "^%S+ shares [%d,]+ gold coins? with .-Your share is ([%d,]+) gold%.$", function(mine)
      cur().gold = cur().gold + num(mine)
    end },
  { "^.+ crumbles into ([%d,]+) gold pieces%.$", function(n) cur().gold = cur().gold + num(n) end },
  -- "gold coins by" or "gold by". Only in a kill's lines (it comes after
  -- the gold) - a sale's tax shows as the game sent it
  { "^You are taxed ([%d,]+) gold.- by your clan%.$", function(n)
      if not r then return "show" end
      r.tax = r.tax + num(n)
    end },
}

local function reward(c)
  for _, p in ipairs(REWARDS) do
    local a, b = c:match(p[1])
    if a then return p[2], a, b end
  end
end

local function on_reward(_, ctx)
  local fn, a, b = reward(ctx.line:clean())
  if not fn or fn(a, b) == "show" then return end
  watch.set(true)
  idle.start(1, flush)
  return false
end
-- Cheap prefixes and substrings (Go-side), the line checked in Lua after
rune.trigger.starts("You receive ", on_reward, { name = "quiet_xp" })
rune.trigger.starts("You get ", on_reward, { name = "quiet_get" })
rune.trigger.starts("You are taxed ", on_reward, { name = "quiet_tax" })
rune.trigger.contains(" gold coins with ", on_reward, { name = "quiet_share" })
rune.trigger.contains(" crumbles into ", on_reward, { name = "quiet_crumble" })

-- While a kill's lines are coming: the game's prompt (GA/EOR-confirmed)
-- ends them. A half line (a packet ending mid-line) also comes through the
-- prompt pass, unconfirmed - not the end
watch.add("starts", "", function(_, ctx)
  if ctx.confirmed then flush() end
end, { name = "quiet_end", on = "prompt" })

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
