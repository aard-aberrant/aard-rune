-- Rune's /log, wrapped (require("modules.log")): where its files go, the
-- path copied at the end, and log.open published (REC on the status bar).
--
-- /log's files (Rune's /log start [raw] [file]): in util.state_dir's
-- userlogs/ (~/.local/state/rune/userlogs), not Rune's config_dir/logs.
-- The path is taken as if userlogs/ were the root (a chroot): "/tmp/x"
-- and "tmp/x" both give userlogs/tmp/x.log, "~/y" userlogs/y.log, and ".."
-- goes up only as far as userlogs/ ("../../etc/passwd" is
-- userlogs/etc/passwd.log). "\\" splits as "/" does; leading dots go from
-- every part (no hidden files). No name left: <date>_<time>.log; .log
-- added if the name has no extension; says whether the file is new or
-- being appended to (Rune opens it to append). The folder must exist - Rune's Go
-- side would make it, so a missing one is refused here first, an error
-- /log shows. Rune's /log calls rune.log.start, so wrapping it covers both.
-- At /log stop, the file's path goes to the clipboard (the user,
-- 2026-11-11), to paste where it's wanted.
local util = require("lib.util")
local view = require("ui.view")

local LOG = view.provides("rune.log", "Rune's /log", {
  ["log.open"] = { "boolean", "a /log file is open" },
})
LOG.set("log.open", rune.log.status() ~= nil)

local log_start = rune.log.start
function rune.log.start(path, opts)
  local parts = {}
  for part in tostring(path or ""):gmatch("[^/\\]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif not (part == "~" and #parts == 0) then
      local p = part:gsub("^%.+", "")
      if p ~= "" then parts[#parts + 1] = p end
    end
  end
  if #parts == 0 then parts[1] = os.date("%Y-%m-%d_%H-%M-%S") end
  if not parts[#parts]:find(".", 1, true) then parts[#parts] = parts[#parts] .. ".log" end
  local rel = table.concat(parts, "/")   -- what the message shows: the path under userlogs/
  local file = table.remove(parts)
  local dir = util.state_dir .. "/userlogs" .. (parts[1] and ("/" .. table.concat(parts, "/")) or "")
  if not util.dir_exists(dir) then return nil, dir .. " doesn't exist - make it first (mkdir -p)." end
  local path = dir .. "/" .. file
  local fh = io.open(path, "r")
  if fh then fh:close() end
  local ok, err = log_start(path, opts)
  if ok then LOG.set("log.open", true); LOG.publish() end
  if ok then util.say("[log] " .. (fh and "appending to the existing " or "new file ") .. "userlogs/" .. rel .. ".") end
  return ok, err
end

-- rune.log.stop is what /log stop calls, so wrapping it covers it
local log_stop = rune.log.stop
function rune.log.stop()
  local path = rune.log.status()
  local ok = log_stop()
  if ok then LOG.set("log.open", rune.log.status() ~= nil); LOG.publish() end
  if ok and path then
    rune.clipboard.set(path)
    util.say("[log] path copied to the clipboard.")
  end
  return ok
end

return {}
