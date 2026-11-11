-- Debug topics (require("core.debug")): a module registers its own, and
-- one command switches them - a slash command, as it's the client's, not
-- the game's (a bare word until 2026-11-09).
--   /debug                  every topic: on or off, what it shows, its status
--   /debug <topic> [on|off] switch one (bare: toggle)
--   /debug <topic> <filter> a topic's filter, and on (/debug gmcp char.status)
--   /debug all off          all off
-- On stays on across /reload (rune.session), off when Rune quits. A topic
-- exists only while its module is loaded (a per-subclass one, nav/moons,
-- only on that subclass); one that's on stays on for when it loads.
-- In a module:
--   local dbg = require("core.debug").topic("recov",
--     "the {recon}/{recoff} recovery tags as they come", status_fn)
--   if dbg.on then dbg.log("...") end
-- status_fn (optional) returns a line shown under the topic in "debug".
-- A topic may set dbg.filter = function(text): then "debug <topic> <text>"
-- (anything but on/off) passes it the text and switches the topic on.
-- dbg.on is a plain field, so a check while off costs one table read; put
-- it in front of building the message, as above.
-- Output: gray, "15:40:12 [debug recov] ...".
local util = require("core.util")
local theme = require("core.theme")

local M = {}
local topics, order = {}, {}
local KEY = "debug_on"   -- rune.session: the topics on, comma-separated

local saved = {}
for name in (rune.session.get(KEY) or ""):gmatch("[^,]+") do saved[name] = true end

-- A topic whose module isn't loaded now (nav/moons on a Priest) keeps its
-- saved on, for when it loads again
local function save()
  local on = {}
  for _, name in ipairs(order) do if topics[name].on then on[#on + 1] = name end end
  for name in pairs(saved) do if not topics[name] then on[#on + 1] = name end end
  rune.session.set(KEY, table.concat(on, ","))
end

function M.topic(name, desc, status)
  local t = topics[name]
  if not t then
    t = { name = name, on = saved[name] == true }
    function t.log(msg)
      rune.echo(theme.muted(os.date("%H:%M:%S") .. " [debug " .. name .. "] " .. msg))
    end
    topics[name] = t
    order[#order + 1] = name
    table.sort(order)
  end
  t.desc, t.status = desc, status
  return t
end

-- A topic's status line (its status_fn), if it has one, under its entry
local function show_status(t, indent)
  if not t.status then return end
  local ok, s = pcall(t.status)
  if ok and s then rune.echo(theme.muted(indent .. s)) end
end

local function list()
  if not order[1] then util.say("[debug] no topics."); return end
  util.say("[debug] topics - /debug <topic> [on|off|filter], /debug all off:")
  for _, name in ipairs(order) do
    local t = topics[name]
    rune.echo(string.format("  %-8s %s  %s", name,
      t.on and theme.on("on ") or theme.off("off"), t.desc or ""))
    show_status(t, "           ")
  end
end

rune.command.add("debug", function(args)
  local name, arg = util.trim(args):match("^(%S*)%s*(.-)$")
  if name == "" then list(); return end
  if name == "all" then
    if arg ~= "off" then util.warn("[debug] /debug all off - one at a time to switch on."); return end
    for _, n in ipairs(order) do topics[n].on = false end
    saved = {}
    save()
    util.say("[debug] all off.")
    return
  end
  local t = topics[name]
  if not t then util.warn("[debug] no topic \"" .. name .. "\" - /debug lists them."); return end
  if arg == "on" then t.on = true elseif arg == "off" then t.on = false
  elseif arg == "" then t.on = not t.on
  elseif t.filter then t.filter(arg); t.on = true
  else util.warn("[debug] /debug " .. name .. " [on|off]"); return end
  save()
  util.say("[debug] " .. name .. " " .. (t.on and "on" or "off") .. ".")
  if t.on then show_status(t, "  ") end
end, "debug topics: list them, switch one (bare toggles), give one a filter (/debug gmcp char.status), or all off")

-- debug gmcp: every GMCP message as it comes, package and raw JSON (cut
-- at 300 characters), before any handler runs - so next to the game's
-- lines it shows which came first. Rune's catch-all "gmcp" hook; while
-- off, one table read per message.
--   /debug gmcp char.status room   only packages starting with one of these
--   /debug gmcp all                every package again
-- The filter stays across /reload (rune.session), as on does
local GMCP_KEY = "debug_gmcp_filter"
local gmcp_only = {}   -- lowercase package prefixes; empty: all
local function gmcp_set(text)
  gmcp_only = {}
  for w in text:lower():gmatch("%S+") do
    if w ~= "all" then gmcp_only[#gmcp_only + 1] = w end
  end
  rune.session.set(GMCP_KEY, table.concat(gmcp_only, " "))
end
gmcp_set(rune.session.get(GMCP_KEY) or "")
local gmcp_dbg = M.topic("gmcp", "every GMCP message as it comes: package and raw JSON", function()
  return "packages: " .. (gmcp_only[1] and table.concat(gmcp_only, " ") or "all")
    .. " - /debug gmcp <prefix ...> | all"
end)
gmcp_dbg.filter = gmcp_set
rune.hooks.on("gmcp", function(package, _, raw)
  if not gmcp_dbg.on then return end
  package = tostring(package)
  if gmcp_only[1] then
    local p, hit = package:lower(), false
    for _, w in ipairs(gmcp_only) do
      if p:sub(1, #w) == w then hit = true; break end
    end
    if not hit then return end
  end
  raw = tostring(raw or "")
  if #raw > 300 then raw = raw:sub(1, 300) .. "..." end
  gmcp_dbg.log(package .. " " .. raw)
end, { name = "debug_gmcp" })

return M
