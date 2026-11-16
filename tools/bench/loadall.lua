dofile((arg[0]:match("^(.*)/") or ".") .. "/harness.lua")
local src = io.open(arg[1] .. "/init.lua"):read("a")
local notfound, other, ok = {}, {}, 0
for m in src:gmatch('\nrequire%("([%w._]+)"%)') do
  local good, err = pcall(require, m)
  if good then ok = ok + 1
  elseif tostring(err):find("module '[^']+' not found") then notfound[#notfound + 1] = m .. ": " .. tostring(err):match("module '[^']+' not found")
  else other[#other + 1] = m .. ": " .. tostring(err):sub(1, 120) end
end
print("loaded " .. ok)
for _, x in ipairs(notfound) do print("NOT FOUND " .. x) end
for _, x in ipairs(other) do print("stub/other " .. x) end
