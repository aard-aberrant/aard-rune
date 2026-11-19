-- Attacks (tt++ conf/classes.tin and conf/aliases.tin)
--   k <mob>   your primary attack (pattack) on <mob>
--   k         in a fight: k_fight, or pattack with no target (the game aims
--             it at your current enemy). Out of one: pattack on the target
--             (modules/target.lua), by its keyword - none found yet: a guess
--             from its name, as the target's check tries first. No target: a message
--   kk [mob]  your secondary attack (sattack)
--   aa        your area attack (paoe)
-- The commands are in data/player.lua, your character's section for the
-- subclass playing now (modules/player.lua; the keys declared below) -
-- looked up again whenever the subclass changes. None for your subclass:
-- these say so and send nothing.

local util = require("lib.util")
local theme = require("ui.theme")
local game = require("modules.game")       -- the subclass (its attacks), fighting or not
local target = require("modules.target")   -- a bare k attacks it
local player = require("modules.player")   -- your attacks, per subclass

-- data/player.lua's keys for each subclass (/player lists them)
player.needs("modules.combat", {
  pattack = { "k: your primary single-target attack - its command, then hit = its word in its damage line, after \"Your \" (ac waits for it; none: only ac's 6 s timeout): { \"c 'gaias fury'\", hit = \"fury\" }, or the command alone", parts = { "hit" } },
  sattack = { "kk: your secondary attack (ac2) - its command, then hit = its damage line's word, as pattack's", parts = { "hit" } },
  paoe = { "aa: your area attack, ac aoe opens a fight with it - its command, then cooldown = its recovery as data/affects.lua names it (ac aoe waits for it; none: no check): { \"c 'heavenly smiting'\", cooldown = \"smiting\" }, or the command alone", parts = { "cooldown" } },
  k_fight = { "what a bare k sends in a fight (default: pattack, no target)", optional = true },
  heal = { "your heal spell, for h and rh (default: incomplete healing)", optional = true },
}, { subclass = true })

local say, warn, trim = util.say, util.warn, util.trim

local combat = {}
-- Set by modules/autocast.lua: called with the mob ("" for a bare one) and
-- which attack ("pri" for k, "sec" for kk) before it's sent; true means
-- don't send
combat.k_hook = nil

local C           -- this subclass's attacks
local subclass    -- the subclass they're for

-- A new subclass or character (modules/game.lua has stored char.base
-- already): its section of data/player.lua
local for_who
rune.gmcp.on("char.base", function()
  if not game.subclass then return end
  local who = tostring(player.name()) .. "/" .. game.subclass
  if who == for_who then return end
  for_who, subclass = who, game.subclass
  C = player.class(subclass)
  if not C then warn("[combat] no " .. subclass:lower() .. " section for " .. tostring(player.name()) .. " in data/player.lua - k, kk and aa need it.") end
end, { name = "combat_base" })
-- /player set, unset or save: read again
player.on_change(function() if subclass then C = player.class(subclass) end end)

-- This subclass's command `key`, or nil after a message
local function attack(key)
  if not C then
    warn("[combat] your subclass's attacks aren't loaded" .. (subclass and (" (" .. subclass .. ")") or " yet") .. ".")
    return nil
  end
  local v = C[key]
  local cmd = type(v) == "table" and v[1] or v
  if type(cmd) ~= "string" then warn("[combat] no " .. key .. " for " .. subclass .. " in data/player.lua."); return nil end
  return cmd, type(v) == "table" and v or nil
end

-- (Aliases: send, then return nothing - a returned value is run as a command)
rune.alias.exact("k", function(args)
  local mob = trim(args)
  local pattack = attack("pattack")
  if not pattack then return end
  if combat.k_hook and combat.k_hook(mob, "pri") then return end
  if mob ~= "" then
    rune.send_raw(pattack .. " " .. mob)
  elseif game.state == 8 then   -- fighting
    rune.send_raw(C.k_fight or pattack)
  else
    local t = target.get()
    -- No keyword yet (the target's check is still asking where): the
    -- check's own first guess from the name - "a shifty exhibit employee"
    -- -> "shifty exhibit employee" (seen 2026-11-10: k typed on arrival,
    -- before where answered). A wrong guess is refused by the game
    local kw, guessed = t and t.kw, false
    if t and not kw and t.name then
      kw = util.mob_keywords(t.name)[1]
      if kw == "" then kw = nil end
      guessed = kw ~= nil
    end
    if kw then
      say("[combat] k: " .. (t.name or kw) .. (guessed and (" (keyword guessed: " .. kw .. ")") or ""))
      -- A numbered keyword (5.traveller, from hqq or target) counts the
      -- area's mobs for where, but an attack seemed to count only the room's
      -- ("They aren't here." with two in the room, 2026-11-06): attack by
      -- the keyword alone - the first one here
      rune.send_raw(pattack .. " " .. (kw:gsub("^%d+%.", "")))
    elseif t then
      warn("[combat] k: no keyword for " .. t.name .. " - k <mob>.")
    else
      rune.echo(theme.quiet("k: no target"))   -- quiet gray (the user, 2026-11-08); help k has the rest
    end
  end
end)

rune.alias.exact("kk", function(args)
  local cmd = attack("sattack")
  if not cmd then return end
  local mob = trim(args)
  if combat.k_hook and combat.k_hook(mob, "sec") then return end
  rune.send_raw(mob ~= "" and (cmd .. " " .. mob) or cmd)
end)

rune.alias.exact("aa", function()
  local cmd = attack("paoe")
  if not cmd then return end
  rune.send_raw(cmd)
end)

-- The primary attack (pattack's command), or nil after a message, and its
-- hit word (pattack's hit, or nil) - for modules/autocast.lua
function combat.pattack()
  local c, pair = attack("pattack")
  return c, pair and pair.hit
end

-- The secondary attack (sattack's command), or nil after a message, and its
-- hit word - for ac2
function combat.sattack()
  local c, pair = attack("sattack")
  return c, pair and pair.hit
end

-- The area attack and its cooldown's name (paoe's command and cooldown), for ac aoe
-- (modules/autocast.lua); quiet - nil when there's none, no warning
function combat.paoe()
  if not C then return nil end
  local v = C.paoe
  if type(v) == "table" then return v[1], v.cooldown end
  return v, nil
end

-- Your heal spell, for h and rh (modules/heal.lua, modules/rheal.lua): the
-- subclass section's heal, else incomplete healing (a subclass not known yet, too)
function combat.heal()
  return C and C.heal or "incomplete healing"
end

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("k", "k [mob]", "your primary attack: on <mob>; bare in a fight: your enemy; bare out of one: the target, by its keyword (set one with target <kw>, gm <mob> or qx)")
help.add("kk", "kk [mob]", "your secondary attack")
help.add("aa", "aa", "your area attack")

return combat
