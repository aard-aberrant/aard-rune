-- Command history across restarts. Rune keeps the last 10,000 commands
-- (Up/Down) and they survive a /reload, but not quitting Rune - there's no
-- history file. So it's kept in history.log in util.state_dir
-- (~/.local/state/rune; until 2026-11-08 history.txt in the config
-- folder). The folder isn't made: missing, each save is an error. Loaded
-- at start (only into an
-- empty history - after a /reload it's still there). Once a minute the
-- lines typed since are appended; before a /reload and at a disconnect the
-- whole file is rewritten from Rune's history. Rune has no hook for
-- quitting, so at worst the last minute is lost.
-- One command a line, with \ and newlines escaped (a multi-line entry).
-- Everything you type, as plain text - outside the repo; the password isn't in
-- it (core/login.lua answers from .env, which isn't typed).

local util = require("core.util")

local FILE = util.state_dir .. "/history.log"
local KEEP = 10000   -- Rune's own limit

local function esc(s) return (s:gsub("\\", "\\\\"):gsub("\n", "\\n")) end
local function unesc(s)
  return (s:gsub("\\(.)", function(c) return c == "n" and "\n" or c end))
end

-- (a read error mustn't stop init.lua: everything after this file would be missing)
local lines_in_file = 0
if #rune.history.get() == 0 then
  local fh = io.open(FILE, "r")
  if fh then
    local ok, err = pcall(function()
      for l in fh:lines() do
        if l ~= "" then rune.history.add(unesc(l)); lines_in_file = lines_in_file + 1 end
      end
    end)
    fh:close()
    if not ok then util.err("[history] can't read " .. FILE .. ": " .. tostring(err)) end
  end
end

-- The lines typed since the last write, from Rune's input hook (each line
-- as it runs, after history expansion). The minute's save appends them, so
-- it never copies the whole history out of Go: that copy and a rewrite of
-- 10,000 lines cost ~56 ms live (/profile, 2026-11-10); an append, well
-- under 1 ms. The full rewrite, from Rune's own history, comes before a
-- /reload and at a disconnect, and puts right the small ways the appended
-- lines can differ from it: a multi-line submission is one entry in Rune
-- and separate lines here; a repeat Rune doesn't keep, or a line another
-- hook drops, is here (Rune drops a repeat again on load)
local pending = {}
local dirty = false   -- typed since the last full rewrite
-- A file grown past KEEP (appends with no /reload or disconnect between
-- runs): the first save rewrites it
local trim = lines_in_file > KEEP
rune.hooks.on("input", function(text)
  if type(text) == "string" then
    pending[#pending + 1] = esc(text)
    dirty = true
  end
end, { name = "history_typed" })

local function rewrite()
  if not dirty and not trim then return end
  local h = rune.history.get()
  if util.write_file(FILE, function(fh)
    for i = math.max(1, #h - KEEP + 1), #h do fh:write(esc(h[i]), "\n") end
  end, "[history]") then
    pending, dirty, trim = {}, false, false
  end
end

local function append()
  if trim then rewrite(); return end
  if not pending[1] then return end
  if util.append_log("history.log", table.concat(pending, "\n"), "[history]") then pending = {} end
end

rune.timer.every(60, append, { name = "history_save" })
rune.hooks.on("reloading", rewrite, { name = "history_save_reload" })
rune.hooks.on("disconnected", rewrite, { name = "history_save_disconnect" })
