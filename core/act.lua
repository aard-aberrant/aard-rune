-- /act: ad hoc triggers made at the keyboard (tt++'s #action). Slash
-- commands, as they're the client's, not the game's. Kept until /unact in
-- their own file, acts.txt in the config folder: one act a line, as typed
-- after /act ("^You feel less holy.$ = c humility"). Rewritten whole on
-- each /act or /unact; read at load, so a /reload or a restart brings
-- them back, and a hand edit takes effect at the next /reload. A line that
-- won't read (no " = ", a bad regex) is reported and left out - and so is
-- gone from the file at the next /act or /unact.
--   /act                          the list, numbered
--   /act <text> = <commands>      when a line holds <text>, send <commands>
--   /act ^<text> = <commands>     ... a line that starts with <text>
--   /act ^<text>$ = <commands>    ... a line that is exactly <text> (no
--                                 escaping; colors don't count, but a
--                                 trailing space the game sends does)
--   /act /<regex>/ = <commands>   ... a Go regex; %1 %2 are its captures
--   /unact <n | pattern>          remove one (its number in the list, or its
--                                 pattern as the list shows it)
-- <commands> go as if typed (rune.send): through aliases, split at ";".
-- A slash line reaches its command whole (Rune splits only game lines at
-- ";"), so:  /act You are hungry = get bread bag;eat bread
-- Only these: /unact looks in this file's own list, so it can't remove any
-- other trigger. The same pattern again replaces its commands.
-- Cost: each act is matched against every line while it exists - a few ns
-- for text, 15-115 ns for a regex (ARCHITECTURE.md, trigbench); none made,
-- nothing.

local util = require("core.util")
local say, warn = util.say, util.warn

local acts = {}   -- { kind, pattern, cmds, handle }, in the order made
local FILE = rune.config_dir .. "/acts.txt"
local seq = 0     -- trigger names act_1, act_2 ...

local function parse(spec)
  if #spec > 2 and spec:match("^/.+/$") then return "regex", spec:sub(2, -2) end
  if #spec > 2 and spec:match("^%^.+%$$") then return "exact", spec:sub(2, -2) end
  if #spec > 1 and spec:sub(1, 1) == "^" then return "starts", spec:sub(2) end
  return "contains", spec
end

local function label(a)
  if a.kind == "regex" then return "/" .. a.pattern .. "/" end
  if a.kind == "exact" then return "^" .. a.pattern .. "$" end
  if a.kind == "starts" then return "^" .. a.pattern end
  return a.pattern
end

local function find(kind, pattern)
  for i, a in ipairs(acts) do
    if a.kind == kind and a.pattern == pattern then return i end
  end
end

-- Make (or replace) one; nil and the error if Rune refuses it (a bad regex)
local function add(kind, pattern, cmds)
  seq = seq + 1
  local ok, h = pcall(rune.trigger[kind], pattern, cmds, { name = "act_" .. seq, group = "act" })
  if not ok then return nil, tostring(h) end
  local a = { kind = kind, pattern = pattern, cmds = cmds, handle = h }
  local i = find(kind, pattern)
  if i then
    acts[i].handle:remove()
    acts[i] = a
  else
    acts[#acts + 1] = a
  end
  return a
end

-- "<pattern> = <commands>" (what follows /act, or a line of the file):
-- the pattern's kind and text, and the commands; nil if there's no " = "
local function split(text)
  local spec, cmds = util.trim(text):match("^(.-)%s+=%s+(.+)$")
  if not spec or util.trim(spec) == "" then return nil end
  local kind, pattern = parse(util.trim(spec))
  return kind, pattern, util.trim(cmds)
end

-- The whole file, after each change (util.write_file: a .tmp renamed over it)
local function save()
  util.write_file(FILE, function(fh)
    for _, a in ipairs(acts) do fh:write(label(a), " = ", a.cmds, "\n") end
  end, "[act]")
end

-- Back at load (a start or a /reload)
do
  local fh = io.open(FILE, "r")
  if fh then
    local n = 0
    for line in fh:lines() do
      n = n + 1
      if not util.blank(line) then
        local kind, pattern, cmds = split(line)
        local a, err
        if kind then a, err = add(kind, pattern, cmds) else err = "no \" = \"" end
        if not a then warn("[act] acts.txt line " .. n .. " left out (" .. err .. "): " .. line) end
      end
    end
    fh:close()
  else
    -- Once: acts kept in rune.store (2026-11-09, before this file) move here
    local ok, list = pcall(rune.store.get, "acts")
    if ok and type(list) == "table" and list[1] then
      for _, s in ipairs(list) do add(s.kind, s.pattern, s.cmds) end
      save()
      rune.store.delete("acts")
    end
  end
end

rune.command.add("act", function(args)
  args = util.trim(args)
  if args == "" then
    if not acts[1] then say("[act] none - /act <text> = <commands> makes one."); return end
    say("[act] ad hoc triggers (/unact <n> removes one):")
    for i, a in ipairs(acts) do say(string.format("  %d. %s = %s", i, label(a), a.cmds)) end
    return
  end
  local kind, pattern, cmds = split(args)
  if not kind then
    warn("[act] /act <text> = <commands> (^<text> for a line's start, ^<text>$ for the whole line, /<regex>/ for a regex).")
    return
  end
  local replaced = find(kind, pattern) ~= nil
  local a, err = add(kind, pattern, cmds)
  if not a then warn("[act] can't make it: " .. err); return end
  save()
  say("[act] " .. (replaced and "replaced: " or "made: ") .. label(a) .. " = " .. a.cmds)
end, "ad hoc triggers, kept until /unact: list them, or make one: /act <text | ^start | ^line$ | /regex/> = <commands> (%1 for a regex capture)")

rune.command.add("unact", function(args)
  args = util.trim(args)
  local i = tonumber(args)
  if not i then
    for k, a in ipairs(acts) do
      if label(a) == args then i = k; break end
    end
  end
  local a = i and acts[i]
  if not a then
    warn("[act] /unact: no act " .. (args ~= "" and ("\"" .. args .. "\"") or "given") .. " - /act lists them.")
    return
  end
  a.handle:remove()
  table.remove(acts, i)
  save()
  say("[act] removed: " .. label(a) .. " = " .. a.cmds)
end, "remove an ad hoc trigger made with /act (only those): /unact <n | pattern>")
