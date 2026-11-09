-- Helpers shared by every file (require("core.util")).

local util = {}

-- Messages: cyan for news, a muted amber for a problem (xterm-256 179,
-- #d7af5f - plain yellow was bright and jarring, the user 2026-11-08), red
-- for an error
function util.say(s) rune.echo(rune.style.cyan(s)) end
function util.warn(s) rune.echo("\27[38;5;179m" .. s .. "\27[0m") end
function util.err(s) rune.echo(rune.style.red(s)) end

-- Replace a pane's text - only when it differs from what was last put
-- there, so a redraw that changes nothing costs one string compare
local shown = {}
-- Triggers, from Rune's source (lua/core/50_triggers.lua, matcher.go) and
-- benchmarks of this config (2026-11-06): every registered trigger is
-- matched in Go against every line, DISABLED ONES TOO - enabled is checked
-- only after a match, and a line with any match at all goes through the Lua
-- dispatch (a line with none, and no open span, skips Lua). So no catch-all
-- stays registered: a block is a span (rune.trigger opts.span, e.g. the
-- minimap), and a reader exists only while it's needed (util.group,
-- util.await, util.eat_blanks below). A catch-all is starts("") (a regex
-- ".*" costs ~0.5 us more a line); a pattern that can't be anchored with a
-- literal start (^.+, (\w+) ..., an alternation) is contains/starts plus a
-- check in Lua - those ran 600-1300 ns a line, anchored ones 10-90. Adding
-- or removing a trigger rebuilds the matcher, so one toggled every round
-- (autocast's) stays registered, disabled.

function util.pane(name, text)
  if shown[name] == text then return end
  shown[name] = text
  rune.pane.replace(name, text)
end

-- The terminal bell. Straight to the terminal - rune.echo drops it (tried)
function util.beep() io.write("\7"); io.flush() end

-- Text without leading and trailing spaces ("" for nil)
function util.trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- Text without its colour codes. A few room names in the converted map carry
-- tt++'s escaped form ("\27[1\;32m"), so a backslash is allowed in the code
function util.strip(s) return (s:gsub("\27%[[%d;\\]*m", "")) end

-- Text without Aardwolf's colour codes (@x123, @R) - GMCP's names carry them
function util.uncolor(s) return (s:gsub("@x%d%d?%d?", ""):gsub("@.", "")) end

-- Nothing but spaces
function util.blank(s) return s:match("^%s*$") ~= nil end

-- Write a file safely: write(fh) fills a .tmp file, which is then renamed
-- over `path`, so a failed write never leaves half a file. `who` starts the
-- error line ("[map]"). Returns true when written
-- Logs (dps.log, pup.log): one line appended per entry, in
-- $XDG_STATE_HOME/rune, else ~/.local/state/rune - logs aren't config, so
-- not in rune.config_dir. The folder isn't made: a missing one is an error
-- (make it by hand: mkdir -p ~/.local/state/rune).
--   util.dir_exists(path)              true if path is an existing folder
--   util.append_log(name, line, who)   true if written
--   util.log_tail(name, n)             the last n lines, newest first ({} if none)
util.state_dir = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or ".") .. "/.local/state")) .. "/rune"
-- "path/." opens only if path is a folder (Go's os.Rename refuses a
-- folder onto itself, so the rename trick doesn't work under Rune)
function util.dir_exists(path)
  local fh = io.open(path .. "/.", "r")
  if fh then fh:close() end
  return fh ~= nil
end
function util.append_log(name, line, who)
  local path = util.state_dir .. "/" .. name
  if not util.dir_exists(util.state_dir) then
    util.err(who .. " can't log: " .. util.state_dir .. " doesn't exist (mkdir -p it).")
    return false
  end
  local fh, err = io.open(path, "a")
  if not fh then
    util.err(who .. " can't append to " .. path .. ": " .. tostring(err))
    return false
  end
  fh:write(line, "\n")
  fh:close()
  return true
end
function util.log_tail(name, n)
  local fh = io.open(util.state_dir .. "/" .. name, "r")
  if not fh then return {} end
  local ring, i = {}, 0
  for line in fh:lines() do
    if line ~= "" then i = i + 1; ring[(i - 1) % n + 1] = line end
  end
  fh:close()
  local out = {}
  for k = i, math.max(1, i - n + 1), -1 do out[#out + 1] = ring[(k - 1) % n + 1] end
  return out
end

function util.write_file(path, write, who)
  local tmp = path .. ".tmp"
  local fh, err = io.open(tmp, "w")
  if not fh then
    util.err(who .. " can't write " .. tmp .. ": " .. tostring(err))
    return false
  end
  write(fh)
  fh:close()
  local ok, rerr = os.rename(tmp, path)
  if not ok then util.err(who .. " can't replace " .. path .. ": " .. tostring(rerr)) end
  return ok == true
end

-- Half a line, hidden while something hides lines. When a packet ends
-- mid-line, Rune shows that half at once, as a temporary row at the foot of
-- the main pane, before any output trigger sees it (session.go: the partial
-- line goes to the prompt overlay, and only "prompt" triggers see it). The
-- whole line then replaces it - and if a hider hides that line, the row
-- comes and goes: the main pane jumps a row and back. So while any hider
-- is on, the half line isn't shown (it shows when complete, if it isn't
-- hidden - so a hider on too long only delays a half line, never loses it). A confirmed prompt (GA/EOR) is never touched. The prompt pass
-- sees only those half lines and prompts, never ordinary lines, so this one
-- stays registered. util.hider(fn): fn() is true while its owner hides lines
local hiders = {}
function util.hider(fn) hiders[#hiders + 1] = fn end
rune.trigger.starts("", function(_, ctx)
  if ctx.confirmed then return end
  for _, on in ipairs(hiders) do
    if on() then return false end
  end
end, { name = "util_hide_partial", on = "prompt" })

-- Triggers that exist only while on: declared once, added by set(true),
-- removed by set(false) - in place of enable/disable, since a disabled
-- trigger is still matched on every line, and any match at all (disabled
-- too) sends the line through Rune's Lua dispatch. Only for groups that are
-- off for long stretches: each add or remove rebuilds the matcher.
--   local g = util.group(hides)   hides: true for a group that hides lines
--   g.add(kind, pattern, fn, opts)   kind: regex, exact, starts, contains
--   g.set(on)    g.is_on()
function util.group(hides)
  local specs, live = {}, nil
  local g = {}
  local function make(s) return rune.trigger[s[1]](s[2], s[3], s[4]) end
  function g.add(kind, pattern, fn, opts)
    local s = { kind, pattern, fn, opts }
    specs[#specs + 1] = s
    if live then live[#live + 1] = make(s) end
  end
  function g.set(on)
    if on and not live then
      live = {}
      for i, s in ipairs(specs) do live[i] = make(s) end
    elseif not on and live then
      for _, t in ipairs(live) do t:remove() end
      live = nil
    end
  end
  function g.is_on() return live ~= nil end
  if hides then util.hider(g.is_on) end
  return g
end

-- Hide the blank line(s) the game sends after a line a trigger has just
-- hidden (tt++ ||gag_line). `clean` is that line's text, so the eater skips
-- it if it sees it (it can, when the eater was on already). Off again at
-- the first line that isn't blank. The eater exists only while it's eating
local eat_skip
local eater = util.group(true)
eater.add("starts", "", function(_, ctx)
  local clean = ctx.line:clean()
  if clean == eat_skip then eat_skip = nil; return end
  if util.blank(clean) then return false end
  eater.set(false)
end, { name = "util_eat_blanks", priority = 5 })
function util.eat_blanks(clean) eat_skip = clean; eater.set(true) end

-- A timer slot: start(secs, fn) cancels the slot's waiting timer (Rune's
-- timer handles) and starts a new one, stop() cancels it - in place of a
-- generation counter that every stale timer had to check
--   local t = util.slot()
--   t.start(secs, fn)    t.stop()    t.running()
function util.slot()
  local h
  local s = {}
  function s.start(secs, fn)
    if h then h:cancel() end
    local mine
    mine = rune.timer.after(secs, function()
      if h == mine then h = nil end
      fn()
    end)
    h = mine
  end
  function s.stop() if h then h:cancel(); h = nil end end
  function s.running() return h ~= nil end
  return s
end

-- A one-off reply: a rune.trigger[kind] (exact, starts, contains) on
-- pattern that exists only until its first match (Rune's once) or `secs`
-- (default 10) - for a reply to something just sent. fn(m, ctx) is the
-- trigger's function, its return value the trigger's. A second call with
-- the same name replaces a waiting one
local awaiting = {}   -- name -> { trigger, timer }
function util.await(kind, pattern, fn, name, secs)
  local old = awaiting[name]
  if old then old[1]:remove(); old[2]:cancel() end
  local w
  w = {
    rune.trigger[kind](pattern, function(m, ctx)
      if awaiting[name] == w then awaiting[name] = nil; w[2]:cancel() end
      return fn(m, ctx)
    end, { name = name, once = true }),
    rune.timer.after(secs or 10, function()
      if awaiting[name] == w then awaiting[name] = nil; w[1]:remove() end
    end),
  }
  awaiting[name] = w
end

-- Plain text word-wrapped to lines of at most w characters; a word longer
-- than w is cut
function util.wrap(text, w)
  local lines, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif #cur + 1 + #word <= w then
      cur = cur .. " " .. word
    else
      lines[#lines + 1] = cur
      cur = word
    end
    while #cur > w do
      lines[#lines + 1] = cur:sub(1, w)
      cur = cur:sub(w + 1)
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

-- A data file (a .lua file that returns a table), or nil after an error line
function util.load_data(path)
  local ok, t = pcall(dofile, path)
  if ok and type(t) == "table" then return t end
  util.err("can't load " .. path .. ": " .. tostring(t))
  return nil
end

-- A mob's likely keywords from its full name, best first, for where, k and
-- the like (tt++ campaign.tin). The article and small words go, commas too
-- ("a hatchling of the wyrm" -> "hatchling wyrm"); then come its leading
-- words from the first one up, then each later word alone from the last.
-- "big red dragon": big red dragon, big, big red, dragon, red. The game
-- only matches a mob's real keywords, so each is a guess - travel.probe
-- tries them with where until one names the mob
local STOP = { of = 1, the = 1, ["and"] = 1, ["in"] = 1, on = 1, at = 1, to = 1,
               ["for"] = 1, de = 1, la = 1, a = 1, as = 1 }

function util.mob_keywords(name)
  local words = {}
  for w in name:gsub(",", ""):gmatch("%S+") do words[#words + 1] = w end
  if words[1] and ({ a = 1, an = 1, the = 1 })[words[1]:lower()] and #words > 1 then
    table.remove(words, 1)
  end
  local kept = {}
  for i, w in ipairs(words) do
    if i == 1 or i == #words or not STOP[w:lower()] then kept[#kept + 1] = w end
  end
  local tries = { table.concat(kept, " ") }
  for n = 1, #kept - 1 do tries[#tries + 1] = table.concat(kept, " ", 1, n) end
  if #kept > 1 then
    for i = #kept, 2, -1 do tries[#tries + 1] = kept[i] end
  end
  return tries
end

return util
