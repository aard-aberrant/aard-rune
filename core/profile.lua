-- Profiling (2026-11-10): how long each trigger, GMCP handler, timer, hook,
-- bar, alias and command takes, to compare a feature before and after a
-- change. A slash command - a client tool, nothing to do with the game.
--   /profile on [label]        clear the counters and start (stays on across /reload; the counters don't)
--   /profile off               stop; the counters stay for report and save
--   /profile [report] [n] [text]   the top n (20) by self time, only names holding text
--   /profile save <name>       profile-<name>.tsv in util.state_dir (~/.local/state/rune)
--   /profile compare <a> [b] [n|all]   saved run a against b, or against the one under way;
--                              the n (30) largest changes, or all
--   /profile list              the saved runs
--   /profile startup           /reload, timing each require in init.lua (the map load too)
-- Workflow: /profile on, a set activity, /profile save before; the change,
-- /reload; /profile on, the same activity, /profile save after; /profile
-- compare before after. Compare means and ms a second, not totals -
-- live play varies. tools/trigbench stays the offline check of pattern cost.
--
-- How: every callback Rune runs - trigger, span, GMCP, timer, hook, bar,
-- alias, command, bind - goes through rune.guarded_call(label, data, fn, ...)
-- (Rune's lua/core/00_init.lua), which Rune's core looks up as a field at
-- each call. On puts `timed` in that field, off puts Rune's own function
-- back: off costs nothing, and no module changes. Self time leaves out
-- callbacks run inside (an alias a trigger sends); "Hook output" from
-- Rune's 50_triggers.lua is the per-line trigger pass (matcher + dispatch).
-- Clock: rune.clock if a patched Rune has it, else os.clock (process CPU
-- time, the TUI's threads too - fine for means, noisy for one call). The
-- wrapper's own cost is measured at on and taken off every figure.
-- Not split: tags.on handlers (inside the one tags_lines trigger), the
-- status bar's segments (Bar "status1"/"status2"), unnamed timers (by where
-- they were made - util.slot's all show as core/util.lua).
-- Cost: off, none per line or callback; on, two clock calls and a few
-- table writes per callback.
local util = require("core.util")
local theme = require("core.theme")
local layout = require("core.layout")   -- the main pane's width

local M = {}
local say, warn = util.say, util.warn
local ON_KEY, START_KEY = "profile_on", "profile_startup"   -- rune.session
local orig = rune.guarded_call
local clock = rune.clock or os.clock
local clock_name = rune.clock and "rune.clock" or "os.clock"

local stats = {}        -- registry entry (data) -> { label, calls, self, incl, max }
local depth, child = 0, {}
local running, started, stopped, label_txt = false, nil, nil, nil
local bias = 0          -- the wrapper's own seconds per call, taken off at report
local startup = nil     -- { { name, secs } ... } after /profile startup

local function timed(label, data, fn, ...)
  depth = depth + 1
  child[depth] = 0
  local t0 = clock()
  local ok, res = orig(label, data, fn, ...)
  local dt = clock() - t0
  local self = dt - child[depth]
  depth = depth - 1
  if depth > 0 then child[depth] = child[depth] + dt end
  local s = stats[data]
  if not s then
    s = { label = label, calls = 0, self = 0, incl = 0, max = 0 }
    stats[data] = s
  end
  s.calls, s.self, s.incl = s.calls + 1, s.self + self, s.incl + dt
  if self > s.max then s.max = self end
  return ok, res
end

-- The wrapper's self time around an empty callback: its bias per call.
-- The fastest of 5 batches - one batch varied 0.5-2 µs (tested 2026-11-10)
local function calibrate()
  local noop = function() end
  bias = math.huge
  for _ = 1, 5 do
    local data = {}
    for _ = 1, 1000 do timed("calibrate", data, noop) end
    bias = math.min(bias, stats[data].self / 1000)
    stats[data] = nil
  end
end

local function start(label)
  -- `child` stays: on while on, this command is a timed frame still open
  -- (each frame sets its own entry as it starts)
  stats = {}
  if not running then depth = 0 end
  rune.guarded_call = timed
  running, started, stopped, label_txt = true, os.time(), nil, label
  calibrate()
  rune.session.set(ON_KEY, label or "1")
end

local function stop()
  rune.guarded_call = orig
  running, stopped = false, os.time()
  rune.session.set(ON_KEY, "")
end

-- Rows --------------------------------------------------------------------

-- 'Trigger "dps_hit" @/home/x/.config/rune/fight/dps.lua:67' -> kind, name
local CFG = rune.config_dir .. "/"
local function split_label(label, data)
  if type(label) == "function" then
    local ok, s = pcall(label, data)
    label = ok and s or "?"
  end
  label = tostring(label)
  local at = label:find(" @" .. CFG, 1, true)   -- a plain find: the path has pattern characters
  if at then label = label:sub(1, at + 1) .. label:sub(at + 2 + #CFG) end
  label = label:gsub("%.lua:(%d+)", ":%1")   -- @fight/dps:67 - room for the name
  local kind, name = label:match("^(%S+)%s*(.*)$")
  return kind or "?", (name ~= "" and name or "-")
end

-- name without a source line, so a compare still matches after an edit (and
-- without .lua, which runs saved before 2026-11-10 have)
local function key_of(kind, name)
  return kind .. "\t" .. (name:gsub("%.lua:", ":"):gsub("(@%S-):%d+", "%1"))
end

-- Columns: a row fits the main pane (layout.RIGHT_W); the name gets what
-- the others leave
local function name_w(others) return math.max(layout.RIGHT_W - others, 30) end

-- Every row: { kind, name, key, calls, self, incl, max } (seconds, bias off).
-- One row per name: a trigger added again (util.group's, as you walk) is a
-- new registry entry each time, under the same name
local function rows()
  local out, by_key = {}, {}
  for data, s in pairs(stats) do
    local kind, name = split_label(s.label, data)
    if not (kind == "Command" and name:find('^"/profile"')) then
      local key = key_of(kind, name)
      local r = by_key[key]
      if not r then
        r = { kind = kind, name = name, key = key, calls = 0, self = 0, incl = 0, max = 0 }
        by_key[key] = r
        out[#out + 1] = r
      end
      r.calls = r.calls + s.calls
      r.self = r.self + math.max(0, s.self - bias * s.calls)
      r.incl = r.incl + math.max(0, s.incl - bias * s.calls)
      r.max = math.max(r.max, s.max - bias)
    end
  end
  table.sort(out, function(a, b) return a.self > b.self end)
  return out
end

-- Lines (Rune's trigger pass), GMCP messages (the gmcp hook core/debug.lua
-- keeps), bar passes (the most-called bar), and the total self time
local function totals(list)
  local t = { lines = 0, gmcp = 0, bars = 0, self = 0 }
  for _, r in ipairs(list) do
    t.self = t.self + r.self
    if r.kind == "Hook" and r.name:find("^output") and r.name:find("50_triggers") then t.lines = r.calls end
    if r.kind == "Hook" and r.name:find('^gmcp "debug_gmcp"') then t.gmcp = r.calls end
    if r.kind == "Bar" and r.calls > t.bars then t.bars = r.calls end
  end
  return t
end

-- Triggers by kind and on/off, timers, hooks, GMCP handlers - for compare
local function static()
  local s = {}
  local ok, list = pcall(rune.trigger.list)
  for _, t in ipairs(ok and list or {}) do
    local k = "trig_" .. tostring(t.mode) .. (t.enabled and "" or "_off")
    s[k] = (s[k] or 0) + 1
  end
  -- (not timers: one-off ones come and go, so their count is noise)
  for _, n in ipairs({ "hooks", "gmcp" }) do
    local ok2, l = pcall(rune[n].list)
    s[n] = ok2 and type(l) == "table" and #l or nil
  end
  return s
end

local function us(secs) return secs * 1e6 end
local function secs_run() return (stopped or os.time()) - (started or os.time()) end

-- Report ------------------------------------------------------------------

local function report(n, filter)
  if not started then say("[profile] nothing yet - /profile on to start."); return end
  local list, t = rows(), nil
  t = totals(list)
  local d = secs_run()
  say(string.format("[profile] %s%s, %d:%02d, %s (wrapper %.1f µs/call taken off)",
    running and "running" or "stopped", label_txt and (" \"" .. label_txt .. "\"") or "",
    math.floor(d / 60), d % 60, clock_name, us(bias)))
  rune.echo(theme.muted(string.format("  %d lines  %d GMCP  %d bar passes  Lua %.1f ms a second (%.1f%% of a core)",
    t.lines, t.gmcp, t.bars, d > 0 and t.self * 1000 / d or 0, d > 0 and 100 * t.self / d or 0)))
  -- (a header with µs is a byte wider than it shows: its %s is one more)
  local w = name_w(53)
  rune.echo(theme.heading(string.format("  %-7s %-" .. w .. "s %7s %8s %10s %10s %5s",
    "kind", "name", "calls", "total ms", "mean µs", "max µs", "%")))
  local shown = 0
  filter = filter and filter:lower()
  for _, r in ipairs(list) do
    if shown >= n then break end
    if not filter or (r.kind .. " " .. r.name):lower():find(filter, 1, true) then
      shown = shown + 1
      rune.echo(string.format("  %-7s %-" .. w .. "s %7d %8.1f %9.1f %9.1f %5.1f", r.kind,
        r.name:sub(1, w), r.calls, r.self * 1000, us(r.self) / r.calls, us(r.max),
        t.self > 0 and 100 * r.self / t.self or 0))
    end
  end
  if shown == 0 then rune.echo(theme.muted("  (nothing" .. (filter and (" matching \"" .. filter .. "\"") or "") .. ")")) end
  if startup then
    rune.echo(theme.heading("  startup (/profile startup): require, ms"))
    for _, s in ipairs(startup) do rune.echo(string.format("  %-40s %9.1f", s[1], s[2] * 1000)) end
  end
end

-- Save, load, list ----------------------------------------------------------

local function file_of(name) return util.state_dir .. "/profile-" .. name .. ".tsv" end

local function save(name)
  if not name:match("^[%w_%-]+$") then warn("[profile] save <name> - letters, digits, _ and - only."); return end
  if not started then warn("[profile] nothing to save - /profile on first."); return end
  local list, st = rows(), static()
  local t = totals(list)
  local ok = util.write_file(file_of(name), function(fh)
    fh:write(string.format("#\tprofile\t%s\t%s\t%d\t%s\t%d\t%d\t%d\t%.9f\n", name,
      os.date("%Y-%m-%d %H:%M", started), secs_run(), clock_name, t.lines, t.gmcp, t.bars, bias))
    local keys = {}
    for k in pairs(st) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do fh:write("#\tstatic\t", k, "\t", tostring(st[k]), "\n") end
    for _, r in ipairs(list) do
      fh:write(string.format("%s\t%s\t%d\t%.9f\t%.9f\t%.9f\n", r.kind, r.name, r.calls, r.self, r.incl, r.max))
    end
  end, "[profile]")
  if ok then say("[profile] saved " .. file_of(name) .. " (" .. #list .. " rows).") end
end

-- A saved run: { meta = { date, secs, clock, lines, gmcp, bars }, static = {}, rows = { key -> row } }
local function load(name)
  local fh = io.open(file_of(name), "r")
  if not fh then return nil end
  local run = { static = {}, rows = {}, list = {} }
  for line in fh:lines() do
    local f = {}
    for v in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = v end
    if f[1] == "#" and f[2] == "profile" then
      run.meta = { date = f[4], secs = tonumber(f[5]), clock = f[6], lines = tonumber(f[7]) or 0,
                   gmcp = tonumber(f[8]) or 0, bars = tonumber(f[9]) or 0 }
    elseif f[1] == "#" and f[2] == "static" then
      run.static[f[3]] = tonumber(f[4])
    elseif f[1] ~= "#" and #f >= 6 then
      local key = key_of(f[1], f[2])
      local r = run.rows[key]
      if r then   -- two unnamed ones from the same file: one row
        r.calls, r.self = r.calls + tonumber(f[3]), r.self + tonumber(f[4])
      else
        r = { kind = f[1], name = f[2], calls = tonumber(f[3]), self = tonumber(f[4]) }
        run.rows[key] = r
        run.list[#run.list + 1] = r
      end
    end
  end
  fh:close()
  return run.meta and run or nil
end

-- The run under way, in load()'s shape
local function live()
  if not started then return nil end
  local list = rows()
  local t = totals(list)
  local run = { static = static(), rows = {}, list = {},
    meta = { date = os.date("%Y-%m-%d %H:%M", started), secs = secs_run(), clock = clock_name,
             lines = t.lines, gmcp = t.gmcp, bars = t.bars } }
  for _, r in ipairs(list) do
    local x = run.rows[r.key]
    if x then x.calls, x.self = x.calls + r.calls, x.self + r.self
    else
      x = { kind = r.kind, name = r.name, calls = r.calls, self = r.self }
      run.rows[r.key] = x
      run.list[#run.list + 1] = x
    end
  end
  return run
end

local function list_saved()
  local ok, p = pcall(io.popen, 'ls "' .. util.state_dir .. '" 2>/dev/null')
  local names = {}
  if ok and p then
    for f in p:lines() do
      local n = f:match("^profile%-([%w_%-]+)%.tsv$")
      if n then names[#names + 1] = n end
    end
    p:close()
  end
  if not names[1] then say("[profile] no saved runs in " .. util.state_dir .. "."); return end
  say("[profile] saved runs (" .. util.state_dir .. "):")
  for _, n in ipairs(names) do
    local r = load(n)
    local m = r and r.meta
    rune.echo(string.format("  %-20s %s", n, m and string.format("%s  %d:%02d  %d lines  %s",
      m.date, math.floor((m.secs or 0) / 60), (m.secs or 0) % 60, m.lines, m.clock) or theme.muted("(unreadable)")))
  end
end

-- Compare -------------------------------------------------------------------
-- Means side by side, the largest change in µs first. No flags: the
-- figures are shown and you judge them (+270% from 1 to 3.7 µs is noise)

local function compare(a, b, n)
  local A = load(a)
  if not A then warn("[profile] no saved run \"" .. a .. "\" - /profile list."); return end
  local B = b and load(b) or (not b and live())
  if not B then
    warn("[profile] " .. (b and ("no saved run \"" .. b .. "\"") or "nothing running to compare with") .. ".")
    return
  end
  local bname = b or "now"
  say(string.format("[profile] %s (%s, %d lines) -> %s (%s, %d lines)", a, A.meta.date, A.meta.lines,
    bname, B.meta.date, B.meta.lines))
  if A.meta.clock ~= B.meta.clock then warn("[profile] different clocks: " .. A.meta.clock .. " vs " .. B.meta.clock) end
  -- All Lua time over the run's length: ms a second
  local function per_sec(run)
    local tot = 0
    for _, r in ipairs(run.list) do tot = tot + r.self end
    local secs = run.meta.secs
    return secs and secs > 0 and tot * 1000 / secs or nil
  end
  local la, lb = per_sec(A), per_sec(B)
  if la and lb then
    rune.echo(theme.muted(string.format("  Lua a second: %.1f -> %.1f ms (%+.1f ms)", la, lb, lb - la)))
  end
  local w = name_w(60)
  -- n: the calls each mean comes from - a mean of 2 calls is a rough one
  rune.echo(theme.heading(string.format("  %-7s %-" .. w .. "s %10s %5s %10s %5s %11s %8s",
    "kind", "name", "before µs", "n", "after µs", "n", "Δ µs", "Δ")))
  local function mean(r) return us(r.self) / math.max(1, r.calls) end
  local out = {}
  for key, rb in pairs(B.rows) do
    local ra = A.rows[key]
    out[#out + 1] = { r = rb, ma = ra and mean(ra), mb = mean(rb), na = ra and ra.calls, nb = rb.calls }
  end
  for key, ra in pairs(A.rows) do
    if not B.rows[key] then out[#out + 1] = { r = ra, ma = mean(ra), na = ra.calls } end
  end
  for _, o in ipairs(out) do o.d = (o.mb or 0) - (o.ma or 0) end
  table.sort(out, function(x, y) return math.abs(x.d) > math.abs(y.d) end)
  local f = "  %-7s %-" .. w .. "s"
  local function cnt(c)   -- 5 columns at most
    if c < 100000 then return tostring(c) end
    return c < 1e7 and (math.floor(c / 1000) .. "k") or (math.floor(c / 1e6) .. "M")
  end
  for i, o in ipairs(out) do
    if n and i > n then
      rune.echo(theme.muted(string.format("  (%d more - /profile compare %s%s all)", #out - n, a, b and (" " .. b) or "")))
      break
    end
    local name = o.r.name:sub(1, w)
    if not o.mb then   -- gone / new: not called in that run
      rune.echo(theme.muted(string.format(f .. " %9.1f %5s %9s %5s %+9.1f", o.r.kind, name, o.ma, cnt(o.na), "gone", "", o.d)))
    elseif not o.ma then
      rune.echo(string.format(f .. " %9s %5s %9.1f %5s %+9.1f", o.r.kind, name, "new", "", o.mb, cnt(o.nb), o.d))
    else
      local pct = o.ma > 0 and 100 * o.d / o.ma or 0
      rune.echo(string.format(f .. " %9.1f %5s %9.1f %5s %+9.1f %+6.0f%%", o.r.kind, name, o.ma, cnt(o.na), o.mb, cnt(o.nb), o.d, pct))
    end
  end
  local diffs = {}
  for _, k in ipairs((function()
    local ks, kseen = {}, {}
    for k in pairs(A.static) do ks[#ks + 1] = k; kseen[k] = true end
    for k in pairs(B.static) do if not kseen[k] then ks[#ks + 1] = k end end
    table.sort(ks)
    return ks
  end)()) do
    local x, y = A.static[k] or 0, B.static[k] or 0
    -- (not timers: runs saved before 2026-11-10 count them)
    if x ~= y and k ~= "timer" then diffs[#diffs + 1] = string.format("%s %+d", k, y - x) end
  end
  if diffs[1] then rune.echo(theme.muted("  registered: " .. table.concat(diffs, ", "))) end
end

-- Startup timing (/profile startup) ----------------------------------------
-- init.lua calls M.startup_begin() before its requires and M.startup_end()
-- after them; both do nothing unless /profile startup set the flag

local real_require
function M.startup_begin()
  if rune.session.get(START_KEY) ~= "1" then return end
  rune.session.set(START_KEY, "")
  startup, real_require = {}, require
  local t_all = clock()
  local d, kids = 0, {}
  require = function(name)   -- the global, put back in startup_end
    if package.loaded[name] then return real_require(name) end
    d = d + 1
    kids[d] = 0
    local t0 = clock()
    local r = real_require(name)
    local dt = clock() - t0
    startup[#startup + 1] = { name, dt - kids[d] }
    d = d - 1
    if d > 0 then kids[d] = kids[d] + dt end
    return r
  end
  M._t_all = t_all
end

function M.startup_end()
  if not real_require then return end
  require = real_require
  real_require = nil
  table.sort(startup, function(a, b) return a[2] > b[2] end)
  table.insert(startup, 1, { "(all of init.lua's requires)", clock() - M._t_all })
  say(string.format("[profile] startup: %.0f ms - /profile shows each require.", startup[1][2] * 1000))
  if not started then started, stopped = os.time(), os.time() end
end

-- Command ---------------------------------------------------------------------

rune.command.add("profile", function(args)
  local sub, rest = util.trim(args):match("^(%S*)%s*(.-)$")
  if sub == "on" then
    start(rest ~= "" and rest or nil)
    say("[profile] on" .. (rest ~= "" and (" \"" .. rest .. "\"") or "") .. string.format(
      " - %s, wrapper %.1f µs/call. /profile to see, /profile off to stop.", clock_name, us(bias)))
  elseif sub == "off" then
    if not running then say("[profile] already off."); return end
    stop()
    say("[profile] off - /profile to see, /profile save <name> to keep.")
  elseif sub == "" or sub == "report" or sub:match("^%d+$") then
    if sub:match("^%d+$") then rest = sub .. " " .. rest end   -- /profile 5 [text]
    local n, text = rest:match("^(%d*)%s*(.-)$")
    report(tonumber(n) or 20, text ~= "" and text or nil)
  elseif sub == "save" then
    save(rest)
  elseif sub == "compare" then
    local words = {}
    for w in rest:gmatch("%S+") do words[#words + 1] = w end
    local n = 30
    local last = words[#words]
    if #words > 1 and (last == "all" or last:match("^%d+$")) then
      n = tonumber(last)   -- nil: all
      table.remove(words)
    end
    if not words[1] or #words > 2 then
      warn("[profile] compare <a> [b] [n|all] - b left out: the run under way; n: the largest changes (30).")
      return
    end
    compare(words[1], words[2], n)
  elseif sub == "list" then
    list_saved()
  elseif sub == "startup" then
    rune.session.set(START_KEY, "1")
    say("[profile] reloading to time init.lua's requires...")
    rune.timer.after(0, rune.reload)   -- after this command, not inside it
  else
    warn("[profile] /profile on [label] | off | [report] [n] [text] | save <name> | compare <a> [b] [n|all] | list | startup")
  end
end, "time triggers, GMCP, timers, bars, aliases: on [label], off, report [n] [text], save <name>, compare <a> [b] [n|all], list, startup")

-- On before a /reload: on again (fresh counters)
local was = rune.session.get(ON_KEY)
if was and was ~= "" then start(was ~= "1" and was or nil) end

return M
