-- Your characters' own things (modules/player.lua). Hand-edited; /reload
-- after a change. A section per character, named as the game spells it,
-- lowercased. The password is not here: it stays in .env, which is never
-- committed.
-- Which module needs each key, and why, is declared in that module's code:
-- /player lists them with their values now, and a missing one is warned
-- about at login. Add an item only when an alias or module uses it.
-- Aliases (modules/aliases.lua, and your own /alias) can name any key in
-- braces: {light} is its value; {get heal} is "get <item> <medkit>" (the
-- item: what follows the verb, "fugu" in "eat fugu"; medkit "": nothing).
return {
  aberrant = {
    -- containers
    eqbag     = "eqbag",
    portalbag = "portalbag",
    medkit    = "medkit",

    -- consumables: the verb, then the item
    heal  = "eat fugu",
    mana  = "quaff lotus",
    moves = "quaff refresh",

    -- worn items
    light      = "beacon",
    regen_ring = "3194918450",
    wake_ring  = "flux",

    -- per subclass (the subclass as GMCP char.base spells it, lowercased).
    -- The one playing now is used; see /player for each key
    priest = {
      pattack = { "c 'voice of god'", hit = "piercing sound" },
      sattack = { "c 'finger of death'", hit = "finger of death" },
      paoe = { "c 'heavenly smiting'", cooldown = "smiting" },
      heal = "regeneration",
      su = "spellup luck %0;c 'pure faith';c 'self harmony';spellup int %0;spellup %0",
      dr_min = 1900,
    },
    shaman = {
      pattack = { "c 'gaias fury'", hit = "fury" },   -- gaias fury hits as "fury"
      sattack = "c 'tempest'",
      paoe = "c 'call lightning'",
      modules = { "modules.moons" },   -- the 3MN light, moons, weather notices hidden
    },
    -- In a fight a Bandit can't backstab, so a bare k spirals instead
    bandit = {
      pattack = "backstab",
      sattack = "spiral",
      paoe = "bsall",
      k_fight = "spiral",
    },
    -- A Ninja can backstab in a fight, so a bare k is a backstab there too
    ninja = {
      pattack = "backstab",
      sattack = "spiral",
      paoe = "bsall",
    },
  },
}
