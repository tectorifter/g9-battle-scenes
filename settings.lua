-- g9-Battle-Scene settings -- plain data, edit directly, no
-- code changes needed. Read fresh once per battle (battle_screen.lua's
-- Screen.new), so a change here takes effect on the very next battle.
return {
  -- "list": original vertical FIGHT/BAG/PKMN/RUN, up/down only.
  -- "grid": 3x2 (3 rows, 2 columns) with free four-direction movement.
  --   Singles/Horde/Boss (no SWITCH):
  --     FIGHT | PKMN        FIGHT | PKMN
  --     FORMS | BAG    or   BAG   | RUN   (if customButtonLabel is empty)
  --           | RUN
  --   Doubles/Triples (SWITCH available):
  --     FIGHT  | PKMN       FIGHT  | PKMN
  --     SWITCH | BAG   or   SWITCH | BAG   (if customButtonLabel is empty)
  --     FORMS  | RUN        RUN    |
  menuLayout = "grid",

  -- "FORMS" -- real, permanent label, not a demo value. Explicit user
  -- decision: battle_forms owns this button (Screen:chooseMenuItem's own
  -- "CUSTOM" branch calls straight into battle_forms's exposed
  -- mod.exports.transforms registry -- Mega Evolution, Dynamax, whatever
  -- else that mod registers). Unlike g2-Battle-Scene (a standalone
  -- library this same button was left off in, since no specific mod was
  -- meant to own it there), g9-Battle-Scene is tightly coupled to
  -- specific combat mods by design -- see this mod's own manifest.json.
  customButtonLabel = "FORMS",

  -- Move animations toggle. When false (default), move animations are
  -- skipped -- the battle plays faster with no visual effect per move.
  -- The pokeball throw at the START of battle and during a CATCH attempt
  -- are always shown regardless of this setting (they are battle-flow
  -- events, not optional move VFX). Set to true to re-enable full
  -- animated move effects.
  moveAnimations = false,
}
