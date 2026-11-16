dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local view = require("ui.view")
local MO
local orig = view.provides
view.provides = function(m, ...) local h = orig(m, ...); if m == "aard.moons" then MO = h end; return h end
require("modules.moons")
view.provides = orig
local theme = require("ui.theme")
local status = require("panes.status")
status.field = function(label, value, width, style)
  value = tostring(value)
  if value == "--" then style = theme.unavailable end
  return label .. " " .. (style or theme.value)(string.format("%-" .. width .. "s", value))
end
local T = theme.moon
local function old(need, allup, setleft, span)
  if need then return status.field("3MN", "??", 7, T.unknown) end
  if allup then
    if setleft < 0 then return status.field("3MN", "--", 7, theme.unavailable) end
    return status.field("3MN", (setleft + 1) .. "t", 7, T.up)
  end
  if not span.ok then return status.field("3MN", "--", 7, theme.unavailable) end
  local soon = span.lo <= 4
  local v = (span.lo > 0 and (math.min(span.lo, 999) .. "t") or "now") .. "/" .. span.len .. "t"
  return status.field("3MN", v, 7, soon and T.soon or theme.muted)
end
local n, bad = 0, 0
for _, need in ipairs({ true, false }) do for _, allup in ipairs({ true, false }) do
  for _, setleft in ipairs({ -1, 0, 3, 12 }) do for _, ok in ipairs({ true, false }) do
    for _, lo in ipairs({ -2, 0, 1, 4, 5, 80, 999, 1500 }) do for _, len in ipairs({ 1, 2, 9 }) do
      MO.set("moon.need", need); MO.set("moon.allup", allup); MO.set("moon.setleft", setleft)
      MO.set("moon.ok", ok); MO.set("moon.lo", lo); MO.set("moon.len", len); MO.publish()
      local row = H.pass():match("status1 L ([^\n]*)")
      local b = row:match("(3MN .-)%s?DPS ")
      local a = old(need, allup, setleft, { ok = ok, lo = lo, len = len })
      n = n + 1
      if a ~= b then bad = bad + 1; if bad < 4 then print(("DIFF %q\n     %q"):format(a, b)) end end
    end end
  end end
end end
print(n .. " states, " .. bad .. " differ")
