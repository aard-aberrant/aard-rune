-- The chats pane: channels and tells (GMCP comm.channel), remote socials,
-- and its scroll keys.
local util = require("core.util")
local game = require("core.game")   -- at login
local layout = require("core.layout")   -- the pane's height (what the restore fills)

-- The log: every line the pane gets is appended to chats.log, with its date
-- ("2026-11-07<TAB>14:03 (Group) ..."), kept for good (tt++'s
-- log/Aardwolf-chats) - colour codes and all (less -R reads them). Rune
-- empties the pane when it quits, so at start its last RESTORE lines (a
-- paneful) are written back; a /reload keeps the pane (only Lua restarts),
-- so not then (rune.session lasts until Rune quits). Only the file's end is read
local LOG = rune.config_dir .. "/chats.log"
local RESTORE = layout.CHATS_H

local function chat(text)
  text = text:gsub("\n", " ")
  rune.pane.write("chats", text)
  local fh = io.open(LOG, "a")
  if fh then fh:write(os.date("%Y-%m-%d"), "\t", text, "\n"); fh:close() end
end

if not rune.session.get("chats_restored") then
  rune.session.set("chats_restored", "1")
  local ok, err = pcall(function()
    local fh = io.open(LOG, "r")
    if not fh then return end
    local size = fh:seek("end")
    fh:seek("set", math.max(0, size - RESTORE * 400))
    local lines = {}
    for l in fh:lines() do lines[#lines + 1] = l end
    fh:close()
    if size > RESTORE * 400 then table.remove(lines, 1) end   -- the cut first line
    for i = math.max(1, #lines - RESTORE + 1), #lines do
      rune.pane.write("chats", (lines[i]:gsub("^[^\t]*\t", "")))
    end
  end)
  if not ok then util.err("[chats] can't read " .. LOG .. ": " .. tostring(err)) end
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
-- 2026-11-07 - the terminal, presumably). The mouse wheel scrolls only the main output: Rune sends
-- every wheel tick there, wherever the pointer is (ui/tui/model.go)
local function up() rune.pane.scroll_up("chats", 10) end
local function down() rune.pane.scroll_down("chats", 10) end
local function live() rune.pane.scroll_to_bottom("chats") end
for _, mod in ipairs({ "alt", "shift" }) do
  rune.bind(mod .. "+pgup", up)
  rune.bind(mod .. "+pgdown", down)
  rune.bind(mod .. "+end", live)
end
