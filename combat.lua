-- Turn resolution -- unlike g2-Battle-Scene's own combat.lua (its own
-- damage/order/AI primitives, deliberately independent), this fork owns
-- NO combat rules at all. Per the standing "combat logic lives in
-- g9-battle-engine-beta only" rule: this file still owns battler
-- bookkeeping (who exists, who's alive, what moves a battler can
-- currently pick, which move/target the enemy AI chooses) -- exactly the
-- "who is acting" half combat/MULTI_BATTLE_HOOKS.md's own contract says a
-- caller keeps -- but the actual RESOLUTION (hit/miss, crit,
-- effectiveness, damage, every sub-effect) is g9-battle-engine-beta's
-- mod.exports.resolveTurnActions(battle, actingBattlers), not a second
-- damage pipeline here.
return function(mod)
  local Combat = {}

  -- One battler: the raw mon table plus which side it's on. No `stages`
  -- table here -- g9-battle-engine-beta owns real per-mon stat stages now
  -- (combat/showdown_primitives.lua's mon.volatile.boosts), not a
  -- parallel copy in this mod.
  --
  -- mon.multiSide, explicit user request (2026-08-28): tags the RAW mon
  -- table itself (not just this wrapper) with its real side -- the one
  -- real signal g9-battle-engine-beta's own N-way Battle:sideOf override
  -- (combat/move_targeting.lua) reads to correctly classify a battler
  -- beyond the primary pair, instead of the native hard-binary "not
  -- battle.player therefore enemy" check that used to misclassify one.
  -- Combat-only, not permanent: cleared on battle.ended
  -- (battle_screen.lua's own listener), the same "own it, then clean it
  -- up when combat ends" discipline this whole ability/status system
  -- already uses (g9-battle-engine-beta's own naturalAbility/
  -- stockpileLayers fields).
  function Combat.newBattler(mon, side)
    if mon then mon.multiSide = side end
    return {
      mon = mon,
      side = side, -- "player" or "enemy"
      fainted = (mon == nil) or ((mon.hp or 0) <= 0),
    }
  end

  function Combat.isAlive(battler)
    return battler ~= nil and battler.mon ~= nil and not battler.fainted
      and (battler.mon.hp or 0) > 0
  end

  function Combat.usableMoves(battler, data)
    local out = {}
    if not (battler and battler.mon) then return out end
    for i, slot in ipairs(battler.mon.moves or {}) do
      if (slot.pp or 0) > 0 and data.moves and data.moves[slot.id] then
        out[#out + 1] = { index = i, slot = slot, def = data.moves[slot.id] }
      end
    end
    return out
  end

  function Combat.chooseAiAction(battler, targets, data)
    local usable = Combat.usableMoves(battler, data)
    if #usable == 0 then return nil end
    local alive = {}
    for _, t in ipairs(targets) do
      if Combat.isAlive(t) then alive[#alive + 1] = t end
    end
    if #alive == 0 then return nil end
    local pick = usable[love.math.random(1, #usable)]
    local target = alive[love.math.random(1, #alive)]
    return { actor = battler, index = pick.index, slot = pick.slot, def = pick.def, target = target }
  end

  -- Resolves a WHOLE turn's worth of queued actions in one call --
  -- resolveTurnActions' own real contract ("hand me everyone acting this
  -- turn"), not one action at a time the way g2-Battle-Scene's own
  -- resolveAction did. `queuedActions` is this mod's own array (actor/
  -- target battler wrappers + slot/def), translated here into the flat
  -- { mon =, move =, target = } list g9-battle-engine-beta actually
  -- wants -- real mon tables and a plain move-id string, not battler
  -- wrappers or def tables (battle:useMove(attacker, defender, moveId)
  -- reads attacker/defender directly, confirmed Battle.lua:1337-1341).
  --
  -- Returns the events g9-battle-engine-beta's own battle:useMove calls
  -- emitted (battle:takeEvents(), drained here so nothing is lost between
  -- this call and the next) -- {kind=, text=, ...} tables, native's own
  -- shape, not reshaped into this mod's old plain-string convention here;
  -- battle_screen.lua extracts .text per event itself.
  function Combat.resolveTurn(g9dex, battle, queuedActions)
    local actingBattlers = {}
    for _, action in ipairs(queuedActions) do
      if Combat.isAlive(action.actor) and action.target then
        actingBattlers[#actingBattlers + 1] = {
          mon = action.actor.mon,
          move = action.slot.id,
          target = action.target.mon,
        }
      end
    end
    g9dex.exports.resolveTurnActions(battle, actingBattlers)
    return battle:takeEvents()
  end

  function Combat.sideDefeated(battlers)
    for _, b in ipairs(battlers) do
      if Combat.isAlive(b) then return false end
    end
    return true
  end

  mod.exports.combat = Combat
  mod.log:info("g9_Battle_Scene: combat installed (delegates resolution to g9-battle-engine-beta)")
end
