-- Doubles preset: two Pokemon per side.
--
-- Standardized 16:9 field geometry -- see battle_screen.lua's geometry
-- header and layouts/singles.lua's own note. `layout` is empty on purpose:
-- the two allies take a1,a2 and the two enemies e5,e6, all at the shared
-- natural sprite scale.
return {
  allyCount = 2,
  enemyCount = 2,
  layout = {},
}
