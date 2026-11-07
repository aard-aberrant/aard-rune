-- The chats pane: channels and tells (GMCP comm.channel), remote socials,
-- and its scroll keys.
local util = require("core.util")
local game = require("core.game")   -- at login

-- Channels over GMCP only: the GMCP message "gmcpchannels on" makes the
-- game stop sending channels and tells as text (tt++ modules/gmcp.tin sent
-- it at every connect - the game doesn't keep it). Sent at each login and
-- /reload (game.on_login). Its reply, "## GMCP Channels Only On.", is
-- hidden - it only ever answers this
game.on_login(function() rune.gmcp.send("gmcpchannels on") end)
rune.trigger.regex("^## GMCP Channels Only On", function(_, ctx)
  util.eat_blanks(ctx.line:clean())
  return false
end, { name = "chats_gchan_reply" })

-- Each channel message, from GMCP comm.channel: mob speech (mobsay) to the
-- main output, where mob programs' speech belongs; everything else to the
-- chats pane with an HH:MM stamp (modules/gmcp.tin's ||gmcp_hook_comm_channel).
rune.gmcp.on("comm.channel", function(d)
  if type(d) ~= "table" or not d.msg then return end
  if d.chan == "mobsay" then
    rune.echo(d.msg)
  else
    rune.pane.write("chats", rune.style.gray(os.date("%H:%M")) .. " " .. d.msg)
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
  rune.pane.write("chats", rune.style.gray(os.date("%H:%M")) .. " " .. ctx.line:raw())
  util.eat_blanks(clean)
  return false
end, { name = "remote_social" })

-- Scrolling the chats pane. PgUp/PgDn and Ctrl+Home/Ctrl+End scroll the
-- main output (Rune's defaults); the same keys with Shift scroll chats.
-- Shift+End goes back to live tailing.
rune.bind("shift+pgup", function() rune.pane.scroll_up("chats", 10) end)
rune.bind("shift+pgdown", function() rune.pane.scroll_down("chats", 10) end)
rune.bind("shift+end", function() rune.pane.scroll_to_bottom("chats") end)
