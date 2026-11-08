-- Shaman attacks (from tt++ conf/classes.tin). Read by combat.lua:
--   pattack  primary single-target attack - k
--   sattack  secondary attack             - kk
--   paoe     area attack                  - aa
--   pattack_hit  pattack's word in its damage line, after "Your " (gaias
--            fury hits as fury) - ac (autocast.lua) waits for it
--   k_fight  what a bare k sends in a fight (optional; default: pattack
--            with no target - the game aims it at your current enemy)
--   modules  features loaded only on this subclass (optional; init.lua) -
--            every other module loads on every subclass
--   heal     your heal spell, for h and rh (optional; default incomplete healing)
--   hr_min, dr_min, stat_min   the info pane's account view shows HR, DR or
--            a stat in red below these (optional; default 1600, 2000, 600)
return {
  pattack = "c 'gaias fury'",
  pattack_hit = "fury",
  sattack = "c 'tempest'",
  paoe = "c 'call lightning'",
  modules = { "nav.moons" },   -- the 3MN light, moons, weather notices hidden
}
