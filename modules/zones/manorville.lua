-- Manorville (your home's zone) - only while you're in it
-- (modules/zones/loader.lua). Nothing of it exists outside manorville.
--   restock          anywhere in manorville: count the medkit, then walk to each
--                    shop whose item is short of its count, buy what's
--                    missing and put it in the medkit; at the end, count
--                    again and say, then g home (travel's home routine)
--   restock check    count and say what would be bought
--   restock stop     stop (anything already sent still happens)
-- Your character's section of data/player.lua, read from the file at each
-- restock (not declared with modules/player.lua - /player doesn't list
-- these, and a /player set doesn't reach them):
--   medkit      the medkit's keyword (put all.<item> <medkit>)
--   medkit_id   its id (ident medkit) - invdata wants the id, not a
--               keyword (the user's log invdata-medkit.log, 2026-11-20)
--   restock     { { item = "201heal", name = "Better Heal Potion",
--               vnum = 52871, want = 60 }, ... } - the item keyword as the
--               shop and the medkit take it, its name as the medkit lists
--               it (optional), the shop's vnum, the count to keep
-- The count: a hidden "invdata <medkit_id>". The reply is {invdata <id>},
-- one row per item (id,flags,name,level,type,unique,wearloc,timer - no
-- stacks), {/invdata}. An item counts for an entry when its name, colors
-- removed, is the entry's name, any case - or, for an entry with no name,
-- holds its item word (fugu: "{::(Fugu)::}"). The keyword alone often isn't
-- in the name (201heal is "Better Heal Potion", seen live 2026-11-20).
-- Buying: "buy <n> <item>", then "put all.<item> <medkit>" (both seen to
-- work, the user 2026-11-20) - the put 2 s after, unless the game said
-- "You can't carry any of those.": that stops the restock where you are.
-- The walks leave this zone: while a restock runs, the script stays loaded
-- (A.keep at each zone change), and goes at the first change after.
-- Never in a fight (the user: no commands in combat): restock won't start,
-- and a fight on the way stops it - nothing more is sent. A shop not
-- reached in 120 s (a walk stopped short) stops it too.
-- Cost: nothing per line; GMCP room.info and char.status each run one test
-- while you're in manorville (or a restock runs). The row reader exists
-- only while a count's reply comes in.
local A = ...

local util = require("lib.util")
local colors = require("ui.colors")
local game = require("modules.game")       -- fighting
local player = require("modules.player")   -- your character's name
local M = require("modules.mapper")        -- where you are
local T = require("modules.travel")        -- the walks, g

local say, warn, hide = util.say, util.warn, util.hide

-- Your section of data/player.lua, read now; nil after a warning
local function section()
  local data = util.load_data(rune.config_dir .. "/data/player.lua")
  local n = player.name()
  local s = data and n and data[n]
  if type(s) ~= "table" then warn("[restock] no section for " .. tostring(n) .. " in data/player.lua."); return nil end
  return s
end

-- Counting the medkit --------------------------------------------------

local on_count        -- cb(counts) waiting for the reply
local names, words, counts   -- exact name -> item word; item words with no name;
                             -- item word -> count, filling
local row_line        -- the row reader: exists only inside a reply
local no_reply = util.slot()

local function row_off() if row_line then row_line:remove(); row_line = nil end end

local function row_on()
  row_off()
  row_line = rune.trigger.starts("", function(_, ctx)
    local clean = ctx.line:clean()
    if clean == "{/invdata}" then
      row_off()
      no_reply.stop()
      local cb = on_count
      on_count = nil
      if cb then cb(counts) end
      return hide(ctx)
    end
    local rest = clean:match("^%d+,[^,]*,(.*)$")
    if not rest then return end
    -- the name may hold commas: it runs up to the last five numbers
    local name = rest:match("^(.-),%-?%d+,%-?%d+,%-?%d+,%-?%d+,%-?%d+$")
    if name then
      name = util.trim(colors.uncolor(name)):lower()
      local item = names[name]   -- an entry's exact name first
      if not item then
        for _, w in ipairs(words) do
          if name:find(w, 1, true) then item = w; break end
        end
      end
      if item then counts[item] = counts[item] + 1 end
    end
    return false
  end, { name = "restock_row", priority = 5 })
end

-- Count the items of `list` (restock entries) in medkit `id`; cb(counts)
local function count(id, list, cb)
  names, words, counts = {}, {}, {}
  for _, e in ipairs(list) do
    if e.name then names[e.name] = e.item else words[#words + 1] = e.item end
    counts[e.item] = 0
  end
  on_count = cb
  util.await("exact", "{invdata " .. id .. "}", function(_, ctx)
    if on_count then row_on() end
    return hide(ctx)
  end, "restock_invdata", 10)
  no_reply.start(10, function()
    if on_count then on_count = nil; row_off(); warn("[restock] no reply to invdata " .. id .. " - is medkit_id right?") end
  end)
  rune.send_raw("invdata " .. id)
end

-- The run --------------------------------------------------------------

local legs    -- { { item, vnum, n } ... } still to do; nil: no restock running
local leg     -- the one being walked to
local run     -- { kit, id, list } of the run
local arrive = util.slot()
local bought = util.slot()   -- the 2 s after a buy (buy, below)

local function stop(why)
  if not legs then return end
  legs, leg = nil, nil
  arrive.stop(); bought.stop()
  if why then warn("[restock] " .. why .. " - stopped.") end
end

local function report(list, got, prefix)
  local parts = {}
  for _, e in ipairs(list) do parts[#parts + 1] = string.format("%s %d/%d", e.item, got[e.item] or 0, e.want) end
  say("[restock] " .. prefix .. table.concat(parts, ", ") .. ".")
end

local next_leg

-- The buy alone, then 2 s for the game's refusal ("You can't carry any of
-- those.", seen live 2026-11-20): it stops the restock where you are -
-- no put, no next shop, no g. No refusal: the put, then the next shop
local function buy()
  if game.state == 8 then stop("you're fighting at the " .. leg.item .. " shop"); return end
  arrive.stop()
  local l = leg
  l.bought = true   -- another room.info here mustn't buy again
  rune.send_raw("buy " .. l.n .. " " .. l.item)
  util.await("exact", "You can't carry any of those.", function()
    if leg == l then stop("you can't carry the " .. l.item .. " - none bought") end
  end, "restock_refused", 2)
  bought.start(2, function()
    if leg ~= l then return end
    rune.send_raw("put all." .. l.item .. " " .. run.kit)
    leg = nil
    next_leg()
  end)
end

function next_leg()
  leg = table.remove(legs, 1)
  if not leg then
    legs = nil
    local r = run
    -- the count first (its reply before home's lines), then g home
    count(r.id, r.list, function(got)
      report(r.list, got, "done: ")
      if game.state == 8 then warn("[restock] you're fighting - not going home."); return end
      T.home()
    end)
    return
  end
  if M.here == leg.vnum then buy(); return end
  if not (M.here and T.search(M.here, function(x) return x == leg.vnum end)) then
    stop("no route to the " .. leg.item .. " shop (" .. leg.vnum .. ")")
    return
  end
  T.go_vnum(leg.vnum, "the " .. leg.item .. " shop")
  arrive.start(120, function() stop("the " .. leg.item .. " shop (" .. leg.vnum .. ") not reached in 120 s") end)
end

A.gmcp.on("room.info", function()
  if leg and not leg.bought and M.here == leg.vnum then buy() end
end, { name = "restock_arrive" })

A.gmcp.on("char.status", function()
  if legs and game.state == 8 then stop("you're fighting") end
end, { name = "restock_fight" })

-- leaving manorville mid-restock: stay till it's done; else nothing left over
A.on_unload(function()
  if legs or on_count then A.keep(); return end
  arrive.stop(); bought.stop(); no_reply.stop(); row_off()
end)

-- What restock needs from your section, checked: kit, id, list - or nil
local function settings()
  local s = section()
  if not s then return nil end
  local kit, id, list = s.medkit, s.medkit_id, s.restock
  if type(kit) ~= "string" or kit == "" then warn("[restock] data/player.lua: medkit (the medkit's keyword) is missing."); return nil end
  if not tostring(id or ""):match("^%d+$") then warn("[restock] data/player.lua: medkit_id (ident medkit's Id) is missing."); return nil end
  if type(list) ~= "table" or #list == 0 then warn("[restock] data/player.lua: restock should be a list of { item, vnum, want }."); return nil end
  local out = {}
  for i, e in ipairs(list) do
    if type(e) ~= "table" or type(e.item) ~= "string" or not tonumber(e.vnum) or not tonumber(e.want) then
      warn("[restock] data/player.lua: restock entry " .. i .. " needs item (a word), vnum and want.")
      return nil
    end
    if e.name ~= nil and type(e.name) ~= "string" then
      warn("[restock] data/player.lua: restock entry " .. i .. "'s name should be text (the item's name in the medkit).")
      return nil
    end
    out[i] = { item = e.item:lower(), name = e.name and util.trim(e.name):lower(),
               vnum = tonumber(e.vnum), want = tonumber(e.want) }
  end
  return kit, tostring(id), out
end

A.alias.exact("restock", function(args)
  local what = util.trim(args)
  if what == "stop" then
    if not legs then say("[restock] nothing running."); return end
    stop(); say("[restock] stopped.")
    return
  end
  if what ~= "" and what ~= "check" then warn("[restock] restock [check | stop]"); return end
  if legs or on_count then warn("[restock] already running - restock stop first."); return end
  if what == "" and game.state == 8 then warn("[restock] not while fighting."); return end
  local kit, id, list = settings()
  if not kit then return end
  count(id, list, function(got)
    local todo, plan = {}, {}
    for _, e in ipairs(list) do
      local n = e.want - (got[e.item] or 0)
      if n > 0 then
        todo[#todo + 1] = { item = e.item, vnum = e.vnum, n = n }
        plan[#plan + 1] = "buy " .. n .. " " .. e.item .. " at " .. e.vnum
      end
    end
    report(list, got, "medkit: ")
    if #todo == 0 then say("[restock] nothing to buy."); return end
    say("[restock] " .. table.concat(plan, "; ") .. (what == "check" and " (check only)." or "."))
    if what == "check" then return end
    if game.state == 8 then warn("[restock] you're fighting - not started."); return end
    legs, run = todo, { kit = kit, id = id, list = list }
    next_leg()
  end)
end)
A.help("restock", "restock [check | stop]",
  "(in manorville) top the medkit up to data/player.lua's restock counts: walk to each short item's shop, buy, put away, g home; check: only count")
