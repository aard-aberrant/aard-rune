-- The chats pane: channels and tells (GMCP comm.channel), remote socials,
-- and its scroll keys.
local util = require("core.util")
local game = require("core.game")   -- at login
local copy = require("core.copy")   -- /copy chat: each line the pane gets

-- The log: no file of its own. While a /log is open, each line the pane
-- gets goes into it too (Rune's log has the game's text lines only, and
-- channels come over GMCP). /log start chat [raw] [file] logs the chats
-- alone: Rune's own two log hooks (lua/core/60_log.lua: "log-output", the
-- game's lines, and "log-echo", what you type) are off until /log stop.
-- Rune holds the file open (Go), so a line is one write - no open/close.
-- The mode is kept in rune.session, as Rune keeps the open log, so a
-- /reload goes on logging chats alone. Rune empties the pane when it quits:
-- a restart starts it empty (a /reload keeps it)
local CHAT_ONLY = "log_chat_only"

local function chat(text)
  text = text:gsub("\n", " ")
  rune.pane.write("chats", text)
  copy.keep(text)
  if rune.log.status() then
    rune.log.write(rune.session.get("log_raw") and text or (text:gsub("\27%[[%d;]*m", "")))
  end
end

local function game_lines(on)
  for _, name in ipairs({ "log-output", "log-echo" }) do
    if on then rune.hooks.enable(name) else rune.hooks.disable(name) end
  end
end
if rune.session.get(CHAT_ONLY) then
  if rune.log.status() then game_lines(false) else rune.session.delete(CHAT_ONLY) end
end

-- /log, wrapped: "start chat" sets the mode; any other start clears it (a
-- log Rune closed itself - a write error - leaves it set); stop clears it
local rune_log = rune.command.get("log")
rune_log = rune_log and rune_log:action()
if rune_log then
  rune.command.add("log", function(args)
    local sub, rest = (args or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local first, more = rest:match("^(%S+)%s*(.*)$")
    if sub == "start" and not rune.log.status() then
      local only = first == "chat"
      game_lines(not only)
      if only then rune.session.set(CHAT_ONLY, "1") else rune.session.delete(CHAT_ONLY) end
      rune_log(only and ("start " .. more) or args)
      if not rune.log.status() then   -- it didn't open
        game_lines(true)
        rune.session.delete(CHAT_ONLY)
      elseif only then
        util.say("[log] chats only.")
      end
      return
    end
    rune_log(args)
    if sub == "stop" then
      game_lines(true)
      rune.session.delete(CHAT_ONLY)
    elseif (sub == "" or sub == "status") and rune.session.get(CHAT_ONLY) then
      util.say("[log] chats only.")
    end
  end, "Log the session to a file, chats included (/log start [chat] [raw] [file], /log stop); chat: the chats alone")
end

-- Channels over GMCP only: the GMCP message "gmcpchannels on" makes the
-- game stop sending channels and tells as text (tt++ modules/gmcp.tin sent
-- it at every connect - the game doesn't keep it). Sent at each login and
-- /reload (game.on_login). Its reply, "## GMCP Channels Only On.", is
-- hidden, by a trigger that exists only until it comes (util.await)
game.on_login(function()
  util.await("starts", "## GMCP Channels Only On", function(_, ctx)
    util.eat_blanks(ctx.line:clean())
    return false
  end, "chats_gchan_reply")
  rune.gmcp.send("gmcpchannels on")
end)

-- Each channel message, from GMCP comm.channel: mob speech (mobsay) to the
-- main output, where mob programs' speech belongs; everything else to the
-- chats pane with an HH:MM stamp (modules/gmcp.tin's ||gmcp_hook_comm_channel).
rune.gmcp.on("comm.channel", function(d)
  if type(d) ~= "table" or not d.msg then return end
  if d.chan == "mobsay" then
    rune.echo(d.msg)
  else
    chat(rune.style.gray(os.date("%H:%M")) .. " " .. d.msg)
  end
end, { name = "aard_channel" })

-- Remote socials ("*Rockwell smiles at you.", "*You smile at Rockwell.")
-- come as text, not GMCP: moved to the chats pane, stamped like a channel,
-- and the blank line(s) the game sends after one are hidden too
-- (general.tin). A line with a double space is left alone - "*Very fast
-- spell-up time    6000 ..." table rows look the same otherwise
rune.trigger.regex("^\\*[A-Z][A-Za-z]+ .*[.!?]$", function(_, ctx)
  local clean = ctx.line:clean()
  if clean:find("  ", 1, true) then return end
  chat(rune.style.gray(os.date("%H:%M")) .. " " .. ctx.line:raw())
  util.eat_blanks(clean)
  return false
end, { name = "remote_social" })

-- finger's reply has a blank line between every two lines (tt++
-- modules/general.tin). The reply is one block, from its header
-- ("----------------- Player : Bamboo (Online) -----------------", tt++'s
-- log) to a line of dashes: a span hides it as it comes and shows it again
-- without the blank lines, all at once at its end. Typed or by f, the same.
-- The header is matched from its leading dashes, so it costs what an
-- anchored pattern does. No closing line within 40: shown at that point
rune.trigger.regex("^-+ Player : ", function(_, ctx)
  for _, l in ipairs(ctx.lines) do
    if not util.blank(l:clean()) then rune.echo(l:raw()) end
  end
end, { name = "chats_finger", gag = true, span = { to = "^-+$", max = 40 } })

-- Scrolling the chats pane. PgUp/PgDn and Ctrl+Home/Ctrl+End scroll the
-- main output (Rune's defaults); the same keys with Alt scroll chats, and
-- Alt+End goes back to live tailing. Shift too - but most terminals keep
-- Shift+PgUp for their own scrollback (Shift didn't scroll chats live
-- 2026-11-07 - the terminal, presumably). The mouse wheel scrolls the pane
-- under the pointer - with our patched Rune (branch scrolling-panes on the
-- aard-aberrant fork, PR'd upstream); stock Rune 5d808d6 sends every wheel
-- tick to the main output
local function up() rune.pane.scroll_up("chats", 10) end
local function down() rune.pane.scroll_down("chats", 10) end
local function live() rune.pane.scroll_to_bottom("chats") end
for _, mod in ipairs({ "alt", "shift" }) do
  rune.bind(mod .. "+pgup", up)
  rune.bind(mod .. "+pgdown", down)
  rune.bind(mod .. "+end", live)
end
