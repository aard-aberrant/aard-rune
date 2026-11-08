# Rune trial - TODO

Port of the tt++ setup (aardwolf-tintin) to Rune, piece by piece. Config: init.lua here.

## Done (confirmed live)
- [x] Priest recoveries on the affects pane (confirmed live 2026-11-07): HUML AUGM SERE HLSH -
      bright with the buff's time while up (humility sn 602 right), gray countdown while cooling;
      {recon}/{recoff} ids learned (humility 52, 1800 s); recdebug shows the tags
- [x] inst (confirmed live 2026-11-07): fight/instinct.lua - one line of skills with instinct above 0,
      copied with rune.clipboard.set (OSC 52 reaches the Mac's clipboard)

- Status: bordered two-row pane above the input (a bar can't have a border); row 2 has
  HP/MN/MV in the tt++ "HP 88.2" format and the state or enemy on the right
- Group pane (rune.pane.replace, fills on reload via "request group"); two columns as tt++ (confirmed live 2026-11-07)
- Layout copying bin/tmuxit.sh, no pane titles
- Minimap from the game's <MAPSTART>..<MAPEND> block, hidden from the main output; blank row
  after the room name; your # found as the magenta one (shops are ##), drawn as a pure green ●
  (24-bit colour works through tmux). Shown as the game sends it (it keeps your # fixed itself);
  name = lines before the first blank one, colour carried across lines; note max 2 lines
- Mouse wheel scrolling (main output only)
- No main-pane jump while lines are hidden (2026-11-07): Rune shows a half line (a packet ending
  mid-line) as a temporary row before output triggers see it; util_hide_partial (a prompt
  trigger) holds it back while a hider is on. qc / quest complete no longer flickers
- Campaign (2026-11-07): an area holding a Dead mob goes last in cn's order (its Dead ones
  last in it), (DEAD) in red on the info pane; a room name several areas share opens a
  picker of them (nearest first), walks to the chosen area's entrance, a second cn to the room

## To check

- [ ] Walks as game runs (nav/travel.lua, offline-tested 2026-11-07): plain moves sent as "run 2n3e",
      doors/portals/home as they are; rooms hidden per command that shows one. Check live: a
      multi-direction run ("run 2nd2ns3es" - only single-direction runs tried), a route with a door and
      a portal, and "Too many run errors" naming the failed step
- [ ] fight/quiet.lua (offline-tested on ~/combat): a kill's xp/bonus/gold/tax on one line, shown
      before the next line (or 1 s after); tells reminder only when the count changes; skinning
      (makes / drops / crumbles into dust) hidden with its blank line. Watch for a reward line shape
      not in that log - it shows as before
- [ ] Per-subclass modules (init.lua's last section): Shaman gets 3MN at login and after /reload; a
      Priest doesn't; logging in as the other subclass reloads once
- [ ] Status bars (native rune.ui.bar, status1/status2): two rows as before, no divider between them,
      TCK never skips a second, SCROLLED shows; TCK kept across /reload
- [ ] Chats pane: tells and channels show there, with Aardwolf's colours (not raw codes)
- [ ] Group pane: no flicker in a fight
- [ ] Status pane: state/enemy right-aligned at the screen's right edge (no border now)
- [ ] F12 mouse toggle - trial; the user isn't keen on it. Try Shift+drag; else drop it
- [ ] Shift+PgUp / Shift+PgDn / Shift+End scroll chats (the terminal may take Shift+PgUp)
- [ ] One-row input (no rule under it); the layout swaps to a self-sizing input while any
      picker is open (wraps rune.ui.picker.show/_settle - internal, may break on a Rune update).
      find confirmed live. Check Ctrl+R, the / list, Esc out of each; Ctrl+F isn't covered
- [ ] Status row 1: TCK counts down from each tick, QST shows minutes / RD / AC and survives
      a reload (request quest), TNL, LVL (gone at 201), ALN colours
- [ ] Status row 2 in a fight: " | Enemy 70" (green under 20) and " | DPS 1234  1:23" after
      MV, the enemy's name (no @-codes) on the right; "dps" / "dps reset"; DPS resets on a new area
- [ ] k / kk / aa (fight/combat.lua, offline-tested): attacks from data/classes/<subclass>.lua (shaman,
      bandit, ninja). k <mob>; bare k in a fight = k_fight or pattack; out of one = pattack on
      gm's target by the keyword given to gm. Not ported: autocast's attack.k hook, Ninja spiral
- [ ] Since the last /reload: bare g (fixed), g <area> only, ga, gm, g sendhian (gvozd),
      single-step wall message, minimap exits up one row
- [ ] Walk hiding (core/tags.lua, offline-tested): during g/find/ga/gm/speedwalks only the room you
      arrive in shows; rooms passed are hidden ({rname}..{/roomchars} + blank), the minimap still
      follows. A walk stopped short prints the room it stopped in (at once on a wrong exit, else
      after 5 s) - no look sent. runto hop lines "Name (5882)" always hidden
- [x] Refactor (confirmed live 2026-11-06): shared helpers in core/util.lua, character/room state from GMCP in
      core/game.lua (read by everything else), status pane in panes/status.lua, minimap in nav/minimap.lua -
      init.lua keeps layout, panes, binds. "Walking" is tags.walking() (rooms of a walk still to
      come) instead of travel's 5 s window: a wall bumped just after a walk no longer reports the
      walk going off course. After /reload: status rows, minimap, group pane, walks, gm, k
- [x] Target (targets/target.lua; t, gm, k and qx confirmed live 2026-11-06): one mob - area + keyword, with name and room when
      known. target / target <kw> / target clear; gm goes (area, then the known room, else
      where's); gm <mob> = target + gm; qx = the quest's name/area/room + gm (second qx walks to
      the quest's room). On entering any area, after a walk ends, a hidden where check: learns
      the area (if unset) and the keyword (by name, util.mob_keywords); a same-named mob in
      another area only gets a note. k uses the keyword. Quest end/kill drops a quest target
- [ ] Tag lines: confirmed live 2026-11-06. Still to see: {sfail} (a failed cast) leaving a
      blank line (tt++ hid the blank after it)

## To do

- [ ] Copy commands: copychat [n] and copyout [n] via rune.clipboard.set (OSC 52;
      tmux already has set-clipboard on). Screen selection crosses panes.
- [ ] Minimap: switch to the trigger `span` option instead of the on/off catch-all
- [ ] Minimap: fixed height (22 lines, like MINIMAP_HEIGHT) once its size is settled
- [ ] Minimap fills only after the first move - send "map" at login (tt++ does)
- [ ] Info pane (panes/info.lua, offline-tested): quest (targets/quest.lua), alerts (info.alert - nothing
      calls it until timer/moons/doubles are ported; no beep yet), account fallback. Not
      ported: infopane pin (bcc's grid is areas/blackclaw.lua)
- [x] timer (panes/timer.lua) - confirmed live: flashes black (24-bit) on red with a beep. Survives
      /reload via rune.store. Not ported: timer repop
- [x] infomsg (panes/info.lua) - confirmed live: infomsg <text> shows it, bare infomsg clears
- [ ] Campaign (targets/campaign.lua, offline-tested): cp check read, area/room-based, cn / cn next,
      kills in any order (hidden cp check), info pane 60. Check the "still have to kill" line's
      exact form live. Dropped: cp sum, cp room, level filter for ambiguous rooms
- [x] where refused ("too many doors") - confirmed live: the hidden check shows nothing, gm reports
      it once, a typed where shows one clean line (no {/where}). Rune's own where replies are
      always hidden now - callers report
- [x] Remote socials (init.lua) - confirmed live: "*Name smiles at you." to chats, blanks after
      hidden. Local socials stay in main: no marker or GMCP to tell them from other text
- [x] Affects pane - see below
- [ ] Status row 1: ALN lock colour still to do. 3MN done (nav/moons.lua,
      offline-tested 2026-11-07; needs a live check: rise/fall, the quiet weather at login and home).
      2XP / 2QP done (targets/doubles.lua). POP done (nav/repop.lua, offline-tested 2026-11-07; live:
      grey estimate after sense life, exact after a repop + sense life, pop's comparison lines).
      timer repop: not wanted (2026-11-07)
- [ ] QST (targets/quest.lua, 2026-11-07): RD at the game's ready; during a wait a GMCP request quest
      each tick, the countdown reset when the minutes drop - live: QST reaches RD with the game's message
      (align.tin). TCK QST TNL LVL ALN done (offline-tested) - QST's warning is red, not flashing
- [x] Status row 2: Enemy, DPS (fight/dps.lua), AC (fight/autocast.lua). PUP left off the bar by
      choice (2026-11-07): `pup` reports it (fight/pup.lua, offline-tested). The right side is cut to fit
- [x] Mapper phase 1: tools/convert_ttmap.py turns map/map-all.tt into map/aard.map (TAB
      lines: R vnum area terrain data note name / X from to exit flags cmds). 34,801 rooms,
      90,288 exits, every exit command translated, no dangling exits. Re-run to refresh while
      the tt++ map is the master.
- [x] Mapper phase 2 (confirmed live - mapinfo matches the tt++ map): nav/mapper.lua - loads aard.map at start (1.57 s in Rune, fine - once per reload;
      0.2 s in C Lua), updates from GMCP room.info with gmcp.tin's rules (maze rooms: no
      exits; -1 skipped; only new exits), saves when dirty every 60 s and on "mapsave";
      "mapinfo"
- [ ] Mapper: rearranging subareas (rooms inside normal areas whose exits change). Options:
      1) self-correcting exits - on entering a room, a GMCP direction that leads somewhere else
         than the map says updates the map and logs it (special exits and exit commands kept;
         can't remove vanished exits - hidden exits aren't in GMCP either);
      2) "mapunstable [off]" - mark a room so it stores no exits (maze treatment) and routes
         never use it, for exits that come and go.
      Open question: do those exits change destination, or appear/disappear? Plus phase 3's
      wrong-exit check.
- [ ] Mapper phase 3 (find, g, g icefall confirmed live before the g/ga/gm split; label/unlabel and the wrong-exit message untested): nav/travel.lua + data/{portals,areas,labels}.lua
      (converted once by tools/convert_ttdata.py; Rune's copies are the master). Shortest routes
      with portal and home steps; g, ga, gm, find (picker), label/unlabel/labels, map unlink, the
      wrong-exit message, no-recall marking. Map also saved before /reload and on disconnect.
      Not ported: g's quiet
      gulp/bank replies, the look owed after a walk a fight stops, g.home eq check.
      map exit <vnum> <command> adds exits GMCP doesn't list ("exits" shows them as Custom):
      Radiance Woods linked that way (13657 "explore woods" / 19804 "leave woods").

## Route checks (expected results, re-check after changing costs or the search)

- find duff from home: walks, no portal (portal_cost = 6; confirmed live as g duff)
- g icefall from home: just "enter" (held default portal, cost 1; now via the area)
- find radiance: arrives via "explore woods" from Blake Forest (13657)
- Travel commands (2026-11-06, offline-tested): g = home; g <area> = areas only (exact zone
  or keyword, else part of a name, picker if several; runto if no route); ga <text> = this area:
  label, then room name; gm <mob> = where, set the target, walk; gm = the target again;
  find = everywhere with the picker; gnom = the airship. hf, the shortcut table, the blacklist
  and g's portal/label lookups are gone (g aylor is now just "d" from home).
- g sendhian: "get gvozd portalbag" first; on "You get ..." holds and enters it, else (2 s,
  none left) the usual route. Limited-use portals: zone instead of vnum in data/portals.lua.
- gm: the where reply's room is matched by name in the area you asked from (nearest wins)
- qx to soh (confirmed live 2026-11-07): one step, the soh portal, ending in 30765 (sohtwo) - zones
  sharing a full name (soh/sohtwo) are one area (travel.same_area), so no "enter unknown"

## Report upstream (Rune)

- Bar `right` field clipped one column short ("standin") - no longer affects us (status is a pane now)
- Mouse wheel scrolls only the main output, not the pane under the pointer
- Input: no way to drop its bottom rule while it sizes itself. A fixed size = 1 removes both rules
  but also stops it growing for pickers (results draw inside the input area) - tried live
  2026-11-06, find's picker didn't fit (worked around by swapping the layout). Ask for an input border option (e.g. border = "top")
  or a popup/floating picker mode - either gives the main output one more row
- [x] eqwear, eqsave, eqcheck, eqsets (gear/eq.lua) - all confirmed live 2026-11-06. Sets in data/eqsets.lua (converted from tt++ conf/eqsets.tin),
      hidden eqdata for what's worn, invmon removals for 5 s go back in eqbag. Not ported:
      the level-up notice
- [ ] Modules (offline-tested): every file requires what it uses and returns its table; no
      globals; init.lua is a list of require()s. Rune: Lua 5.1 ("lunar"), require finds files in
      the config dir, /reload starts a fresh Lua state (probed 2026-11-06)
- [x] Beep on crit alerts (util.beep: io.write BEL - rune.echo drops it) - confirmed live
- [x] dt <type> / next / reset, d1-d6 (gear/eq.lua, data/weapons.lua) - dt reset and dN confirmed live.
      Wield slot 24 (invmon wield tracking) confirmed live: "already wielded" shows 2026-11-06
- [x] Aliases (core/aliases.lua): all of tt++ conf/aliases.tin - gh su sq dd hh cc cv
      qa qs qd ll sleep donate tend (aa kk in fight/combat.lua, d1-d6 in gear/eq.lua). su confirmed live
      2026-11-06. Speedwalk (nav/travel.lua) runs an alias of the same name first (su, dd).
      sleep wears the regen ring; the swap back on waking is in fight/rheal.lua
- [x] rt: the blank line(s) after each hidden runto hop line are hidden too (core/tags.lua) - confirmed live
- [x] rh / rh stop / sleep (fight/rheal.lua) - confirmed live. GMCP-driven (HP up after a cast = healed,
      mana down only = fizzle), gear/invmon.lua tracks what's worn (seeded by a hidden eqdata at
      load). Waking with the regen ring on swaps it back
- [x] g (bare) - confirmed live: home's room and its blank line show; gulp/deposit/withdraw
      hidden up to the {/eqdata} of a hidden eqdata that also refreshes invmon's worn list
      (nav/travel.lua home_routine, eq.check_worn)
- [x] ac (fight/autocast.lua, working live 2026-11-06): the tt++ autocast - casts pattack at a fighting char.status
      unless pending; pending clears on the damage line ("Your <pattack_hit> "), a fizzle,
      "on whom?" (game text, like dps - GMCP can't tell which spell landed), or after 6 s.
      AC light on status row 2. (ac trace removed 2026-11-06 - a general logging mechanism comes later)
- [x] qc (targets/quest.lua): home, quest complete, gulp - gulp hidden between two eqdata tags. Confirmed live 2026-11-06
- [x] Affects pane (panes/affects.lua, data/affects.lua; confirmed live 2026-11-06, totem line not yet seen): tracked good/bad
      lights, sk/sp, expiry histogram, next 3 to expire, totem line (Shaman). From {affon}/{affoff}
      and {recon}/{recoff}65, plus a hidden slist affected (char.base at login/reload, a new spell
      number, saf/aff/affects, affectsreset). Totem placed/expired/still-recovering are game text;
      a hidden totem reads time and area. Not ported: Ninja recovery lines, table/graph views.
      core/tags.lua: {sfail} now hides the blank after it
- [x] h (fight/heal.lua, confirmed live 2026-11-06): incomplete healing now, or queued in a fight and sent at the first
      non-fighting char.status; the game's "can't concentrate" refusal (matched for 5 s after the
      send) queues it again while fighting. h stop drops it
- [ ] Review 2026-11-06 (offline: luac, whole setup loaded against a mock Rune): core/layout.lua (pane
      sizes, layout, picker wrapper), panes/group.lua and panes/chats.lua out of init.lua; panes/status.lua has slots
      (row1, row2, row2_end) - QST moved to targets/quest.lua, DPS registers itself, tick countdown in
      core/game.lua (game.tick); util.wrap shared; route search ~30% faster (step made once); zone_of
      indexed; g <area> and qx share go_zones; campaign's hidden cp check queued, not timed
- [ ] Later (user, 2026-11-06): a comprehensive debugging / logging mechanism, and a
      benchmarking one - shared by every module, replacing one-off traces like the old ac trace
      Rune's own `go test ./lua -bench TriggerDispatch` (github.com/mmcdole/rune) measured the
      trigger cost (2026-11-06); in-game timing should cover route search, map load, pane redraws.
- [ ] Moons (nav/moons.lua), kept as the full tt++ port for now (2026-11-07) - revisit with the
      benchmarks: the simple version (rise/fall + ticks only, ~120 lines; up to ~22 min to know all
      three after login), or carrying the phases across a logout (saved at disconnect, moved on by
      the time away / tick length, checked by one weather - unverified that ticks are steady enough)
- [x] g tanra (2026-11-06): the map's Portal Chamber (28357) e exit pointed at 181, really the
      weather observatory - removed with map unlink e, route fine since. Added: mf (route shown, not
      walked), a failed walk names the first step that went wrong, map unlink / map exit (nav/mapper.lua),
      a typed map shows in the main output
- [ ] Mapper: correct an exit when GMCP gives another destination for it? (tt++ only ever adds)
- [ ] Channels: gmcpchannels on sent at load and login (panes/chats.lua) - check ct/gt show only in chats
- [ ] autohunt / autohuntoff / hqq / hqof (fight/hunt.lua, offline-tested): tt++ hunt.tin; hunt replies are
      game text, triggers on only while one runs; a fight pauses autohunt until char.status says
      it's over; hqq's find becomes the target (N.mob). Not ported: huntmaster before hqq
- [ ] Area scripts (areas/loader.lua, offline-tested): loaded on entering the zone, removed on leaving;
      areascripts. geniewish (ftl wff wfa mini), knossos. partroxis (2026-11-07, offline-tested): maze
      navigator (mazerun/mazenext/..., speedrun back after a wrong exit, rooms hidden) and graxkeys.
      Check live: the exits reply's end line, a fight mid-run, the dwarf's room (5830 a guess).
      blackclaw (2026-11-07, offline-tested): breath grid in the info pane, rr/rrs; with fight/bcc.lua
      (bcc, bcc find, the run count in home's room note). bcc confirmed live 2026-11-07. Check live:
      the grid's countdown, rr retreat/plain answers, the whisper line and the count (131 next)
- [ ] spup / spn / spq (host/spup.lua, offline-tested 2026-11-07): tt++ spuphost.tin. Test mode on at every
      load - spup test off to really gossip. Check live: the gossip toggle's
      hint line, the sitting check on a wrapped "is / sitting here." entry
- [ ] 2XP / 2QP (targets/doubles.lua, offline-tested 2026-11-07): tt++ doubles.tin; hidden double at login.
      Check live: the double reply's QP lines and its "not running" lines (tt++ guessed them), whether
      INFO lines come as text or the GMCP info channel (both read)
- [ ] REC at status row 1's right end (panes/status.lua): flashes while Rune's /log is open
