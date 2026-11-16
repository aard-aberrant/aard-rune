-- The display engine (require("core.view")): modules publish declared,
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
-- Widgets (developers): view.widget(type, def) - see the bottom.
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
  util = require("core.util")
  colors = require("core.colors")
  theme = require("core.theme")
  dbg = require("core.debug").topic("view", "the display engine: each publish, and each redraw with its cost")
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
view.shape("block", { desc = "text the game colored, several lines", check = function(v) return type(v) == "string" end })

-- Data --------------------------------------------------------------------

local decl = {}       -- data name -> { shape, desc, time, standard, module, fields }
local store = {}      -- data name -> value
local ver = {}        -- data name -> version, +1 at each set
local subs = {}       -- data name -> { fn, ... }
local modules = {}    -- module -> { desc, names = { ... } }
local requested = false
local watchers = {}    -- data name -> { instance = true }: what shows it, parents included

local function request()
  if requested then return end
  requested = true
  if rune and rune.ui and rune.ui.refresh_bars then rune.ui.refresh_bars() end
end

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
  local names = {}
  for name, d in pairs(decls or {}) do
    local shape = d[1]
    if not shapes[shape] then fail(module .. ": " .. name .. " has an unknown shape \"" .. tostring(shape) .. "\"", 2) end
    if decl[name] then
      fail(name .. " is provided by both " .. decl[name].module .. " and " .. module, 2)
    end
    decl[name] = { shape = shape, desc = d[2] or "", time = d.time, standard = d.standard,
                   fields = d.fields, module = module }
    ver[name] = 0
    names[#names + 1] = name
  end
  table.sort(names)
  modules[module] = { desc = desc or "", names = names }
  local S, pending = {}, {}
  function S.set(name, v)
    local d = decl[name]
    if not d or d.module ~= module then fail(module .. " doesn't provide " .. tostring(name), 2) end
    if view.dev and v ~= nil then
      local sh = shapes[d.shape]
      local s = d.shape
      while sh and not sh.check do s = sh.is; sh = shapes[s] end
      if sh and not sh.check(v) then
        deps(); util.warn("[view] " .. module .. " set " .. name .. " to a " .. type(v) .. ", not a " .. d.shape)
      end
    end
    local old = store[name]
    if old == v then return end
    if type(v) == "table" and type(old) == "table" and v.cur ~= nil and v.cur == old.cur and v.max == old.max then
      store[name] = v; return
    end
    store[name] = v
    ver[name] = ver[name] + 1
    local ws = watchers[name]
    if ws then for i in pairs(ws) do i.dirty = true end end
    if not pending[name] then pending[name] = true; pending[#pending + 1] = name end
    request()
  end
  function S.get(name) return store[name] end
  function S.publish()
    if #pending == 0 then return end
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
  for _, n in ipairs(m.names) do decl[n], store[n], subs[n] = nil, nil, nil; ver[n] = nil end
  modules[module] = nil
  request()
end

function view.get(name) return store[name] end
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
  if k == "data" then return store[t.name] end
  if k == "const" then return t.value end
  if k == "field" then
    local p = value(t.parent)
    if p == nil then return nil end
    return t.fn(p)
  end
  local args = {}
  for i, inp in ipairs(t.inputs) do
    args[i] = value(inp)
    if args[i] == nil then return nil end
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
  local s = 0
  for _, inp in ipairs(t.inputs) do s = s + stamp(inp) end
  return s
end

function view.shape_of(r) return R[asref(r)].shape end
function view.follows_clock(r) return R[asref(r)].time == true end

-- Helpers: derived refs from a fixed library ------------------------------

local function derived(label, shape, inputs, fn)
  local time = false
  for _, i in ipairs(inputs) do if R[i].time then time = true end end
  return mkref({ kind = "derived", shape = shape, inputs = inputs, fn = fn, time = time, label = label })
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
    function(x, y) if y ~= 0 then return x * 100 / y end end)
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
      function(x) if test(x, n) then return x end end)
  end
end
bound("below", function(x, n) return x < n end)
bound("above", function(x, n) return x > n end)
function helpers.round(a, places)
  a = asref(a)
  need(a, "number", "round", 1)
  local m = 10 ^ (places or 0)
  return derived("round(" .. R[a].label .. ")", R[a].shape, { a },
    function(x) return floor(x * m + 0.5) / m end)
end
view.helpers = helpers

-- Styles ------------------------------------------------------------------
-- The user's: name -> a palette name ("red"), a list of them mixed
-- ({ "bold", "red" }), or rules on a value
-- ({ { below = 20, "red" }, { below = 60, "yellow" }, "green" }).
-- Palette names are core/theme.lua's (data/theme.lua's changes apply); "plain" is no color.

local styles = {}
local compiled = {}   -- name -> fn(text, value) or false (unstyled)
local style_gen = 0   -- +1 at each view.styles: every widget redraws in the new colors
view.palette = function(name)
  deps()
  return theme[name]
end
function view.styles(t)
  styles, compiled = t or {}, {}
  style_gen = style_gen + 1
  request()
end
-- Styles added to the current ones (while panes move over one by one)
function view.add_styles(t)
  for k, v in pairs(t) do styles[k] = v end
  compiled = {}
  style_gen = style_gen + 1
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
local function compile(name)
  local spec = styles[name]
  if spec == nil then return false end
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
function view.style(name, s, v)
  local f = compiled[name]
  if f == nil then f = compile(name); compiled[name] = f end
  if not f then return s end
  return f(s, v)
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

local function width(s) deps(); return colors.width(s) end

-- ctx for render: ctx.style(slot, text, value) - the widget's own slots
local function ctx_for(def)
  return { style = function(slot, s, v) return view.style(def.type .. "." .. slot, s, v) end }
end

-- An instance's text now: rebuilt only when an input changed
-- At an instance's first draw: dyn (it or a child is redrawn on every
-- pass), timed (follows the clock), and the data names it shows - it's
-- marked dirty when one of them changes
local function names_of(r, into)
  local t = R[r]
  if t.kind == "data" then into[t.name] = true
  elseif t.kind == "field" then names_of(t.parent, into)
  elseif t.kind == "derived" then for _, x in ipairs(t.inputs) do names_of(x, into) end end
end
local function flags(i)
  local dyn, timed, names = i.always and true or false, false, {}
  for _, r in ipairs(i.inputs or {}) do
    if R[r].time then timed = true end
    names_of(r, names)
  end
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
  local changed = not i.drawn or i.gen ~= style_gen or i.always
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

-- the code for a ref's value: lines that set local `name`, and return nil if it's nil
local function ref_code(r, ctx, lines)
  ctx.memo = ctx.memo or {}
  if ctx.memo[r] then return ctx.memo[r] end
  local t = R[r]
  ctx.n = ctx.n + 1
  local v = "v" .. ctx.n
  if t.kind == "data" then
    lines[#lines + 1] = "local " .. v .. " = S[" .. q(t.name) .. "]"
  elseif t.kind == "const" then
    ctx.k[#ctx.k + 1] = t.value
    lines[#lines + 1] = "local " .. v .. " = K[" .. #ctx.k .. "]"
  elseif t.kind == "field" then
    local pv = ref_code(t.parent, ctx, lines)
    ctx.f[#ctx.f + 1] = t.fn
    lines[#lines + 1] = "local " .. v .. " = F[" .. #ctx.f .. "](" .. pv .. ")"
  else
    local args = {}
    for i, x in ipairs(t.inputs) do args[i] = ref_code(x, ctx, lines) end
    ctx.f[#ctx.f + 1] = t.fn
    lines[#lines + 1] = "local " .. v .. " = F[" .. #ctx.f .. "](" .. table.concat(args, ", ") .. ")"
  end
  lines[#lines + 1] = "if " .. v .. " == nil then return nil end"
  ctx.memo[r] = v
  return v
end

local gen   -- gen(i) -> function() returning the instance's text or nil
local function body_text(i, ctx, lines)
  local st = i.settings
  local parts = {}
  for k, part in ipairs(st.parts) do
    if type(part) == "string" then parts[#parts + 1] = q(part)
    else
      local v = ref_code(i.inputs[part.input], ctx, lines)
      ctx.n = ctx.n + 1
      local sv = "s" .. ctx.n
      lines[#lines + 1] = "local " .. sv .. " = type(" .. v .. ") == \"number\" and FMT(" .. v .. ") or tostring(" .. v .. ")"
      for _, f in ipairs(part.filters) do
        local fn, arg = f[1], f[2]
        if fn == FILTERS.fixed then
          lines[#lines + 1] = "if type(" .. v .. ") == \"number\" then " .. sv .. " = format(" .. q("%." .. (tonumber(arg) or 0) .. "f") .. ", " .. v .. ") end"
        elseif fn == FILTERS.pad then
          lines[#lines + 1] = "do local w = WIDTH(" .. sv .. ") if w < " .. (tonumber(arg) or 0) .. " then " .. sv .. " = " .. sv .. " .. rep(\" \", " .. (tonumber(arg) or 0) .. " - w) end end"
        elseif fn == FILTERS.style then
          lines[#lines + 1] = sv .. " = STYLE(" .. q(arg) .. ", " .. sv .. ", " .. v .. ")"
        elseif fn == FILTERS.as then
          lines[#lines + 1] = sv .. " = " .. q(arg or "")
        else
          ctx.f[#ctx.f + 1] = fn
          lines[#lines + 1] = sv .. " = F[" .. #ctx.f .. "](" .. sv .. ", " .. v .. ", " .. (arg and q(arg) or "nil") .. ")"
        end
      end
      parts[#parts + 1] = sv
    end
  end
  local line = #parts > 0 and table.concat(parts, " .. ") or '""'
  if st.style then
    -- by may be nil (the text shows, unstyled): not ref_code, which ends the
    -- text at a nil - unless the template already needed it
    local by = "nil"
    if st.by then
      if ctx.memo and ctx.memo[st.by] then by = ctx.memo[st.by]
      else ctx.k[#ctx.k + 1] = st.by; by = "VAL(K[" .. #ctx.k .. "])" end
    end
    return "STYLE(" .. q(st.style) .. ", " .. line .. ", " .. by .. ")"
  end
  return line
end

local function body(i, ctx, lines)
  local ty = i.def.type
  if ty == "text" then return body_text(i, ctx, lines) end
  if ty == "literal" then return q(i.s) end
  if ty == "lit" then return i.style and ("STYLE(" .. q(i.style) .. ", " .. q(i.s) .. ")") or q(i.s) end
  local kids = i.children or {}
  local function kid(c)
    ctx.c[#ctx.c + 1] = gen(c)
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
  if ty == "first" then
    for _, c in ipairs(kids) do
      lines[#lines + 1] = "do local x = " .. kid(c) .. " if x ~= nil then return x end end"
    end
    return "nil"
  end
  if ty == "join" or ty == "spaced" then
    local sep = ty == "spaced" and " " or ""
    lines[#lines + 1] = "local o, n = {}, 0"
    for _, c in ipairs(kids) do
      local test = ty == "join" and "x ~= nil" or "x ~= nil and x ~= \"\""
      lines[#lines + 1] = "do local x = " .. kid(c) .. " if " .. test .. " then n = n + 1; o[n] = x end end"
    end
    lines[#lines + 1] = "if n == 0 then return nil end"
    return "concat(o, " .. q(sep) .. ")"
  end
  if ty == "calls" then
    ctx.k[#ctx.k + 1] = i.list
    lines[#lines + 1] = "local o, n, L = {}, 0, K[" .. #ctx.k .. "]"
    lines[#lines + 1] = "for k = 1, #L do local x = L[k]() if x ~= nil and x ~= \"\" then n = n + 1; o[n] = x end end"
    lines[#lines + 1] = "if n == 0 then return nil end"
    return "concat(o, " .. q(i.sep) .. ")"
  end
  -- a render widget (rag, meter ...): its own render on its input's value
  local v = ref_code(i.input, ctx, lines)
  ctx.k[#ctx.k + 1] = i
  ctx.f[#ctx.f + 1] = i.def.render
  lines[#lines + 1] = "local I = K[" .. #ctx.k .. "]"
  return "F[" .. #ctx.f .. "](I.settings, " .. v .. ", CTX(I.def))"
end

gen = function(i)
  if i.fn then return i.fn end
  if i.dyn == nil then flags(i) end
  local ctx = { n = 0, f = {}, k = {}, c = {} }
  local lines = {}
  local ret = body(i, ctx, lines)
  local src = "local S, F, K, C, STYLE, FMT, WIDTH, CTX, format, rep, concat, VAL = ...\nreturn function()\n"
    .. table.concat(lines, "\n") .. "\nreturn " .. ret .. "\nend"
  local chunk, err = loadstr(src, "=view:" .. i.def.type)
  if not chunk then error("generated code for " .. i.def.type .. " didn't load: " .. tostring(err)) end
  local raw = chunk(store, ctx.f, ctx.k, ctx.c, view.style, fmtnum, width, ctx_for,
    string.format, string.rep, table.concat, value)
  i.src = src
  if i.dyn then
    i.fn = raw
  else
    i.fn = function()
      if i.drawn and not i.dirty and i.gen == style_gen and (not i.timed or i.tnow == view.clock()) then return i.out end
      i.dirty = false
      i.gen = style_gen
      if i.timed then i.tnow = view.clock() end
      local out = raw()
      i.out, i.drawn = out, true
      i.rebuilt = (i.rebuilt or 0) + 1
      return out
    end
  end
  return i.fn
end
view.gen = gen

-- Panes and bars ----------------------------------------------------------
-- view.pane(name, { refresh = "change" | "every", every = n, pick = "stack" |
--   "priority", item, item, ... })   items: instances or literal text
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

local host        -- the bar whose render runs the pass (the first registered)
local function flush_safe()
  local ok, err = pcall(view.flush)
  if not ok then deps(); util.warn("[view] redraw failed: " .. tostring(err)) end
end
function view.pane(name, spec)
  local p = { name = name, items = items_of(spec), refresh = spec.refresh or "change",
              every = spec.every, pick = spec.pick or "stack", due = 0 }
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
      rune.ui.bar("view_flush", function() flush_safe(); return nil end)
    end
  end
  request()
end

local bar_rows = {}
function view.bar(name, spec)
  local b = { name = name, left = items_of(spec.left or {}), right = items_of(spec.right or {}) }
  bars[name] = b
  if not host then host = name end
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
function view.flush()
  requested = false
  passes = passes + 1
  deps()
  local now = view.clock()
  local t0 = dbg.on and os.clock()
  for _, name in ipairs(order) do
    local p = panes[name]
    if p and (p.refresh ~= "every" or now >= p.due) then
      if p.refresh == "every" then p.due = now + p.every end
      local text = compose(p.items, p.pick, "\n")
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
  panes, bars, order, bar_rows, styles, compiled = {}, {}, {}, {}, {}, {}
  requested, passes, host = false, 0, nil
end

return view
