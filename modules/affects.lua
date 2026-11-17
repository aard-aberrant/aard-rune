-- Your affects (require("modules.affects")): what's up on you, the
-- recoveries, the Shaman's totem - published as data, drawn by the panes
-- that want it (data/layout/affects.lua).
-- Kept current from the game's tags: {affon}sn,secs and {affoff}sn as
-- affects start and end, {recon}id,secs / {recoff}id for recoveries (65 is
-- Create Totem). One hidden "slist affected" fills it in (at login and
-- /reload, on a spell number not seen yet - to learn its name and kind -
-- and after saf, aff or affects); its reply is the whole list, so it
-- replaces what's known. A typed slist affected is read too, and shows.
-- The totem is an object in the room, not an affect, and has no tag: its
-- placing, expiry and "still recovering" lines are game text (Shaman only),
-- and a hidden "totem" reads its time and area.
--   saf / aff / affects [args]   the game's command, then a hidden slist
--   affectsreset                 just the hidden slist
--   /debug recov [on|off]        show the {recon}/{recoff} tags as they come (lib/debug.lua)
-- modules/tags.lua hides the affon, affoff, sfail, recon and recoff lines.
--
-- Data (ui/view.lua): affects, one record, touched at every change:
--   up      sn -> os.time it ends, 0 for no time: everything that's up
--   spells  sn -> { name (lower case), target (1 = offensive), type (2 = skill) }
--   recs    this subclass's recoveries (data/affects.lua's recoveries):
--           { d = its entry, ends = os.time it's ready, 0 = ready }
--   totem   { type, area, ends, rec_end, ready, none }
--   seen    a slist affected reply has been read
--   n       counts the changes (a reader keeping work per change)

local util = require("lib.util")
local view = require("ui.view")
local game = require("modules.game")       -- the subclass (recoveries, the totem)
local tags = require("modules.tags")       -- the slist and affect tags

local say, trim = util.say, util.trim

local CFG = util.load_data(rune.config_dir .. "/data/affects.lua") or { track = {} }

-- State -----------------------------------------------------------------

local A = {
  up = {}, spells = {}, recs = {}, seen = false, n = 0,
  totem = { type = nil, area = "", ends = 0, rec_end = 0, ready = false, none = false },
}
local spell, totem = A.spells, A.totem
local asked = {}     -- sn -> true once a slist has been asked for it

local V = view.provides("aard.affects", "your affects, recoveries and totem, from the game's tags and slist", {
  affects = { "record", "up (sn -> end, 0 = no time), spells (sn -> name, target, type), recs, totem, seen, "
    .. "n (counts changes) - changed in place", get = function() return A end },
})
local touch = V.toucher("affects")
local function changed() A.n = A.n + 1; touch() end

-- By recovery id, by spell number and by name (lower case). An id is the
-- {recon} tag's
local rec_by_id, rec_by_sn, rec_by_name = {}, {}, {}
local rec_asked = {}   -- recovery id -> true once a slist has been asked for it
local subclass

-- An entry of data/affects.lua for this subclass: no `only`, or it's listed
local function mine(d)
  if not d.only then return true end
  for _, s in ipairs(d.only) do if s == subclass then return true end end
  return false
end

local function build()
  local recs = {}
  rec_by_id, rec_by_sn, rec_by_name = {}, {}, {}
  for _, d in ipairs(CFG.recoveries or {}) do
    if mine(d) then
      local r = { d = d, ends = 0 }
      recs[#recs + 1] = r
      if d.id then rec_by_id[d.id] = r end
      if d.sn then rec_by_sn[d.sn] = r end
      rec_by_name[d.name:lower()] = r
    end
  end
  A.recs = recs
end

-- A recovery's id, learned (an slist row): this one, not any given before.
-- Id 0 isn't one: augmentation's {recon} comes as 0 (live, 2026-11-07), and
-- 0 may stand for more than one recovery - its tags ask an slist instead
local function rec_learn(r, id)
  if not id or id == 0 then return end
  for k, v in pairs(rec_by_id) do if v == r and k ~= id then rec_by_id[k] = nil end end
  rec_by_id[id] = r
end

-- Once a second: an affect more than 10 s past its end with no affoff (a
-- lost tag) goes, and a totem that ran out unseen. Looked for only once
-- the soonest end (as of the last change) is that far past
local check_n, check_at = -1, 0
rune.timer.every(1, function()
  local now = os.time()
  if A.n == check_n and now < check_at then return end
  local any, soonest = false, math.huge
  for sn, e in pairs(A.up) do
    if e > 0 then
      if e + 10 < now then A.up[sn] = nil; any = true
      elseif e < soonest then soonest = e end
    end
  end
  if totem.type and totem.ends > 0 then
    if totem.ends <= now then totem.type, totem.area, totem.ends = nil, "", 0; any = true
    elseif totem.ends - 11 < soonest then soonest = totem.ends - 11 end
  end
  if any then changed() end
  check_n, check_at = A.n, soonest + 11
end, { name = "affects_expire" })

-- slist affected ----------------------------------------------------------
-- A reply (tt++, confirmed live, log/affects2.txt):
--   {spellheaders affected}
--   155,aid,2,221,100,-1,1        sn,name,target,secs,learned,recovery,type
--   {/spellheaders}
--   {recoveries affected}
--   65,Create Totem,312           id,name,secs (tt++'s guess, from slist)
--   {/recoveries}
-- Each block is a Rune span from its tag to its closing tag, hidden as it
-- comes: its action reads the rows at the end, then shows the block again
-- if the reply was typed. A block whose closing tag never came (cut at
-- `max` lines) shows again too, so no other line is lost with it.
-- The game answers commands in order, and a reply can come long after the
-- send - one asked for during a spellup waits behind every spell of it. So
-- no timeout: each slist affected sent is queued (hidden: ours; shown: a
-- typed one), and each reply takes the first.

local queue = {}       -- per slist affected not answered yet: true = hide
local quiet = false    -- the reply being read is ours (from its first block to its second)
util.hider(function() return queue[1] == true or quiet end)

local function resync()
  queue[#queue + 1] = true
  rune.send_raw("slist affected")
end

-- A spell number not seen: ask once, a second after the last such tag, so
-- a spellup of new spells costs one query
local soon = util.slot()
local function resync_soon(sn)
  if asked[sn] then return end
  asked[sn] = true
  soon.start(1, resync)
end

local function show(lines) for _, l in ipairs(lines) do rune.echo(l:raw()) end end
local function closed(lines, tag) return lines[#lines]:clean() == tag end

-- sn,name,target,secs,learned,recovery,type - the name may hold commas
local function on_spell(c)
  local sn, name, target, secs, _, recov, kind = c:match("^(%d+),(.*),(%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%d+)$")
  if not sn then return end
  sn, secs = tonumber(sn), tonumber(secs)
  local r = rec_by_sn[sn]
  if r and tonumber(recov) > 0 then rec_learn(r, tonumber(recov)) end
  spell[sn] = { name = name:lower(), target = tonumber(target), type = tonumber(kind) }
  A.up[sn] = secs > 0 and os.time() + secs or 0
end

rune.trigger.exact("{spellheaders affected}", function(_, ctx)
  local lines = ctx.lines
  quiet = table.remove(queue, 1) == true
  A.up = {}
  for i = 2, #lines do on_spell(lines[i]:clean()) end
  changed()
  if not (quiet and closed(lines, "{/spellheaders}")) then show(lines) end
end, { name = "affects_slist_spells", gag = true, span = { to = "^\\{/spellheaders\\}$", max = 300 } })

-- Every recovery still running is listed: Create Totem is ready unless its
-- row (id,name,secs) comes
rune.trigger.exact("{recoveries affected}", function(_, ctx)
  local lines = ctx.lines
  totem.rec_end, totem.ready = 0, true
  for _, r in ipairs(A.recs) do r.ends = 0 end   -- ready unless listed
  for i = 2, #lines do
    local id, name, secs = lines[i]:clean():match("^(%d+),(.*),(%d+)$")
    id, secs = tonumber(id), tonumber(secs)
    if id == 65 then totem.rec_end, totem.ready = os.time() + secs, false end
    local r = name and rec_by_name[name:lower()]
    if r then rec_learn(r, id); r.ends = os.time() + secs end
  end
  A.seen = true
  changed()
  if quiet and closed(lines, "{/recoveries}") then util.eat_blanks("{/recoveries}") else show(lines) end
  quiet = false
end, { name = "affects_slist_recov", gag = true, span = { to = "^\\{/recoveries\\}$", max = 50 } })

-- The tags ----------------------------------------------------------------
-- (modules/tags.lua hides them)

tags.on("affon", function(rest)
  local sn, secs = rest:match("^(%d+),(%-?%d+)$")
  if not sn then return end
  sn, secs = tonumber(sn), tonumber(secs)
  A.up[sn] = secs > 0 and os.time() + secs or 0
  if not spell[sn] then resync_soon(sn) end
  changed()
end)

tags.on("affoff", function(rest)
  local sn = rest:match("^(%d+)$")
  if not sn then return end
  A.up[tonumber(sn)] = nil
  changed()
end)

-- {recon}id,secs / {recoff}id: 65 is Create Totem; a tracked recovery's
-- id. Another id while a tracked one's id isn't known yet: a hidden slist,
-- once per id, whose recoveries rows name it
-- "debug recov" (lib/debug.lua): each tag as it comes (hidden otherwise),
-- with the recovery it matched; its status line, the ids learned so far
local rec_dbg = require("lib.debug").topic("recov",
  "the {recon}/{recoff} recovery tags as they come", function()
    local known = {}
    for id, r in pairs(rec_by_id) do known[#known + 1] = r.d.label .. "=" .. id end
    table.sort(known)
    return "recovery ids known: " .. (known[1] and table.concat(known, " ") or "none yet")
  end)
local function dbg(what, id)
  if not rec_dbg.on then return end
  local r = rec_by_id[id]
  rec_dbg.log(what .. (id == 65 and " (Create Totem)" or id == 0 and " (id 0 - asking slist which)"
    or r and (" (" .. r.d.name .. ")") or " (not tracked / id not known yet)"))
end

tags.on("recon", function(rest)
  if rec_dbg.on then dbg("{recon}" .. rest, tonumber(rest:match("^(%d+)"))) end
  local id, secs = rest:match("^(%d+),(%d+)$")
  if not id then return end
  id, secs = tonumber(id), tonumber(secs)
  local recs = A.recs
  if id == 65 then
    totem.rec_end, totem.ready = os.time() + secs, false
  elseif id == 0 then
    if #recs > 0 then soon.start(1, resync) end   -- which one, by name
  elseif rec_by_id[id] then
    rec_by_id[id].ends = os.time() + secs
  elseif #recs > 0 and not rec_asked[id] then
    for _, r in ipairs(recs) do
      local known = false
      for _, v in pairs(rec_by_id) do if v == r then known = true end end
      if not known then rec_asked[id] = true; soon.start(1, resync); break end
    end
  end
  changed()
end)

tags.on("recoff", function(rest)
  if rec_dbg.on then dbg("{recoff}" .. rest, tonumber(rest:match("^(%d+)"))) end
  local id = tonumber(rest:match("^(%d+)$"))
  if id == 65 then
    totem.rec_end, totem.ready = 0, true
  elseif id == 0 then
    if #A.recs > 0 then soon.start(1, resync) end
  elseif id and rec_by_id[id] then
    rec_by_id[id].ends = 0
  end
  changed()
end)

-- Used too soon: "You are still recovering your Humility abilities (1:23)."
-- (tt++'s pattern) - its time, by name; Create Totem's is the totem's.
-- Literal in Go, the line checked in Lua
rune.trigger.contains("You are still recovering your ", function(_, ctx)
  local name, m, s = ctx.line:clean():match("You are still recovering your (.+) abilities %((%d+):(%d+)%)")
  if not name then return end
  local ends = os.time() + tonumber(m) * 60 + tonumber(s)
  if name == "Create Totem" then
    totem.rec_end, totem.ready = ends, false
  else
    local r = rec_by_name[name:lower()]
    if not r then return end
    r.ends = ends
  end
  changed()
end, { name = "affects_recovering" })

-- The totem (Shaman) ------------------------------------------------------
-- Game text - no tag covers it. Placing one asks a hidden "totem", whose
-- reply (tt++ log):
--   Area         Room   ...   Totem Name      Expires         (header)
--   ------------ -----------------------------------          (rule)
--   Wyrm         Center of the Council   Bear Totem   04:02  (the row)
-- or "You don't currently have a totem." Only those lines are hidden, and
-- the blank after the last; a typed totem is read the same way and shows.

local totem_quiet = false   -- the reply being read is ours
util.hider(function() return totem_quiet end)
local totem_q = {}          -- per totem sent, not answered yet: true = hide
-- Both exist only while on (util.group)
local totem_trig = util.group()   -- on for a Shaman
local reply_trig = util.group()   -- on only while a totem reply is expected
local reply_timeout = util.slot()   -- 60 s after the last totem sent


-- Send totem and read its reply: hidden (ours) or shown (typed). Queued
-- like slist above - it may wait behind other commands. A reply that never
-- matched (60 s after the last send) empties the queue
local function totem_send(hidden)
  totem_q[#totem_q + 1] = hidden
  totem_quiet = totem_q[1]
  reply_trig.set(true)
  rune.send_raw("totem")
  reply_timeout.start(60, function()
    if totem_q[1] ~= nil then
      totem_q, totem_quiet = {}, false
      reply_trig.set(false)
    end
  end)
end
local function totem_query() totem_send(true) end

-- The reply's last line: stop reading; ours: hide it and the blank after
local function totem_done(ctx)
  local hidden = table.remove(totem_q, 1)
  totem_quiet = totem_q[1] == true
  if not totem_q[1] and totem_q[1] ~= false then reply_trig.set(false) end
  if not hidden then return end
  return util.hide(ctx)
end

totem_trig.add("regex", "You place an? (\\w+) totem in the room\\.", function(m)
  totem.type, totem.area, totem.ends, totem.none, totem.ready = m[1], "", 0, false, false
  changed()
  totem_query()
end, { name = "affects_totem_placed" })

totem_trig.add("regex", "^Your totem has expired\\.", function()
  totem.type, totem.area, totem.ends = nil, "", 0
  changed()
end, { name = "affects_totem_expired" })

-- Literal matches checked in Lua: as regexes these cost 1-1.3 us a line
-- (see lib/util.lua's note on triggers)
local function head() if totem_quiet then return false end end
reply_trig.add("contains", "Totem Name", head, { name = "affects_totem_head" })
reply_trig.add("contains", "------------ -----------------------------------", head,
  { name = "affects_totem_rule" })

reply_trig.add("contains", " Totem ", function(_, ctx)
  local kind, a, b, c = ctx.line:clean():match("(%w+) Totem%s+(%d+):(%d+):?(%d*)%s*$")
  if not kind then return end
  a, b, c = tonumber(a), tonumber(b), tonumber(c)
  local secs = c and (a * 3600 + b * 60 + c) or (a * 60 + b)
  totem.type, totem.none, totem.ends = kind, false, os.time() + secs
  totem.area = trim(ctx.line:clean():sub(1, 12))
  changed()
  return totem_done(ctx)
end, { name = "affects_totem_row" })

reply_trig.add("regex", "^You don't currently have a totem\\.", function(_, ctx)
  totem.type, totem.area, totem.ends, totem.none = nil, "", 0, true
  changed()
  return totem_done(ctx)
end, { name = "affects_totem_none" })


rune.alias.exact("totem", function() totem_send(false) end)

-- Login, reload, subclass -------------------------------------------------
-- char.base comes at login, and after a /reload (init.lua asks for char):
-- the recoveries are built for the subclass, and the first one fills it in
-- with a hidden slist (and totem, on a Shaman)

rune.gmcp.on("char.base", function()
  if game.subclass and game.subclass ~= subclass then
    subclass = game.subclass
    build()
    totem_trig.set(subclass == "Shaman")
    changed()
  end
  if not A.seen and #queue == 0 then
    resync()
    if subclass == "Shaman" then totem_query() end
  end
end, { name = "affects_base" })

-- A typed slist affected: its reply shows, and is read
rune.alias.exact("slist", function(args)
  args = trim(args)
  if args == "affected" then queue[#queue + 1] = false end
  rune.send_raw(args ~= "" and ("slist " .. args) or "slist")
end)

for _, cmd in ipairs({ "saf", "aff", "affects" }) do
  rune.alias.exact(cmd, function(args)
    args = trim(args)
    rune.send_raw(args ~= "" and (cmd .. " " .. args) or cmd)
    resync()
  end)
end

rune.alias.exact("affectsreset", function()
  asked = {}
  say("[affects] asking the game again.")
  resync()
end)

build()

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("saf", "saf / aff / affects [args]", "the game's command, then a hidden slist that resets the affects pane")
help.add("slist", "slist [args]", "the game's slist; a typed slist affected also resets the affects pane")
help.add("affectsreset", "affectsreset", "resync the affects pane (a light looks stuck or wrong)")
help.add("totem", "totem", "the game's totem; its reply also sets the totem line")

return A
