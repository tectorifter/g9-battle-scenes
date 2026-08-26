-- g9-Battle-Scene settings -- plain data, edit directly, no
-- code changes needed. Read fresh once per battle (battle_screen.lua's
-- Screen.new), so a change here takes effect on the very next battle.
return {
  -- "list": original vertical FIGHT/BAG/PKMN/RUN, up/down only.
  -- "grid": 2x2 (FIGHT/PKMN top row, BAG/RUN bottom row), free movement
  --   on all four directions -- becomes a 5-cell cross (FIGHT/PKMN top,
  --   BAG/RUN bottom, custom button dead center) when customButtonLabel
  --   below is set.
  menuLayout = "grid",

  -- "Gimmicks" -- real, permanent label, not a demo value. Explicit user
  -- decision: battle_forms owns this button (Screen:chooseMenuItem's own
  -- "CUSTOM" branch calls straight into battle_forms's exposed
  -- mod.exports.transforms registry -- Mega Evolution, Dynamax, whatever
  -- else that mod registers). Unlike g2-Battle-Scene (a standalone
  -- library this same button was left off in, since no specific mod was
  -- meant to own it there), g9-Battle-Scene is tightly coupled to
  -- specific combat mods by design -- see this mod's own manifest.json.
  customButtonLabel = "Gimmicks",
}
