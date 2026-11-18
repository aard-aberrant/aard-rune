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
--   /player                    the declared keys: module, why, value now
-- Cost: nothing per line; a check at each char.base that changes the
-- character or subclass.

local util = require("lib.util")
local game = require("modules.game")   -- the character's name, the subclass

local say, warn = util.say, util.warn

local P = {}
local FILE = "data/player.lua"
local data = util.load_data(rune.config_dir .. "/" .. FILE) or {}

-- key -> { module, desc, optional }, for the character's own keys (top)
-- and its subclass sections' (sub)
local top, sub = {}, {}

-- The character: game's name once char.base came, else the one kept over
-- a /reload
local NAME_KEY = "player_name"
local function name() return game.name or rune.session.get(NAME_KEY) end
P.name = name

local function section()
  local n = name()
  local s = n and data[n]
  return type(s) == "table" and s or nil
end

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
    if type(d) == "table" then into[key] = { module = module, desc = d[1] or "", optional = d.optional }
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
rune.command.add("player", function()
  local n = name()
  if not n then warn("[player] the character isn't known yet - after login."); return end
  local gone = check()
  if #gone > 0 then warn("[player] missing: " .. table.concat(gone, ", ")) end
  local function list(head, decl, t)
    local keys = {}
    for k in pairs(decl) do keys[#keys + 1] = k end
    table.sort(keys)
    rune.echo(head)
    for _, k in ipairs(keys) do
      local d = decl[k]
      rune.echo("  " .. k .. " = " .. show(t and t[k], d.optional) .. (d.optional and "  (optional)" or ""))
      rune.echo("      " .. d.module .. ": " .. d.desc)
    end
  end
  local s = section()
  list(n .. " (" .. FILE .. ")", top, s)
  if game.subclass then list(n .. "." .. game.subclass:lower(), sub, P.class()) end
  -- in the section but declared by nothing: {key} for your own /alias
  local extra = {}
  for k, v in pairs(s or {}) do
    if not top[k] and type(v) ~= "table" then extra[#extra + 1] = k .. " = " .. show(v) end
  end
  table.sort(extra)
  if #extra > 0 then rune.echo("  no module needs (yours for {key} in /alias): " .. table.concat(extra, ", ")) end
end, "your character's things in data/player.lua: each key, the module that needs it and why, its value")

return P
