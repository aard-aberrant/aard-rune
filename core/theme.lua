-- The theme (require("core.theme")): every color the config shows.
-- Modules use it and nothing else - never core/colors.lua directly.
-- /theme lists it all: each name as you'd set it in data/theme.lua, in its
-- own colors, what it's made of, and where it shows.
--
-- Three parts, all overridable in data/theme.lua:
--   the palette  theme.yellow, theme.gray, theme.green_tc ... - the colors
--                the theme works with (core/colors.lua's). Change one and
--                everything built on it follows.
--   the roles    theme.caution, theme.value, theme.alert ... - shared: what
--                a color is FOR, built from the palette. Change one and only
--                it changes.
--   the groups   theme.map.me, theme.bcc.hot1 ... - a module's own roles,
--                defined in the module with theme.define (below), built
--                from the palette and the roles. An area's group exists only
--                while the area is loaded.
-- The palette is built at load with data/theme.lua's changes, then the
-- roles from it; a group when its module defines it. So everything uses
-- the palette as changed. After that every name is a plain field.
--
-- Each is called on text - theme.value("12") - or gives its bare code as
-- .on, for text that runs on into other colors (colors.RESET ends it).
--
-- A module's group:
--   local T = theme.define("bcc", "Blackclaw", {
--     { "hot1", theme.yellow,               "a square's count: 1" },
--     { "kill", mix(theme.bold, theme.red), "KILL KILL KILL" },
--   })
--   T.hot1.on, T.kill("KILL")         - or theme.bcc.hot1 anywhere
-- and an area's unload calls theme.undefine("bcc").
local colors = require("core.colors")
local bg, mix = colors.bg, colors.mix

local function warn(s) rune.echo(colors.amber_tc("[theme] " .. s)) end

-- The palette: names, in /theme's order. Each defaults to core/colors.lua's
local PALETTE = {
  "default", "dark", "red", "green", "yellow", "blue", "magenta", "cyan", "white", "gray",
  "black_tc", "amber_tc", "green_tc", "orange_tc", "steel_tc",
  "bold", "faint", "underline",
}
local IS_PALETTE = {}
for _, n in ipairs(PALETTE) do IS_PALETTE[n] = true end

-- A palette name as a ref, for the roles below and data/theme.lua: worked
-- out once the palette is built
local P = setmetatable({}, { __index = function(_, k) return { ref = k, expr = "theme." .. k } end })

-- The shared roles: name, default, where it shows. { "Heading" } starts a
-- section of /theme
local ROLES = {
  { "Not themed" },
  { "default_bg", bg(P.default), "the terminal's own background" },
  { "Messages" },
  { "news",  P.cyan,     "util.say: a thing done, a state shown" },
  { "warn",  P.amber_tc, "util.warn: a problem (plain yellow was too bright)" },
  { "error", P.red,      "util.err: an error" },
  { "Text" },
  { "muted",       P.gray,      "timestamps, ids, separators, side notes" },
  { "unavailable", P.faint,     "no value to show: \"--\", 2XP/2QP off, affects off, empty timer bands, no totem, group members not here" },
  { "quiet",       P.gray,      "k with no target" },
  { "value",       P.cyan,      "status values, help usage, eq levels" },
  { "self",        P.cyan,      "your name in the group pane" },
  { "heading",     P.green,     "help's [Aardwolf commands] / [Rune commands]" },
  { "on",          P.green,     "a thing on or live: AC, debug on, DPS and PUP while counting" },
  { "off",         P.gray,      "a toggle off: AC, debug off, REC with no log open" },
  { "found",       P.green,     "an answer: an soh keyword, eq's \"<- your level\"" },
  { "emphasis",    P.underline, "PUP's average" },
  { "Levels" },
  { "good",    P.green,  "HP, TCK, TNL, POP, QST, ALN, time left, affects' timers: fine" },
  { "caution", P.yellow, "the same, getting low" },
  { "danger",  P.red,    "the same, low" },
  { "Blocks" },
  { "alert",         mix(P.black_tc, bg(P.red)),    "info pane alerts, an important affect off" },
  { "alert_caution", mix(P.black_tc, bg(P.yellow)), "info pane warnings" },
  { "scrolled",      mix(P.black_tc, bg(P.yellow)), "SCROLLED: the main pane scrolled back" },
}
local IS_ROLE = {}
for _, r in ipairs(ROLES) do if r[2] then IS_ROLE[r[1]] = true end end

-- data/theme.lua's changes, by full name ("yellow", "caution",
-- "bcc.hot1"). The file is run with a table to set them on. A palette or
-- role name it doesn't know is warned about here; a group's names are
-- checked when its module defines it (a group never defined - an area not
-- loaded, or a typo - shows in /theme). Reading a name there - theme.yellow,
-- theme.caution, theme.map.me - gives a ref: worked out once that name is
-- built, so a change can follow the palette, a role or a group's color as
-- changed
local function ref(name) return { ref = name, expr = "theme." .. name } end
local set = {}
local proxies = {}
local proxy = setmetatable({}, {
  __index = function(_, k)
    if IS_PALETTE[k] or IS_ROLE[k] then return ref(k) end
    if not proxies[k] then
      proxies[k] = setmetatable({}, {
        __index = function(_, m) return ref(k .. "." .. tostring(m)) end,
        __newindex = function(_, m, v) set[k .. "." .. tostring(m)] = v end,
      })
    end
    return proxies[k]
  end,
  __newindex = function(_, k, v)
    if IS_PALETTE[k] or IS_ROLE[k] then set[k] = v
    else warn("data/theme.lua sets theme." .. tostring(k) .. ", which isn't a theme name - ignored") end
  end,
})
do
  local chunk, err = loadfile(rune.config_dir .. "/data/theme.lua")
  if chunk then
    local ok, e = pcall(chunk, proxy)
    if not ok then err = e end
  end
  if err then warn("can't load data/theme.lua: " .. tostring(err)) end
end

-- What /theme shows for each name: how it's written, where it shows,
-- whether data/theme.lua changes it
local shown = {}

-- The palette: core/colors.lua's, with data/theme.lua's changes (a ref
-- there means core/colors.lua's color of that name). Each is named
-- theme.<name>, so what's built on it shows as such
local pal = {}
for _, n in ipairs(PALETTE) do
  local v, c = set[n], nil
  if v ~= nil then
    c = colors.resolve(v, function(k) return colors[k] end)
    if not c then warn("data/theme.lua: theme." .. n .. " isn't a color - ignored") end
  end
  pal[n] = colors.named(c or colors[n], "theme." .. n)
  shown[n] = { expr = c and v.expr or colors[n].expr, changed = c ~= nil }
end

local theme = {}
for n, c in pairs(pal) do theme[n] = c end

-- Building names: each from data/theme.lua's change if it has one, else
-- its default. A ref is worked out by lookup - the palette, a role, a
-- group's color - building that name first if it isn't yet, so the order
-- of names doesn't matter. A loop (caution = theme.danger, danger =
-- theme.caution) can't be built: warned about, and the defaults used
local building = {}
local function make(name, default, desc, lookup)
  if building[name] then return nil end
  building[name] = true
  local v, c = set[name], nil
  if v ~= nil then
    c = colors.resolve(v, lookup)
    if not c then warn("data/theme.lua: theme." .. name .. " isn't a color, or loops back on itself - its default is used") end
  end
  local changed = c ~= nil
  c = c or colors.resolve(default, lookup)
  building[name] = nil
  shown[name] = { expr = changed and v.expr or default.expr, desc = desc, changed = changed }
  return c and colors.named(c, "theme." .. name)
end

-- The shared roles
local ROLE = {}
for _, r in ipairs(ROLES) do if r[2] then ROLE[r[1]] = r end end
local function role(k)
  if theme[k] then return theme[k] end
  local r = ROLE[k]
  if not r then return nil end
  local c = make(k, r[2], r[3], function(n) return pal[n] or role(n) end)
  theme[k] = c
  return c
end
for _, r in ipairs(ROLES) do if r[2] then role(r[1]) end end

-- Groups ------------------------------------------------------------------

local groups = {}   -- defined: name -> { title, names }
local order = {}    -- their names, in definition order

-- theme.define(group, title, { { name, default, desc }, ... }) - a module's
-- roles as theme.<group>.<name>; returns the group. A default is built from
-- the palette, the roles and other groups (theme.yellow, theme.caution,
-- mix(theme.bold, theme.red)). Defining it again (an area loaded again)
-- replaces it
function theme.define(group, title, list)
  if IS_PALETTE[group] or IS_ROLE[group] or group == "define" or group == "undefine" then
    error("theme.define: \"" .. group .. "\" is a theme name already", 2)
  end
  local T, names, known, spec = {}, {}, {}, {}
  for _, r in ipairs(list) do
    names[#names + 1] = r[1]
    known[r[1]] = true
    spec[r[1]] = r
  end
  local function member(m)
    if T[m] then return T[m] end
    local r = spec[m]
    if not r then return nil end
    T[m] = make(group .. "." .. m, r[2], r[3], function(n)
      local g, mm = n:match("^(.-)%.(.+)$")
      if not g then return theme[n] end              -- the palette, a role
      if g == group then return member(mm) end       -- this group's own
      return theme[g] and theme[g][mm] or nil        -- another group, if defined
    end)
    return T[m]
  end
  for _, m in ipairs(names) do member(m) end
  for k in pairs(set) do
    local g, m = k:match("^(.-)%.(.+)$")
    if g == group and not known[m] then
      warn("data/theme.lua sets theme." .. k .. ", which the " .. group .. " group doesn't have - ignored")
    end
  end
  if not groups[group] then order[#order + 1] = group end
  groups[group] = { title = title, names = names }
  theme[group] = T
  return T
end

-- theme.undefine(group) - an area's group, when the area unloads
function theme.undefine(group)
  if not groups[group] then return end
  groups[group] = nil
  theme[group] = nil
  for i, g in ipairs(order) do if g == group then table.remove(order, i); break end end
end

-- /theme ------------------------------------------------------------------

-- /theme [text]: every name - or those containing text - as you'd set it
-- in data/theme.lua, in its own colors, what it's made of, where it shows,
-- and "(changed)" where data/theme.lua sets it
local function line(name, c)
  local s = shown[name]
  local label = c(string.format("%-24s", "theme." .. name))
  local tail = (s.desc and (" " .. s.desc) or "") .. (s.changed and (" " .. theme.caution("(changed)")) or "")
  local expr = tail == "" and s.expr or string.format("%-38s", s.expr)
  return "  " .. label .. " " .. theme.muted(expr) .. tail
end
rune.command.add("theme", function(args)
  local q = (args or ""):match("^%s*(.-)%s*$"):lower()
  local function want(name) return q == "" or name:find(q, 1, true) end
  local out = {}
  local function section(title, note)
    out[#out + 1] = theme.heading("[" .. title .. "]") .. (note and theme.muted(" - " .. note) or "")
  end
  local first = true
  for _, n in ipairs(PALETTE) do
    if want(n) then
      if first then section("theme palette", "change one and everything built on it follows"); first = false end
      out[#out + 1] = line(n, pal[n])
    end
  end
  local pending
  for _, r in ipairs(ROLES) do
    if not r[2] then pending = r[1]
    elseif want(r[1]) then
      if pending then section(pending); pending = nil end
      out[#out + 1] = line(r[1], theme[r[1]])
    end
  end
  for _, g in ipairs(order) do
    local G, head = groups[g], true
    for _, m in ipairs(G.names) do
      local name = g .. "." .. m
      if want(name) or want(G.title:lower()) then
        if head then section(G.title); head = false end
        out[#out + 1] = line(name, theme[g][m])
      end
    end
  end
  -- data/theme.lua's changes to groups not defined now
  local idle = {}
  for k in pairs(set) do
    local g = k:match("^(.-)%.")
    if g and not groups[g] and want(k) then idle[#idle + 1] = k end
  end
  if #idle > 0 then
    table.sort(idle)
    section("not loaded", "data/theme.lua sets these; their module isn't loaded (an area out of its zone), or the group is misspelled")
    for _, k in ipairs(idle) do out[#out + 1] = "  " .. theme.muted("theme." .. k .. " = " .. tostring(type(set[k]) == "table" and set[k].expr or set[k])) end
  end
  if #out == 0 then return rune.echo(theme.muted("[theme] no name contains \"" .. q .. "\".")) end
  out[#out + 1] = theme.muted("Change any of these in data/theme.lua, then /reload.")
  for _, l in ipairs(out) do rune.echo(l) end
end, "the theme: every color name you can change in data/theme.lua, shown in its colors (/theme quest - only names containing quest)")

return theme
