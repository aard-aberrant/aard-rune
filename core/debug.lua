-- Debug topics (require("core.debug")): a module registers its own, and
-- one command switches them.
--   debug                  every topic: on or off, what it shows, its status
--   debug <topic> [on|off] switch one (bare: toggle)
--   debug all off          all off
-- On stays on across /reload (rune.session), off when Rune quits. A topic
-- exists only while its module is loaded (a per-subclass one, nav/moons,
-- only on that subclass); one that's on stays on for when it loads.
-- In a module:
--   local dbg = require("core.debug").topic("recov",
--     "the {recon}/{recoff} recovery tags as they come", status_fn)
--   if dbg.on then dbg.log("...") end
-- status_fn (optional) returns a line shown under the topic in "debug".
-- dbg.on is a plain field, so a check while off costs one table read; put
-- it in front of building the message, as above.
-- Output: gray, "15:40:12 [debug recov] ...".
local util = require("core.util")

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
      rune.echo(rune.style.gray(os.date("%H:%M:%S") .. " [debug " .. name .. "] " .. msg))
    end
    topics[name] = t
    order[#order + 1] = name
    table.sort(order)
  end
  t.desc, t.status = desc, status
  return t
end

local function list()
  if not order[1] then return util.say("[debug] no topics.") end
  util.say("[debug] topics - debug <topic> [on|off], debug all off:")
  for _, name in ipairs(order) do
    local t = topics[name]
    rune.echo(string.format("  %-8s %s  %s", name,
      t.on and rune.style.green("on ") or rune.style.gray("off"), t.desc or ""))
    if t.status then
      local ok, s = pcall(t.status)
      if ok and s then rune.echo(rune.style.gray("           " .. s)) end
    end
  end
end

rune.alias.exact("debug", function(args)
  local name, arg = util.trim(args):match("^(%S*)%s*(%S*)")
  if name == "" then return list() end
  if name == "all" then
    if arg ~= "off" then return util.warn("[debug] debug all off - one at a time to switch on.") end
    for _, n in ipairs(order) do topics[n].on = false end
    saved = {}
    save()
    return util.say("[debug] all off.")
  end
  local t = topics[name]
  if not t then return util.warn("[debug] no topic \"" .. name .. "\" - debug lists them.") end
  if arg == "on" then t.on = true elseif arg == "off" then t.on = false
  elseif arg == "" then t.on = not t.on
  else return util.warn("[debug] debug " .. name .. " [on|off]") end
  save()
  util.say("[debug] " .. name .. " " .. (t.on and "on" or "off") .. ".")
  if t.on and t.status then
    local ok, s = pcall(t.status)
    if ok and s then rune.echo(rune.style.gray("  " .. s)) end
  end
end)

-- Help (core/help.lua): /help, xhelp
local help = require("core.help")
help.add("debug", "debug [topic [on|off] | all off]", "debug topics: list them, switch one (bare toggles), or all off")

return M
