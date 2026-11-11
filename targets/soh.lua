-- School of Horror mob keywords (tt++ modules/soh.tin). Its mobs have hidden
-- keywords, and Bamboo's bot answers "bb soh <mob>" in group chat with one:
--   (Group) Bamboo: '[Bambot] Keyword for "euphonix": ragbrai'
-- Every such reply seen (GMCP comm.channel, any channel, whoever asked) is
-- saved to data/soh.lua; this never asks the bot itself. A name is kept as
-- its last word, lower case ("evil euphonix", "an evil form of sagen": the
-- same mobs as euphonix, sagen). "Found nothing!" isn't saved; a different
-- keyword for a saved name is only reported, never written.
--   soh            how many are saved
--   soh <mob>      its keyword: that name, else every name containing it (20 at most)
-- For the other targets/ files:
--   soh.keyword(name)          the word to use for a soh mob (below, for which)
--   soh.for_mob(name, zone)    that word if zone is the School of Horror, else nil
--   soh.label(name, zone)      the name with it: "Evil Euphonix (ragbrai)" - the
--                              quest and campaign rows on the info pane

local util = require("core.util")
local colors = require("core.colors")
local theme = require("core.theme")
local travel = require("nav.travel")   -- same_area: soh and sohtwo are one area

local say, warn = util.say, util.warn
local FILE = rune.config_dir .. "/data/soh.lua"
local kw = util.load_data(FILE) or {}

local function short(name)
  return (util.trim(name):lower():match("(%S+)$")) or ""
end

-- Written to a .tmp file, then renamed over data/soh.lua; sorted, so a diff reads well
local HEADER = [[
-- School of Horror mob keywords: mob name (lower case, its last word only -
-- "evil euphonix" is euphonix) -> its hidden keyword, from Bambot's replies
-- to "bb soh <mob>". Converted from tt++ conf/soh_keywords.tin 2026-11-07;
-- targets/soh.lua adds a name a reply brings and rewrites this file (a
-- different keyword for a saved name is only reported). Hand-edit freely,
-- then /reload.
]]
local function save()
  local names = {}
  for n in pairs(kw) do names[#names + 1] = n end
  table.sort(names)
  util.write_file(FILE, function(fh)
    fh:write(HEADER, "return {\n")
    for _, n in ipairs(names) do fh:write(string.format("  [%q] = %q,\n", n, kw[n])) end
    fh:write("}\n")
  end, "[soh]")
end

rune.gmcp.on("comm.channel", function(d)
  if type(d) ~= "table" or type(d.msg) ~= "string" or not d.msg:find("Keyword for", 1, true) then return end
  local name, key = colors.strip(d.msg):match("Bambot.-Keyword for \"([^\"]-)\": (.-)'%s*$")
  if not name or key:find("^Found nothing") then return end
  name, key = short(name), key:gsub('"', "")
  if not name:match("^[a-z][a-z0-9'%-]*$") or key == "" or kw[name] == key then return end
  if kw[name] then
    warn("[soh] conflict for " .. name .. ": saved " .. kw[name] .. ", Bambot says " .. key .. " - not changed.")
    return
  end
  kw[name] = key
  save()
  rune.echo(theme.muted("[soh] saved " .. name .. " = " .. key))
end, { name = "soh_capture" })

rune.alias.exact("soh", function(args)
  local q = short(args)
  if q == "" then
    local n = 0
    for _ in pairs(kw) do n = n + 1 end
    say("[soh] " .. n .. " mob keywords saved. soh <mob> looks one up.")
    return
  end
  if kw[q] then rune.echo(q .. ": " .. theme.found(kw[q])); return end
  local hits = {}
  for n in pairs(kw) do if n:find(q, 1, true) then hits[#hits + 1] = n end end
  if #hits == 0 then warn("[soh] nothing saved for \"" .. q .. "\"."); return end
  table.sort(hits)
  for i = 1, math.min(#hits, 20) do rune.echo(hits[i] .. ": " .. theme.found(kw[hits[i]])) end
  if #hits > 20 then rune.echo(theme.muted("[soh] ... and " .. (#hits - 20) .. " more - type more of the name.")) end
end)

local soh = {}
-- The word to try: a note in brackets dropped ("weirdcode [magic immune]"),
-- then the first of several keywords ("KILLER Princess": KILLER; "A / B": A)
function soh.keyword(name)
  local k = kw[short(name or "")]
  if not k then return nil end
  return (k:gsub("%b[]", ""):match("^[^%s/]+"))
end
function soh.for_mob(name, zone)
  return name and travel.same_area(zone, "soh") and soh.keyword(name) or nil
end

function soh.label(name, zone)
  local k = soh.for_mob(name, zone)
  return k and (name .. " (" .. k .. ")") or name
end

-- Help (core/help.lua): /help
local help = require("core.help")
help.add("soh", "soh [mob]", "School of Horror mob keywords: how many are saved, or a mob's (any name containing it)")

return soh
