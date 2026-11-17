-- Loads the real status-bar modules from ROOT (arg[1]) with Rune stubbed.
-- H.feed(pkg, data), H.line(text) drive them; H.pass() renders the bars.
-- LAYOUT(name): data/layout/<name> on this tree, else an older tree's panes/<name> (ui/layout for "screen")
LAYOUT = LAYOUT or function(n) local new = "data.layout." .. n; if package.searchpath(new, package.path) then return require(new) end return require(n == "screen" and "ui.layout" or "panes." .. n) end
local ROOT = arg[1]
package.path = ROOT .. "/?.lua;" .. package.path
H = { handlers = {}, triggers = {}, bars = {}, bar_order = {}, now = 1000000, sess = {} }
os.time = function() return H.now end
local function stub(name)
  return setmetatable({}, {
    __index = function(t, k)
      if type(k) == "number" then return nil end
      local v = stub(name .. "." .. tostring(k)); rawset(t, k, v); return v
    end,
    __call = function() return stub(name .. "()") end,
  })
end
local function trig(kind)
  return function(pat, fn, opts)
    H.triggers[#H.triggers + 1] = { kind = kind, pat = pat, fn = fn }
    return stub("trigger")
  end
end
rune = stub("rune")
rune.config_dir = ROOT
rune.echo = function() end
rune.session = { get = function(k) return H.sess[k] end, set = function(k, v) H.sess[k] = v end }
rune.gmcp = { on = function(pkg, fn) H.handlers[pkg] = H.handlers[pkg] or {}; table.insert(H.handlers[pkg], fn); return stub("g") end,
              send = function() end, subscribe = function() end }
rune.trigger = { regex = trig("regex"), starts = trig("starts"), exact = trig("exact"), contains = trig("contains"),
                 ends = trig("ends"), list = function() return {} end }
rune.ui = stub("ui")
rune.ui.bar = function(n, f) if not H.bars[n] then H.bar_order[#H.bar_order + 1] = n end; H.bars[n] = f end
rune.ui.refresh_bars = function() end
rune.log = { status = function() return H.log end, start = function(p) H.log = p; return true end,
             stop = function() H.log = nil; return true end }
rune.store = { get = function() return nil end, set = function() end, delete = function() end }
rune._state = { scroll_mode = "live" }
rune.timer = { after = function() return stub("timer") end, every = function() return stub("timer") end }
rune.pane = stub("pane")
local util = require("lib.util")
util.append_log = function() end
util.append_file = function() end
util.write_file = function() return true end
util.dir_exists = function() return true end
util.say = function() end
function H.feed(pkg, d) for _, fn in ipairs(H.handlers[pkg] or {}) do fn(d) end end
for _, m in ipairs({ "modules.game", "layout:status", "modules.quest", "modules.repop", "modules.dps", "modules.pup",
                     "modules.doubles", "modules.autocast" }) do
  local name = m:match("^layout:(.*)")
  local ok, err = pcall(name and LAYOUT or require, name or m)
  if not ok then print("LOAD " .. m .. ": " .. tostring(err)) end
end
function H.pass()
  local out = {}
  for _, n in ipairs(H.bar_order) do
    if n:match("^status%d") or n == "view_flush" then
      local r = H.bars[n]()
      if r then out[#out + 1] = n .. " L " .. tostring(r.left) .. "\n" .. n .. " R " .. tostring(r.right) end
    end
  end
  return table.concat(out, "\n")
end
return H
