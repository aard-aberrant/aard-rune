-- Every color in this config (require("core.colors")). The only file that
-- writes a color code: no other Lua file may hold one, nor call
-- rune.style (the user, 2026-11-09). Colors here are named by how they
-- look; what each is FOR is data/theme.lua, which modules use - so a
-- module asks for theme.value, not cyan, and the theme says value = cyan.
--
-- A color is called on text: colors.red("x") is x in red, then a reset
-- (as rune.style's). colors.red.on is the code alone, for text that runs on
-- into other colors; colors.RESET ends it.
--
-- Below: the colors, the codes the game sends that we look for (the
-- game's, not ours), and the helpers that read, strip, convert and cut
-- colored text - modules call the helpers directly.

local colors = {}

local ESC = "\27["
local RESET = ESC .. "0m"
colors.RESET = RESET

-- A color: c.on is its text code, c.bg its background code, c.expr how
-- it's written ("colors.red"). Calling it on text paints the text
-- (c.on .. text .. reset).
local MT = { __call = function(self, s) return self.on .. tostring(s) .. RESET end }
local function style(on, bg) return setmetatable({ on = on, bg = bg }, MT) end
local function code(c) return ESC .. c .. "m" end
local function basic(n) return style(code(n), code(n + 10)) end   -- 31 -> 41, 90 -> 100
local function rgb(r, g, b)
  local v = string.format("%d;%d;%d", r, g, b)
  return style(code("38;2;" .. v), code("48;2;" .. v))
end

-- For the theme (core/theme.lua, data/theme.lua) - modules never use these.
-- bg(x) is x's background; mix(a, b, ...) puts several together (bold and
-- a color, text on a background). Both are recorded, not worked out: x may
-- be a color or a name in the theme's palette (theme.yellow - a ref,
-- { ref = "yellow" }), which is only known once the palette is built. The
-- theme works them out at load with colors.resolve. Each keeps how it was
-- written (.expr), for /theme
function colors.bg(x) return { kind = "bg", arg = x, expr = "bg(" .. x.expr .. ")" } end
function colors.mix(...)
  local args, ex = { ... }, {}
  for i, a in ipairs(args) do ex[i] = a.expr end
  return { kind = "mix", args = args, expr = "mix(" .. table.concat(ex, ", ") .. ")" }
end

-- The same codes under another name (the theme's palette: theme.yellow is
-- colors.yellow, shown as "theme.yellow")
function colors.named(c, expr)
  return setmetatable({ on = c.on, bg = c.bg, off = c.off, expr = expr }, MT)
end

-- x worked out to a color: a color as is, a ref by lookup(name), bg / mix
-- of those. nil if it can't be (not a color, an unknown name, the
-- background of a style that has none)
function colors.resolve(x, lookup)
  if type(x) ~= "table" then return nil end
  if x.ref then return lookup(x.ref) end
  if x.kind == "bg" then
    local c = colors.resolve(x.arg, lookup)
    return c and c.bg and style(c.bg) or nil
  end
  if x.kind == "mix" then
    local on = {}
    for i, a in ipairs(x.args) do
      local c = colors.resolve(a, lookup)
      if not c then return nil end
      on[i] = c.on
    end
    return style(table.concat(on))
  end
  if x.on then return x end
end

-- The colors --------------------------------------------------------------

-- The basic colors - the terminal theme's own, as rune.style's (in
-- ~/.config/ghostty/config's palette: red #FF0000, green #57BF37, yellow
-- #FFFF00, blue #9999FF, magenta #B148B8, cyan #58C2C5, white #C7C7C7,
-- gray - bright black - #676767, dark - the palette's black - #555555)
colors.dark    = basic(30)
colors.red     = basic(31)
colors.green   = basic(32)
colors.yellow  = basic(33)
colors.blue    = basic(34)
colors.magenta = basic(35)
colors.cyan    = basic(36)
colors.white   = basic(37)
colors.gray    = basic(90)

-- The terminal's own text and background (39 / 49: #CCCCCC on #222222) -
-- for text that isn't themed. Unlike a reset, it keeps bold and the rest
colors.default = style(code(39), code(49))

-- Truecolor (_tc): fixed, the same on any terminal theme
colors.black_tc  = rgb(0, 0, 0)        -- the palette's black (dark) is a gray
colors.amber_tc  = rgb(215, 175, 95)   -- #D7AF5F (xterm-256 179)
colors.green_tc  = rgb(0, 255, 0)      -- #00FF00, brighter than the palette's green
colors.orange_tc = rgb(255, 128, 0)
colors.steel_tc  = rgb(75, 100, 160)

-- Styles, not colors (no background). Faint is the terminal's own (the
-- user, 2026-11-09). Underline is ended by .off, not a reset, so it can
-- sit inside a color
colors.bold  = style(code(1))
colors.faint = style(code(2))
colors.underline = style(code(4))
colors.underline.off = code(24)

-- Each color and style knows how it's written, for /theme
for name, c in pairs(colors) do
  if type(c) == "table" and c.on then c.expr = "colors." .. name end
end

-- The game's codes --------------------------------------------------------
-- What the game sends, matched as it comes - not ours to change

colors.game = {
  -- your # on the map: bold magenta (the game's help map key, raw map
  -- blocks /logged 2026-11-09)
  me = ESC .. "1;35m",
  -- another player's * on the map: bold red
  player = ESC .. "1;31m",
  -- a remote social's leading *: "Remote socials are prefixed with a cyan
  -- asterisk" (the game's help); live 2026-11-09 the raw line was
  -- "\e[0;36m*\e[0;37mWarlow smiles at you."
  social = ESC .. "0;36m",
}

-- Aardwolf's own color codes, for text we send to the game (gossip)
colors.aard = {
  red = "@r", bright_green = "@G", bright_yellow = "@Y", white = "@w",
}

-- Helpers -----------------------------------------------------------------

-- A code as a Lua pattern (its [ escaped), to find it with a pattern
function colors.pattern(code) return (code:gsub("[%[%]%(%)%.%%%+%-%*%?%^%$]", "%%%0")) end

-- Text has a color code in it
function colors.has(s) return s:find("\27", 1, true) ~= nil end

-- Text without its color codes
function colors.strip(s) return (s:gsub("\27%[[%d;]*m", "")) end

-- Codes shown as \e, for a debug line
function colors.show(s) return (s:gsub("\27", "\\e")) end

-- Text without Aardwolf's color codes (@x123, @R) - GMCP's names carry them;
-- @@ is a plain @
function colors.uncolor(s)
  return (s:gsub("@x%d%d?%d?", ""):gsub("@(.)", function(c) return c == "@" and "@" or "" end))
end

-- Aardwolf's color codes made terminal colors, to show text as the game
-- will: @r..@w dark (31-37), @R..@W bright (91-97), @D dark gray, @x123
-- the 256-color one, @@ a plain @. Anything else is left as it is
local AARD = { r = 31, g = 32, y = 33, b = 34, m = 35, c = 36, w = 37,
               R = 91, G = 92, Y = 93, B = 94, M = 95, C = 96, W = 97, D = 90 }
function colors.aard_ansi(s)
  s = s:gsub("@x(%d%d?%d?)", ESC .. "38;5;%1m"):gsub("@(.)", function(c)
    if c == "@" then return "@" end
    return AARD[c] and (ESC .. AARD[c] .. "m") or nil
  end)
  return s .. RESET
end

-- The last color code in a raw line, or nil if it has none
function colors.last(raw)
  local found = nil
  for esc in raw:gmatch("\27%[[%d;]*m") do found = esc end
  return found
end

-- Split a raw line into color codes and characters (one UTF-8 character
-- each). Calls f(kind, text) with kind "esc" or "char"
local function each_token(raw, f)
  local i = 1
  while i <= #raw do
    local esc = raw:match("^\27%[[%d;]*m", i)
    if esc then
      f("esc", esc)
      i = i + #esc
    else
      local ch = raw:match("^[\1-\127\194-\244][\128-\191]*", i) or raw:sub(i, i)
      f("char", ch)
      i = i + #ch
    end
  end
end

-- The columns a raw line shows: codes out, then UTF-8 continuation bytes
function colors.width(raw)
  return #(raw:gsub("\27%[[%d;]*m", ""):gsub("[\128-\191]", ""))
end

-- Cut a raw line to w visible columns, keeping its color codes, and end it
-- with a reset (the minimap's rows, the group pane's title). A line that
-- fits - every map row (the game's map is 29 wide, the pane 31) - is only
-- counted, by two native gsubs, not walked a character at a time in Lua.
-- Measured on lunar (2026-11-09, real blocks): ~37 us a map block, was
-- ~220 us; a line too long (a long room name) still costs its walk, ~20 us
function colors.crop(raw, w)
  if colors.width(raw) <= w then return raw .. RESET end
  local out, cols = {}, 0
  each_token(raw, function(kind, t)
    if kind == "esc" then
      out[#out + 1] = t
    elseif cols < w then
      out[#out + 1] = t
      cols = cols + 1
    end
  end)
  return table.concat(out) .. RESET
end

return colors
