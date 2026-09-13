-- g9-Battle-Scene -- fork of g2-Battle-Scene, tightly coupled to
-- g9-battle-engine instead of standing alone as a library.
-- g2-Battle-Scene itself is untouched (a finished product for other
-- modders); this mod exists because "gen 9 battle engine and battle
-- scene must be connected" and "combat logic lives in g9-battle-engine
-- only" -- so unlike g2-Battle-Scene, this mod owns NO combat rules
-- of its own. Turn resolution calls
-- g9dex.exports.resolveTurnActions(battle, actingBattlers) -- the
-- multi-battler seam combat/MULTI_BATTLE_HOOKS.md speced and
-- combat/turn_order.lua now implements -- so STAB/Tera/Protect/damage/
-- accuracy/sub-effects all come from g9-battle-engine's own real
-- pipeline, not a second copy of the math. EXP and catch call the real
-- native Gen 2 primitives directly (Battle:awardExperience,
-- src/battle/gen2/Catching.lua) rather than a hand-ported formula --
-- catch.lua/experience.lua are gone from this fork entirely, not kept
-- dormant.
--
-- Everything else is unchanged from g2-Battle-Scene: still owns the
-- named battle-layout index (layouts.lua's layouts/<name>.lua presets)
-- and the rendering that makes a named layout an actual playable scene,
-- still not responsible for WHEN a battle starts or WHAT'S in it (the
-- calling mod's own job), still no encounter-trigger logic of its own.
--
-- Layout is NOT baked in: layouts.lua reads named layouts/<name>.lua
-- preset files from this mod's own folder at runtime (see its own header
-- for the exact workflow and file shape). The calling mod picks a preset
-- by name via mod.exports.pushLayoutBattle (e.g. "bossFight", "horde",
-- "singles") and supplies the actual battler roster;
-- battle_screen.lua reads that preset's GUI/sprite positions.
local function loadSibling(mod, filename)
  local body, readErr = mod:read(filename)
  assert(body, readErr)
  local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. filename)
  assert(chunk, err)
  return chunk()
end

return function(mod)
  -- Generation backend FIRST: battle_screen.lua asserts it, and it is what
  -- makes one scene source serve both Gold/Silver and Red/Blue/Yellow.
  -- See native.lua's own header for the split.
  loadSibling(mod, "native.lua")(mod)
  loadSibling(mod, "layouts.lua")(mod)
  loadSibling(mod, "combat.lua")(mod)
  loadSibling(mod, "battle_screen.lua")(mod)
  mod.log:info("g9_Battle_Scene: loaded")
end
