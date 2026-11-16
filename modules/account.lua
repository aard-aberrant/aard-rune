-- Your account (require("modules.account")), from GMCP char.worth and
-- char.stats (tt++ account.tin) - data only: the info pane (panes/info.lua)
-- shows it.
-- The minimums below which the pane shows red: the defaults
-- (conf/equipment.tin); a subclass's file (data/classes/<subclass>.lua)
-- may set its own: hr_min, dr_min, stat_min. Read again when the subclass
-- changes.
local util = require("lib.util")
local game = require("modules.game")   -- char.worth, char.stats, the subclass
local view = require("ui.view")

local DEF_HR, DEF_DR, DEF_STAT = 1600, 2000, 600
local mins_for   -- the subclass they were read for

local STATS = { "str", "wis", "con", "dex", "luck" }
local decls = {
  ["acct.gold"]     = { "number", "gold on hand; nil until GMCP char.worth" },
  ["acct.bank"]     = { "number", "gold in the bank" },
  ["acct.worth"]    = { "number", "gold on hand and in the bank" },
  ["acct.known"]    = { "boolean", "GMCP char.worth has come (true from then on)" },
  ["acct.qp"]       = { "number", "quest points" },
  ["acct.tp"]       = { "number", "trivia points" },
  ["acct.trains"]   = { "number", "trains" },
  ["acct.hr"]       = { "number", "hitroll; nil until GMCP char.stats" },
  ["acct.dr"]       = { "number", "damroll" },
  ["acct.hr_min"]   = { "number", "the hitroll your subclass should have" },
  ["acct.dr_min"]   = { "number", "the damroll your subclass should have" },
  ["acct.stat_min"] = { "number", "the least a stat should be" },
}
for _, k in ipairs(STATS) do decls["acct." .. k] = { "number", k .. " (char.stats)" } end
local A = view.provides("aard.account", "your gold, points and stats, from GMCP char.worth / char.stats", decls)
A.set("acct.hr_min", DEF_HR); A.set("acct.dr_min", DEF_DR); A.set("acct.stat_min", DEF_STAT)

local function num(t, k) return t and tonumber(t[k]) end
-- Each package sets only its own values (a char.worth leaves the stats alone)
local function worth()
  local w = game.worth
  local gold, bank = num(w, "gold"), num(w, "bank")
  A.set("acct.gold", gold); A.set("acct.bank", bank)
  A.set("acct.worth", gold and bank and gold + bank or nil)
  A.set("acct.known", gold ~= nil and bank ~= nil)
  A.set("acct.qp", num(w, "qp")); A.set("acct.tp", num(w, "tp")); A.set("acct.trains", num(w, "trains"))
  A.publish()
end
local function stats()
  local s = game.stats
  A.set("acct.hr", num(s, "hr")); A.set("acct.dr", num(s, "dr"))
  for _, k in ipairs(STATS) do A.set("acct." .. k, num(s, k)) end
  A.publish()
end
rune.gmcp.on("char.worth", worth, { name = "account_char.worth" })
rune.gmcp.on("char.stats", stats, { name = "account_char.stats" })

-- A new subclass (modules/game.lua has stored char.base already): its minimums
rune.gmcp.on("char.base", function()
  local sub = game.subclass
  if not sub or sub == mins_for then return end
  mins_for = sub
  local C = util.class_data(sub) or {}
  A.set("acct.hr_min", C.hr_min or DEF_HR)
  A.set("acct.dr_min", C.dr_min or DEF_DR)
  A.set("acct.stat_min", C.stat_min or DEF_STAT)
  A.publish()
end, { name = "account_class_mins" })

worth(); stats()   -- what game has already (a /reload)

return {}
