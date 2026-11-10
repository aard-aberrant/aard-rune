-- eqwear (tt++ modules/eqsets.tin): puts on the pieces of an equipment set
-- you aren't wearing, from EQBAG, and puts what they replace back in it.
--   eqwear          the set for your level: the highest saved level at or
--                   below it (named sets are never picked this way)
--   eqwear <level>  the set for that level
--   eqwear <name>   a named set (eqwear bcc)
--   eqsave [level | name]  what you wear now, saved as that set (default:
--                   your level) - replaces one of that name
--   eqcheck [level | name]  the set's pieces you aren't wearing
--   eqsets          the sets, yours marked; eqsets <set> its items;
--                   eqsets del <set> removes one
--   dt <type> | next | reset, d1 .. d6   damage-type weapons (below)
-- The sets are data/eqsets.lua: set -> wear location -> { id, name },
-- rewritten by eqsave.
-- What you wear comes from a hidden eqdata, asked for each time - the
-- reply is {eqdata}, one row per item (id,flags,name,level,type,unique,
-- wearloc,...), {/eqdata}. For 5 s after the commands go, every item the
-- game's invmon tag says came off (gear/invmon.lua) goes into EQBAG - that
-- includes anything a two-handed weapon pushed off. At load a hidden
-- eqdata seeds gear/invmon.lua's list of what's worn.

local util = require("core.util")
local colors = require("core.colors")
local theme = require("core.theme")
local invmon = require("gear.invmon")   -- what's worn; what came off (into the bag)
local game = require("core.game")       -- your level (the set for it)
local tags = require("core.tags")       -- the eqdata reply's tags

local say, warn = util.say, util.warn

local EQBAG = "eqbag"
-- Paired slots need the slot named, or the game may replace the other one
-- (tt++: confirmed for ears; the others assumed to follow)
local SLOT_KW = { [3] = "lear", [4] = "rear", [5] = "neck1", [6] = "neck2",
  [16] = "lwrist", [17] = "rwrist", [19] = "lfinger", [20] = "rfinger" }
local OFFHAND = 25   -- wear would wield it in the main hand: dual instead

local sets = util.load_data(rune.config_dir .. "/data/eqsets.lua") or {}

-- The set for `want` (a name, a level, or "" for yours) and its key
local function pick(want)
  if want ~= "" and not want:match("^%d+$") then return sets[want], want end
  local lvl, best = tonumber(want) or game.level or 0, nil
  for k in pairs(sets) do
    if type(k) == "number" and k <= lvl and (not best or k > best) then best = k end
  end
  return best and sets[best], best
end

-- eqdata, hidden -------------------------------------------------------

local on_rows        -- callback waiting for the reply: on_rows(worn), worn =
                     -- id -> { name, loc }
local no_reply = util.slot()   -- 10 s after eqdata is sent
local worn           -- id -> true, filling
local row_line       -- the row reader: exists only inside a reply

local hide = util.hide

-- A row: id,flags,name,level,type,unique,wearloc,... - the name may hold
-- commas, so it runs up to the first four numbers after it. Added at
-- {eqdata}, removed at {/eqdata} (or the timeout): a disabled trigger is
-- still matched on every line (core/util.lua's note)
util.hider(function() return row_line ~= nil end)
local function row_off() if row_line then row_line:remove(); row_line = nil end end
local function row_on()
  row_off()
  row_line = rune.trigger.starts("", function(_, ctx)
    local id, rest = ctx.line:clean():match("^(%d+),(.*)$")
    if not id then return end
    local name, loc = (rest .. ","):match("^[^,]*,(.-),%-?%d+,%-?%d+,%-?%d+,(%-?%d+),")
    worn[id] = { name = name and util.trim(colors.uncolor(name)),
                 loc = tonumber(loc) }
    return false
  end, { name = "eq_row", priority = 5 })
end

tags.on("eqdata", function(rest, ctx)
  if not on_rows or rest ~= "" then return end
  worn = {}
  row_on()
  return hide(ctx)
end)


tags.on("/eqdata", function(rest, ctx)
  if not on_rows or rest ~= "" then return end
  row_off()
  local cb = on_rows
  on_rows = nil
  cb(worn)
  return hide(ctx)
end)

-- Ask for eqdata, hidden; cb(worn) with the reply. false if one is out
local function eqdata(cb, what)
  if on_rows then warn("[eq] " .. what .. ": still waiting for eqdata."); return false end
  on_rows = cb
  no_reply.start(10, function()
    if on_rows then on_rows = nil; row_off(); warn("[eq] " .. what .. ": no eqdata reply.") end
  end)
  rune.send_raw("eqdata")
  return true
end

-- Removed items back in the bag ----------------------------------------

local bag_until = 0
invmon.on(function(action, id)
  if action == 1 and os.time() <= bag_until then rune.send_raw("put " .. id .. " " .. EQBAG) end
end)

-- For 5 s from now, everything that comes off goes into EQBAG
local function bag_removed() bag_until = os.time() + 5 end

-- The set's wear locations whose item isn't worn, in order
local function missing(set, now)
  local locs = {}
  for loc, item in pairs(set) do
    if not now[tostring(item.id)] then locs[#locs + 1] = loc end
  end
  table.sort(locs)
  return locs
end

local function no_set(cmd, want)
  warn("[eq] " .. cmd .. ": no set called " .. (want ~= "" and want or "for your level") .. ".")
end

-- eqwear -----------------------------------------------------------------

rune.alias.exact("eqwear", function(args)
  local want = util.trim(args):lower()
  local set, key = pick(want)
  if not set then return no_set("eqwear", want) end
  eqdata(function(now)
    local locs = missing(set, now)
    if #locs == 0 then return say("[eq] eqwear: already wearing the whole " .. key .. " set.") end
    local cmds = {}
    for _, loc in ipairs(locs) do
      local id = tostring(set[loc].id)
      cmds[#cmds + 1] = "get " .. id .. " " .. EQBAG
      if loc == OFFHAND then cmds[#cmds + 1] = "dual " .. id
      else cmds[#cmds + 1] = "wear " .. id .. (SLOT_KW[loc] and (" " .. SLOT_KW[loc]) or "") end
    end
    say("[eq] eqwear: putting on " .. #locs .. (#locs == 1 and " piece" or " pieces") .. " of the " .. key .. " set.")
    bag_removed()
    rune.send_raw(table.concat(cmds, "\n"))
  end, "eqwear")
end)

-- eqsave -----------------------------------------------------------------

local SETS_FILE = rune.config_dir .. "/data/eqsets.lua"

-- The sets' keys: levels in order, then names
local function set_keys()
  local keys = {}
  for k in pairs(sets) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) == "number" end
    return a < b
  end)
  return keys
end

local function save()
  local keys = set_keys()
  local out = { "-- Equipment sets for eqwear: set -> wear location -> { id, name }. A set is",
    "-- a level (used from that level up to the next saved one) or a name (only",
    "-- when asked for: eqwear titan). Rewritten by eqsave; hand-editable.", "return {" }
  for _, k in ipairs(keys) do
    out[#out + 1] = type(k) == "number" and ("  [" .. k .. "] = {") or string.format("  [%q] = {", k)
    local locs = {}
    for loc in pairs(sets[k]) do locs[#locs + 1] = loc end
    table.sort(locs)
    for _, loc in ipairs(locs) do
      local it = sets[k][loc]
      out[#out + 1] = string.format("    [%d] = { id = %s, name = %q },", loc, tostring(it.id), it.name or "")
    end
    out[#out + 1] = "  },"
  end
  out[#out + 1] = "}"
  return util.write_file(SETS_FILE, function(fh) fh:write(table.concat(out, "\n"), "\n") end, "[eq]")
end

-- eqsave [level | name]: what you wear now, as that set (default: your level)
rune.alias.exact("eqsave", function(args)
  local want = util.trim(args):lower()
  if want == "" then want = tostring(game.level or "") end
  if not want:match("^[a-z0-9_-]+$") then
    return warn("[eq] eqsave: a level or a name (letters, digits, _ and -).")
  end
  local key = tonumber(want) or want
  eqdata(function(now)
    local set, n = {}, 0
    for id, it in pairs(now) do
      if it.loc and it.loc >= 0 then
        set[it.loc] = { id = tonumber(id), name = it.name }
        n = n + 1
      end
    end
    if n == 0 then return warn("[eq] eqsave: nothing worn was read - not saved.") end
    local had = sets[key] ~= nil
    sets[key] = set
    if save() then
      say("[eq] eqsave: " .. n .. " items saved as the " .. key .. " set" .. (had and " (replacing the old one)." or "."))
    end
  end, "eqsave")
end)

-- eqcheck ----------------------------------------------------------------

-- eqcheck [level | name]: the set's pieces you aren't wearing
rune.alias.exact("eqcheck", function(args)
  local want = util.trim(args):lower()
  local set, key = pick(want)
  if not set then return no_set("eqcheck", want) end
  eqdata(function(now)
    local locs = missing(set, now)
    if #locs == 0 then return say("[eq] eqcheck: wearing the whole " .. key .. " set.") end
    say("[eq] eqcheck: not wearing these from the " .. key .. " set:")
    for _, loc in ipairs(locs) do
      local it = set[loc]
      rune.echo(string.format("  %2d %s %s", loc, it.name or "?", theme.muted("(" .. tostring(it.id) .. ")")))
    end
  end, "eqcheck")
end)

-- eqsets -----------------------------------------------------------------

-- eqsets: the sets, the one for your level marked. eqsets <set>: its items.
-- eqsets del <set>: removes it
rune.alias.exact("eqsets", function(args)
  local a, b = util.trim(args):lower():match("^(%S*)%s*(.-)$")
  if a == "del" then
    local key = tonumber(b) or b
    if b == "" or not sets[key] then return warn("[eq] eqsets: no set saved as " .. b .. ".") end
    sets[key] = nil
    if save() then say("[eq] eqsets: removed the " .. b .. " set.") end
    return
  end
  if a ~= "" then
    local set = sets[tonumber(a) or a]
    if not set then return warn("[eq] eqsets: no set saved as " .. a .. ".") end
    local locs = {}
    for loc in pairs(set) do locs[#locs + 1] = loc end
    table.sort(locs)
    for _, loc in ipairs(locs) do
      rune.echo(string.format("  %2d %s %s", loc, set[loc].name or "?", theme.muted("(" .. tostring(set[loc].id) .. ")")))
    end
    return
  end
  local keys = set_keys()
  if #keys == 0 then return say("[eq] no equipment sets yet - wear one and eqsave [level | name].") end
  local _, mine = pick("")
  for _, k in ipairs(keys) do
    local n = 0
    for _ in pairs(sets[k]) do n = n + 1 end
    rune.echo("  " .. theme.value(tostring(k)) .. ": " .. n .. " items"
      .. (k == mine and theme.found("  <- your level") or ""))
  end
end)

-- dt ---------------------------------------------------------------------
-- dt <type>  wield that damage type's weapon from EQBAG (a unique start of
--            the name works: dt elec); the one it replaces goes back in
-- dt n(ext)  the next type, alphabetically, wrapping; from the primary
--            weapon, the first
-- dt r(eset) back to the primary weapon
-- dt         the types.   d1 .. d6: dt <type>, from data/weapons.lua
-- What's wielded: gear/invmon.lua's worn list, at the wield slot (24 - assumed:
-- the saved sets hold a shard there, 25 is the off hand); else what dt
-- last wielded.

local W = util.load_data(rune.config_dir .. "/data/weapons.lua") or { types = {}, keys = {} }
local WIELD = 24
local last_dt          -- what dt last wielded, until invmon says

-- The id in the wield slot, as a string, if known
local function wielded()
  for id, loc in pairs(invmon.worn) do
    if loc == WIELD then return id end
  end
  return last_dt
end

local types = {}
for t in pairs(W.types) do types[#types + 1] = t end
table.sort(types)

local function type_of(id)
  for t, wid in pairs(W.types) do
    if tostring(wid) == id then return t end
  end
end

local function wield(id, what)
  id = tostring(id)
  if wielded() == id then return say("[eq] dt: " .. what .. " is already wielded.") end
  say("[eq] dt: " .. what .. " -> " .. id)
  bag_removed()
  last_dt = id
  rune.send_raw("get " .. id .. " " .. EQBAG .. "\nwield " .. id)
end

local function dt(arg)
  arg = util.trim(arg):lower()
  if arg == "" then
    return say("[eq] dt types: " .. table.concat(types, " ") .. " | also dt next, dt reset")
  end
  if arg == "r" or arg == "reset" then
    if not W.primary then return warn("[eq] dt: no primary weapon in data/weapons.lua.") end
    return wield(W.primary, "primary weapon")
  end
  if arg == "n" or arg == "next" then
    local w = wielded()
    local cur = w and type_of(w)
    local nxt = types[1]
    for i, t in ipairs(types) do
      if t == cur then nxt = types[i % #types + 1] end
    end
    if not nxt then return warn("[eq] dt: no weapons in data/weapons.lua.") end
    return wield(W.types[nxt], nxt)
  end
  local hits = {}
  for _, t in ipairs(types) do
    if t == arg then hits = { t }; break end
    if t:sub(1, #arg) == arg then hits[#hits + 1] = t end
  end
  if #hits == 1 then return wield(W.types[hits[1]], hits[1]) end
  if #hits > 1 then return warn("[eq] dt: several types start with " .. arg .. ": " .. table.concat(hits, " ")) end
  warn("[eq] dt: no weapon for " .. arg .. ".")
  dt("")
end

rune.alias.exact("dt", function(args) dt(args) end)
for i, t in ipairs(W.keys or {}) do
  rune.alias.exact("d" .. i, function() dt(t) end)
end

-- What's worn, for gear/invmon.lua, from a hidden eqdata: at load (after a
-- /reload it knows nothing) and on each bare g (nav/travel.lua - the eqdata
-- also marks the end of g's chores)
local function check_worn()   -- false if an eqdata was already out
  return eqdata(function(now)
    local worn = {}
    for id, it in pairs(now) do if it.loc then worn[id] = it.loc end end
    invmon.seed(worn)
  end, "checking what's worn")
end

game.on_login(check_worn)

-- Beating the idle logout (tt++ modules/afk.tin sent board all): at the
-- game's idle warning, a hidden eqdata - any command resets the idle clock,
-- and this one's reply is hidden already. The line, "Your eyes glaze over.",
-- isn't in the tt++ logs: the wording is from a gossip tip ("just trigger
-- "Your eyes glaze over." to look or score") and others going idle in the
-- room ("X's eyes glaze over and he appears to be somewhere else."). tt++
-- matched it anywhere; anchored here, so a channel quoting it can't set it off
rune.trigger.starts("Your eyes glaze over.", function() check_worn() end, { name = "afk_glaze" })

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("eqwear", "eqwear [level | name]", "wear the set for your level (or that level / named set) from the eq bag; what it replaces goes in the bag")
help.add("eqsave", "eqsave [level | name]", "save what you wear now as a set (default: your level)")
help.add("eqcheck", "eqcheck [level | name]", "the set's pieces you aren't wearing")
help.add("eqsets", "eqsets [set | del <set>]", "the saved sets (yours marked), one set's items, or delete one")
help.add("dt", "dt <type> | next | reset", "wield the damage-type weapon for <type> (a unique start works), the next type, or back to your primary")
help.add("d1", "d1 .. d6", "dt for the damage types in data's order")

return { bag = EQBAG, check_worn = check_worn }
