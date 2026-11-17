-- lua chat_drive.lua ROOT [bench]: what the chats pane gets (rune.pane.write), per step
-- LAYOUT(name): data/layout/<name> on this tree, else an older tree's panes/<name> (ui/layout for "screen")
LAYOUT = LAYOUT or function(n) local new = "data.layout." .. n; if package.searchpath(new, package.path) then return require(new) end return require(n == "screen" and "ui.layout" or "panes." .. n) end
dofile(arg[1] .. "/tools/bench/harness.lua")
rune.session.delete = function(k) H.sess[k] = nil end
rune.hooks = { on = function() end, enable = function() end, disable = function() end }
rune.command = { get = function() return nil end, add = function() end }
rune.bind = function() end
local writes = {}
rune.pane = setmetatable({ write = function(n, t) writes[#writes + 1] = n .. " | " .. t end }, { __index = function() return function() end end })
local ok, err = pcall(LAYOUT, "chats")
if not ok then print("LOAD chats: " .. err) end
local function ctx(raw) return { line = { raw = function() return raw end, clean = function() return raw end } } end
local function line(raw)
  local clean = raw:gsub("\27%[[%d;]*m", "")
  for _, t in ipairs(H.triggers) do
    if t.kind == "starts" and t.pat ~= "" and clean:sub(1, #t.pat) == t.pat then t.fn(nil, ctx(raw)) end
  end
end
local real_date = os.date
os.date = function(f, t) return real_date(f, t or H.now) end
H.now = 1763300000
if arg[2] == "bench" then
  local N = 20000
  local t = os.clock()
  for k = 1, N do H.feed("comm.channel", { chan = "gossip", msg = "\27[0;35mBob gossips 'hi " .. k .. "'" }); H.pass() end
  print(string.format("one channel line + pass  %6.2f us", (os.clock() - t) / N * 1e6))
  t = os.clock()
  for k = 1, N do H.pass() end
  print(string.format("pass alone               %6.2f us", (os.clock() - t) / N * 1e6))
  return
end
local steps = {
  { "one channel", function() H.feed("comm.channel", { chan = "gossip", msg = "\27[0;35mBob gossips 'hi'" }) end },
  { "three in one event", function()
    H.feed("comm.channel", { chan = "tell", msg = "Ann tells you 'a'" })
    H.feed("comm.channel", { chan = "tell", msg = "Ann tells you 'b\nc'" })
    H.feed("comm.channel", { chan = "gtell", msg = "Zed: 'd'" }) end },
  { "mobsay (main window)", function() H.feed("comm.channel", { chan = "mobsay", msg = "The guard says 'halt'" }) end },
  { "remote social", function() H.now = H.now + 75; line("\27[0;36m*\27[0;37mWarlow smiles at you.") end },
  { "not a social", function() line("*SQUISH*") end },
}
for _, s in ipairs(steps) do s[2](); H.pass(); print("-- " .. s[1]); for _, w in ipairs(writes) do print(w) end; writes = {} end
