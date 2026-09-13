-- Boss fight preset: four of your Pokemon against ONE boss.
--
-- Standardized 16:9 field geometry -- see battle_screen.lua's geometry
-- header and layouts/singles.lua's own note -- with the two deliberate
-- exceptions this preset exists for. First, `boss = true` makes the lone
-- enemy stand at column e5 (col 5, just right of the centre seam) and draws
-- it at the field's natural scale PLUS that +0.6 (x1 x 1.6 = x1.6), so it is
-- clearly the biggest sprite on the field. The boss is CENTRED on e5 and
-- anchored to the TOP of the field (its feet land BOSS_MUL bands down), so it
-- towers over the upper/enemy half rather than standing down on the allies'
-- own ground line. It uses its own headroom, so it is never clipped.
-- Second, because the boss stands to the RIGHT of the centre seam
-- and the four allies start at the far LEFT (cols 1..4), the two
-- groups stay clear of each other.
--
-- Nothing here nudges a sprite or a HUD box: the grid places everything.
return {
  allyCount = 4,
  enemyCount = 1,
  boss = true,
  layout = {},
}
