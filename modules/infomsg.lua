-- infomsg [-t secs] text: your own text on the info pane (data/layout/info.lua
-- shows it, over quest, campaign and account, under the alerts) - this
-- module holds it as data. | starts a new line (4 at most). -t: gone after
-- that many seconds. Bare: cleared.
local util = require("lib.util")
local view = require("ui.view")

local M = view.provides("aard.infomsg", "your own text (infomsg)", {
  ["infomsg.line1"] = { "text", "the first line; nil: no message" },
  ["infomsg.line2"] = { "text", "the second line (\"\" when empty); nil: none" },
  ["infomsg.line3"] = { "text", "the third" },
  ["infomsg.line4"] = { "text", "the fourth" },
})

local clear = util.slot()   -- an infomsg's time up

local function msg(text, secs)
  clear.stop()
  local rows = {}
  if text then
    for l in (text .. "|"):gmatch("(.-)|") do
      if #rows < 4 then rows[#rows + 1] = l end
    end
  end
  for k = 1, 4 do M.set("infomsg.line" .. k, rows[k]) end
  M.publish()
  if text and secs then clear.start(secs, function() msg(nil) end) end
end

rune.alias.exact("infomsg", function(args)
  local text = util.trim(args)
  if text == "" then msg(nil); return end
  local secs, rest = text:match("^%-t%s+(%d+)%s+(.+)$")
  if text:match("^%-t") and not secs then
    util.warn("[info] infomsg [-t seconds] [text] - | starts a new line.")
    return
  end
  msg(rest or text, tonumber(secs))
end)

-- Help (lib/help.lua): /help
local help = require("lib.help")
help.add("infomsg", "infomsg [-t secs] [text]", "your own text on the info pane (| starts a line, 4 lines); -t: gone after secs; bare clears it")

return {}
