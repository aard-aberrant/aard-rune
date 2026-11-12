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

Rune connects at the login prompts, before any GMCP. `core/login.lua` answers
the name and password prompts from `.env`, which is never committed and is
kept chmod 600 (see `.env.example`). Anything that needs a character in the
game, not just a connection, uses `game.on_login(fn)`. It runs at the first
`char.base` after a load or reconnect.

## Folders and layering

```
core/     util  game  layout  tags  aliases  login  history  debug  help  profile
panes/    status  group  chats  info  affects  timer
gear/     eq  invmon
nav/      mapper  maprec  travel  minimap  moons  repop
targets/  target  quest  campaign  doubles  soh
fight/    combat  autocast  heal  hunt  dps  rheal  pup  instinct  quiet  bcc
host/     spup (hosting spellups)
areas/    loader  + one script per zone (geniewish, knossos, partroxis, blackclaw)
data/     settings and game data (Lua tables), data/classes/<subclass>.lua
map/      aard.map, the room map
tools/    one-time converters from the tt++ data, rune-api.txt (API dump),
          trigbench/ (what the triggers cost per line)
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
    once with `ctx.lines`. The minimap block, the room description, finger's
    reply and slist's two blocks are spans. A gagged span whose reply was typed,
    or whose closing line never came, shows its lines again in its action;
  - `util.group()` holds a declared set of triggers and adds or removes them
    with `set(on)` (hunt, campaign, the totem, the home-routine
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
- **The status rows** (`panes/status.lua`) are two native Rune bars, `status1`
  and `status2`, which Rune redraws every 250 ms. Row 1 is timers and running measures
  (clocks, countdowns, DPS, PUP), row 2 is you (your stats, then the enemy). A row-1 segment
  with nothing running shows a gray `--`, padded to its usual width. They have slots: `row1`, `row1_end` and `row2`. A feature adds functions
  that return its segment (the text alone; the row adds the spaces), and calls `rune.ui.refresh_bars()` to show a change at once.
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

**Help.** Every command has an entry: the module that makes it registers
it next to its code with `require("core.help").add(name, usage,
description)` (an area script: `A.help(...)`, gone when it unloads).
`core/help.lua` wraps Rune's own `/help`, which lists Rune's commands and
then ours; `/help <text>` searches both. `core/aliases.lua`
registers its one-liners from its own table, so a new one gets help too.
A slash command (`/act`, `/copy`, `/debug`, `/profile` - the client's tools, nothing
to do with the game) needs no entry: Rune's list shows its description.
A new command without a help entry is unfinished.

**Debug output.** `core/debug.lua` holds named topics: a module registers
one with `local dbg = require("core.debug").topic(name, description, status_fn)`
and writes `if dbg.on then dbg.log(msg) end` - the check first, so a debug
line costs nothing to build while its topic is off. `/debug` lists them and
switches them (`/debug <topic> [on|off]`, `/debug all off`). A topic that's
on stays on across `/reload`. Debug code goes in a topic, not a command of
its own. Topics: `act` (core/act.lua), `gmcp` (core/debug.lua), `group`,
`chats`, `recov` (panes/affects.lua), `rooms` (nav/mapper.lua), `minimap`,
`quiet`, `pup`, `dps`, `campaign`.

**Profiling.** `/profile` (`core/profile.lua`) times every callback Rune
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
does `return rune.send_raw(...)` (see Conventions). One-line aliases live in `core/aliases.lua`,
and everything else sits with its feature.

## Per-subclass modules

A module that only one subclass uses goes in that subclass's
`data/classes/<subclass>.lua` as `modules = { ... }` (Shaman: `nav.moons`),
not in `init.lua`. Every other module loads on every subclass, so a class
file lists only its extras. The loader is the last section of `init.lua`:
the subclass comes in GMCP `char.base` and is kept in `rune.session`, so a
`/reload` loads the modules at once. A different subclass later (a remort,
another character) reloads, because Lua can't take a module's triggers and
slots back out. Parts of a shared module that depend on the subclass (the
totem, `only` affects) check `game.subclass` themselves.

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
always-loaded module, not an area script: fight/bcc.lua, with the fight itself
in areas/blackclaw.lua.

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
  any path given (`panes/status.lua` wraps `rune.log.start`). No folder is
  made; a missing one is an error. Rune's `/log` leaves out `rune.echo`; ours
  puts it in (`core/copy.lua` wraps `rune.echo`), so our messages and debug
  topics' lines are in a log, except a chat-only one.
- `data/classes/<subclass>.lua` holds the attack commands for `k`, `kk` and
  `aa`, chosen by GMCP `char.base` subclass.
- `map/aard.map` is the room map: TAB-separated `R` (room) and `X` (exit)
  lines, about 34,800 rooms. It was converted from tt++ by
  `tools/convert_ttmap.py`, and `nav/mapper.lua` keeps it current from GMCP as
  you walk; `nav/maprec.lua` (map record) adds the custom exits GMCP can't show.
  `nav/mapper.lua` also owns the rest of the world's data - areas
  (`data/areas.lua`: names, `same_area`, `zone_of`) and room labels
  (`data/labels.lua`, `map label`) - and requires nothing of the modules that
  use it. `nav/travel.lua` does route search, walks and the travel commands
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
