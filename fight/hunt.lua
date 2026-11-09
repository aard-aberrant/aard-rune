-- Hunting (tt++ modules/hunt.tin). Both read the game's hunt replies - game
-- text, there is no GMCP for hunt - with triggers that are on only while
-- one runs. Starting either stops the other.
--   autohunt [mob]   hunt, take the direction it gives, hunt again ... until
--                    you arrive or hunt can't lead you there. A fight pauses
--                    it: the next hunt goes when GMCP says the fight is over.
--                    No mob: the target (below)
--   hunt [mob]       the game's hunt; no mob: the target (below)
--   autohuntoff      stop it
--   hqq [mob]        the hunt trick: hunt 1.mob, 2.mob, 3.mob ... A reply
--                    with a direction means that one can be hunted, so it's
--                    the wrong one; "unable to hunt that target" (or "is
--                    here!") marks the right one, which becomes the target
--                    (targets/target.lua: N.mob, and its check finds the room).
--                    No mob: the target's keyword
--   hqof             give up on an hqq
-- The target, for autohunt and hunt: its keyword as it is ("2.warrior"). A
-- target with only a name (quest, campaign, before the area check has
-- answered): travel.probe finds the keyword with where - in this area
-- only, as hunt is - and the target keeps it (target.learn_kw)
-- Not ported: tt++'s huntmaster cast before hqq (a Hunter on a global
-- quest, from variables nothing set).
-- The replies (tt++'s patterns):
--   You are confident that X passed through here, heading D.
--   You are certain that X is D from here.
--   You have no idea what you're doing, but maybe X is|left D?   (hqq: wrong)
--   X is here!
--   No one in this area by the name X
--   You seem unable to hunt that target for some reason.
--   You couldn't find a path to X from here.
--   Not while you are fighting!

local util = require("core.util")
local game = require("core.game")       -- fighting or not
local target = require("targets.target")   -- hqq's mob becomes it; the default mob
local travel = require("nav.travel")   -- probe: a keyword for a target with only a name

local say, warn, trim = util.say, util.warn, util.trim

local mode       -- nil, "auto" or "trick"
local mob        -- autohunt: what's hunted; hqq: the keyword
local n = 1      -- hqq: the number being tried
local waiting = false   -- autohunt: a hunt owed once the fight ends
-- The reply triggers exist only while a hunt runs (util.group)
local replies = util.group()
local on = replies.set

local function stop(why)
  if not mode then return end
  local was = mode
  mode, waiting = nil, false
  on(false)
  if why then
    say((was == "auto" and "[autohunt] off - " or "[hqq] ") .. why .. (was == "auto" and (" (" .. mob .. ")") or ""))
  end
end

local function hunt()
  if mode == "trick" then return rune.send_raw("hunt " .. n .. "." .. mob) end
  if game.state == 8 then waiting = true; return end
  rune.send_raw("hunt " .. mob)
end

-- A direction: autohunt walks it and hunts again; for hqq, a wrong mob
local function direction(dir)
  if mode == "auto" then
    rune.send_raw(dir)
    return hunt()
  end
  say("[hqq] wrong mob - " .. n .. "." .. mob)
  n = n + 1
  hunt()
end

local function found(how)
  local kw = n .. "." .. mob
  say("[hqq] " .. how .. " - " .. kw)
  stop()
  target.set({ kw = kw, src = "manual" })
end

local count = 0
local function add(pat, fn, mode)
  replies.add(mode or "regex", pat, fn, { name = "hunt_" .. count })
  count = count + 1
end

add("^You are confident that .+ passed through here, heading (\\w+)\\.", function(m) direction(m[1]) end)
add("^You are certain that .+ is (\\w+) from here\\.", function(m) direction(m[1]) end)
add("^You have no idea what you're doing, but maybe .+ (?:is|left) \\w+", function()
  if mode == "trick" then direction() end
end)
-- contains + a check: the regex ^.+ is here!$ cost 600 ns a line (core/util.lua)
add(" is here!", function(_, ctx)
  if not ctx.line:clean():find(" is here!$") then return end
  if mode == "auto" then stop("arrived") else found("mob in the room") end
end, "contains")
add("You seem unable to hunt that target for some reason\\.", function()
  if mode == "auto" then stop("that mob can't be hunted") else found("right mob") end
end)
add("^No one in this area by the name ", function()
  stop(mode == "auto" and "no such mob here" or "wrong area, wrong mob, or no_hunt.")
end)
add("^You couldn't find a path to .+ from here\\.$", function()
  if mode == "auto" then stop("no path") else direction() end
end)
add("^Not while you are fighting!$", function()
  if mode == "auto" then waiting = true end
end)

-- The fight is over: the hunt it held up
rune.gmcp.on("char.status", function()
  if mode == "auto" and waiting and game.state ~= 8 then
    waiting = false
    hunt()
  end
end, { name = "hunt_fight_over" })

-- The target's keyword for `who`, to fn(kw) - probed for if it has only a name
local function target_kw(who, fn)
  local t = target.get()
  if t and t.kw then return fn(t.kw) end
  if not (t and t.name) then return warn("[" .. who .. "] " .. who .. " <mob> - or set a target first.") end
  say("[" .. who .. "] finding a keyword for " .. t.name .. "...")
  travel.probe(t.name, function(kw)
    if not kw then return warn("[" .. who .. "] no keyword found for " .. t.name .. " in this area.") end
    target.learn_kw(kw)
    fn(kw)
  end)
end

local function autohunt(m)
  stop()
  mode, mob = "auto", m
  on(true)
  say("[autohunt] hunting " .. m .. " - autohuntoff to stop.")
  hunt()
end

rune.alias.exact("autohunt", function(args)
  local m = trim(args)
  if m == "" then return target_kw("autohunt", autohunt) end
  autohunt(m)
end)

-- hunt: the game's own, the target when no mob is given
rune.alias.exact("hunt", function(args)
  local m = trim(args)
  if m ~= "" then rune.send_raw("hunt " .. m); return end
  target_kw("hunt", function(kw) rune.send_raw("hunt " .. kw) end)
end)

rune.alias.exact("autohuntoff", function()
  if mode ~= "auto" then return say("[autohunt] not running.") end
  stop("stopped")
end)

rune.alias.exact("hqq", function(args)
  local m = trim(args)
  if m == "" then
    local t = target.get()
    m = t and t.kw and t.kw:gsub("^%d+%.", "") or ""
    if m == "" then return warn("[hqq] hqq <mob> - or set a target with a keyword first.") end
  end
  stop()
  mode, mob, n = "trick", m, 1
  on(true)
  hunt()
end)

rune.alias.exact("hqof", function()
  if mode ~= "trick" then return say("[hqq] not running.") end
  stop("given up")
end)

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("autohunt", "autohunt [mob]", "hunt and follow its directions until you arrive or it can't lead you there; a fight pauses it; no mob: the target")
help.add("hunt", "hunt [mob]", "the game's hunt; no mob: the target (its keyword, found with where if it has only a name)")
help.add("autohuntoff", "autohuntoff", "stop an autohunt")
help.add("hqq", "hqq [mob]", "the hunt trick: hunt 1.mob, 2.mob ... until the right one, which becomes the target")
help.add("hqof", "hqof", "give up on an hqq")
