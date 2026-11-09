-- /copy <n> [chat]: the last n lines of the main pane (or the chats pane)
-- to the clipboard, for a stretch longer than one screen (a tmux
-- Option-drag can't scroll Rune's pane: Rune is on the alternate screen, so
-- tmux has no history of it).
-- Lua can't read a pane, so this keeps its own copy of each, colors taken
-- off - a limit on each, so it stays small (about 100 bytes a line: 1000
-- lines ~100 KB, 500 ~50 KB):
--   main  the last 1000 game lines as shown (after triggers' rewrites,
--         gagged lines left out - the same output hook and priority as
--         Rune's /log, lua/core/60_log.lua), and what you type as
--         "> qc" (Rune's echo hook, as /log does - the typed line, not
--         what an alias sends), and our own messages ([eq] ... lines,
--         every rune.echo - Rune has no hook for them, so rune.echo is
--         wrapped below)
--   chat  the last 500 lines panes/chats.lua writes to its pane
--         (copy.keep)
-- A /reload keeps both (rune.session, written once at the reload).
-- Copied with rune.clipboard.set (OSC 52, as inst does).
-- Cost: one Lua call per game line, per chat line, per typed command and
-- per message (a table store); nothing on a timer.

local util = require("core.util")

local copy = {}

-- A ring of the last max lines, kept across a /reload under rune.session key
local function ring(key, max)
  local r = { buf = {}, head = 0, count = 0, max = max }   -- buf[head] is the newest line
  function r.push(text)
    r.head = r.head % max + 1
    r.buf[r.head] = text
    if r.count < max then r.count = r.count + 1 end
  end
  function r.last(n)   -- the last n lines, oldest first
    local out = {}
    for i = n - 1, 0, -1 do out[#out + 1] = r.buf[(r.head - 1 - i) % max + 1] end
    return out
  end
  for line in (rune.session.get(key) or ""):gmatch("([^\n]*)\n") do r.push(line) end
  rune.session.delete(key)
  rune.hooks.on("reloading", function()
    if r.count > 0 then rune.session.set(key, table.concat(r.last(r.count), "\n") .. "\n") end
  end, { name = key .. "_reload" })
  return r
end

local main, chat = ring("copy_lines", 1000), ring("copy_chat_lines", 500)

rune.hooks.on("output", function(line) main.push(line:clean()) end, { name = "copy_keep", priority = 200 })
-- After Rune's own echo handler (priority 100), which adds the "> "
rune.hooks.on("echo", function(text) main.push(util.strip(text)) end, { name = "copy_keep_echo", priority = 200 })

-- Our messages: rune.echo (lua/core/00_init.lua) is a plain function with
-- no hook, so it's wrapped. Every file calls rune.echo at the time (none
-- keeps its own copy), so they all go through this. The original is kept
-- in rune._copy_echo, so a /reload that keeps Lua's state wraps the
-- original again, not the last wrapper (every message would be kept twice)
rune._copy_echo = rune._copy_echo or rune.echo
local echo = rune._copy_echo
function rune.echo(text)
  for piece in (util.strip(tostring(text)) .. "\n"):gmatch("([^\n]*)\n") do main.push(piece) end
  echo(text)   -- returns nothing, as Rune's does
end

-- panes/chats.lua: each line it writes to the chats pane
function copy.keep(text) chat.push((text:gsub("\27%[[%d;]*m", ""))) end

rune.command.add("copy", function(args)
  local n, which = (args or ""):match("^%s*(%d+)%s*(%a*)%s*$")
  n = tonumber(n)
  if not n or n < 1 or (which ~= "" and which ~= "chat") then
    return util.warn("[copy] /copy <n> [chat] - the last n lines of the main pane (" .. main.count
      .. " of " .. main.max .. " kept) or the chats pane (" .. chat.count .. " of " .. chat.max .. ").")
  end
  local r = which == "chat" and chat or main
  n = math.min(n, r.count)
  if n == 0 then return util.warn("[copy] nothing yet.") end
  local text = table.concat(r.last(n), "\n")
  rune.clipboard.set(text)
  util.say("[copy] " .. n .. (which == "chat" and " chat" or "") .. " line" .. (n == 1 and "" or "s")
    .. " (" .. #text .. " characters) on the clipboard.")
end, "the last n lines of the main pane, or with chat the chats pane, to the clipboard: /copy <n> [chat]")

return copy
