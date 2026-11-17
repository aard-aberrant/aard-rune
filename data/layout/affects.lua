-- The affects pane: generic widgets on modules/affects.lua's data, through
-- process/affects.lua (what each compares) and format/affects.lua (its text):
--   the tracked affects (data/affects.lua): good ones on the left with
--     minutes left - green, yellow at 2 min, red at 1; off: gray, or black
--     on red for an important one - and bad ones as lights on the right,
--     gray, black on red while on you
--   recoveries (data/affects.lua, by subclass) under the good affects: while
--     the spell is up, bright with its time left (as a good affect); while
--     it recovers, gray with minutes until ready; ready, the label in gray
--   sk: N  sp: good/bad - everything that's up
--   the expiry histogram - how many good spells and skills (not the tracked
--     ones, which have their own times) run out within 30s, 1m, 2m, 5m, 10m
--   the next three of them to run out, by name, colored by how soon
--   Shaman: the totem - type, minutes left, area; then Create Totem's
--     recovery, "totem ready"
--   recoveries with a line of their own (data/affects.lua's line - Priest:
--     smite): "smite ready" green, "smite ready in 6s" gray (m:ss
--     above a minute)
require("data.layout.screen")
require("modules.affects")
local screen = require("ui.screen")
local theme = require("ui.theme")
require("ui.widgets.barchart")   -- panel:barchart (the histogram)
local P = require("process.affects")
local F = require("format.affects")

local p = screen.containers.affects
local SRC = { "subclass", "affects" }
-- a line of its own, the container's width; a nil processed value shows nothing
local function line(t)
  local f = t.format
  t.y, t.source, t.w = "next", SRC, "*"
  t.format = function(v, w) if v ~= nil then return f(v, w) end end
  return p:widget(t)
end

-- the tracked affects and recoveries, a row each
for i = 1, P.nrows do line { every = 1, process = P.row(i), format = F.row(i) } end

-- sk / sp, then a gap
line { process = P.counts, format = F.counts }
line { process = P.seen, format = F.blank }

-- the histogram: how many run out within 30 s, 1, 2, 5, 10 min (exactly
-- 60 s left is 1m), a bar per band
local RED, YEL, GRN = theme.danger, theme.caution, theme.good
p:barchart {
  source = SRC, every = 1, values = P.moments, scale = P.cfg.per_block or 2, cells = 10,
  buckets = { 30, 60, 120, 300, 600 }, moments = true, sorted = true,
  labels = { "30s", "1m", "2m", "5m", "10m" }, colors = { RED, RED, YEL, GRN, GRN }, zero = theme.unavailable,
}

-- a gap, then the next three to run out, each in its band's color
line { every = 1, process = P.any_timers, format = F.blank }
p:list { source = SRC, every = 1, max = 3, records = P.timers, key = "name",
  process = P.timer_band, format = F.timer }

-- a gap, then the totem (Shaman)
line { every = 1, process = P.any_totem, format = F.blank }
line { every = 1, process = P.totem, format = F.totem }

-- a gap, then the recoveries on lines of their own (Priest: smiting)
line { process = P.any_cooldown, format = F.blank }
for i = 1, P.nlines do line { every = 1, process = P.cooldown(i), format = F.cooldown } end
