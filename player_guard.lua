-- player_guard.lua -- a base-engine crash fix, installed by main.lua at boot
-- before any other sibling.
--
-- WHAT IT FIXES.  Player:update's step-completion branch runs
--   self.cellX, self.cellY = self.targetX, self.targetY
--   self.px, self.py = self.cellX * 16, self.cellY * 16
-- (src/world/Player.lua:237-240; src/world/gen2/Player.lua carries the same
-- branch at its own completion line).  A real step always has a target, so
-- that is fine.  But the engine can also move an entity with NO target at
-- all: OverworldState:marchInPlace pushes a scriptMove with inPlace = true
-- (src/world/OverworldController.lua:5448-5452) and updateScriptMoves then
-- arms `moving = true, marching = true` and no targetX/targetY (:5476-5480);
-- Commands.march_in_place's ambient `marchers` loop re-arms exactly that
-- state every frame (:5498-5506); WorldAPI's `handle:marchInPlace()` reaches
-- both (src/world/WorldAPI.lua:493).  NPC:update HAS an arm for that state
-- (src/world/NPC.lua:99-106, and src/world/gen2/Npc.lua:584-590) --
-- Player:update has none, so the very next frame assigns cellX = nil and the
-- frame after that dies on
--   src/world/Player.lua:239: attempt to perform arithmetic on a nil value
--     (field 'cellX')
-- with the whole overworld down (a save-anywhere build then fails to save,
-- because the update never returns).
--
-- WHY IT LIVES HERE, AND NOT IN A CALLER.  This is a guard against the BASE
-- engine's hole, not a feature of any one mod.  Nothing in vanilla ever
-- marches the PLAYER (npcByIndex resolves only self.npcs and the player is
-- not in that table), so the state is only ever reached by a mod that holds a
-- WorldAPI handle onto the player -- e.g. the game/engine-controlled movement
-- a script plays over the hero around a fight, once the parked world script
-- is resumed at battle exit.  g9-Battle-Scene is the one mod every encounter
-- in this workspace is routed through, and it is a hard dependency of the
-- sample that used to carry this guard, so installing it at THIS mod's boot
-- puts the wrap in place before any frame of any routed battle (or the
-- post-battle script that follows it) can run, and every caller -- the battle
-- sample, g9-trainer-sample, wild_forms's boss scenes -- inherits it for free
-- instead of each shipping its own copy.
--
-- WHAT IT DOES.  For the marching case it mirrors NPC:update's in-place beat
-- (one walk cycle, no translation) so the queued scriptMove can retire and
-- updateScriptMoves still fires its onDone; for a target-less non-march it
-- simply puts the entity back on its own cell.  Every healthy call -- a step
-- with a target, or no movement at all -- is handed straight to the engine's
-- own update, so normal play is untouched.  Idempotent (a second install is a
-- no-op, so a caller that also guards cannot double-wrap) and a no-op on a
-- build whose player module cannot be resolved, so it can never be the reason
-- a boot fails.
return function(mod)
  local function tryRequire(name)
    local ok, value = pcall(require, name)
    if ok then return value end
    return nil
  end

  -- GameVersion is the engine's own answer, and the same one native.lua reads
  -- (loaded after this file); a boot that cannot answer it -- a trimmed build
  -- under test -- is treated as Gen 1, the engine's own default.  Gold, Silver
  -- and Crystal are all generation 2 in this engine (src/core/Game2.lua loads
  -- src.world.gen2.World for every one of them), so "gen2" means all three.
  local gen = 1
  local GameVersion = tryRequire("src.core.GameVersion")
  if GameVersion and GameVersion.generation then
    local ok, value = pcall(GameVersion.generation)
    if ok and (value == 1 or value == 2) then gen = value end
  end

  local name = gen == 2 and "src.world.gen2.Player" or "src.world.Player"
  local Player = tryRequire(name)
  if type(Player) ~= "table" then return false end
  if type(Player.update) ~= "function" or Player.g9StepGuard then return false end

  local nativeUpdate = Player.update
  Player.g9StepGuard = true
  Player.update = function(self, ...)
    if self.moving and self.targetX == nil then
      if self.marching then
        local stepLen = self.stepFramesCur or self.stepFrames or 16
        self.progress = (self.progress or 0) + 1
        self.animClock = (self.animClock or 0) + 1
        if self.progress >= stepLen then
          self.progress = 0
          self.moving = false
          self.marching = false
          self.stepFlip = not self.stepFlip
        end
        return false
      end
      self.moving = false
      self.marching = false
      self.progress = 0
      if self.cellX then
        self.px, self.py = self.cellX * 16, (self.cellY or 0) * 16
      end
      return false
    end
    return nativeUpdate(self, ...)
  end

  if mod and mod.log then
    mod.log:info("g9_Battle_Scene: player step guard installed on %s", name)
  end
  return true
end
