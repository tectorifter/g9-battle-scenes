-- Triples preset: three Pokemon per side.
--
-- Standardized 16:9 field geometry -- see battle_screen.lua's geometry
-- header and layouts/singles.lua's own note. `layout` is empty on purpose:
-- the three allies take a1..a3 and the three enemies e4..e6, all at the
-- shared natural sprite scale. At 1:1 a wide species may reach past its own
-- column, which is the whole point of drawing each sprite at its own size.
return {
  allyCount = 3,
  enemyCount = 3,
  layout = {},
}
