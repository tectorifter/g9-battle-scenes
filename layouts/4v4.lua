-- 4v4 preset: four Pokemon per side, with its own exclusive adjacency
-- ruleset (see battle_screen.lua's g9.request_adjacency wrap).
--
-- Standardized 16:9 field geometry -- see battle_screen.lua's geometry
-- header and layouts/singles.lua's own note. `layout` is empty on purpose:
-- the four allies fill rightward from a1 (cols 1..4) and the four enemies
-- fill leftward from e6 (cols 3..6), all at the shared natural sprite
-- scale, exactly as the grid places every other preset. The two sides
-- stand on disjoint vertical bands (enemy upper, ally lower), so the
-- column overlap in the middle is purely a positional naming fact and no
-- two sprites ever share a ground line.
--
-- The `fourVFour` flag is the whole point of this preset: it is the ONLY
-- thing that turns on the 4v4 adjacency ruleset, and it is read by
-- battle_screen.lua alone:
--   * every ally counts as adjacent to every other ally, BOTH teams (the
--     same "adjacent allies = all allies" a boss fight reports, extended
--     to the enemy side), so an ally-scope move like Life Dew reaches the
--     whole team and a foes-scope switch-in ability (Intimidate) reaches
--     every foe;
--   * an OFFENSIVE SPREAD move (all-opponents / all-other-pokemon --
--     Rock Slide, Muddy Water, Earthquake, Surf, ...) is the ONE
--     exception: on the ENEMY side it keeps NORMAL positional adjacency,
--     so it reaches at most three of the four enemies and never all four;
--   * an all-other-pokemon move (Earthquake) still reaches the WHOLE ally
--     side -- it damages allies as the real move does -- while keeping
--     that same three-enemy cap.
-- Nothing here is keyed on the enemy COUNT (a trainer simply cannot field
-- more than `enemyCount` at once; anything past four is benched as usual),
-- so no other preset can be reached by this ruleset.
return {
  allyCount = 4,
  enemyCount = 4,
  fourVFour = true,
  layout = {},
}
