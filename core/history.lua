-- Command history across restarts. Rune keeps the last 10,000 commands
-- (Up/Down) and they survive a /reload, but not quitting Rune - there's no
-- history file. So it's kept in history.txt here: loaded at start (only
-- into an empty history - after a /reload it's still there), and written
-- once a minute when it changed, before a /reload and at a disconnect.
-- Rune has no hook for quitting, so at worst the last minute is lost.
-- One command a line, with \ and newlines escaped (a multi-line entry).
-- Everything you type, as plain text - git-ignored; the password isn't in
-- it (core/login.lua answers from .env, which isn't typed).

local util = require("core.util")

local FILE = rune.config_dir .. "/history.txt"
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

-- The history as it was last written: its size and last entry
local saved_n, saved_last
local function mark(h) saved_n, saved_last = #h, h[#h] end
mark(rune.history.get())

-- Written to a .tmp file, then renamed over history.txt
local function save()
  local h = rune.history.get()
  if #h == saved_n and h[#h] == saved_last then return end
  local tmp = FILE .. ".tmp"
  local fh, err = io.open(tmp, "w")
  if not fh then return util.err("[history] can't write " .. tmp .. ": " .. tostring(err)) end
  for i = math.max(1, #h - KEEP + 1), #h do fh:write(esc(h[i]), "\n") end
  fh:close()
  local ok, rerr = os.rename(tmp, FILE)
  if not ok then return util.err("[history] can't replace " .. FILE .. ": " .. tostring(rerr)) end
  mark(h)
end

rune.timer.every(60, save, { name = "history_save" })
rune.hooks.on("reloading", save, { name = "history_save_reload" })
rune.hooks.on("disconnected", save, { name = "history_save_disconnect" })
