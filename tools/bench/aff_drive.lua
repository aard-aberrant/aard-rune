-- lua aff_drive.lua ROOT [bench] > out: the affects pane after each step of
-- one scenario (slist replies, tags, totem text, the clock), and the hidden
-- commands sent. Works on the old pane (draws itself on a 1 s timer) and
-- on the widget one (ui/screen.lua's pass)
-- LAYOUT(name): data/layout/<name> on this tree, else an older tree's panes/<name> (ui/layout for "screen")
LAYOUT = LAYOUT or function(n) local new = "data.layout." .. n; if package.searchpath(new, package.path) then return require(new) end return require(n == "screen" and "ui.layout" or "panes." .. n) end
local ROOT, MODE = arg[1], arg[2]
package.path = ROOT .. "/?.lua;" .. package.path
H = { handlers = {}, aliases = {}, after = {}, every = {}, trig = {}, tags = {}, now = 1000000, sess = {}, sent = {} }
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
rune = stub("rune")
rune.config_dir = ROOT
rune.echo = function() end
rune.send_raw = function(c) H.sent[#H.sent + 1] = c end
rune.session = { get = function(k) return H.sess[k] end, set = function(k, v) H.sess[k] = v end }
rune.gmcp = { on = function(pkg, fn) H.handlers[pkg] = H.handlers[pkg] or {}; table.insert(H.handlers[pkg], fn); return stub("g") end,
              send = function() end, subscribe = function() end }
local function trig(kind)
  return function(pat, fn, opts)
    local t = { kind = kind, pat = pat, fn = fn, on = true }
    H.trig[#H.trig + 1] = t
    return { disable = function() t.on = false end, enable = function() t.on = true end, remove = function() t.on = false end }
  end
end
rune.trigger = { regex = trig("regex"), starts = trig("starts"), exact = trig("exact"), contains = trig("contains"),
                 ends = trig("ends"), list = function() return {} end }
rune.alias = { exact = function(n, fn) H.aliases[n] = fn; return stub("alias") end,
               regex = function() return stub("alias") end, starts = function() return stub("alias") end }
rune.ui = stub("ui")
rune.ui.bar = function() end
rune.ui.refresh_bars = function() end
rune.store = { get = function() return nil end, set = function() end, delete = function() end }
rune._state = { scroll_mode = "live" }
rune.timer = {
  after = function(secs, fn)
    local t = { at = H.now + secs, fn = fn }
    H.after[#H.after + 1] = t
    return { cancel = function() t.dead = true end }
  end,
  every = function(secs, fn) H.every[#H.every + 1] = fn; return stub("timer") end,
}
H.panes = {}
rune.pane = { replace = function(n, text) H.panes[n] = text end }
package.loaded["modules.tags"] = { on = function(n, fn) H.tags[n] = fn end }
local layout = LAYOUT("screen")
rune._state.width = 44 + layout.RIGHT_W + 1; rune._state.height = 50
local util = require("lib.util")
util.say, util.warn, util.err = function() end, function() end, function() end
require("modules.game")
LAYOUT("affects")
local SCR = package.loaded["ui.screen"]

local function feed(pkg, d) for _, fn in ipairs(H.handlers[pkg] or {}) do fn(d) end end
local function L(s) return { clean = function() return s end, raw = function() return s end } end
local function ctx1(s) return { line = L(s), lines = { L(s) } } end
-- a line through the triggers (regex: the Lua-ized pattern, captures)
local function line(s)
  for _, t in ipairs(H.trig) do
    if t.on and t.pat ~= "" then
      if t.kind == "contains" and s:find(t.pat, 1, true) then t.fn(nil, ctx1(s))
      elseif t.kind == "exact" and s == t.pat then t.fn(nil, ctx1(s))
      elseif t.kind == "regex" then
        local lp = t.pat:gsub("\\%.", "%%."):gsub("\\w", "%%w"):gsub("%?", "?")
        local m = { s:match(lp) }
        if m[1] then t.fn(m, ctx1(s)) end
      end
    end
  end
end
local function span(first, rows, last)
  local ls = { L(first) }
  for _, r in ipairs(rows) do ls[#ls + 1] = L(r) end
  ls[#ls + 1] = L(last)
  for _, t in ipairs(H.trig) do
    if t.kind == "exact" and t.pat == first then t.fn(nil, { line = ls[1], lines = ls }) end
  end
end
local function tag(name, rest) H.tags[name](rest) end
local function draw() if SCR then SCR.pass() else for _, fn in ipairs(H.every) do fn() end end end
local function second()
  H.now = H.now + 1
  local again = true
  while again do
    again = false
    for _, t in ipairs(H.after) do
      if not t.dead and t.at <= H.now then t.dead = true; again = true; t.fn(); break end
    end
  end
  for _, fn in ipairs(H.every) do fn() end
  draw()
end
local function advance(n) for _ = 1, n do second() end end
local step = 0
local function snap(label)
  draw()
  step = step + 1
  io.stdout:write("@@ " .. step .. " " .. label .. "  sent: " .. table.concat(H.sent, ";") .. "\n"
    .. (H.panes.affects or "") .. "\n")
  H.sent = {}
end

local function slist(spells, recs)
  span("{spellheaders affected}", spells, "{/spellheaders}")
  span("{recoveries affected}", recs or {}, "{/recoveries}")
end
local SPELLS = {
  "71,sanctuary,2,300,100,-1,1", "72,shield,2,-1,100,-1,1", "155,aid,2,221,100,-1,1",
  "29,curse,1,600,100,-1,1", "300,armor,2,20,100,-1,1", "301,bless,2,50,100,-1,1",
  "302,giant strength,2,100,100,-1,1", "303,fly,2,250,100,-1,1", "304,haste,2,500,100,-1,1",
  "305,stone skin,2,700,100,-1,1", "306,kobold stench,2,90,100,-1,1", "120,heighten senses,2,1000,100,-1,2",
  "307,detect invis,2,1500,100,-1,1", "308,green death,1,40,100,-1,1",
}

snap("empty"); advance(1); snap("1s")
feed("char.base", { name = "Seth", subclass = "Shaman" })
snap("shaman")
slist(SPELLS, { "65,Create Totem,312" })
snap("slist")
for _, s in ipairs({ 1, 9, 10, 10, 30, 20, 40, 60 }) do advance(s); snap("+" .. s) end
line("You place a Bear totem in the room.")
snap("totem placed")
line("Totem Name"); line("Wyrm         Center of the Council   Bear Totem   04:02")
snap("totem row")
tag("affon", "400,5")       -- new, unknown spell
snap("affon unknown"); advance(1); snap("+1 asks")
tag("affoff", "29"); snap("curse off")
tag("affon", "66,120"); snap("poison on")
tag("affoff", "71"); snap("sanc off")
tag("recon", "65,200"); snap("recon totem")
for _ = 1, 6 do advance(30); snap("+30") end
line("Your totem has expired."); snap("totem expired")
tag("recoff", "65"); snap("recoff")
line("You are still recovering your Create Totem abilities (1:23)."); snap("still recovering")
advance(90); snap("+90")
layout.left_w = function() return 50 end
rune._state.width = 50 + layout.RIGHT_W + 1
advance(1); snap("wider")
feed("char.base", { name = "Seth", subclass = "Priest" })
snap("priest")
slist({ "602,humility,2,100,100,40,1", "71,sanctuary,2,500,100,-1,1" }, { "41,Serenity,200" })
snap("priest slist")
tag("recon", "40,300"); snap("recon humility")
tag("affoff", "602"); snap("humility off")
for _ = 1, 4 do advance(60); snap("+60") end
H.aliases["saf"](""); snap("saf")
slist({}, {}); snap("empty slist")

if MODE ~= "bench" then return end
-- 30 spells up for an hour or so, a Shaman with a totem
local many = {}
for k = 1, 30 do many[#many + 1] = (500 + k) .. ",spell number " .. k .. ",2," .. (1800 + k * 97) .. ",100,-1," .. (k % 4 == 0 and 2 or 1) end
many[#many + 1] = "71,sanctuary,2,2400,100,-1,1"
feed("char.base", { name = "Seth", subclass = "Shaman" })
slist(many, {})
line("You place a Bear totem in the room."); line("Wyrm         Center of the Council   Bear Totem   40:02")
advance(2)
local N = 1500
local t = os.clock()
for _ = 1, N do second() end
local idle = (os.clock() - t) / N * 1e6
-- the same seconds' bare loop (timers list, no work): subtracted
local every = H.every; H.every = {}
local scr = SCR; SCR = nil
t = os.clock(); for _ = 1, N do second() end
local base = (os.clock() - t) / N * 1e6
H.every, SCR = every, scr
H.after = {}
local M = 20000
t = os.clock()
for k = 1, M do tag("affon", (500 + k % 30 + 1) .. "," .. (1800 + k % 50)); draw() end
local one = (os.clock() - t) / M * 1e6
t = os.clock()
for k = 1, M / 10 do
  for j = 1, 10 do tag("affon", (500 + (k + j) % 30 + 1) .. "," .. (1700 + (k * j) % 90)) end
  draw()
end
local ten = (os.clock() - t) / (M / 10) * 1e6
print(string.format("idle second: %6.2f us", idle - base))
print(string.format("one affon + draw: %6.2f us", one))
print(string.format("10 affon + draw: %6.2f us", ten))
