# Display benchmarks and screen comparisons

Plain Lua (Homebrew `lua`, 5.5) with Rune stubbed: `harness.lua` loads the
real modules from a config tree and feeds them GMCP packages; the info
scripts carry their own copy of the stubs. Rune itself runs Lua 5.1
(Lunar), so absolute numbers differ from live; compare two trees run the
same way, on the same machine, back to back. Live numbers come from
`/profile` (reference-profile-activity).

Every script takes the config tree to load as its first argument, so the
same script runs against the working tree and against an older one.

## An older tree to compare against

From the config folder (the scratch folder must exist and be empty):

```
git archive HEAD | tar -x -C /path/to/scratch/head
```

Any commit works in place of HEAD.

## Benchmarks (µs per message, lower is better)

| Script | Run | Measures |
|---|---|---|
| `vit_bench.lua` | `ROOT small` / `ROOT big` | one char.vitals + the pass; small = invisible HP change, big = visible |
| `gold1.lua` | `ROOT old\|new` | char.worth with gold +1 (display unchanged), the same message again |
| `info_bench.lua` | `ROOT old\|new worth\|stats\|quest\|questidle\|questtick` | the info pane: account updates, quest countdown |
| `chg_prof.lua`, `idle_prof.lua`, `passprof.lua` | as info_bench | the same, split into handler and pass time |
| `key_prof.lua` | `ROOT` | vitals with the bar pass, per part |
| `group_bench.lua`, `group_same.lua` | `ROOT bench\|snap` | the group pane: a changed / a repeated packet |
| `scenario.lua` | `ROOT bench` | every status segment through its states |

`old|new`: `old` is for a tree from before the info pane's data modules
(commit 21d8410 and earlier: `info.alert`, no modules/account.lua); `new`
for one that has them. It also labels the output lines.

`python3 sc_cmp.py BEFORE.txt AFTER.txt`: two saved runs side by side,
medians, sorted by the size of the change (Δ µs, Δ %).

## Screen comparisons (must be identical)

| Script | Run | Compare |
|---|---|---|
| `scenario.lua` | `ROOT snap > out.txt` | `cmp` the two trees' outputs |
| `group_bench.lua`, `group_same.lua` | `ROOT snap > out.txt` | `cmp` |
| `group_snap40.lua` | `ROOT > out.txt` | `cmp` (40 members) |
| `moon_cmp2.lua` | `ROOT > out.txt` | `cmp` (768 moon states) |
| `cases_bench.lua` | `ROOT check > out.txt` | `cmp` |
| `info_drive.lua` | `ROOT old\|new > out.txt` | `python3 cellcmp.py A B`: cell by cell (character, colors, attributes) |

`loadall.lua ROOT`: requires every module init.lua lists; modules.copy and
panes.chats fail only on the stub (no `rune.pane.delete`).
