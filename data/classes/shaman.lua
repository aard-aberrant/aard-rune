-- Shaman attacks (from tt++ conf/classes.tin). Read by combat.lua:
--   pattack  primary single-target attack - k
--   sattack  secondary attack             - kk
--   paoe     area attack                  - aa
--   pattack_hit  pattack's word in its damage line, after "Your " (gaias
--            fury hits as fury) - ac (autocast.lua) waits for it
--   k_fight  what a bare k sends in a fight (optional; default: pattack
--            with no target - the game aims it at your current enemy)
return {
  pattack = "c 'gaias fury'",
  pattack_hit = "fury",
  sattack = "c 'tempest'",
  paoe = "c 'call lightning'",
}
