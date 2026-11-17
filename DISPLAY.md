# Showing new data on the screen

How to get a new piece of information from the game onto the screen. There
are two halves, and they never mix:

- a **module** (`modules/`) finds the fact and *publishes* it under a name;
- the **layout** (`data/layout/`) places a *widget* that shows that name.

The module never says how the fact looks, and the widget knows nothing
about the game. Between them sit an optional **processor** (the data → the
value the widget compares) and **formatter** (that value → the text shown).

The worked example below counts the rooms you've entered this session and
shows the count on status row 2 as `STP 12`. It uses `room.num`, which
`modules/game.lua` already publishes from GMCP `room.info`. The code was run
in the bench harness (`tools/bench/harness.lua`), but it isn't part of the
config.

## 1. Publish the data (a module)

Create `modules/steps.lua`:

```lua
-- Steps (require("modules.steps")): how many rooms you've entered since
-- login or /reload - a new room number from GMCP room.info.
local view = require("ui.view")
require("modules.game")   -- publishes room.num

local S = view.provides("steps", "rooms entered this session", {
  ["steps.n"] = { "number", "rooms entered since login or /reload" },
})

local n = 0
S.set("steps.n", n)
view.subscribe("room.num", function(_, num)
  if num == nil or num == -1 then return end   -- -1: a maze room, no number
  n = n + 1
  S.set("steps.n", n)
  S.publish()
end)

return {}
```

- `view.provides(module, description, { name = { shape, description } })`
  declares what the module publishes. Shapes: `"number"`, `"percent"`,
  `"seconds"`, `"timestamp"` (an `os.time`), `"text"`, `"block"` (colored
  text, several lines), `"boolean"`, `"ratio"` (`{ cur, max }`, like `hp`),
  `"list"`, `"record"` and `"stream"` (events, such as chat lines) - in
  `ui/view.lua`.
- `S.set(name, value)` is the only way to change it. Setting the same value
  again is no change and costs almost nothing.
- `S.publish()` once at the end of each update. That's when the widgets on
  the data look at it, so several `set`s in one update cost one look.
- Publish the **raw fact**: the count, not "STP 12", not a color. How it
  looks belongs to the layout.
- To get data from the game, a module listens to GMCP (`rune.gmcp.on`), to
  lines (`rune.trigger.*`) or to another module's data (`view.subscribe`,
  as here). ARCHITECTURE.md's "Where information comes from" and "Triggers
  and their cost" cover which to use.

## 2. Show it (the layout)

In `data/layout/status.lua`, in the row 2 part:

```lua
-- STP: rooms entered this session
require("modules.steps")
row2:value { source = "steps.n", label = " STP ", show = F.commas }
```

`/reload`, walk a few rooms: `STP 3`; after 1203 rooms, `STP 1,203`.

- The layout file requires the module it shows, so the module loads
  whenever its widget does. (A module used without a widget is listed in
  `init.lua` instead.)
- `source` is the data name. A list of names gives the processor all of
  them: `source = { "quest.on", "quest.ends" }`.
- `F` is `format/generic.lua` (`num`, `commas`, `short`, `clock` ...), and
  `P` is `process/generic.lua`, both already loaded at the top of the file.

### The generic widgets

Each is a file in `ui/widgets/` with its options in its header. A layout
file requires each one it uses (`require("ui.widgets.value")`).

| Widget | Shows | Example |
|---|---|---|
| `value` | a label and a value: `show` (text), `color` (or `color(v)`), `w` (width), `missing` (while nil), `zero` | `TNL 1234` |
| `tenths` | any number to one place (a `value`) | `HP 87.5` with `process = P.pct` |
| `countdown` | seconds or minutes left until a moment (a `value`) | `TCK 12` |
| `timer` | a length of time as m:ss (a `value`) | DPS's `1:05` |
| `text` | text or rows of text, cut to the width | the room name |
| `indicator` | a fixed text, colored by state | `AC`, `REC` |
| `banner` | text centered on a band | the group's name |
| `block` | a heading and a wrapped body, filling the container; may flash | an alert |
| `barchart` | a bar per row; can count numbers into buckets itself | the affects histogram |
| `widget` | anything: your own `process` and `format` | the breath grid's squares |

Beside them, the containers' own kinds (`ui/screen.lua`'s header):
`c:list` (a row per record: the group's members), `c:append` (a stream:
chat lines), `c:priority` (one item at a time: the info pane) and
`c:container` (a nested group whose state colors what's inside: DPS, PUP).

## 3. A processor and a formatter of your own

When no generic one fits. Say STP should only show whole hundreds,
`STP <100` and then `STP 1200+`:

`process/steps.lua`:

```lua
-- Steps processors (require("process.steps")): modules/steps.lua's data.
local floor = math.floor
local P = {}

-- The count in whole hundreds: 0 under 100, 1 for 100-199 ... - the
-- widget then changes only when a new hundred is reached
function P.hundreds(n) return n and floor(n / 100) end

return P
```

`format/steps.lua`:

```lua
-- Steps formatters (require("format.steps")): process/steps.lua's values.
local M = {}

-- 0 -> "<100", 12 -> "1200+"
function M.hundreds(h) return h == 0 and "<100" or (h .. "00+") end

return M
```

And in the layout:

```lua
local PS, FS = require("process.steps"), require("format.steps")
row2:value { source = "steps.n", label = " STP ", process = PS.hundreds, show = FS.hundreds }
```

- **A processor** gets the sources' values (and `now`, the time) and
  returns **one** value: a number, a string or a boolean, compared with `~=`
  to the last one. Only a change redraws the widget, so round to what will
  be shown. Here the 99 steps between hundreds cost a compare each and no
  redraw. `nil` means nothing to show.
- **A formatter** turns that value into the text (colors included, through
  `theme.*`). It runs only when the value changed.
- **Where they go:** `process/<module>.lua` and `format/<module>.lua`, named
  after the module whose data they read, so a widget moved to another
  container keeps them. One that would suit any MUD goes in
  `process/generic.lua` or `format/generic.lua` instead.
- **Something that changes with the clock** (a countdown): give the widget
  `every = 1`, and have the processor return a second value, the seconds
  until its value can change (`math.huge`: only the data changes it).
  `process/generic.lua`'s `secs_left` and `mins_left` do this.

## 4. A container of its own

To show it somewhere new instead, add a rectangle to
`data/layout/screen.lua`:

```lua
screen:container { name = "steps", x = 0, y = 0, w = 20, h = 3, border = "bottom" }
```

(the other containers' rectangles must change to make room; a gap or an
overlap is an error at load, naming the containers), then a
`data/layout/steps.lua` that fills it (`local p = screen.containers.steps`,
widgets on `p`) and a `require("data.layout.steps")` line in `init.lua`.

## 5. Check it

- `/reload`. A mistake in a layout file is an error at load that names the
  file and line: an unknown widget is `method '<name>' (a nil value)` (its
  `require` is missing), an unknown container lists the ones there are.
- `/profile` while it's showing, to see what it costs (ARCHITECTURE.md's
  Conventions).
- For a change to an existing widget: `tools/bench/` runs the screen
  comparisons and benchmarks on the old and new trees (its README).

## Rules, in short

- Modules publish raw facts, never text or colors.
- Nothing game-specific goes in `ui/widgets/`. How a widget shows (widths,
  labels, buckets, order) goes in its options, in the layout.
- A processor returns one small value, rounded to what's shown.
- Processors and formatters live per module in `process/` and `format/`.
- The layout files only place widgets.
