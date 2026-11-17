-- A command to look at a priority container and pin one of its items
-- (require("ui.pin")) - any priority container:
--   local pins = require("ui.pin").new { key = "info_pin", command = "infopane",
--     tag = "info", what = "info pane", help = "..." }
--   local pick = container:priority { ..., pin = pins.get }
--   pins.attach(pick)   -- after its items
-- <command>: list the items (on the pane / showing / idle, pinned);
-- <command> <name>: pin one (a prefix will do) - it shows whenever it has
-- something; <command> reset: the normal order. The pin is kept in
-- rune.session under key, so a /reload keeps it.
local util = require("lib.util")
local screen = require("ui.screen")
local help = require("lib.help")

local M = {}

function M.new(t)
  local key, cmd, tag, what = t.key, t.command, "[" .. t.tag .. "] ", t.what
  local pin = rune.session.get(key)
  if pin == "" then pin = nil end
  local o = {}
  function o.get() return pin end
  function o.attach(pick)
    rune.alias.exact(cmd, function(args)
      local arg = util.trim(args):lower()
      if arg == "" then
        util.say(tag .. what .. " items (the first with something to show wins):")
        local now = screen.peek(pick)
        for _, it in ipairs(pick.list) do
          local state = it.name == pick.shown and "on the pane" or (now[it.name] and "showing" or "idle")
          rune.echo(string.format("  %-11s %3d  %s%s", it.name, it.prio, state, it.name == pin and "  (pinned)" or ""))
        end
        return
      end
      if arg == "reset" then
        pin = nil
        rune.session.set(key, "")
        pick:refresh()
        util.say(tag .. what .. ": back to the normal order.")
        return
      end
      local hits = {}
      for _, it in ipairs(pick.list) do
        if it.name == arg then hits = { it.name }; break end
        if it.name:sub(1, #arg) == arg then hits[#hits + 1] = it.name end
      end
      if #hits == 0 then util.warn(tag .. cmd .. ": nothing called \"" .. arg .. "\" - " .. cmd .. " lists them."); return end
      if #hits > 1 then util.warn(tag .. cmd .. ": \"" .. arg .. "\" could be " .. table.concat(hits, ", ") .. "."); return end
      pin = hits[1]
      rune.session.set(key, pin)
      pick:refresh()
      util.say(tag .. what .. ": pinned to " .. pin
        .. (screen.peek(pick)[pin] and "" or ", which has nothing to show yet - it shows when it does")
        .. ". " .. cmd .. " reset to undo.")
    end)
    help.add(cmd, cmd .. " [<name>|reset]", t.help or ("list what can show in the " .. what
      .. "; <name>: pin one (it shows whenever it has something); reset: the normal order again"))
  end
  return o
end

return M
