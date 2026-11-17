# Architecture

The Aardwolf setup for the [Rune](https://github.com/mmcdole/rune) MUD client, ported
from the tt++ setup in `aardwolf-tintin`. Rune is the only client (tt++ retired
2026-11-06). Rune reads this directory as `~/.config/rune`.

This file is the map: how the pieces fit and the rules they follow. `README.md`
has the setup, the screen and the main commands. Each file's
header comment documents its own commands and the game messages it reads.
`TODO.md` tracks what's ported, what's been confirmed live, and what's next.

## Startup

`init.lua` does four things:

1. Subscribes to the GMCP packages: Char, Room, Comm, Core, Group.
2. Sets up Rune itself: key bindings (Ctrl+E, Alt+E, F12 for the mouse) and the
   jump to live output when you send a command while scrolled back.
3. `require`s every feature, grouped by folder.
4. Asks the game for `char`, `group`, `room` and `quest`, because `/reload`
   starts every Lua table empty and the game only sends those when they change.

`/reload` throws away the whole Lua state and runs `init.lua` again. Anything
that has to survive a reload (the quest's start time, a running timer, the
moons' phases, the rings rh swapped out) goes in `rune.store`.

Rune connects at the login prompts, before any GMCP. `modules/login.lua` answers
the name and password prompts from `.env`, which is never committed and is
kept chmod 600 (see `.env.example`). Anything that needs a character in the
game, not just a connection, uses `game.on_login(fn)`. It runs at the first
`char.base` after a load or reconnect.

## Folders and layering

```
lib/            util  debug  help  profile
ui/             colors  theme  view  screen  pin  picker
ui/widgets/     value  tenths  timer  countdown  text  indicator  banner  block  barchart
process/        generic  + one per module: affects  group  quest  campaign  account  bcc
                repop  moons  dps  pup  game  minimap
format/         generic  + the same, and chats  log
modules/        game  tags  group  aliases  login  history  copy  act  chats  log
                mapper  maprec  travel  minimap  moons  repop
                target  quest  campaign  doubles  soh
                combat  autocast  heal  hunt  dps  rheal  pup  instinct  quiet  bcc
                eq  invmon  spup
modules/zones/  loader  + one script per zone (geniewish, knossos, partroxis, blackclaw)
data/           settings and game data (Lua tables), data/classes/<subclass>.lua
data/layout/    the screen: screen (the containers) + status  group  chats  info  affects  minimap
map/            aard.map, the room map
tools/          one-time converters from the tt++ data, rune-api.txt (API dump),
                trigbench/ (what the triggers cost per line), bench/ (the display's
                benchmarks and screen comparisons)
```

Organized by module (2026-11-15; the display 2026-11-16), in these kinds:

- **Libraries** (`lib/`, `ui/`, `process/generic.lua`, `format/generic.lua`):
  game-agnostic code the rest builds on - the framework. They require nothing
  in `modules/` or `data/layout/`. The widgets in `ui/widgets/` are all
  generic: nothing in them knows Aardwolf.
- **Modules** (`modules/`): anything that does something in the game or knows
  Aardwolf, even when many others require it (`game`, `tags`, `mapper`). A
  module requires the libraries and the modules it uses; requires never go in
  a circle. Modules publish raw facts (`ui/view.lua`) and know no container.
- **Processors and formatters** (`process/<module>.lua`, `format/<module>.lua`):
  what one module's data becomes on the screen - the value a widget compares
  (rounded to what's shown, several facts packed into one number where a row
  shows several) and the text it shows. One file per module, not per
  container, so a widget moved to another container takes its processor along.
- **The layout** (`data/layout/`): placement only - which generic widget shows
  which data, with which processor and formatter, and the display's own
  settings (widths, labels, colors, a chart's buckets). `screen.lua` places the
  containers; one file per container fills it. For another MUD, the same
  widgets are configured on that MUD's modules. `/data` lists the data names
  there are (`ui/view.lua`); at load `init.lua` warns about any a layout uses
  that no module provides (`ui/screen.lua`'s `check`), except where the layout
  marks it `optional = true` - a module that loads only sometimes.
- **Zone scripts** (`modules/zones/`) may require anything, because they're
  loaded last and only while you're in their zone.

Every module that others use returns its table (`local game = require("modules.game")`).
Lua's `require` runs each file once per Lua state, so the order of the
`require` lines in `init.lua` doesn't matter.

## Where information comes from

In order of preference:

1. **GMCP.** Character, vitals, room, quest, group, channels and the tick. It's
   structured, needs no parsing and costs nothing per line. `modules/game.lua`'s
   handlers run first (priority 1) and keep the current values in `game`
   (`game.state`, `game.room.num`, `game.tick` …), so every later handler of the
   same message reads fresh values. Aardwolf sometimes sends numbers as
   strings, so everything goes through `tonumber`.
2. **The game's inline tags.** `{rname}`, `{affon}`, `{invmon}`, `{where}` and
   the like. The tags stay on in the game. `modules/tags.lua` has the one
   trigger that looks at tag lines. Features register with
   `tags.on(name, fn)` instead of adding triggers, and `fn(rest, ctx)`
   returning `false` hides the line.
3. **Game text.** Only when neither of the above can tell: DPS, autocast hits,
   hunt replies, campaign lists, the totem, moons, login prompts. Each such
   file's header quotes the lines it matches and where they came from (a log,
   tt++, or seen live). Game messages aren't assumed: a pattern nobody has seen
   live is marked as a guess.

## Triggers and their cost

From Rune's source (`lua/matcher.go`, `lua/core/50_triggers.lua`) and
benchmarks of this config (2026-11-06; the note is also in `lib/util.lua`):

- **Every enabled trigger is matched in Go against every line; disabled ones
  cost nothing** (Rune PR #174, "skip disabled triggers in Go"; before it they
  were matched too). A trigger in a disabled group counts as disabled. A line
  with any match goes through Rune's Lua dispatch; a line with none (and no
  open span) skips Lua. Enabling or disabling a trigger only marks the list
  changed: the next line brings the matcher's on/off flags up to date in one
  Go call (and a Lua loop over that pass's triggers), once per batch of
  changes.
- **Anchored and literal patterns are cheap** (10–90 ns a line). Regexes with a
  leading `.+` or `\w+`, or alternations, cost 600–1300 ns. So: `exact`,
  `starts` or `contains` plus a check in Lua wherever a regex can't be
  anchored with a literal start.
- **No catch-all stays on.** A catch-all is `rune.trigger.starts("", ...)`
  (a string compare, not the regex `.*`), and while it's enabled every line
  goes through Lua. Disabled it costs nothing, so a reader is on only while
  it's needed:
  - **a block is a Rune span** (`opts.span = { to = ..., max = ... }`, with
    `gag = true` to hide it): one literal header trigger, and its action runs
    once with `ctx.lines`. The minimap block, the room description, finger's
    reply and slist's two blocks are spans. A gagged span whose reply was typed,
    or whose closing line never came, shows its lines again in its action;
  - `util.group()` holds a declared set of triggers and enables or disables
    them together with `set(on)` (hunt, campaign, the totem, the home-routine
    hiders, the walk's room hider, the blank-line eater);
  - `util.await(kind, pattern, fn, name, secs)` waits for one reply to
    something just sent (Rune's `once`), then goes (heal's refusal, the login
    config replies);
  - readers built inline do the same (spup, the partroxis exits, eqdata rows).
- **Measure, don't guess:** `tools/trigbench` reads every trigger pattern
  from the config and times them against real /log files (`go test -bench .
  -args ~/combatmsg ...`). 2026-11-08: 50 permanent triggers, ~0.9 µs a line
  (literals ~8 ns each, regexes 15-115 ns). Rune's own `/triggers` lists them.
  That is the Go matcher only; `/profile` times the Lua side, live (below).
- **Adding or removing a trigger rebuilds the matcher,** so a trigger toggled
  often (autocast's, every combat round) stays registered and is enabled and
  disabled - which, since PR #174, costs nothing per line while off.
- **Timers are cancelled, not outlived.** `rune.timer.after` returns a handle with
  `:cancel()`. `util.slot()` is a timer that replaces its waiting one
  (`start(secs, fn)`, `stop()`), in place of tt++-style generation counters.

## Shared patterns

**Hidden queries.** Many features send a command and read its reply without
showing it: `slist`, `totem`, `where`, `exits`, `cp check`, `weather`,
`eqdata`. Each keeps a FIFO queue of what it sent (`true` means hidden, `false`
means typed by you and shown), so a typed command and a hidden one waiting in
the game's queue can't be confused. A reply's triggers are switched on only
while one is expected, and a timeout empties the queue if no reply comes.
`util.eat_blanks` hides the blank lines the game sends after a hidden reply.

**No stray blank lines.** Anything that hides lines must not leave a blank or
double blank behind. `modules/tags.lua` squeezes room-block blanks, and
`util.eat_blanks` follows hidden replies. Nor may it make the main pane
jump: Rune shows half a line (a packet that ends mid-line) as a temporary
row before output triggers see it, so while anything hides lines,
`util_hide_partial` (a prompt trigger) holds that half back. A hider tells it
it's on with `util.group(true)` or `util.hider(fn)`.

**Hiding a walk's rooms.** `tags.hide_rooms(n, owner)` hides the next `n - 1`
room blocks and shows only the last, the room you arrive in. `g` and
speedwalks use it, and so does the Partroxis maze's run back. `owner` (nil for
travel, `"maze"` for Partroxis) tells modules/travel.lua's wrong-exit handling to
leave a walk to whoever started it. A 5 s watchdog shows the held room if a
walk stalls.

**The screen.**
- **`data/layout/screen.lua`** places every container and sets their sizes.
- **The status rows** (`data/layout/status.lua`) are two native Rune bars, `status1`
  and `status2`, which Rune polls every 250 ms. Row 1 is timers and running measures
  (clocks, countdowns, DPS, PUP), row 2 is you (your stats, then the enemy). A row-1 segment
  with nothing running shows a gray `--`, padded to its usual width. Each segment is a generic
  widget on data a module publishes, so the modules know nothing of the rows. DPS and PUP are
  nested containers: their state (live, last, none) picks the colors of the widgets inside.
- **The info pane** (`data/layout/info.lua`) is a priority container: the first item with
  something to show wins - Black Claw Crag's grid, alerts, infomsg, quest, campaign, account.
  Each item is widgets on a module's data. `infopane` (`ui/pin.lua`, for any priority
  container) lists the items and pins one. `alerts.alert(level, secs, title, text)`
  (`modules/alerts.lua`) flashes it; an alert counts down only while it's shown
  (`info.shown`, published by the container).

**The target.** `modules/target.lua` holds the one mob you're after: area,
keyword, name and room. Quest (`qx`) and campaign (`cn`) set it, and `k` and
`gm` use it. `target.on_change(fn)` notifies listeners such as the campaign
row.

**Messages.** `util.say` (cyan, news), `util.warn` (yellow, a problem),
`util.err` (red, an error). Every message starts with its module's tag:
`[maze]`, `[eq]`, `[zones]`.

**Help.** Every command has an entry: the module that makes it registers
it next to its code with `require("lib.help").add(name, usage,
description)` (a zone script: `A.help(...)`, gone when it unloads).
`lib/help.lua` wraps Rune's own `/help`, which lists Rune's commands and
then ours; `/help <text>` searches both. `modules/aliases.lua`
registers its one-liners from its own table, so a new one gets help too.
A slash command (`/act`, `/copy`, `/debug`, `/profile` - the client's tools, nothing
to do with the game) needs no entry: Rune's list shows its description.
A new command without a help entry is unfinished.

**Debug output.** `lib/debug.lua` holds named topics: a module registers
one with `local dbg = require("lib.debug").topic(name, description, status_fn)`
and writes `if dbg.on then dbg.log(msg) end` - the check first, so a debug
line costs nothing to build while its topic is off. `/debug` lists them and
switches them (`/debug <topic> [on|off]`, `/debug all off`). A topic that's
on stays on across `/reload`. Debug code goes in a topic, not a command of
its own. Topics: `act` (modules/act.lua), `gmcp` (lib/debug.lua), `group`,
`chats` (modules/chats.lua), `recov` (modules/affects.lua), `rooms` (modules/mapper.lua), `minimap`,
`quiet`, `pup`, `dps`, `campaign`.

**Profiling.** `/profile` (`lib/profile.lua`) times every callback Rune
runs - trigger, span, GMCP, timer, hook, bar, alias, command, bind. They all
go through `rune.guarded_call`; `/profile on` swaps a timing wrapper into
that field and `/profile off` puts Rune's own function back, so off costs
nothing and no module needs code for it. To check a change: `/profile on`,
a set activity, `/profile save before`; make the change, `/reload`;
`/profile on`, the same activity, `/profile save after`; `/profile compare
before after`. Compare shows each handler's mean before and after, in µs
and %, the largest change first (the top 30; `compare <a> [b] all` for
every one), plus Lua ms a second and any change in registered triggers.
It flags nothing: read the µs - a handler going from 1 to 3 µs is noise
(live, small handlers vary up to ~10 µs run to run), and even +5 µs on every
line is ~0.25 ms a second at 50 lines/s. Runs are saved as
`profile-<name>.tsv` in `~/.local/state/rune`. `/profile startup` reloads
and times each require in init.lua. The clock is `os.clock` (process CPU),
fine for means over many calls, rough for one.

**Aliases.** Rune keys aliases by name, so adding one replaces any other of
that name. An alias's return value is run as a command, so a handler never
does `return rune.send_raw(...)` (see Conventions). One-line aliases live in `modules/aliases.lua`,
and everything else sits with its feature.

## How the screen is redrawn

The display engine is `ui/screen.lua`; its header documents every call.
`DISPLAY.md` walks through adding a data source and showing it. In short:

**Containers and widgets.** `screen:container { name, x, y, w, h, border,
title }` is a rectangle that becomes a Rune pane (a one-row one, a bar).
Widgets go in it: `c:widget { source, process, format, every, w, x, y }`,
and the generic widgets in `ui/widgets/` built on it (`c:value`, `c:tenths`,
`c:barchart` ...). Beside them: `c:list` (a row per record, each compared on
its own), `c:append` (a stream, each event added), `c:priority` (items, the
first with something wins) and `c:container` (nested: one entry in its
parent's line, whose state picks its children's colors).

**A widget.** `source` (data names) -> `process(v..., now)`, which returns
one value -> compared with `~=` to the last; only a change marks the widget
dirty. `format(value)` makes the text, and runs only for a dirty widget.
A processor rounds to what's shown, so a change you couldn't see does
nothing: gold 2,500,000 -> 2,500,001 is "2.5M" either way (`P.round`), HP
69,960 -> 69,990 of 88,000 is 79.5% either way (`c:tenths`). Where a row
shows several things, the processor packs them into one number (the
affects rows, a group member), so the comparison is still one `~=`. The
stored data is always exact - `view.get` and subscribers see 2,500,001.

**Passes.** A module's `set` runs the processors of the widgets on that
name; a changed one is dirty and asks for a pass. Rune runs the pass once
at the end of the event (a packet, a key, a timer), however many values
changed: dirty widgets are formatted, their lines rebuilt, each changed
container written once. A widget dirty already isn't processed again on
more changes in the same event - it's processed once more at the pass.
Nothing dirty: the pass does nothing.

**Timed widgets.** `every = n` processes a widget at most every n seconds,
on the bar poll - never a Rune timer of its own. A timed processor may
return a second value, the seconds until its value can change (`math.huge`:
only its data changes it); the widget isn't looked at again until then.

**Adding to it.** A generic widget is a file in `ui/widgets/` that registers
itself (`screen.add_widget(name, fn)` -> `c:name {...}`); a layout file
requires each widget it uses. A processor or formatter is a plain function:
generic ones in `process/generic.lua` / `format/generic.lua`, one module's in
`process/<module>.lua` / `format/<module>.lua`. Nothing game-specific goes in
a widget; settings for how it shows (a chart's buckets, a list's order and
length) go in its constructor, in the layout file.

## Per-subclass modules

A module that only one subclass uses goes in that subclass's
`data/classes/<subclass>.lua` as `modules = { ... }` (Shaman: `modules.moons`),
not in `init.lua`. Every other module loads on every subclass, so a class
file lists only its extras. The loader is the last section of `init.lua`:
the subclass comes in GMCP `char.base` and is kept in `rune.session`, so a
`/reload` loads the modules at once. A different subclass later (a remort,
another character) reloads, because Lua can't take a module's triggers and
slots back out. Parts of a shared module that depend on the subclass (the
totem, `only` affects) check `game.subclass` themselves.

## Zone scripts

`modules/zones/loader.lua` watches GMCP `room.info`. On entering a zone with a file
`modules/zones/<zone>.lua`, it loads that file. On leaving, it removes everything the
script added. A script costs nothing anywhere else, and its triggers can't
take a line from anything else there.

A script is a chunk called with one argument, `A`, which mirrors `rune.*` but
records every handle:

- `A.trigger.regex/exact/starts/contains`
- `A.alias.exact/regex`: refuses a name that exists outside the area, because
  removing it later would delete the outside one
- `A.timer.after/every`, `A.gmcp.on`, `A.hooks.on`
- `A.on_unload(fn)`, `A.keep()` (stay until the next zone change), `A.zone`

The loader loads a script from inside the zone's first `room.info`, so the
script's own `room.info` handlers miss that one. A script that needs the
current room reads `game.room` when it loads (partroxis does).

A command that has to work from outside its area (`bcc find`) belongs in an
always-loaded module, not a zone script: modules/bcc.lua, with the fight itself
in modules/zones/blackclaw.lua.

## Data and the map

- `data/*.lua` are plain Lua tables loaded with `util.load_data`. Some are
  hand-edited settings (affects, portals, weapons), some are rewritten by
  commands (`eqsave` writes `eqsets.lua`, `map label` writes `labels.lua`), and
  `areas.lua` was converted once from tt++. Every file this config writes
  (those, the map, history, soh keywords) goes through `util.write_file`: a
  .tmp file renamed into place.
- Logs aren't config: they go in `util.state_dir`, which is `$XDG_STATE_HOME/rune`
  or `~/.local/state/rune`. `util.append_log` adds a line to `dps.log` or `pup.log`,
  one per finished session, and `util.log_tail` reads the last few back.
  Rune's `/log` files go in `userlogs/` there, with `userlogs/` as the root of
  any path given (`modules/log.lua` wraps `rune.log.start`). No folder is
  made; a missing one is an error. Rune's `/log` leaves out `rune.echo`; ours
  puts it in (`modules/copy.lua` wraps `rune.echo`), so our messages and debug
  topics' lines are in a log, except a chat-only one.
- `data/classes/<subclass>.lua` holds the attack commands for `k`, `kk` and
  `aa`, chosen by GMCP `char.base` subclass.
- `map/aard.map` is the room map: TAB-separated `R` (room) and `X` (exit)
  lines, about 34,800 rooms. It was converted from tt++ by
  `tools/convert_ttmap.py`, and `modules/mapper.lua` keeps it current from GMCP as
  you walk; `modules/maprec.lua` (map record) adds the custom exits GMCP can't show.
  `modules/mapper.lua` also owns the rest of the world's data - areas
  (`data/areas.lua`: names, `same_area`, `zone_of`) and room labels
  (`data/labels.lua`, `map label`) - and requires nothing of the modules that
  use it. `modules/travel.lua` does route search, walks and the travel commands
  on top of it.

## Conventions

- **A header comment in every file:** what it does, its commands, the tt++
  file it came from, the game lines or GMCP messages it reads (with their
  source), and anything dropped from the tt++ version.
- **Efficiency first,** then simplicity. When dropping a minor feature would
  make the code noticeably simpler, that's raised as an option, not done
  silently.
- **GMCP over text,** as above.
- **Rune's native features first.** Where Rune has a feature for a job, use it
  rather than building one in Lua. For example: bars (`rune.ui.bar`) for the
  status rows, spans and groups for hiding output, `rune.session`/`rune.store`
  for state, `rune.history` for command history. Rune's version is usually
  cheaper (Go, not Lua), steadier (its bars redraw on a fixed 250 ms clock,
  where `rune.timer.every` slips), and less code. Build your own only where
  Rune has nothing, or its version can't do the job; then say why in the
  file's header.
- **A call that returns nothing is never used as a return value:**
  `if bad then warn(x); return end`, not `return warn(x)`. `return f(...)`
  only where f gives a value the caller uses - a string, `false` to hide a
  line (`return util.hide(ctx)`), or a wrapper passing on what it wraps.
  (An alias's return value is run as a command, so a returned value there
  is never an accident.)
- **Syntax-check with `luac -p`** on the Mac. It's Lua 5.5, stricter than Rune's
  Lua 5.1 engine (lunar): you can't assign to a loop variable, for example.
  Offline tests use a mock `rune` table, outside this directory.
- **Secrets stay out:** `.env` is git-ignored and never read by tools.
