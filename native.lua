-- native.lua -- the generation backend for g9-Battle-Scene.
--
-- "Preserve gold/silver compatibility, but make sure g9-battle-scene works
-- in gen 1."  Gold/Silver (generation 2) is this mod's original home and stays
-- byte-for-byte behaviourally identical: every symbol below maps 1:1 onto the
-- exact gen2 module or `data.gen2*` field the scene required before, so the
-- Gen 2 path is unchanged by construction.  Red/Blue/Yellow (generation 1) is
-- the new arm.
--
-- WHY A BACKEND FILE AT ALL.  The scene was written against the Gen 2 engine,
-- which is model/view separated (`src.battle.gen2.Battle` is a pure model,
-- `src.ui.gen2.BattleState` is the screen).  Gen 1 is NOT: `src.battle.
-- BattleState` is one screen class that owns the model AND the presentation.
-- The scene therefore needs a thin, per-generation shim for the handful of
-- engine surfaces it touches, rather than a `if gen == 2` scattered through
-- 5,200 lines.  This file is that shim; battle_screen.lua talks only to it.
--
-- WHAT IS GEN-SPECIFIC, and why:
--   * Battle model      -- gen2 `Battle.new` (a real model) vs gen1 a
--                          `BattleState` instance used purely as a model
--                          (its move executor is the game's own).
--   * Catching          -- one switchable rate for both arms, chosen by the
--                          CATCH FORMULA mod option (options.lua): Gen IX
--                          (Scarlet/Violet, the default), Gen II or Gen I --
--                          see the CATCH RATE block below.  The native
--                          `Catching.attempt` is no longer on the catch path.
--   * EXP               -- gen2 `Battle:awardExperience` (screen-free model
--                          method) vs gen1 `Experience.apply` (the pure module
--                          `BattleState:awardExp` is built on; the method
--                          itself is queue-coupled to the native screen).
--   * HUD tiles         -- gen2 `src.ui.gen2.BattleHud` (VRAM $60-$78 tiles)
--                          vs gen1 `src.render.HudTiles` ($62-$7F overlay).
--                          The real Gen 2 HUD is used on Gen 1 too whenever
--                          the Gen 2 menu graphics are present (see below).
--   * menus             -- gen2 Gen2PartyMenu/Gen2PackMenu vs gen1
--                          PartyMenu + a ball-only ListMenu.
--   * move animations   -- TWO native engines, picked by the same
--                          asset rule as everything else.  With the Gen 2
--                          battle-anim tables present, gen2 AnimRunner/
--                          BattleAnimView play (the Gen 2 arm's own engine,
--                          wired into a Gen 1 boot too).  Without them -- a
--                          stock Red/Blue/Yellow boot -- Gen 1's OWN
--                          `src.battle.AnimPlayer` plays instead: a different
--                          contract (compiled per-frame OAM steps over
--                          data.battle_anims.moveAnims, not a running
--                          script), so it gets its own arm rather than a
--                          translation.  Both are the game's own data; there
--                          is no "no animation" Gen 1 case any more.
--   * trainer colours   -- gen2 TrainerPalettes via src.world.gen2.Palettes,
--                          used whenever the Gen 2 palette table is present;
--                          otherwise Gen 1 draws its trainer art raw (its SGB
--                          colouring is a native-screen pipeline this scene
--                          does not reproduce).
--   * status labels     -- gen2 `data.gen2Statuses` when that table is
--                          present, else gen1 `src.battle.Status.hudLabelFor`.
--
-- CALLING THE GEN 2 ASSETS INTO GEN 1.  A stock Red/Blue/Yellow boot carries
-- no `data.gen2*` tables at all (src/core/Game2.lua loads them only for a
-- Gold/Silver boot), so the Gen 1 arm treats them as an optional asset pack:
-- when the live game data is found to carry any Gen 2 asset table -- an engine
-- that bundles Gold's data, or a content mod that merges a `data.gen2*`
-- registry -- the Gen 1 arm answers every asset question with the SAME table
-- the Gen 2 arm reads (palette/menu-gfx/status/trainer/constants/anim data),
-- builds the real Gen 2 battle HUD (so Gen 1 gets the cart's $60-$78 tiles and
-- a real exp bar back), loads the Gen 2 move-animation engine, and colours
-- trainer art through the Gen 2 palette rows.  With no Gen 2 assets present
-- every path keeps its Gen 1 behaviour exactly, and none of the Gen 2 anim/HUD
-- modules are even loaded.  The generation switch (`N.isGen2`) is NOT what
-- selects this: the presence of the assets is.
--
-- COMBAT AUTHORITY.  The standing rule is "combat logic lives in
-- g9-battle-engine only".  On Gen 2 that is exactly what happens:
-- `resolveTurnActions(battle, acting)` drives the engine's whole pipeline and
-- this mod owns none of it.  On Gen 1 the engine mod is a Gen 2 engine and
-- cannot drive a Gen 1 `BattleState`, so the combat authority is the GAME'S
-- OWN Gen 1 battle engine -- `BattleState:performMove` (accuracy, damage,
-- effects, status, PP: the real thing, not a reimplementation) sequenced by
-- the real `src.battle.TurnOrder`.  That is the same "call the native
-- primitives" discipline the mod already applies to catch and EXP on Gen 2;
-- no formula is duplicated.  A future gen-1-capable engine mod can take over
-- by exporting `resolveTurnActionsForGen1(battle, acting)` -- checked first
-- below -- with no change to this file's callers.
--
-- Loaded FIRST by main.lua, before battle_screen.lua.
return function(mod)
  local function tryRequire(name)
    local ok, value = pcall(require, name)
    if ok then return value end
    return nil
  end

  -- A sibling file of this mod, returning whatever it returns (no mod arg --
  -- this is for a plain data module, not a `return function(mod)` sibling).
  local function loadSiblingFile(filename)
    local body, readErr = mod:read(filename)
    assert(body, readErr)
    local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. filename)
    assert(chunk, err)
    return chunk()
  end

  local GameVersion = tryRequire("src.core.GameVersion")
  local gen = 1
  if GameVersion and GameVersion.generation then
    local ok, value = pcall(GameVersion.generation)
    if ok and value then gen = value end
  end

  local N = { gen = gen, isGen2 = (gen == 2) }

  ------------------------------------------------------------------
  -- THE THROWN BALL -- the game's own colour, animation params and catch
  -- loop, shared by both arms because they are static cart data/behaviour
  -- rather than a module one generation owns.  Gen 2's own screen reads
  -- exactly these (src/ui/gen2/BattleState.lua:3218-3322); the scene hands
  -- them to the native ANIM_THROW_POKE_BALL script through AnimRunner.
  ------------------------------------------------------------------

  -- data/battle_anims/ball_colors.asm BallColors, in its own order.  Anything
  -- not listed falls to the terminator row's PAL_BATTLE_OB_GRAY.  This is the
  -- "native colour" the ball is drawn in: the animation's own object function
  -- (BATTLE_ANIM_FUNC_POKEBALL/ballPal) stamps env.ballPalette onto the ball.
  local BALL_COLORS = {
    MASTER_BALL = "PAL_BATTLE_OB_GREEN",
    ULTRA_BALL = "PAL_BATTLE_OB_YELLOW",
    GREAT_BALL = "PAL_BATTLE_OB_BLUE",
    POKE_BALL = "PAL_BATTLE_OB_RED",
    HEAVY_BALL = "PAL_BATTLE_OB_GRAY",
    LEVEL_BALL = "PAL_BATTLE_OB_BROWN",
    LURE_BALL = "PAL_BATTLE_OB_BLUE",
    FAST_BALL = "PAL_BATTLE_OB_BLUE",
    FRIEND_BALL = "PAL_BATTLE_OB_YELLOW",
    MOON_BALL = "PAL_BATTLE_OB_GRAY",
    LOVE_BALL = "PAL_BATTLE_OB_RED",
  }
  local BALL_COLOR_DEFAULT = "PAL_BATTLE_OB_GRAY"

  -- POKE_BALL's own item id (constants/item_constants.asm:13), for a cache
  -- whose items table has no index on the row.
  local POKE_BALL_ID = 5

  -- The wobble hook used to be GetPokeBallWobble
  -- (engine/battle_anims/pokeball_wobble.asm) itself: the cart re-rolled
  -- WobbleProbabilities (data/battle/wobble_probabilities.asm) once per wobble
  -- against the final catch rate, so the number of shakes was a property of
  -- the animation loop rather than of how the throw resolved.  The catch is
  -- formula-driven now (see the CATCH RATE block), so the wobble count comes
  -- out of whichever formula the CATCH FORMULA option selected -- SV's four
  -- shake checks, Gen II's three, or Gen I's shake tiers -- and is simply
  -- replayed as the 0/1/2 answer the ball's script branches on
  -- (N.ballWobbleFromChecks).  The native table is gone with it: keeping both
  -- would leave two live sources of truth for the same shake.

  -- GetBallAnimPal (engine/battle_anims/functions.asm:292): the PAL_BATTLE_OB_*
  -- name the thrown ball wears, resolved for the item being thrown.
  N.ballPalette = function(ballId)
    return BALL_COLORS[ballId] or BALL_COLOR_DEFAULT
  end

  -- wBattleAnimParam for the throw: the item's own id, except that everything
  -- past POKE_BALL (the Kurt balls) is thrown with POKE_BALL's -- `cp POKE_BALL
  -- + 1 / jr c, .not_kurt_ball / ld a, POKE_BALL` (item_effects.asm:396).  It
  -- is what BattleAnim_ThrowPokeBall's anim_if_param_equal rows branch on
  -- (data/moves/animations.asm:305-308).
  N.ballAnimParam = function(data, ballId)
    local items = (data and data.items) or {}
    local pokeBall = (items.POKE_BALL and items.POKE_BALL.index) or POKE_BALL_ID
    local entry = items[ballId]
    local id = entry and (entry.index or entry.id)
    if type(id) ~= "number" then id = pokeBall end
    if id > pokeBall then return pokeBall end
    return id
  end

  -- PlayStereoSFX (audio/engine.asm:2571), the ONE sfx path with no CheckSFX
  -- gating -- the throw's own SFX_THROW_BALL then SFX_BALL_POOF would otherwise
  -- be dropped as outranked by its first (see BattleState:startAnim's own sound
  -- hook).  Guarded through pcall so a trimmed engine or a headless harness
  -- simply plays nothing rather than aborting the throw.
  N.playAnimSfx = function(data, name)
    if not name then return end
    local ok, Sound = pcall(require, "src.core.Sound")
    if not ok or type(Sound) ~= "table" then return end
    local fn = Sound.playStereo or Sound.play
    if type(fn) ~= "function" then return end
    pcall(fn, data, name)
  end

  ------------------------------------------------------------------
  -- CATCH RATE -- one switchable formula per throw.
  --
  -- The CATCH FORMULA mod option (options.lua, default "gen9") chooses which
  -- generation's capture maths a thrown ball uses.  All three arms return the
  -- same four values -- caught, shakes (0-3 shown), a, chance -- so the ball's
  -- animation, the failure line and the catch.rate seam never learn which one
  -- ran (N.catchAttemptForMode is the single dispatcher; N.catchFormula reads
  -- the option afresh each throw, so a change lands on the very next ball):
  --
  --   gen9  Scarlet/Violet  -- N.modernCatchAttempt (the default).
  --   gen2  Gold/Silver     -- N.gen2CatchAttempt.
  --   gen1  Red/Blue/Yellow -- N.gen1CatchAttempt.
  --
  -- The scene used to throw balls through the native per-generation rate
  -- maths (Gen 2 PokeBallEffect's 0..255 roll, Gen 1 ItemUseBall's two-roll
  -- with a per-ball randMax).  Those numbers are the games' own, and the
  -- gen1/gen2 arms below are exactly them -- transcribed from the engine's
  -- own src/battle/Catching.lua and src/battle/gen2/Catching.lua -- while the
  -- default arm is the modern formula:
  --
  --   a = floor( (3*maxHp - 2*hp) / (3*maxHp) * 4096 * darkGrass
  --              * rate_modified * bonus_ball * badgePenalty )
  --       * bonus_level * bonus_status * bonus_misc
  --
  -- clamped to [1, 1044480] (255 * 4096).  a == 1044480 is certain -- a
  -- Master Ball, or a rate that saturates.  The wobble count is the
  -- generation-VI+ four-check model the modern games use:
  --
  --   b = floor( 65536 * (a / 1044480) ^ (3/16) )
  --   four rolls in 0..65535; a check passes when roll < b; the mon is caught
  --   when all four pass.  The wobbles SHOWN are the checks that passed before
  --   the first failure, capped at three, so a catch wobbles three times and
  --   clicks and a failure wobbles 0-3 times and breaks free -- the exact beat
  --   the cart plays, and the same 0/1/2 answer the ball's animation script
  --   already branches on.  The Gen I and Gen II arms feed the same shake
  --   contract: Gen II from its three b(a) shake checks, Gen I from its
  --   Z = X*Y/255 shake tiers.
  --
  -- Three terms of the SV formula have no Gen 1/Gen 2 counterpart and stay 1:
  -- badgePenalty (SV obedience), darkGrass (Gen V dark grass) and bonus_misc
  -- (Capture Power / back strike).  They are still read from `opts` so a
  -- caller that knows them can pass them.
  ------------------------------------------------------------------

  local CATCH_SCALE = 4096 * 255          -- 1044480: a's ceiling
  local CATCH_ROLLS = 4                   -- Gen VI+ shake checks
  local CATCH_SHAKE_EXP = 3 / 16          -- 0.1875

  local function floorNumber(value, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    return math.floor(n)
  end

  -- A uniform integer in 0..maxExclusive-1.  The battle's own random arrives
  -- in one of TWO shapes built into the engine, and they are NOT
  -- interchangeable -- the generation picks the shape:
  --
  --   Gen 1  battle.rng(a, b)  -> a..b, inclusive.  This is the scene's own
  --                               buildBattle `state.random`, literally
  --                               love.math.random(a, b).
  --   Gen 2  battle.random(n)  -> 0..n-1.  gen2/Battle.lua:276
  --                               `self.random = opts.random or function(n)
  --                               return rand(nil, n) end`, whose default
  --                               rand(nil, n) is love.math.random(n) - 1.
  --
  -- Probing the arity CANNOT tell these apart, and guessing wrong is
  -- catastrophic: LOVE's RandomGenerator:random(l, u) computes
  -- floor(r * l) + 1 when u is nil (love wrap_RandomGenerator.lua), so
  -- calling a ONE-argument roll as rng(0, n) is not an error -- it returns 1
  -- every single time.  Every check then passes and every thrown ball becomes
  -- a guaranteed catch, which is exactly the reported "catch formula seems to
  -- be 100%".  The generation decides instead, mirroring the engine's own
  -- modules (g9-battle-engine's percentRoll/rangeRoll in main.lua).  The value
  -- is clamped into the requested range so an off-contract roll from a
  -- trimmed build can never escape 0..maxExclusive-1.
  local function modernRoll(random, maxExclusive)
    if type(random) == "function" then
      local ok, value
      if N.isGen2 then
        ok, value = pcall(random, maxExclusive)
      else
        ok, value = pcall(random, 0, maxExclusive - 1)
      end
      if ok and type(value) == "number" then
        value = math.floor(value)
        if value < 0 then return 0 end
        if value > maxExclusive - 1 then return maxExclusive - 1 end
        return value
      end
    end
    local rng = (love and love.math and love.math.random) or math.random
    return math.floor(rng(maxExclusive)) - 1
  end

  -- bonus_level: SV's curve.  The max() makes the below-level-13 cut-off
  -- implicit -- at 13 the term reaches 1 and never falls short of it.
  N.levelBonus = function(level)
    local lv = floorNumber(level, 0)
    if lv <= 0 then return 1 end
    return math.max((36 - 2 * lv) / 10, 1)
  end

  -- bonus_status, Gen VIII+ numbers: sleep and freeze 2.5, the rest 1.5.  The
  -- ids are the engine's own (Gen 1 Status.lua and Gen 2 Battle.STATUSES
  -- agree): SLP, FRZ, PSN, BRN, PAR (TOX if a mod adds it).  Lower-case and
  -- long names are accepted so a caller's own vocabulary still lands.
  local STATUS_BONUS_MODERN = {
    SLP = 2.5, FRZ = 2.5, sleep = 2.5, freeze = 2.5, asleep = 2.5,
    PSN = 1.5, BRN = 1.5, PAR = 1.5, TOX = 1.5,
    poison = 1.5, burn = 1.5, paralyze = 1.5, paralysed = 1.5, toxic = 1.5,
  }
  N.statusBonus = function(status)
    if status == nil or status == false or status == "" then return 1 end
    return STATUS_BONUS_MODERN[status] or 1
  end

  -- Gen VIII/IX flat ball multipliers.  MASTER/PARK are certainties rather
  -- than multipliers, so they are handled before the table is consulted.
  local BALL_MULTIPLIER_MODERN = {
    POKE_BALL = 1, GREAT_BALL = 1.5, ULTRA_BALL = 2,
    SAFARI_BALL = 1.5, SPORT_BALL = 1.5,
    PREMIER_BALL = 1, LUXURY_BALL = 1, HEAL_BALL = 1,
    FRIEND_BALL = 1, CHERISH_BALL = 1,
  }
  local BALL_CERTAIN = { MASTER_BALL = true, PARK_BALL = true }

  local function typesOf(opts)
    local def = opts.def
    local list = opts.types or (def and (def.types or def.type))
    if type(list) ~= "table" then list = { list } end
    return list
  end

  local function hasType(opts, upper, mixed)
    for _, t in ipairs(typesOf(opts)) do
      if t == upper or t == mixed then return true end
    end
    return false
  end

  local function firstNumber(...)
    for i = 1, select("#", ...) do
      local n = tonumber((select(i, ...)))
      if n then return n end
    end
    return nil
  end

  -- The Moon Ball's modern target list (the Moon Stone evolutionary families;
  -- the item itself is the Gen 1/2 path, checked alongside).
  local MOON_STONE_LINE = {
    NIDORAN_F = true, NIDORINA = true, NIDOQUEEN = true,
    NIDORAN_M = true, NIDORINO = true, NIDOKING = true,
    CLEFAIRY = true, CLEFABLE = true,
    JIGGLYPUFF = true, WIGGLYTUFF = true,
    SKITTY = true, DELCATTY = true, MUNNA = true, MUSHARNA = true,
  }

  -- Heavy Ball's weight adjustment (Gen IV onward): additive to the species
  -- rate, not a multiplier.  Bands in kilograms.
  local function heavyBallAdjust(kg)
    if not kg then return 0 end
    if kg < 100 then return -20 end
    if kg < 200 then return 0 end
    if kg < 300 then return 20 end
    if kg < 400 then return 30 end
    return 40
  end

  -- One arm per conditional ball, fn(opts) -> bonus[, rateAdjust].
  local BALL_ARM_MODERN = {
    DREAM_BALL = function(opts)
      local s = opts.status
      return (s == "SLP" or s == "sleep" or s == "asleep") and 4 or 1
    end,
    DIVE_BALL = function(opts) return opts.fishing and 3.5 or 1 end,
    DUSK_BALL = function(opts) return (opts.night or opts.cave) and 3 or 1 end,
    NET_BALL = function(opts)
      if hasType(opts, "WATER", "Water") or hasType(opts, "BUG", "Bug") then
        return 3.5
      end
      return 1
    end,
    REPEAT_BALL = function(opts) return opts.registered and 3.5 or 1 end,
    TIMER_BALL = function(opts)
      local turns = tonumber(opts.turns) or 0
      return math.min(1 + 0.3 * turns, 4)
    end,
    QUICK_BALL = function(opts)
      return (tonumber(opts.turn) or 1) <= 1 and 5 or 1
    end,
    NEST_BALL = function(opts)
      local level = tonumber(opts.level) or 100
      return math.max(1, math.min(4, (41 - level) / 10))
    end,
    BEAST_BALL = function(opts) return opts.ultraBeast and 5 or 0.1 end,
    LEVEL_BALL = function(opts)
      local level, player = tonumber(opts.level), tonumber(opts.playerLevel)
      if not (level and player) or level > player then return 1 end
      if level <= math.floor(player / 4) then return 8 end
      if level <= math.floor(player / 2) then return 4 end
      return 2
    end,
    LURE_BALL = function(opts) return opts.fishing and 3 or 1 end,
    FAST_BALL = function(opts)
      local speed = firstNumber(opts.speed,
        opts.mon and opts.mon.stats and opts.mon.stats.speed,
        opts.def and opts.def.speed,
        opts.def and opts.def.baseStats and opts.def.baseStats.speed)
      return (speed and speed >= 100) and 4 or 1
    end,
    MOON_BALL = function(opts)
      local species = opts.species or (opts.mon and opts.mon.species)
      if species and MOON_STONE_LINE[species] then return 3 end
      local def = opts.def
      if def and def.evolveItem == "MOON_STONE" then return 3 end
      return 1
    end,
    LOVE_BALL = function(opts)
      local wild, player = opts.gender, opts.playerGender
      if not wild or not player or wild == "unknown" or player == "unknown" then
        return 1
      end
      if opts.species ~= opts.playerSpecies then return 1 end
      return wild ~= player and 8 or 1
    end,
    HEAVY_BALL = function(opts) return 1, heavyBallAdjust(opts.weightKg) end,
  }

  -- The merged `balls` record for a ball id, or nil.  Gen 2 fills
  -- data.gen2Balls from its loader; a Gen 1 boot may carry one too.
  N.registeredBall = function(ball, opts)
    local data = opts.data or (opts.battle and opts.battle.data)
      or (opts.game and opts.game.data)
    local balls = opts.balls or (data and (data.gen2Balls or data.balls))
    return balls and balls[ball] or nil
  end

  -- bonus_ball (and, for the Heavy Ball, the additive rate_modified tweak).
  -- Returns bonus, certain, rateAdjust.
  N.ballBonus = function(ballId, opts)
    opts = opts or {}
    local ball = ballId or "POKE_BALL"
    -- The merged ball registry (data.balls, which the game fills from its own
    -- src/battle/Catching.lua) is the authoritative source for a ball's catch
    -- factor, exactly as the Gen I and Gen II arms read it.  When it carries a
    -- record for this ball, honour that record's autoCatch / multiplier before
    -- the flat SV table below; a Gen I/II record carries neither (its effect is
    -- randMax/hpFactor/wobbleFactor) so it falls straight through to the SV
    -- numbers.  This is what makes a mod-added ball's own multiplier land.
    local record = N.registeredBall(ball, opts)
    if record then
      if record.autoCatch or record.multiplier == math.huge then
        return 255, true, 0
      end
      if type(record.multiplier) == "number" then
        return record.multiplier, false, 0
      end
    end
    if BALL_CERTAIN[ball] then return 255, true, 0 end
    local flat = BALL_MULTIPLIER_MODERN[ball]
    if flat then return flat, false, 0 end
    local arm = BALL_ARM_MODERN[ball]
    if arm then
      local bonus, adjust = arm(opts)
      return bonus or 1, false, adjust or 0
    end
    return 1, false, 0
  end

  -- The modern formula.  Returns caught, shakes (0-3 shown), a, chance.
  N.modernCatchAttempt = function(opts)
    opts = opts or {}
    local ball = opts.ball or "POKE_BALL"
    local maxHp = math.max(1, floorNumber(opts.maxHp, 1))
    local hp = math.max(0, math.min(floorNumber(opts.hp, maxHp), maxHp))
    local speciesRate = tonumber(opts.catchRate) or tonumber(opts.rate) or 45

    local bonus, certain, rateAdjust = N.ballBonus(ball, opts)
    if certain then return true, 3, CATCH_SCALE, 1 end

    local rateModified = math.max(1, math.min(255,
      math.floor(speciesRate + (rateAdjust or 0))))

    local hpFactor = (3 * maxHp - 2 * hp) / (3 * maxHp)
    local a = math.floor(hpFactor * 4096 * (opts.darkGrass or 1)
      * rateModified * bonus * (opts.badgePenalty or 1))
    a = math.floor(a * N.levelBonus(opts.level)
      * N.statusBonus(opts.status) * (opts.misc or 1))
    if a >= CATCH_SCALE then return true, 3, CATCH_SCALE, 1 end
    if a < 1 then a = 1 end

    local b = math.floor(65536 * (a / CATCH_SCALE) ^ CATCH_SHAKE_EXP)
    if b > 65535 then b = 65535 end

    local passed = 0
    for _ = 1, CATCH_ROLLS do
      if modernRoll(opts.random, 65536) < b then
        passed = passed + 1
      else
        break
      end
    end
    local caught = passed >= CATCH_ROLLS
    local chance = (b / 65536) ^ CATCH_ROLLS
    return caught, math.min(passed, 3), a, chance
  end

  -- -- status, shared by the Gen I and Gen II arms -------------------
  -- Both generations keep the cart's three-letter id ("SLP", "FRZ", "PSN",
  -- "BRN", "PAR"); a table-shaped status is accepted too so a mod's record
  -- still lands.
  local function statusKey(opts)
    local status = opts.status
    if type(status) == "table" then
      status = status.id or status.name or status.key
    end
    return status
  end

  local SLEEP_FREEZE = {
    SLP = true, FRZ = true, slp = true, frz = true,
    sleep = true, asleep = true, freeze = true, frozen = true,
  }
  local OTHER_STATUS = {
    PSN = true, BRN = true, PAR = true, TOX = true,
    psn = true, brn = true, par = true, tox = true,
    poison = true, burn = true, paralyze = true, paralysed = true,
    paralysis = true, toxic = true,
  }
  local function isSleepFreeze(status) return SLEEP_FREEZE[status] == true end
  local function isOtherStatus(status) return OTHER_STATUS[status] == true end

  -- -- Generation I ---------------------------------------------------
  -- ItemUseBall (engine/items/item_effects.asm), the numbers the engine's own
  -- src/battle/Catching.lua carries: each ball has its own catch-roll ceiling
  -- (randMax), HP factor and wobble divisor (wobbleFactor).  An unknown ball
  -- falls back to POKE_BALL's roll and the 150 wobble divisor, exactly as that
  -- module's DEFAULT_BALL does.
  local GEN1_BALLS = {
    POKE_BALL   = { randMax = 255, hpFactor = 12, wobbleFactor = 255 },
    GREAT_BALL  = { randMax = 200, hpFactor = 8,  wobbleFactor = 200 },
    ULTRA_BALL  = { randMax = 150, hpFactor = 12, wobbleFactor = 150 },
    SAFARI_BALL = { randMax = 150, hpFactor = 12, wobbleFactor = 150 },
  }
  local GEN1_BALL_DEFAULT = { randMax = 255, hpFactor = 12, wobbleFactor = 150 }

  -- Status.recordFor's catchBonus / shakeBonus (src/battle/Status.lua): sleep
  -- and freeze are worth 25 on the first roll and 10 on the wobble tier,
  -- poison/burn/paralysis 12 and 5.
  local function gen1CatchBonus(status)
    if isSleepFreeze(status) then return 25 end
    if isOtherStatus(status) then return 12 end
    return 0
  end
  local function gen1ShakeBonus(status)
    if isSleepFreeze(status) then return 10 end
    if isOtherStatus(status) then return 5 end
    return 0
  end

  -- The HP factor f = floor(floor(maxHp*255/factor) / max(1, floor(hp/4))),
  -- capped at 255 (the cart shifts HP right twice, so its own /4 is integer).
  local function gen1HpFactor(maxHp, hp, factor)
    local f = math.floor(math.floor(maxHp * 255 / factor)
      / math.max(1, math.floor(hp / 4)))
    if f < 1 then f = 1 end
    if f > 255 then f = 255 end
    return f
  end

  -- The wobble tiers: Y = rate*100/wobbleFactor, Z = f*Y/255 (+ the status
  -- shake bonus), Z<10 -> 0 shakes, <30 -> 1, <70 -> 2, else 3.
  local function gen1Shakes(rate, f, wobbleFactor, status)
    local y = math.floor(rate * 100 / wobbleFactor)
    local z
    if y > 255 then z = 255 else z = math.floor(f * y / 255) end
    z = z + gen1ShakeBonus(status)
    if z < 10 then return 0 end
    if z < 30 then return 1 end
    if z < 70 then return 2 end
    return 3
  end

  -- Gen I's two-roll catch.  `a` is reported as f (the 1..255 HP factor),
  -- Gen I's own final catch value.
  N.gen1CatchAttempt = function(opts)
    opts = opts or {}
    local ball = opts.ball or "POKE_BALL"
    if ball == "MASTER_BALL" then return true, 3, 255, 1 end
    -- The ball's own catch data comes from the MERGED registry the game loads
    -- (data.balls, filled by src/battle/Catching.lua's registerInto) when it
    -- carries it, exactly as the game's own Catching.attempt reads `opts.ballDef
    -- or BALLS[ball] or DEFAULT_BALL`.  A ball record's autoCatch is the cart's
    -- "never rolls" (the Master Ball); its randMax/hpFactor/wobbleFactor are
    -- ItemUseBall's own per-ball numbers.  Our table is only the fallback for a
    -- boot with no loader (a harness) or an id the game does not know.
    local record = N.registeredBall(ball, opts)
    if record and (record.autoCatch or record.multiplier == math.huge) then
      return true, 3, 255, 1
    end
    local def
    if record and type(record.randMax) == "number" then
      def = {
        randMax = record.randMax,
        hpFactor = record.hpFactor or GEN1_BALL_DEFAULT.hpFactor,
        wobbleFactor = record.wobbleFactor or GEN1_BALL_DEFAULT.wobbleFactor,
      }
    else
      def = GEN1_BALLS[ball] or GEN1_BALL_DEFAULT
    end
    local maxHp = math.max(1, floorNumber(opts.maxHp, 1))
    local hp = math.max(1, math.min(floorNumber(opts.hp, maxHp), maxHp))
    local rate = tonumber(opts.catchRate) or tonumber(opts.rate) or 45
    local status = statusKey(opts)
    local catchBonus = gen1CatchBonus(status)
    local f = gen1HpFactor(maxHp, hp, def.hpFactor)
    local outcomes = def.randMax + 1
    local automatic = math.min(outcomes, catchBonus)
    local passed = math.min(outcomes, math.max(0, rate + catchBonus + 1))
    local chance = (automatic + (passed - automatic) * (f + 1) / 256) / outcomes
    if chance < 0 then chance = 0 elseif chance > 1 then chance = 1 end
    -- First roll: randMax-wide, less the status bonus.  r < 0 catches on the
    -- status alone; r above the species rate breaks free before the HP roll.
    local r = modernRoll(opts.random, outcomes) - catchBonus
    if r < 0 then return true, 3, f, chance end
    if r > rate then
      return false, gen1Shakes(rate, f, def.wobbleFactor, status), f, chance
    end
    if modernRoll(opts.random, 256) <= f then return true, 3, f, chance end
    return false, gen1Shakes(rate, f, def.wobbleFactor, status), f, chance
  end

  -- -- Generation II --------------------------------------------------
  -- PokeBallEffect (engine/items/item_effects.asm), the numbers the engine's
  -- own src/battle/gen2/Catching.lua carries.  `multiplier` is the flat factor
  -- applied to the species rate; the balls whose factor depends on the battle
  -- live in GEN2_SPECIALTY below.  MASTER_BALL is handled before this table.
  local GEN2_MULTIPLIER = {
    ULTRA_BALL = 2, GREAT_BALL = 1.5,
    POKE_BALL = 1, SAFARI_BALL = 1.5, PARK_BALL = 1.5, FRIEND_BALL = 1,
  }
  -- FastBallMultiplier's cart bug: the loop only ever reaches the first three
  -- SometimesFleeMons rows, so only these species get the x4.
  local GEN2_FAST_BALL_SPECIES = {
    MAGNEMITE = true, GRIMER = true, TANGELA = true,
  }

  -- HeavyBallMultiplier's weight conversion: the dex weight (tenths of a
  -- pound) becomes tenths of a kilogram via w/2 - w/32 - w/64, and only its
  -- HIGH byte is compared.  Additive to the species rate, not a multiplier.
  local function gen2HeavyBallBoost(weight)
    local half = math.floor((weight or 0) / 2)
    local sub1 = math.floor(half / 16)
    local sub2 = math.floor(sub1 / 2)
    local high = math.floor((half - sub1 - sub2) / 256)
    if high < 4 then return -20 end   -- under 102.4 kg
    if high < 8 then return 0 end     -- under 204.8 kg
    if high < 12 then return 20 end   -- under 307.2 kg
    if high < 16 then return 30 end   -- under 409.6 kg
    return 40
  end

  -- The first EVOLVE_ITEM a species has, the way the engine's Gen 2 catch site
  -- derives evolveItem for the Moon Ball.
  local function evolveItemOf(opts)
    local evolutions = opts.def and opts.def.evolutions
    if type(evolutions) ~= "table" then return nil end
    for _, entry in ipairs(evolutions) do
      if entry.method == "EVOLVE_ITEM" then return entry.item end
    end
    return nil
  end

  -- BallMultiplierFunctionTable's conditional arms.  Three cart bugs are kept
  -- deliberately (the engine's module documents them): Fast Ball only knows
  -- three species, Love Ball boosts SAME-sex pairs, and Moon Ball compares
  -- against BURN_HEAL (nothing evolves by it) so it never boosts.  Each caps
  -- at 255 the way every `sla b / jr c` does.
  local GEN2_SPECIALTY = {
    HEAVY_BALL = function(rate, opts)
      if not opts.weight then return rate end
      return math.max(1, rate + gen2HeavyBallBoost(opts.weight))
    end,
    LEVEL_BALL = function(rate, opts)
      local player, enemy = tonumber(opts.playerLevel), tonumber(opts.level)
      if not (player and enemy) or enemy >= player then return rate end
      rate = rate * 2
      if enemy < math.floor(player / 2) then rate = rate * 2 end
      if enemy < math.floor(player / 4) then rate = rate * 2 end
      return math.min(255, rate)
    end,
    LURE_BALL = function(rate, opts)
      if not opts.fishing then return rate end
      return math.min(255, rate * 3)
    end,
    FAST_BALL = function(rate, opts)
      if not GEN2_FAST_BALL_SPECIES[opts.species] then return rate end
      return math.min(255, rate * 4)
    end,
    MOON_BALL = function(rate, opts)
      if evolveItemOf(opts) ~= "BURN_HEAL" then return rate end
      return math.min(255, rate * 4)
    end,
    LOVE_BALL = function(rate, opts)
      if not opts.species or opts.species ~= opts.playerSpecies then
        return rate
      end
      local wild, player = opts.gender, opts.playerGender
      if not wild or not player or wild == "unknown"
          or player == "unknown" then
        return rate
      end
      if wild ~= player then return rate end -- the cart's same-sex boost
      return math.min(255, rate * 8)
    end,
  }

  -- rate_modified: the species rate through the flat multiplier or the
  -- conditional arm, clamped to [1, 255].  Returns rate, certain.
  local function gen2BallRate(catchRate, ball, opts)
    -- The game's own src/battle/gen2/Catching.lua resolves the ball through the
    -- MERGED registry record FIRST (Catching.recordFor -> data.gen2Balls), and
    -- only then applies a flat multiplier or a specialty arm -- an unregistered
    -- id leaves the species rate alone.  Mirror that exact order so the ball's
    -- real BallMultiplierFunctionTable factor is the one used; our own tables
    -- are only the fallback for a loader-free boot (a harness) or an id the game
    -- does not know.
    local record = N.registeredBall(ball, opts)
    if record then
      if record.autoCatch or record.multiplier == math.huge then
        return catchRate, true
      end
      if type(record.multiplier) == "number" then
        return math.floor(catchRate * record.multiplier), false
      end
      if type(record.specialty) == "function" then
        return record.specialty(catchRate, opts), false
      end
    end
    local multiplier = GEN2_MULTIPLIER[ball]
    if multiplier then return math.floor(catchRate * multiplier), false end
    local arm = GEN2_SPECIALTY[ball]
    if arm then return arm(catchRate, opts), false end
    return catchRate, false
  end

  -- The shake-probability b(a), the cart's WobbleProbabilities table
  -- (data/battle/wobble_probabilities.asm; Bulbapedia's "Capture method
  -- (Generation II)" a-ranges give the same numbers).  Each row is
  -- { aCeiling, b }: the FIRST row whose aCeiling is at least a supplies the
  -- chance out of 255 that a shake check passes.  This is the exact scan the
  -- engine's Gen 2 screen performs (src/ui/gen2/BattleState.lua:pokeballWobble,
  -- `if row[1] >= rate`), transcribed verbatim so the two can be diffed.
  local GEN2_SHAKE_B = {
    { 1, 63 }, { 2, 75 }, { 3, 84 }, { 4, 90 }, { 5, 95 }, { 7, 103 },
    { 10, 113 }, { 15, 126 }, { 20, 134 }, { 30, 149 }, { 40, 160 },
    { 50, 169 }, { 60, 177 }, { 80, 191 }, { 100, 201 }, { 120, 211 },
    { 140, 220 }, { 160, 227 }, { 180, 234 }, { 200, 240 }, { 220, 246 },
    { 240, 251 }, { 254, 253 }, { 255, 255 },
  }
  local function gen2ShakeB(a)
    for _, row in ipairs(GEN2_SHAKE_B) do
      if row[1] >= a then return row[2] end
    end
    return GEN2_SHAKE_B[#GEN2_SHAKE_B][2]
  end

  -- bonus_status: 10 for sleep or freeze, 0 otherwise.  The cart MEANT 5 for
  -- burn/poison/paralysis but its `and` test falls through, so those give no
  -- bonus (the engine's own Gen 2 module reproduces the same bug).
  local function gen2StatusBonus(status)
    if isSleepFreeze(status) then return 10 end
    return 0
  end

  -- The Gen II catch: modify the species rate by the ball, build `a` from the
  -- HP term plus the status bonus (with the cart's 8-bit truncation), roll
  -- `a` for the catch, and only on a failure roll the three shake checks
  -- against b(a).  A catch is always three wobbles and a click.
  N.gen2CatchAttempt = function(opts)
    opts = opts or {}
    local ball = opts.ball or "POKE_BALL"
    if ball == "MASTER_BALL" then return true, 3, 255, 1 end
    local maxHp = math.max(1, floorNumber(opts.maxHp, 1))
    local hp = math.max(0, math.min(floorNumber(opts.hp, maxHp), maxHp))
    local speciesRate = tonumber(opts.catchRate) or tonumber(opts.rate) or 45

    local rate, certain = gen2BallRate(speciesRate, ball, opts)
    if certain then return true, 3, 255, 1 end
    rate = math.max(1, math.min(255, math.floor(rate)))

    -- The cart shifts both HP terms right twice once 3*maxHp fills a byte, and
    -- then compares only the low byte of the shifted max; the shifted HP term
    -- floors at 1.  Kept, because it is what Gold/Silver really does.
    local tripleMax = maxHp * 3
    local doubleHp = hp * 2
    if tripleMax >= 256 then
      tripleMax = math.floor(tripleMax / 4) % 256
      doubleHp = math.max(1, math.floor(doubleHp / 4))
    end
    tripleMax = math.max(1, tripleMax)

    local a = math.floor((tripleMax - doubleHp) * rate / tripleMax)
    a = math.max(1, a) + gen2StatusBonus(statusKey(opts))
    if a > 255 then a = 255 end

    if a >= 255 then return true, 3, a, 1 end
    -- The cart's own single-byte roll: a value under the final rate catches,
    -- so the odds are exactly a/256 (PokeBallEffect's `cp b / jr nc`).
    local chance = a / 256
    if modernRoll(opts.random, 256) < a then return true, 3, a, chance end
    local b = gen2ShakeB(a)
    local passed = 0
    for _ = 1, 3 do
      if modernRoll(opts.random, 256) < b then
        passed = passed + 1
      else
        break
      end
    end
    return false, passed, a, chance
  end

  -- The selected formula, read from the CATCH FORMULA option at throw time (so
  -- a change lands on the very next ball, no reload).
  --
  -- AUTO (the default) follows the RUNNING GAME: a Red/Blue/Yellow boot throws
  -- with Gen I's ItemUseBall maths and a Gold/Silver/Crystal boot with Gen II's
  -- PokeBallEffect maths.  That is the "proper path" -- each generation's own
  -- ball data (Gen I's per-ball randMax/hpFactor/wobbleFactor, Gen II's
  -- BallMultiplierFunctionTable factor) is what the cart actually applies, and
  -- it is what the game's own src/battle/Catching.lua and
  -- src/battle/gen2/Catching.lua implement.  The scene used to default to
  -- GEN IX on every boot, so a Gen I game ran Scarlet/Violet's maths: SV's
  -- bonus_level (`max((36-2*level)/10,1)` below level 13) inflates the rate
  -- for the low-level wild Pokemon both Gen I and Gen II field, and for the
  -- many species whose catch rate is already 255 it reaches a = 1044480 --
  -- the certainty ceiling -- so a thrown Poke Ball was a guaranteed catch.
  -- That is exactly the reported "catch is 100%".  GEN 1 / GEN 2 / GEN 9 stay
  -- available as explicit overrides (a Gen I game can still be asked for SV
  -- maths), and an unknown or absent option resolves through AUTO.
  local CATCH_FORMULA_DEFAULT = "auto"
  local CATCH_FORMULA_KEYS = {
    auto = true, gen1 = true, gen2 = true, gen9 = true,
  }
  N.catchFormula = function()
    local value
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, got = pcall(function() return options:get("catch_formula") end)
      if ok then value = got end
    end
    if value == nil or value == "" or not CATCH_FORMULA_KEYS[value]
        or value == "auto" then
      return N.isGen2 and "gen2" or "gen1"
    end
    return value
  end

  -- One dispatcher for all three arms, so the throw, the mod seam and the
  -- failure line follow the option without knowing which formula it names.
  N.catchAttemptForMode = function(mode, opts)
    if mode == "gen1" then return N.gen1CatchAttempt(opts) end
    if mode == "gen2" then return N.gen2CatchAttempt(opts) end
    return N.modernCatchAttempt(opts)
  end

  -- The wobble count when only the outcome and the rate are known -- a mod
  -- that replaced the catch.rate result instead of the formula.  Same
  -- four-check model; a catch is always shown as three wobbles and a click.
  N.shakesFor = function(caught, a, random)
    if caught then return 3 end
    local rate = tonumber(a) or 0
    if rate >= CATCH_SCALE then return 3 end
    if rate < 1 then rate = 1 end
    local b = math.floor(65536 * (rate / CATCH_SCALE) ^ CATCH_SHAKE_EXP)
    if b > 65535 then b = 65535 end
    local passed = 0
    for _ = 1, CATCH_ROLLS do
      if modernRoll(random, 65536) < b then passed = passed + 1 else break end
    end
    if passed >= CATCH_ROLLS then return 3 end
    return math.min(passed, 3)
  end

  -- GetPokeBallWobble's answer, but driven by the modern check count: the
  -- ball wobbles `shakes` times and the NEXT call is the verdict (1 click,
  -- 2 break free).  Same 0/1/2 contract as N.ballWobble, so the native
  -- ANIM_THROW_POKE_BALL script branches on it identically.
  N.ballWobbleFromChecks = function(caught, shakes)
    local shown = math.max(0, math.min(3, floorNumber(shakes, 0)))
    local wobble = 0
    return function()
      wobble = wobble + 1
      if wobble > shown then return caught and 1 or 2 end
      return 0
    end
  end

  -- UseDisposableItem (Gen 2) / Bag.remove (Gen 1): one copy of the thrown
  -- ball leaves the bag on every valid throw, miss or catch, exactly as the
  -- cart spends it.  Returns true when a copy was actually removed.
  N.consumeItem = function(save, ballId)
    if not (save and ballId) then return false end
    local inventory = save.inventory
    if type(inventory) ~= "table" or inventory[ballId] == nil then
      return false
    end
    if not N.isGen2 then
      local Bag = tryRequire("src.inventory.Bag")
      if Bag and type(Bag.remove) == "function" then
        Bag.remove(save, ballId, 1)
        return true
      end
    end
    inventory[ballId] = math.max(0, (tonumber(inventory[ballId]) or 1) - 1)
    if inventory[ballId] == 0 then inventory[ballId] = nil end
    return true
  end

  -- The four failure lines, indexed by the number of wobbles shown.  Gen IX
  -- and Gen II share the Crystal/common_3.asm set (data/text/common_3.asm:239-
  -- 258); Gen I rolls its own (ItemUseBallText01..04, text_6.asm:29-35), where
  -- a 0-shake result really is "the Ball missed" and every tier reads
  -- differently.  The line follows whichever formula the CATCH FORMULA option
  -- selected, so a Gen I throw fails in Gen I's voice.
  local BALL_FAILURE_TEXT = {
    "Oh no! The POKéMON broke free!",
    "Aww! It appeared to be caught!",
    "Aargh! Almost had it!",
    "Shoot! It was so close too!",
  }
  local BALL_FAILURE_TEXT_GEN1 = {
    "You missed the POKéMON!",
    "Darn! The POKéMON broke free!",
    "Aww! It appeared to be caught!",
    "Shoot! It was so close too!",
  }
  N.ballMissMessage = function(shakes)
    local count = math.max(0, math.min(3, floorNumber(shakes, 0)))
    if N.catchFormula() == "gen1" then
      return BALL_FAILURE_TEXT_GEN1[count + 1]
    end
    return BALL_FAILURE_TEXT[count + 1]
  end

  -- The caught line, likewise per generation: Gen I announces a catch with
  -- "All right! %s was caught!" (data/text/text_6.asm:29, ItemUseBallText05)
  -- while Gen II onwards use "Gotcha! %s was caught!" (data/text/common_3.asm
  -- :265, Text_BallCaught).  The caught tail is identical either way, so only
  -- the wording follows the CATCH FORMULA option.
  N.caughtMessage = function(name)
    if N.catchFormula() == "gen1" then
      return "All right! " .. name .. " was caught!"
    end
    return "Gotcha! " .. name .. " was caught!"
  end

  -- The POKéDEX "SEEN" stamp, which has the same owner problem as the caught
  -- tail below: native writes it while LOADING an enemy mon
  -- (`LoadEnemyMon`'s "Saw this mon", gen1 BattleState.lua:781/912 and gen2
  -- `BattleState:markSeen`), and this scene replaces that screen.  `seen` is
  -- spelled the same on both generations, so this needs no split.
  N.markSeen = function(game, mon)
    local save = game and game.save
    if not (save and mon and mon.species) then return end
    save.pokedex = save.pokedex or { seen = {} }
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.seen[mon.species] = true
  end

  -- THE CAUGHT MON'S DEX REGISTRATION, which this scene owns because it
  -- replaces the native screen that used to do it.
  --
  -- Native marks the POKéDEX inside the very method that files the catch:
  -- Gen 1's `BattleState:storeCaughtMon` calls `markOwned(game, species)`
  -- (which sets `pokedex.owned[species]` and `seen`), then `stampOT`; Gen 2's
  -- `BattleState:pushCaught` runs `SetSeenAndCaughtMon` / `CheckCaughtMon`
  -- (`pokedex.caught[species]` + `seen`), `Mon.stampOT`, `stampCaughtData`
  -- (met place/time/level) and `Unown.registerCatch`.  A scene catch added the
  -- mon to the party but ran NONE of that, so `save.pokedex` was never touched
  -- and the caught count never moved -- the reported "catch is not registering
  -- caught to pokedex completeness".
  --
  -- Returns (isNew, species): `isNew` is whether the row was NOT already
  -- owned/caught, the flag the native screens read to decide whether to show
  -- the "new POKéDEX data" beat.
  N.registerCatch = function(game, mon, opts)
    opts = opts or {}
    local save = game and game.save
    if not (save and mon) then return false, mon and mon.species end
    local species = mon.species
    if N.isGen2 then
      -- OT first, exactly as PokeBallEffect's TryAddMonToParty /
      -- SendMonIntoBox arm writes wPlayerName/wPlayerID before the mon is
      -- filed (item_effects.asm:548-556).
      local Mon = tryRequire("src.battle.gen2.Mon")
      if Mon and type(Mon.stampOT) == "function" then
        pcall(Mon.stampOT, save, mon)
      end
      save.pokedex = save.pokedex or { seen = {}, caught = {} }
      local dex = save.pokedex
      dex.seen = dex.seen or {}
      dex.caught = dex.caught or {}
      -- CheckCaughtMon answers BEFORE SetSeenAndCaughtMon stamps (:519-527).
      local knew = dex.caught[species] and true or false
      dex.caught[species] = true
      dex.seen[species] = true
      -- caught_data.asm:163-199 (Crystal only; a no-op elsewhere).  The opts
      -- are the same set native's `BattleState:stampCaughtData` builds.
      local Catching2 = tryRequire("src.battle.gen2.Catching")
      if Catching2 and type(Catching2.stampCaughtData) == "function" then
        local world = game.world
        local battle = opts.battle
        local map = world and world.map
        pcall(Catching2.stampCaughtData, mon, {
          version = save.version,
          save = save,
          data = game.data,
          bugContest = opts.bugContest,
          timeOfDay = (battle and battle.timeOfDay)
            or (world and world.timeOfDayId and world:timeOfDayId()),
          map = map and map.def,
          backupMap = world and world.backupMapId and world.maps
            and world.maps[world.backupMapId],
          playerGender = save.player and save.player.gender,
        })
      end
      -- AddPartyMon's `.registerunowndex` / SendMonIntoBox's `.not_unown`.
      local Unown = tryRequire("src.core.gen2.Unown")
      if Unown and type(Unown.registerCatch) == "function" then
        pcall(Unown.registerCatch, save, mon)
      end
      return (not knew), species
    end
    -- Gen 1: `pokedex.owned` is the caught table and `pokedex.seen` the seen
    -- one (there is no separate `caught` map).  `markOwned` is the native
    -- routine itself when the engine still exports it.
    save.pokedex = save.pokedex or { seen = {}, owned = {} }
    local dex = save.pokedex
    dex.seen = dex.seen or {}
    dex.owned = dex.owned or {}
    local knew = dex.owned[species] and true or false
    local BattleStateMod = tryRequire("src.battle.BattleState")
    if BattleStateMod and type(BattleStateMod.markOwned) == "function" then
      pcall(BattleStateMod.markOwned, game, species)
    end
    dex.owned[species] = true
    dex.seen[species] = true
    if BattleStateMod and type(BattleStateMod.stampOT) == "function" then
      pcall(BattleStateMod.stampOT, save, mon)
    end
    return (not knew), species
  end

  -- The whole modern attempt, behind the mod catch.rate hook.  The hook
  -- contract is unchanged -- (ball, mon, def, opts) in, `caught, rate` out --
  -- with `rate` now the modern `a`; the wrapper also forwards `shakes` and
  -- `chance` so a pass-through chain keeps the exact wobble count it rolled.
  -- A mod that returns only `caught, rate` gets the count re-derived from the
  -- rate it chose (N.shakesFor).
  local function vanillaCatchHook(_, _, _, o)
    local caught, shakes, a, chance = N.catchAttemptForMode(N.catchFormula(), o)
    return caught, a, shakes, chance
  end

  N.runCatch = function(opts)
    opts = opts or {}
    local Runtime = tryRequire("src.mods.Runtime")
    local caught, a, shakes, chance
    if Runtime and type(Runtime.call) == "function" then
      caught, a, shakes, chance = Runtime.call("catch.rate", vanillaCatchHook,
        opts.ball or "POKE_BALL", opts.mon, opts.def, opts)
    end
    if caught == nil then
      caught, shakes, a, chance = N.catchAttemptForMode(N.catchFormula(), opts)
    else
      caught = caught and true or false
      a = a or 0
      if shakes == nil then shakes = N.shakesFor(caught, a, opts.random) end
    end
    if shakes == nil then shakes = 0 end
    return caught, shakes, a, chance
  end

  N.ballThrownWanted = function()
    local Runtime = tryRequire("src.mods.Runtime")
    return (Runtime and type(Runtime.wants) == "function"
      and Runtime.wants("battle.ball_thrown")) and true or false
  end

  N.emitBallThrown = function(payload)
    local Runtime = tryRequire("src.mods.Runtime")
    if Runtime and type(Runtime.emit) == "function" then
      Runtime.emit("battle.ball_thrown", payload)
    end
  end

  ------------------------------------------------------------------
  -- GENERATION 2 -- the real modules and data fields, unchanged.
  ------------------------------------------------------------------
  if N.isGen2 then
    N.Battle = require("src.battle.gen2.Battle")
    N.Catching = require("src.battle.gen2.Catching")
    N.HpBar = require("src.battle.gen2.HpBar")
    N.BattleHud = require("src.ui.gen2.BattleHud")
    N.Mon = require("src.battle.gen2.Mon")
    N.Palettes = require("src.world.gen2.Palettes")
    N.AnimRunner = require("src.battle.gen2.AnimRunner")
    N.BattleAnimView = require("src.ui.gen2.BattleAnimView")
    N.Sprites = require("src.pokemon.Sprites")
    -- The Gen 2 item engine the PACK's battle arm runs through
    -- (engine/items/pack.asm UseItem -> item_effects.asm): partyAction says
    -- which family an item runs on a mon, useOnMon/usePpItem apply it and
    -- own every number and refusal.  The scene calls these rather than
    -- re-deriving an item's effect (see battle_screen's Screen:applyPartyItem).
    N.ItemEffects = require("src.core.gen2.ItemEffects")

    N.paletteData = function(data) return data and data.gen2Palettes end
    N.menuGfxData = function(data) return data and data.gen2MenuGfx end
    N.statusesData = function(data) return data and data.gen2Statuses end
    N.trainersData = function(data) return data and data.gen2Trainers end
    N.constantsData = function(data) return data and data.gen2Constants end
    N.animData = function(data) return data and data.gen2BattleAnims end

    N.monExp = function(mon)
      return mon and (mon.experience or mon.exp) or 0
    end

    N.partyMenuId = function() return "Gen2PartyMenu" end
    N.packMenuId = function() return "Gen2PackMenu" end

    N.isBall = function(id, def) return def ~= nil and def.pocket == "BALL" end

    -- The engine's own prize-money routine (WinTrainerBattle's money arm,
    -- engine/battle/core.asm:2310-2323), required lazily so a boot without the
    -- module still loads the scene.
    local Prize = tryRequire("src.battle.gen2.Prize")

    N.buildBattle = function(opts) return N.Battle.new(opts) end
    N.newStages = function() return N.Battle.newStages() end
    N.takeEvents = function(battle) return battle:takeEvents() end

    N.setParticipants = function(battle, battlers, save, combat)
      battle.participants = {}
      for _, battler in ipairs(battlers) do
        if combat.isAlive(battler) then
          for index, mon in ipairs(save.party) do
            if mon == battler.mon then
              battle.participants[index] = true
              break
            end
          end
        end
      end
    end

    N.awardExperience = function(battle, loser) battle:awardExperience(loser) end

    -- THE MULTI-FAINT EXP POOL (see battle_screen.lua's Screen:awardFaintExp).
    -- A horde -- or any multi-slot layout -- can lose several enemies on ONE
    -- turn.  Per the user's rule their exp is summed into ONE pool first, and
    -- the EXP SHARE config then splits that pool, so the award narrates one
    -- active line and one bench line instead of a pair per enemy.  The scene
    -- asks here for a synthetic stand-in "loser": a species def carrying the
    -- summed single-participant exp as `baseExp` and the summed base stats as
    -- `baseStats`, plus a loser sitting at the engine's own divisor as its
    -- level.  Mon.experienceGain is `floor(baseExp * level / 7)`, so at level
    -- 7 it collapses to exactly the pool, and the config's split divides it
    -- once.  The trainer/traded/lucky multipliers stay OUT of the pool -- the
    -- generation's own pass re-applies them per recipient, exactly as it does
    -- for a single faint.  Returns nil (the caller falls back to one award per
    -- loser) when no loser has a def.
    N.expBatch = function(battle, losers)
      local Mon = N.Mon
      local data = battle and battle.data
      if not Mon or type(losers) ~= "table" or type(data) ~= "table"
          or type(data.pokemon) ~= "table" then return nil end
      local exp, stats, count = 0, {}, 0
      for _, loser in ipairs(losers) do
        local def = battle:speciesDef(loser)
        if def then
          exp = exp + Mon.experienceGain(def, loser.level or 1, 1, false, {})
          for key, value in pairs(def.baseStats or {}) do
            stats[key] = (stats[key] or 0) + (tonumber(value) or 0)
          end
          count = count + 1
        end
      end
      if count == 0 then return nil end
      local id = "__g9_exp_batch__"
      return {
        id = id,
        def = {
          id = id, name = "EXP BATCH", baseExp = exp,
          baseStats = stats, learnset = {},
        },
        loser = { species = id, level = 7 },
      }
    end

    -- THE AFTER-BATTLE EVOLUTION SWEEP (ExitBattle's own `predef
    -- EvolveAfterBattle`, engine/battle/core.asm).  A fight this screen draws
    -- never reaches the native BattleState's WIN arm -- finishTurn/throwBall
    -- just set self.outcome -- so the sweep simply never ran and no
    -- scene-driven battle could EVER evolve a Pokemon.  This is the Gen 2 half
    -- of closing that gap; the Gen 1 half is the same-named function in the
    -- Gen 1 arm below.
    --
    -- `flags` is Screen.g9EvolvableFlags, a set of party INDICES -- Gen 2's own
    -- wEvolvableFlags shape, filled by Screen:awardFaintExp from the model's
    -- per-level `level` events, exactly where the cart sets that slot's bit.
    -- The conditions AND the apply both come from the engine's own module
    -- (src/core/gen2/Evolution.lua), so g9-evolutions' patched rows and every
    -- native row are read the way the cart reads them; the only thing added
    -- here is the screen stack that plays the result.  `runsAfterBattle` is the
    -- native ExitBattle gate (a loss or a draw never evolves); the scene only
    -- calls this on a WIN anyway.
    --
    -- Returns false when there is nothing to stage OR the engine module is
    -- absent (an older engine), so the caller falls straight through to its own
    -- exit.  When it returns true it OWNS the exit and calls onDone once the
    -- last animation has resolved.
    N.runAfterBattleEvolutions = function(screen, onDone)
      local Evolution = tryRequire("src.core.gen2.Evolution")
      local Screens = tryRequire("src.ui.Screens")
      if not (Evolution and type(Evolution.plan) == "function"
          and type(Evolution.runsAfterBattle) == "function"
          and type(Screens) == "table" and type(Screens.push) == "function") then
        return false
      end
      if not Evolution.runsAfterBattle(screen.outcome) then return false end
      local flags = screen.g9EvolvableFlags
      if type(flags) ~= "table" or not next(flags) then return false end
      local game = screen.game
      local battle = screen.battle
      local save = game and game.save
      local party = (battle and battle.party) or (save and save.party) or {}
      -- wTimeOfDay, for the TR_MORNDAY / TR_NITE happiness rows, captured here
      -- exactly as the native screen captures it (Palettes.clockDaytime).
      local timeOfDay
      local Palettes = tryRequire("src.world.gen2.Palettes")
      if Palettes and type(Palettes.clockDaytime) == "function" then
        local ok, value = pcall(Palettes.clockDaytime)
        if ok then timeOfDay = value end
      end
      local plans = Evolution.plan((game and game.data) or {}, party, flags,
        { timeOfDay = timeOfDay })
      if #plans == 0 then return false end
      local index = 0
      local function nextOne()
        index = index + 1
        local plan = plans[index]
        if not plan then
          if onDone then onDone() end
          return
        end
        Screens.push(game, "Gen2EvolutionAnim", {
          mon = plan.mon,
          entry = plan.entry,
          index = plan.index,
          party = party,
          save = save,
          -- The native screen's own chaining, verbatim: the animation calls
          -- onDone and the CALLER pops it (it never pops itself).
          onDone = function()
            game.stack:pop()
            nextOne()
          end,
        })
      end
      nextOne()
      return true
    end

    -- ExitBattle's `farcall GivePokerusAndConvertBerries`, the beat that sits
    -- immediately after `predef EvolveAfterBattle` inside the SAME WIN arm --
    -- so it belongs to the same after-battle moment as the evolution sweep
    -- above and was missing from a scene fight for the same reason.  Silent by
    -- design: nothing tells the player, and the Pokemon Center nurse is the
    -- first thing that ever mentions it.  Gen 1 has no Pokerus and no berry
    -- juice, so the Gen 1 arm defines this as a no-op.  pcall'd -- a save
    -- mutation must never be able to strand the player in a battle that cannot
    -- exit.
    N.afterBattleSaveEffects = function(screen)
      local evolution = tryRequire("src.core.gen2.Evolution")
      if evolution and type(evolution.runsAfterBattle) == "function"
          and not evolution.runsAfterBattle(screen.outcome) then
        return
      end
      local game = screen.game
      local battle = screen.battle
      local save = game and game.save
      if not save then return end
      local party = (battle and battle.party) or save.party or {}
      local BerryJuice = tryRequire("src.battle.gen2.BerryJuice")
      if BerryJuice and type(BerryJuice.convertAfterBattle) == "function" then
        pcall(BerryJuice.convertAfterBattle, save, party)
      end
      local Pokerus = tryRequire("src.core.gen2.Pokerus")
      if Pokerus and type(Pokerus.giveAfterBattle) == "function" then
        pcall(Pokerus.giveAfterBattle, save, party)
      end
    end

    -- Prize money for beating a trainer -- the engine's OWN routine, not a
    -- re-derivation: Prize.award is ComputeTrainerReward + WinTrainerBattle
    -- (baseMoney x wCurPartyLevel, four quarters split between the wallet and
    -- the Bank of Mom, the Amulet Coin doubling before the split) and
    -- Prize.message is the exact line the cart prints.  wCurPartyLevel is
    -- Prize.rewardLevel(enemyParty) -- the LAST row ReadTrainerParty built,
    -- whichever mon actually fainted last -- which is what vanilla pays for
    -- (Falkner's level 9 Pidgeotto, not the level 7 Pidgey that came out
    -- first).  `trainer` is passed explicitly because the caller owns the real
    -- trainer record and battle.trainer is not guaranteed on every arm (the
    -- Gen 1 model carries none at all) -- one signature, both arms.  Returns
    -- nil when there is nothing to pay, so a caller can never print a line for
    -- money that was not handed over.
    N.awardTrainerPrize = function(battle, save, trainer)
      if not (battle and save and save.player) then return nil end
      if not (Prize and Prize.award and Prize.rewardLevel and Prize.message) then
        return nil
      end
      trainer = trainer or battle.trainer
      if type(trainer) ~= "table" then return nil end
      local award = Prize.award(save, {
        baseMoney = trainer.baseMoney,
        level = Prize.rewardLevel(battle.enemyParty),
        amuletCoin = battle.amuletCoin,
      })
      if not award or (award.total or 0) <= 0 then return nil end
      return {
        amount = award.total,
        award = award,
        text = Prize.message(award, save.player.name),
      }
    end

    -- The selected catch formula (see the CATCH RATE block above).  Gen 2
    -- keeps its captured tail: a caught mon is reloaded out of its base data
    -- and the battle.catch_exp hook runs, both through Battle:caught.
    N.catchAttempt = function(opts)
      opts = opts or {}
      local caught, shakes, a, chance = N.runCatch(opts)
      if caught and opts.battle and type(opts.battle.caught) == "function" then
        opts.battle:caught(opts.mon)
      end
      if N.ballThrownWanted() then
        N.emitBallThrown({
          battle = opts.battle, ball = opts.ball or "POKE_BALL",
          caught = caught, shakes = shakes, rate = a, chance = chance,
          mon = opts.mon, species = opts.species,
        })
      end
      return caught, shakes, a, chance
    end

    -- The pre-existing Gen 2 full-party destination: insertion at the head of
    -- the current box, refilling PP.  Returns ok, message-suffix.
    N.depositCatch = function(save, mon)
      local Boxes = require("src.core.gen2.Boxes")
      local index = math.max(1, math.min(Boxes.NUM_BOXES,
        math.floor(tonumber(save.currentBox) or 1)))
      local box = Boxes.box(save, index)
      table.insert(box, 1, mon)
      if type(Boxes.enterBox) == "function" then Boxes.enterBox(mon) end
      local where = (Boxes.name and Boxes.name(save, index)) or "the PC"
      return true, " It was sent to " .. where .. "."
    end

    N.resolveTurn = function(g9dex, battle, actingBattlers)
      g9dex.exports.resolveTurnActions(battle, actingBattlers)
      return battle:takeEvents()
    end

    -- Resume a turn a pivot self-switch paused (see g9-battle-engine's
    -- combat/turn_order.lua PIVOT PAUSE).  The engine re-enters its own
    -- resolver with the mon the scene sent in; the rest of the round's events
    -- are drained here exactly like N.resolveTurn's.
    N.resumeAfterPivot = function(g9dex, battle, incoming, outgoing)
      local eng = g9dex and g9dex.exports
      if not (eng and type(eng.resumeAfterPivot) == "function") then return {} end
      eng.resumeAfterPivot(battle, incoming, outgoing)
      return battle:takeEvents()
    end

    N.statusLabel = nil

    -- -- trainer intro art ---------------------------------------------
    -- Player back-pic: native reads gen2MenuGfx.battleHud and raises
    -- player.sprite over it.  Returns path, trueColor, colours.
    N.playerBackArt = function(data, save, battle)
      local hud = data and data.gen2MenuGfx and data.gen2MenuGfx.battleHud
      local palettes = data and data.gen2Palettes
      local female = save and save.player
        and save.player.gender == "female"
      local path = hud and hud.playerBack
      if hud and hud.playerBackFemale and female then
        path = hud.playerBackFemale
      end
      local trueColor = false
      if path then
        path, trueColor = N.Sprites.playerPic(path, {
          side = "back", kind = "battle", battle = battle, data = data,
        })
      end
      local colors = N.Palettes.trainerColors(palettes,
        female and "FALKNER" or "PLAYER")
        or N.Palettes.trainerColors(palettes, "PLAYER")
      return path, trueColor, colors
    end

    -- Enemy class front-pic, same sources native's BattleState:drawPic reads.
    -- Returns path, trueColor, colours.
    N.enemyTrainerArt = function(data, trainerData)
      local hud = data and data.gen2MenuGfx and data.gen2MenuGfx.battleHud
      local palettes = data and data.gen2Palettes
      local classId = trainerData.classId or trainerData.class
      local classes = data and data.gen2Trainers
        and data.gen2Trainers.classes
      local classDef = classes and classes[classId]
      local path = (classDef and classDef.pic)
        or (hud and hud.trainerPics and hud.trainerPics[classId])
      local trueColor = (classDef and classDef.trueColor) and true or false
      return path, trueColor, N.Palettes.trainerColors(palettes, classId)
    end

  ------------------------------------------------------------------
  -- GENERATION 1 -- adapters over the Gen 1 engine's own primitives.
  ------------------------------------------------------------------
  else
    local BattleState = require("src.battle.BattleState")
    local Catching = require("src.battle.Catching")
    local Experience = require("src.battle.Experience")
    local Stats = tryRequire("src.pokemon.Stats")
    local Growth = require("src.pokemon.Growth")
    local Status = require("src.battle.Status")
    local TurnOrder = require("src.battle.TurnOrder")
    local HudTiles = require("src.render.HudTiles")
    -- Pure (no love, no requires) HP-bar maths, vendored for the exact
    -- ComputeHPBarPixels / GetHPPal math.  VENDORED as the mod's own
    -- hp_bar.lua rather than required by its engine name: the engine's
    -- cross-generation require gate (src/mods/Loader.lua's
    -- crossGenerationDenial) refuses every require("src.*.gen2.*") on a Gen 1
    -- boot, so the engine module is unreachable from here even though its
    -- code is pure.  The Gen 2 arm above still requires the real engine
    -- module and is unchanged.
    local HpBarPure = loadSiblingFile("hp_bar.lua")

    ------------------------------------------------------------------
    -- GEN 2 ASSETS ON A GEN 1 BOOT.
    -- See the header's "Calling the Gen 2 assets into Gen 1" note.  A stock
    -- Gen 1 boot has none of these tables, so every accessor below keeps
    -- answering nil (its previous behaviour); a build that carries them gets
    -- the Gen 2 asset set through the same code the Gen 2 arm runs.
    ------------------------------------------------------------------
    local GEN2_ASSET_KEYS = {
      "gen2Palettes", "gen2MenuGfx", "gen2Statuses", "gen2Trainers",
      "gen2Constants", "gen2BattleAnims",
    }
    -- `data` iff it carries at least one Gen 2 asset table, else nil.
    local function gen2Assets(data)
      if type(data) ~= "table" then return nil end
      for _, key in ipairs(GEN2_ASSET_KEYS) do
        if data[key] then return data end
      end
      return nil
    end
    N.gen2Assets = gen2Assets
    -- Is a Gen 2 asset pack present in this boot?  Probed off the live
    -- game-data singleton at LOAD time: the engine loads generated data and
    -- folds every mod merge over it BEFORE the mod loader runs, so this sees
    -- everything a "Gen 1 boot carrying Gen 2 assets" would carry.  A stock
    -- Gen 1 boot answers false, and the Gen 2 modules below are then never
    -- loaded at all.  (The accessors further down still read the per-call
    -- `data`, so an asset table that appears later is not lost.)
    local bootData = tryRequire("src.core.Data")
    local gen2 = gen2Assets(bootData) ~= nil
    -- The shared Gen 2 modules the Gen 2 arm loads unconditionally, pcall'd
    -- so a trimmed build yields nil rather than failing the boot.
    local Gen2Palettes = gen2 and tryRequire("src.world.gen2.Palettes") or nil
    local Gen2BattleHud = gen2 and tryRequire("src.ui.gen2.BattleHud") or nil

    N.HpBar = HpBarPure
    N.Catching = Catching
    N.Sprites = require("src.pokemon.Sprites")

    -- -- HUD ---------------------------------------------------------
    -- A HudTiles-backed stand-in for the Gen 2 BattleHud interface the scene
    -- calls: :available() / :drawHpBar(hp,maxHp,tx,ty) / :drawExpBar(...),
    -- plus the static EXP_LENGTH_PX.  Gen 1's own DrawHPBar already draws the
    -- same "HP:" + six 8px cells + cap at the same 48px width, so the readout
    -- geometry carries over.  Gen 1 has no in-battle exp bar, so drawExpBar
    -- is a deliberate no-op (the player readout simply has no exp row).
    local HudMt = {}
    HudMt.__index = HudMt
    HudMt.EXP_LENGTH_PX = HpBarPure.LENGTH_PX
    function HudMt.new() return setmetatable({}, HudMt) end
    function HudMt:available() return true end
    function HudMt:drawHpBar(hp, maxHp, tx, ty)
      local data = require("src.core.Data")
      local shim = { hp = math.max(0, hp or 0),
                     stats = { hp = math.max(1, maxHp or 1) } }
      -- barType 1 is the player's own in-battle bar (double-bar cap).
      return pcall(HudTiles.drawHPBar, data, tx, ty, shim, 1)
    end
    function HudMt:drawExpBar() return false end
    N.BattleHud = HudMt

    -- "All the Gen 2 assets" includes the HUD itself.  Gen 2's battle HUD
    -- draws the cart's own $60-$78 tiles AND a real exp bar, which is exactly
    -- what the scene was written against; HudMt exists only because a stock
    -- Gen 1 boot cannot supply the Gen 2 menu graphics.  So hand the scene the
    -- real Gen 2 HUD the moment those graphics are present, and HudMt
    -- otherwise.  Same entry points either way (:available(), :drawHpBar,
    -- :drawExpBar, .EXP_LENGTH_PX) -- which is all the scene talks to.
    local HudDispatch = {}
    function HudDispatch.new(menuGfx, palettes)
      if Gen2BattleHud and menuGfx and menuGfx.battleHud then
        return Gen2BattleHud.new(menuGfx, palettes)
      end
      return HudMt.new()
    end
    HudDispatch.EXP_LENGTH_PX = (Gen2BattleHud and Gen2BattleHud.EXP_LENGTH_PX)
      or HudMt.EXP_LENGTH_PX
    N.BattleHud = HudDispatch

    -- -- exp curve ----------------------------------------------------
    -- Mon.partySpecies/growthFor/experienceForLevel, the three helpers the
    -- expFraction readout uses.  Gen 1's mon stores its total as `.exp` (the
    -- scene reads that through N.monExp) and its curve is evaluated by the
    -- real src.pokemon.Growth, exactly as Experience.apply does it.
    N.Mon = {
      MAX_LEVEL = 100,
      partySpecies = function(mon) return mon and mon.species end,
      growthFor = function(data, rate)
        return { rate = rate, rates = data and data.growth_rates }
      end,
      experienceForLevel = function(growth, level)
        if not growth then return 0 end
        return Growth.expForLevel(growth.rate, level, growth.rates)
      end,
    }

    -- -- trainer colours ----------------------------------------------
    -- The Gen 2 class-colour rows, from the same module the Gen 2 arm uses,
    -- whenever the Gen 2 palette table is present.  With none, nil -- which
    -- makes drawRawImage draw the sheet raw, the honest DMG look rather than a
    -- wrong tint (Gen 1's own SGB colouring is a native-screen pipeline this
    -- scene does not reproduce).
    N.Palettes = {
      trainerColors = function(palettes, classId)
        if not (Gen2Palettes and palettes) then return nil end
        return Gen2Palettes.trainerColors(palettes, classId)
      end,
    }

    -- Gen 2's move-animation engine, the same modules the Gen 2 arm wires.
    -- Loaded only when the Gen 2 assets are actually present (pcall-guarded on
    -- top).  When they are, the scene's move-anim entry points take the Gen 2
    -- path exactly as they always did (the Gen 2 arm's own engine, on a Gen 1
    -- boot); when they are not, the Gen 1 arm below takes over instead.
    N.AnimRunner = gen2 and tryRequire("src.battle.gen2.AnimRunner") or nil
    N.BattleAnimView = gen2
      and tryRequire("src.ui.gen2.BattleAnimView") or nil

    ------------------------------------------------------------------
    -- GEN 1'S OWN MOVE-ANIMATION ENGINE -- src/battle/AnimPlayer.lua.
    --
    -- The cart's Red/Blue/Yellow battle animations are played by a
    -- DIFFERENT module with a DIFFERENT data contract from Gen 2's
    -- AnimRunner: AnimPlayer compiles `data.battle_anims`' moveAnims rows
    -- into a flat list of timed OAM steps at :start() (the subanimation
    -- player of engine/battle/animations.asm, reimplemented), then just
    -- ticks them with :update()/:isDone().  That is why the scene needs an
    -- arm, not a translation -- but it IS the native engine, and the
    -- scene's Gen 1 arms drive exactly the contract the game's own
    -- BattleState drives (src/battle/BattleState.lua:1399-1405).
    --
    -- Loaded whenever the module resolves.  The engine's own cross-
    -- generation gate (src/mods/Loader.lua) refuses `src.*.gen2.*` on a Gen
    -- 1 boot but `src.battle.AnimPlayer` is Gen 1's own module, so it is
    -- always reachable here; tryRequire keeps a trimmed build from failing
    -- the boot over it.  A missing module (or missing `data.battle_anims`)
    -- simply makes the scene's Gen 1 animation call sites no-ops.
    N.AnimPlayer = tryRequire("src.battle.AnimPlayer")

    -- `data.battle_anims` is a BASE Gen 1 generated module (src/core/
    -- Data.lua's MODULES list), so it is there on every Red/Blue/Yellow
    -- boot -- unlike the `gen2*` tables above, which are an optional pack.
    -- Shape: { moveAnims = { <id> = {seq=...} }, subanims, frameBlocks,
    -- baseCoords, tilesheets } -- see tools/extract/battle_anims.py.
    N.gen1AnimData = function(data) return data and data.battle_anims end

    -- BattleState:tossAnimFor (src/battle/BattleState.lua:5499-5506): the
    -- ball record's own tossAnim, else wCurItem's mapping
    -- POKE->TOSS, GREAT->GREATTOSS, everything else ULTRATOSS.
    N.ballTossAnim = function(ballId)
      local def = Catching.BALLS and Catching.BALLS[ballId]
      if def and def.tossAnim then return def.tossAnim end
      return ballId == "POKE_BALL" and "TOSS_ANIM"
          or ballId == "GREAT_BALL" and "GREATTOSS_ANIM"
          or "ULTRATOSS_ANIM"
    end

    -- The Master/Ultra OBJ-palette strobe, off the ball record
    -- (DoBallTossSpecialEffects; AnimPlayer's own opts.ballFlicker).
    N.ballFlicker = function(ballId)
      local def = Catching.BALLS and Catching.BALLS[ballId]
      return (def and def.flicker) or false
    end

    -- A battle_anim row's sound byte is a MOVE id: GetMoveSound plays that
    -- move's MoveSoundTable entry (sfx + its own pitch/tempo bytes), except
    -- that the GROWL/ROAR animations (IsCryMove) play the ATTACKER's cry
    -- instead, with the move's own tempo layered on.  Mirrors
    -- BattleState:playAnimSound, pcall'd so a trimmed engine or a headless
    -- harness simply plays nothing rather than aborting the animation.
    -- `opts.animName`/`opts.crySpecies` are the running animation's id and
    -- its attacker's species (only GROWL/ROAR read them).
    N.playMoveAnimSound = function(data, soundMove, opts)
      if not soundMove then return end
      local ok, Sound = pcall(require, "src.core.Sound")
      if not ok or type(Sound) ~= "table" then return end
      local mdef = data and data.moves and data.moves[soundMove]
      local anim = mdef and mdef.anim
      local name = opts and opts.animName
      if (name == "GROWL" or name == "ROAR") and opts and opts.crySpecies then
        if type(Sound.playMoveCry) == "function" then
          pcall(Sound.playMoveCry, data, opts.crySpecies, anim and anim.tempo)
        end
        return
      end
      if not anim then return end
      if type(Sound.playMove) == "function" then
        pcall(Sound.playMove, data, anim)
      elseif anim.sound then
        pcall(Sound.play, data, anim.sound)
      end
    end

    -- The Gen 2 asset tables, straight off `data` exactly as the Gen 2 arm
    -- reads them.  Absent on a stock Gen 1 boot (nil, the accessors' previous
    -- answer); present on a build carrying the Gen 2 assets, which then get
    -- the whole set: menu graphics + palettes for the HUD, battle animations,
    -- trainer art and colours, authored status labels.
    N.paletteData = function(data) return data and data.gen2Palettes end
    N.menuGfxData = function(data) return data and data.gen2MenuGfx end
    N.statusesData = function(data) return data and data.gen2Statuses end
    N.trainersData = function(data) return data and data.gen2Trainers end
    N.constantsData = function(data) return data and data.gen2Constants end
    N.animData = function(data) return data and data.gen2BattleAnims end

    N.monExp = function(mon) return mon and (mon.exp or 0) or 0 end

    N.partyMenuId = function() return "PartyMenu" end
    N.packMenuId = function() return "ListMenu" end

    N.isBall = function(id) return Catching.BALLS[id] ~= nil end

    N.newStages = function() return {} end

    -- -- the battle model ---------------------------------------------
    -- A real BattleState instance (so the game's own methods are all on the
    -- metatable) used as a MODEL: `makeBattler` builds the native battlers
    -- from the caller's own mon tables, `performMove` is the native move
    -- executor, and the screen-side message queue is drained into the event
    -- stream this scene already paces on.
    N.buildBattle = function(opts, game, data)
      local state = setmetatable({}, BattleState)
      state.game = game
      state.data = game.data
      state.kind = (data.trainer ~= nil and data.trainer ~= false)
        and "trainer" or "wild"
      state.rng = function(a, b) return love.math.random(a, b) end
      state.random = state.rng
      state.queue = {}
      state.events = {}
      state.participants = {}
      state.moveAnimRow = nil
      state.nextInsert = 0
      state.stages = { player = {}, enemy = {} }
      -- The substrate EffectRegistry/Status expect on a battle object.
      state.sides = {
        { index = 1, battlers = {}, screens = {}, hazards = {}, tokens = {} },
        { index = 2, battlers = {}, screens = {}, hazards = {}, tokens = {} },
      }
      state.field = { weather = nil, tokens = {}, sides = state.sides }

      local rulesets = game.data.rulesets or {}
      local selected = game.save and game.save.options
        and game.save.options.ruleset
      state.ruleset = (selected and rulesets[selected])
        or rulesets.gen1_faithful
        or tryRequire("src.battle.rulesets.gen1_faithful")

      -- Native battlers for every mon the scene will field, keyed by the mon
      -- table itself so the g9dex-shaped useMove(monMon, monTarget, moveId)
      -- call can find them.
      local byMon, sideByMon, orderMons = {}, {}, {}
      state.battlersByMon = byMon
      state.sideByMon = sideByMon
      state.rosterMons = orderMons
      local function addBattler(mon, isPlayer)
        if not mon or byMon[mon] then return end
        byMon[mon] = BattleState.makeBattler(game.data, mon, isPlayer,
          isPlayer and game.save or nil)
        sideByMon[mon] = isPlayer and "player" or "enemy"
        orderMons[#orderMons + 1] = mon
      end
      for _, mon in ipairs(data.enemies or {}) do addBattler(mon, false) end
      for _, mon in ipairs(data.players or {}) do addBattler(mon, true) end

      state.enemyParty = data.enemies or {}
      state.enemyIndex = 1
      state.enemy = (data.enemies and data.enemies[1]) and byMon[data.enemies[1]]
      state.player = (data.players and data.players[1]) and byMon[data.players[1]]

      function state:emit(event) table.insert(self.events, event) end
      function state:takeEvents()
        local out = self.events
        self.events = {}
        return out
      end
      function state:clearVolatile(mon)
        local battler = byMon[mon]
        if battler then pcall(BattleState.clearVolatiles, self, battler) end
      end
      function state:setEnemyIndex(mon)
        for i, m in ipairs(self.enemyParty) do
          if m == mon then self.enemyIndex = i return end
        end
      end

      -- BattleState.lua keeps displayName local; mirrored here for the
      -- recharge line ("Enemy X must recharge!") exactly as that file builds
      -- it (raw name on the player side, the "Enemy " qualifier on the foe's).
      local function displayName(battler)
        if battler.isPlayer then return battler.name end
        return require("src.core.Strings")("Enemy %s", battler.name)
      end

      -- BattleState.lua's own local, read off the live ruleset; decides
      -- whether a side's poison/burn/leech-seed residual runs right after
      -- its move (Gen 1 / gen1_faithful) or in the end-of-round sweep
      -- (modern_clean). Mirrored here so the scene's per-move call matches
      -- what BattleState:endOfTurn will do with `sweep`.
      local function residualAfterMove(battle)
        local ruleset = battle.ruleset
        return not ruleset or ruleset.residualAfterMove ~= false
      end

      -- BattleState:statusInterrupt (the pre-move status gauntlet:
      -- sleep/freeze/held-in-place/flinch/disable/confusion/full-paralysis),
      -- guarded so an older vanilla BattleState without the method cannot
      -- take the battle down. Returns true when the action was eaten.
      function state:statusGate(user, target, moveId)
        if type(BattleState.statusInterrupt) ~= "function" then return false end
        local ok, interrupted = pcall(BattleState.statusInterrupt, self, user,
          target, moveId)
        return ok and interrupted or false
      end

      -- The native move executor, in the g9dex shape (mons, not battlers).
      -- Drains the native screen queue this move filled into real events, each
      -- routed through self:emit so the scene's event probe stamps its HP
      -- snapshot exactly as it does on Gen 2.
      --
      -- IMPORTANT: performMove is only the move EXECUTOR. The rest of a Gen 1
      -- turn -- the pre-move status gauntlet, the recharge arm, the trapping
      -- continuation and the per-move residual -- lives in
      -- BattleState:executeAction, and the scene calls performMove directly.
      -- Every one of those effects is therefore reproduced here, in the
      -- asm's own order (core.asm CheckPlayerStatusConditions), or a flinched/
      -- sleeping/frozen/fully-paralysed/confused/must-recharge mon would
      -- silently get a free move.
      function state:useMove(attackerMon, defenderMon, moveId)
        -- A Pokemon that only reaches the field MID-battle -- a benched mon
        -- switched in -- has no engine battler yet: `byMon` is built from the
        -- STARTING field roster only.  Native builds a fresh battler from the
        -- mon on every switch-in (BattleState.makeBattler) and this scene
        -- caches ONE per mon and reuses it (see g9-battle-engine's own
        -- combat/modern_transform.lua note), so the equivalent here is to
        -- build it the first time the mon is actually used.  Without this a
        -- switched-in mon could neither be hit nor attack on Gen 1 -- the
        -- scene's own retarget of a queued attacker onto the arriving mon
        -- (Screen:advanceResolving's switch branch) would resolve against a
        -- mon with no battler and the move would be dropped in silence --
        -- which is what makes a switch-in take the hit it now correctly aims
        -- at.
        local function ensureBattler(mon)
          if not mon or byMon[mon] then return end
          addBattler(mon, mon.multiSide ~= "enemy")
        end
        ensureBattler(attackerMon)
        ensureBattler(defenderMon)
        local user = byMon[attackerMon]
        local target = defenderMon and byMon[defenderMon] or nil
        if not (user and target) then return end
        local inst
        for _, slot in ipairs(user.mon.moves or {}) do
          if slot.id == moveId then inst = slot break end
        end
        inst = inst or { id = moveId, pp = 1 }
        self.queue = {}
        self.nextInsert = 0
        self.moveAnimRow = nil
        -- The scene's own HP vector as of BEFORE this action resolves (see
        -- drainNativeMove): the per-hit drain beats walk this forward, so a
        -- multi-hit move's bar comes to rest at every landed hit instead of
        -- jumping to the final total.  `g9Scene` is published by the scene's
        -- event probe; without it every beat falls back to the probe's own
        -- live snapshot, exactly as before this change.
        self.__g9PreMoveSnap = (self.g9Scene and self.g9Scene.snapshotHp)
          and self.g9Scene:snapshotHp() or nil
        -- The held-in-place mirror executeAction refreshes before the status
        -- checks (core.asm:414-416): the victim is held exactly while the
        -- opponent's trapping counter is live (including a counter sitting at
        -- 0 until the end-of-turn release).
        user.boundTurns = target.trappingTurns
                          and math.max(1, target.trappingTurns) or nil
        -- Recharge turn (Hyper Beam et al): executeAction's `recharge` arm
        -- never reaches performMove. The pre-recharge slice can still eat the
        -- turn WITHOUT consuming the flag -- the native Hyper Beam glitch --
        -- which is exactly what preRechargeChecks reproduces.
        if user.mustRecharge then
          local blocked = false
          if type(BattleState.preRechargeChecks) == "function" then
            local oka, ate = pcall(BattleState.preRechargeChecks, self,
              user, target)
            blocked = oka and ate or false
          end
          if not blocked then
            user.mustRecharge = nil
            self:sayNext(self:romText("_MustRechargeText",
              "%s\nmust recharge!", displayName(user)))
          end
          self:drainNativeMove(nil)
          return
        end
        -- Trapping continuation: while this battler's trapping counter is
        -- live the native turn ignores its choice and runs the locked
        -- continuation (executeAction's `trapping` arm). The counter is
        -- released by BattleState:endOfTurn once it has reached 0.
        if user.trappingTurns then
          if self:statusGate(user, target, user.trapMove) then
            self:drainNativeMove(nil)
            return
          end
          self:continueTrapping(user, target)
          self:drainNativeMove(user.trapMove)
          return
        end
        -- Bide continuation: the exact same shape one branch down from
        -- executeAction's own `bide` arm (core.asm's fightLockedAction -- a
        -- live store skips the move menu and runs continueBide).  The store is
        -- STARTED by the Bide move's own effect (g9-battle-engine's
        -- GALAR_BIDE_EFFECT -- see combat/modern_bide.lua); from then on every
        -- turn runs the cart's native wait/release here, which is also what
        -- keeps a continuation from spending a second PP (it never reaches
        -- performMove).  `statusInterrupt` still gets first refusal, so a
        -- sleeping/frozen/paralysed user loses the beat but keeps the store,
        -- matching the native order.
        if user.bideTurns and type(BattleState.continueBide) == "function" then
          if self:statusGate(user, target, "BIDE") then
            self:drainNativeMove(nil)
            return
          end
          local okBide, errBide = pcall(BattleState.continueBide, self, user, target)
          self:drainNativeMove("BIDE")
          if not okBide then error(errBide, 0) end
          return
        end
        -- The pre-move status gauntlet, before every ordinary move. When it
        -- eats the turn, the status text it queued is all this action emits.
        if self:statusGate(user, target, moveId) then
          self:drainNativeMove(nil)
          return
        end
        local ok, err = pcall(BattleState.performMove, self, user, target,
          inst, false)
        -- Gen 1 timing: each side's poison/burn/leech-seed residual runs
        -- right after its OWN move (residualAfterMove rulesets) -- the
        -- trailing HandlePoisonBurnLeechSeed executeAction queues. The
        -- modern ruleset skips this and the end-of-round sweep in
        -- BattleState:endOfTurn runs instead.
        if ok and residualAfterMove(self) then
          local rok, rerr = pcall(BattleState.residualFor, self, user, target)
          if not rok then ok, err = false, rerr end
        end
        self:drainNativeMove(moveId)
        if not ok then error(err, 0) end
      end

      -- A shallow copy of an HP vector (mon table -> hp).  Each emitted beat
      -- carries its own copy rather than the running table the next drain row
      -- would overwrite, so the scene's chase can hold it safely.
      function state.copyHpSnap(src)
        local out = {}
        for mon, hp in pairs(src) do out[mon] = hp end
        return out
      end

      function state:drainNativeMove(moveId)
        -- The native queue carries the bar's OWN per-hit stops: every landed
        -- hit funnels through BattleState:applyDamage -> self:drainNext(target,
        -- target.mon.hp), which queues { drain = true, battler = target,
        -- stopAt = <hp after THIS hit> }.  The multi-hit loop in
        -- EffectRegistry.runDamaging calls applyDamage once per hit, so the
        -- queue holds one drain row per hit.  Walking them in order and
        -- emitting a textless beat apiece is what lets the scene's own chase
        -- rest at EVERY hit -- previously everything but .text was dropped, so
        -- each event the scene saw already carried the final total and a
        -- two-hit move animated as ONE drop (the reported collapse).
        --
        -- `snap` starts at the HP vector from before this action and steps
        -- forward with each drain row, so the beats are the real per-hit
        -- positions (and a recoil drain on the user lands after the target's,
        -- exactly as the native queue orders them).
        local base = self.__g9PreMoveSnap
        local snap = base and state.copyHpSnap(base) or nil
        for _, row in ipairs(self.queue) do
          if type(row) == "table" then
            if row.drain and row.battler and row.battler.mon and snap then
              snap[row.battler.mon] = row.stopAt or (row.battler.mon.hp or 0)
              self:emit({ kind = "damage", g9SceneHp = state.copyHpSnap(snap) })
            elseif type(row.text) == "string" then
              self:emit({ kind = "say", text = row.text,
                          g9SceneHp = snap and state.copyHpSnap(snap) or nil })
            end
          end
        end
        -- A move happened: give the scene a per-action move beat so anything
        -- keyed to it (a future Gen 1 animation arm) has a hook.  No anim
        -- module is wired on Gen 1, so the scene's handler is a no-op today.
        if moveId then self:emit({ kind = "move", move = moveId }) end
        self.queue = {}
        self.nextInsert = 0
        self.__g9PreMoveSnap = nil
      end

      -- Experience, via the pure module the native screen's awardExp is built
      -- on, now raised through the engine's shared battle.exp_award seam so
      -- the EXP SHARE option (exp_share.lua) has one hook point on BOTH
      -- generations -- previously this override resolved the split itself and
      -- the hook never fired on a scene-driven Gen 1 battle at all.
      --
      -- ctx is built to the engine's own Gen 1 shape.  `participants`/`alive`
      -- describe whichever player mons the scene marked active for THIS
      -- enemy (battle.expSharePending.active, the per-enemy "stood on the
      -- field during its stay" set Screen:awardFaintExp stashes); without it
      -- the mon-keyed self.participants the screen rebuilds from the field is
      -- used, exactly as before.  `applyShare(mon, split, announce)` pays one
      -- mon through the engine's Experience.apply and raises
      -- battle.exp_gained for it -- the same event the Gen 2 pass emits and
      -- the g9-battle-engine EV-yield subscriber reads.
      function state:awardExperience(loser)
        local def = loser and self.data.pokemon[loser.species]
        if not def then return end
        local Runtime = tryRequire("src.mods.Runtime")
        local party = (self.game and self.game.save and self.game.save.party)
          or {}
        local playerId = self.game.save and self.game.save.player
          and self.game.save.player.id
        local pending = self.expSharePending
        local activeSet = pending and pending.active or nil
        if not (type(activeSet) == "table" and next(activeSet)) then
          activeSet = nil
        end
        local participants, alive = 0, {}
        for _, mon in ipairs(party) do
          local isActive = activeSet and activeSet[mon]
            or (not activeSet and self.participants and self.participants[mon])
          if isActive then
            participants = participants + 1
            if (mon.hp or 0) > 0 then alive[#alive + 1] = mon end
          end
        end
        if participants == 0 and self.player and self.player.mon
            and (self.player.mon.hp or 0) > 0 then
          participants, alive = 1, { self.player.mon }
        end
        -- The native per-level learn checks (engine/battle/experience.asm:245-
        -- 256).  A mon that reaches a level its species learns a move at either
        -- learns it at once (a free slot) or -- full moveset -- has to be asked
        -- which move to forget.  This arm bypasses BattleState:learnMove (it is
        -- queue-coupled to the native screen), so the checks are re-issued as
        -- scene events instead: a `learn` line, or a `choose-forget` record the
        -- screen parks on until the player answers (Screen:beginMoveLearn).
        -- The mon's OWN record is read per level, so a multi-level gain learns
        -- every move each level grants, exactly as the native loop does -- the
        -- pooled multi-faint award's synthetic loser def never matters here.
        local function learnAt(mon, lv)
          local speciesDef = self.data.pokemon[mon.species]
          if not speciesDef then return end
          local speciesName = mon.nickname
            or (type(speciesDef.name) == "string" and speciesDef.name)
            or tostring(mon.species)
          for _, moveId in ipairs(Experience.movesLearnedAt(speciesDef, lv)) do
            mon.moves = mon.moves or {}
            local known = false
            for _, mv in ipairs(mon.moves) do
              if mv.id == moveId then known = true break end
            end
            local mdef = self.data.moves[moveId]
            if not known and mdef then
              if #mon.moves < 4 then
                mon.moves[#mon.moves + 1] = { id = moveId, pp = mdef.pp }
                if Runtime and type(Runtime.emit) == "function" then
                  Runtime.emit("pokemon.move_learned",
                    { mon = mon, moveId = moveId })
                end
                self:emit({ kind = "learn", mon = mon, move = moveId,
                  text = require("src.core.Strings")("%s learned %s!",
                    speciesName, mdef.name) })
              else
                self:emit({ kind = "choose-forget", mon = mon, move = moveId,
                  moveName = mdef.name })
              end
            end
          end
        end
        local function applyShare(mon, split, announce)
          local traded = playerId ~= nil
            and ((mon.otId ~= nil and mon.otId ~= playerId)
              or (mon.otId == nil and mon.traded == true))
          local levels, gained = Experience.apply(self.data, mon, def,
            loser.level or 1, self.kind == "trainer", split, traded, nil)
          -- Track level-ups for the after-battle evolution sweep, exactly the
          -- way the native screen tracks wEvolvableFlags: a mon that grew this
          -- fight is what EvolveAfterBattle walks, and the B-cancel leaves the
          -- mon at/above its threshold so it is NOT re-offered after every
          -- later fight.  Kept mon-keyed (Gen 1's own checkParty shape) on the
          -- model, which is what this shim's self is.
          if levels and #levels > 0 then
            self.g9LeveledUp = self.g9LeveledUp or {}
            self.g9LeveledUp[mon] = true
            -- GrewLevelText (experience.asm:245) followed by the move checks,
            -- the native order: one "grew to level" line per level reached,
            -- each followed by that level's learn checks.
            local speciesDef = self.data.pokemon[mon.species]
            local speciesName = mon.nickname
              or (speciesDef and speciesDef.name) or tostring(mon.species)
            local Strings = require("src.core.Strings")
            for _, lv in ipairs(levels) do
              self:emit({ kind = "level", mon = mon, level = lv,
                text = Strings("%s grew to level %d!", speciesName, lv) })
              learnAt(mon, lv)
            end
          end
          if Runtime and type(Runtime.emit) == "function" then
            Runtime.emit("battle.exp_gained", {
              battle = self, mon = mon, gained = gained, levels = levels,
            })
          end
          -- exp_share.lua's condensed summary reads each mon's real gain off
          -- battle.exp_gained; this return is the no-Runtime fallback for the
          -- same figure (the argument it prints from).
          return gained
        end
        -- The vanilla award, unchanged: the mon-keyed self.participants the
        -- screen sets right before awarding, split across the survivors.
        local function vanillaExpAward(ctx)
          local count = 0
          if self.participants then
            for _ in pairs(self.participants) do count = count + 1 end
          end
          if count == 0 then count = 1 end
          for _, mon in ipairs(party) do
            if self.participants and self.participants[mon]
                and (mon.hp or 0) > 0 then
              ctx.applyShare(mon, count, true)
            end
          end
        end
        local ctx = {
          battle = self, participants = math.max(1, participants),
          alive = alive, applyShare = applyShare,
        }
        if Runtime and type(Runtime.wantsHook) == "function"
            and Runtime.wantsHook("battle.exp_award") then
          Runtime.call("battle.exp_award", vanillaExpAward, ctx)
        else
          vanillaExpAward(ctx)
        end
      end

      return state
    end

    N.setParticipants = function(battle, battlers, save, combat)
      battle.participants = {}
      for _, battler in ipairs(battlers) do
        if combat.isAlive(battler) then battle.participants[battler.mon] = true end
      end
    end

    N.takeEvents = function(battle) return battle:takeEvents() end

    N.awardExperience = function(battle, loser) battle:awardExperience(loser) end

    -- THE MULTI-FAINT EXP POOL (see battle_screen.lua's Screen:awardFaintExp).
    -- A horde -- or any multi-slot layout -- can lose several enemies on ONE
    -- turn.  Per the user's rule their exp is summed into ONE pool first, and
    -- the EXP SHARE config then splits that pool, so the award narrates one
    -- active line and one bench line instead of a pair per enemy.  The scene
    -- asks here for a synthetic stand-in "loser": a species def carrying the
    -- summed single-participant exp as `baseExp` and the summed base stats as
    -- `baseStats`, plus a loser sitting at the engine's own divisor as its
    -- level.  Experience.apply is `floor(floor(baseExp / split) * level /
    -- divisor)`, so at level == divisor it collapses to exactly
    -- `floor(pool / split)`.  The trainer/traded multipliers stay OUT of the
    -- pool -- this arm's own applyShare re-applies them per recipient, exactly
    -- as it does for a single faint.  Returns nil (the caller falls back to
    -- one award per loser) when no loser has a def.
    N.expBatch = function(battle, losers)
      local data = battle and battle.data
      if type(losers) ~= "table" or type(data) ~= "table"
          or type(data.pokemon) ~= "table" then return nil end
      local consts = data.constants
      local divisor = (consts and consts.exp and consts.exp.divisor) or 7
      local exp, stats, count = 0, {}, 0
      for _, loser in ipairs(losers) do
        local def = loser and data.pokemon[loser.species]
        if def then
          exp = exp + Experience.gainFor(def, loser.level or 1, false, 1,
            false, consts)
          for key, value in pairs(def.baseStats or {}) do
            stats[key] = (stats[key] or 0) + (tonumber(value) or 0)
          end
          count = count + 1
        end
      end
      if count == 0 then return nil end
      -- Every Stats.ORDER key has to be present: Experience.apply divides the
      -- block without a nil guard.
      if Stats and Stats.ORDER then
        for _, key in ipairs(Stats.ORDER) do stats[key] = stats[key] or 0 end
      end
      local id = "__g9_exp_batch__"
      return {
        id = id,
        def = {
          id = id, name = "EXP BATCH", baseExp = exp,
          baseStats = stats, learnset = {},
        },
        loser = { species = id, level = divisor },
      }
    end

    -- THE AFTER-BATTLE EVOLUTION SWEEP -- the Gen 1 half.  The native screen
    -- runs `require("src.pokemon.Evolution").checkParty(game, onDone,
    -- self.leveledUp)` from BattleState:finish, before EndOfBattle hands the
    -- map back (end_of_battle.asm:42-45).  A scene-drawn Gen 1 battle never
    -- reaches that finish() -- finishTurn in battle_screen.lua is what decides
    -- the outcome -- so the sweep never ran and nothing could evolve.  This
    -- closes that gap; the Gen 2 half is the same-named function in the Gen 2
    -- arm above.
    --
    -- `battle.g9LeveledUp` is the mon-keyed set this arm's own applyShare fills
    -- from Experience.apply's returned level list, so the gate is the cart's own
    -- "only a mon that gained a level during the fight is offered an
    -- evolution".
    --
    -- checkParty owns the whole movie (it pushes the native EvolutionState
    -- screens and applies the change), so nothing is driven here -- and because
    -- it calls onDone synchronously when nothing is pending, the caller's exit
    -- is deliberately idempotent (see battle_screen.lua's beginAfterBattleExit)
    -- so that synchronous call and a `return true` cannot double-exit.
    N.runAfterBattleEvolutions = function(screen, onDone)
      local Evolution = tryRequire("src.pokemon.Evolution")
      if not (Evolution and type(Evolution.checkParty) == "function") then
        return false
      end
      local battle = screen.battle
      local leveled = battle and battle.g9LeveledUp
      if type(leveled) ~= "table" or not next(leveled) then return false end
      local ok, err = pcall(Evolution.checkParty, screen.game, onDone, leveled)
      if not ok then
        mod.log:warn("g9_Battle_Scene: after-battle evolution failed: %s",
          tostring(err))
        return false
      end
      return true
    end

    -- Gen 1 has no Pokerus and no berry juice, so the after-battle save beat is
    -- a no-op here.  Defined anyway so battle_screen.lua never branches on
    -- generation (the same contract every other N.* seam keeps).
    N.afterBattleSaveEffects = function() end

    -- Prize money for beating a trainer.  Gen 1's own routine, the one
    -- BattleState:enemyMonFainted runs: `local prize = (self.trainer.baseMoney
    -- or 0) * self.enemy.mon.level; self.game.save.money = self.game.save.money
    -- + prize`.  No quarter split and no Bank of Mom -- those are Gen 2's
    -- WinTrainerBattle, not Gen 1's -- and the level is wCurPartyLevel, the
    -- LAST row of the roster, which is the mon whose faint ended the fight
    -- (the roster is sent out in order).  Signed exactly like the Gen 2 arm so
    -- battle_screen.lua never branches on generation.
    N.awardTrainerPrize = function(battle, save, trainer)
      if not (battle and save) then return nil end
      trainer = trainer or battle.trainer
      if type(trainer) ~= "table" then return nil end
      local party = battle.enemyParty or {}
      local last = party[#party]
      local level = (last and last.level) or 0
      local amount = math.floor(tonumber(trainer.baseMoney) or 0) * level
      if amount <= 0 then return nil end
      save.money = (save.money or 0) + amount
      local name = (save.player and save.player.name) or "PLAYER"
      return {
        amount = amount,
        text = require("src.core.Strings")("%s got \xc2\xa5%d for winning!",
          name, amount),
      }
    end

    N.statusLabel = function(mon, data)
      if not (mon and mon.status) then return nil end
      -- A build carrying the Gen 2 status table uses its authored HUD label
      -- -- the same record the Gen 2 arm's statusTag reads -- so Gen 1 shows
      -- the Gen 2 text; otherwise the native Gen 1 registry's own label.
      local authored = data and data.gen2Statuses
        and data.gen2Statuses[mon.status]
      if authored then
        if authored.substatus then return nil end
        return authored.hudLabel or authored.label
      end
      return Status.hudLabelFor(data and data.statuses, mon.status)
    end

    -- -- trainer intro art ---------------------------------------------
    -- With the Gen 2 assets present: the Gen 2 back-pic, off
    -- gen2MenuGfx.battleHud and GBC-coloured through the Gen 2 palette rows,
    -- resolved exactly as the Gen 2 arm resolves it.  Otherwise Gen 1's own
    -- back-pic, off the shared Sprites.playerPath seam (the real native
    -- source: field.playerPics, with the catch-tutorial/oak fallbacks), which
    -- already raises player.sprite exactly once -- drawn raw.
    N.playerBackArt = function(data, save, battle)
      local hud = data and data.gen2MenuGfx and data.gen2MenuGfx.battleHud
      local palettes = data and data.gen2Palettes
      local female = save and save.player
        and save.player.gender == "female"
      local path = hud and hud.playerBack
      if hud and hud.playerBackFemale and female then
        path = hud.playerBackFemale
      end
      if path then
        local trueColor
        path, trueColor = N.Sprites.playerPic(path, {
          side = "back", kind = "battle", battle = battle, data = data,
        })
        local colors = N.Palettes.trainerColors(palettes,
          female and "FALKNER" or "PLAYER")
          or N.Palettes.trainerColors(palettes, "PLAYER")
        return path, trueColor, colors
      end
      local fallback, rawTrue = N.Sprites.playerPath(data, "back", {
        kind = "battle", battle = battle, data = data,
      })
      return fallback, rawTrue, nil
    end

    -- Trainer class front-pic.  With the Gen 2 assets present: the Gen 2
    -- lookup the Gen 2 arm runs -- a trainers-registry `pic`/`trueColor` wins
    -- over the extracted menu_gfx sheet, GBC-coloured through the Gen 2
    -- palette rows.  Otherwise the native Gen 1 lookup, drawn raw (Gen 1's SGB
    -- colouring is a native-screen pipeline this scene does not reproduce).
    N.enemyTrainerArt = function(data, trainerData)
      local classId = trainerData.classId or trainerData.class
      local classes = data and data.gen2Trainers
        and data.gen2Trainers.classes
      local classDef = classes and classes[classId]
      local hud = data and data.gen2MenuGfx and data.gen2MenuGfx.battleHud
      local path = (classDef and classDef.pic)
        or (hud and hud.trainerPics and hud.trainerPics[classId])
      if path then
        local trueColor = (classDef and classDef.trueColor) and true or false
        return path, trueColor, N.Palettes.trainerColors(
          data and data.gen2Palettes, classId)
      end
      local trainerRec = data and data.trainers and data.trainers[classId]
      local gen1Path = BattleState.trainerPicPath(data, trainerRec, classId,
        trainerData.partyIndex or 1)
      return gen1Path, BattleState.trainerTrueColor(data, trainerRec), nil
    end

    -- The selected catch formula (see the CATCH RATE block above).  Gen 1 has
    -- no captured tail here: the scene owns the party/box filing, and
    -- BattleState:caught does not exist -- the native store path is the
    -- screen's own storeCaughtMon, which this scene replaces.
    N.catchAttempt = function(opts)
      opts = opts or {}
      local caught, shakes, a, chance = N.runCatch(opts)
      if N.ballThrownWanted() then
        N.emitBallThrown({
          battle = opts.battle, ball = opts.ball or "POKE_BALL",
          caught = caught, shakes = shakes, rate = a, chance = chance,
          mon = opts.mon, species = opts.species,
        })
      end
      return caught, shakes, a, chance
    end

    N.depositCatch = function(save, mon)
      local Boxes = require("src.pokemon.Boxes")
      local index = Boxes.deposit(save, mon)
      if index then return true, " It was sent to the PC." end
      return false
    end

    -- -- Gen 1 end of turn --------------------------------------------
    -- The scene drives BattleState:performMove per action and never runs the
    -- native per-action turn engine (BattleState:executeAction), so the
    -- end-of-round half of a Gen 1 turn had no caller at all: the modern-
    -- ruleset residual sweep, the trapping-counter release (CheckNumAttacks-
    -- Left), the residualDone/skipMove reset, and the battle.turn_ended event
    -- every turn-tick listener waits on.  This runs the non-presentation half
    -- of BattleState:endOfTurn once per turn, whichever path resolved the
    -- moves; it queues its status text with sayNext, so the drain right after
    -- turns those rows into events.  (The Gen-1-timing per-move residual runs
    -- inside state:useMove instead, exactly as residualAfterMove rulesets
    -- expect, and endOfTurn then skips its own sweep.)
    N.applyGen1EndOfTurn = function(battle)
      if type(BattleState.endOfTurn) ~= "function" then return end
      local ok = pcall(BattleState.endOfTurn, battle)
      if not ok then return end
      if type(battle.drainNativeMove) == "function" then
        battle:drainNativeMove(nil)
      end
    end

    -- -- turn resolution ----------------------------------------------
    -- Natively ordered (real TurnOrder priority/speed) and natively executed
    -- (BattleState:performMove).  An engine mod that grows a Gen 1 arm takes
    -- over by exporting resolveTurnActionsForGen1.
    N.resolveTurn = function(g9dex, battle, actingBattlers)
      -- Head of every Gen 1 turn (core.asm MainInBattleLoop ->
      -- BattleState:clearTurnFlinches, BattleState.lua:2096): a flinch set by
      -- a SLOWER attacker after its victim already moved must not survive into
      -- the next turn, or it eats a move it never earned. Runs before either
      -- resolution path so both share it; battlers kept recharging (or mid
      -- Rage) keep theirs, exactly as the native helper does.
      if type(BattleState.clearTurnFlinches) == "function" then
        pcall(BattleState.clearTurnFlinches, battle)
      end
      local eng = g9dex and g9dex.exports
      local handled = false
      if eng and type(eng.resolveTurnActionsForGen1) == "function" then
        handled = pcall(eng.resolveTurnActionsForGen1, battle, actingBattlers)
      end
      if handled then
        N.applyGen1EndOfTurn(battle)
        return battle:takeEvents()
      end

      local byMon = battle.battlersByMon
      local order = {}
      for _, action in ipairs(actingBattlers) do order[#order + 1] = action end

      local function moveDef(action)
        local user = byMon[action.mon]
        if not user then return nil end
        return battle:moveDef({ id = action.move })
      end
      -- Insertion sort -- a turn is a handful of actions, and this keeps the
      -- native firstMover comparison in exactly one place.
      for i = 2, #order do
        local j = i
        while j > 1 do
          local a, b = order[j], order[j - 1]
          local aUser, bUser = byMon[a.mon], byMon[b.mon]
          local aFirst = true
          if aUser and bUser then
            aFirst = TurnOrder.firstMover(aUser, moveDef(a), bUser, moveDef(b),
              battle.rng, false)
          end
          if aFirst then break end
          order[j], order[j - 1] = order[j - 1], order[j]
          j = j - 1
        end
      end

      local function aliveOpponent(mon)
        local side = battle.sideByMon[mon]
        for _, other in ipairs(battle.rosterMons) do
          if battle.sideByMon[other] ~= side and other ~= mon
             and (other.hp or 0) > 0 then
            return other
          end
        end
        return nil
      end

      for _, action in ipairs(order) do
        local actor = byMon[action.mon]
        if actor and (action.mon.hp or 0) > 0 then
          local target = action.target
          if not target or (target.hp or 0) <= 0 then
            target = aliveOpponent(action.mon)
          end
          if target and (target.hp or 0) > 0 then
            battle:useMove(action.mon, target, action.move)
          end
        end
      end
      N.applyGen1EndOfTurn(battle)
      return battle:takeEvents()
    end

    -- -- stepwise turn resolution (Gen 1) ------------------------------
    -- The scene displays a turn one visible beat at a time, so for Gen 1 it
    -- asks for the turn ONE ACTION at a time instead of all at once: that is
    -- what keeps a Transform's sprite/stat exchange landing AFTER the
    -- higher-priority move whose announcement is still on screen, rather
    -- than every action's state landing up front. (On Gen 2 -- and against
    -- an engine with no stepwise arm -- N.beginTurn below is simply undefined
    -- and the scene falls back to the whole-turn N.resolveTurn above,
    -- unchanged.)
    --
    -- N.beginTurn computes this turn's real order and returns true when the
    -- engine supports stepping; false tells the caller to fall back.
    N.beginTurn = function(g9dex, battle, actingBattlers)
      if not battle then return false end
      local eng = g9dex and g9dex.exports
      if not (eng and type(eng.beginTurnActionsForGen1) == "function") then
        -- No stepwise arm: return false BEFORE the turn-head reset, so the
        -- fallback batch N.resolveTurn below performs it exactly once.
        return false
      end
      -- Head of every Gen 1 turn -- the same pre-resolution call N.resolveTurn
      -- makes (see its note): a flinch set by a SLOWER attacker after its
      -- victim already moved must not survive into the next turn.
      if type(BattleState.clearTurnFlinches) == "function" then
        pcall(BattleState.clearTurnFlinches, battle)
      end
      local ok = pcall(eng.beginTurnActionsForGen1, battle, actingBattlers)
      return ok and true or false
    end

    -- Resolves ONE actor of the stepwise turn begun above. Returns
    -- (events, done): `events` is everything that action emitted, drained
    -- here so nothing is lost between this call and the next, and `done` is
    -- true once the order is exhausted -- at which point end-of-turn runs and
    -- its own status text is appended to the same batch. The caller then
    -- finishes the turn exactly as the batch path does.
    N.resolveNextAction = function(g9dex, battle)
      local eng = g9dex and g9dex.exports
      if not (eng and type(eng.resolveNextActionForGen1) == "function") then
        return battle:takeEvents(), true
      end
      local ok, resolved = pcall(eng.resolveNextActionForGen1, battle)
      local events = battle:takeEvents()
      if not ok or not resolved then
        N.applyGen1EndOfTurn(battle)
        for _, e in ipairs(battle:takeEvents()) do events[#events + 1] = e end
        return events, true
      end
      return events, false
    end

    -- Gen 1's battle bag is the cart's OWN bag -- the engine's BagMenu --
    -- not a ball-only list.  BagMenu lists every item, opens the real party
    -- picker for a targeted one (item_effects.asm's ItemUseMedicine), runs
    -- the effect through src.inventory.ItemEffects, animates the party HP
    -- fill and prints every message itself.  When it is done it hands the
    -- spent turn back through `battle:itemUsed(messages, opts)` for a
    -- non-ball item and `battle:throwBall(id)` for a ball.
    --
    -- Those two are the NATIVE BattleState methods, and they would run the
    -- native battle loop against the native battle object -- a different
    -- battle than the one this screen is playing.  So they are shadowed on
    -- THIS scene's own model instance and routed back into the screen,
    -- exactly the instance-only override the model already uses for
    -- state:useMove / state:statusGate (see the note by those).  Everything
    -- the player sees or reads stays the cart's own.
    N.openBag = function(screen)
      local Screens = require("src.ui.Screens")
      local battle = screen.battle
      if battle then
        battle.itemUsed = function(_, messages, opts)
          screen:onBagItemUsed(messages, opts)
        end
        battle.throwBall = function(_, id)
          -- BagMenu runs consume() on the ball BEFORE it calls this, so the
          -- copy already left the bag; spend no second one.
          screen:throwBall(id, true)
        end
      end
      Screens.push(screen.game, "BagMenu", {
        battle = battle,
        onCancel = function()
          screen.suppressInputFrame = true
          screen.phase = "actionMenu"
        end,
      })
    end
  end

  mod.exports.native = N
  mod.log:info("g9_Battle_Scene: native backend ready (gen %d)", N.gen)
end
