-- Chats (require("modules.chats")): channels and tells (GMCP comm.channel)
-- and remote socials, published as a stream (chat.line) for the chats pane
-- (data/layout/chats.lua); /copy chat and an open /log get each line too. Also
-- /log start chat (the chats alone) and finger's reply without its blank
-- lines.
local util = require("lib.util")
local colors = require("ui.colors")
local game = require("modules.game")   -- at login
local copy = require("modules.copy")   -- /copy chat: each line the pane gets
local line_text = require("format.chats").line

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

-- The chat lines are a stream (aard.chat): the chats pane shows them
-- (data/layout/chats.lua); /copy and the log take them here
local view = require("ui.view")
local C = view.provides("aard.chat", "channels, tells and remote socials, as they come", {
  ["chat.line"] = { "stream", "one line: { time = os.time(), text = the line in the game's colors }" },
})
local function chat(msg)
  msg = msg:gsub("\n", " ")
  local e = { time = os.time(), text = msg }
  C.emit("chat.line", e)
  local text = line_text(e)
  copy.keep(text)
  if rune.log.status() then
    rune.log.write(rune.session.get("log_raw") and text or colors.strip(text))
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
    return util.hide(ctx)
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
    chat(d.msg)
  end
end, { name = "aard_channel" })

-- Remote socials ("*Rockwell smiles at you.", "*You smile at Rockwell.")
-- come as text, not GMCP: moved to the chats pane, stamped like a channel,
-- and the blank line(s) the game sends after one are hidden too
-- (general.tin). The game marks one by its color: "Remote socials are
-- prefixed with a cyan asterisk" (the game's help), and live 2026-11-09 the
-- raw line was "\e[0;36m*\e[0;37mWarlow smiles at you." Other lines that start
-- with a * have another color or none ("*SQUISH*" green, "*Click*, the door
-- opens." and area trivia none - tt++'s logs), so the color alone decides:
-- any text after it, any ending ("*Gasp!* ...", '... goes "Hmmmm."').
-- The trigger is a literal prefix, so it costs next to nothing; the color
-- check runs only on lines that start with a *.
-- debug chats: each line that starts with a *, raw (\e for escape), and
-- what was done with it
local CYAN_STAR = colors.game.social
local dbg = require("lib.debug").topic("chats", "lines starting with *: raw, and moved to chats or left")
rune.trigger.starts("*", function(_, ctx)
  local raw = ctx.line:raw()
  local lead = raw:match("^(.-)%*") or ""
  local social = lead:sub(-#CYAN_STAR) == CYAN_STAR and colors.strip(lead) == ""
  if dbg.on then
    dbg.log((social and "moved: " or "left: ") .. colors.show(raw))
  end
  if not social then return end
  chat(raw)
  return util.hide(ctx)
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


return {}
