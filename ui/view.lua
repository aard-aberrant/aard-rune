-- The display engine (require("ui.view")): modules publish declared,
-- shaped data; widgets turn data into text; panes and bars place widgets.
-- Generic - nothing here knows the game. Plan:
-- ~/.claude/plans/ok-time-to-plan-humble-nest.md (2026-11-15).
--
-- Developers (modules):
--   local S = view.provides("aard.vitals", "your vitals from GMCP", {
--     hp   = { "ratio",     "hit points" },
--     tick = { "timestamp", "when the next tick is due" },
--   })
--   S.set("hp", { cur = 2310, max = 4200 })   -- the only way to change data
--   S.publish()                                -- once per update: subscribers run
--   view.get("hp")   view.subscribe("hp", fn)  -- other modules read
-- Widgets (developers): view.widget(type, def) - see the bottom; a
-- module's own segment: view.widgets.custom(type, { inputs = { "quest.state",
-- "quest.ready_at.left.min" }, clock = bool }, function(st, state, mins) ...
-- end) - st(slot, text, value) styles with the user's "<type>.<slot>".
-- Slots other modules fill: w.slot(list), view.slot_add(list, item, pos).
-- Layout (users, later a restricted config file; for now Lua):
--   local w = view.widgets
--   local health = w.rag(20, 60)        -- red < 20, amber < 60, else green
--   view.bar("status2", { left = { "HP ", w.pad(health(view.ref("hp")), 9) } })
--   view.pane("info", { pick = "priority", w.text("{campaign.area} ...") })
--
-- Data names are global ("hp", "campaign.area"); a data ref's shape adds
-- fields: hp.cur, hp.max, hp.pct, hp.frac (ratio), tick.left (timestamp).
--
-- When things draw: S.set asks Rune for a bar pass (rune.ui.refresh_bars,
-- ~1 us; once per burst). Rune runs the bars once at the end of each event
-- it handles (a packet, a timer, a key - session.go flushPresentation) and
-- every 250 ms. The first view bar registered redraws everything then,
-- before returning its own row (Rune renders bars in registration order,
-- so the later ones find theirs ready); with panes and no view bar, a
-- hidden bar, view_flush, does it - no extra Rune call per pass otherwise.
-- A set that changes a value marks dirty only the widgets showing that
-- data, and their parents; a pass skips every clean one. Values that
-- follow the clock (tick.left) are worked out again once the second
-- changes; widgets built from functions (calls) on every pass. Panes get
-- rune.pane.replace only when their text changed (util.pane); bars return
-- their saved row.
-- set a new table for a ratio or list: the same table set again (changed
-- in place) is no change. A value equal to the one held is no change either.
-- No timers: phase 0 measured rune.timer.after at 107-150 us a call.
-- Cost: S.set - a compare, a table write, a dirty mark per widget showing
-- it, the refresh flag; a pass - a flag check per clean widget on the way
-- to the dirty ones; rebuilds only on change.

local view = {}

local unpack = table.unpack or unpack
local floor, ceil = math.floor, math.ceil

-- Injected so plain-Lua tests can run without Rune
view.clock = os.time
view.dev = false   -- check every S.set against its declared shape

local util, colors, theme, dbg
local function deps()
  if util then return end
  util = require("lib.util")
  colors = require("ui.colors")
  theme = require("ui.theme")
  dbg = require("lib.debug").topic("view", "the display engine: each publish, and each redraw with its cost")
end

local function fail(msg, level) error("[view] " .. msg, (level or 1) + 1) end

-- Shapes ------------------------------------------------------------------
-- name -> { is = parent, check = fn(v), fields = { k = { shape, desc, fn, time } }, desc }

local shapes = {}
function view.shape(name, def)
  def.fields = def.fields or {}
  shapes[name] = def
end
local function shape_is(a, b)   -- a counts as b (itself, or a descendant)
  while a do
    if a == b then return true end
    a = shapes[a] and shapes[a].is
  end
  return false
end
view.shape_is = shape_is
-- All fields of a shape, its parents' too
local function shape_field(shape, k)
  while shape do
    local f = shapes[shape] and shapes[shape].fields[k]
    if f then return f end
    shape = shapes[shape] and shapes[shape].is
  end
end
local function shape_fields(shape)
  local out = {}
  while shape do
    for k in pairs(shapes[shape] and shapes[shape].fields or {}) do out[#out + 1] = k end
    shape = shapes[shape] and shapes[shape].is
  end
  table.sort(out)
  return out
end
view.shape_fields = shape_fields

local function isnum(v) return type(v) == "number" end
view.shape("number", { desc = "a number", check = isnum })
view.shape("percent", { is = "number", desc = "a number, 0-100" })
view.shape("seconds", { is = "number", desc = "a length of time in seconds", fields = {
  min = { "number", "minutes, rounded up", function(s) return ceil(s / 60) end },
}})
view.shape("text", { desc = "text", check = function(v) return type(v) == "string" end })
view.shape("boolean", { desc = "true or false", check = function(v) return type(v) == "boolean" end })
view.shape("timestamp", { is = "number", desc = "a moment (os.time)", fields = {
  left = { "seconds", "seconds until it, 0 once past", function(t) return math.max(0, t - view.clock()) end, true },
  ago  = { "seconds", "seconds since it, 0 before it", function(t) return math.max(0, view.clock() - t) end, true },
  due  = { "seconds", "seconds until it, nil once past", function(t) local d = t - view.clock(); if d >= 0 then return d end end, true },
}})
view.shape("ratio", { desc = "a value and its maximum: { cur, max }",
  check = function(v) return type(v) == "table" and isnum(v.cur) and isnum(v.max) end,
  fields = {
    cur  = { "number", "the value", function(r) return r.cur end },
    max  = { "number", "the maximum", function(r) return r.max end },
    pct  = { "percent", "cur as a percent of max (nil when max is 0)",
             function(r) if r.max ~= 0 then return r.cur * 100 / r.max end end },
    frac = { "text", "cur/max", function(r) return r.cur .. "/" .. r.max end },
  }})
view.shape("list", { desc = "a list of records", check = function(v) return type(v) == "table" end })
view.shape("record", { desc = "named values (a table) - set a new one at each change",
  check = function(v) return type(v) == "table" end })
view.shape("block", { desc = "text the game colored, several lines", check = function(v) return type(v) == "string" end })

-- Data --------------------------------------------------------------------

local decl = {}       -- data name -> { shape, desc, time, standard, module, fields }
-- Data with a getter (provides' get = fn): never stored - a read of it
-- (view.get, a widget) calls the getter; S.touch(name) says it changed.
-- For data that changes often between draws (DPS at each hit): no table
-- built per change, the value read once per redraw
local getters = {}
local store = {}      -- data name -> value
local ver = {}        -- data name -> version, +1 at each set
local subs = {}       -- data name -> { fn, ... }
local modules = {}    -- module -> { desc, names = { ... } }
local requested = false
-- set when the bars' code must be built again (a slot added to, a style
-- changed: the code holds each style's codes; new data: a later widget
-- that lacked it may build now)
local restructure = false
local watchers = {}    -- data name -> { instance = true }: what shows it, parents included

local function request()
  if requested then return end
  requested = true
  if rune and rune.ui and rune.ui.refresh_bars then rune.ui.refresh_bars() end
end

local armed = {}   -- touchers used since the last pass: reset at the next

local depth = 0
local function notify(names)
  if depth >= 4 then
    deps()
    if dbg.on then dbg.log("publish cascade cut at depth 4: " .. table.concat(names, ",")) end
    return
  end
  depth = depth + 1
  for _, n in ipairs(names) do
    for _, fn in ipairs(subs[n] or {}) do
      local ok, err = pcall(fn, n, store[n])
      if not ok then deps(); util.warn("[view] a subscriber of " .. n .. " failed: " .. tostring(err)) end
    end
  end
  depth = depth - 1
end

function view.provides(module, desc, decls)
  if modules[module] then fail("module " .. module .. " already provides its data", 2) end
  restructure = true
  local names = {}
  for name, d in pairs(decls or {}) do
    local shape = d[1]
    if not shapes[shape] then fail(module .. ": " .. name .. " has an unknown shape \"" .. tostring(shape) .. "\"", 2) end
    if decl[name] then
      fail(name .. " is provided by both " .. decl[name].module .. " and " .. module, 2)
    end
    decl[name] = { shape = shape, desc = d[2] or "", time = d.time, standard = d.standard,
                   fields = d.fields, module = module }
    if d.get then getters[name] = d.get end
    ver[name] = 0
    names[#names + 1] = name
  end
  table.sort(names)
  modules[module] = { desc = desc or "", names = names }
  local S, pending = {}, {}
  local function check(name)
    local d = decl[name]
    if not d or d.module ~= module then fail(module .. " doesn't provide " .. tostring(name), 3) end
    if getters[name] then fail(name .. " has a getter - touch it, not set", 3) end
    return d
  end
  local function shape_warn(name, d, v)
    local sh = shapes[d.shape]
    local s = d.shape
    while sh and not sh.check do s = sh.is; sh = shapes[s] end
    if sh and not sh.check(v) then
      deps(); util.warn("[view] " .. module .. " set " .. name .. " to a " .. type(v) .. ", not a " .. d.shape)
    end
  end
  -- The set itself, once the name is known good: equal = no change; then
  -- stored, its widgets marked, the pass asked for; a subscriber's name
  -- (or debug view's) kept for publish
  local function put(name, d, v)
    local old = store[name]
    if old == v then return end
    if type(v) == "table" and type(old) == "table" and v.cur ~= nil and v.cur == old.cur and v.max == old.max then
      store[name] = v; return
    end
    if view.dev and v ~= nil then shape_warn(name, d, v) end
    store[name] = v
    ver[name] = ver[name] + 1
    local ws = watchers[name]
    if ws then for i in pairs(ws) do i.dirty = true end end
    if (subs[name] or (dbg and dbg.on)) and not pending[name] then pending[name] = true; pending[#pending + 1] = name end
    if not requested then request() end
  end
  function S.set(name, v) put(name, check(name), v) end
  -- S.setter(name): a function(v) that sets name - checked once (a
  -- module's hot path: every GMCP vitals and status)
  function S.setter(name)
    local d = check(name)
    return function(v) put(name, d, v) end
  end
  function S.get(name) return view.get(name) end
  -- S.toucher(name): a function that touches name - checked once, then
  -- only what a touch must do (for a module's hot path: each hit line).
  -- After one touch the rest until the next pass do nothing: the widgets
  -- are dirty already and the pass asked for
  function S.toucher(name)
    local d = decl[name]
    if not d or d.module ~= module or not getters[name] then fail(module .. " has no getter data " .. tostring(name), 2) end
    local on = false
    local function reset() on = false end
    return function()
      if on then return end
      on = true
      armed[#armed + 1] = reset
      ver[name] = ver[name] + 1
      local ws = watchers[name]
      if ws then for i in pairs(ws) do i.dirty = true end end
      if (subs[name] or (dbg and dbg.on)) and not pending[name] then pending[name] = true; pending[#pending + 1] = name end
      if not requested then request() end
    end
  end
  -- a getter's data changed: redrawn at the next pass
  function S.touch(name)
    local d = decl[name]
    if not d or d.module ~= module or not getters[name] then fail(module .. " has no getter data " .. tostring(name), 2) end
    ver[name] = ver[name] + 1
    local ws = watchers[name]
    if ws then for i in pairs(ws) do i.dirty = true end end
    if not pending[name] then pending[name] = true; pending[#pending + 1] = name end
    request()
  end
  -- (no subscriber of any pending name and debug off: only the list cleared)
  function S.publish()
    local np = #pending
    if np == 0 then return end
    local any = dbg and dbg.on
    if not any then for k = 1, np do if subs[pending[k]] then any = true; break end end end
    if not any then
      for k = 1, np do pending[pending[k]] = nil; pending[k] = nil end
      return
    end
    local names = {}
    for i, n in ipairs(pending) do names[i] = n; pending[n] = nil; pending[i] = nil end
    deps()
    if dbg.on then dbg.log("publish " .. module .. ": " .. table.concat(names, ",")) end
    notify(names)
  end
  return S
end

-- A module's data goes (an area unloaded)
function view.unprovide(module)
  local m = modules[module]
  if not m then return end
  for _, n in ipairs(m.names) do decl[n], store[n], subs[n], getters[n] = nil, nil, nil, nil; ver[n] = nil end
  modules[module] = nil
  request()
end

function view.get(name)
  local g = getters[name]
  if g then return g() end
  return store[name]
end
function view.subscribe(name, fn)
  subs[name] = subs[name] or {}
  table.insert(subs[name], fn)
end

-- The catalog (for the catalog command, docs and validation)
function view.data(name) return decl[name] end
function view.modules() return modules end

-- Refs --------------------------------------------------------------------
-- A ref stands for a value worked out when drawn: data ("hp"), a shape's
-- field of another ref (hp.pct), a helper's result (pct(a, b)), or a
-- constant. Fields are reached by indexing (hp.pct); internals live in
-- R[ref], not on the ref, so a field name can't clash with them.
--   kind, shape, time (follows the clock), and:
--   data: name;  field: parent, fn;  derived: inputs, fn;  const: value

local R = setmetatable({}, { __mode = "k" })
local REF = {}
local function mkref(t)
  local r = setmetatable({}, REF)
  R[r] = t
  return r
end
REF.__index = function(r, k)
  local t = R[r]
  t.memo = t.memo or {}
  if t.memo[k] then return t.memo[k] end
  local f = shape_field(t.shape, k)
  if not f then
    fail(t.label .. " is a " .. t.shape .. ": no field \"" .. tostring(k) .. "\""
      .. (#shape_fields(t.shape) > 0 and (" - it has " .. table.concat(shape_fields(t.shape), ", ")) or ""), 2)
  end
  local fr = mkref({ kind = "field", shape = f[1], time = t.time or f[4], parent = r, fn = f[3],
                     label = t.label .. "." .. k })
  t.memo[k] = fr
  return fr
end
REF.__tostring = function(r) return "ref " .. R[r].label end

local function isref(x) return getmetatable(x) == REF end
view.isref = isref

-- A data name, with shape fields after it: "hp", "hp.pct", "campaign.area"
-- (the longest leading part that's data, the rest fields)
local dataref = {}
function view.ref(name)
  if dataref[name] then return dataref[name] end
  local parts = {}
  for p in tostring(name):gmatch("[^.]+") do parts[#parts + 1] = p end
  for i = #parts, 1, -1 do
    local base = table.concat(parts, ".", 1, i)
    local d = decl[base]
    if d then
      local r = dataref[base]
      if not r then
        r = mkref({ kind = "data", shape = d.shape, time = d.time, name = base, label = base })
        dataref[base] = r
      end
      for j = i + 1, #parts do r = r[parts[j]] end
      dataref[name] = r
      return r
    end
  end
  fail("no data named \"" .. tostring(name) .. "\"", 2)
end

-- Rows: view.row(list) - refs to the fields of the row a list widget is
-- drawing (r.hp, r.here), so any widget or helper works on a row. The list
-- data declares its rows' fields: provides' fields = { name = shape, ... }
local ROW = {}      -- list name -> the record being drawn
local rowver = {}   -- list name -> +1 at each row drawn (what a row's widgets compare)
function view.row(name)
  local d = decl[name]
  if not d or not shape_is(d.shape, "list") then fail("row: " .. tostring(name) .. " isn't list data", 2) end
  local fields = d.fields or {}
  return setmetatable({}, { __index = function(t, k)
    local sh = fields[k]
    if not sh then
      local have = {}
      for f in pairs(fields) do have[#have + 1] = f end
      table.sort(have)
      fail(name .. "'s rows have no field \"" .. tostring(k) .. "\" - they have " .. table.concat(have, ", "), 2)
    end
    local ref = mkref({ kind = "row", shape = sh, list = name, field = k, label = name .. "[]." .. k })
    rawset(t, k, ref)
    return ref
  end })
end

function view.const(v, shape)
  return mkref({ kind = "const", value = v, shape = shape or (type(v) == "number" and "number" or "text"),
                 label = tostring(v) })
end
local function asref(x)
  if isref(x) then return x end
  if type(x) == "number" or type(x) == "string" then return view.const(x) end
  fail("expected data or a value, got " .. type(x), 3)
end

-- A ref's value now
local function value(r)
  local t = R[r]
  local k = t.kind
  if k == "data" then
    local g = getters[t.name]
    if g then return g() end
    return store[t.name]
  end
  if k == "const" then return t.value end
  if k == "field" then
    local p = value(t.parent)
    if p == nil then return nil end
    return t.fn(p)
  end
  if k == "row" then
    local rec = ROW[t.list]
    return rec and rec[t.field]
  end
  local args = {}
  for i, inp in ipairs(t.inputs) do
    args[i] = value(inp)
    if args[i] == nil and not t.nils then return nil end
  end
  return t.fn(unpack(args, 1, #t.inputs))
end
view.value = value

-- What changes when a ref's value may have: the sum of its data's
-- versions (each only grows, so any change raises the sum)
local function stamp(r)
  local t = R[r]
  local k = t.kind
  if k == "data" then return ver[t.name] or -1 end
  if k == "const" then return 0 end
  if k == "field" then return stamp(t.parent) end
  if k == "row" then return rowver[t.list] or 0 end
  local s = 0
  for _, inp in ipairs(t.inputs) do s = s + stamp(inp) end
  return s
end

function view.shape_of(r) return R[asref(r)].shape end
function view.follows_clock(r) return R[asref(r)].time == true end

-- Helpers: derived refs from a fixed library ------------------------------

-- code(args): the same as fn, as a Lua expression on the inputs' variables
-- (generated code runs it inline - no call)
local function derived(label, shape, inputs, fn, nils, code)
  local time = false
  for _, i in ipairs(inputs) do if R[i].time then time = true end end
  return mkref({ kind = "derived", shape = shape, inputs = inputs, fn = fn, time = time, label = label, nils = nils, code = code })
end
local function need(r, shape, who, n)
  if not shape_is(R[r].shape, shape) then
    fail(who .. ": argument " .. n .. " (" .. R[r].label .. ") is a " .. R[r].shape .. ", needs a " .. shape, 3)
  end
end
local helpers = {}
function helpers.pct(a, b)
  a, b = asref(a), asref(b)
  need(a, "number", "pct", 1); need(b, "number", "pct", 2)
  return derived("pct(" .. R[a].label .. ", " .. R[b].label .. ")", "percent", { a, b },
    function(x, y) if y ~= 0 then return x * 100 / y end end, nil,
    function(x, y) return "(" .. y .. " ~= 0 and " .. x .. " * 100 / " .. y .. " or nil)" end)
end
local function arith(name, op)
  helpers[name] = function(a, b)
    a, b = asref(a), asref(b)
    need(a, "number", name, 1); need(b, "number", name, 2)
    return derived(name .. "(" .. R[a].label .. ", " .. R[b].label .. ")", "number", { a, b }, op)
  end
end
arith("sum", function(x, y) return x + y end)
arith("diff", function(x, y) return x - y end)
arith("min", math.min)
arith("max", math.max)
-- when(a, cond): a while cond is true, else nil; below(a, n) / above(a, n):
-- a while it's under (over) n, else nil - so a line can leave a value out
function helpers.when(a, cond)
  a, cond = asref(a), asref(cond)
  return derived("when(" .. R[a].label .. ", " .. R[cond].label .. ")", R[a].shape, { a, cond },
    function(x, c) if c then return x end end)
end
local function bound(name, test)
  helpers[name] = function(a, n)
    a = asref(a)
    need(a, "number", name, 1)
    if type(n) ~= "number" then fail(name .. ": the limit must be a number", 2) end
    return derived(name .. "(" .. R[a].label .. ", " .. n .. ")", R[a].shape, { a },
      function(x) if test(x, n) then return x end end, nil,
      function(x) return "((" .. x .. (name == "below" and " < " or " > ") .. n .. ") and " .. x .. " or nil)" end)
  end
end
bound("below", function(x, n) return x < n end)
-- less(a, n): true while a is under n, false otherwise (nil while a is) - a
-- clock value turned into one that changes only when it crosses n
function helpers.less(a, n)
  a = asref(a)
  need(a, "number", "less", 1)
  if type(n) ~= "number" then fail("less: the limit must be a number", 2) end
  return derived("less(" .. R[a].label .. ", " .. n .. ")", "boolean", { a }, function(x) return x < n end)
end
bound("above", function(x, n) return x > n end)
-- Tests (cases' when): true or false, never nil - a nil input is just not
-- equal, not true. eq(a, v): a equals v; any(a, b, ...) / all(a, b, ...):
-- one / every one is true (not nil or false); no(a): a is nil or false
local function tests(name, label, inputs, fn, code)
  return derived(label, "boolean", inputs, fn, true, code)
end
local function lit(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "number" or type(v) == "boolean" or v == nil then return tostring(v) end
end
function helpers.eq(a, v)
  a = type(a) == "string" and view.ref(a) or asref(a)
  local l = lit(v)
  return tests("eq", "eq(" .. R[a].label .. ", " .. tostring(v) .. ")", { a }, function(x) return x == v end,
    l and function(x) return "(" .. x .. " == " .. l .. ")" end)
end
local function list_of(name, ...)
  local refs, labels = {}, {}
  for k = 1, select("#", ...) do
    local x = select(k, ...)
    refs[k] = type(x) == "string" and view.ref(x) or asref(x)
    labels[k] = R[refs[k]].label
  end
  return refs, name .. "(" .. table.concat(labels, ", ") .. ")"
end
function helpers.any(...)
  local refs, label = list_of("any", ...)
  return tests("any", label, refs, function(...)
    for k = 1, select("#", ...) do if select(k, ...) then return true end end
    return false
  end, function(...)
    local t = {}
    for k = 1, select("#", ...) do t[k] = "(" .. select(k, ...) .. " and true or false)" end
    return "(" .. table.concat(t, " or ") .. ")"
  end)
end
function helpers.all(...)
  local refs, label = list_of("all", ...)
  return tests("all", label, refs, function(...)
    for k = 1, select("#", ...) do if not select(k, ...) then return false end end
    return true
  end, function(...)
    local t = {}
    for k = 1, select("#", ...) do t[k] = "(" .. select(k, ...) .. " and true or false)" end
    return "(" .. table.concat(t, " and ") .. ")"
  end)
end
-- even(): true on an even second, false on an odd one - a flash, one
-- second each way (when(even(), x): only while x - nothing flashes, nothing
-- to rebuild)
function helpers.even()
  local r = derived("even()", "boolean", {}, function() return view.clock() % 2 == 0 end, true)
  R[r].time = true
  return r
end
function helpers.no(a)
  a = type(a) == "string" and view.ref(a) or asref(a)
  return tests("no", "no(" .. R[a].label .. ")", { a }, function(x) return not x end,
    function(x) return "(not " .. x .. ")" end)
end
function helpers.round(a, places)
  a = asref(a)
  need(a, "number", "round", 1)
  local m = 10 ^ (places or 0)
  return derived("round(" .. R[a].label .. ")", R[a].shape, { a },
    function(x) return floor(x * m + 0.5) / m end)
end
-- floor(a): a rounded down; either(a, b): a, or b while a is nil ("?" for
-- a level not sent)
function helpers.floor(a)
  a = asref(a)
  need(a, "number", "floor", 1)
  return derived("floor(" .. R[a].label .. ")", R[a].shape, { a }, floor, nil,
    function(x) return "FLOOR(" .. x .. ")" end)
end
function helpers.either(a, b)
  a, b = asref(a), asref(b)
  return derived("either(" .. R[a].label .. ", " .. R[b].label .. ")", R[a].shape, { a, b },
    function(x, y) if x == nil then return y end return x end, true,
    function(x, y) return "(" .. x .. " == nil and " .. y .. " or " .. x .. ")" end)
end
view.helpers = helpers

-- Styles ------------------------------------------------------------------
-- The user's: name -> a palette name ("red"), a list of them mixed
-- ({ "bold", "red" }), or rules on a value
-- ({ { below = 20, "red" }, { below = 60, "yellow" }, "green" }).
-- Palette names are ui/theme.lua's (data/theme.lua's changes apply) - a
-- module's group member as "quest.ready"; "plain" is no color.

local styles = {}
local compiled = {}   -- name -> fn(text, value) (unstyled: returns the text)
local style_gen = 0   -- +1 at each view.styles: every widget redraws in the new colors
view.palette = function(name)
  deps()
  local g, m = name:match("^(.-)%.(.+)$")
  if g then return theme[g] and theme[g][m] or nil end   -- a module's group: "quest.ready"
  return theme[name]
end
-- (compiled is cleared in place: generated code holds the table)
local function clear(t) for k in pairs(t) do t[k] = nil end end
function view.styles(t)
  styles = t or {}
  clear(compiled)
  style_gen = style_gen + 1
  restructure = true
  request()
end
-- Styles added to the current ones (while panes move over one by one)
function view.add_styles(t)
  for k, v in pairs(t) do styles[k] = v end
  clear(compiled)
  style_gen = style_gen + 1
  restructure = true
  request()
end

local RESET = "\27[0m"
local function code_of(spec)
  if spec == "plain" then return "" end   -- no color: the text as it is
  if type(spec) == "string" then
    local c = view.palette(spec)
    return c and c.on
  end
  if type(spec) == "table" and spec[1] and not spec.below and not spec.above and spec.equals == nil then
    local on = {}
    for i, n in ipairs(spec) do on[i] = code_of(n); if not on[i] then return nil end end
    return table.concat(on)
  end
end
-- A palette entry with its own off code (emphasis: underline on 4, off 24):
-- its on and off, so it can sit inside another style's color
local function own_off(spec)
  if type(spec) ~= "string" or spec == "plain" then return nil end
  local c = view.palette(spec)
  if c and c.off then return c.on, c.off end
end
local function compile(name)
  local spec = styles[name]
  if spec == nil then return false end
  local on, off = own_off(spec)
  if on then return function(s) return on .. s .. off end end
  local fixed = code_of(spec)
  if fixed == "" then return function(s) return s end end
  if fixed then return function(s) return fixed .. s .. RESET end end
  -- rules: the first that matches the value; a bare entry is the fallback
  local rules = {}
  for _, r in ipairs(spec) do
    if type(r) == "table" then
      rules[#rules + 1] = { below = r.below, above = r.above, equals = r.equals, on = code_of(r[1]) }
    else
      rules[#rules + 1] = { on = code_of(r) }   -- the fallback
    end
  end
  return function(s, v)
    for _, r in ipairs(rules) do
      local hit
      if r.below then hit = type(v) == "number" and v < r.below
      elseif r.above then hit = type(v) == "number" and v > r.above
      elseif r.equals ~= nil then hit = v == r.equals
      else hit = true end
      if hit then return (r.on and r.on ~= "") and (r.on .. s .. RESET) or s end
    end
    return s
  end
end
-- Text in style `name`, judged on `v` for rules; unstyled if there's no such style
local function plain(s) return s end
local function style_fn(name)
  local f = compile(name) or plain
  compiled[name] = f
  return f
end
function view.style(name, s, v)
  return (compiled[name] or style_fn(name))(s, v)
end

-- Widgets -----------------------------------------------------------------
-- view.widget(type, {
--   desc  = "...",
--   make  = function(...) return settings end,     -- the constructor's arguments
--   forms = { { "number" }, { "ratio", via = function(r) return r.pct end }, ... },
--   slots = { "red", "amber", "green" },           -- styled as "<type>.<slot>"
--   render = function(settings, v, ctx) return text or nil end,
-- })
-- view.widgets.<type>(...) returns the configured widget; calling that on
-- data (refs, or plain values) matches a form and returns an instance to
-- place. A widget with direct = true is placed straight from its
-- constructor (text). Instances: { def, settings, input = ref, ... }.

local wdefs = {}
view.widgets = {}
local INST = {}
local function inst(t) return setmetatable(t, INST) end
local function isinst(x) return getmetatable(x) == INST end
view.isinst = isinst

local function form_match(def, args)
  for _, f in ipairs(def.forms) do
    if #f == #args then
      local ok = true
      for i, s in ipairs(f) do
        if not shape_is(R[args[i]].shape, s) then ok = false; break end
      end
      if ok then return f.via and f.via(unpack(args)) or args[1] end
    end
  end
  local got, can = {}, {}
  for i, a in ipairs(args) do got[i] = R[a].label .. " (" .. R[a].shape .. ")" end
  for i, f in ipairs(def.forms) do can[i] = table.concat(f, ", ") end
  fail(def.type .. " can't take " .. table.concat(got, ", ") .. " - it takes: " .. table.concat(can, " | "), 4)
end

function view.widget(wtype, def)
  def.type = wtype
  def.forms = def.forms or {}
  wdefs[wtype] = def
  view.widgets[wtype] = function(...)
    local settings = def.make and def.make(...) or {}
    if def.direct then return inst({ def = def, settings = settings, inputs = settings.inputs or {} }) end
    return function(...)
      local args = { ... }
      for i = 1, select("#", ...) do args[i] = asref(args[i]) end
      local input = form_match(def, args)
      return inst({ def = def, settings = settings, input = input, inputs = { input } })
    end
  end
end
function view.widget_defs() return wdefs end

-- plain ASCII (digits, most labels): its length - no gsubs
local find = string.find
local function width(s)
  if not find(s, "[\27\128-\255]") then return #s end
  deps(); return colors.width(s)
end

-- ctx for render: ctx.style(slot, text, value) - the widget's own slots
local function ctx_for(def)
  return { style = function(slot, s, v) return view.style(def.type .. "." .. slot, s, v) end }
end

-- An instance's text now: rebuilt only when an input changed
-- At an instance's first draw: dyn (it or a child is redrawn on every
-- pass), timed (follows the clock), and the data names it shows (its
-- children's too) - it's marked dirty when one of them changes
local function names_of(r, into)
  local t = R[r]
  if t.kind == "data" then into[t.name] = true
  elseif t.kind == "field" then names_of(t.parent, into)
  elseif t.kind == "row" then into[t.list] = true
  elseif t.kind == "derived" then for _, x in ipairs(t.inputs) do names_of(x, into) end end
end
local function flags(i)
  if i.build and not i.children then   -- later: its widget, if its data exists now
    local ok, child = pcall(i.build)
    if ok and isinst(child) then i.children = { child }
    else
      i.children = {}
      deps()
      if dbg.on then dbg.log("later widget left out: " .. tostring(ok and "no widget" or child)) end
    end
  end
  local dyn, timed, names = i.always and true or false, i.clock and true or false, {}
  if i.list then   -- a slot: its instances are its children, a function makes it dyn
    local kids = {}
    for _, x in ipairs(i.list) do
      if isinst(x) then kids[#kids + 1] = x else dyn = true end
    end
    i.children, i.n = kids, #i.list
  end
  local tin
  for _, r in ipairs(i.inputs or {}) do
    if R[r].time then timed = true; tin = tin or {}; tin[#tin + 1] = r end
    names_of(r, names)
  end
  -- each clock input once; a derived one left out when every clock input
  -- under it is compared already (it can't change unless one of those does)
  if tin then
    local direct, seen, keep = {}, {}, {}
    for _, r in ipairs(tin) do if R[r].kind ~= "derived" then direct[r] = true end end
    -- (a derived clock source with no clock inputs - even() - is its own)
    local function covered(r)
      local t = R[r]
      if not t.time then return true end
      if t.kind ~= "derived" then return direct[r] == true end
      local any = false
      for _, x in ipairs(t.inputs) do
        if R[x].time then any = true end
        if not covered(x) then return false end
      end
      return any
    end
    for _, r in ipairs(tin) do
      if not seen[r] and not (R[r].kind == "derived" and covered(r)) then keep[#keep + 1] = r end
      seen[r] = true
    end
    tin = keep
  end
  -- a leaf following the clock only through its inputs: compared by value
  -- each new second, rebuilt only when one changed (QST's minutes)
  i.tin = (tin and not i.clock and not (i.children and i.children[1])) and tin or nil
  for _, c in ipairs(i.children or {}) do
    if c.dyn == nil then flags(c) end
    dyn = dyn or c.dyn; timed = timed or c.timed
    for n in pairs(c.names) do names[n] = true end
  end
  for n in pairs(names) do
    watchers[n] = watchers[n] or setmetatable({}, { __mode = "k" })
    watchers[n][i] = true
  end
  i.dyn, i.timed, i.names = dyn, timed, names
end
local function draw(i)
  if i.dyn == nil then flags(i) end
  if i.drawn and not i.dyn and not i.dirty and i.gen == style_gen and (not i.timed or i.tnow == view.clock()) then
    return i.out
  end
  i.dirty = false
  if i.timed then i.tnow = view.clock() end
  local changed = not i.drawn or i.gen ~= style_gen or i.always or i.clock
  if i.list and i.n ~= #i.list then flags(i); changed = true end
  i.gen = style_gen
  i.last = i.last or {}
  for n, r in ipairs(i.inputs) do
    local key
    if R[r].time then key = value(r) else key = stamp(r) end
    if i.last[n] ~= key then changed = true end
    i.last[n] = key
  end
  for _, c in ipairs(i.children or {}) do
    if draw(c) ~= c.prev then changed = true end
    c.prev = c.out
  end
  if not changed then return i.out end
  i.drawn = true
  local ok, out
  if i.def.compose then
    ok, out = pcall(i.def.compose, i)
  else
    local v = value(i.input)
    ok, out = pcall(i.def.render, i.settings, v, ctx_for(i.def))
  end
  if not ok then
    deps()
    if not i.err then util.warn("[view] " .. i.def.type .. " widget failed: " .. tostring(out)) end
    i.err, out = true, nil
  end
  i.out = out
  i.rebuilt = (i.rebuilt or 0) + 1
  return out
end
view.draw = draw

-- The built-in widgets ------------------------------------------------------

-- Number formatting: whole numbers as they are, others to `places` (1)
local function fmtnum(v, places)
  if type(v) ~= "number" then return tostring(v) end
  if v == floor(v) then return tostring(floor(v)) end
  return string.format("%." .. (places or 1) .. "f", v)
end
local function commas(v)
  local s = fmtnum(v, 0)
  local sign, int = s:match("^(-?)(%d+)$")
  if not int then return s end
  return sign .. int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end
local function dur(s)
  if type(s) ~= "number" then return tostring(s) end
  s = floor(s)
  if s >= 3600 then return string.format("%dh%02dm", floor(s / 3600), floor(s % 3600 / 60)) end
  if s >= 60 then return string.format("%dm%02ds", floor(s / 60), s % 60) end
  return s .. "s"
end
view.fmt = { num = fmtnum, commas = commas, dur = dur }

-- rag(t1[, t2]): red below t1, amber below t2, else green; one threshold:
-- red below it, else green. On a ratio it judges the percent; the number is
-- shown as it is (whole) or to one place
view.widget("rag", {
  desc = "a number in red, amber or green by thresholds",
  make = function(t1, t2, opts)
    if type(t1) ~= "number" then fail("rag: the first threshold must be a number", 3) end
    if t2 ~= nil and type(t2) ~= "number" then fail("rag: the second threshold must be a number", 3) end
    return { t1 = t1, t2 = t2, places = opts and opts.places }
  end,
  forms = {
    { "number" },
    { "ratio", via = function(r) return r.pct end },
    { "number", "number", via = function(a, b) return helpers.pct(a, b) end },
  },
  slots = { "red", "amber", "green" },
  render = function(s, v, ctx)
    if v == nil then return nil end
    local slot = v < s.t1 and "red" or (s.t2 and v < s.t2) and "amber" or "green"
    return ctx.style(slot, fmtnum(v, s.places), v)
  end,
})

-- meter(width): a bar filled to the percent (ratio, or a percent)
view.widget("meter", {
  desc = "a bar filled to a percent",
  make = function(w) return { w = w or 10 } end,
  forms = {
    { "percent" },
    { "ratio", via = function(r) return r.pct end },
    { "number", "number", via = function(a, b) return helpers.pct(a, b) end },
  },
  slots = { "fill", "empty" },
  render = function(s, v, ctx)
    if v == nil then return nil end
    local n = math.max(0, math.min(s.w, floor(v * s.w / 100 + 0.5)))
    return ctx.style("fill", string.rep("█", n)) .. ctx.style("empty", string.rep("░", s.w - n))
  end,
})

-- text("template"): {name} and {name|filter:arg|...}; nil when any named
-- value is nil (so a priority pane moves on). Filters: pad:n, rpad:n,
-- cut:n, commas, dur, num:places, plain, style:name. Parsed once
-- crop(s, n): s cut to n columns; colored text gets a reset at the end,
-- plain text none (so a style put on it afterwards covers it all)
local function crop(s, n)
  if not find(s, "[\27\128-\255]") then return #s <= n and s or s:sub(1, n) end   -- plain ASCII
  deps()
  local c = colors.crop(s, n)
  if not s:find("\27", 1, true) then c = c:sub(1, -#colors.RESET - 1) end
  return c
end
local FILTERS = {
  pad = function(s, _, n) local w = width(s); n = tonumber(n) or 0; return w < n and s .. string.rep(" ", n - w) or s end,
  rpad = function(s, _, n) local w = width(s); n = tonumber(n) or 0; return w < n and string.rep(" ", n - w) .. s or s end,
  cut = function(s, _, n) return crop(s, tonumber(n) or 0) end,
  commas = function(_, v) return commas(v) end,
  dur = function(_, v) return dur(v) end,
  num = function(_, v, n) return fmtnum(v, tonumber(n)) end,
  plain = function(s) deps(); return colors.strip(s) end,
  style = function(s, v, name) return view.style(name, s, v) end,
  -- fixed:n - always n places ("100.0"); as:text - show text, judged on the value
  fixed = function(s, v, n) return type(v) == "number" and string.format("%." .. (tonumber(n) or 0) .. "f", v) or s end,
  as = function(_, _, txt) return txt or "" end,
  -- after:text - text added at the end ("{x|after:s|style:y}": "23s" styled whole)
  after = function(s, _, txt) return s .. (txt or "") end,
  -- clock - seconds as m:ss ("0:52", "12:05"), ">100m" from 100 minutes
  clock = function(s, v)
    if type(v) ~= "number" then return s or tostring(v) end
    if v >= 6000 then return ">100m" end
    return string.format("%d:%02d", math.floor(v / 60), v % 60)
  end,
  -- mmss - seconds as MM:SS, "99:99" past 99 minutes
  mmss = function(s, v)
    if type(v) ~= "number" then return s or tostring(v) end
    if v > 5999 then return "99:99" end
    return string.format("%02d:%02d", math.floor(v / 60), v % 60)
  end,
  -- ell:n - cut to n columns, the last a "…" when it was longer
  ell = function(s, _, n)
    n = tonumber(n) or 0
    if width(s) <= n then return s end
    local c = crop(s, n - 1)
    local R, reset = colors.RESET, false
    while c:sub(-#R) == R do c, reset = c:sub(1, -#R - 1), true end
    return c .. "…" .. (reset and R or "")
  end,
}
local function parse(tpl, vars)
  local parts, inputs = {}, {}
  local pos = 1
  while true do
    local a, b, inner = tpl:find("{([^{}]+)}", pos)
    if not a then
      if pos <= #tpl then parts[#parts + 1] = tpl:sub(pos) end
      break
    end
    if a > pos then parts[#parts + 1] = tpl:sub(pos, a - 1) end
    local segs = {}
    for seg in inner:gmatch("[^|]+") do segs[#segs + 1] = seg end
    local r = vars and vars[segs[1]] and asref(vars[segs[1]]) or view.ref(segs[1])
    local filters = {}
    for k = 2, #segs do
      local fname, arg = segs[k]:match("^(%w+):?(.*)$")
      if not fname or not FILTERS[fname] then fail("text: unknown filter \"" .. segs[k] .. "\" in \"" .. tpl .. "\"", 4) end
      filters[#filters + 1] = { FILTERS[fname], arg ~= "" and arg or nil }
    end
    inputs[#inputs + 1] = r
    parts[#parts + 1] = { input = #inputs, filters = filters }
    pos = b + 1
  end
  return parts, inputs
end
-- text(tpl, opts): opts.vars - names for refs in the template ({ lvl =
-- below(level, 201) }); opts.style + opts.by - the whole line in a style,
-- judged on that value (data name or ref)
view.widget("text", {
  desc = "a line from a template: {name|filter}",
  direct = true,
  make = function(tpl, opts)
    if type(tpl) ~= "string" then fail("text: needs a template string", 3) end
    opts = opts or {}
    local parts, inputs = parse(tpl, opts.vars)
    local by
    if opts.by then
      by = type(opts.by) == "string" and view.ref(opts.by) or asref(opts.by)
      inputs[#inputs + 1] = by
    end
    return { parts = parts, inputs = inputs, tpl = tpl, style = opts.style, by = by }
  end,
  compose = function(i)
    local s = i.def.line(i)
    if s ~= nil and i.settings.style then
      return view.style(i.settings.style, s, i.settings.by and value(i.settings.by))
    end
    return s
  end,
  line = function(i)
    local out = {}
    for k, p in ipairs(i.settings.parts) do
      if type(p) == "string" then out[k] = p
      else
        local v = value(i.inputs[p.input])
        if v == nil then return nil end
        local s = type(v) == "number" and fmtnum(v) or tostring(v)
        for _, f in ipairs(p.filters) do s = f[1](s, v, f[2]) end
        out[k] = s
      end
    end
    return table.concat(out)
  end,
})

-- cases(label, { case, case, ... }, opts): a labeled value whose text and
-- style depend on the data - the first case whose test holds and whose
-- template has every value. A case: { when = test, "template", style =
-- name, by = data or ref }; no when: always (the fallback, last).
-- "LABEL " goes before the case's text (no label: nil or ""); opts.pad: the
-- case's text padded to that many columns after its style. Compiled to one
-- function: the tests and templates inline, as text's
local function aref(x) return type(x) == "string" and view.ref(x) or asref(x) end
-- every ref an instance reads (its inputs, its children's, its cases')
local function refs_of(i, into)
  for _, r in ipairs(i.inputs or {}) do into[#into + 1] = r end
  for _, c in ipairs(i.children or {}) do refs_of(c, into) end
  return into
end
view.refs_of = refs_of
function view.widgets.cases(label, list, opts)
  opts = opts or {}
  local inputs, cs = {}, {}
  for k, c in ipairs(list) do
    local case
    if isinst(c[1]) then   -- a widget: its text (several spans in their own styles)
      local ins = {}
      refs_of(c[1], ins)
      case = { w = c[1], inputs = ins, style = c.style, width = c.width }
    else
      if type(c[1]) ~= "string" then fail("cases: case " .. k .. " needs a template string or a widget", 2) end
      local parts, ins = parse(c[1], c.vars)
      case = { parts = parts, inputs = ins, style = c.style, width = c.width }
    end
    if c.when ~= nil then case.test = aref(c.when); inputs[#inputs + 1] = case.test end
    if c.by ~= nil then case.by = aref(c.by); case.inputs[#case.inputs + 1] = case.by end
    for _, r in ipairs(case.inputs) do inputs[#inputs + 1] = r end
    cs[k] = case
  end
  local prefix = (label and label ~= "") and (label .. " ") or ""
  return inst({ def = { type = "cases", compose = function(i)
    for _, c in ipairs(i.cases) do
      if not c.test or value(c.test) then
        local s
        if c.w then s = draw(c.w) else s = wdefs.text.line({ settings = c, inputs = c.inputs }) end
        if s ~= nil then
          if c.width then s = FILTERS.pad(s, nil, c.width) end
          if c.style then s = view.style(c.style, s, c.by and value(c.by)) end
          if i.pad then s = FILTERS.pad(s, nil, i.pad) end
          return i.prefix .. s
        end
      end
    end
    return nil
  end }, inputs = inputs, cases = cs, prefix = prefix, pad = opts.pad })
end

-- pad(x, n) / cut(x, n): another instance (or data) padded or cut to n columns
local function wrap(kind, x, n)
  if not isinst(x) then x = view.widgets.text("{v}", { vars = { v = asref(x) } }) end
  return inst({ def = { type = kind, compose = function(i)
    local s = i.children[1].out
    if s == nil then return nil end
    if kind == "pad" then return FILTERS.pad(s, nil, n) end
    return FILTERS.cut(s, nil, n)
  end }, inputs = {}, children = { x }, n = n })
end
function view.widgets.pad(x, n) return wrap("pad", x, n) end
function view.widgets.cut(x, n) return wrap("cut", x, n) end

-- Groups of instances (or text):
--   first(a, b, ...)   the first with text ("TCK 12", else "TCK --")
--   join(a, b, ...)    those with text, run together
--   spaced(a, b, ...)  those with text, a space between; nil if none
--   lit(text, style)   fixed text, in a style
local function kids(...)
  local list = {}
  for n = 1, select("#", ...) do
    local x = select(n, ...)
    if type(x) == "string" then
      local s = x
      x = inst({ def = { type = "literal", compose = function() return s end }, inputs = {}, s = s })
    end
    if not isinst(x) then fail("expected widgets or text, got " .. type(x), 3) end
    list[#list + 1] = x
  end
  return list
end
local function group(kind, sep, ...)
  return inst({ def = { type = kind, compose = function(i)
    local out = {}
    for _, c in ipairs(i.children) do
      if c.out ~= nil then
        if kind == "first" then return c.out end
        if c.out ~= "" or kind == "join" then out[#out + 1] = c.out end
      end
    end
    if kind == "first" or #out == 0 then return nil end
    return table.concat(out, sep)
  end }, inputs = {}, children = kids(...) })
end
function view.widgets.first(...) return group("first", "", ...) end
function view.widgets.join(...) return group("join", "", ...) end
function view.widgets.spaced(...) return group("spaced", " ", ...) end
function view.widgets.lit(s, style)
  return inst({ def = { type = "lit", compose = function() return style and view.style(style, s) or s end },
                inputs = {}, s = s, style = style })
end

-- later(fn): the widget fn() returns, built at the first pass - when every
-- module has loaded, so a pane can name data from modules loaded after it.
-- Data no module provides: nothing (left out; debug view says why); a
-- module providing data later (an area's) brings another try
function view.widgets.later(fn)
  return inst({ def = { type = "later", compose = function(i)
    local c = i.children and i.children[1]
    return c and c.out
  end }, inputs = {}, build = fn })
end

-- calls(list, sep): functions called on every pass, their text joined (nil
-- if none has any) - the status rows' segments from modules not moved to
-- data yet. No saving: they cost what they did before
function view.widgets.calls(list, sep)
  return inst({ always = true, def = { type = "calls", compose = function()
    local out = {}
    for _, f in ipairs(list) do
      local s = f()
      if s ~= nil and s ~= "" then out[#out + 1] = s end
    end
    if #out == 0 then return nil end
    return table.concat(out, sep or " ")
  end }, inputs = {}, list = list, sep = sep or " " })
end


-- Generated code: each instance in a bar becomes one Lua function, built
-- at its first pass with load() (panes still use draw, above, for now). A clean instance returns its saved text after a flag
-- check; a dirty one runs straight-line code - no tree walk, no stamps
-- Off if this Lua can't load code from a string: the tree draw instead
local loadstr = loadstring or load
do
  local ok, f = pcall(loadstr, "return 1")
  view.gen_on = ok and type(f) == "function" and f() == 1
end
local function q(x) return string.format("%q", x) end

-- the code for a ref's value that may be nil: lines that set a local,
-- nothing returned early (custom widgets' inputs, a line's by, clock keys)
local function row_read(t, ctx)
  if not ctx.rowk then ctx.k[#ctx.k + 1] = ROW; ctx.rowk = #ctx.k end
  return "K[" .. ctx.rowk .. "][" .. q(t.list) .. "]"
end
local function opt_code(r, ctx, lines)
  ctx.omemo = ctx.omemo or {}
  if ctx.omemo[r] then return ctx.omemo[r] end
  local t = R[r]
  ctx.n = ctx.n + 1
  local v = "o" .. ctx.n
  if t.kind == "data" and getters[t.name] then
    ctx.f[#ctx.f + 1] = getters[t.name]
    lines[#lines + 1] = "local " .. v .. " = F[" .. #ctx.f .. "]()"
  elseif t.kind == "data" then
    lines[#lines + 1] = "local " .. v .. " = S[" .. string.format("%q", t.name) .. "]"
  elseif t.kind == "const" then
    ctx.k[#ctx.k + 1] = t.value
    lines[#lines + 1] = "local " .. v .. " = K[" .. #ctx.k .. "]"
  elseif t.kind == "row" then
    lines[#lines + 1] = "local " .. v .. " = " .. row_read(t, ctx) .. "; " .. v .. " = " .. v .. " and " .. v .. "[" .. q(t.field) .. "]"
  else
    local args, test = {}, {}
    if t.kind == "field" then args[1] = opt_code(t.parent, ctx, lines)
    else for i, x in ipairs(t.inputs) do args[i] = opt_code(x, ctx, lines) end end
    local call
    if t.code then call = t.code(unpack(args, 1, #args))
    else ctx.f[#ctx.f + 1] = t.fn; call = "F[" .. #ctx.f .. "](" .. table.concat(args, ", ") .. ")" end
    if t.nils then
      lines[#lines + 1] = "local " .. v .. " = " .. call
    elseif t.code then
      for i, a in ipairs(args) do test[i] = a .. " ~= nil" end
      lines[#lines + 1] = "local " .. v .. "; if " .. table.concat(test, " and ") .. " then " .. v .. " = " .. call .. " end"
    else
      for i, a in ipairs(args) do test[i] = a .. " ~= nil" end
      lines[#lines + 1] = "local " .. v .. "; if " .. table.concat(test, " and ") .. " then " .. v
        .. " = F[" .. #ctx.f .. "](" .. table.concat(args, ", ") .. ") end"
    end
  end
  ctx.omemo[r] = v
  return v
end

-- A group's children, then its text - saved, and handed back as it was
-- when no child's text changed (a group the clock reaches each second)
local function group_code(calls, test, sep, ctx, lines)
  ctx.k[#ctx.k + 1] = {}
  local P = "K[" .. #ctx.k .. "]"
  local xs, same, keep = {}, {}, {}
  for k, call in ipairs(calls) do
    ctx.n = ctx.n + 1
    xs[k] = "x" .. ctx.n
    lines[#lines + 1] = "local " .. xs[k] .. " = " .. call
    same[k] = xs[k] .. " == P[" .. k .. "]"
    keep[k] = "P[" .. k .. "] = " .. xs[k]
  end
  if ctx.flat then   -- nothing read back: P only written
    lines[#lines + 1] = "local P = " .. P
  else
    lines[#lines + 1] = "local P = " .. P
    if #xs > 0 then
      lines[#lines + 1] = "if P.d and " .. table.concat(same, " and ") .. " then return P.out end"
      lines[#lines + 1] = table.concat(keep, "; ")
    end
    lines[#lines + 1] = "P.d = true"
  end
  if sep == "" and #xs > 0 then   -- join: run together straight, nil only when all are
    local any, cat = {}, {}
    for k, x in ipairs(xs) do any[k] = x .. " ~= nil"; cat[k] = "(" .. x .. " or \"\")" end
    lines[#lines + 1] = "local r = nil"
    lines[#lines + 1] = "if " .. table.concat(any, " or ") .. " then r = " .. table.concat(cat, " .. ") .. " end"
    if not ctx.flat then lines[#lines + 1] = "P.out = r" end
    return "r"
  end
  lines[#lines + 1] = "local o, n = {}, 0"
  for _, x in ipairs(xs) do
    lines[#lines + 1] = "if " .. test(x) .. " then n = n + 1; o[n] = " .. x .. " end"
  end
  lines[#lines + 1] = "local r = n > 0 and concat(o, " .. string.format("%q", sep) .. ") or nil"
  lines[#lines + 1] = "P.out = r"
  return "r"
end

-- the code for a ref's value: lines that set local `name`, and return nil if it's nil
local function ref_code(r, ctx, lines)
  ctx.memo = ctx.memo or {}
  if ctx.memo[r] then return ctx.memo[r] end
  local t = R[r]
  ctx.n = ctx.n + 1
  local v = "v" .. ctx.n
  if t.kind == "data" and getters[t.name] then
    ctx.f[#ctx.f + 1] = getters[t.name]
    lines[#lines + 1] = "local " .. v .. " = F[" .. #ctx.f .. "]()"
  elseif t.kind == "data" then
    lines[#lines + 1] = "local " .. v .. " = S[" .. q(t.name) .. "]"
  elseif t.kind == "const" then
    ctx.k[#ctx.k + 1] = t.value
    lines[#lines + 1] = "local " .. v .. " = K[" .. #ctx.k .. "]"
  elseif t.kind == "row" then
    lines[#lines + 1] = "local " .. v .. " = " .. row_read(t, ctx) .. "; " .. v .. " = " .. v .. " and " .. v .. "[" .. q(t.field) .. "]"
  elseif t.kind == "field" then
    local pv = ref_code(t.parent, ctx, lines)
    ctx.f[#ctx.f + 1] = t.fn
    lines[#lines + 1] = "local " .. v .. " = F[" .. #ctx.f .. "](" .. pv .. ")"
  else
    local args = {}
    for i, x in ipairs(t.inputs) do args[i] = t.nils and opt_code(x, ctx, lines) or ref_code(x, ctx, lines) end
    ctx.f[#ctx.f + 1] = t.fn
    lines[#lines + 1] = "local " .. v .. " = F[" .. #ctx.f .. "](" .. table.concat(args, ", ") .. ")"
  end
  -- nil: no text - or, in a case, on to the next case (cases sets nilret)
  lines[#lines + 1] = "if " .. v .. " == nil then " .. (ctx.nilret or "return nil") .. " end"
  ctx.memo[r] = v
  return v
end

-- A style applied in generated code: none - the text; fixed - its codes
-- around the text, inline; rules - its function, bound when the code is
-- built (a style change builds the code again)
local function style_code(name, sx, vx, ctx)
  local spec = styles[name]
  if spec == nil then return sx end
  local on, off = own_off(spec)
  if on then return "(" .. q(on) .. " .. " .. sx .. " .. " .. q(off) .. ")" end
  local fixed = code_of(spec)
  if fixed == "" then return sx end
  if fixed then return "(" .. q(fixed) .. " .. " .. sx .. " .. " .. q(RESET) .. ")" end
  ctx.f[#ctx.f + 1] = style_fn(name)
  return "F[" .. #ctx.f .. "](" .. sx .. ", " .. vx .. ")"
end
-- filters whose text comes from the value alone (the default text unused)
local FROM_VALUE = { [FILTERS.mmss] = true, [FILTERS.clock] = true, [FILTERS.commas] = true, [FILTERS.dur] = true, [FILTERS.num] = true }
local gen   -- gen(i) -> function() returning the instance's text or nil
-- pad code for x to n columns, given what's known of its width now (lo:
-- at least, ex: exactly, or nil): nothing when it's wide enough already, the
-- spaces as a literal when its width is known, else measured when drawn.
-- Returns the width known after it
local function pad_code(lines, x, n, lo, ex)
  n = tonumber(n) or 0
  if ex then
    if ex < n then lines[#lines + 1] = x .. " = " .. x .. " .. " .. q(string.rep(" ", n - ex)) end
    return math.max(lo, n), math.max(ex, n)
  end
  if lo < n then
    lines[#lines + 1] = "do local w = WIDTH(" .. x .. ") if w < " .. n .. " then " .. x .. " = " .. x .. " .. rep(\" \", " .. n .. " - w) end end"
  end
  return math.max(lo, n), nil
end
local function body_text(i, ctx, lines)
  local st = i.settings
  local parts = {}
  local tlo, tex = 0, 0   -- the line's width: at least, exactly (nil: not known)
  for k, part in ipairs(st.parts) do
    if type(part) == "string" then
      parts[#parts + 1] = q(part)
      tlo = tlo + width(part); if tex then tex = tex + width(part) end
    else
      local lo, ex = 0, nil   -- this value's width
      local v = ref_code(i.inputs[part.input], ctx, lines)
      ctx.n = ctx.n + 1
      local sv = "s" .. ctx.n
      -- the default text, unless the first filter makes its own from the value
      local first = part.filters[1] and part.filters[1][1]
      if first == FILTERS.fixed then
        lines[#lines + 1] = "local " .. sv .. " = type(" .. v .. ") == \"number\" and format(" .. q("%." .. (tonumber(part.filters[1][2]) or 0) .. "f") .. ", " .. v .. ") or tostring(" .. v .. ")"
      elseif first == FILTERS.as then
        lines[#lines + 1] = "local " .. sv .. " = " .. q(part.filters[1][2] or "")
        ex = width(part.filters[1][2] or ""); lo = ex
      elseif first == FILTERS.mmss then
        lines[#lines + 1] = "local " .. sv .. " = type(" .. v .. ") ~= \"number\" and tostring(" .. v .. ") or " .. v
          .. " > 5999 and \"99:99\" or format(\"%02d:%02d\", FLOOR(" .. v .. " / 60), " .. v .. " % 60)"
      elseif first == FILTERS.clock then
        lines[#lines + 1] = "local " .. sv .. " = type(" .. v .. ") ~= \"number\" and tostring(" .. v .. ") or " .. v
          .. " >= 6000 and \">100m\" or format(\"%d:%02d\", FLOOR(" .. v .. " / 60), " .. v .. " % 60)"
      elseif first and FROM_VALUE[first] then
        ctx.f[#ctx.f + 1] = first
        lines[#lines + 1] = "local " .. sv .. " = F[" .. #ctx.f .. "](nil, " .. v .. ", " .. (part.filters[1][2] and q(part.filters[1][2]) or "nil") .. ")"
      else
        lines[#lines + 1] = "local " .. sv .. " = type(" .. v .. ") == \"number\" and FMT(" .. v .. ") or tostring(" .. v .. ")"
      end
      for fi, f in ipairs(part.filters) do
       if not (fi == 1 and (first == FILTERS.fixed or first == FILTERS.as or FROM_VALUE[first])) then
        local fn, arg = f[1], f[2]
        if fn == FILTERS.fixed then
          lines[#lines + 1] = "if type(" .. v .. ") == \"number\" then " .. sv .. " = format(" .. q("%." .. (tonumber(arg) or 0) .. "f") .. ", " .. v .. ") end"
        elseif fn == FILTERS.pad then
          lo, ex = pad_code(lines, sv, arg, lo, ex)
        elseif fn == FILTERS.rpad then
          local n = tonumber(arg) or 0
          if ex then
            if ex < n then lines[#lines + 1] = sv .. " = " .. q(string.rep(" ", n - ex)) .. " .. " .. sv end
            lo, ex = math.max(lo, n), math.max(ex, n)
          elseif lo < n then
            lines[#lines + 1] = "do local w = WIDTH(" .. sv .. ") if w < " .. n .. " then " .. sv .. " = rep(\" \", " .. n .. " - w) .. " .. sv .. " end end"
            lo = n
          end
        elseif fn == FILTERS.style then
          lines[#lines + 1] = sv .. " = " .. style_code(arg, sv, v, ctx)   -- codes only: no columns
        elseif fn == FILTERS.as then
          lines[#lines + 1] = sv .. " = " .. q(arg or "")
          ex = width(arg or ""); lo = ex
        else
          ctx.f[#ctx.f + 1] = fn
          lines[#lines + 1] = sv .. " = F[" .. #ctx.f .. "](" .. sv .. ", " .. v .. ", " .. (arg and q(arg) or "nil") .. ")"
          if fn == FILTERS.after then lo = lo + width(arg or ""); ex = ex and ex + width(arg or "")
          else lo, ex = 0, nil end
        end
       end
      end
      parts[#parts + 1] = sv
      tlo = tlo + lo; tex = tex and ex and tex + ex
    end
  end
  ctx.wlo, ctx.wex = tlo, tex
  local line = #parts > 0 and table.concat(parts, " .. ") or '""'
  if st.style then
    -- by may be nil (the text shows, unstyled): not ref_code, which ends the
    -- text at a nil - unless the template already needed it
    local by = "nil"
    if st.by then
      by = (ctx.memo and ctx.memo[st.by]) or opt_code(st.by, ctx, lines)
    end
    return style_code(st.style, line, by, ctx)
  end
  return line
end

local function body(i, ctx, lines)
  local ty = i.def.type
  if ty == "text" then return body_text(i, ctx, lines) end
  if ty == "literal" then return q(i.s) end
  if ty == "lit" then return i.style and style_code(i.style, q(i.s), "nil", ctx) or q(i.s) end
  local kids = i.children or {}
  -- Fusion: a fixed child, or the only one that changes (its parent is
  -- dirty whenever it is), runs as part of its parent - its own code, no
  -- cache of its own to check. Not a clock widget (it may say it's idle)
  local fuse
  if ty == "pad" or ty == "cut" or ty == "first" or ty == "join" or ty == "spaced" or ty == "later" then
    local var
    for _, c in ipairs(kids) do
      if not (c.def.type == "literal" or c.def.type == "lit") then
        if var then var = false; break end
        var = c
      end
    end
    if var and not var.dyn and not var.clock then fuse = var end
  end
  local function kid(c)
    if ctx.flat then   -- a list's row: every child's own code, called straight
      ctx.c[#ctx.c + 1] = gen(c, true)
      return "C[" .. #ctx.c .. "]()"
    end
    gen(c)
    if c == fuse or c.def.type == "literal" or c.def.type == "lit" then
      ctx.c[#ctx.c + 1] = c.raw
      if c == fuse then i.fused = c end
    else
      ctx.c[#ctx.c + 1] = c.fn
    end
    return "C[" .. #ctx.c .. "]()"
  end
  if ty == "pad" or ty == "cut" then
    local k = kid(kids[1])
    lines[#lines + 1] = "local x = " .. k
    lines[#lines + 1] = "if x == nil then return nil end"
    if ty == "pad" then
      lines[#lines + 1] = "do local w = WIDTH(x) if w < " .. i.n .. " then x = x .. rep(\" \", " .. i.n .. " - w) end end"
      return "x"
    end
    ctx.f[#ctx.f + 1] = FILTERS.cut
    return "F[" .. #ctx.f .. "](x, nil, " .. i.n .. ")"
  end
  if ty == "first" or ty == "later" then
    for _, c in ipairs(kids) do
      lines[#lines + 1] = "do local x = " .. kid(c) .. " if x ~= nil then return x end end"
    end
    return "nil"
  end
  if ty == "join" or ty == "spaced" then
    local calls = {}
    for k, c in ipairs(kids) do calls[k] = kid(c) end
    local test = ty == "join" and function(x) return x .. " ~= nil" end
      or function(x) return x .. " ~= nil and " .. x .. " ~= \"\"" end
    return group_code(calls, test, ty == "spaced" and " " or "", ctx, lines)
  end
  if ty == "calls" then
    ctx.k[#ctx.k + 1] = i.list
    lines[#lines + 1] = "local o, n, L = {}, 0, K[" .. #ctx.k .. "]"
    lines[#lines + 1] = "for k = 1, #L do local x = L[k]() if x ~= nil and x ~= \"\" then n = n + 1; o[n] = x end end"
    lines[#lines + 1] = "if n == 0 then return nil end"
    return "concat(o, " .. q(i.sep) .. ")"
  end
  if ty == "cases" then
    -- the tests first (each a local, true or false), then each case in a
    -- block a missing value leaves for the next case
    -- each case's test and values worked out only when it's reached (the
    -- first that holds ends it); the clock inputs come from the key check
    local top = {}
    for r, v in pairs(ctx.omemo or {}) do top[r] = v end
    for k, c in ipairs(i.cases) do
      ctx.memo, ctx.omemo, ctx.nilret = {}, setmetatable({}, { __index = top }), "break"
      lines[#lines + 1] = "repeat"
      if c.test then
        local tv = opt_code(c.test, ctx, lines)   -- its lines first, then the check
        lines[#lines + 1] = "if not " .. tv .. " then break end"
      end
      ctx.n = ctx.n + 1
      local x = "c" .. ctx.n
      if c.w then   -- a widget: its own code, called; nil moves on
        ctx.c[#ctx.c + 1] = gen(c.w, ctx.flat)
        lines[#lines + 1] = "local " .. x .. " = C[" .. #ctx.c .. "]()"
        lines[#lines + 1] = "if " .. x .. " == nil then break end"
        ctx.wlo, ctx.wex = 0, nil
      else
        for _, r in ipairs(c.inputs) do
          local v = opt_code(r, ctx, lines)
          lines[#lines + 1] = "if " .. v .. " == nil then break end"
          ctx.memo[r] = v
        end
        -- the template, its width, then its style
        local line = body_text({ settings = { parts = c.parts }, inputs = c.inputs }, ctx, lines)
        lines[#lines + 1] = "local " .. x .. " = " .. line
      end
      local lo, ex = ctx.wlo, ctx.wex   -- the template's width, as far as known
      if c.width then lo, ex = pad_code(lines, x, c.width, lo, ex) end
      if c.style then
        local by = c.by and ((ctx.memo and ctx.memo[c.by]) or opt_code(c.by, ctx, lines)) or "nil"
        lines[#lines + 1] = x .. " = " .. style_code(c.style, x, by, ctx)
      end
      if i.pad then pad_code(lines, x, i.pad, lo, ex) end   -- a style adds no columns
      lines[#lines + 1] = "do return " .. q(i.prefix) .. " .. " .. x .. " end"
      lines[#lines + 1] = "until true"
    end
    ctx.memo, ctx.omemo, ctx.nilret = nil, top, nil
    return "nil"
  end
  if ty == "custom" or i.render then
    local args = {}
    for k, r in ipairs(i.inputs) do args[k] = opt_code(r, ctx, lines) end
    ctx.k[#ctx.k + 1] = i
    lines[#lines + 1] = "local I = K[" .. #ctx.k .. "]"
    return "I.render(I.st" .. (args[1] and (", " .. table.concat(args, ", ")) or "") .. ")"
  end
  if ty == "slot" then
    local calls = {}
    for k, x in ipairs(i.list) do
      if isinst(x) then calls[k] = kid(x) else ctx.f[#ctx.f + 1] = x; calls[k] = "F[" .. #ctx.f .. "]()" end
    end
    return group_code(calls, function(x) return x .. " ~= nil and " .. x .. " ~= \"\"" end, i.sep, ctx, lines)
  end
  -- a render widget (rag, meter ...): its own render on its input's value
  local v = ref_code(i.input, ctx, lines)
  ctx.k[#ctx.k + 1] = i
  ctx.f[#ctx.f + 1] = i.def.render
  lines[#lines + 1] = "local I = K[" .. #ctx.k .. "]"
  return "F[" .. #ctx.f .. "](I.settings, " .. v .. ", CTX(I.def))"
end

-- flat: for a list's rows - the code alone, no cache (everything in a row
-- is built again for each row), children called straight
gen = function(i, flat)
  if flat then
    if i.flatfn then return i.flatfn end
  elseif i.fn then return i.fn end
  if i.dyn == nil then flags(i) end
  local ctx = { n = 0, f = {}, k = {}, c = {}, flat = flat }
  local lines = {}
  -- its own clock inputs: worked out by the key check just before (keys),
  -- read from there, not again
  local keys = {}
  if i.tin and not i.dyn and not flat then
    ctx.omemo = {}
    for k, r in ipairs(i.tin) do ctx.omemo[r] = "KY[" .. k .. "]" end
  end
  local ret = body(i, ctx, lines)
  local src = "local S, F, K, C, STYLE, FMT, WIDTH, CTX, format, rep, concat, VAL, CS, SF, KY, FLOOR = ...\nreturn function()\n"
    .. table.concat(lines, "\n") .. "\nreturn " .. ret .. "\nend"
  local chunk, err = loadstr(src, "=view:" .. i.def.type)
  if not chunk then error("generated code for " .. i.def.type .. " didn't load: " .. tostring(err)) end
  local raw = chunk(store, ctx.f, ctx.k, ctx.c, view.style, fmtnum, width, ctx_for,
    string.format, string.rep, table.concat, value, compiled, style_fn, keys, math.floor)
  if flat then i.flatfn, i.flatsrc = raw, src; return raw end
  i.src, i.raw = src, raw
  -- a fused child's clock inputs are its parent's to compare - into the
  -- child's keys, which its code reads
  if i.fused and i.fused.tin and not i.tin then i.tin, keys = i.fused.tin, i.fused.keys end
  i.keys = keys
  -- the clock inputs' values, compared with the last and kept: true if all the same
  local keyf
  if i.tin then
    local kctx, kl = { n = 0, f = {}, k = {}, c = {} }, {}
    kl[#kl + 1] = "local same = true"
    for k, r in ipairs(i.tin) do
      local v = opt_code(r, kctx, kl)
      kl[#kl + 1] = "if " .. v .. " ~= keys[" .. k .. "] then same = false; keys[" .. k .. "] = " .. v .. " end"
    end
    local ksrc = "local S, F, K = ...\nreturn function(keys)\n" .. table.concat(kl, "\n") .. "\nreturn same\nend"
    local kchunk, kerr = loadstr(ksrc, "=view:keys")
    if not kchunk then error("generated keys for " .. i.def.type .. " didn't load: " .. tostring(kerr)) end
    keyf = kchunk(store, kctx.f, kctx.k)
  end
  if i.dyn then
    i.fn = raw
  else
    i.fn = function()
      local keyed = false
      if i.drawn and not i.dirty and i.gen == style_gen then
        if not i.timed or i.idle then return i.out end
        local now = view.clock()
        if i.tnow == now then return i.out end
        i.tnow = now
        if keyf then
          if keyf(keys) then return i.out end
          keyed = true
        end
      end
      i.dirty = false
      i.gen = style_gen
      if i.timed then i.tnow = view.clock() end
      -- the clock inputs now (raw reads them from keys)
      if keyf and not keyed then keyf(keys) end
      local out, live = raw()
      -- a clock widget that said the clock doesn't matter now (false):
      -- not rebuilt on new seconds until its data changes
      i.idle = i.clock and live == false
      i.out, i.drawn = out, true
      i.rebuilt = (i.rebuilt or 0) + 1
      return out
    end
  end
  return i.fn
end
view.gen = gen

-- custom(type, { inputs = { names or refs }, clock = bool }, render):
-- a developer's widget for one module's segment - render(st, value, ...)
-- returns the text; st(slot, text, value) styles it with the user's style
-- "<type>.<slot>". Rebuilt when an input changes (a clock input when its
-- value does), or each new second with clock = true - unless render
-- returned false after the text (nothing moving: REC with no log open),
-- then not until an input changes. Inputs may be nil
function view.widgets.custom(wtype, spec, render)
  local refs = {}
  for k, x in ipairs(spec.inputs or {}) do refs[k] = type(x) == "string" and view.ref(x) or asref(x) end
  local i = inst({ def = { type = wtype, compose = function(i)
    local v = {}
    for k, r in ipairs(i.inputs) do v[k] = value(r) end
    return i.render(i.st, unpack(v, 1, #i.inputs))
  end }, inputs = refs, render = render, clock = spec.clock })
  i.st = function(slot, text, v) return view.style(wtype .. "." .. slot, text, v) end
  return i
end

-- slot(list[, sep]): a list other modules add to (view.slot_add) - widgets,
-- or functions called on every pass (segments not moved to data yet); those
-- with text, sep (" ") between
function view.widgets.slot(list, sep)
  return inst({ def = { type = "slot", compose = function(i)
    local out = {}
    for _, x in ipairs(i.list) do
      local t
      if isinst(x) then t = draw(x) else t = x() end
      if t ~= nil and t ~= "" then out[#out + 1] = t end
    end
    if #out == 0 then return nil end
    return table.concat(out, i.sep)
  end }, inputs = {}, list = list, sep = sep or " " })
end
-- Add to a slot's list (pos as table.insert's): its bars are built again
function view.slot_add(list, item, pos)
  if pos then table.insert(list, pos, item) else list[#list + 1] = item end
  restructure = true
  request()
end

-- While a pane with a size draws: the lines left below what's above (a
-- list fills them) and its width (a list's columns, a banner)
local pane_room, pane_w

-- list(name, { row = widget, sort = { ref, ... }, key = ref, width = n,
-- gap = "  " }): list data, a line per row - row is a widget on the row's
-- fields (view.row(name)) and any other data. sort: ascending by each in
-- turn (false before true, nil last), then the list's order. Rows go in
-- columns of width n (gap between) as many as the pane's width takes, each
-- as high as the lines left; one column (every row) when two don't fit.
-- Text is built only for the rows shown, and kept per row (by key, else
-- position): built again only when a field it shows changed, or data
-- outside the row it shows, or a style. Redrawn when the list, the pane's
-- size or that outside data changed
local function sortval(v)
  if v == nil then return math.huge end
  if v == true then return 1 elseif v == false then return 0 end
  return v
end
local function insts_of(i, into)
  into[#into + 1] = i
  for _, c in ipairs(i.children or {}) do insts_of(c, into) end
  for _, c in ipairs(i.cases or {}) do if c.w then insts_of(c.w, into) end end
  return into
end
function view.widgets.list(name, opts)
  opts = opts or {}
  local src = view.ref(name)
  local row = opts.row
  if not isinst(row) then fail("list: row = a widget", 2) end
  local sorts = {}
  for k, x in ipairs(opts.sort or {}) do sorts[k] = aref(x) end
  local key = opts.key and aref(opts.key)
  -- what a row's text depends on: the row's fields, and data outside it
  local fields, ext, seenf, seene = {}, {}, {}, {}
  local function walk(x)
    local t = R[x]
    if t.kind == "row" then
      if t.list ~= name then fail("list " .. name .. ": its row shows another list's row (" .. t.label .. ")", 4) end
      if not seenf[t.field] then seenf[t.field] = true; fields[#fields + 1] = t.field end
    elseif t.kind == "data" then
      if not seene[t.name] and t.name ~= name then seene[t.name] = true; ext[#ext + 1] = t.name end
    elseif t.kind == "field" then walk(t.parent)
    elseif t.kind == "derived" then for _, y in ipairs(t.inputs) do walk(y) end end
  end
  for _, x in ipairs(refs_of(row, {})) do walk(x) end
  local inputs = { src }
  for _, n in ipairs(ext) do inputs[#inputs + 1] = view.ref(n) end
  local ns, nf, ne = #sorts, #fields, #ext
  local tree = insts_of(row, {})
  local cw, gap = opts.width, opts.gap or "  "
  local function less(a, b)
    for k = 1, ns do
      local x, y = a[k], b[k]
      if x ~= y then return x < y end
    end
    return a.i < b.i
  end
  -- the row's code and the sort values' (built at the first draw; not
  -- built: drawn the slow way)
  local rowfn, sortf
  local function build()
    rowfn, sortf = false, false
    if not view.gen_on then return end
    local ok, f = pcall(gen, row, true)
    if ok then rowfn = f else deps(); util.warn("[view] list " .. name .. ": " .. tostring(f) .. " - drawn the slow way") end
    if ns == 0 then return end
    local ctx, lines = { n = 0, f = {}, k = {}, c = {} }, {}
    for k, x in ipairs(sorts) do
      local v = opt_code(x, ctx, lines)
      lines[#lines + 1] = "e[" .. k .. "] = SV(" .. v .. ")"
    end
    local chunk = loadstr("local S, F, K, SV, FLOOR = ...\nreturn function(e)\n" .. table.concat(lines, "\n") .. "\nend", "=view:sort")
    if chunk then sortf = chunk(store, ctx.f, ctx.k, sortval, floor) end
  end
  return inst({ always = true, def = { type = "list", compose = function(i)
    if i.bgen ~= style_gen then   -- the code holds the styles' codes: built again
      for _, x in ipairs(tree) do x.flatfn = nil end
      rowfn, i.bgen = nil, style_gen
    end
    if rowfn == nil then build() end
    local list = value(src)
    if type(list) ~= "table" then i.mst = nil; return nil end
    local st = stamp(src)
    local same = i.mst == st and i.mroom == pane_room and i.mw == pane_w and i.mgen == style_gen
    local ev, outside = i.ev, false
    for k = 1, ne do
      local v = view.get(ext[k])
      if ev[k] ~= v then outside = true; ev[k] = v end
    end
    if same and not outside then return i.out end
    if outside or i.mgen ~= style_gen then i.cache = {} end
    i.mst, i.mroom, i.mw, i.mgen = st, pane_room, pane_w, style_gen
    local n = #list
    if n == 0 then return nil end
    -- each row's sort values, then the sort
    local rows, pool = i.rows, i.pool
    for k = n + 1, #rows do rows[k] = nil end
    for k = 1, n do
      local e = pool[k]
      if not e then e = {}; pool[k] = e end
      local rec = list[k]
      ROW[name] = rec
      e.rec, e.i = rec, k
      if sortf then sortf(e) else for s = 1, ns do e[s] = sortval(value(sorts[s])) end end
      if key then e.key = value(key) else e.key = k end
      rows[k] = e
    end
    if ns > 0 then table.sort(rows, less) end
    -- the columns
    local ncols, h = 1, n
    if cw and pane_w then ncols = floor((pane_w + #gap) / (cw + #gap)) end
    if ncols < 2 then ncols = 1 else h = math.max(pane_room or n, 1) end
    local shown = math.min(n, ncols * h)
    local cache, dg = i.cache, (i.dg or 0) + 1
    i.dg = dg
    local function cell(e)
      local rec, c = e.rec, cache[e.key]
      if c then
        local ok = true
        for f = 1, nf do if c[f] ~= rec[fields[f]] then ok = false; break end end
        if ok then c.seen = dg; return c end
      else
        c = {}; cache[e.key] = c
      end
      ROW[name] = rec
      rowver[name] = (rowver[name] or 0) + 1
      if not rowfn then for _, x in ipairs(tree) do x.dirty = true end end
      local t
      if rowfn then t = rowfn() else t = draw(row) end
      c.text, c.padded = t or "", nil
      for f = 1, nf do c[f] = rec[fields[f]] end
      c.seen = dg
      return c
    end
    local out = {}
    for line = 1, math.min(h, shown) do
      local parts = {}
      for col = 0, ncols - 1 do
        local k = line + col * h
        if k > shown then break end
        parts[#parts + 1] = cell(rows[k])
      end
      local np = #parts
      for k = 1, np do
        local c = parts[k]
        if k < np and cw then
          if not c.padded then c.padded = FILTERS.pad(c.text, nil, cw) end
          parts[k] = c.padded
        else
          parts[k] = c.text
        end
      end
      out[line] = table.concat(parts, gap)
    end
    ROW[name] = nil
    for k, c in pairs(cache) do if c.seen ~= dg then cache[k] = nil end end
    return table.concat(out, "\n")
  end }, inputs = inputs, rows = {}, pool = {}, cache = {}, ev = {} })
end

-- banner(x, { style = name, fill = name }): text (a game's colored text
-- too) across the pane's width: in style's color where it sets none, cut
-- to the width and centered (an odd column over on the right), on fill's
-- background across the row. Nothing when x is nil or ""
function view.widgets.banner(x, opts)
  opts = opts or {}
  local src = aref(x)
  return inst({ always = true, def = { type = "banner", compose = function(i)
    local v = value(src)
    if v == nil or v == "" then i.mv = nil; return nil end
    local wd = pane_w or width(v)
    if i.mv == v and i.mw == wd and i.mgen == style_gen then return i.out end
    i.mv, i.mw, i.mgen = v, wd, style_gen
    deps()
    local on = opts.style and code_of(styles[opts.style]) or ""
    local fill = opts.fill and code_of(styles[opts.fill]) or ""
    local t = colors.crop(on .. v, wd)
    local pad = wd - colors.width(t)
    local left = floor(pad / 2)
    return fill .. string.rep(" ", left) .. t .. fill .. string.rep(" ", pad - left) .. RESET
  end }, inputs = { src } })
end

-- Panes and bars ----------------------------------------------------------
-- view.pane(name, { refresh = "change" | "every", every = n, pick = "stack" |
--   "priority", size = function() return lines, columns end, item, item,
--   ... })   items: instances or literal text; size: what a list or a
--   banner fills (checked at each pass - a resize shows at once)
-- view.bar(name, { left = { items }, right = { items } })
-- stack: the items with text, a line each (a pane) or run together (a bar
-- side); priority: the first item with text.

local panes, bars = {}, {}
local order = {}

local function items_of(spec)
  local list = {}
  for _, it in ipairs(spec) do
    if type(it) == "string" then
      local s = it
      it = inst({ def = { type = "literal", compose = function() return s end }, inputs = {}, s = s })
    end
    if not isinst(it) then fail("a pane or bar holds widgets or text, not a " .. type(it), 3) end
    list[#list + 1] = it
  end
  return list
end

local function compose(list, pick, sep)
  local out = {}
  for _, it in ipairs(list) do
    local s = draw(it)
    if s ~= nil then
      if pick == "priority" then return s end
      out[#out + 1] = s
    end
  end
  if pick == "priority" then return "" end
  return table.concat(out, sep)
end

-- a pane with a size: each item told the lines left and the width
-- (each item's text the same string as at the last pass: the text shown,
-- not joined again)
local function compose_sized(p)
  pane_room, pane_w = p.size()
  local out, last, same = p.outs or {}, p.last or {}, p.text ~= nil
  local n = 0
  for _, it in ipairs(p.items) do
    local s = draw(it)
    if s ~= nil then
      n = n + 1
      out[n] = s
      if last[n] ~= s then same = false end
      if p.pick == "priority" then break end
      if s ~= it.lines_of then
        local _, nl = s:gsub("\n", "")
        it.lines_of, it.nlines = s, nl + 1
      end
      pane_room = pane_room - it.nlines
    end
  end
  pane_room, pane_w = nil, nil
  for k = n + 1, #out do out[k] = nil end
  if same and n == #last then return p.text end
  for k = 1, n do last[k] = out[k] end
  for k = n + 1, #last do last[k] = nil end
  p.outs, p.last = out, last
  p.text = table.concat(out, "\n")
  return p.text
end

local host        -- the bar whose render runs the pass (the first registered)
local function flush_safe()
  local ok, err = pcall(view.flush)
  if not ok then deps(); util.warn("[view] redraw failed: " .. tostring(err)) end
end
function view.pane(name, spec)
  -- shown "": an empty pane isn't written until it has something
  local p = { name = name, items = items_of(spec), refresh = spec.refresh or "change",
              every = spec.every, pick = spec.pick or "stack", size = spec.size, due = 0, shown = "" }
  if p.refresh == "every" and not (tonumber(p.every) and p.every > 0) then
    fail("pane " .. name .. ": refresh \"every\" needs every = seconds", 2)
  end
  if not panes[name] then order[#order + 1] = name end
  panes[name] = p
  -- panes before any view bar: a hidden bar runs the pass, never shown
  -- (it returns nothing; Rune disables a bar after 3 failures, so it never
  -- fails)
  if not host then
    host = "view_flush"
    if rune and rune.ui and rune.ui.bar then
      rune.ui.bar("view_flush", function() if host == "view_flush" then flush_safe() end; return nil end)
    end
  end
  request()
end

local bar_rows = {}
function view.bar(name, spec)
  local b = { name = name, left = items_of(spec.left or {}), right = items_of(spec.right or {}) }
  bars[name] = b
  -- the first view bar runs the pass - taking it over from the hidden bar
  -- if a pane came first (that one then returns nothing, doing nothing)
  if not host or host == "view_flush" then host = name end
  if rune and rune.ui and rune.ui.bar then
    rune.ui.bar(name, function()
      if host == name then flush_safe() end
      return bar_rows[name]
    end)
  end
  request()
end

-- The pass: every pane and bar due, each widget rebuilt only if changed
local passes = 0
-- After a slot_add: every bar's generated code goes, built again from the
-- (now longer) lists at this pass
local function forget(i)
  i.fn, i.dyn, i.drawn, i.flatfn = nil, nil, nil, nil
  if i.build then i.children = nil end
  for _, c in ipairs(i.children or {}) do forget(c) end
  for _, x in ipairs(i.list or {}) do if isinst(x) then forget(x) end end
end
function view.flush()
  requested = false
  for k = #armed, 1, -1 do armed[k](); armed[k] = nil end
  if restructure then
    restructure = false
    for _, b in pairs(bars) do
      b.lf, b.rf, b.nogen = nil, nil, nil
      for _, it in ipairs(b.left) do forget(it) end
      for _, it in ipairs(b.right) do forget(it) end
    end
  end
  passes = passes + 1
  deps()
  local now = view.clock()
  local t0 = dbg.on and os.clock()
  for _, name in ipairs(order) do
    local p = panes[name]
    if p and (p.refresh ~= "every" or now >= p.due) then
      if p.refresh == "every" then p.due = now + p.every end
      local text
      if p.size then text = compose_sized(p) else text = compose(p.items, p.pick, "\n") end
      if text ~= p.shown then
        p.shown = text
        deps(); util.pane(name, text)
      end
    end
  end
  for name, b in pairs(bars) do
    local l, r
    if view.gen_on and not b.nogen and not b.lf then
      local ok, err = pcall(function()
        b.lf = gen(view.widgets.join(unpack(b.left))); b.rf = gen(view.widgets.join(unpack(b.right)))
      end)
      if not ok then
        b.nogen, b.lf, b.rf = true, nil, nil
        deps(); util.warn("[view] bar " .. name .. ": " .. tostring(err) .. " - drawn the slow way")
      end
    end
    if b.lf then
      l, r = b.lf() or "", b.rf() or ""
    else
      l, r = compose(b.left, "stack", ""), compose(b.right, "stack", "")
    end
    local row = bar_rows[name]
    if not row or row.left ~= l or row.right ~= r then bar_rows[name] = { left = l, right = r } end
  end
  if t0 and dbg.on then
    local us = (os.clock() - t0) * 1e6
    if us > 50 then dbg.log(string.format("pass %d: %.0f us", passes, us)) end
  end
end

-- For tests and debug
function view._reset()
  decl, store, ver, subs, modules, dataref, watchers = {}, {}, {}, {}, {}, {}, {}
  getters = {}
  panes, bars, order, bar_rows, styles, compiled = {}, {}, {}, {}, {}, {}
  requested, passes, host = false, 0, nil
end

return view
