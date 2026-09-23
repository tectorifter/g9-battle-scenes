-- Turn resolution -- unlike g2-Battle-Scene's own combat.lua (its own
-- damage/order/AI primitives, deliberately independent), this fork owns
-- NO combat rules at all. Per the standing "combat logic lives in
-- g9-battle-engine only" rule: this file still owns battler
-- bookkeeping (who exists, who's alive, what moves a battler can
-- currently pick, which move/target the enemy AI chooses) -- exactly the
-- "who is acting" half combat/MULTI_BATTLE_HOOKS.md's own contract says a
-- caller keeps -- but the actual RESOLUTION (hit/miss, crit,
-- effectiveness, damage, every sub-effect) is g9-battle-engine's
-- mod.exports.resolveTurnActions(battle, actingBattlers), not a second
-- damage pipeline here.
return function(mod)
  local Combat = {}
  -- The generation backend (native.lua, loaded before this file).  Turn
  -- resolution is the one place the two games genuinely diverge: Gen 2 gives
  -- g9-battle-engine a real model to drive, Gen 1 has no such model, so
  -- the backend owns which authority resolves the turn.  See native.lua.
  local N = assert(mod.exports.native,
    "g9-Battle-Scene: native.lua must load before combat.lua")

  ------------------------------------------------------------------
  -- MOVE VALIDITY (round 100): the engine's own "can this mon pick this move
  -- right now, and if not why not" answer. g9-battle-engine exports
  -- mod.exports.moveUsability(battle, mon, moveId) -> nil | { reason=, flag= },
  -- covering the Choice move-lock, item move-type bans (Assault Vest), Taunt/
  -- Torment, and the Fake Out/First Impression/Last Resort condition gates.
  -- This module owns "what moves a battler can currently pick", so the
  -- annotation lives here. Combat.engine/Combat.battle are pinned by
  -- battle_screen.lua's pushDoubleBattleScreen once the real battle exists;
  -- the lookup falls back to mod:find so the AI/report paths still work if a
  -- caller forgets to pin them.
  ------------------------------------------------------------------
  Combat.engine = nil
  Combat.battle = nil

  local function engineExports()
    if Combat.engine then return Combat.engine end
    local ok, engMod = pcall(function() return mod:find("g9-battle-engine") end)
    if ok and engMod and engMod.exports then
      Combat.engine = engMod.exports
      return engMod.exports
    end
    return nil
  end

  local function engineBlock(battler, moveId)
    local eng = engineExports()
    local battle = Combat.battle
    if not (eng and eng.moveUsability and battle and battler and moveId) then return nil end
    local ok, res = pcall(eng.moveUsability, battle, battler, moveId)
    if ok and type(res) == "table" and res.reason then return res end
    return nil
  end

  -- Stamp every PP-legal entry with the engine's verdict. `usable` stays the
  -- ONE flag the screen reads, so a 0-PP row and an engine-blocked row refuse
  -- through the same branch; invalidReason/invalidFlag carry the WHY and the
  -- player-facing text the screen prints.
  local function annotate(entries, battler)
    for _, entry in ipairs(entries) do
      if entry.usable then
        local blk = engineBlock(battler, entry.slot.id)
        if blk then
          entry.usable = false
          entry.invalidReason = blk.reason
          entry.invalidFlag = blk.flag
        end
      end
    end
    return entries
  end

  -- One battler: the raw mon table plus which side it's on. No `stages`
  -- table here -- g9-battle-engine owns real per-mon stat stages now
  -- (combat/showdown_primitives.lua's mon.volatile.boosts), not a
  -- parallel copy in this mod.
  --
  -- mon.multiSide, explicit user request (2026-08-28): tags the RAW mon
  -- table itself (not just this wrapper) with its real side -- the one
  -- real signal g9-battle-engine's own N-way Battle:sideOf override
  -- (combat/move_targeting.lua) reads to correctly classify a battler
  -- beyond the primary pair, instead of the native hard-binary "not
  -- battle.player therefore enemy" check that used to misclassify one.
  -- Combat-only, not permanent: cleared on battle.ended
  -- (battle_screen.lua's own listener), the same "own it, then clean it
  -- up when combat ends" discipline this whole ability/status system
  -- already uses (g9-battle-engine's own naturalAbility/
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
        -- `usable` starts true (this list is already the PP filter), exactly
        -- like allMoves' own `(slot.pp or 0) > 0` stamp, so `annotate` can
        -- clear it for an engine-forbidden row. Without this field annotate
        -- skipped every entry and the AI could queue a blocked move.
        out[#out + 1] = { index = i, slot = slot, def = data.moves[slot.id], usable = true }
      end
    end
    return annotate(out, battler)
  end

  -- Every move the battler still KNOWS, whether or not it has PP left --
  -- the player's move menu lists all of them (the native games never
  -- drop a 0-PP move off the list: the cursor still travels onto it and
  -- choosing it is simply refused with "No PP left for this move!"),
  -- while the AI's own picker keeps usableMoves' PP filter. Each entry
  -- carries `usable` (real PP left) so the screen can refuse the pick
  -- without re-reading the slot, and the raw `index` so the SELECT-swap
  -- can reorder any slot, PP or not, exactly as the native menu does.
  function Combat.allMoves(battler, data)
    local out = {}
    if not (battler and battler.mon) then return out end
    for i, slot in ipairs(battler.mon.moves or {}) do
      if slot.id and data.moves and data.moves[slot.id] then
        out[#out + 1] = {
          index = i, slot = slot, def = data.moves[slot.id],
          usable = (slot.pp or 0) > 0,
        }
      end
    end
    -- Round 100: a real-PP move the engine's rules currently forbid (Choice
    -- lock / item move-type ban / Taunt-Torment / unmet condition) comes back
    -- usable=false with invalidReason set, so the screen refuses it exactly
    -- like a 0-PP move -- just with the engine's own explanation.
    return annotate(out, battler)
  end

  -- The MAXIMUM PP of a move slot, for the move list's `cur/max` readout.
  -- Gen 2 slots carry a real `maxPp` field (Mon.movesAtLevel / Trainers.party
  -- write it -- Mon.lua's `maxPp = moveDef.pp`), but Gen 1 slots are only
  -- `{id, pp, ppUps}`: the native games compute the maximum on the fly
  -- (BattleState.lua's `def.pp + ppUps * floor(def.pp/5)`), so a Gen 1 slot's
  -- `maxPp` is nil. Reading `slot.maxPp or slot.pp` there made the maximum
  -- appear to fall by one with every use -- PP looked like it was being
  -- drained from the maximum as well as the current value. Derive the real
  -- maximum for both generations from whichever source the slot actually
  -- has, so depletion only ever moves the CURRENT value.
  function Combat.maxPpOf(slot, def)
    if type(slot) ~= "table" then return 0 end
    if slot.maxPp then return slot.maxPp end
    local base = (type(def) == "table" and def.pp) or 0
    if base <= 0 then return slot.pp or 0 end
    return base + (slot.ppUps or 0) * math.floor(base / 5)
  end

  -- The AI's own picker. `usableMoves` now carries the engine's verdict too --
  -- a PP-legal move the RULES currently forbid comes back usable=false with
  -- invalidReason set (see `annotate`) -- so the picker must skip those rows:
  -- otherwise the AI would knowingly queue a move the engine then refuses at
  -- resolution, wasting its whole turn. Picking only from the allowed rows
  -- keeps the AI's choice legal without a second copy of any rule here.
  function Combat.chooseAiAction(battler, targets, data)
    local allowed = {}
    for _, entry in ipairs(Combat.usableMoves(battler, data)) do
      if entry.usable then allowed[#allowed + 1] = entry end
    end
    if #allowed == 0 then return nil end
    local alive = {}
    for _, t in ipairs(targets) do
      if Combat.isAlive(t) then alive[#alive + 1] = t end
    end
    if #alive == 0 then return nil end
    local pick = allowed[love.math.random(1, #allowed)]
    local target = alive[love.math.random(1, #alive)]
    return { actor = battler, index = pick.index, slot = pick.slot, def = pick.def, target = target }
  end

  -- Translates this mod's own queued actions (actor/target battler
  -- wrappers + slot/def) into the flat { mon =, move =, target = } list
  -- g9-battle-engine wants -- real mon tables and a plain move-id string,
  -- not battler wrappers or def tables (battle:useMove(attacker, defender,
  -- moveId) reads attacker/defender directly, confirmed
  -- Battle.lua:1337-1341). Shared by the batch and stepwise resolution
  -- paths below so the two cannot drift.
  local function toActingBattlers(queuedActions)
    local actingBattlers = {}
    for _, action in ipairs(queuedActions) do
      -- `fail` actions carry NO recipient on purpose: the scene's positional
      -- adjacency left every candidate out of reach, so the move is meant to
      -- be used and fail.  They still go to the engine, which announces the
      -- move and prints its own "But it failed!" line (spending the PP);
      -- without this they were dropped here and the slot silently did
      -- nothing at all.
      if Combat.isAlive(action.actor) and (action.target or action.fail) then
        actingBattlers[#actingBattlers + 1] = {
          mon = action.actor.mon,
          move = action.slot.id,
          target = action.target and action.target.mon or nil,
          fail = action.fail or nil,
        }
      end
    end
    return actingBattlers
  end

  -- Resolves a WHOLE turn's worth of queued actions in one call --
  -- resolveTurnActions' own real contract ("hand me everyone acting this
  -- turn"), not one action at a time the way g2-Battle-Scene's own
  -- resolveAction did.
  --
  -- Returns the events g9-battle-engine's own battle:useMove calls
  -- emitted (battle:takeEvents(), drained here so nothing is lost between
  -- this call and the next) -- {kind=, text=, ...} tables, native's own
  -- shape, not reshaped into this mod's old plain-string convention here;
  -- battle_screen.lua extracts .text per event itself.
  function Combat.resolveTurn(g9dex, battle, queuedActions)
    return N.resolveTurn(g9dex, battle, toActingBattlers(queuedActions))
  end

  -- Resume a turn a pivot self-switch paused (g9-battle-engine's
  -- combat/turn_order.lua PIVOT PAUSE).  `incoming` is the mon the scene sent
  -- in; the engine finishes the round -- repointing every not-yet-acted actor
  -- that had been aimed at the mon that left -- and its events are drained
  -- here exactly like the batch turn's.  Returns an empty list on a backend
  -- with no resume arm (Gen 1, whose pivots are inert by design).
  function Combat.resumeAfterPivot(g9dex, battle, incoming, outgoing)
    if type(N.resumeAfterPivot) ~= "function" then return {} end
    return N.resumeAfterPivot(g9dex, battle, incoming, outgoing)
  end

  -- Stepwise resolution (see N.beginTurn's own note): begin this turn's REAL
  -- order, then ask for one action at a time -- which lets the scene display
  -- each action's own events (and the sprite/stat changes that go with them)
  -- before the next action resolves. Returns false when the backend has no
  -- stepwise arm (Gen 2, or an older g9-battle-engine), and the scene then
  -- falls back to the whole-turn Combat.resolveTurn above -- so those paths
  -- are byte-for-byte unchanged.
  function Combat.beginTurn(g9dex, battle, queuedActions)
    if type(N.beginTurn) ~= "function" then return false end
    return N.beginTurn(g9dex, battle, toActingBattlers(queuedActions))
      and true or false
  end

  -- One actor's worth of the turn begun above: (events, done).
  function Combat.resolveNextAction(g9dex, battle)
    if type(N.resolveNextAction) ~= "function" then return nil, true end
    return N.resolveNextAction(g9dex, battle)
  end

  -- The mons in this turn's own real ACTION ORDER, for the battle screen's
  -- gimmick sequence: when both sides transform on the same turn, the
  -- animation that belongs to whichever Pokemon acts FIRST plays first (see
  -- battle_screen's GIMMICK SEQUENCE block).  Prefers an engine export when the
  -- engine grows one; otherwise reads the order the engine's own
  -- beginTurnActionsForGen1 parked on the battle -- `__g9Gen1Order`, the exact
  -- field resolveNextActionForGen1 walks -- so no engine change is needed for
  -- the read.  Returns an empty list when neither is available (a batch-only
  -- engine, i.e. Gen 2), and the screen then falls back to its own stable
  -- order rather than guessing.
  function Combat.orderedActorMons(battle)
    local eng = engineExports()
    if eng and type(eng.orderedActionMonsForGen1) == "function" then
      local ok, list = pcall(eng.orderedActionMonsForGen1, battle)
      if ok and type(list) == "table" then return list end
    end
    local out = {}
    local ordered = battle and battle.__g9Gen1Order
    if type(ordered) == "table" then
      for _, actor in ipairs(ordered) do
        local mon = actor and actor.id and actor.id.mon
        if mon then out[#out + 1] = mon end
      end
    end
    return out
  end

  function Combat.sideDefeated(battlers)
    for _, b in ipairs(battlers) do
      if Combat.isAlive(b) then return false end
    end
    return true
  end

  mod.exports.combat = Combat
  mod.log:info("g9_Battle_Scene: combat installed (delegates resolution to g9-battle-engine)")
end
