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
--
-- One thing here is NOT scene machinery: player_guard.lua is a crash fix for
-- the BASE engine's player (a target-less walk-in-place beat assigns
-- cellX = nil and the next line dies -- see that file's own header).  It is
-- installed first because it must be in place before any frame can run, and
-- because this mod is the one every routed battle leaves through -- so the
-- hazard that plays over the hero around a fight is covered here once for
-- every caller rather than in each of them.
--
-- background.lua adds the one purely cosmetic extra: a near-top-down GROUND
-- PLANE behind the sprites, chosen from the encounter out of the player's own
-- assets/backgrounds/ folder (the BACKGROUND option, default auto -- OFF
-- restores the old white field).  No art ships; see that file's header for
-- the tag scheme and why a missing PNG can never break a battle.
local function loadSibling(mod, filename)
  local body, readErr = mod:read(filename)
  assert(body, readErr)
  local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. filename)
  assert(chunk, err)
  return chunk()
end

-- A sibling that is plain data (returns a table), not a `return function(mod)`
-- module -- options.lua, this mod's options schema.
local function loadDataSibling(mod, filename)
  local body, readErr = mod:read(filename)
  assert(body, readErr)
  local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. filename)
  assert(chunk, err)
  return chunk()
end

return function(mod)
  -- Base-engine crash fix FIRST, before anything else this mod does: the
  -- player step guard must be in place before any frame can run.  See
  -- player_guard.lua's own header for the crash and why it lives here.
  loadSibling(mod, "player_guard.lua")(mod)
  -- Generation backend next: battle_screen.lua asserts it, and it is what
  -- makes one scene source serve both Gold/Silver and Red/Blue/Yellow.
  -- See native.lua's own header for the split.
  loadSibling(mod, "native.lua")(mod)
  -- Player-facing options (the manager renders these rows; the CATCH FORMULA
  -- choice is what native.lua's CATCH RATE block reads per throw).  The same
  -- table is the manifest's options_schema, so the manager can render it even
  -- while this mod is disabled; define() here is what gives mod.options:get
  -- its defaults at runtime.
  if mod.options and type(mod.options.define) == "function" then
    local ok, rows = pcall(loadDataSibling, mod, "options.lua")
    if ok and type(rows) == "table" then mod.options:define(rows) end
  end
  -- Optional ground art (the BACKGROUND option).  Loaded after the options
  -- schema is defined -- it reads that row lazily -- and before
  -- battle_screen.lua, which calls the seam it exposes from drawContent.
  -- See background.lua for the terrain detection, the shipped set and the
  -- degrade-to-white contract.
  loadSibling(mod, "background.lua")(mod)
  loadSibling(mod, "layouts.lua")(mod)
  loadSibling(mod, "combat.lua")(mod)
  -- The FANTASY COMBAT modernized GUI (the FANTASY COMBAT option).  Loaded
  -- after the options schema (F.enabled reads the fantasy_combat row the
  -- define() above created) and before battle_screen.lua, which captures
  -- mod.exports.fantasyCombat at its own load time and draws through it
  -- from drawContent.  See fantasy_combat.lua's own header.
  loadSibling(mod, "fantasy_combat.lua")(mod)
  -- The EXP SHARE distribution rules (the EXP SHARE option).  Loaded after
  -- the options schema -- it reads that row lazily, per award -- and before
  -- battle_screen.lua so the screen's own Gen 1 model can raise the same
  -- battle.exp_award seam this module wraps.  See exp_share.lua's own
  -- header for the per-generation split and the active-set contract.
  loadSibling(mod, "exp_share.lua")(mod)
  -- The MEGA EVOLUTION animation (the transformation sequence).  Loaded after
  -- the options schema and before battle_screen.lua, which captures its export
  -- at load time and stages the sequence from its own resolve pass.  See
  -- evolution_anim.lua's header and battle_screen.lua's MEGA EVOLUTION block.
  loadSibling(mod, "evolution_anim.lua")(mod)
  loadSibling(mod, "battle_screen.lua")(mod)
  -- Wild-boss options LAST, so battle_screen.lua's own install has already
  -- run when this registers its battle.damage 1-HP wrap and its exports.
  -- The screen reads mod.exports.specialBoss lazily at battle time, so the
  -- order only matters for the wrap's position in the shared chain -- and
  -- the wrap asks for the highest priority there is anyway (see its own
  -- header).  See special_boss.lua for BOSS CATCH / SPECIAL BOSSES /
  -- SHINY BOSS and why they are scoped to a WILD boss fight only.
  loadSibling(mod, "special_boss.lua")(mod)
  mod.log:info("g9_Battle_Scene: loaded")
end
