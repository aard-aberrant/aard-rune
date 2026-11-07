-- Weapons for dt (eq.lua), by item id - kept in eqbag. Converted once from
-- tt++ conf/equipment.tin (2026-11-06); hand-editable. One weapon per type.
return {
  primary = 2588531336,   -- what dt reset wields (it's also the electric one)
  types = {
    acid     = 3923061740,
    air      = 3924705475,
    bash     = 3909897131,
    cold     = 3923092631,
    earth    = 3924847359,
    electric = 2588531336,
    holy     = 3923140109,
    magic    = 3922816745,
    negative = 3923136045,
    pierce   = 3928852240,
    water    = 3922806605,
  },
  -- shortcuts: d1 .. d6 = dt <type>
  keys = { "pierce", "holy", "magic", "negative", "water", "cold" },
}
