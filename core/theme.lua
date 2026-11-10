-- The theme (require("core.theme")): every color the config shows.
-- Modules use it and nothing else - never core/colors.lua directly.
-- /theme lists it all: each name as you'd override it, in its own colors,
-- what it's made of, and where it shows.
--
-- Two layers, both overridable in data/theme.lua:
--   the palette  theme.yellow, theme.gray, theme.green_tc ... - the colors
--                the theme works with (core/colors.lua's). Change one and
--                every role built on it follows.
--   the roles    theme.caution, theme.value, theme.quest.ready ... - what a
--                color is FOR, built from the palette. Change one and only
--                it changes. A module's own roles are in a group:
--                theme.map.me, theme.reward.xp ...
-- Built at load in that order - the palette with data/theme.lua's changes,
-- then the roles from it, with its changes - so a role always uses the
-- palette as changed. After load every name is a plain field.
--
-- Each is called on text - theme.value("12") - or gives its bare code as
-- .on, for text that runs on into other colors (colors.RESET ends it).
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

-- A palette name as a ref: worked out once the palette is built
local P = setmetatable({}, { __index = function(_, k) return { ref = k, expr = "theme." .. k } end })

-- The roles: name, default, where it shows. A dotted name is a module's
-- group. { "Heading" } starts a section of /theme
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
  { "REC (status bar)" },
  { "rec.on",    mix(P.black_tc, bg(P.red)), "REC while a log is open, flashing with rec.flash" },
  { "rec.flash", P.red,                      "REC's other flash" },
  { "QST and the quest lines" },
  { "quest.ready",  mix(P.black_tc, bg(P.green)), "QST RD: a quest can be had" },
  { "quest.active", P.yellow, "QST AC: on a quest" },
  { "quest.frame",  P.yellow, "the quest request / complete lines: brackets" },
  { "quest.text",   P.red,    "the same: the values" },
  { "quest.label",  P.white,  "the same: labels" },
  { "Quest and campaign targets (info pane)" },
  { "target.area", P.cyan,    "the area" },
  { "target.room", P.blue,    "the room" },
  { "target.mob",  P.magenta, "the mob" },
  { "target.gone", P.red,     "the room, when the target is killed or gone" },
  { "The group pane" },
  { "group.marker",     P.green,       "L / F / E: leader, followed, both" },
  { "group.title",      P.yellow,      "the group's name, where the game sets no color" },
  { "group.title_band", bg(P.default), "the name's row background" },
  { "The minimap" },
  { "map.header", P.yellow,   "zone | vnum" },
  { "map.word",   P.bold,     "RUNNING / FIGHTING / DARKNESS" },
  { "map.note",   P.cyan,     "the room's note" },
  { "map.me",     P.green_tc, "your dot" },
  { "map.player", P.red,      "another player's square" },
  { "The fight's reward tab" },
  { "reward.tab",  P.dark,     "the triangle" },
  { "reward.bg",   bg(P.dark), "the tab" },
  { "reward.xp",   P.green,    "the xp" },
  { "reward.gold", P.yellow,   "the gold" },
  { "reward.text", P.white,    "the kills" },
  { "2XP / 2QP (status bar)" },
  { "double.xp", P.yellow, "2XP, while on" },
  { "double.qp", P.red,    "2QP, while on" },
  { "3MN, the moons (status bar)" },
  { "moon.soon",    P.cyan,              "a three-moon window soon" },
  { "moon.up",      mix(P.bold, P.yellow), "all three up now" },
  { "moon.unknown", P.yellow,            "??: not known yet" },
  { "Blackclaw" },
  { "bcc.safe",  P.green,              "a safe square, the safe direction" },
  { "bcc.quiet", P.dark,               "an empty square" },
  { "bcc.hot1",  P.yellow,             "a square's count: 1" },
  { "bcc.hot2",  P.orange_tc,          "2" },
  { "bcc.hot3",  P.red,                "3 and up" },
  { "bcc.label", P.gray,               "Axaldra: / safe:" },
  { "bcc.value", mix(P.bold, P.white), "the direction, the center" },
  { "bcc.note",  P.cyan,               "\"The direction ... is now safe!\"" },
  { "bcc.move",  mix(P.bold, P.yellow), "MOVE MOVE MOVE" },
  { "bcc.kill",  mix(P.bold, P.red),   "KILL KILL KILL" },
}
local IS_ROLE, GROUPS = {}, {}
for _, r in ipairs(ROLES) do
  if r[2] then
    IS_ROLE[r[1]] = true
    local g = r[1]:match("^(.-)%.")
    if g then GROUPS[g] = true end
  end
end

-- data/theme.lua's changes, by full name ("yellow", "quest.ready"). The file
-- is run with a table to set them on - theme.yellow = ..., theme.quest.ready
-- = ... - that knows every name: an unknown one is warned about and
-- ignored. Reading a palette name there (theme.yellow) gives a ref, so a
-- change can be built on the palette as changed
local set = {}
local function setter(prefix)
  return function(_, k, v)
    local name = prefix .. tostring(k)
    if not (IS_PALETTE[name] or IS_ROLE[name]) then
      return warn("data/theme.lua sets theme." .. name .. ", which isn't a theme name - ignored")
    end
    set[name] = v
  end
end
local proxies = {}
for g in pairs(GROUPS) do proxies[g] = setmetatable({}, { __newindex = setter(g .. ".") }) end
local proxy = setmetatable({}, {
  __index = function(_, k) return proxies[k] or (IS_PALETTE[k] and P[k]) or nil end,
  __newindex = setter(""),
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
-- there means core/colors.lua's color of that name)
local pal = {}
for _, n in ipairs(PALETTE) do
  local v, c = set[n], nil
  if v ~= nil then
    c = colors.resolve(v, function(k) return colors[k] end)
    if not c then warn("data/theme.lua: theme." .. n .. " isn't a color - ignored") end
  end
  pal[n] = c or colors[n]
  shown[n] = { expr = c and v.expr or colors[n].expr, changed = c ~= nil }
end
local function from_palette(k) return pal[k] end

-- The theme: the palette, then the roles - grouped ones in their group
local theme = {}
for n, c in pairs(pal) do theme[n] = c end
for _, r in ipairs(ROLES) do
  local name, default, desc = r[1], r[2], r[3]
  if default then
    local v, c = set[name], nil
    if v ~= nil then
      c = colors.resolve(v, from_palette)
      if not c then warn("data/theme.lua: theme." .. name .. " isn't a color - ignored") end
    end
    local changed = c ~= nil
    c = c or colors.resolve(default, from_palette)
    local g, m = name:match("^(.-)%.(.+)$")
    if g then
      theme[g] = theme[g] or {}
      theme[g][m] = c
    else
      theme[name] = c
    end
    shown[name] = { expr = changed and v.expr or default.expr, desc = desc, changed = changed }
  end
end

-- /theme [text]: every name - or those containing text - as you'd set it
-- in data/theme.lua, in its own colors, what it's made of, where it shows,
-- and "changed" where data/theme.lua sets it
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
  local any = false
  for _, n in ipairs(PALETTE) do
    if want(n) then
      if not any then out[#out + 1] = theme.heading("[theme palette]") .. theme.muted(" - change one and every role built on it follows"); any = true end
      out[#out + 1] = line(n, pal[n])
    end
  end
  local section
  for _, r in ipairs(ROLES) do
    if not r[2] then section = r[1]
    elseif want(r[1]) then
      if section then
        out[#out + 1] = theme.heading("[" .. section .. "]")
        section = nil
      end
      local g, m = r[1]:match("^(.-)%.(.+)$")
      out[#out + 1] = line(r[1], g and theme[g][m] or theme[r[1]])
    end
  end
  if #out == 0 then return rune.echo(theme.muted("[theme] no name contains \"" .. q .. "\".")) end
  out[#out + 1] = theme.muted("Change any of these in data/theme.lua, then /reload.")
  for _, l in ipairs(out) do rune.echo(l) end
end, "the theme: every color name you can change in data/theme.lua, shown in its colors (/theme quest - only names containing quest)")

return theme
