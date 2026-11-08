-- Attacks (tt++ conf/classes.tin and conf/aliases.tin)
--   k <mob>   your primary attack (pattack) on <mob>
--   k         in a fight: k_fight, or pattack with no target (the game aims
--             it at your current enemy). Out of one: pattack on the target
--             (targets/target.lua), by its keyword. No target or keyword: a message
--   kk [mob]  your secondary attack (sattack)
--   aa        your area attack (paoe)
-- The commands are in data/classes/<subclass>.lua - the subclass as GMCP
-- char.base spells it, lowercased - read again whenever it changes. No
-- file for your subclass: these say so and send nothing.

local util = require("core.util")
local game = require("core.game")       -- the subclass (its attacks), fighting or not
local target = require("targets.target")   -- a bare k attacks it

local say, warn, trim = util.say, util.warn, util.trim

local combat = {}
-- Set by fight/autocast.lua: called with k's mob ("" for a bare k) before k sends
-- its attack; true means don't send
combat.k_hook = nil

local C           -- this subclass's attacks
local subclass    -- the subclass they're for

-- A new subclass (core/game.lua has stored char.base already): read its file
rune.gmcp.on("char.base", function()
  if not game.subclass or game.subclass == subclass then return end
  subclass = game.subclass
  C = util.load_data(rune.config_dir .. "/data/classes/" .. subclass:lower() .. ".lua")
  if not C then warn("[combat] no attacks for " .. subclass .. " - k, kk and aa need that file.") end
end, { name = "combat_base" })

-- This subclass's command `key`, or nil after a message
local function attack(key)
  if not C then
    warn("[combat] your subclass's attacks aren't loaded" .. (subclass and (" (" .. subclass .. ")") or " yet") .. ".")
    return nil
  end
  if not C[key] then warn("[combat] no " .. key .. " for " .. subclass .. ".") end
  return C[key]
end

-- (Aliases: send, then return nothing - a returned value is run as a command)
rune.alias.exact("k", function(args)
  local mob = trim(args)
  local pattack = attack("pattack")
  if not pattack then return end
  if combat.k_hook and combat.k_hook(mob) then return end
  if mob ~= "" then
    rune.send_raw(pattack .. " " .. mob)
  elseif game.state == 8 then   -- fighting
    rune.send_raw(C.k_fight or pattack)
  else
    local t = target.get()
    if t and t.kw then
      say("[combat] k: " .. (t.name or t.kw))
      -- A numbered keyword (5.traveller, from hqq or target) counts the
      -- area's mobs for where, but an attack seemed to count only the room's
      -- ("They aren't here." with two in the room, 2026-11-06): attack by
      -- the keyword alone - the first one here
      rune.send_raw(pattack .. " " .. (t.kw:gsub("^%d+%.", "")))
    elseif t then
      warn("[combat] k: no keyword for " .. t.name .. " - k <mob>.")
    else
      rune.echo("\27[38;5;246mk: no target\27[0m")   -- quiet gray (the user, 2026-11-08); help k has the rest
    end
  end
end)

rune.alias.exact("kk", function(args)
  local cmd = attack("sattack")
  if not cmd then return end
  local mob = trim(args)
  rune.send_raw(mob ~= "" and (cmd .. " " .. mob) or cmd)
end)

rune.alias.exact("aa", function()
  local cmd = attack("paoe")
  if not cmd then return end
  rune.send_raw(cmd)
end)

-- The primary attack (pattack), or nil after a message, and its hit word
-- (pattack_hit, or nil) - for fight/autocast.lua
function combat.pattack()
  local c = attack("pattack")
  return c, c and C.pattack_hit
end

-- Your heal spell, for h and rh (fight/heal.lua, fight/rheal.lua): the class
-- file's heal, else incomplete healing (a subclass not known yet, too)
function combat.heal()
  return C and C.heal or "incomplete healing"
end

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("k", "k [mob]", "your primary attack: on <mob>; bare in a fight: your enemy; bare out of one: the target, by its keyword (set one with target <kw>, gm <mob> or qx)")
help.add("kk", "kk [mob]", "your secondary attack")
help.add("aa", "aa", "your area attack")

return combat
