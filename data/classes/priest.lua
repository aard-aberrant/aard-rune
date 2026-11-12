-- Priest attacks. Read by combat.lua:
--   pattack  primary single-target attack - k
--   sattack  secondary attack             - kk
--   paoe     area attack                  - aa
--   pattack_hit  pattack's word in its damage line, after "Your " (gaias
--            fury hits as fury) - ac (autocast.lua) waits for it
--   k_fight  what a bare k sends in a fight (optional; default: pattack
--            with no target - the game aims it at your current enemy)
return {
  pattack = "c 'voice of god'",
  pattack_hit = "piercing sound",
  sattack = "c 'finger of death'",
  paoe = "c 'heavenly smiting'",
  heal = "regeneration",   -- h and rh
  -- su (core/aliases.lua): this subclass's own, in place of the shared one
  su = "autoassist off;spellup luck %0;c 'pure faith';c 'self harmony';spellup int %0;spellup %0;autoassist on",
  dr_min = 1900,
}
