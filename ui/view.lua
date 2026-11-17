-- The data (require("ui.view")): modules publish declared, shaped data;
-- ui/screen.lua's widgets show it. Generic - nothing here knows the game.
--
-- Modules:
--   local S = view.provides("aard.vitals", "your vitals from GMCP", {
--     level = { "number",    "your level", standard = true },
--     tick  = { "timestamp", "when the next tick is due" },
--     hp    = { "ratio",     "hit points", get = function() return held.hp end },
--   })
--   S.set("level", 201)          -- the only way to change data
--   local set = S.setter("tick") -- the same, checked once (a hot path)
--   S.touch("hp")                -- a getter's data changed (S.toucher: checked once)
--   S.emit("chat.line", ev)      -- a stream's event: each one counts, never set
--   S.publish()                  -- once per update: subscribers run
-- Others read: view.get("level"), view.subscribe("level", fn(name, v)).
-- Data names are global ("hp", "campaign.area"); standard = true marks the
-- names kept the same across MUDs, so layouts carry over.
-- A value equal to the one held is no change; a ratio with the same cur
-- and max neither. Set a new table for a ratio or a list: the same table
-- changed in place and set again is no change.
--
-- ui/screen.lua listens through four hooks (set once, by it): _on_change
-- (a name changed), _on_publish (a module published), _on_emit (a stream's
-- event), _on_provide (new data: a widget waiting for it may start).
-- Cost: S.set - a compare, a table write, the change hook.

local view = {}

-- Injected so plain-Lua tests can run without Rune
view.clock = os.time
view.dev = false   -- check every S.set against its declared shape

local util, dbg
local function deps()
  if util then return end
  util = require("lib.util")
  dbg = require("lib.debug").topic("view", "the data: each publish")
end

local function fail(msg, level) error("[view] " .. msg, (level or 1) + 1) end

-- Shapes ------------------------------------------------------------------
-- What a value is: name -> { is = parent, check = fn(v), desc }

local shapes = {}
function view.shape(name, def) shapes[name] = def end

local function isnum(v) return type(v) == "number" end
local function istable(v) return type(v) == "table" end
local function isstring(v) return type(v) == "string" end
view.shape("number", { desc = "a number", check = isnum })
view.shape("percent", { is = "number", desc = "a number, 0-100" })
view.shape("seconds", { is = "number", desc = "a length of time in seconds" })
view.shape("timestamp", { is = "number", desc = "a moment (os.time)" })
view.shape("text", { desc = "text", check = isstring })
view.shape("block", { desc = "text the game colored, several lines", check = isstring })
view.shape("boolean", { desc = "true or false", check = function(v) return type(v) == "boolean" end })
view.shape("ratio", { desc = "a value and its maximum: { cur, max }",
  check = function(v) return istable(v) and isnum(v.cur) and isnum(v.max) end })
view.shape("list", { desc = "a list of records", check = istable })
view.shape("record", { desc = "named values (a table) - set a new one at each change", check = istable })
view.shape("stream", { desc = "events, each one counts: S.emit(name, event), never set", check = function() return true end })

-- Data --------------------------------------------------------------------

local decl = {}       -- data name -> { shape, desc, standard, module }
-- Data with a getter (provides' get = fn): never stored - a read of it
-- calls the getter; S.touch(name) says it changed. For data that changes
-- often between draws (DPS at each hit): no table built per change, the
-- value read once per draw
local getters = {}
local store = {}      -- data name -> value
local subs = {}       -- data name -> { fn, ... }
local modules = {}    -- module -> { desc, names = { ... } }

local function changed(name)
  local f = view._on_change
  if f then f(name) end
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
    decl[name] = { shape = shape, desc = d[2] or "", standard = d.standard, module = module }
    if d.get then getters[name] = d.get end
    names[#names + 1] = name
  end
  table.sort(names)
  modules[module] = { desc = desc or "", names = names }
  local S, pending = {}, {}
  if view._on_provide then view._on_provide() end
  local function check(name)
    local d = decl[name]
    if not d or d.module ~= module then fail(module .. " doesn't provide " .. tostring(name), 3) end
    if getters[name] then fail(name .. " has a getter - touch it, not set", 3) end
    return d
  end
  local function check_getter(name)
    local d = decl[name]
    if not d or d.module ~= module or not getters[name] then fail(module .. " has no getter data " .. tostring(name), 3) end
  end
  local function shape_warn(name, d, v)
    local s = d.shape
    local sh = shapes[s]
    while sh and not sh.check do s = sh.is; sh = shapes[s] end
    if sh and not sh.check(v) then
      deps(); util.warn("[view] " .. module .. " set " .. name .. " to a " .. type(v) .. ", not a " .. d.shape)
    end
  end
  -- a subscriber's name (or the debug log's) kept for publish
  local function note(name)
    if (subs[name] or (dbg and dbg.on)) and not pending[name] then pending[name] = true; pending[#pending + 1] = name end
  end
  -- The set itself, once the name is known good: equal = no change; then
  -- stored and the change told
  local function put(name, d, v)
    local old = store[name]
    if old == v then return end
    if type(v) == "table" and type(old) == "table" and v.cur ~= nil and v.cur == old.cur and v.max == old.max then
      store[name] = v; return
    end
    if view.dev and v ~= nil then shape_warn(name, d, v) end
    store[name] = v
    changed(name)
    note(name)
  end
  function S.set(name, v) put(name, check(name), v) end
  -- S.setter(name): a function(v) that sets name - checked once (a
  -- module's hot path: every GMCP vitals and status)
  function S.setter(name)
    local d = check(name)
    return function(v) put(name, d, v) end
  end
  function S.get(name) return view.get(name) end
  -- a getter's data changed
  local function touch(name) changed(name); note(name) end
  function S.touch(name) check_getter(name); touch(name) end
  -- S.toucher(name): a function that touches name - checked once (a
  -- module's hot path: each hit line)
  function S.toucher(name)
    check_getter(name)
    return function() touch(name) end
  end
  -- a stream's event: to whatever shows it (ui/screen.lua's append)
  function S.emit(name, ev)
    check(name)
    local f = view._on_emit
    if f then f(name, ev) end
  end
  -- (no subscriber of any pending name and debug off: only the list cleared)
  function S.publish()
    if view._on_publish then view._on_publish() end
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
  for _, n in ipairs(m.names) do decl[n], store[n], subs[n], getters[n] = nil, nil, nil, nil end
  modules[module] = nil
  if rune and rune.ui and rune.ui.refresh_bars then rune.ui.refresh_bars() end
end

-- the raw tables, for ui/screen.lua's readers
function view._raw() return store, getters end
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

-- For tests
function view._reset() decl, getters, store, subs, modules = {}, {}, {}, {}, {} end

return view
