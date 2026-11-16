local root = arg[1]
package.path = root .. "/?.lua;" .. package.path
dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local layout = require("ui.layout")
local W = 44
layout.group_h = function() return 8 end
layout.left_w = function() return W end
local util = require("lib.util")
local panes = {}
util.pane = function(n, t) panes[n] = t end
require("modules.group"); require("panes.group")
H.feed("char.base", { name = "Aberrant", tier = "1", subclass = "x" })
local out = {}
local function grp(k, sz, leaveout)
  local m = {}
  for i = 1, sz do
    if i ~= leaveout then
      m[#m + 1] = { name = i == 1 and "Aberrant" or ("Member" .. i), info = { hp = tostring(100 + (k * 7 + i * 113) % 900), mhp = "1000", lvl = tostring(100 + i % 100), here = (i % 9 == 0) and 0 or 1 } }
    end
  end
  return { groupname = "@RThe @YBig @GGroup", leader = "Member2", members = m }
end
for k = 1, 30 do
  local sz = (k < 20) and 40 or 25
  if k == 25 then W = 30 end
  H.feed("group", grp(k % 7 == 0 and k - 1 or k, sz, k % 5 == 0 and 3 or nil)); H.pass()
  out[#out + 1] = "-- " .. k .. "\n" .. tostring(panes.group)
end
print(table.concat(out, "\n"))
