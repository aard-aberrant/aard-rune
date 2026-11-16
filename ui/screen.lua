-- The layout engine (require("ui.screen")) - PROTOTYPE.
-- A tree: the screen, its panels, their widgets.
--
-- Panels: screen:panel { name, x, y, w, h, border, title } - a rectangle
-- in cells. x, y: from the left / top, negative from the right / bottom
-- edge. w, h: a size, negative = up to that far from the far edge, nil =
-- the rest. border: "all", "none" or sides ("right bottom"); a border takes
-- cells inside the rectangle. A side between two panels becomes Rune's
-- divider. screen:output {...} and screen:input {...} are Rune's own.
-- The rectangles become Rune's layout tree (rows and columns) at
-- screen.apply(): an arrangement straight cuts can't split, space no panel
-- covers, two panels that both take the rest - a clear error.
--
-- Widgets in a panel:
--   panel:widget { text = "..." }                  fixed text
--   panel:widget { source, process, format, every, w, x, y }
--     source: a data name or a list of names (ui/view.lua's registry)
--     process(v1, v2, ..., now) -> one value, compared with ~= to the last:
--       only a change marks the widget dirty (its line, its panel)
--     format(processed, width) -> the string shown (colors included), or
--       nil: the widget shows nothing - a line of nothing but such
--       widgets takes no row. Runs only at the refresh, only when dirty
--     every = n: processed again each n seconds (on the bar poll, never a
--       Rune timer); every = 0: at every refresh. A timed processor may
--       return a second value: the seconds until its value can change -
--       not looked at again until then (a change of its data still is);
--       math.huge: only its data changes it
--     w: a width (padded / cut), "*" the rest of the line, nil its text's
--     y = "next": starts the next line; y = a number: a line at that row
--       of the panel (0 the top, negative from the bottom) - the lines
--       above it cut to fit, blank rows up to it; x < 0: a bar's right side
--     a widget's text may hold several lines ("\n")
--   panel:list { source, records, key, process, format, order, max, every,
--     w, gap }: a row per record - each row processed and compared on its
--     own; format(v, key, cols); key a function of the record or a field
--     name ("name"). records(v..., now) -> the list (default:
--     the source's value); max: rows shown at most; columns of w cells
--     when the panel is wide enough
--   panel:append { source, process, format }: a stream's events, each one
--     kept (process -> nil drops it) is appended - every event counts
--   panel:priority { shown, pin }: items, the first with something wins
-- More widgets, built on these, are in ui/widgets/ - a pane requires the
-- ones it uses (each adds its panel:name)
--
-- The refresh (once per Rune event, from the first bar's render): dirty
-- widgets formatted, their lines rebuilt, each changed panel written once.
-- A widget dirty already isn't processed again on more changes - only
-- noted; the refresh processes it once more only then.

local view = require("ui.view")
local colors = require("ui.colors")
local util = require("lib.util")
local unpack = table.unpack or unpack
local find, rep, concat, floor = string.find, string.rep, table.concat, math.floor

local M = {}
local store, getters = view._raw()
local rearm = view._rearm

local watch = {}       -- data name -> { widget, ... }
local timed = {}       -- widgets with every > 0
local polled = {}      -- widgets with every = 0
local waiting = {}     -- widgets whose data isn't all provided yet
local queue, nq = {}, 0
local requested = false
local NONE = {}        -- never processed / never shown

local function request()
  if requested then return end
  requested = true
  rune.ui.refresh_bars()
end

-- Visible width (color codes and UTF-8 continuation bytes not counted)
local function width(s)
  if not find(s, "[\27\128-\255]") then return #s end
  return colors.width(s)
end
M.width = width

local function queue_panel(p)
  if not p.queued then p.queued = true; nq = nq + 1; queue[nq] = p end
end
local function mark(wd)
  wd.dirty = true
  wd.line.dirty = true
  local it = wd.item
  if it then local d = it.dirtyw; d[#d + 1] = wd end
  queue_panel(wd.panel)
end
-- a widget's new processed value; an item counts its widgets with one
-- (not nil) - it has something to show while the count is above 0
local function setlast(wd, v)
  local it = wd.item
  if it then
    local was = wd.last
    local a, b = was ~= nil and was ~= NONE, v ~= nil
    if a ~= b then it.have = it.have + (b and 1 or -1) end
  end
  wd.last = v
end

-- The widget's reader: its processor on its data's current values
local function build_run(wd)
  local p, names = wd.process, wd.src
  local n = #names
  if n == 0 then wd.run = function(now) return p(now) end; return end
  local gs = {}
  for k = 1, n do gs[k] = getters[names[k]] or false end
  if n == 1 then
    local a, g = names[1], gs[1]
    if g then wd.run = function(now) return p(g(), now) end
    else wd.run = function(now) return p(store[a], now) end end
    return
  end
  if n == 2 then
    local a, b, ga, gb = names[1], names[2], gs[1], gs[2]
    wd.run = function(now)
      local x, y
      if ga then x = ga() else x = store[a] end
      if gb then y = gb() else y = store[b] end
      return p(x, y, now)
    end
    return
  end
  if n == 3 or n == 4 then   -- direct reads: no table, no unpack
    local a, b, c, ga, gb, gc = names[1], names[2], names[3], gs[1], gs[2], gs[3]
    local d, gd = names[4], gs[4]
    if n == 3 then
      wd.run = function(now)
        local x, y, z
        if ga then x = ga() else x = store[a] end
        if gb then y = gb() else y = store[b] end
        if gc then z = gc() else z = store[c] end
        return p(x, y, z, now)
      end
    else
      wd.run = function(now)
        local x, y, z, u
        if ga then x = ga() else x = store[a] end
        if gb then y = gb() else y = store[b] end
        if gc then z = gc() else z = store[c] end
        if gd then u = gd() else u = store[d] end
        return p(x, y, z, u, now)
      end
    end
    return
  end
  local vals = {}
  wd.run = function(now)
    for k = 1, n do
      local g = gs[k]
      if g then vals[k] = g() else vals[k] = store[names[k]] end
    end
    vals[n + 1] = now
    return p(unpack(vals, 1, n + 1))
  end
end

-- A timed widget processed: when to look again (its processor's second
-- value, else every). at: when that was set (a clock gone back: due)
local function run(wd, now)
  local v, nxt = wd.run(now)
  if wd.every then wd.at = now; wd.due = now + (nxt or wd.every) end
  return v
end

-- All its data provided: the widget goes live (watched, timed, dirty)
local function attach(wd)
  for _, n in ipairs(wd.src) do if not view.data(n) then return false end end
  if wd.process then build_run(wd) end
  for _, n in ipairs(wd.src) do
    local ws = watch[n]
    if not ws then ws = {}; watch[n] = ws end
    ws[#ws + 1] = wd
  end
  if wd.every == 0 then polled[#polled + 1] = wd
  elseif wd.every then timed[#timed + 1] = wd; wd.due, wd.at = 0, 0 end
  wd.live = true
  wd.again = true   -- never processed yet
  mark(wd)
  return true
end

-- A data name changed (ui/view.lua's set / touch): each live widget on it
-- processed; dirty only if the result differs. Dirty already: only noted.
-- A list is processed row by row at the refresh (a list changes as a
-- whole). Returns false twice: touchers keep reporting (a touch may be the
-- note), and the pass is asked for here
-- The changed widgets are collected and processed once, at the module's
-- publish (a message sets several values: a widget reading three of them
-- is processed once, not three times) - or at the next refresh, for a
-- module that doesn't publish
local clock = view.clock
local pend, np = {}, 0
view._on_change = function(name)
  local ws = watch[name]
  if not ws then return false, false end
  for k = 1, #ws do
    local wd = ws[k]
    if wd.dirty then
      wd.again = true
    elseif not wd.pend then
      wd.pend = true
      np = np + 1; pend[np] = wd
    end
  end
  return false, false
end
local function settle(now, in_pass)
  if np == 0 then return end
  local any = false
  for k = 1, np do
    local wd = pend[k]
    pend[k] = nil
    wd.pend = false
    if wd.dirty then
      wd.again = true
    elseif wd.lazy then
      mark(wd); any = true
    else
      now = now or clock()
      local v = run(wd, now)
      if v ~= wd.last then setlast(wd, v); mark(wd); any = true end
    end
  end
  np = 0
  if any and not in_pass and not requested then request() end
end
view._on_publish = function() settle() end
-- A stream's event: each append widget on it keeps it (its processor may
-- drop it); one kept marks the widget
view._on_emit = function(name, ev)
  local ws = watch[name]
  if not ws then return end
  for k = 1, #ws do
    local wd = ws[k]
    local v = wd.process(ev)
    if v ~= nil then
      local q = wd.pending
      q[#q + 1] = v
      if not wd.dirty then mark(wd) end
      if not requested then request() end
    end
  end
end
local provided = false
view._on_provide = function() provided = true; request() end

-- Panels -------------------------------------------------------------------

local Panel = {}
Panel.__index = Panel
local panels, order = {}, {}
local bar_rows, host = {}, nil

local function ident(v) return v end
local function tostr(v) if v == nil then return nil end return tostring(v) end
local function new_line() return { widgets = {}, outs = {}, dirty = true, kind = "line" } end

local function add_item(p, item)
  p.items[#p.items + 1] = item
  return item
end

-- the line a widget goes on
local function line_for(p, t)
  if t.x and t.x < 0 then
    p.right = p.right or new_line()
    return p.right
  end
  if type(t.y) == "number" then
    local l = add_item(p, new_line())
    l.y, p.placed = t.y, true
    if p.root then p.root.placed = true end
    return l
  end
  local last = p.items[#p.items]
  if t.y == "next" or not last or last.kind ~= "line" then return add_item(p, new_line()) end
  return last
end

-- A piece of a panel's text added to out (base: the panel's rows before
-- out's first, used: before this piece): one with a row (y) starts there -
-- out cut to fit above it, blank rows up to it. Returns the rows used
local function nrows(s)
  local n, at = 1, find(s, "\n", 1, true)
  while at do n = n + 1; at = find(s, "\n", at + 1, true) end
  return n
end
local pads = {}   -- k blank rows as one piece of a panel's text, by k
local function place(out, base, used, s, y, prows, n)
  if y then
    local target = y >= 0 and y or prows + y
    if used > target then
      local keep, rows = target - base, {}
      for row in (concat(out, "\n") .. "\n"):gmatch("([^\n]*)\n") do
        if #rows >= keep then break end
        rows[#rows + 1] = row
      end
      for k = #out, 1, -1 do out[k] = nil end
      for k = 1, #rows do out[k] = rows[k] end
      used = base + #rows
    end
    if used < target then   -- the blank rows: one piece (k - 1 newlines; the join adds the last)
      local k = target - used
      local pad = pads[k]
      if not pad then pad = rep("\n", k - 1); pads[k] = pad end
      out[#out + 1] = pad
      used = target
    end
  end
  out[#out + 1] = s
  return used + (n or nrows(s))
end

function Panel:widget(t)
  local line = line_for(self, t)
  local wd = { panel = self.root or self, item = self.root and self or nil, line = line, w = t.w, slot = #line.outs + 1 }
  line.widgets[#line.widgets + 1] = wd
  if t.text then
    line.outs[wd.slot] = t.text
    wd.fixed = true
    line.dirty = true
    queue_panel(self.root or self)
    request()
    return wd
  end
  local src = t.source
  if type(src) == "string" then src = { src } end
  wd.src = src or {}
  wd.process = t.process or ident
  wd.format = t.format or tostr
  wd.every = t.every
  wd.last, wd.shown = NONE, NONE
  line.outs[wd.slot] = ""
  wd.isnil = true
  if not attach(wd) then waiting[#waiting + 1] = wd end
  return wd
end

-- list: rows keyed by key(rec); each row's processed value compared on its
-- own; order(v) -> a number, rows ascending (ties in the data's order)
function Panel:list(t)
  local src, key = t.source, t.key
  if type(src) == "string" then src = { src } end
  if type(key) == "string" then local f = key; key = function(r) return r[f] end end
  local wd = { panel = self, kind = "list", lazy = true, src = src, key = key,
               process = t.records or ident, every = t.every, max = t.max,
               rowproc = t.process or ident, format = t.format, order = t.order,
               cw = t.w, gap = t.gap or "  ", rows = {}, list = {}, dat = {}, out = nil }
  wd.line = wd
  add_item(self, wd)
  if not attach(wd) then waiting[#waiting + 1] = wd end
  return wd
end

-- append: a stream's events, each kept one formatted and written in order
function Panel:append(t)
  local wd = { panel = self, kind = "append", src = { t.source }, process = t.process or ident,
               format = t.format or tostring, pending = {}, lazy = true }
  wd.line = wd
  add_item(self, wd)
  self.append_only = true
  local d = view.data(t.source)
  local ws = watch[t.source]
  if not ws then ws = {}; watch[t.source] = ws end
  ws[#ws + 1] = wd
  return wd
end

-- priority { shown = data name, pin = fn }: items, the first with something
-- to show wins - an item has something while any of its widgets' processed
-- value isn't nil. keep = true: a pin can't beat it (an alert). pin(): an
-- item's name to show instead whenever it has something. shown: published
-- with the name of the item on the panel (nil: none). An item takes the
-- same widget calls as a panel
function Panel:priority(t)
  t = t or {}
  local P = { kind = "priority", panel = self, list = {}, pin = t.pin, shown = nil }
  if t.shown then
    P.pub = view.provides("screen." .. t.shown, "what a priority panel shows", {
      [t.shown] = { "text", "the name of the item shown; nil: none" } })
    P.shown_name = t.shown
  end
  function P:item(o)
    local it = setmetatable({ items = {}, root = self.panel, name = o.name or tostring(#self.list + 1),
                              prio = o.prio, keep = o.keep, have = 0, dirtyw = {} }, Panel)
    self.list[#self.list + 1] = it
    return it
  end
  -- a pin changed: drawn again at the next refresh
  function P:refresh() queue_panel(self.panel); request() end
  add_item(self, P)
  return P
end

-- Sizes and layout ----------------------------------------------------------

local function sides(b)
  local s = { t = false, b = false, l = false, r = false }
  if b == "all" then s.t, s.b, s.l, s.r = true, true, true, true
  elseif b and b ~= "none" then
    for w in b:gmatch("%a+") do
      local k = ({ top = "t", bottom = "b", left = "l", right = "r" })[w]
      if not k then error("[screen] border: unknown side " .. w, 3) end
      s[k] = true
    end
  end
  return s
end

-- a rectangle on a W x H screen: x0, y0, x1, y1 (x1, y1 past the end)
local function rect(p, W, H)
  local x0 = p.x >= 0 and p.x or W + p.x
  local y0 = p.y >= 0 and p.y or H + p.y
  local x1 = (p.w == nil or p.w == "*") and W or p.w < 0 and W + p.w or x0 + p.w
  local y1 = (p.h == nil or p.h == "*") and H or p.h < 0 and H + p.h or y0 + p.h
  return x0, y0, x1, y1
end

local function make(kind, t)
  local p = setmetatable({ kind = kind, name = t.name or kind, x = t.x or 0, y = t.y or 0, w = t.w, h = t.h,
                           border = sides(t.border), title = t.title, items = {} }, Panel)
  if panels[p.name] then error("[screen] two panels named " .. p.name, 3) end
  panels[p.name] = p
  order[#order + 1] = p
  return p
end
function M.panel(_, t) return make("panel", t) end
function M.output(_, t) t.name = "output"; return make("output", t) end
function M.input(_, t) t.name = "input"; return make("input", t) end
function M.get(name) return panels[name] end
-- screen.panels.status2: a panel by name - a name no panel has is an
-- error that lists the panels there are
M.panels = setmetatable({}, { __index = function(_, name)
  local p = panels[name]
  if p then return p end
  local names = {}
  for _, q in ipairs(order) do names[#names + 1] = q.name end
  error("[screen] no panel named " .. tostring(name) .. " - the panels: " .. concat(names, ", "), 2)
end })

-- screen.add_widget(name, fn): fn(panel, t) becomes panel:name(t) on every
-- panel (and priority item) - a widget of ui/widgets/, registered when its
-- file is required. A name taken already (a widget, or one of the
-- engine's own: widget, list, append, priority) is an error
function M.add_widget(name, fn)
  if Panel[name] ~= nil then error("[screen] a widget named " .. name .. " exists already", 2) end
  Panel[name] = fn
  return fn
end

-- the inside of a panel now (the terminal's size): rows, columns
local function content(p)
  local st = rune._state
  local W, H = st.width or 0, st.height or 0
  if W == p.sw and H == p.sh then return p.srows, p.scols end   -- the terminal's size unchanged
  local x0, y0, x1, y1 = rect(p, W, H)
  local b = p.border
  p.sw, p.sh = W, H
  p.srows = y1 - y0 - (b.t and 1 or 0) - (b.b and 1 or 0)
  p.scols = x1 - x0 - (b.l and 1 or 0) - (b.r and 1 or 0)
  return p.srows, p.scols
end
M.content = content

-- Rune's layout tree from the rectangles, resolved at two screen sizes: a
-- size that differs between them is "the rest" (no size)
local A, B = { 1000, 1000 }, { 2000, 2000 }
local function leaf_node(L)
  local p = L.p
  local h = L.a[4] - L.a[2]
  local node
  if p.kind == "input" then node = { type = "input" }
  elseif p.kind == "panel" and h == 1 and L.b[4] - L.b[2] == 1 then
    node = { type = "bar", name = p.name }
    p.bar = true
  else
    node = { type = "pane", name = p.name }
    local s = L.s
    if s.t and s.b and s.l and s.r then node.border = "full"
    elseif s.t and s.b and not s.l and not s.r then node.border = "horizontal"
    elseif not (s.t or s.b or s.l or s.r) then node.border = "none"
    else error("[screen] panel " .. p.name .. ": a border on one side must be between two panels", 0) end
    if type(p.title) == "string" then node.title = p.title
    elseif node.border ~= "none" then node.title = "" end
  end
  return node
end
local AX = { x = { 1, 3, "l", "r", "row" }, y = { 2, 4, "t", "b", "column" } }
local build
local function split(leaves, axis)
  local lo, hi, near, far = AX[axis][1], AX[axis][2], AX[axis][3], AX[axis][4]
  table.sort(leaves, function(u, v) return u.a[lo] < v.a[lo] end)
  local groups, cur, top = {}, nil, nil
  for _, L in ipairs(leaves) do
    if cur and L.a[lo] >= top then groups[#groups + 1] = cur; cur = nil end
    if not cur then cur = {}; top = L.a[hi] end
    cur[#cur + 1] = L
    if L.a[hi] > top then top = L.a[hi] end
  end
  groups[#groups + 1] = cur
  if #groups < 2 then return nil end
  -- the boundaries: a border side there becomes a divider
  local div = {}
  for g = 1, #groups - 1 do
    local c = 0
    for _, L in ipairs(groups[g]) do if L.a[hi] > c then c = L.a[hi] end end
    local function touching(list, k, at)
      local t = {}
      for _, L in ipairs(list) do if L.a[k] == at then t[#t + 1] = L end end
      return t
    end
    local left, right = touching(groups[g], hi, c), touching(groups[g + 1], lo, c)
    -- (a border Rune draws itself - all sides, top and bottom - stays as it is)
    local function native(x) return x.t and x.b and (x.l == x.r) end
    local function all(t, side)
      for _, L in ipairs(t) do if not L.s[side] or native(L.s) then return false end end
      return #t > 0
    end
    for _, L in ipairs(groups[g + 1]) do
      if L.a[lo] > c then error("[screen] empty space before panel " .. L.p.name .. " - no panel covers it", 0) end
    end
    if all(left, far) then
      for _, L in ipairs(left) do L.s[far] = false; L.a[hi] = L.a[hi] - 1; L.b[hi] = L.b[hi] - 1 end
      div[g] = true
    elseif all(right, near) then
      for _, L in ipairs(right) do L.s[near] = false; L.a[lo] = L.a[lo] + 1; L.b[lo] = L.b[lo] + 1 end
      div[g] = true
    end
  end
  local function extent(list, r)
    local a, b = math.huge, -math.huge
    for _, L in ipairs(list) do
      if L[r][lo] < a then a = L[r][lo] end
      if L[r][hi] > b then b = L[r][hi] end
    end
    return b - a
  end
  local function child(list)
    local node = #list == 1 and leaf_node(list[1]) or build(list)
    local ea, eb = extent(list, "a"), extent(list, "b")
    if ea == eb and node.type ~= "bar" then node.size = ea end
    return node, ea == eb, ea
  end
  -- runs of groups with no divider between them: a container of their own
  local kids, any_div = {}, false
  local g = 1
  while g <= #groups do
    local run = { groups[g] }
    while g < #groups and not div[g] do g = g + 1; run[#run + 1] = groups[g] end
    if g < #groups then any_div = true end
    g = g + 1
    if #run == 1 then
      kids[#kids + 1] = child(run[1])
    else
      local c = { type = AX[axis][5], children = {} }
      local fixed, total = true, 0
      for _, list in ipairs(run) do
        local n, f, e = child(list)
        c.children[#c.children + 1] = n
        fixed = fixed and f; total = total + e
      end
      if fixed then c.size = total end
      kids[#kids + 1] = c
    end
  end
  if #kids == 1 then return kids[1] end
  local fill = 0
  for _, k in ipairs(kids) do if k.size == nil and k.type ~= "bar" then fill = fill + 1 end end
  if fill > 1 then error("[screen] two panels side by side both take the rest", 0) end
  local node = { type = AX[axis][5], children = kids }
  if any_div then node.dividers = true end
  return node
end
build = function(leaves)
  local n = split(leaves, "x") or split(leaves, "y")
  if not n then
    local names = {}
    for _, L in ipairs(leaves) do names[#names + 1] = L.p.name end
    error("[screen] panels " .. table.concat(names, ", ") .. " overlap, or no straight cut splits them", 0)
  end
  return n
end

local tree, input_node, input_size
-- screen.tree(): Rune's layout, built once from the panels
function M.tree()
  if tree then return tree end
  local leaves = {}
  for _, p in ipairs(order) do
    local L = { p = p, s = {} }
    for k, v in pairs(p.border) do L.s[k] = v end
    L.a = { rect(p, A[1], A[2]) }
    L.b = { rect(p, B[1], B[2]) }
    leaves[#leaves + 1] = L
  end
  tree = build(leaves)
  local function find_input(n)
    if n.type == "input" then input_node = n end
    for _, c in ipairs(n.children or {}) do find_input(c) end
  end
  find_input(tree)
  return tree
end

-- screen.apply(picking): Rune's layout; while a picker is open the input
-- sizes itself (ui/layout.lua's picker wrapper)
function M.apply(picking)
  local t = M.tree()
  if input_node then
    if input_size == nil then input_size = input_node.size or false end
    input_node.size = not picking and input_size or nil
  end
  rune.ui.layout(t)
  -- the bars: a Rune bar each, the first runs the refresh
  for _, p in ipairs(order) do
    if p.bar and not p.bar_on then
      p.bar_on = true
      host = host or p.name
      local name = p.name
      rune.ui.bar(name, function()
        if host == name then M.pass() end
        return bar_rows[name]
      end)
    end
  end
  for _, p in ipairs(order) do
    if #p.items > 0 or p.right then p.queued = true; nq = nq + 1; queue[nq] = p end
  end
  request()
end

-- The refresh ------------------------------------------------------------------

local function fit(s, n)
  local w = width(s)
  if w < n then return s .. rep(" ", n - w) end
  if w > n then return colors.crop(s, n) end
  return s
end

-- a line: its dirty widgets formatted; its text (nil: every widget shows
-- nothing); true when it changed
local function redraw_line(line, now, cols, rows)
  if not line.dirty then return false end
  line.dirty = false
  local ws, outs, any = line.widgets, line.outs, false
  local col = 0
  for k = 1, #ws do
    local wd = ws[k]
    local wn = wd.w
    local star = wn == "*"
    if star then wn = math.max((cols or 0) - col, 0) end
    if wd.dirty or wd.stale then
      wd.dirty, wd.stale = false, false
      local v = wd.last
      if wd.again then
        wd.again = false
        v = run(wd, now)
        setlast(wd, v)
      end
      if v ~= wd.shown or wn ~= wd.wn then
        wd.shown, wd.wn = v, wn
        local s = wd.format(v, wn, rows)
        wd.isnil = s == nil
        if s and wn and not star then s = fit(s, wn) end
        outs[k] = s or ""
        any = true
      end
    end
    if wn then col = col + wn elseif cols then col = col + width(outs[k]) end
  end
  if any or line.text == nil and not line.hidden then
    local hidden = true
    for k = 1, #ws do if ws[k].fixed or not ws[k].isnil then hidden = false; break end end
    line.hidden = hidden
    line.text = concat(outs)
    line.nrows = nil   -- (counted when placed)
  end
  return any
end

-- a list's rows: processed one by one (only a changed one formatted), in
-- order, in columns; nil when there's no list
-- a list's rows: processed one by one (only a changed one formatted), in
-- order; true when anything changed. process(rec, now)
local function list_rows(wd, now)
  local list = run(wd, now)
  local rows, keyf, proc, ord, cols = wd.rows, wd.key, wd.rowproc, wd.order, wd.fcols
  local dat, out, changed, gen = wd.dat, wd.list, false, (wd.gen or 0) + 1
  wd.gen = gen
  local n = type(list) == "table" and #list or 0
  if wd.max and not ord and n > wd.max then n = wd.max end   -- (sorted: every row needed)
  for k = 1, n do
    local rec = list[k]
    local key = keyf and keyf(rec) or k
    local r = rows[key]
    if not r then r = { last = NONE }; rows[key] = r end
    local v = proc(rec, now)
    if v ~= r.last then
      r.last = v
      r.text = wd.format(v, key, cols) or ""
      r.padded = nil
      if ord then r.o = ord(v) end
      changed = true
    end
    r.i, r.gen = k, gen
    if dat[k] ~= r then dat[k] = r; changed = true end
  end
  for k = n + 1, #dat do dat[k] = nil; changed = true end
  if changed then   -- rows in the data's order, then sorted
    for key, r in pairs(rows) do if r.gen ~= gen then rows[key] = nil end end
    for k = 1, n do out[k] = dat[k] end
    for k = n + 1, #out do out[k] = nil end
    if ord and n > 1 then
      table.sort(out, function(a, b) if a.o ~= b.o then return a.o < b.o end return a.i < b.i end)
    end
  end
  wd.n = n
  return changed
end

-- its text, in columns; nil when there's no list. A timed list's rows are
-- compared at the second (fresh: done, and changed)
local function list_text(wd, room, cols, now)
  if wd.fcols ~= cols then   -- a row's text may follow the width
    wd.fcols, wd.dirty, wd.fresh = cols, true, false
    for _, r in pairs(wd.rows) do r.last = NONE end
  end
  if wd.dirty then
    wd.dirty = false
    local changed = wd.fresh
    wd.fresh = false
    if not changed then changed = list_rows(wd, now) end
    if not changed and wd.room == room and wd.cols == cols then return wd.out end
  elseif wd.room == room and wd.cols == cols then
    return wd.out
  end
  wd.room, wd.cols = room, cols
  local n, out, cw, gap = wd.n or 0, wd.list, wd.cw, wd.gap
  if n == 0 then wd.out = nil; return nil end
  local ncols, h = 1, n
  if cw and cols then ncols = floor((cols + #gap) / (cw + #gap)) end
  if ncols < 2 then ncols = 1 else h = math.max(room or n, 1) end
  local shown = math.min(n, ncols * h, wd.max or n)
  local lines = {}
  for l = 1, math.min(h, shown) do
    local parts = {}
    for c = 0, ncols - 1 do
      local k = l + c * h
      if k > shown then break end
      parts[#parts + 1] = out[k]
    end
    local np = #parts
    for k = 1, np do
      local r = parts[k]
      if k < np and cw then
        if not r.padded then local tw = width(r.text); r.padded = tw < cw and r.text .. rep(" ", cw - tw) or r.text end
        parts[k] = r.padded
      else
        parts[k] = r.text
      end
    end
    lines[l] = concat(parts, gap)
  end
  wd.out = concat(lines, "\n")
  return wd.out
end

-- an item has something: a widget's processed value isn't nil (one marked
-- with more to come is processed now)
local function available(item, now)
  local d = item.dirtyw
  for k = 1, #d do
    local wd = d[k]
    if wd.again then wd.again = false; setlast(wd, run(wd, now)) end
  end
  return item.have > 0
end
local function priority_text(P, now, rows, cols, top, prows)
  local pin = P.pin and P.pin()
  local best, kept, pinned
  for _, it in ipairs(P.list) do
    if (not best or it.keep or it.name == pin) and available(it, now) then
      best = best or it
      if it.keep then kept = true end
      if it.name == pin then pinned = it end
    end
  end
  if pinned and not kept then best = pinned end
  -- the items not shown: their dirty widgets set aside (stale - formatted
  -- when their item shows), so their next change marks the panel again
  for _, it in ipairs(P.list) do
    local d = it.dirtyw
    if it ~= best then
      for k = 1, #d do local wd = d[k]; if wd.dirty then wd.dirty = false; wd.stale = true end end
    end
    for k = #d, 1, -1 do d[k] = nil end
  end
  local name = best and best.name
  if P.pub and P.shown ~= name then P.pub.set(P.shown_name, name); P.pub.publish() end
  P.shown = name
  if not best then return nil end
  local out, placed, used = {}, best.placed, top
  for _, line in ipairs(best.items) do
    if line.kind == "line" then
      redraw_line(line, now, cols, rows)
      if not line.hidden then
        if placed then
          local n = line.nrows
          if not n then n = nrows(line.text); line.nrows = n end
          used = place(out, top, used, line.text, line.y, prows, n)
        else out[#out + 1] = line.text end
      end
    end
  end
  return concat(out, "\n")
end
-- every item's state now: { name = true when it has something }
local function peek(P)
  local now, t = clock(), {}
  for _, it in ipairs(P.list) do t[it.name] = available(it, now) end
  return t
end
M.peek = peek

local function redraw_pane(p, now)
  local rows, cols = content(p)
  local resized = rows ~= p.rows or cols ~= p.cols
  if resized then
    p.rows, p.cols = rows, cols
    for _, it in ipairs(p.items) do
      if it.kind == "line" then
        for _, wd in ipairs(it.widgets) do if wd.w == "*" and wd.live then wd.dirty = true; it.dirty = true end end
      end
    end
  end
  local any = resized
  for _, it in ipairs(p.items) do
    if it.kind == "line" and redraw_line(it, now, cols, rows) then any = true end
    if it.kind == "list" and it.dirty then any = true end
    if it.kind == "priority" then any = true end
  end
  if not any then return end
  local out, room, items, placed = {}, rows, p.items, p.placed
  for k, it in ipairs(items) do
    local s
    if it.kind == "line" then
      if not it.hidden then s = it.text end
    elseif it.kind == "priority" then
      s = priority_text(it, now, room, cols, rows - room, rows)
    else
      s = list_text(it, room, cols, now)
    end
    if s and placed then
      local n
      if it.kind == "line" then
        n = it.nrows
        if not n then n = nrows(s); it.nrows = n end
      end
      room = rows - place(out, 0, rows - room, s, it.y, rows, n)
    elseif s then
      out[#out + 1] = s
      if k < #items then
        local _, nl = s:gsub("\n", "")
        room = room - nl - 1
      end
    end
  end
  local text = concat(out, "\n")
  if text ~= (p.text or "") then p.text = text; util.pane(p.name, text) end   -- empty: not written until it has something
end

local function redraw_append(p, now)
  for _, it in ipairs(p.items) do
    if it.dirty then
      it.dirty = false
      local q = it.pending
      for k = 1, #q do
        rune.pane.write(p.name, it.format(q[k]))
        q[k] = nil
      end
    end
  end
end

local last_now, last_w, last_h
function M.pass()
  requested = false
  rearm()
  local st = rune._state
  if st.width ~= last_w or st.height ~= last_h then   -- the terminal resized: every panel looked at
    last_w, last_h = st.width, st.height
    for _, p in pairs(panels) do if p.items then queue_panel(p) end end
  end
  local now = clock()
  settle(now, true)
  if provided then
    provided = false
    for k = #waiting, 1, -1 do if attach(waiting[k]) then table.remove(waiting, k) end end
  end
  if now ~= last_now then
    last_now = now
    for k = 1, #timed do
      local wd = timed[k]
      if now >= wd.due or now < wd.at then   -- (or the clock went back)
        if wd.dirty then wd.again = true; wd.at, wd.due = now, now   -- processed at the refresh
        elseif wd.lazy then                  -- a list: marked only if a row changed
          if wd.fcols ~= nil and list_rows(wd, now) then mark(wd); wd.fresh = true
          elseif wd.fcols == nil then mark(wd) end
        else
          local v = run(wd, now)
          if v ~= wd.last then setlast(wd, v); mark(wd) end
        end
      end
    end
  end
  for k = 1, #polled do
    local wd = polled[k]
    if wd.dirty then wd.again = true
    else
      local v = wd.run(now)
      if v ~= wd.last then setlast(wd, v); mark(wd) end
    end
  end
  for k = 1, nq do
    local p = queue[k]
    queue[k] = nil
    p.queued = false
    if p.bar then
      local items = p.items
      local a = items[1] and redraw_line(items[1], now)
      local b = p.right and redraw_line(p.right, now)
      if a or b or not bar_rows[p.name] then
        bar_rows[p.name] = { left = items[1] and items[1].text or "", right = p.right and p.right.text or "" }
      end
    elseif p.append_only then
      redraw_append(p, now)
    else
      redraw_pane(p, now)
    end
  end
  nq = 0
end

-- Formatter helpers -------------------------------------------------------
local RESET = colors.RESET or "\27[0m"
-- paint(color, s): s in a theme color (theme.value, theme.quest.ready)
function M.paint(c, s) return c.on .. s .. RESET end
-- crop(s, n): s cut to n columns; colored text keeps a reset at the end
function M.crop(s, n)
  if not find(s, "[\27\128-\255]") then return #s <= n and s or s:sub(1, n) end
  local c = colors.crop(s, n)
  if not find(s, "\27", 1, true) then c = c:sub(1, -#RESET - 1) end
  return c
end
-- bar(n, scale, cells): n as a bar of `cells` cells, `scale` per full
-- cell, in eighths of a cell; more than fits: an arrow in the last cell.
-- Always `cells` wide
local EIGHTHS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }
function M.bar(n, scale, cells)
  local units = floor(n * 8 / scale)
  if units > cells * 8 then return rep("█", cells - 1) .. "▶" end
  local full, part = floor(units / 8), units % 8
  if part > 0 then return rep("█", full) .. EIGHTHS[part] .. rep(" ", cells - full - 1) end
  return rep("█", full) .. rep(" ", cells - full)
end
function M.pad(s, n) local w = width(s); return w < n and s .. rep(" ", n - w) or s end
function M.rpad(s, n) local w = width(s); return w < n and rep(" ", n - w) .. s or s end

return M
