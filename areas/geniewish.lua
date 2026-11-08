-- A Genie's Last Wish shortcuts (tt++ areas/geniewish.tin). Only while you're
-- in the geniewish zone (areas/loader.lua).
--   ftl    find the lamp
--   wff    wish for forgiveness
--   wfa    wish for adventure
--   mini   n, wish for peace, then 4 north
local A = ...

local function cmd(name, text, desc)
  A.alias.exact(name, function() rune.send_raw(text) end)
  A.help(name, name, desc .. " (geniewish)")
end
cmd("ftl", "find the lamp", "find the lamp")
cmd("wff", "wish for forgiveness", "wish for forgiveness")
cmd("wfa", "wish for adventure", "wish for adventure")
cmd("mini", "n\nwish for peace\nn\nn\nn\nn", "n, wish for peace, then 4 north")
