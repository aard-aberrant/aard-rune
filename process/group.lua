-- Group processors (require("process.group")): modules/group.lua's members
-- -> what the group pane's list compares, a member at a time.
local floor = math.floor

local P = {}

-- The flags packed into a member's number (format/group.lua reads them)
P.HERE, P.ME, P.LEADER, P.FOLLOWED = 1, 2, 4, 8
local HERE, ME, LEADER, FOLLOWED = P.HERE, P.ME, P.LEADER, P.FOLLOWED

-- A member: everything its row shows, in one number - level (0: not
-- known), HP percent, and here / me / leader / followed (one bit each):
-- ((lvl + 1) * 100000 + pct) * 16 + flags. The name is the row's key
function P.member(m)
  local pct = 0
  if m.hp and m.mhp and m.mhp ~= 0 then pct = floor(m.hp * 100 / m.mhp) end
  local flags = (m.here and HERE or 0) + (m.me and ME or 0) + (m.leader and LEADER or 0) + (m.followed and FOLLOWED or 0)
  return ((m.lvl and m.lvl + 1 or 0) * 100000 + pct) * 16 + flags
end

-- The list's order: members here first, then lowest HP; ties in the
-- game's order
function P.here_then_hp(v)
  local flags = v % 16
  local pct = floor(v / 16) % 100000
  return (flags % 2 == 1 and 0 or 100000) + pct
end

return P
