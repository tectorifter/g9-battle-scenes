-- Singles preset: one Pokemon per side -- the classic one-on-one wild
-- encounter field.
--
-- This is the preset a caller picks for an ordinary wild encounter, and
-- the one Sample-Battle-Scene's wild-encounter hook routes to by name.
--
-- Every preset carries the SAME standardized 16:9 field geometry -- it
-- lives in battle_screen.lua's own geometry header, and a preset's `layout`
-- table is EMPTY unless it wants to nudge one specific HUD/F box. Sprites
-- are placed by the shared 8-column grid: the ally fills rightward from a1
-- and the enemy leftward from e6, each leaving its OUTER columns empty when
-- it is under strength, so a lone ally stands at a1 and a lone enemy at e6.
-- The two teams use disjoint vertical
-- bands (enemy upper, ally lower), so they can never collide. See
-- battle_screen.lua's Screen:pos for how a HUD override still works.
return {
  allyCount = 1,
  enemyCount = 1,
  layout = {},
}
