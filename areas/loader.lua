-- Area scripts (tt++ modules/areas.tin): areas/<zone>.lua exists only while
-- you're in that GMCP zone - read when you enter it, removed when you leave.
-- So an area's triggers and aliases cost nothing elsewhere, and can't take
-- a line from anything else there. No list to keep: the file's name is the
-- zone's (areas/geniewish.lua for zone geniewish).
-- A script is a chunk that gets one argument, A - the same calls as rune.*,
-- every one recorded so leaving the zone removes it:
--   A.trigger.regex/exact/starts/contains, A.alias.exact/regex,
--   A.timer.after/every, A.gmcp.on, A.hooks.on
--   A.on_unload(fn)  fn() just before the script goes (stop things, give
--                    up the info pane)
--   A.keep()         from an on_unload fn: stay until the next zone change
--                    (in the middle of something that leaves and comes back)
--   A.zone           the zone
-- An area alias may not reuse a name that exists outside it: Rune keys
-- aliases by name, so it would replace that one, and removing it would
-- delete it. Such a name is refused with a warning.
-- A command that has to work from elsewhere ("bcc find") goes in an
-- always-loaded module instead.
--   areascripts   the scripts there are, and which one is loaded
-- Requires core only; area scripts require whatever they use.
local util = require("core.util")
local game = require("core.game")   -- the zone you're in

local say, warn = util.say, util.warn

local DIR = rune.config_dir .. "/areas/"
local loaded      -- { zone, handles, unload, keep } or nil

local function exists(zone)
  if not zone:match("^[%w_-]+$") or zone == "loader" then return false end
  local f = io.open(DIR .. zone .. ".lua", "r")
  if f then f:close(); return true end
  return false
end

local function context(rec)
  local function wrap(lib, fname, check)
    return function(...)
      if check then
        local ok, why = check(...)
        if not ok then warn("[areas] " .. rec.zone .. ": " .. why); return nil end
      end
      local h = rune[lib][fname](...)
      if h then rec.handles[#rec.handles + 1] = h end
      return h
    end
  end
  local function alias_free(name)
    if rune.alias.get(name) then return false, "alias \"" .. name .. "\" exists outside the area - not added." end
    return true
  end
  return {
    zone = rec.zone,
    trigger = { regex = wrap("trigger", "regex"), exact = wrap("trigger", "exact"),
                starts = wrap("trigger", "starts"), contains = wrap("trigger", "contains") },
    alias = { exact = wrap("alias", "exact", alias_free), regex = wrap("alias", "regex") },
    timer = { after = wrap("timer", "after"), every = wrap("timer", "every") },
    gmcp = { on = wrap("gmcp", "on") },
    hooks = { on = wrap("hooks", "on") },
    on_unload = function(fn) rec.unload[#rec.unload + 1] = fn end,
    keep = function() rec.keep = true end,
  }
end

-- Removes the loaded script; false if it asked to stay
local function unload(force)
  local rec = loaded
  if not rec then return true end
  rec.keep = false
  for _, fn in ipairs(rec.unload) do
    local ok, e = pcall(fn)
    if not ok then util.err("[areas] " .. rec.zone .. " unload: " .. tostring(e)) end
  end
  if rec.keep and not force then return false end
  for _, h in ipairs(rec.handles) do pcall(h.remove, h) end
  loaded = nil
  say("[areas] removed " .. rec.zone)
  return true
end

local function load(zone)
  local chunk, e = loadfile(DIR .. zone .. ".lua")
  if not chunk then return util.err("[areas] can't load " .. zone .. ": " .. tostring(e)) end
  local rec = { zone = zone, handles = {}, unload = {} }
  loaded = rec
  local ok, err = pcall(chunk, context(rec))
  if not ok then
    util.err("[areas] " .. zone .. ": " .. tostring(err))
    unload(true)
    return
  end
  say("[areas] loaded " .. zone)
end

rune.gmcp.on("room.info", function()
  local zone = game.room.zone
  if zone == "" then return end
  if loaded and loaded.zone == zone then return end
  if loaded and not unload() then return end
  if exists(zone) then load(zone) end
end, { name = "areas_zone" })

rune.alias.exact("areascripts", function()
  local names = {}
  local ok, p = pcall(io.popen, 'ls "' .. DIR .. '" 2>/dev/null')
  if not ok or not p then return warn("[areas] can't list " .. DIR .. " here.") end
  for line in p:lines() do
    local z = line:match("^(.+)%.lua$")
    if z and z ~= "loader" then names[#names + 1] = z end
  end
  p:close()
  say("[areas] scripts (loaded only inside their zone): "
    .. (#names > 0 and table.concat(names, ", ") or "none")
    .. (loaded and (" - loaded: " .. loaded.zone) or ""))
end)
