-- The affects pane's settings (affects.lua), from tt++ conf/affects.tin.
-- Edit, then /reload.
--   track  the affects with a line of their own, by spell number - the
--          {affon}/{affoff} id (slist lists every spell's number):
--            good       true: want it on (the left column, with its time);
--                       false: want it off (a light in the right column)
--            label      what the pane shows - 3 or 4 letters reads best
--            important  a good one that shows black on red while it's off
--                       (else gray)
--            only       the subclass(es) it's for, as GMCP char.base spells
--                       them; none: every character
--            also       a bad one: other affects that light it too, by name
--                       as slist affected gives them, lower case
--          Each column is in spell-number order, as in tt++.
--   bad_extra    affects that count as bad though the game doesn't mark
--                them offensive (attack skills): in the bad sp number, not
--                in the expiry rows or the next-to-expire lines
--   per_block    the histogram's scale: spells per full block
--   totem_icons  shown in place of a totem's type; others show as the word
--   recoveries   spells with a cooldown, in the left column under the good
--                affects: while up, bright with the time left (as a good
--                affect); while recovering, gray with the minutes until
--                ready; ready and not up, the label alone in gray:
--                  name   as the game writes it in slist's recoveries rows
--                         and "You are still recovering your NAME
--                         abilities", any case
--                  label  what the pane shows
--                  sn     its spell number (slist) - its time while up; and
--                         id, its recovery id (the {recon} tag's), if known -
--                         else learned from slist
--                  only   as in track
--                  line   a word: shown on a line of its own at the pane's
--                         foot instead of a row - "<word> ready", or
--                         "<word> ready in 6s" counting down (m:ss above
--                         a minute)
return {
  track = {
    [71]  = { good = true,  label = "SANC", important = true },
    [154] = { good = true,  label = "WOLF", only = { "Shaman" } },
    [72]  = { good = true,  label = "SHLD", important = true },
    [552] = { good = true,  label = "GFOC", only = { "Shaman" } },
    [518] = { good = true,  label = "GREV", only = { "Shaman" } },
    [120] = { good = true,  label = "HGTN", important = true },   -- heighten senses (a skill)
    [66]  = { good = false, label = "POIS" },
    [65]  = { good = false, label = "DISE", also = { "green death" } },
    [29]  = { good = false, label = "CURS" },
    [237] = { good = false, label = "WEB" },
    [81]  = { good = false, label = "WEAK" },
    [6]   = { good = false, label = "BLND", also = { "fire breath" } },
  },
  bad_extra = { ["kobold stench"] = true, ["green death"] = true, ["fire breath"] = true },
  recoveries = {
    { name = "humility",     label = "HUML",     sn = 602, only = { "Priest" } },
    { name = "augmentation", label = "AUGM",         sn = 532, only = { "Priest" } },
    { name = "serenity",     label = "SERE",     sn = 572, only = { "Priest" } },
    { name = "shielding",    label = "HLSH",      sn = 569, only = { "Priest" } },
    -- heavenly smiting's cooldown (aa, ac aoe): the game calls it Smiting -
    -- {recon}37,10 at the cast, "## You may now use Smiting." 10 s later
    -- (userlogs/smit.log, 2026-11-17); spell number 574 (the user). Its own
    -- line (line), not a row
    { name = "smiting", label = "SMIT", sn = 574, id = 37, line = "smite", only = { "Priest" } },
  },
  per_block = 2,
  totem_icons = { Bear = "🐻", Owl = "🦉", Ent = "🌳" },
}
