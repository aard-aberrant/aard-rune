# Architecture

The Aardwolf setup for the [Rune](https://github.com/mmcdole/rune) MUD client, ported
from the tt++ setup in `aardwolf-tintin`. Rune is the only client (tt++ retired
2026-11-06). Rune reads this directory as `~/.config/rune`.

This file is the map: how the pieces fit and the rules they follow. Each file's
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

Rune connects at the login prompts, before any GMCP. `core/login.lua` answers
the name and password prompts from `.env`, which is never committed and is
kept chmod 600 (see `.env.example`). Anything that needs a character in the
game, not just a connection, uses `game.on_login(fn)`. It runs at the first
`char.base` after a load or reconnect.

## Folders and layering

```
core/     util  game  layout  tags  aliases  login
panes/    status  group  chats  info  affects  timer
gear/     eq  invmon
nav/      mapper  travel  minimap  moons
targets/  target  quest  campaign
fight/    combat  autocast  heal  hunt  dps  rheal  pup
host/     spup (hosting spellups)
areas/    loader  + one script per zone (geniewish, knossos, partroxis)
data/     settings and game data (Lua tables), data/classes/<subclass>.lua
map/      aard.map, the room map
tools/    one-time converters from the tt++ data, rune-api.txt (API dump)
```

The folders form layers, top to bottom. A file requires only from its own
folder or one above it in that list, never below. So:

- `core/util`, `core/game` and `core/layout` require nothing of ours.
- **Panes know no features.** A pane offers slots or a provider API, and the
  features plug in. Features require panes, never the other way round.
- **Area scripts may require anything**, because they're loaded last and only
  while you're in their zone.

Every module that others use returns its table (`local game = require("core.game")`).
Lua's `require` runs each file once per Lua state, so the order of the
`require` lines in `init.lua` doesn't matter.

## Where information comes from

In order of preference:

1. **GMCP.** Character, vitals, room, quest, group, channels and the tick. It's
   structured, needs no parsing and costs nothing per line. `core/game.lua`'s
   handlers run first (priority 1) and keep the current values in `game`
   (`game.state`, `game.room.num`, `game.tick` …), so every later handler of the
   same message reads fresh values. Aardwolf sometimes sends numbers as
   strings, so everything goes through `tonumber`.
2. **The game's inline tags.** `{rname}`, `{affon}`, `{invmon}`, `{where}` and
   the like. The tags stay on in the game. `core/tags.lua` has the one
   trigger that looks at tag lines. Features register with
   `tags.on(name, fn)` instead of adding triggers, and `fn(rest, ctx)`
   returning `false` hides the line.
3. **Game text.** Only when neither of the above can tell: DPS, autocast hits,
   hunt replies, campaign lists, the totem, moons, login prompts. Each such
   file's header quotes the lines it matches and where they came from (a log,
   tt++, or seen live). Game messages aren't assumed: a pattern nobody has seen
   live is marked as a guess.

## Triggers and their cost

From Rune's source (`lua/matcher.go`) and benchmarks of this config
(2026-11-06; the note is also in `core/util.lua`):

- **Every registered trigger is matched in Go against every line, disabled ones
  too.** `enabled` is checked in Lua only after a match, and a line with any
  match at all (a disabled one included) goes through Rune's Lua dispatch.
  A line with none skips Lua. So disabling a trigger saves its callback, not
  its match, and a disabled catch-all still sends every line through Lua.
- **Anchored and literal patterns are cheap** (10–90 ns a line). Regexes with a
  leading `.+` or `\w+`, or alternations, cost 600–1300 ns. So: `exact`,
  `starts` or `contains` plus a check in Lua wherever a regex can't be
  anchored with a literal start.
- **No catch-all stays registered.** A catch-all is `rune.trigger.starts("", ...)`
  (a string compare, not the regex `.*`), and one sitting disabled would send
  every line through Lua. Instead:
  - **a block is a Rune span** (`opts.span = { to = ..., max = ... }`, with
    `gag = true` to hide it): one literal header trigger, and its action runs
    once with `ctx.lines`. The minimap block and the room description are spans;
  - `util.group()` holds a declared set of triggers and adds or removes them
    with `set(on)` (hunt, campaign, the totem, the slist and home-routine
    hiders, the walk's room hider, the blank-line eater);
  - `util.await(kind, pattern, fn, name, secs)` waits for one reply to
    something just sent (Rune's `once`), then goes (heal's refusal, the login
    config replies);
  - readers built inline do the same (spup, the partroxis exits, eqdata and slist rows).
- **Adding or removing a trigger rebuilds the matcher,** so a trigger toggled
  every combat round (autocast's) stays registered and disabled.
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
double blank behind. `core/tags.lua` squeezes room-block blanks, and
`util.eat_blanks` follows hidden replies. Nor may it make the main pane
jump: Rune shows half a line (a packet that ends mid-line) as a temporary
row before output triggers see it, so while anything hides lines,
`util_hide_partial` (a prompt trigger) holds that half back. A hider tells it
it's on with `util.group(true)` or `util.hider(fn)`.

**Hiding a walk's rooms.** `tags.hide_rooms(n, owner)` hides the next `n - 1`
room blocks and shows only the last, the room you arrive in. `g` and
speedwalks use it, and so does the Partroxis maze's run back. `owner` (nil for
travel, `"maze"` for Partroxis) tells nav/travel.lua's wrong-exit handling to
leave a walk to whoever started it. A 5 s watchdog shows the held room if a
walk stalls.

**Panes.**
- **`core/layout.lua`** sets every pane's size.
- **`util.pane(name, text)`** writes a pane only when its text changed, so redraws are cheap.
- **The status pane** (`panes/status.lua`) has slots: `row1`, `row1_end`, `row2`
  and `row2_end`. A feature adds functions that return its segment, and calls
  `status.draw()` when its text changes.
- **The info pane** (`panes/info.lua`) is shared by priority with `info.set(name, prio, text)`.
  The lowest priority wins: alerts 20/25, quest 50, campaign 60, account 90.
  `info.alert(level, secs, title, text)` flashes it.

**The target.** `targets/target.lua` holds the one mob you're after: area,
keyword, name and room. Quest (`qx`) and campaign (`cn`) set it, and `k` and
`gm` use it. `target.on_change(fn)` notifies listeners such as the campaign
row.

**Messages.** `util.say` (cyan, news), `util.warn` (yellow, a problem),
`util.err` (red, an error). Every message starts with its module's tag:
`[maze]`, `[eq]`, `[areas]`.

**Aliases.** Rune keys aliases by name, so adding one replaces any other of
that name. An alias's return value is run as a command, so a handler never
does `return rune.send_raw(...)`. One-line aliases live in `core/aliases.lua`,
and everything else sits with its feature.

## Area scripts

`areas/loader.lua` watches GMCP `room.info`. On entering a zone with a file
`areas/<zone>.lua`, it loads that file. On leaving, it removes everything the
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
always-loaded module, not an area script.

## Data and the map

- `data/*.lua` are plain Lua tables loaded with `util.load_data`. Some are
  hand-edited settings (affects, portals, weapons), some are rewritten by
  commands (`eqsave` writes `eqsets.lua`, `label` writes `labels.lua`), and
  `areas.lua` was converted once from tt++.
- `data/classes/<subclass>.lua` holds the attack commands for `k`, `kk` and
  `aa`, chosen by GMCP `char.base` subclass.
- `map/aard.map` is the room map: TAB-separated `R` (room) and `X` (exit)
  lines, about 34,800 rooms. It was converted from tt++ by
  `tools/convert_ttmap.py`, and `nav/mapper.lua` keeps it current from GMCP as
  you walk. `nav/travel.lua` does route search, walks and the travel commands
  on top of it.

## Conventions

- **A header comment in every file:** what it does, its commands, the tt++
  file it came from, the game lines or GMCP messages it reads (with their
  source), and anything dropped from the tt++ version.
- **Efficiency first,** then simplicity. When dropping a minor feature would
  make the code noticeably simpler, that's raised as an option, not done
  silently.
- **GMCP over text,** as above.
- **Syntax-check with `luac -p`** on the Mac. It's Lua 5.5, stricter than Rune's
  Lua 5.1 engine (lunar): you can't assign to a loop variable, for example.
  Offline tests use a mock `rune` table, outside this directory.
- **Secrets stay out:** `.env` is git-ignored and never read by tools.
