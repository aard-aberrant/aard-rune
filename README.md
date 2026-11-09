# Aardwolf for Rune

A personal setup for playing [Aardwolf](https://www.aardwolf.com) in the
[Rune](https://github.com/mmcdole/rune) MUD client. It's a port of an earlier
tt++ setup, and replaced it as the only client on 2026-11-06.

It adds a set of panes around the game's output (group, info, minimap, affects,
chats, two status rows), a room map with routing and travel, quest and campaign
helpers, fight tools (autocast, DPS and powerup meters, healing), and quieter
output where the game repeats itself. It reads the game through GMCP and the
game's own tags wherever it can, and through its text only where those can't tell.

## Setup

1. **Rune.** Any recent Rune works. Mouse-wheel scrolling of the side panes needs
   a patched build (`aard-aberrant/rune`, branch `scrolling-panes`); stock Rune
   scrolls only the main output.
2. **This folder** is Rune's config directory: put it at `~/.config/rune`.
   Rune runs `init.lua` from there at start and on `/reload`.
3. **Login.** Copy `.env.example` to `.env` and `chmod 600` it. `core/login.lua`
   answers the name and password prompts from it. Leave out `PASSWORD` to type
   it yourself. `.env` is never committed.
4. **Logs and history** go in `~/.local/state/rune` (or `$XDG_STATE_HOME/rune`).
   Nothing creates folders, so make them once:
   `mkdir -p ~/.local/state/rune/userlogs`.
5. **Connect**, then `/reload` after any change to the files.

## The screen

```
┌──────────────────────────────┬──────────────────────────────────────┐
│ group                        │ chats                     (12 rows)  │
│ (the rest of the height)     ├──────────────────────────────────────┤
│                              │                                      │
├──────────────────────────────┤ main output                          │
│ info              (4 rows)   │                                      │
├────────────┬─────────────────┤                                      │
│ minimap    │ affects         │                                      │
│ 31 x 22    │                 ├──────────────────────────────────────┤
│            │                 │ status row 1: timers, DPS, PUP       │
│            │                 │ status row 2: HP MN MV ... | enemy   │
│            │                 │ input                                │
└────────────┴─────────────────┴──────────────────────────────────────┘
     left column: the rest        right column: 100 wide
```

- **group**: your group, two columns.
- **info**: one thing at a time, by priority: an alert, the quest, the
  campaign, your account. `infopane` lists and pins them.
- **minimap**: the game's own map for your room; RUNNING during a run.
- **affects**: your tracked affects, recoveries, what runs out next.
- **chats**: channels and tells, out of the main output.
- **status row 1**: timers and running measures: TCK (the tick), QST, POP
  (repop), 3MN (moons), DPS, PUP, 2XP/2QP, and REC while `/log` is on.
- **status row 2**: you: HP, MN, MV, alignment, level, TNL, autocast, then
  the enemy's health and name in a fight, else your state.

Sizes are in `core/layout.lua`.

## Commands

`/help` lists everything, Rune's and ours; `/help <text>` searches. Each file's
header comment documents its own commands. The ones used most:

| | |
|---|---|
| `g`, `g <area>` | home and chores; or travel to an area |
| `find <text>`, `ga <text>`, `mf <text>` | go to a label, area or room; in this area; show the route |
| `13s`, `3e2n` | speedwalk |
| `label <word>`, `labels` | name the room you're in |
| `qx`, `qc` | go to the quest mob; home, quest complete, gulp |
| `cn`, `cp` | go to the next campaign mob; the campaign list |
| `target`, `gm <mob>`, `k`, `kk`, `aa` | the target, and your attacks |
| `ac` | autocast on/off |
| `h`, `rh`, `sleep` | heal; heal up between ticks |
| `dps`, `pup` | damage and powerup sessions |
| `eqwear`, `eqsave`, `eqcheck`, `eqsets`, `dt` | gear sets; damage-type weapons |
| `map`, `map info`, `map record` | the game's map; where you are on ours; record a custom exit |
| `timer 5m30` | a countdown on the info pane |

Client tools are slash commands:

| | |
|---|---|
| `/act <text> = <commands>`, `/unact` | your own triggers, kept in `acts.txt` |
| `/copy <n> [chat]` | the last n lines of the main (or chats) pane to the clipboard |
| `/log start [chat] [raw] [file]`, `/log stop` | log to `~/.local/state/rune/userlogs/` |
| `/debug [topic] [on\|off]` | debug output, by topic |

**Keys:** Ctrl+E goes to the end of the input line (Rune's edit-in-editor moves
to Alt+E). F12 switches the mouse between wheel scrolling and selecting text.

## The files

```
init.lua    sets Rune up and loads every feature
core/       shared code: game state from GMCP, tags, layout, help, debug, login,
            history, /act, /copy, aliases
panes/      the panes: status, group, chats, info, affects, timer
gear/       gear sets, what you wear
nav/        the map, routing and travel, minimap, moons, repop
targets/    the target, quest, campaign, doubles, School of Horror keywords
fight/      attacks, autocast, healing, hunting, DPS, powerups, fight summaries
host/       hosting spellups
areas/      one script per zone, loaded only while you're in it
data/       settings and game data (portals, areas, labels, gear sets, classes)
map/        aard.map, the room map (saved as you explore)
tools/      converters from the tt++ data, Rune's API dump, a trigger benchmark
```

Files the setup writes stay here and in git: the map, labels, gear sets, School
of Horror keywords, `acts.txt`, and Rune's own `store.json`. Logs and command
history go to `~/.local/state/rune`.

## More

- `ARCHITECTURE.md`: how the pieces fit, the layering rules, trigger costs,
  shared patterns.
- `TODO.md`: what's ported, what's been confirmed live, what's next.
