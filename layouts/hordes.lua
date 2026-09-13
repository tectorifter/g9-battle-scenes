-- Horde preset: five enemies against one of yours.
--
-- Standardized 16:9 field geometry -- see battle_screen.lua's geometry
-- header and layouts/singles.lua's own note. `horde = true` puts the lone
-- ally at column a2 (col 2), facing the swarm, while the five enemies take
-- e2..e6 across the right half; each enemy now carries its OWN HUD box, over
-- its own slot, in one even row at the side's shared head line (see
-- battle_screen.lua's GUI placement header / spreadBoxCentres). Five is the
-- widest shipped row: 5*56.4 + 4*2 = 290px, inside the 320px canvas, so keep
-- this preset at five -- a sixth box would no longer fit.
return {
  allyCount = 1,
  enemyCount = 5,
  horde = true,
  layout = {},
}
