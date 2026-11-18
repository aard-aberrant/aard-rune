-- /alias: ad hoc aliases made at the keyboard (tt++'s #alias), the
-- counterpart of /act (modules/act.lua). Kept until /unalias in their own
-- file, aliases.txt in the config folder: one a line, as typed after /alias
-- ("gq = get all;put all bag"). Rewritten whole on each /alias or /unalias;
-- read at load, so a /reload or a restart brings them back, and a hand edit
-- takes effect at the next /reload. A line that won't read is reported and
-- left out - and so is gone from the file at the next /alias or /unalias.
--   /alias                      the list, numbered
--   /alias <word> = <commands>  typing <word> sends <commands>
--   /unalias <n | word>         remove one (its number in the list, or its word)
-- In <commands>: ";" separates commands, %0 is everything typed after the
-- word, %1 %2 ... its words. With no %0-%9 in them, what's typed after the
-- word goes on the end (as Rune's own string aliases do): with
-- "bs = backstab", "bs orc" sends "backstab orc". {key} is your
-- character's value from data/player.lua, {get key} "get <item> <medkit>"
-- (modules/player.lua): "/alias lt = wear {light}". One missing: a
-- warning, nothing sent.
-- The commands go as if typed: returned to Rune, which splits them at ";",
-- runs them through aliases (so one can use another) and stops a loop.
-- Only these: an alias made in the config (modules/aliases.lua, combat's
-- k ...) can't be replaced or removed here. The same word again replaces
-- its commands.
-- Cost: one entry in Rune's exact-alias table each - looked up only when
-- you type a command; nothing per line.

local util = require("lib.util")
local player = require("modules.player")   -- {key} in the commands
local say, warn = util.say, util.warn

local list = {}   -- { word, cmds, handle }, in the order made
local FILE = rune.config_dir .. "/aliases.txt"

local function find(word)
  for i, a in ipairs(list) do
    if a.word == word then return i end
  end
end

-- cmds with what was typed after the word
local function expand(cmds, args)
  args = util.trim(args or "")
  if not cmds:find("%%%d") then
    return args ~= "" and (cmds .. " " .. args) or cmds
  end
  local w = {}
  for word in args:gmatch("%S+") do w[#w + 1] = word end
  return (cmds:gsub("%%(%d)", function(n)
    n = tonumber(n)
    return n == 0 and args or w[n] or ""
  end))
end

-- Make (or replace) one; nil and why if the word is taken by the config
local function add(word, cmds)
  local i = find(word)
  if not i and rune.alias.get(word) then
    return nil, "\"" .. word .. "\" is an alias of the config already"
  end
  -- {key} filled before what's typed goes in (braces typed stay as typed)
  local h = rune.alias.exact(word, function(args)
    local filled = player.fill(cmds)
    if not filled then return end   -- it said which; nothing sent
    return expand(filled, args)
  end, { group = "alias" })
  local a = { word = word, cmds = cmds, handle = h }
  if i then list[i] = a else list[#list + 1] = a end   -- Rune replaced the old one (same word)
  return a
end

-- "<word> = <commands>": nil if it isn't that shape
local function split(text)
  local word, cmds = util.trim(text):match("^(%S+)%s+=%s+(.+)$")
  if not word then return nil end
  return word, util.trim(cmds)
end

-- The whole file, after each change (util.write_file: a .tmp renamed over it)
local function save()
  util.write_file(FILE, function(fh)
    for _, a in ipairs(list) do fh:write(a.word, " = ", a.cmds, "\n") end
  end, "[alias]")
end

-- Back at load (a start or a /reload) - after the config's own aliases
-- (init.lua loads this late), so a clash leaves the config's in place
do
  local fh = io.open(FILE, "r")
  if fh then
    local n = 0
    for line in fh:lines() do
      n = n + 1
      if not util.blank(line) then
        local word, cmds = split(line)
        local a, err
        if word then a, err = add(word, cmds) else err = "not <word> = <commands>" end
        if not a then warn("[alias] aliases.txt line " .. n .. " left out (" .. err .. "): " .. line) end
      end
    end
    fh:close()
  end
end

rune.command.add("alias", function(args)
  args = util.trim(args)
  if args == "" then
    if not list[1] then say("[alias] none - /alias <word> = <commands> makes one."); return end
    say("[alias] your aliases (/unalias <n> removes one):")
    for i, a in ipairs(list) do say(string.format("  %d. %s = %s", i, a.word, a.cmds)) end
    return
  end
  local word, cmds = split(args)
  if not word then
    warn("[alias] /alias <word> = <commands> (; between commands, %0 all typed after it, %1 %2 its words).")
    return
  end
  local replaced = find(word) ~= nil
  local a, err = add(word, cmds)
  if not a then warn("[alias] can't make it: " .. err .. "."); return end
  save()
  say("[alias] " .. (replaced and "replaced: " or "made: ") .. a.word .. " = " .. a.cmds)
end, "your own aliases, kept until /unalias: list them, or make one: /alias <word> = <commands> (; between, %0 all after it, %1 %2 its words)")

rune.command.add("unalias", function(args)
  args = util.trim(args)
  local i = tonumber(args) or find(args)
  local a = i and list[i]
  if not a then
    warn("[alias] /unalias: no alias " .. (args ~= "" and ("\"" .. args .. "\"") or "given") .. " of yours - /alias lists them.")
    return
  end
  a.handle:remove()
  table.remove(list, i)
  save()
  say("[alias] removed: " .. a.word .. " = " .. a.cmds)
end, "remove an alias made with /alias (only those): /unalias <n | word>")

return {}
