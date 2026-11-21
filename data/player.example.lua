-- A starting point for data/player.lua (copy it there, rename the section
-- to your character, put in your own things). modules/player.lua reads it;
-- /player lists every key a module needs, why, and your value. The
-- password stays in .env.
-- {key} in an alias is its value; {get heal} is "get <item> <medkit>".
return {
  yourname = {
    eqbag     = "eqbag",          -- your eq bag: eqwear, dt, rh
    portalbag = "portalbag",      -- portals taken from it on routes
    medkit    = "medkit",         -- qa qs sq qd get from it ("": from inventory)
    medkit_id = "1234567890",     -- restock: ident medkit's Id (invdata needs it)

    -- restock (at home): each item word, its shop's vnum, the count to keep
    restock = {
      { item = "fugu", vnum = 15855, want = 60 },
    },

    heal  = "quaff heal",         -- qa: the verb, then the item
    mana  = "quaff lotus",        -- qs, sq
    moves = "quaff refresh",      -- qd

    light      = "torch",         -- tend: uncurse, then wear it
    regen_ring = "regen",         -- rh and sleep: worn for regeneration
    wake_ring  = "ring",          -- rh: worn if what the regen ring replaced isn't known

    -- one section per subclass you play: its attacks and the rest (the
    -- spells here are placeholders - put in your own)
    priest = {
      -- k: the command, and its word after "Your " in its damage line (ac)
      pattack = { "c 'first spell'", hit = "first" },
      sattack = { "c 'second spell'", hit = "second" },   -- kk, ac2
      -- aa, ac aoe: the command, and its cooldown as data/affects.lua names it
      paoe = { "c 'area spell'", cooldown = "area" },
      -- optional: k_fight, heal,
      -- su, hr_min, dr_min, stat_min, modules - /player says what each does
    },
  },
}
