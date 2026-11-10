-- The affects pane (tt++ modules/affects.tin), beside the minimap:
--   the tracked affects (data/affects.lua): good ones on the left with
--     minutes left - green, yellow at 2 min, red at 1; off: gray, or black
--     on red for an important one - and bad ones as lights on the right,
--     gray, black on red while on you
--   sk: N  sp: good/bad - everything that's up
--   the expiry histogram - how many good spells and skills (not the tracked
--     ones, which have their own times) run out within 30s, 1m, 2m, 5m, 10m
--   the next three of them to run out, by name, coloured by how soon
--   recoveries (data/affects.lua, by subclass) under the good affects: while
--     the spell is up, bright with its time left (as a good affect); while
--     it recovers, gray with minutes until ready; ready, the label in gray
--   Shaman: the totem - type, minutes left, area; then Create Totem's
--     recovery, "totem ready"
-- Kept current from the game's tags: {affon}sn,secs and {affoff}sn as
-- affects start and end, {recon}65,secs / {recoff}65 for Create Totem. One
-- hidden "slist affected" fills it in (at login and /reload, on a spell
-- number not seen yet - to learn its name and kind - and after saf, aff or
-- affects); its reply is the whole list, so it replaces what's known. A
-- typed slist affected is read too, and shows.
-- The totem is an object in the room, not an affect, and has no tag: its
-- placing, expiry and "still recovering" lines are game text (Shaman only),
-- and a hidden "totem" reads its time and area.
--   saf / aff / affects [args]   the game's command, then a hidden slist
--   affectsreset                 just the hidden slist
--   /debug recov [on|off]        show the {recon}/{recoff} tags as they come (core/debug.lua)
-- core/tags.lua hides the affon, affoff, sfail, recon and recoff lines.

local util = require("core.util")
local theme = require("core.theme")
local game = require("core.game")       -- the subclass (tracked affects, the totem)
local layout = require("core.layout")   -- the pane's width
local tags = require("core.tags")       -- the slist and affect tags

local say, trim = util.say, util.trim

local CFG = util.load_data(rune.config_dir .. "/data/affects.lua") or { track = {} }
local PER_BLOCK = CFG.per_block or 2
local ICONS = CFG.totem_icons or {}
local BAD_EXTRA = CFG.bad_extra or {}

local RED, YEL, GRN, GRAY, CYAN =
  theme.danger, theme.caution, theme.good, theme.muted, theme.target.area
local alert = theme.alert
local OFF = theme.unavailable   -- off: a spell not up, a bad one not on you, an empty timer band, no totem

-- State -----------------------------------------------------------------

local up = {}        -- sn -> end (os.time), 0 for no time: everything that's up
local spell = {}     -- sn -> { name, target, type } from slist affected
local asked = {}     -- sn -> true once a slist has been asked for it
local seen = false   -- a slist affected reply has been read
local totem = { type = nil, area = "", ends = 0, rec_end = 0, ready = false, none = false }

-- This subclass's recoveries (data/affects.lua's recoveries): a list of
-- { d = its entry, ends = os.time it's ready, 0 = ready }, and by recovery
-- id, by spell number and by name (lower case). An id is the {recon} tag's
local recs, rec_by_id, rec_by_sn, rec_by_name = {}, {}, {}, {}
local rec_asked = {}   -- recovery id -> true once a slist has been asked for it

-- This subclass's tracked affects: good and bad id lists (by number), the
-- label widths, and also-name -> id
local good_ids, bad_ids, also = {}, {}, {}
local good_w, bad_w = 0, 0
local subclass

-- An entry of data/affects.lua for this subclass: no `only`, or it's listed
local function mine(d)
  if not d.only then return true end
  for _, s in ipairs(d.only) do if s == subclass then return true end end
  return false
end

local function build()
  good_ids, bad_ids, also, good_w, bad_w = {}, {}, {}, 0, 0
  for id, d in pairs(CFG.track) do
    if mine(d) then
      if d.good then
        good_ids[#good_ids + 1] = id
        if #d.label > good_w then good_w = #d.label end
      else
        bad_ids[#bad_ids + 1] = id
        if #d.label > bad_w then bad_w = #d.label end
        for _, name in ipairs(d.also or {}) do also[name] = id end
      end
    end
  end
  table.sort(good_ids)
  table.sort(bad_ids)
  recs, rec_by_id, rec_by_sn, rec_by_name = {}, {}, {}, {}
  for _, d in ipairs(CFG.recoveries or {}) do
    if mine(d) then
      local r = { d = d, ends = 0 }
      recs[#recs + 1] = r
      if d.id then rec_by_id[d.id] = r end
      if d.sn then rec_by_sn[d.sn] = r end
      rec_by_name[d.name:lower()] = r
      if #d.label > good_w then good_w = #d.label end
    end
  end
end

-- A recovery's id, learned (an slist row): this one, not any given before.
-- Id 0 isn't one: augmentation's {recon} comes as 0 (live, 2026-11-07), and
-- 0 may stand for more than one recovery - its tags ask an slist instead
local function rec_learn(r, id)
  if not id or id == 0 then return end
  for k, v in pairs(rec_by_id) do if v == r and k ~= id then rec_by_id[k] = nil end end
  rec_by_id[id] = r
end

-- Drawing ---------------------------------------------------------------

local dirty = true
local next_draw = 0  -- os.time of the next redraw due to time passing

local function mins(secs) return math.ceil(secs / 60) end
-- Seconds until a "Nm" (minutes rounded up) shows one less
local function till_minute(left) return left - (mins(left) - 1) * 60 end
-- Seconds until a time_style colour changes (at 120, 60 and 0 s left)
local function till_colour(left)
  if left > 120 then return left - 120 elseif left > 60 then return left - 60 end
  return left
end
local function rjust(s, w) s = tostring(s); return string.rep(" ", w - #s) .. s end

-- Seconds left -> the colour the pane uses: red to 1 min, yellow to 2
local function time_style(left)
  if left <= 60 then return RED elseif left <= 120 then return YEL end
  return GRN
end


-- A label and its minutes left (4 more wide: " 45m"), in `style`
local function timed(style, label, left)
  return style(label .. " " .. rjust(math.min(math.max(mins(left), 0), 99), 2) .. "m")
end

-- A tracked good affect's line, label and timer
local function good_line(id, now)
  local d = CFG.track[id]
  local label = rjust(d.label, good_w)
  local e = up[id]
  if not e then return (d.important and alert(label) or OFF(label)) .. "    " end
  if e == 0 then return GRN(label) .. "    " end
  return timed(time_style(e - now), label, e - now)
end

-- A recovery's line, under the good affects: while its spell is up, as a
-- good affect's (bright, the time left); while it recovers, gray with the
-- minutes until it's ready; ready and not up, the label alone in gray
local function rec_line(r, now)
  local label = rjust(r.d.label, good_w)
  local e = r.d.sn and up[r.d.sn]
  if e == 0 then return GRN(label) .. "    " end
  if e and e > now then return timed(time_style(e - now), label, e - now) end
  if r.ends > now then return timed(GRAY, label, r.ends - now) end
  return OFF(label) .. "    "
end

local function bad_light(id, lit)
  local label = rjust(CFG.track[id].label, bad_w)
  return lit and alert(label) or OFF(label)
end

local EIGHTHS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }
local BANDS = { { "30s", 30, RED }, { "1m", 60, RED }, { "2m", 120, YEL },
                { "5m", 300, GRN }, { "10m", 600, GRN } }

local function hist_row(band, n)
  local units = math.floor(n * 8 / PER_BLOCK)
  local bar
  if units > 80 then
    bar = string.rep("█", 9) .. "▶"
  else
    local full, rem = math.floor(units / 8), units % 8
    bar = string.rep("█", full) .. (rem > 0 and EIGHTHS[rem] or "")
    bar = bar .. string.rep(" ", 10 - full - (rem > 0 and 1 or 0))
  end
  local text = rjust(band[1], 3) .. " " .. bar .. " " .. rjust(n, 2)
  return n == 0 and OFF(text) or band[3](text)
end

local function totem_line(now, width)
  if subclass ~= "Shaman" then return nil end
  if totem.type and totem.ends > 0 and totem.ends <= now then
    totem.type, totem.area, totem.ends = nil, "", 0   -- ran out unseen
  end
  if totem.type then
    local icon = ICONS[totem.type]
    local tw = icon and 2 or #totem.type
    local area = totem.area:sub(1, math.max(width - tw - 5, 0))
    if totem.ends > 0 then
      local left = totem.ends - now
      local style = left <= 120 and YEL or GRN
      return style((icon or totem.type) .. " " .. rjust(mins(left), 2) .. "m") .. " " .. CYAN(area)
    end
    return GRN(icon or totem.type) .. "     " .. CYAN(area)
  end
  if totem.rec_end > now then return OFF("totem ready in " .. mins(totem.rec_end - now) .. "m") end
  if totem.ready or totem.rec_end > 0 then return GRN("totem ready") end
  if totem.none then return OFF("no totem") end
  return nil
end

local function draw()
  dirty = false
  local now = os.time()
  local width = layout.affects_w()
  local soonest = math.huge   -- seconds until something shown changes colour
  local out = {}

  -- An affect more than 10 s past its end with no affoff came (a lost tag)
  for sn, e in pairs(up) do
    if e > 0 and e + 10 < now then up[sn] = nil end
  end

  -- The two columns: good lines, bad lights beside them from the top. A bad
  -- light is lit by its own affect or one named in its also
  local lit = {}
  for _, id in ipairs(bad_ids) do lit[id] = up[id] ~= nil end
  for sn in pairs(up) do
    local s = spell[sn]
    local id = s and also[s.name]
    if id then lit[id] = true end
  end
  local rows = math.max(#good_ids + #recs, #bad_ids)
  local blank_good = string.rep(" ", good_w + 4)
  -- the bad lights end at the pane's right edge
  local gap = string.rep(" ", math.max(width - (good_w + 4) - bad_w, 1))
  for i = 1, rows do
    local id, r = good_ids[i], recs[i - #good_ids]
    local line = id and good_line(id, now) or r and rec_line(r, now) or blank_good
    if id and up[id] and up[id] > now then soonest = math.min(soonest, till_minute(up[id] - now)) end
    if r then
      local e = r.d.sn and up[r.d.sn]
      if e and e > now then soonest = math.min(soonest, till_minute(e - now), till_colour(e - now))
      elseif r.ends > now then soonest = math.min(soonest, till_minute(r.ends - now)) end
    end
    if bad_ids[i] then line = line .. gap .. bad_light(bad_ids[i], lit[bad_ids[i]]) end
    out[#out + 1] = line
  end

  if seen then
    -- Counts, and the timed good affects that aren't tracked
    local sk, sp, bad = 0, 0, 0
    local timers = {}   -- { left, name }
    local tracked_good = {}
    for _, id in ipairs(good_ids) do tracked_good[id] = true end
    for _, r in ipairs(recs) do if r.d.sn then tracked_good[r.d.sn] = true end end
    for sn, e in pairs(up) do
      local s = spell[sn]
      if s then   -- one not learned yet is left out until the slist comes
        local is_bad = s.target == 1 or BAD_EXTRA[s.name]
        if is_bad then sp, bad = sp + 1, bad + 1
        elseif s.type == 2 then sk = sk + 1
        else sp = sp + 1 end
        if not is_bad and e > 0 and not tracked_good[sn] and e > now then
          timers[#timers + 1] = { left = e - now, name = s.name }
        end
      end
    end
    local left_s = "sk: " .. sk
    local right_plain = "sp: " .. (sp - bad) .. "/" .. bad
    local gap = math.max(width - #left_s - #right_plain, 1)
    out[#out + 1] = GRAY("sk:") .. " " .. GRN(sk) .. string.rep(" ", gap)
      .. GRAY("sp:") .. " " .. GRN(sp - bad) .. GRAY("/") .. RED(bad)

    -- The histogram: each spell in the first band its time fits (minutes
    -- rounded up, so exactly 60 s left is 1m)
    local n = { 0, 0, 0, 0, 0 }
    for _, t in ipairs(timers) do
      local u = t.left - 1
      for i, band in ipairs(BANDS) do
        if u < band[2] then
          n[i] = n[i] + 1
          -- it moves to the next band down at band[i-1]'s cut-off
          local lower = i > 1 and BANDS[i - 1][2] or 0
          soonest = math.min(soonest, u - lower + 1)
          break
        end
      end
      if u >= 600 then soonest = math.min(soonest, u - 600 + 1) end
    end
    out[#out + 1] = ""
    for i, band in ipairs(BANDS) do out[#out + 1] = hist_row(band, n[i]) end

    -- The next three to run out
    table.sort(timers, function(a, b) return a.left < b.left end)
    if timers[1] then out[#out + 1] = "" end
    for i = 1, math.min(3, #timers) do
      local t = timers[i]
      local name = t.name:sub(1, 1):upper() .. t.name:sub(2)
      out[#out + 1] = time_style(t.left)(name:sub(1, width))
      soonest = math.min(soonest, till_colour(t.left))
    end
  end

  local tl = totem_line(now, width)
  if tl then
    if seen then out[#out + 1] = "" end
    out[#out + 1] = tl
    if totem.ends > now then soonest = math.min(soonest, till_minute(totem.ends - now)) end
    if totem.rec_end > now then soonest = math.min(soonest, till_minute(totem.rec_end - now)) end
  end

  util.pane("affects", table.concat(out, "\n"))
  -- Redraw again when something shown will change (a minute ticking down,
  -- a colour, a histogram band), and at least every 30 s
  next_draw = now + math.max(1, math.min(soonest, 30))
end

-- Changes ask for a draw; a 1 s timer does it, so a burst of tags (a
-- spellup) costs one draw
local function changed() dirty = true end

rune.timer.every(1, function()
  if dirty or os.time() >= next_draw then draw() end
end, { name = "affects_draw" })

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
  up[sn] = secs > 0 and os.time() + secs or 0
end

rune.trigger.exact("{spellheaders affected}", function(_, ctx)
  local lines = ctx.lines
  quiet = table.remove(queue, 1) == true
  up = {}
  for i = 2, #lines do on_spell(lines[i]:clean()) end
  changed()
  if not (quiet and closed(lines, "{/spellheaders}")) then show(lines) end
end, { name = "affects_slist_spells", gag = true, span = { to = "^\\{/spellheaders\\}$", max = 300 } })

-- Every recovery still running is listed: Create Totem is ready unless its
-- row (id,name,secs) comes
rune.trigger.exact("{recoveries affected}", function(_, ctx)
  local lines = ctx.lines
  totem.rec_end, totem.ready = 0, true
  for _, r in ipairs(recs) do r.ends = 0 end   -- ready unless listed
  for i = 2, #lines do
    local id, name, secs = lines[i]:clean():match("^(%d+),(.*),(%d+)$")
    id, secs = tonumber(id), tonumber(secs)
    if id == 65 then totem.rec_end, totem.ready = os.time() + secs, false end
    local r = name and rec_by_name[name:lower()]
    if r then rec_learn(r, id); r.ends = os.time() + secs end
  end
  seen = true
  changed()
  if quiet and closed(lines, "{/recoveries}") then util.eat_blanks("{/recoveries}") else show(lines) end
  quiet = false
end, { name = "affects_slist_recov", gag = true, span = { to = "^\\{/recoveries\\}$", max = 50 } })

-- The tags ----------------------------------------------------------------
-- (core/tags.lua hides them)

tags.on("affon", function(rest)
  local sn, secs = rest:match("^(%d+),(%-?%d+)$")
  if not sn then return end
  sn, secs = tonumber(sn), tonumber(secs)
  up[sn] = secs > 0 and os.time() + secs or 0
  if not spell[sn] then resync_soon(sn) end
  changed()
end)

tags.on("affoff", function(rest)
  local sn = rest:match("^(%d+)$")
  if not sn then return end
  up[tonumber(sn)] = nil
  changed()
end)

-- {recon}id,secs / {recoff}id: 65 is Create Totem; a tracked recovery's
-- id. Another id while a tracked one's id isn't known yet: a hidden slist,
-- once per id, whose recoveries rows name it
-- "debug recov" (core/debug.lua): each tag as it comes (hidden otherwise),
-- with the recovery it matched; its status line, the ids learned so far
local rec_dbg = require("core.debug").topic("recov",
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
  dbg("{recon}" .. rest, tonumber(rest:match("^(%d+)")))
  local id, secs = rest:match("^(%d+),(%d+)$")
  if not id then return end
  id, secs = tonumber(id), tonumber(secs)
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
  dbg("{recoff}" .. rest, tonumber(rest:match("^(%d+)")))
  local id = tonumber(rest:match("^(%d+)$"))
  if id == 65 then
    totem.rec_end, totem.ready = 0, true
  elseif id == 0 then
    if #recs > 0 then soon.start(1, resync) end
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
  util.eat_blanks(ctx.line:clean())
  return false
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
-- (see core/util.lua's note on triggers)
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
-- the tracked list is built for the subclass, and the first one fills the
-- pane with a hidden slist (and totem, on a Shaman)

rune.gmcp.on("char.base", function()
  if game.subclass and game.subclass ~= subclass then
    subclass = game.subclass
    build()
    totem_trig.set(subclass == "Shaman")
    changed()
  end
  if not seen and #queue == 0 then
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

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("saf", "saf / aff / affects [args]", "the game's command, then a hidden slist that resets the affects pane")
help.add("slist", "slist [args]", "the game's slist; a typed slist affected also resets the affects pane")
help.add("affectsreset", "affectsreset", "resync the affects pane (a light looks stuck or wrong)")
help.add("totem", "totem", "the game's totem; its reply also sets the totem line")
