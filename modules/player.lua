-- Your character's own things (require("modules.player")): data/player.lua,
-- a section per character - its name as GMCP char.base spells it,
-- lowercased - holding its bags, consumables, worn items, and a section
-- per subclass (attacks, su, heal ...). The password stays in .env.
-- Read once at load: /reload after editing.
--
-- Modules say what they need, so the list is in code, beside its use:
--   local need = player.needs("modules.rheal", {
--     regen_ring = "rh: worn for regeneration, then back in the eq bag",
--   })
--   need("regen_ring")         -- the value; missing: a warning, nil
--   need("regen_ring", true)   -- the same, no warning (a hot path)
-- A subclass's keys (looked up in the character's section for the
-- subclass playing now):
--   player.needs("modules.combat", { pattack = "k: ...", k_fight = { "...", optional = true } },
--                { subclass = true })
--   player.class()             -- that subclass's table, or nil
-- Optional keys ({ desc, optional = true }) are listed but never warned
-- about. When char.base brings a new character or subclass, the required
-- keys missing from its section are warned about once, each naming the
-- module that needs it.
--   player.fill(text)          -- {key} in an alias -> its value; {get key}
--                                 -> "get <item> <medkit>" for a consumable
--                                 ("eat fugu": the item is after the verb;
--                                 medkit "": nothing). nil, key if one's missing
--   player.on_change(fn)       fn() after /player set, unset or save (a
--                                 module that keeps a value it read)
-- /player                        the declared keys: module, why, value now
-- /player set <key> <value>      a temporary value: kept over a /reload,
--                                gone at a restart. <key>: one of yours
--                                (light), your subclass's (pattack), another
--                                subclass's (shaman.pattack), or a part of a
--                                pair (pattack.hit, paoe.cooldown, pattack.1
--                                the command). A whole key set replaces it
--                                whole (a pair's hit goes too)
-- /player unset [key]            back to the file's value (none: all)
-- /player save [key]             the temporary values into data/player.lua
--                                (none: all) - only each value is rewritten
--                                on its line (lib/luaedit.lua), and the file
--                                is written only if it reads back with
--                                exactly the new values and nothing else changed
-- Cost: nothing per line; a check at each char.base that changes the
-- character or subclass.

local util = require("lib.util")
local game = require("modules.game")   -- the character's name, the subclass

local say, warn = util.say, util.warn

local P = {}
local FILE = "data/player.lua"
local PATH = rune.config_dir .. "/" .. FILE
local data = util.load_data(PATH) or {}

-- key -> { module, desc, optional, parts }, for the character's own keys
-- (top) and its subclass sections' (sub)
local top, sub = {}, {}

-- The character: game's name once char.base came, else the one kept over
-- a /reload
local NAME_KEY = "player_name"
local function name() return game.name or rune.session.get(NAME_KEY) end
P.name = name

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end

-- Temporary values (/player set): { { path = "light" | "priest.pattack" |
-- "priest.pattack.hit", value } ... } in the order set, per character, kept
-- in rune.session as "path\tvalue" lines
local function over_key(n) return "player_over." .. n end
local function overrides(n)
  local list = {}
  for line in (rune.session.get(over_key(n)) or ""):gmatch("[^\n]+") do
    local path, v = line:match("^([^\t]+)\t(.*)$")
    if path then list[#list + 1] = { path = path, value = v } end
  end
  return list
end
local function keep_overrides(n, list)
  local out = {}
  for _, o in ipairs(list) do out[#out + 1] = o.path .. "\t" .. o.value end
  if #out == 0 then rune.session.delete(over_key(n)) else rune.session.set(over_key(n), table.concat(out, "\n")) end
end

-- One temporary value put into a section (a copy of the file's)
local function apply(s, path, v)
  local segs = {}
  for seg in path:gmatch("[^.]+") do segs[#segs + 1] = seg end
  local t, key, part = s, segs[1], segs[2]
  if sub[segs[2] or ""] and not top[segs[1]] then   -- subclass.key[.part]
    if type(s[segs[1]]) ~= "table" then s[segs[1]] = {} end
    t, key, part = s[segs[1]], segs[2], segs[3]
  end
  if not part then t[key] = v; return end
  local cur = t[key]
  if part == "1" then
    if type(cur) == "table" then cur = copy(cur); cur[1] = v; t[key] = cur else t[key] = v end
  elseif type(cur) == "table" then cur = copy(cur); cur[part] = v; t[key] = cur
  else t[key] = { cur, [part] = v } end
end

-- The section in use: the file's, with the temporary values over it -
-- built when the character or the temporary values change
local built, built_for
local function rebuild() built_for = nil end
local function section()
  local n = name()
  if not n then return nil end
  if built_for ~= n then
    built_for = n
    local base = type(data[n]) == "table" and data[n] or nil
    local list = overrides(n)
    if not base and #list == 0 then built = nil
    else
      built = copy(base or {})
      for _, o in ipairs(list) do apply(built, o.path, o.value) end
    end
  end
  return built
end

local changed = {}
function P.on_change(fn) changed[#changed + 1] = fn end
local function tell() rebuild(); for _, fn in ipairs(changed) do pcall(fn) end end

-- The subclass playing now's table in the character's section, or nil
function P.class(subclass)
  local s, c = section(), subclass or game.subclass
  local t = s and c and s[c:lower()]
  return type(t) == "table" and t or nil
end

local function missing_text(key, d, where)
  if not name() then return "[player] the character isn't known yet (after login) - " .. key .. " is in its section" end
  return "[player] " .. name() .. " has no " .. key .. where
    .. " in " .. FILE .. " - " .. d.module .. " needs it (" .. d.desc .. ")"
end

local function value(key, is_sub)
  local t = is_sub and P.class() or section()
  return t and t[key]
end

function P.needs(module, decls, opts)
  local is_sub = opts and opts.subclass
  local into = is_sub and sub or top
  for key, d in pairs(decls) do
    if into[key] then error("[player] " .. key .. " is declared by both " .. into[key].module .. " and " .. module, 2) end
    if type(d) == "table" then into[key] = { module = module, desc = d[1] or "", optional = d.optional, parts = d.parts }
    else into[key] = { module = module, desc = d } end
  end
  return function(key, quiet)
    local d = into[key]
    if not d then error("[player] " .. module .. " didn't declare " .. tostring(key), 2) end
    local v = value(key, is_sub)
    if v == nil and not quiet and not d.optional then
      warn(missing_text(key, d, is_sub and (" for " .. tostring(game.subclass or "its subclass")) or ""))
    end
    return v
  end
end

-- {key} and {get key} filled from the character's section; nil and the
-- missing key if one isn't there
local function warn_missing(key)
  local d = top[key] or { module = "your /alias", desc = "{" .. key .. "}" }
  warn(missing_text(key, d, ""))
end
function P.fill(text)
  if not text:find("{", 1, true) then return text end
  local s, gone, dropped = section() or {}, nil, false
  local function get(key)
    local v = s[key]
    if type(v) ~= "string" then gone = gone or key; return nil end
    return v
  end
  local out = text:gsub("{get ([%w_]+)}", function(key)
    local v, kit = get(key), get("medkit")
    if not (v and kit) then return "" end
    if kit == "" then dropped = true; return "" end
    return "get " .. (v:match("^%S+%s+(.+)$") or v) .. " " .. kit
  end):gsub("{([%w_]+)}", function(key) return get(key) or "" end)
  if gone then warn_missing(gone); return nil, gone end
  -- a {get key} with no medkit left an empty command: its ";" goes too
  if dropped then out = out:gsub(";%s*;", ";"):gsub("^%s*;%s*", ""):gsub("%s*;%s*$", "") end
  return out
end

-- The required keys missing now: { "key (module)" ... }
local function check()
  local out, s, c = {}, section(), P.class()
  if not name() then return out end
  for key, d in pairs(top) do
    if not d.optional and (not s or s[key] == nil) then out[#out + 1] = key .. " (" .. d.module .. ")" end
  end
  if game.subclass then
    for key, d in pairs(sub) do
      if not d.optional and (not c or c[key] == nil) then
        out[#out + 1] = game.subclass:lower() .. "." .. key .. " (" .. d.module .. ")"
      end
    end
  end
  table.sort(out)
  return out
end

local function check_warn()
  local gone = check()
  if #gone == 0 then return end
  if not section() then
    warn("[player] " .. FILE .. " has no section for " .. name() .. " - data/player.example.lua is a start; /player lists what each key is for")
    return
  end
  warn("[player] " .. FILE .. ": " .. name() .. " is missing " .. table.concat(gone, ", ") .. " - /player lists what each is for")
end

-- Checked when char.base brings a new character or subclass (init.lua asks
-- for char.base at every load, so a /reload checks too, once every module
-- has declared its keys)
local checked_for
rune.gmcp.on("char.base", function()
  if game.name then rune.session.set(NAME_KEY, game.name) end
  local k = tostring(name()) .. "/" .. tostring(game.subclass)
  if k == checked_for then return end
  checked_for = k
  check_warn()
end, { name = "player_check" })

-- /player: every declared key, the module needing it, why, its value
local function show(v, optional)
  if v == nil then return optional and "(not set)" or "(missing)" end
  if type(v) == "table" then
    -- a pair ({ cmd, hit = ... }) or a list: its items, then its named values
    local parts = {}
    for _, x in ipairs(v) do parts[#parts + 1] = tostring(x) end
    local names = {}
    for k in pairs(v) do if type(k) == "string" then names[#names + 1] = k end end
    table.sort(names)
    for _, k in ipairs(names) do parts[#parts + 1] = k .. " = " .. tostring(v[k]) end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return v == "" and '""' or tostring(v)
end
-- What a typed key names: { path, base, decl } - path as kept ("light",
-- "priest.pattack.hit"), base the whole key it's part of ("priest.pattack"),
-- or nil and why
local function close_names(word)
  local out = {}
  for _, decl in ipairs({ top, sub }) do
    for k in pairs(decl) do
      if k:find(word:sub(1, 2), 1, true) or word:find(k, 1, true) then out[#out + 1] = k end
    end
  end
  table.sort(out)
  return #out > 0 and (" - did you mean " .. table.concat(out, ", ") .. "?") or " - /player lists them"
end
local function resolve(spec)
  local segs = {}
  for seg in spec:lower():gmatch("[^.]+") do segs[#segs + 1] = seg end
  local cls, key, part
  if top[segs[1]] then key, part = segs[1], segs[2]
  elseif sub[segs[1]] then
    if not game.subclass then return nil, "your subclass isn't known yet - name it: <subclass>." .. segs[1] end
    cls, key, part = game.subclass:lower(), segs[1], segs[2]
  elseif segs[2] and sub[segs[2]] then cls, key, part = segs[1], segs[2], segs[3]
  else return nil, "no key " .. spec .. close_names(segs[1] or "") end
  local d = cls and sub[key] or top[key]
  if part and part ~= "1" then
    local ok = false
    for _, x in ipairs(d.parts or {}) do if x == part then ok = true end end
    if not ok then
      return nil, key .. " has no part " .. part .. (d.parts and (" - its parts: 1 (the command), " .. table.concat(d.parts, ", ")) or " - it's one value")
    end
  end
  if (#segs > (cls and not sub[segs[1]] and 3 or 2)) then return nil, "too many parts in " .. spec end
  local base = (cls and (cls .. ".") or "") .. key
  return { path = base .. (part and ("." .. part) or ""), base = base, cls = cls, key = key, decl = d }
end

-- /player set / unset / save ---------------------------------------------

local function set_cmd(rest)
  local spec, v = rest:match("^(%S+)%s+(.-)%s*$")
  if not spec or v == "" then warn("[player] /player set <key> <value> (\"\" for empty)"); return end
  if v == '""' or v == "''" then v = "" end
  local r, why = resolve(spec)
  if not r then warn("[player] " .. why); return end
  local n = name()
  local list, keep = overrides(n), {}
  for _, o in ipairs(list) do
    -- the same path again, or a whole key over its parts: the old ones go
    if o.path ~= r.path and not (r.path == r.base and o.path:sub(1, #r.base + 1) == r.base .. ".") then keep[#keep + 1] = o end
  end
  keep[#keep + 1] = { path = r.path, value = v }
  keep_overrides(n, keep)
  tell()
  local t = r.cls and P.class(r.cls) or section()
  say("[player] " .. r.base .. " = " .. show(t and t[r.key]) .. " (temporary - /player save keeps it, /player unset drops it)")
end

local function unset_cmd(spec)
  local n = name()
  local list = overrides(n)
  if spec == "" then
    keep_overrides(n, {})
    tell()
    say("[player] " .. (#list == 0 and "no temporary values." or ("back to " .. FILE .. ": " .. #list .. " temporary value" .. (#list == 1 and "" or "s") .. " dropped.")))
    return
  end
  local r, why = resolve(spec)
  if not r then warn("[player] " .. why); return end
  local keep, gone = {}, 0
  for _, o in ipairs(list) do
    if o.path == r.path or (r.path == r.base and o.path:sub(1, #r.base + 1) == r.base .. ".") then gone = gone + 1
    else keep[#keep + 1] = o end
  end
  if gone == 0 then say("[player] " .. r.path .. " has no temporary value."); return end
  keep_overrides(n, keep)
  tell()
  say("[player] " .. r.path .. " back to " .. FILE .. "'s.")
end

local function equal(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function read_file()
  local fh = io.open(PATH, "r")
  if not fh then return nil end
  local text = fh:read("*a")
  fh:close()
  return text
end
local function load_text(text)
  local f = (loadstring or load)(text, "=" .. FILE)
  if not f then return nil end
  if setfenv then setfenv(f, {}) end
  local ok, t = pcall(f)
  return ok and type(t) == "table" and t or nil
end

local luaedit = require("lib.luaedit")
local function save_cmd(spec)
  local n = name()
  local list = overrides(n)
  local bases, seen = {}, {}
  local only
  if spec ~= "" then
    local r, why = resolve(spec)
    if not r then warn("[player] " .. why); return end
    only = r.base
  end
  for _, o in ipairs(list) do
    local r = resolve(o.path)
    if r and (not only or r.base == only) and not seen[r.base] then seen[r.base] = true; bases[#bases + 1] = r end
  end
  if #bases == 0 then say("[player] nothing to save" .. (only and (" for " .. only) or "") .. " - /player set makes a temporary value."); return end
  local text = read_file()
  if not text then warn("[player] can't read " .. FILE .. "."); return end
  local now = section()
  local expect = copy(data)
  expect[n] = type(expect[n]) == "table" and expect[n] or {}
  for _, r in ipairs(bases) do
    local t = r.cls and (now[r.cls] or {}) or now
    local v = t[r.key]
    local path = { n }
    local into = expect[n]
    if r.cls then
      path[2] = r.cls
      if type(into[r.cls]) ~= "table" then into[r.cls] = {} end
      into = into[r.cls]
    end
    local out, why = luaedit.set(text, path, r.key, luaedit.literal(v), r.decl.module .. ": " .. (r.decl.desc:match("^(.-) %- ") or r.decl.desc))
    if not out then warn("[player] can't save " .. r.base .. ": " .. why .. " - nothing written; edit " .. FILE .. " by hand"); return end
    text = out
    into[r.key] = copy(v)
  end
  -- written only if it reads back exactly as expected: the new values, the rest as it was
  local back = load_text(text)
  if not back or not equal(back, expect) then
    warn("[player] save stopped: " .. FILE .. " wouldn't read back as expected - nothing written; edit it by hand")
    return
  end
  if not util.write_file(PATH, function(fh) fh:write(text) end, "[player]") then return end
  data = back
  local keep = {}
  for _, o in ipairs(list) do
    local r = resolve(o.path)
    if not (r and seen[r.base]) then keep[#keep + 1] = o end
  end
  keep_overrides(n, keep)
  tell()
  local names = {}
  for _, r in ipairs(bases) do names[#names + 1] = r.base end
  say("[player] saved to " .. FILE .. ": " .. table.concat(names, ", "))
end

-- /player [set | unset | save]: the list, or a change
rune.command.add("player", function(args)
  local n = name()
  if not n then warn("[player] the character isn't known yet - after login."); return end
  args = util.trim(args or "")
  local verb, rest = args:match("^(%S+)%s*(.-)%s*$")
  if verb == "set" then set_cmd(rest); return
  elseif verb == "unset" then unset_cmd(rest); return
  elseif verb == "save" then save_cmd(rest); return
  elseif verb then warn("[player] /player, /player set <key> <value>, /player unset [key], /player save [key]"); return end
  local gone = check()
  if #gone > 0 then warn("[player] missing: " .. table.concat(gone, ", ")) end
  -- the temporary values' whole keys, and what the file has for them
  local temp = {}
  for _, o in ipairs(overrides(n)) do
    local r = resolve(o.path)
    if r then temp[r.base] = true end
  end
  local file = type(data[n]) == "table" and data[n] or {}
  local function list(head, decl, t, cls)
    local keys = {}
    for k in pairs(decl) do keys[#keys + 1] = k end
    table.sort(keys)
    rune.echo(head)
    for _, k in ipairs(keys) do
      local d = decl[k]
      local base = (cls and (cls .. ".") or "") .. k
      local was = cls and (type(file[cls]) == "table" and file[cls][k]) or (not cls and file[k]) or nil
      local mark = temp[base] and ("  (temporary; file: " .. show(was, d.optional) .. ")") or (d.optional and "  (optional)" or "")
      rune.echo("  " .. k .. " = " .. show(t and t[k], d.optional) .. mark)
      rune.echo("      " .. d.module .. ": " .. d.desc)
    end
  end
  local s = section()
  list(n .. " (" .. FILE .. ")", top, s)
  if game.subclass then list(n .. "." .. game.subclass:lower(), sub, P.class(), game.subclass:lower()) end
  -- in the section but declared by nothing: {key} for your own /alias
  local extra = {}
  for k, v in pairs(s or {}) do
    if not top[k] and type(v) ~= "table" then extra[#extra + 1] = k .. " = " .. show(v) end
  end
  table.sort(extra)
  if #extra > 0 then rune.echo("  no module needs (yours for {key} in /alias): " .. table.concat(extra, ", ")) end
end, "your character's things in data/player.lua: /player lists each key (the module that needs it, why, its value); set <key> <value> (temporary), unset [key], save [key] (into the file)")

return P
