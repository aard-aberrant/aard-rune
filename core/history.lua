-- Command history across restarts. Rune keeps the last 10,000 commands
-- (Up/Down) and they survive a /reload, but not quitting Rune - there's no
-- history file. So it's kept in history.log in util.state_dir
-- (~/.local/state/rune; until 2026-11-08 history.txt in the config
-- folder). The folder isn't made: missing, each save is an error. Loaded
-- at start (only into an
-- empty history - after a /reload it's still there), and written
-- once a minute when it changed, before a /reload and at a disconnect.
-- Rune has no hook for quitting, so at worst the last minute is lost.
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
if #rune.history.get() == 0 then
  local fh = io.open(FILE, "r")
  if fh then
    local ok, err = pcall(function()
      for l in fh:lines() do
        if l ~= "" then rune.history.add(unesc(l)) end
      end
    end)
    fh:close()
    if not ok then util.err("[history] can't read " .. FILE .. ": " .. tostring(err)) end
  end
end

-- Something typed since the last write: Rune's input hook sets it, so the
-- minute's check is a flag, not a copy of the whole history out of Go.
-- (A line typed that Rune doesn't keep - a repeat - only costs a write)
local typed = false
rune.hooks.on("input", function() typed = true end, { name = "history_typed" })

local function save()
  if not typed then return end
  local h = rune.history.get()
  if util.write_file(FILE, function(fh)
    for i = math.max(1, #h - KEEP + 1), #h do fh:write(esc(h[i]), "\n") end
  end, "[history]") then typed = false end
end

rune.timer.every(60, save, { name = "history_save" })
rune.hooks.on("reloading", save, { name = "history_save_reload" })
rune.hooks.on("disconnected", save, { name = "history_save_disconnect" })
