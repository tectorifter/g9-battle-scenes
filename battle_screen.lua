-- Phase 4 battle scene: real move/target/catch flow (combat.lua/
-- catch.lua) plus real battle sprites -- enemies show their real front
-- pic, the player's own two mons show their real back pic (data.pokemon
-- [species].spriteFront/spriteBack -- confirmed real fields, Schemas.lua
-- R.pokemon/R.forms), the same convention every native battle screen
-- uses, loaded/cached the same defensive way this codebase's own
-- overworld sprite mods do (pcall'd love.graphics.newImage, scaled to
-- fit rather than assumed to already be a fixed size, silently falls
-- back to no image rather than crashing the whole scene over one
-- missing file). Still not a finished battle system -- see combat.lua/
-- catch.lua's own headers for the exact remaining scope (no status/
-- stat-stage moves, static turn order, POKE_BALL-only, no PC box).
--
-- Layout: vanilla's own classic single-battle HUD -- enemy readout
-- upper-left, enemy sprite upper-right-ish, player sprite lower-left,
-- player readout lower-right -- doubled for two battlers per side per
-- explicit user spec (a hand-drawn ASCII layout): each row clusters its
-- two GUI boxes together on one side and its two sprites together on
-- the other, MIRRORED between the enemy row and the player row, so the
-- two GUI clusters sit diagonally opposite each other and so do the two
-- sprite clusters -- rather than each battler's own sprite+box paired
-- side by side (the previous pass), which pushed sprites toward
-- opposite screen edges instead of grouping the team together the way
-- a real double battle reads. No title text (not vanilla, wastes a row
-- the layout needs).
--
-- Bottom is a wide message/move-select area (F) beside a narrower
-- FIGHT/BAG/PKMN/RUN menu (E) -- vanilla's own text-box-plus-menu split,
-- not the single full-width box the earlier passes used.
--
-- Design field is 320x180 (40x22.5 tiles, 16:9); the scene draws it onto a
-- 960x540 CANVAS (the design field at x3 -- see DS).
--
-- How that canvas reaches the window is the ONE thing the two generations do
-- differently, and both paths are owned here:
--
--   * Gen 2 -- Game2's renderer resolves the scene through
--     drawsWidescreen/drawWidescreen and blits it window-filling (unchanged;
--     the Gen 2 path never touches any of the Gen 1 members below).
--   * Gen 1 -- src/core/Game.lua has no drawWidescreen path at all.  It asks
--     each state for the UI SURFACE it wants (BattleState:uiSize ->
--     Renderer:setUISize) and then calls state:draw() into it, so the scene
--     answers that same wide-battle contract and Screen:draw renders the
--     960x540 canvas 1:1 into the surface the engine allocated.  See the
--     WIDESCREEN CONTRACT block by Screen:drawWidescreen.
return function(mod)
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")
  -- The real, unprefixed, engine-level event bus -- Runtime.emit, not
  -- mod.events:emit (which is prefix-gated to "mod.<this mod's own
  -- id>." and would reject a bare "battle.turn_started" outright).
  -- Confirmed shared with mod.events' own bus via Runtime.install
  -- (src/mods/Runtime.lua:36-37) -- native's own turn loop raises
  -- "battle.turn_started" exactly this way, and any mod listening via
  -- mod.events:on (the GLOBAL listen side) hears it regardless of which
  -- side emitted it. Used in Screen:advanceResolving so mods that key
  -- real per-turn work off this event (battle_forms's own gimmick
  -- activation, this session; potentially others) keep working correctly
  -- against a battle this mod drives, not just a native-turn-loop one.
  local Runtime = require("src.mods.Runtime")
  -- The generation backend (native.lua, loaded before this file).  Every
  -- engine surface this scene touches that differs between Red/Blue/Yellow
  -- and Gold/Silver is reached through it, so the code below is one scene for
  -- both games.  On Gen 2 each of these locals is the exact module it used to
  -- be; on Gen 1 it is a Gen 1 adapter over the game's own primitives -- see
  -- native.lua's header for the full split and for the combat-authority rule.
  local N = assert(mod.exports.native,
    "g9-Battle-Scene: native.lua must load before battle_screen.lua")
  -- Real native Battle, constructed here so battle:useMove (driven
  -- through g9-battle-engine's mod.exports.resolveTurnActions) has
  -- the type chart/stats/RNG/event-queue machinery it needs -- see
  -- pushDoubleBattleScreen's own comment for why battler roster/identity
  -- still stays this mod's own arrays, never battle.player/battle.enemy.
  -- (Gen 1: a BattleState instance used purely as a model.)
  local Battle = N.Battle
  -- Real catch formula/rate, replacing g2-Battle-Scene's own catch.lua
  -- (dropped entirely in this fork -- see manifest.json's description).
  -- (Gen 1: the native src/battle/Catching.lua algorithm.)
  local Catching = N.Catching
  -- Genuinely pure (data in, data out, no Battle-instance dependency) --
  -- confirmed by direct source read, the same standard this mod already
  -- held Damage.calc/Catching.attempt to. HpBar.pixels/.palette/.draw
  -- reproduce the cart's own ComputeHPBarPixels/GetHPPal exactly (the
  -- 48px-wide bar, its green/yellow/red thresholds, a live mon never
  -- showing a fully-empty bar), so this mod's bar reads identically to
  -- every native HP bar in the game rather than a reinvented one.
  -- (Pure -- the same module serves both generations.)
  local HpBar = N.HpBar
  -- The real move-animation engine, Gen 2's own -- separate from Gen 1's
  -- (src/battle/AnimPlayer.lua) and, confirmed by direct source read,
  -- NOT coupled to the native single-battle BattleState class at all:
  -- AnimRunner.new/:start/:step just needs data/constants/hooks (its own
  -- header says "Love-free"), and BattleAnimView:drawObjects(runner,
  -- battle) is the only half that touches love.graphics. The reference
  -- wiring this mirrors is src/ui/gen2/BattleState.lua:1064-1151
  -- (startAnim/animForMove).  Gen 2 drives AnimRunner/BattleAnimView.
  --
  -- GEN 1 DOES HAVE AN EQUIVALENT -- its own src/battle/AnimPlayer.lua,
  -- which the cart's own BattleState drives (src/battle/BattleState.lua:
  -- 1399-1405).  It is a DIFFERENT module with a different data contract
  -- (battle_anims moveAnims rows instead of Gen 2's animation scripts),
  -- so it is not a drop-in substitute for AnimRunner -- but it IS the
  -- native Gen 1 engine, and the scene arms it whenever the Gen 2 pair is
  -- absent (see the GEN 1'S OWN ANIMATION ARM block below).  Both are nil
  -- only on a build missing that module AND the Gen 2 ones, where every
  -- animation call site still degrades to "no animation".
  local AnimRunner = N.AnimRunner
  local BattleAnimView = N.BattleAnimView
  -- Gen 1's own battle-animation player (src/battle/AnimPlayer.lua), the
  -- native engine its BattleState drives.  Nil unless the module resolves;
  -- the Gen 1 arm below treats that as "no animation", never a crash.
  local AnimPlayer = N.AnimPlayer
  -- Both needed to draw a move animation's OBJ layer with the real
  -- attacker/target position remap (Screen:drawMoveAnimObjects) instead
  -- of BattleAnimView:drawObjects' own vanilla-fixed coordinates -- same
  -- require paths BattleAnimView.lua itself uses.
  local bit = require("bit")
  local GbcPalette = require("src.render.GbcPalette")
  -- The cart's own HUD tiles -- the "HP:" badge, the bar's six fill cells and
  -- its end cap, the <LV> level glyph and the exp bar -- drawn from the same
  -- sheets/palettes the native battle screen loads, so this mod's readout is
  -- the game's own art instead of a hand-drawn approximation. See BattleHud's
  -- own header for which VRAM slot holds what.  (Gen 1: a HudTiles-backed
  -- adapter with the same interface -- see native.lua.)
  local BattleHud = N.BattleHud
  -- Mon's exp-curve helpers, for the exp bar's fill fraction -- the native
  -- number is computed off the same growth records Mon.gainExperience used
  -- (see expFraction below, mirroring BattleState:expPixels).
  local Mon = N.Mon
  -- Strings resolves a status record's label marker into the text the native
  -- HUD prints (Battle.STATUSES stores plain strings, but a mod may register
  -- its own), so a statused mon's tag reads exactly as the cart's does.
  local Strings = require("src.core.Strings")
  -- The GBC palette tables the trainer pics are COLOURED from. A trainer pic
  -- is a 4-shade (grayscale) sheet like every other imported 2bpp image, so
  -- the class's own TrainerPalettes row has to be substituted in at draw time
  -- -- native does exactly this in BattleState:drawPic (Palettes.trainerColors
  -- + GbcPalette.with), and drawing the sheet raw is what left the trainer
  -- pics grey. See drawRawImage.  (Gen 1: no palette row -- its SGB colouring
  -- is a native-screen pipeline; the sheets draw raw.)
  local Palettes = N.Palettes
  -- The player.sprite seam (Sprites.playerPic), the same hook Gen 1 raises
  -- for its own back-pic. Native raises it for the player's Gen 2 back-pic
  -- too, so a mod's swapped picture -- and its trueColor answer, which says
  -- the art is already full-colour and must NOT be remapped -- reaches the
  -- draw exactly as it does on the native screen.  The module is shared.
  local Sprites = require("src.pokemon.Sprites")

  ------------------------------------------------------------------
  -- Real N-way adjacency, the one contribution combat/
  -- MULTI_BATTLE_HOOKS.md's own doc says a battle-scene mod needs to make
  -- for a spread move (Earthquake/Surf/Muddy Water) or an ally-scope
  -- ability/switch-in trigger (Intimidate, Hospitality) to see the real
  -- roster instead of degrading to the native two-battler fallback.
  --
  -- The grid this answers from already exists as real, working state --
  -- self.enemyBattlers[i]/self.playerBattlers[i], explicitly built
  -- N-agnostic ("Looped, not hardcoded to exactly 2", Screen.new's own
  -- comment) and already index-aligned with each side's own grid slot
  -- column (sideColumns) -- this wrap is the
  -- missing piece connecting that real grid to g9-battle-engine's
  -- own targeting seam, not a new grid built from scratch.
  --
  -- lastScreen: a single reference, not a registry -- this engine only
  -- ever runs one battle at a time (confirmed throughout this mod: one
  -- Screen instance pushed per pushDoubleBattleScreen call, no concurrent-
  -- battle concept anywhere). Set at push time below; a stale reference
  -- from a battle that already ended is harmless -- the `screen.battle ==
  -- battle` check below fails and this falls through to the real fallback
  -- the hook already has (the native two-battler case), never a wrong
  -- answer.
  local lastScreen = nil

  local function battlerArraysFor(screen, mon)
    for i, b in ipairs(screen.playerBattlers) do
      if b.mon == mon then return screen.playerBattlers, screen.enemyBattlers, i end
    end
    for i, b in ipairs(screen.enemyBattlers) do
      if b.mon == mon then return screen.enemyBattlers, screen.playerBattlers, i end
    end
    return nil
  end

  mod.hooks:wrap("g9.request_adjacency", function(nextFn, battle, caster, moveId)
    local screen = lastScreen
    if not (screen and screen.battle == battle) then
      return nextFn(battle, caster, moveId)
    end
    local ownArr, oppArr, casterIndex = battlerArraysFor(screen, caster)
    if not ownArr then return nextFn(battle, caster, moveId) end
    -- combat.isAlive looked up lazily (not hoisted): this hook is
    -- registered at install time, well before mod.exports.combat exists
    -- (combat.lua's own install runs separately) -- by the time a real
    -- battle ever reaches this closure, every sibling file has finished
    -- loading, the same lazy-lookup convention g9-battle-engine's
    -- own code uses throughout for exactly this reason.
    local combat = mod.exports.combat
    local isAlive = combat and combat.isAlive

    -- Boss-fight rule, explicit user directive (2026-08-28), matching
    -- combat/MULTI_BATTLE_HOOKS.md's own "Boss-fight rule" section
    -- verbatim: "the allies a wrapped handler reports should be the FULL
    -- ally roster regardless of real proximity ('adjacent allies = all
    -- allies'), independent of which boss-fight protections are active."
    -- Checked generically -- battle.bossFightFlags being a non-empty
    -- table means SOME boss-fight protection is active, regardless of
    -- which specific one -- rather than one named flag, matching that
    -- doc's own "independent of which... are active" wording exactly.
    --
    -- Structured as its own explicit branch on purpose, not folded into
    -- the loop below via an extra condition: this file has NO real
    -- positional/slot-adjacency restriction anywhere today (every ally
    -- already counts as adjacent regardless of real proximity, for every
    -- fight), so this branch is functionally identical to the plain one
    -- right now -- but a future real triples adjacency feature (e.g.
    -- restricting a corner slot's own spread hit from reaching the far
    -- corner) would only ever be added to the ELSE branch, never here,
    -- so the boss-fight guarantee stays structurally enforced rather
    -- than accidentally preserved by the absence of a feature that
    -- doesn't exist yet.
    local isBossFight = battle.bossFightFlags ~= nil and next(battle.bossFightFlags) ~= nil
    local allies, enemies = {}, {}
    if isBossFight then
      for i, b in ipairs(ownArr) do
        if i ~= casterIndex and (not isAlive or isAlive(b)) then
          allies[#allies + 1] = b.mon
        end
      end
    else
      -- No real positional restriction exists yet -- see the boss-fight
      -- branch's own comment above. When one is built, it belongs here,
      -- never in the isBossFight branch.
      for i, b in ipairs(ownArr) do
        if i ~= casterIndex and (not isAlive or isAlive(b)) then
          allies[#allies + 1] = b.mon
        end
      end
    end
    for _, b in ipairs(oppArr) do
      if not isAlive or isAlive(b) then
        enemies[#enemies + 1] = b.mon
      end
    end
    return { allies = allies, enemies = enemies }
  end, 0)

  -- Clears the mon.multiSide tag this mod's own combat.lua sets
  -- (Combat.newBattler) once the battle itself ends -- combat-only state,
  -- matching every other per-mon combat-only field this project's own
  -- ability/status system already clears the same way. mod.events:on is
  -- the real GLOBAL listen side (this file's own header, above) -- fires
  -- regardless of which side emitted battle.ended, native or this mod's
  -- own driven battle alike.
  mod.events:on("battle.ended", function(ev)
    local battle = ev and ev.battle
    local screen = lastScreen
    if not (battle and screen and screen.battle == battle) then return end
    for _, b in ipairs(screen.playerBattlers) do
      if b.mon then b.mon.multiSide = nil end
    end
    for _, b in ipairs(screen.enemyBattlers) do
      if b.mon then b.mon.multiSide = nil end
    end
  end)

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true

  -- The DESIGN space this whole file's geometry is authored in: 320x180
  -- (40x22.5 tiles). It is NOT the render surface any more -- see DS
  -- below. Every tile/px constant, every slot rect and every font/border
  -- draw stays in these units, so the layout is unchanged.
  local VW, VH = 320, 180
  -- Design -> CANVAS scale. The coordinate space this scene actually draws
  -- into is CANVAS_W x CANVAS_H = 960x540 (16:9) -- the design field at x3.
  -- Everything authored in VWxVH is drawn under one scale(DS) transform,
  -- so the layout keeps its exact shape and proportions, but the SURFACE
  -- it lands on is 960x540, i.e. half of 1080p.
  -- Why 960x540: it is a whole-number multiple of the design field (x3)
  -- AND a clean sub-multiple of every standard display -- x1 = 960x540,
  -- x2 = 1920x1080, x4 = 3840x2160 (4K), x8 = 7680x4320 (8K) -- so on
  -- those sizes the window-fill scale (see fitScale) lands on a perfect
  -- whole number and stays crisp. On any OTHER size it now fills at
  -- whatever fractional ratio the display allows (user's rule, round
  -- sixty-nine: filling the window beats integer-letterboxing, because
  -- the letters floated the whole scene -- bottom GUI included -- away
  -- from the real screen edge). It also lets the sprite pack's own art
  -- reach the screen at its real resolution: a sprite is baked at the
  -- CANVAS scale (drawSprite's ctx.scale) and blitted 1:1, instead of
  -- being baked small and then magnified by the fit transform.
  local DS = 3
  local CANVAS_W, CANVAS_H = VW * DS, VH * DS -- 960x540
  -- Intro send-out pacing. Player mons and every trainer-battle mon
  -- (enemy and player) are THROWN from a pokeball: the ball arcs from
  -- the trainer's side to the mon's platform, lands with a white poof,
  -- and the mon materializes there. The ball is the game's own art (the
  -- BATTLE_ANIM_OBJ_POKE_BALL frameset off the same battle_anims cache
  -- the move animations use -- see drawNativeBall), thrown along this
  -- screen's own per-slot arc rather than vanilla's fixed coordinate; the
  -- primitive drawPokeball is only the fallback. Only a WILD
  -- mon gets the vanilla slide-in: it drops from the top of the screen
  -- onto its own platform.
  local BALL_FLIGHT = 0.45    -- ball in the air
  local BALL_POOF = 0.18      -- landing flash
  local BALL_APPEAR = 0.3     -- mon materializing at the landing spot
  local BALL_THROW_TOTAL = BALL_FLIGHT + BALL_POOF + BALL_APPEAR
  local BALL_RADIUS = 6
  -- Ball arc: throw origin (trainer's hand, just off that side's edge),
  -- arc apex, then the mon's platform (computed per-slot at draw time).
  -- Player throws from off the left edge up-forward toward center; the
  -- enemy throws from off the right edge (the direction its trainer pic
  -- slid off).
  local BALL_PLAYER_OX, BALL_PLAYER_OY = 0, 86
  local BALL_PLAYER_AX, BALL_PLAYER_AY = 96, 18
  local BALL_ENEMY_OX, BALL_ENEMY_OY = 330, 10
  local BALL_ENEMY_AX, BALL_ENEMY_AY = 292, 2
  -- A wild-encounter mon has no trainer to throw its ball, so it appears
  -- IN PLACE: drawn at its final sprite position from the very first frame,
  -- fading from completely invisible (alpha 0) to completely visible
  -- (alpha 1) over this many seconds -- the user's rule (round sixty-three).
  -- This replaced a 0.5s drop-in that slid the mon down from the top of the
  -- screen; its position, size and reveal gating are otherwise unchanged.
  local WILD_FADE_DURATION = 1.0
  -- Trainer/intro pic slides, ported from the native screen's own frame
  -- counts (src/ui/gen2/BattleState.lua:124-129): the enemy trainer's
  -- class front-pic slides OFF to the right in TRAINER_SLIDE_FRAMES=16
  -- frames (8 steps x 2 frames), the player trainer's back-pic slides OFF
  -- to the left in BACKPIC_SLIDE_FRAMES=18 (9 steps x 2). Duration here
  -- is frames/60 (the native screen advances once per 60fps frame), and
  -- each step is one 8px tile.
  local TRAINER_SLIDE_STEPS = 8
  local BACKPIC_SLIDE_STEPS = 9
  local TRAINER_SLIDE_DURATION = 16 / 60
  local BACKPIC_SLIDE_DURATION = 18 / 60
  -- `time` (seconds) into a `duration`-long slide -> the cumulative 8px
  -- tile offset at that instant, matching native's per-frame step
  -- (px += floor(frameCount/2)*8). nil time (no slide) is 0.
  local function slideStepPx(time, duration, steps)
    if not time then return 0 end
    local p = math.min(1, time / duration)
    return math.floor(p * steps) * 8
  end
  -- The classic multi-target ("hits every adjacent opponent") move ids,
  -- used by Screen:isSpreadMove as the LAST-resort check when the move
  -- def carries no `target` field and the engine mod is too old to
  -- export isSpreadMove. The authoritative answer stays the engine's
  -- (national_dex target archetype); this list only keeps the picker
  -- skipped when that answer can't be asked at all. Curated to moves
  -- that are unambiguously multi-target (single-target moves like Body
  -- Slam/Hyper Voice/Sweet Kiss are deliberately absent -- wrongly
  -- listing one would silently drop the target picker).
  local SPREAD_MOVE_IDS = {
    LEER = true, GROWL = true, TAIL_WHIP = true, STRING_SHOT = true,
    POISON_GAS = true, SWEET_SCENT = true, BUBBLE = true, ICY_WIND = true,
    ROCK_SLIDE = true, RAZOR_LEAF = true, SWIFT = true, TWISTER = true,
    SURF = true, EARTHQUAKE = true, EXPLOSION = true, SELF_DESTRUCT = true,
    MUDDY_WATER = true, HEAT_WAVE = true, BLIZZARD = true, ERUPTION = true,
    WATER_SPOUT = true, DISCHARGE = true, DAZZLING_GLEAM = true,
    MORTALSPIN = true, BOOMBURST = true,
  }
  -- Lose outro: how long the faint-to-black takes to climb the whole
  -- canvas after your last mon falls (vanilla's blackout). Purely
  -- cosmetic -- the defeat box draws over it and A/B still exits.
  local OUTRO_BLACKOUT_DURATION = 1.2
  local CURSOR_CODE = 0xED
  -- Theme.cursorHollow (src/ui/Theme.lua:12, charmap.asm $EC) -- the same
  -- hollow-arrow marker the engine's own party/list reordering leaves on
  -- a picked-up row (src/ui/ListMenu.lua, src/ui/PartyMenu.lua), reused
  -- here for the same purpose on a picked-up move.
  local SWAP_MARKER_CODE = 0xEC
  -- The native refusal when a listed move has no PP left (Gen 1's
  -- _MoveNoPPText / Gen 2's BattleText_TheresNoPPLeftForThisMove). A
  -- 0-PP move is never dropped off the list; picking it prints this and
  -- returns to the list, exactly as both native move menus do.
  local MOVE_NO_PP_TEXT = "No PP left for this move!"
  -- mon.gender is "male"/"female"/"unknown" (Mon.lua's own GENDERS
  -- table). These two escapes are the exact UTF-8 bytes for MALE SIGN /
  -- FEMALE SIGN already used elsewhere in this codebase's own UI
  -- (src/ui/gen2/TradeMenu.lua) -- confirmed the font renders them as a
  -- single glyph, not reinvented as text.
  local GENDER_SYMBOL = { male = "\xe2\x99\x82", female = "\xe2\x99\x80" }

  -- BAG (throws balls, among whatever else the pack lets through) and
  -- PKMN (voluntary switch) replace the earlier CATCH-as-a-menu-item
  -- design -- a standalone CATCH button isn't how the real games work;
  -- a ball is an item you throw from the bag. Both reuse the engine's
  -- own native PackMenu/PartyMenu screens (Gen2PackMenu/Gen2PartyMenu --
  -- confirmed real, callback-driven screens, not part of the 2-battler
  -- Battle class this mod stays independent of) rather than reinventing
  -- bag/party UI.
  -- E menu item ids, fixed regardless of layout mode -- only their draw
  -- ORDER/POSITION differs between list/grid/cross. "CUSTOM"'s visible
  -- label comes from settings.lua (self.customButtonLabel, read once per
  -- battle in Screen.new); selecting it fires a hook instead of a
  -- built-in action (see Screen:chooseMenuItem).
  local MENU_LABELS = { FIGHT = "FIGHT", BAG = "BAG", PKMN = "PKMN", RUN = "RUN",
    SWITCH = "SWITCH" }

  -- Plain 2x2 grid coordinates (confirmed directly by the user: FIGHT/
  -- PKMN on top, BAG/RUN on bottom). Real row/col toggling works fine
  -- here (only 2 rows and 2 columns, so "the other one" is always
  -- unambiguous) -- no need for the explicit-cycle workaround below.
  local GRID2_ROWS = { { "FIGHT", "PKMN" }, { "BAG", "RUN" } }

  -- 3x3 slot grid for the cross layout (grid mode + a custom button
  -- set), nil = empty/skipped cell -- purely for DRAWING positions.
  local CROSS_SLOTS = {
    { "FIGHT", nil, "PKMN" },
    { nil, "CUSTOM", nil },
    { "BAG", nil, "RUN" },
  }

  -- SWITCH-ENABLED shapes, used when the battle has two or more living
  -- allies and is not a bossFight (see the layout note by the geometry
  -- constants far below). SWITCH sits directly UNDER FIGHT in both: the
  -- wide grid gains a middle row, the cross gains its empty middle-left
  -- cell -- everything else keeps its old place, CUSTOM included.
  local GRID2_ROWS_SW = { { "FIGHT", "PKMN" }, { "SWITCH", "BAG" }, { "RUN", nil } }
  local CROSS_SLOTS_SW = {
    { "FIGHT", nil, "PKMN" },
    { "SWITCH", "CUSTOM", nil },
    { "BAG", nil, "RUN" },
  }

  -- Cross NAVIGATION is two explicit cycles, not coordinate math: a
  -- single row/column step from any corner lands on a skipped cell and
  -- keeps going straight through to the OPPOSITE corner, so the center
  -- is geometrically unreachable by any raw up/down/left/right step from
  -- a corner. These exact orders were specified directly by the user,
  -- not derived from the grid layout above.
  local CROSS_RIGHT_CYCLE = { "FIGHT", "CUSTOM", "PKMN", "BAG", "RUN" }
  local CROSS_DOWN_CYCLE = { "FIGHT", "CUSTOM", "BAG", "PKMN", "RUN" }

  -- Emitted (mod.events:emit) when the custom button is chosen, kept
  -- alongside the real, direct battle_forms call below (Screen:
  -- chooseMenuItem's own "CUSTOM" branch) so any OTHER mod can still
  -- otherMod.events:on(CUSTOM_BUTTON_EVENT, fn) and react independently.
  -- Must be prefixed "mod.<this mod's own id>." -- the engine's own
  -- emit() rejects anything else, so no mod can forge another mod's
  -- event namespace. Fixed 2026-08-23: this line was copy-pasted from
  -- g2-Battle-Scene still saying "mod.g2-Battle-Scene.customButton" --
  -- under this mod's own id ("g9-Battle-Scene"), that string fails the
  -- prefix gate outright, so the emit below would have silently done
  -- nothing since the moment this mod was created.
  local CUSTOM_BUTTON_EVENT = "mod.g9-Battle-Scene.customButton"

  -- Emitted (mod.events:emit) by the FORMS bridge for each phase of a
  -- manually activated transformation, so a peer mod can follow one without
  -- reading this scene's internals: `phase` is "armed" (a FORM was confirmed
  -- and is waiting on battle.turn_started), "used" (battle_forms' own
  -- activation consumed it) or "cancelled" (the picker was backed out of, the
  -- arm was refused, or the activation was refused). Every payload carries
  -- `mon` -- the live Pokemon the FORM belongs to -- because battle_forms
  -- resolves the owner from `battle.player`, which this scene only focuses on
  -- that mon for the duration of each battle_forms call (see the GIMMICK
  -- SELECT section's own FORMS OWNER block). Also `slot`, `id`, `label`,
  -- `reason` (cancellations), `battle`, `game`, `world`. Prefixed with this
  -- mod's own id for the same reason CUSTOM_BUTTON_EVENT is.
  local FORMS_EVENT = "mod.g9-Battle-Scene.forms"

  -- Two-choice prompt: the phase this screen sits in while a question is
  -- on screen. Declared HERE, at module scope, rather than beside the
  -- prompt section itself (search "TWO-CHOICE PROMPT" below, where every
  -- function that uses it lives) for one concrete Lua reason: functions
  -- defined above that section have to name it, and a local declared
  -- after a function that names it is not captured as an upvalue at all
  -- -- the function would silently read a GLOBAL of the same name.
  --
  -- Namespaced with this mod's own id so it can never collide with one of
  -- this screen's own phase strings, including one added later. Nothing
  -- outside the prompt section should compare against it --
  -- mod.exports.battleChoiceActive is the supported query.
  --
  -- The screen a question is aimed at is `lastScreen`, declared far above
  -- with the adjacency hook that also uses it. This deliberately does not
  -- keep a second reference of its own: one battle runs at a time (that
  -- declaration's own header establishes why), so a second variable would
  -- be the same fact stored twice and free to disagree with itself.
  local PROMPT_PHASE = "g9-Battle-Scene:prompt"

  -- Plain data, read fresh once per battle (Screen.new) from this mod's
  -- own settings.lua at its root -- never cached across battles (same
  -- reasoning as layouts.lua's own loadLayoutFile: a stale positive read
  -- is a worse bug than a cheap, once-per-battle re-parse). Missing/
  -- broken file degrades to the original list layout with no custom
  -- button, never a crash.
  local function loadSettingsFile()
    local defaults = { menuLayout = "list", customButtonLabel = "" }
    local body = mod:read("settings.lua")
    if not body then return defaults end
    local chunk, err = loadstring(body, "@" .. mod.path .. "/settings.lua")
    if not chunk then
      mod.log:warn("g9_Battle_Scene: settings.lua failed to parse: %s", tostring(err))
      return defaults
    end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
      mod.log:warn("g9_Battle_Scene: settings.lua did not return a table")
      return defaults
    end
    return data
  end

  -- ------------------------------------------------------------------
  -- STANDARDIZED FIELD GEOMETRY
  -- One 16:9 field that EVERY layout preset shares -- no preset carries
  -- its own hand-tuned field positions any more. The design field is
  -- 320x180 (16:9; the old 320x160 was 2:1 and got letterboxed on a 16:9
  -- window), drawn onto a 960x540 canvas at x3 (see DS) and fit to the
  -- window by FILLING it (see fitScale). The message/menu box owns the bottom
  -- BOTTOM_H (6.5 tiles = 52 design px, y 128..180 -- flush with the
  -- field's own bottom edge), and the whole field above it (y 0..128)
  -- belongs to the sprites and HUDs.
  --
  -- The sprite GRID is eight columns (cols 1..8, left->right, i.e.
  -- a1..a4/e1..e5 by the user's own naming). Each column's centre is exactly
  -- COL_W -- the readout's own pitch -- from its neighbour, so a side's
  -- columns and its row of stat readouts share one spacing and every readout
  -- stands dead over its own mon. The two sides anchor at opposite ends:
  -- allies fill RIGHTWARD from a1 and enemies fill LEFTWARD
  -- from e6: singles -> a1 / e6, doubles -> a1,a2 / e5,e6, triples ->
  -- a1,a2,a3 / e4,e5,e6, hordes -> a2 / e2..e6, bossFight -> a1..a4 / e5.
  -- A boss enemy always takes column 5 (e5); a horde's lone ally takes
  -- column 2 (a2). See sideColumns/slotRect below. A preset no longer
  -- nudges a sprite at all.
  --
  -- ROUND EIGHTY-TWO (user-reported): the pitch used to be only 40.5px,
  -- narrower than the 56.4px readout, so the readout row had to be SPREAD
  -- wider than the sprites to keep the boxes off one another -- and its
  -- outer boxes then stopped standing over their own mons, worst in a
  -- five-mon horde. The pitch is now the readout's own (see the COL_W
  -- block below), so no spreading is needed and the GUI tracks the sprite
  -- positions exactly. The old ALLY_X_SHIFT (+50 canvas px) that used to
  -- be applied on top of the ally columns is folded into the ally anchor
  -- (ALLY_LEFT_X), so the lead ally stays exactly where it was.
  --
  -- VERTICALLY each side gets its own band: the enemy's the upper half
  -- (feet at 8 tiles = 64px), the ally's the lower half (feet on BOTTOM_Y
  -- = the text box's own top edge). The bands are disjoint, so no two
  -- sprites ever share their own ground line. Each slot is an ANCHOR the
  -- sprite stands on (its centre x, its ground line), never a box the art is
  -- folded into.
  --
  -- SIZING: every sprite is drawn at its side's own scale (SPRITE_SCALE_FRONT
  -- for enemies, SPRITE_SCALE_BACK for allies -- two INDEPENDENT multipliers,
  -- both default 1) x its OWN trimmed pixels, and the bossFight boss at
  -- SPRITE_SCALE_FRONT * BOSS_MUL (the "+0.6" applies to bosses ONLY). This
  -- is a straight multiplier, NOT a per-slot box: the slot a sprite is handed
  -- is an ANCHOR only (its centre x, its ground line), never a size to be
  -- folded into. So a Diglett stays small and a Koraidon stays huge -- the
  -- pack's own relative sizes -- and no two species are forced to the same
  -- height or width. A sheet is drawn at its FULL size x that side's scale:
  -- NO fold of any kind (round sixty-nine). A sheet taller than the field
  -- simply rises off the top of the scene and is cut by the screen edge --
  -- preserving the full size is the rule, and the edge does the cropping.
  -- (There is deliberately NO native-picture-box
  -- cap any more -- that 56px/48px fold flattened every bigger species down
  -- to the size the game's own screen would show; see the note by
  -- SPRITE_SCALE_FRONT/BACK.)
  --
  -- This replaced an earlier model that handed each sprite its slot rect as
  -- the exact pixel box to bake into, which made every species come out the
  -- SAME slot-sized square (user-reported: "sprites are being reduced to an
  -- exact same height-width").
  local ROW_H = 8
  -- GUI_TW=15 (interior (15-2)*8=104px) is sized for line 2: the native HP
  -- bar -- the cart's own "HP:" badge + six cells + end cap, 9 tiles = 72px
  -- -- the widest single element the box carries. 104px leaves that real
  -- margin and comfortably fits the 8-tile (64px) exp bar on the player's
  -- row below it.
  local GUI_TW = 15
  -- A readout is 15 tiles (120 design px) wide before BOX_SCALE -- the same
  -- width on both sides. Readouts are one box per slot in a single row now,
  -- so there is no per-side stack spacing any more (see spreadBoxCentres).
  --
  -- ROUND EIGHTY-TWO: THE SPRITE PITCH IS THE READOUT'S OWN PITCH. A readout
  -- is 56.4px wide, so two of them need 56.4 + GUI_BOX_GAP (2) = 58.4px of
  -- centre-to-centre room. The sprite grid's column pitch is EXACTLY that
  -- (COL_W below), so one readout stands dead over every mon with no
  -- spreading and no drift. Before this the pitch was only 40.5px -- far
  -- narrower than a readout -- so spreadBoxCentres had to widen the row to
  -- keep the boxes off one another, and the row's outer boxes no longer sat
  -- over their own mons (user-reported, worst in a five-mon horde where the
  -- GUI spread too wide and stopped matching the sprite positions). The
  -- eight-column a1..a8/e1..e5 scheme is unchanged; only its pitch and its
  -- two anchors moved. HUD_W is the readout's own drawn width
  -- (GUI_TW * 8 * BOX_SCALE = 56.4), kept here so the sprite grid and the
  -- readout row can never drift apart.
  local HUD_W = 56.4
  -- The pitch: a readout plus the sliver its row leaves to its neighbour.
  -- Written as HUD_W + 2 rather than GUI_BOX_W + GUI_BOX_GAP (the same
  -- number, declared further down) because every sprite/slot helper below
  -- reads it, and those are defined before the readout constants.
  local COL_W = HUD_W + 2
  -- The enemy team's anchor column: e6 (col 6), the rightmost column an
  -- enemy ever occupies. The five-mon horde fills columns 2..6, so its
  -- readout row is 4*COL_W + HUD_W = 290px wide; giving the 320px canvas the
  -- SAME margin at each end puts e6 at 276.8px -- the rightmost the enemy
  -- team can stand while every readout still lands inside the canvas. Every
  -- smaller enemy count keeps e6 and steps leftward (see sideColumns), so
  -- the team stays right-aligned.
  local ENEMY_RIGHT_X = VW - (VW - 4 * COL_W - HUD_W) / 2 - HUD_W / 2
  -- The ally team's anchor column: a1 (col 1). Held at the exact spot the old
  -- grid put the lead ally (its old a1 centre plus the ALLY_X_SHIFT that used
  -- to be applied on top of it), so a lone ally does not move -- a fuller
  -- team now just spreads rightward on the same pitch its readouts use.
  local ALLY_LEFT_X = 35
  -- The sprite field: the canvas itself. Only ever used as the OUTER clamp
  -- for a slot's own hit-box width (a lone mon's slot takes the free
  -- half-field on its empty side); the outer columns of the eight-column
  -- scheme sit past it and are simply never occupied by a shipped preset.
  local SPRITE_FIELD_L = 0
  local SPRITE_FIELD_R = VW

  -- The field's DEFAULT sprite scale, PER SIDE: enemies use FRONT, allies
  -- use BACK, so the two teams' sizes are controlled INDEPENDENTLY. Every
  -- sheet is drawn at its side's scale x its own trimmed pixel size. A
  -- straight MULTIPLIER (x1 = the pack's own pixels, 1:1 and crispest)
  -- rather than a field-wide divisor, so relative sizes within a side stay
  -- exactly the pack's own. Tweak SPRITE_SCALE_FRONT to resize the enemy
  -- team (and the boss, which is a front) and SPRITE_SCALE_BACK to resize
  -- the ally team; both directions work. A preset may override either with
  -- `spriteScaleFront` / `spriteScaleBack` (or the legacy single
  -- `spriteScale`, which sets both). With every fold gone (round sixty-nine)
  -- a sheet is drawn at exactly its side's scale x its own trimmed pixels:
  -- never against its slot's width or height, never against any picture-box
  -- cap, and no longer against the field's own headroom either -- those
  -- folds are what used to make every species the same size.
  local SPRITE_SCALE_FRONT = 0.5
  local SPRITE_SCALE_BACK = 0.5

  -- NO SIZE CAP AT ALL (deliberately removed). Natural sizing used to fold
  -- every sheet back to its side's native Gen-2 box -- 56px front / 48px
  -- back, x1.6 for the boss -- so an oversized pack frame could never draw a
  -- mon bigger than the game's own screen would. That cap is what FLATTENED
  -- a big species the moment it passed that size (user-reported), and it is
  -- gone. So was the LAST remaining fold -- the field-headroom cap that
  -- shrank any sheet taller than the band above its ground line (round
  -- sixty-nine). A sheet is now drawn at its FULL size x its side's scale,
  -- period: if its art stands taller than the field it simply draws past the
  -- top of the scene and is cut by the screen edge, which is exactly what
  -- "preserve full sprite size" means. Width always follows the art's own
  -- aspect ratio.

  -- The trainer class/back pics that stand in a side's sprite slots during
  -- the intro are the cart's own 6-7 tile squares (48-56px); drawn at
  -- their native 7 tiles rather than stretched to the sprite band's own
  -- 64px, which would blow a trainer up past a mon's size.
  local TRAINER_PIC_T = 5

  -- The enemy team's own ground line: the enemy band is the UPPER half of
  -- the field, so its sprites' bottoms land at 8 tiles (64px) and the ally
  -- band (feet on BOTTOM_Y, the text box's own top edge) takes the lower
  -- half. The two bands are disjoint, so the two teams can never collide on
  -- the y axis no matter how tall a sheet is. The slot's own headroom is NOT
  -- handed to the sprite mod any more (round sixty-nine: that fold is gone),
  -- so an oversized legendary (a 130px Koraidon) is clipped at the top of
  -- the field rather than shrunken -- the user's explicit rule: preserve the
  -- full sprite size and let the screen edge do the cropping.
  local ENEMY_FEET_T = ROW_H
  -- The bossfight enemy's own size ratio: +0.6 (x1.6) on TOP of the field's
  -- FRONT scale, so ONLY the boss is drawn at SPRITE_SCALE_FRONT * BOSS_MUL
  -- its own pixels. See bossSlot: the boss is CENTRED on column 5 (e5) and
  -- stands in the enemy half of the field, BOSS_MUL bands tall, rather than
  -- down on the allies' own ground line.
  local BOSS_MUL = 1.5
  -- The bossfight boss's own POSITION nudge: +40 CANVAS px straight DOWN (a
  -- y-only shift; x is untouched), expressed as a design-px value because the
  -- 960x540 canvas is the fixed surface this file draws
  -- into, so a canvas-px offset is the same fraction of the field regardless
  -- of the window it is fitted to. Applied inside drawSprite (boss only), so
  -- it moves the sprite, the HUD head line and the pokeball's landing spot
  -- together, and never touches the bake (size) itself.
  local BOSS_Y_SHIFT = -60 / DS
  -- The player team's ground line is the TEXT BOX's own top edge -- see
  -- this file's standardized-geometry header. BOTTOM_H is a fixed 6.5
  -- tiles (52px) rather than 2/3 of whatever is left, so the F/E box's
  -- interior keeps the 36px the action menu has always needed (3 real
  -- rows) and the box reaches the canvas's bottom edge.
  local BOTTOM_H = 6.5
  local BOTTOM_Y = VH / 8 - BOTTOM_H -- 16 tiles (128px)
  -- The ally team's ground line IS the text box's own top edge, so no ally
  -- sprite can ever be drawn inside the text box, however tall it is.
  local ALLY_FEET_T = BOTTOM_Y
  local F_TW = 28
  local E_TW = VW / 8 - F_TW
  -- The player's GUI column's own tx, derived from E's own right edge
  -- (F_TW + E_TW, tile-space) rather than independently re-deriving the
  -- canvas width -- explicit request: the player GUI box's own right
  -- edge should align with the FIGHT/BAG/PKMN/RUN box's right edge, not
  -- just happen to coincide with it. F_TW+E_TW always equals VW/8 by
  -- construction (E_TW's own definition above), so this is the SAME
  -- number the old `VW/8 - GUI_TW` gave -- written this way so the
  -- dependency is on E's geometry by name, staying correct even if F_TW/
  -- E_TW's own split ever changes independently of VW.
  local GUI_RIGHT_TX = F_TW + E_TW - GUI_TW -- 25

  -- -- HUD readout placement: one box per slot + the 70% height rule ------
  -- Explicit user directive: each readout belongs OVER its own pokemon,
  -- with no box frame or white background left (see drawGuiBox) so the
  -- sprite reads straight through it. Two rules, both
  -- decided here:
  --
  -- 1. ONE BOX PER SLOT. The readouts used to be one STACKED column per
  --    team, all sharing a tx; they are now split so each box is PAIRED
  --    with the one mon -- and therefore the one slot -- it reports on. A
  --    box is centred on its own slot's centre-x, the exact point
  --    drawSprite centres that mon's sprite on, so moving the sprite moves
  --    its readout with it. (Native keeps each readout in the corner
  --    OPPOSITE its own team; "over the mon" is why the box background had
  --    to go transparent, and why it could not just stay in that corner.)
  --    A box is GUI_BOX_W (56.4px) wide, and the sprite grid's own pitch is
  --    exactly that width plus GUI_BOX_GAP (see COL_W), so the columns are
  --    already one non-overlapping readout apart and centring a box on its
  --    own slot's centre-x keeps every box clear of its neighbour. (Round
  --    eighty-two: the pitch used to be only 40.5px -- narrower than a
  --    readout -- so this row had to be re-spread, and its outer boxes then
  --    stopped sitting over their own mons; spreadBoxCentres, below, still
  --    runs as the safety net for a row that really does overlap, but a
  --    shipped row now comes back untouched.) Order is preserved, so box i
  --    is always battler i's.
  --
  -- 2. SAME HEIGHT. Every box on a side keeps the SAME height as its
  --    neighbours -- one head line per side, not one per mon -- so a full
  --    team reads as one even row ("keeping always the same height for the
  --    stat info gui"). Each box sits ON its side's head line, a hat rather
  --    than a sign held up beside it: its BOTTOM edge lies on that line
  --    (one box per slot now, so both sides place a single row the same
  --    way), and the mon's head reads through the transparent box.
  --    The head line is GUI_HEAD_PCT of the way up a sprite's OWN drawn
  --    height, measured from its feet (NOT a screen reference): the top
  --    ~30% of a pokemon sprite is its head, so 70% up lands at the base of
  --    the head. It is measured per sprite, then AVERAGED over the side
  --    (sideHeadY, below) into the single line the whole row shares.
  local GUI_HEAD_PCT = 0.70
  -- The head line for a side, in design px: the mean, over that side's
  -- battlers, of the head point of the sprite ACTUALLY DRAWN for it this
  -- frame -- drawn top + (1 - GUI_HEAD_PCT) * drawn height, recorded per
  -- battler by drawContent's sprite pass (drawSprite's own dy/dh returns).
  -- This measures the SPRITE'S OWN drawn box on purpose, NOT a slot/band
  -- (whose height is the whole 8-tile row no matter what art stands in it),
  -- so the line really does track the heads; it is averaged into the ONE
  -- line every box on the side shares, which is what keeps the row level.
  -- `fallback` (that side's ground line) covers a side with nothing drawn
  -- yet -- its trainer pic still stands in the slot, or its mons have not
  -- landed -- and the HUD is hidden until those mons are revealed anyway.
  local function sideHeadY(battlers, headLines, fallback)
    local n, sum = 0, 0
    for _, b in ipairs(battlers) do
      local hy = headLines[b]
      if hy then
        sum = sum + hy
        n = n + 1
      end
    end
    if n == 0 then return fallback end
    return sum / n
  end
  -- Shrinks the ENTIRE readout -- border, name, bar, numeric HP, exp bar, all
  -- of it -- to 47% size, anchored at the box's own top-left tile corner
  -- (that point stays fixed; everything else scales toward it) via a plain
  -- graphics transform around the whole draw, rather than recomputing every
  -- dimension by hand. Declared HERE rather than with the GUI_BOX_H_* group
  -- further down because the placement maths below needs it; that group now
  -- just reads this local.
  local BOX_SCALE = 0.47
  -- A readout's REAL drawn width -- GUI_TW tiles at BOX_SCALE -- and half
  -- of it. The readout is drawn from its LEFT edge (drawGuiBox's
  -- anchorRight=false), so centring it on a point is just (centre - half
  -- width), in px; guiTxOn applies that and clamps the result so the box
  -- always stays inside the canvas. GUI_BOX_GAP is the sliver left between
  -- two boxes in a spread row (spreadBoxCentres) so their borders never
  -- touch.
  local GUI_BOX_W = GUI_TW * 8 * BOX_SCALE -- 56.4px
  local GUI_BOX_HALF_W = GUI_BOX_W / 2     -- 28.2px
  local GUI_BOX_GAP = 2                    -- design px between adjacent boxes

  -- True interior origin for a box at (tx,ty): Font.drawBox's border
  -- glyphs occupy a full 8px tile at each edge (Font.lua:544-558),
  -- confirmed live after an earlier pass's text visibly struck through
  -- both the box's top and bottom border by assuming a thin rule instead.
  -- F/E's own text-anchor origin is computed PER-DRAW (self.fTextX/
  -- fTextY/eTextX/eTextY, set in drawContent) since F/E's own tuned
  -- positions (self.layout's fBox/eBox) aren't at these default tiles.
  -- Max characters per line before Font.draw's fixed 8px glyphs would
  -- run past F's real interior right edge -- 2 chars of slack under the
  -- exact (F_TW-2) fit, so a wrapped line never sits flush against the
  -- border.

  -- -- sprite grid helpers --------------------------------------------
  -- The centre-x (design px) of column `col` (1..8) for one side. Each side
  -- steps away from its own anchor (e6 for the enemy, a1 for the ally) by one
  -- COL_W per column, so an under-strength side keeps its anchor column and
  -- leaves the columns behind it empty -- see sideColumns.
  local function colCentre(side, col)
    if side == "enemy" then return ENEMY_RIGHT_X - (6 - col) * COL_W end
    return ALLY_LEFT_X + (col - 1) * COL_W
  end

  -- The column each of a side's battlers stands in, 1..8. Allies fill
  -- RIGHTWARD from a1 (cols 1,2,3,4) and enemies fill LEFTWARD from e6
  -- (cols 6,5,4,3,2), so a side under its maximum keeps its innermost
  -- column and leaves its outer ones empty. Two exceptions: a boss enemy
  -- always takes column 5 (e5), and a horde's lone ally takes column 2 (a2).
  local function sideColumns(count, side, boss, horde)
    count = math.max(1, count)
    if side == "enemy" then
      -- A boss enemy always stands at e5 (column 5).
      if boss then return { 5 } end
      -- Enemies fill LEFTWARD from column 6 (e6): 1 -> {6}, 2 -> {5,6},
      -- 3 -> {4,5,6}, 5 -> {2,3,4,5,6}. Clamp any battler past seven to
      -- column 1 so an oversized roster stays inside the field.
      local cols = {}
      for i = 1, count do cols[i] = math.max(7 - count + (i - 1), 1) end
      return cols
    end
    -- A horde's lone ally stands at a2 (column 2).
    if horde and count == 1 then return { 2 } end
    -- Allies fill RIGHTWARD from column 1 (a1): 1 -> {1}, 2 -> {1,2},
    -- 3 -> {1,2,3}, 4 -> {1,2,3,4}. Clamp any battler past eight to 8.
    local cols = {}
    for i = 1, count do cols[i] = math.min(i, 8) end
    return cols
  end

  -- The x centres (design px) for one side's row of readouts, one per entry
  -- in `centres` (that side's slot centres, in battler order).
  --
  -- ROUND EIGHTY-TWO: this is now normally the IDENTITY. The sprite grid's
  -- pitch (COL_W) IS the readout's own pitch (GUI_BOX_W + GUI_BOX_GAP), so a
  -- side's slot centres already stand exactly one non-overlapping readout
  -- apart and each box simply comes back on its own mon. It is kept -- and
  -- still does real work -- only as the safety net for a row whose centres
  -- are NOT already on that pitch (an over-full roster clamped onto the same
  -- column, say): it re-lays the row on the non-overlapping pitch around the
  -- MEAN of the slot centres so the boxes still read as one row over the
  -- team, then slides it to stay inside the canvas. A lone entry always comes
  -- back exactly on its own slot; order is preserved, so entry i is always
  -- battler i's box. (At most eight entries; the widest shipped row -- a
  -- five-mon horde -- is 4*58.4 + 56.4 = 290px, inside a 320px canvas.)
  local function spreadBoxCentres(centres)
    local n = #centres
    local out = {}
    if n == 0 then return out end
    if n == 1 then out[1] = centres[1]; return out end
    -- Already clear of one another? Leave the row EXACTLY on the mons. The
    -- sprite grid's pitch is this very pitch now (see COL_W), so a shipped
    -- row lands here and comes back untouched -- bit for bit on the slot
    -- centres -- and the re-layout below is reserved for a row that really
    -- does overlap (which is also the only case where it would be pulled off
    -- its mons, the thing the user asked to stop).
    local clear = true
    for i = 2, n do
      if centres[i] - centres[i - 1] < GUI_BOX_W then clear = false break end
    end
    if clear then
      for i = 1, n do out[i] = centres[i] end
      return out
    end
    local pitch = GUI_BOX_W + GUI_BOX_GAP
    local mean = 0
    for i = 1, n do mean = mean + centres[i] end
    mean = mean / n
    local first = mean - (n - 1) * pitch / 2
    local left = first - GUI_BOX_HALF_W
    local right = first + (n - 1) * pitch + GUI_BOX_HALF_W
    local shift = 0
    if left < 0 then
      shift = -left
    elseif right > VW then
      shift = VW - right
    end
    for i = 1, n do out[i] = first + (i - 1) * pitch + shift end
    return out
  end

  -- The tile-space tx that puts a BOX_SCALE-sized readout (GUI_BOX_W wide,
  -- drawn from its LEFT edge) centred on canvas x `cx`, clamped so the box
  -- can never hang off either side of the canvas.
  local function guiTxOn(cx)
    local tx = (cx - GUI_BOX_HALF_W) / 8
    return math.max(0, math.min((VW - GUI_BOX_W) / 8, tx))
  end

  -- The pixel slot {x,y,w,h} for column `col` within the occupied set
  -- `cols`: centred on the column, half-width = the nearer of (gap to the
  -- neighbouring column's own centre / 2) and (gap to the field edge), so a
  -- lone sprite gets up to the whole half-field while neighbours get one
  -- column each. The 1px shave keeps integer boxes from ever touching.
  --
  -- A slot is an ANCHOR, not a size: drawSprite centres the sprite on the
  -- slot's own centre-x and stands it on the slot's ground line (its bottom
  -- edge, feetT*8). The width/height here are still the sprite's own hit-box
  -- (the pokeball's fallback landing spot, the move-animation anchors), never
  -- a box the art is folded into.
  --
  -- `side` ("enemy"/"ally") picks which side's column grid the slot is read
  -- from -- each side anchors its own columns (see colCentre). The other
  -- bounds are shared: the clamp to the physical field edges (SPRITE_FIELD_L/
  -- R) bounds the free half-field a lone mon's slot may take.
  local function slotRect(cols, col, feetT, rowH, side)
    local center = colCentre(side, col)
    local left, right = SPRITE_FIELD_L, SPRITE_FIELD_R
    for i, cc in ipairs(cols) do
      if cc == col then
        if cols[i - 1] then left = (center + colCentre(side, cols[i - 1])) / 2 end
        if cols[i + 1] then right = (center + colCentre(side, cols[i + 1])) / 2 end
        break
      end
    end
    local half = math.min(center - left, right - center)
    local w = math.max(8, math.floor(half * 2) - 1)
    local h = rowH * 8
    return {
      x = math.floor(center - w / 2 + 0.5),
      y = feetT * 8 - h,
      w = w,
      h = h,
    }
  end

  -- The boss's own slot: CENTRED on column 5 -- e5 -- and standing in the
  -- ENEMY half of the field, so it no longer shares the allies' own ground
  -- line (user-reported: the boss used to sit down among the four allies,
  -- "at a7 or a8", when it belongs in e5). The old slot clamped its LEFT
  -- edge to e5's left edge and ran it to the player HUD, which parked the
  -- sprite ~1.5 columns right of e5. Now the slot's CENTRE is e5's centre,
  -- so the boss stands in e5. It is BOSS_MUL enemy bands tall with its TOP
  -- on the field's own top edge (y=0), so it towers over the upper half
  -- instead of standing on the allies' line, and it is never clipped.
  local function bossSlot()
    local center = colCentre("enemy", 5)
    local h = math.max(8, math.floor(BOSS_MUL * ROW_H * 8) - 1)
    local w = math.max(8, 2 * math.floor(math.min(center - SPRITE_FIELD_L,
      SPRITE_FIELD_R - center)) - 1)
    return {
      x = math.floor(center - w / 2 + 0.5),
      y = 0,
      w = w,
      h = h,
    }
  end

  -- Window pixels per CANVAS pixel. ALWAYS the exact fit ratio -- the
  -- largest fractional scale that keeps the whole canvas inside the
  -- window -- so the canvas FILLS the room it has instead of being
  -- letterboxed down to the next whole number. This is what puts the
  -- bottom message/menu band's own bottom frame ON the screen's bottom
  -- edge at any window size (the user's rule, round sixty-nine): a
  -- whole-number fit used to shrink the canvas to x1 on any window that
  -- could not hold a full x2 (720p, 900p, 1440p, any windowed size),
  -- leaving the text/menu boxes floating well above the real screen edge
  -- with bars around them, and keeping the field itself small. Filling
  -- enlarges every element -- most importantly giving the player's sprites
  -- the extra vertical room above their ground line that the old
  -- integer-letterboxed canvas withheld. The trade is that a sprite's own
  -- pixels no longer always land on whole screen pixels off the exact
  -- multiples (960x540 / 1920x1080 / 4K / 8K); on those it is still a
  -- clean whole number.
  local function fitScale(winW, winH)
    local raw = math.min((winW or 0) / CANVAS_W, (winH or 0) / CANVAS_H)
    return raw > 0 and raw or 1
  end

  -- Top-left of the centred canvas, in window px.
  local function fitOrigin(winW, winH, scale)
    return math.floor((winW - CANVAS_W * scale) / 2),
      math.floor((winH - CANVAS_H * scale) / 2)
  end

  local function displayName(mon)
    return mon.nickname or mon.name or mon.species or "???"
  end

  -- The mon's maximum hit points, whichever field this generation keeps it in.
  -- Gen 2's src/battle/gen2/Mon.lua stamps `mon.maxHp = stats.hp`, so every
  -- Gen 2 mon has .maxHp and this is that field, unchanged.  Gen 1's mon never
  -- carries .maxHp -- src/pokemon/Stats.lua's Stats.ensure recomputes
  -- mon.stats.hp and clamps mon.hp to it, but does not (and must not, or a
  -- levelled mon's stale cap would be preferred by the engine's own
  -- `mon.maxHp or mon.stats.hp` reads) write .maxHp -- so Gen 1's real cap is
  -- mon.stats.hp.  Reading mon.maxHp bare gave the bar a nil max on Gen 1:
  -- the HudTiles shim turns that into a max of 1, so the fill computed from
  -- hp*48/1 clamped to a permanently FULL bar -- the reported "HP bar isn't
  -- lowering when a Pokemon takes damage".  Same `or` fallback the engine
  -- itself uses (e.g. src/battle/gen2/Battle.lua:1397), so Gen 2 is
  -- byte-for-byte unchanged and Gen 1 draws the bar it always should have.
  local function maxHpOf(mon)
    return (mon and mon.maxHp) or (mon and mon.stats and mon.stats.hp) or 0
  end

  -- Word-wraps text to fit F's own real interior width (F_TW-2 chars,
  -- see this file's header note on Font.drawBox's border cost) and
  -- draws it as however many lines that takes. Battle messages
  -- (combat.lua's own resolveAction text especially -- "X used Y! It's
  -- super effective! Critical hit! Z fainted!" -- and the catch/switch
  -- status lines) routinely run well past F's ~26-char width; drawing
  -- them as one unwrapped line is exactly what let text run past the
  -- box border. F has 6 lines of real vertical room (its interior is 6
  -- tiles tall), far more than any single message here needs.
  local function drawWrapped(text, x, y, maxChars, lineHeight)
    lineHeight = lineHeight or 9
    -- ROUND 107: the F box must never draw a control token or the word
    -- "prompt". Battle text coming out of the engine/ROM keeps trailing
    -- {PROMPT}/{DONE} control tokens (RomText.lua preserves them; TextBox
    -- strips them, but this scene draws through Font directly), and the
    -- font renders the token's letters literally -- a flinched mon showed
    -- "... flinched!{PROMPT}". Strip the tokens (any case) and any stray
    -- standalone "prompt" word before wrapping.
    text = tostring(text or "")
    text = text:gsub("{%s*[Pp][Rr][Oo][Mm][Pp][Tt]%s*}", " ")
    text = text:gsub("{%s*[Dd][Oo][Nn][Ee]%s*}", " ")
    text = text:gsub("%f[%a][Pp][Rr][Oo][Mm][Pp][Tt]%f[%A]", " ")
    text = text:gsub("%s+", " ")
    local line = ""
    local row = 0
    for word in text:gmatch("%S+") do
      local candidate = (line == "") and word or (line .. " " .. word)
      if #candidate > maxChars and line ~= "" then
        Font.draw(line, x, y + row * lineHeight)
        row = row + 1
        line = word
      else
        line = candidate
      end
    end
    if line ~= "" then
      Font.draw(line, x, y + row * lineHeight)
      row = row + 1
    end
    return row
  end

  -- Shrinks `name` one character at a time until "name .. suffix" fits
  -- within maxWidth px, measured with Font.width (glyph advances, not
  -- raw Lua string length -- important here specifically because the
  -- gender suffix is a multi-byte UTF-8 escape, and byte-counting it
  -- would under-truncate). This mod's own species roster runs well past
  -- vanilla's naming assumptions (GOTHITELLE, SIZZLIPEDE...), so without
  -- this a long name combined with "Lv##" + gender is exactly what ran
  -- text past the GUI box's own border before this pass.
  local function fitName(name, maxWidth, suffixWidth)
    local avail = maxWidth - suffixWidth
    while #name > 0 and Font.width(name) > avail do
      name = name:sub(1, #name - 1)
    end
    return name
  end

  -- path -> Image or false (tried and failed -- never retried every
  -- frame). Same pattern this codebase's own overworld sprite mods use
  -- for exactly the same reason: a missing/bad file must degrade to "no
  -- sprite drawn," never crash the frame it's asked for in.
  local spriteCache = {}
  local function loadSprite(path)
    if not path then return nil end
    local cached = spriteCache[path]
    if cached ~= nil then return cached or nil end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      img:setFilter("nearest", "nearest")
      spriteCache[path] = img
      return img
    end
    spriteCache[path] = false
    return nil
  end

  -- Resolve one battler's sprite exactly the way drawSprite draws it, WITHOUT
  -- drawing it: the art seam (pokemon.sprite) picks the file, it is loaded, and
  -- the frame seam (battle.mon_pic) swaps in the sprite pack's current frame.
  -- Kept separate from drawSprite so a caller in the UPDATE phase can start a
  -- sheet baking early without touching love.graphics -- Screen:prewarmSlot
  -- raises these same seams during a pokeball's flight, which is what stops a
  -- trainer's send-out from ever flashing the vanilla pic. Returns (img,
  -- naturalBake); img is nil both when the battler has no art at all and when
  -- the frame seam has asked us to draw NOTHING this frame yet -- a managed
  -- species whose sheet is still baking (see the battle.mon_pic block below).
  local function resolveSprite(r, boss, battler, spriteField, data, scaleMul)
    local mon = battler and battler.mon
    if not mon then return nil end
    local def = data and data.pokemon and data.pokemon[mon.species]
    local path = def and def[spriteField]
    -- Resolve through the engine's own art seam instead of drawing the raw
    -- species-record field. National Dex sets spriteFront/spriteBack to its
    -- OWN placeholder for every species past the cart's roster, so reading
    -- the field directly drew that placeholder -- a "?" for every combatant
    -- -- while a sprite mod sat on the real art. src/ui/gen2/BattleState.lua
    -- raises this same hook with these same ctx keys for the native screen,
    -- so this is the seam every other mon-pic consumer on Gen 2 already uses.
    if path and Runtime.wantsHook("pokemon.sprite") then
      local ctx = {
        species = mon.species,
        side = (spriteField == "spriteBack") and "back" or "front",
        kind = "battle",
        mon = mon,
        trueColor = (def and def.trueColor) and true or false,
        data = data,
        shiny = mon.shiny and true or false,
      }
      local hooked = Runtime.call("pokemon.sprite",
        function(value) return value end, path, ctx)
      if type(hooked) == "string" and hooked ~= "" then path = hooked end
    end
    local img = path and loadSprite(path)
    if not img then return nil end
    -- Set true only when the sprite pack hands back its own CANVAS-scale
    -- natural bake (see the battle.mon_pic block below); a vanilla pic stays
    -- DESIGN-scale. Returned to drawSprite, which uses it for its blit scale.
    local naturalBake = false
    -- Animated art arrives through a SECOND seam: pokemon.sprite above picks
    -- the file, battle.mon_pic swaps the current frame into the image on its
    -- way to the screen -- which is why a sprite mod's animated sets showed
    -- here as a still first frame. An animator keys its clock off the battler
    -- it is handed and advances on its own, so raising this once per draw is
    -- the whole of it; there is no tick to run here.
    -- This side's scale multiplier: the caller's per-battle override
    -- (self.spriteScaleFront/_Back, or a preset's own) if given, else this
    -- file's own default. FRONT and BACK are INDEPENDENT, so the two teams
    -- resize separately; the boss rides the FRONT scale.
    local sideBack = (spriteField == "spriteBack")
    local fieldScale = scaleMul or (sideBack and SPRITE_SCALE_BACK or SPRITE_SCALE_FRONT)
    if Runtime.wantsHook("battle.mon_pic") then
      local pctx = {
        species = mon.species,
        side = (spriteField == "spriteBack") and "back" or "front",
        mon = mon,
        battler = battler,
        -- Only `.data` is read off this (an animator uses it to find the
        -- species' battle-scale fields), and drawSprite is handed that
        -- data already -- so this carries the real table rather than
        -- reaching for a screen `self` that is not in scope here.
        battle = data and { data = data } or nil,
        -- NATURAL SIZE: the slot is an anchor, not a box. The mod bakes the
        -- sheet at exactly `scale` x its own (trimmed) pixels and returns an
        -- image that is ALREADY the final size, so the blit below is 1:1 in
        -- CANVAS pixels and each species keeps the size its art gives it (a
        -- Diglett stays small, a Koraidon stays huge) instead of every
        -- sprite being folded into the same slot-sized square. `scale` is
        -- THIS side's multiplier (SPRITE_SCALE_FRONT for enemies,
        -- SPRITE_SCALE_BACK for allies; x1.6 on top for the boss -- the
        -- "+0.6", bosses only) times DS, i.e. the canvas scale, so the bake
        -- lands at the resolution the 960x540 surface can actually show
        -- instead of being baked small and magnified by the fit transform.
        -- NO SIZE CAP OF ANY KIND (user's rule, round sixty-nine): the
        -- picture-box cap went first (see the note by SPRITE_SCALE_FRONT/
        -- BACK), and the field-headroom fold goes with it now. `maxH` is
        -- deliberately NOT passed, so the pack bakes the sheet at exactly
        -- `scale` x its own trimmed pixels and NOTHING shrinks it -- a
        -- species whose art stands taller than the field simply draws past
        -- the top of the scene and is cut by the screen edge, which is what
        -- "preserve full sprite size" means. With the canvas now filling the
        -- window (see fitScale) the field is as tall as the display allows,
        -- so the player's side gets all the room there is.
        natural = true,
        scale = fieldScale * (boss and BOSS_MUL or 1) * DS,
      }
      local ok, swapped = pcall(Runtime.call, "battle.mon_pic",
        function(value) return value end, img, pctx)
      -- The pack's natural bake comes back rasterised at CANVAS scale, so
      -- it is blitted 1:1 there -- one design px is DS canvas px, hence the
      -- / DS in the draw scale below. A vanilla pic (no pack, or a sheet
      -- the pack could not manage) is native DESIGN-px art and draws at its
      -- own size as always.
      if ok and swapped == false then
        -- The frame seam manages this species and its sheet is STILL BAKING
        -- (the sprite mod returns `false` for exactly that one case): draw
        -- NOTHING this frame. The vanilla pic must never be shown while a
        -- real sheet is on its way -- that was the native flash a trainer's
        -- send-out showed for the first frames of the mon's materialize.
        return nil
      end
      if ok and swapped and swapped ~= img then
        img = swapped
        naturalBake = true
      end
    end
    return img, naturalBake
  end

  -- Floats a mon's sprite at its own pixel SLOT `r` = {x,y,w,h}. The slot is
  -- an ANCHOR, not a size: the sprite's own centre-x sits on the slot's
  -- centre-x and its feet stand on the slot's bottom edge (the ground line).
  -- `boss` (true only for the bossFight enemy) asks the sprite mod for the
  -- boss's own extra size on top of the FRONT scale (see
  -- SPRITE_SCALE_FRONT/BACK / BOSS_MUL). Every sprite is drawn at its OWN
  -- size -- the pack's relative sizes, which is what "normal size" means --
  -- never folded into the slot's box, so no two species are forced to the
  -- same height or width; there is no fold of any kind (round sixty-nine).
  -- Returns the sprite's own bottom-center screen position (post-draw),
  -- or nil if nothing was drawn -- callers that need to know WHERE a
  -- battler's sprite actually landed this frame (move animations, see
  -- Screen:startMoveAnim) read this instead of re-deriving the same
  -- slot/scale math a second time. nil is also returned, quite deliberately,
  -- for the frames a managed species' sheet is still baking: the sprite is
  -- simply absent (see resolveSprite) rather than showing its vanilla pic.
  --
  -- Two more values follow that anchor when something DID draw: the
  -- sprite's own drawn TOP (`dy`) and drawn HEIGHT (`dh`), both in design
  -- px. They are the sprite's REAL box -- the size the art came out at,
  -- which varies per species -- not the slot's band, so the head-placement
  -- pass (drawContent's HUD section) can put a readout on a mon's own head
  -- rather than on a shared row line. A fifth value, `dhFull`, is that
  -- same height at appear = 1: the materialize animation scales the drawn
  -- box about the feet, so a caller that wants a line that does not ride
  -- up with the animation (the HUD anchor) uses `dhFull` with the ground
  -- line the sprite currently stands on. Callers that only want the
  -- anchor keep reading the first two returns and ignore the rest.
  --
  -- A final optional `alpha` (0..1) multiplies only the blit's opacity --
  -- the wild-encounter fade-in (round sixty-three) passes its 0..1 ramp
  -- here so the mon materializes without moving; every existing caller
  -- omits it and draws fully opaque (alpha defaults to 1), so nothing
  -- else about a sprite's draw changes.
  local function drawSprite(r, boss, battler, spriteField, data, anchorRight, offX, offY, appear, scaleMul, alpha)
    local img, naturalBake = resolveSprite(r, boss, battler, spriteField, data, scaleMul)
    if not img then return nil end
    local iw, ih = img:getDimensions()
    -- 1:1 blit in CANVAS pixels for a natural bake (see pctx above), plain
    -- DESIGN-px size for the vanilla pic. Nothing is resampled to fit the
    -- slot, so every species comes out at its own size -- which is the
    -- whole point.
    local scale = (appear or 1) / (naturalBake and DS or 1)
    local dw, dh = iw * scale, ih * scale
    local dx = r.x + (r.w - dw) / 2
    local dy = r.y + r.h - dh
    dx = dx + (offX or 0)
    dy = dy + (offY or 0)
    -- Boss-fight only: stand the boss BOSS_Y_SHIFT lower (see BOSS_MUL's own
    -- note). A POSITION shift alone -- the bake above is untouched, so the
    -- boss keeps its size -- and it is applied before the anchor/head values
    -- are derived below, so the HUD readout and the ball's landing spot move
    -- with the art.
    if boss then dy = dy + BOSS_Y_SHIFT end
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, dx, dy, 0, scale, scale)
    -- The bottom-center anchor; this sprite's own drawn box (top y and
    -- height, design px); and that height at appear = 1 (see the header
    -- note -- `appear` is only ever a plain multiplier on the scale, so
    -- the full-size height is just the art's height over its bake
    -- divisor, which is also the right answer when appear is 0).
    local fullH = ih / (naturalBake and DS or 1)
    return dx + dw / 2, dy + dh, dy, dh, fullH
  end

  -- Draws a raw image -- a trainer's pic, which has no species record --
  -- the same way drawSprite floats a mon: bottom-anchored in the SAME pixel
  -- slot `r` its mon will occupy, upright, scaled to TRAINER_PIC_T tiles
  -- (trainer pics are 6/7-tile squares on native, read as a bit larger than
  -- a mon's box). offX shifts it horizontally -- the trainer slides' 8px
  -- tile steps.
  --
  -- COLOUR: a trainer pic is a 4-shade grayscale sheet, and native colours
  -- it by remapping those four shades through the trainer's own row of
  -- TrainerPalettes -- BattleState:drawPic's
  -- `colors = Palettes.trainerColors(...)` arm, applied through
  -- GbcPalette.with. Drawing the sheet raw (what this did before) shows it
  -- grey, which is the bug this fixes. `colors` is that four-colour row
  -- (nil when the class has no palette entry -- native falls through and
  -- draws raw in that case too); `trueColor` marks a mod-supplied FULL-COLOUR
  -- pic, which native draws as-is in GBC mode and only remaps in DMG/classic
  -- -- so the guard below is native's own:
  --   colors and not (trueColor and GbcPalette.mode == "gbc")
  -- Returns the bottom-center position, or nil if nothing drew.
  local function drawRawImage(pathOrImg, r, offX, anchorRight, colors, trueColor)
    local img = pathOrImg
    if type(img) == "string" then img = loadSprite(img) end
    if not img then return nil end
    local iw, ih = img:getDimensions()
    local scale = (TRAINER_PIC_T * 8) / math.max(iw, ih)
    local dw, dh = iw * scale, ih * scale
    local dx = (anchorRight and (r.x + r.w - dw)) or (r.x + (r.w - dw) / 2)
    local dy = r.y + r.h - dh
    dx = dx + (offX or 0)
    local function body()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, dx, dy, 0, scale, scale)
    end
    if colors and not (trueColor and GbcPalette.mode == "gbc")
        and GbcPalette.available() then
      GbcPalette.with(colors, body)
    else
      body()
    end
    return dx + dw / 2, dy + dh
  end

  -- Draws a pokeball as primitives at `cx,cy` with radius `r`. `spin`
  -- (0..1 over the flight) turns the ball one-and-a-half times so the
  -- red/white split visibly tumbles. This is now only the FALLBACK --
  -- drawNativeBall below draws the game's own ball art -- kept for the
  -- case where the cached battle_anims data or that sprite sheet is
  -- missing, so a send-out still reads as a ball rather than nothing.
  local function drawPokeball(cx, cy, r, spin)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate((spin or 0) * 2 * math.pi * 1.5)
    love.graphics.setColor(0.85, 0.12, 0.12, 1) -- red top half
    love.graphics.arc("fill", "pie", 0, 0, r, math.pi, 2 * math.pi)
    love.graphics.setColor(1, 1, 1, 1)          -- white bottom half
    love.graphics.arc("fill", "pie", 0, 0, r, 0, math.pi)
    love.graphics.setColor(0.1, 0.1, 0.1, 1)    -- center band + button
    love.graphics.rectangle("fill", -r, -1.5, 2 * r, 3)
    love.graphics.circle("fill", 0, 0, 2.2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
  end

  ------------------------------------------------------------------
  -- The native pokeball, for the send-out throw.
  --
  -- User-reported: the primitive ball above reads as a drawn stand-in,
  -- not the game's own ball. The real one is just another object in the
  -- battle_anims cache this file ALREADY receives (self.data.
  -- gen2BattleAnims): BATTLE_ANIM_OBJ_POKE_BALL, whose object row names
  -- BATTLE_ANIM_FRAMESET_POKE_BALL_1 -- the two-frame closed ball the
  -- native throw flies (oamframe OAMSET_0A/0B alternating, the 4th frame
  -- X-flipped, so the ball visibly tumbles) -- and BATTLE_ANIM_GFX_POKE_BALL,
  -- the sheet, drawn through the SAME BattleAnimView + GbcPalette.objPalette
  -- path Screen:drawMoveAnimObjects already uses, so the pixels and the
  -- red OBJ palette (PAL_BATTLE_OB_RED, off the object row) are the cart's
  -- own rather than a redrawn approximation.
  --
  -- Nothing native moves it: the throw's own arc is this screen's, because
  -- a double battle's landing spot is a per-slot platform, not vanilla's
  -- one fixed coordinate. So only the ball's OAM frame is taken from the
  -- animation; its position comes from the caller's parabola. The OAM
  -- entry math below is a faithful copy of AnimObjects.lua's
  -- Pool:updateOam (tile = base + oamset.vtile + sprite.tile, and a
  -- flipped frame mirrors each cell by -(offset+8) while toggling that
  -- cell's own flip), fed back through BattleAnimView's real drawObjects
  -- via a minimal stand-in runner.
  -- The native ball art is 16px across; next to this screen's sprites a
  -- 16px ball reads about right, so it is drawn at 0.6 (~10px) regardless
  -- of how tall the sprite bands are. Tying it to a slot's own box would
  -- blow the ball up to ~30-60px.
  --
  -- GEN 1 uses its OWN ball, never this one: a Gen 1 boot has no
  -- gen2BattleAnims and no BattleAnimView, so drawNativeBall hands off to
  -- drawGen1NativeBall, which reads the ball's own frame block out of the
  -- Gen 1 anim tables (`data.battle_anims`, the same ones AnimPlayer drives
  -- for Gen 1's moves and catch throw). See that function's own header.
  local BALL_DRAW_SCALE = 0.6
  -- The landing pose is drawn with its centre a little above the platform
  -- bottom the mon is anchored to, so the open ball sits ON the ground.
  local BALL_LAND_LIFT = 5
  local BALL_OAM_XFLIP, BALL_OAM_YFLIP, BALL_OAM_PAL1 = 0x20, 0x40, 0x10
  -- The struct origin (0-255 OAM space) of a 16x16 two-by-two OAM set sits
  -- 8 right and 16 down of the ball's own centre (each cell draws at
  -- x-8/y-16; the four cells span [Sx-16,Sx] x [Sy-24,Sy-8]), so a local
  -- origin of (8,16) centres the ball on the draw origin the caller sets.
  local BALL_LOCAL_X, BALL_LOCAL_Y = 8, 16

  local function s8(value)
    value = (value or 0) % 256
    return value < 0x80 and value or value - 256
  end

  -- A frameset's drawable rows with their per-frame duration (60fps frames)
  -- and flip flags, dropping the restart/end/delete pseudo-rows -- the same
  -- walk AnimObjects.lua's Pool:getFrame does.
  local function ballFramesetPlan(anims, framesetName)
    local frames = anims.framesets and anims.framesets[framesetName]
    if not frames then return nil end
    local list, total = {}, 0
    for _, row in ipairs(frames) do
      if row[1] == "frame" then
        local duration = row[3] or 1
        list[#list + 1] = { oamset = row[2], flip = row[4] or 0, duration = duration }
        total = total + duration
      elseif row[1] == "wait" then
        local duration = row[2] or 1
        list[#list + 1] = { duration = duration }
        total = total + duration
      end
    end
    if total <= 0 then return nil end
    return { list = list, total = total }
  end

  local function ballFrameAt(plan, elapsed)
    local at = (math.floor(elapsed * 60) % plan.total) + 1
    for _, frame in ipairs(plan.list) do
      if at <= frame.duration then return frame end
      at = at - frame.duration
    end
    return plan.list[#plan.list]
  end

  -- Gen 1's OWN ball, for the same send-out throw.  A Gen 1 boot has no
  -- AnimRunner/BattleAnimView (that is the Gen 2 animation contract), so
  -- there is no BATTLE_ANIM_OBJ_POKE_BALL to read -- but Gen 1 is not
  -- ball-less.  The cart's own TOSS_ANIM row in `data.battle_anims` -- the
  -- very Gen 1 tables this file already drives through
  -- src/battle/AnimPlayer.lua for the move and catch animations -- is a
  -- subanimation whose first frame block IS the ball: FRAMEBLOCK_03, a 2x2
  -- 16x16 composite of tiles $02 (upper half) and $12 (lower half) out of
  -- anim tileset 0 (data/battle_anims/frame_blocks.asm FrameBlock03,
  -- reached via subanimations.asm Subanim_0BallTossHigh, which
  -- data/moves/animations.asm BallTossAnim points at).  That is the very
  -- tile the catch arm's own ball flies, drawn through the same
  -- sheet/quad path Screen:drawGen1AnimSprites uses, so the send-out ball
  -- and the catch ball are one object rendered one way.
  --
  -- The Gen 2 object/frameset/sheet above is deliberately NOT read here
  -- (user rule: Gen 1 uses Gen 1's native ball, never Gen 2's).
  --
  -- Nothing native tumbles this ball -- the GB's toss walks a static ball
  -- graphic along a base-coordinate list -- so the flight is a plain
  -- translate of the block following the caller's own arc.  Returns false
  -- when the data or its sheet is unavailable, so the caller keeps
  -- drawPokeball's primitive and a send-out still reads as a ball.
  local function drawGen1NativeBall(screen, cx, cy)
    if not AnimPlayer then return false end
    local anims = N.gen1AnimData(screen.data)
    local toss = anims and anims.moveAnims and anims.moveAnims["TOSS_ANIM"]
    local row = toss and toss.seq and toss.seq[1]
    if not row then return false end
    local sub = anims.subanims and anims.subanims[row.subanim]
    local entry = sub and sub.blocks and sub.blocks[1]
    local fb = entry and anims.frameBlocks and anims.frameBlocks[entry.block]
    local sheet = anims.tilesheets and anims.tilesheets[row.tileset]
    if not (fb and sheet) then return false end
    -- A dedicated player, cached on the screen, only for the sheet image
    -- and its tile quads -- the ball is a still composite, so none of the
    -- step machinery is used.  (AnimPlayer's image/quad caches are
    -- per-instance; one player per battle is all this needs.)
    local player = screen.gen1BallPlayer
    if not player then
      player = AnimPlayer.new(anims)
      screen.gen1BallPlayer = player
    end
    local img = player:sheetImage(row.tileset)
    if not img then return false end
    local G = love.graphics
    G.setColor(1, 1, 1, 1)
    G.push()
    G.translate(cx, cy)
    G.scale(BALL_DRAW_SCALE, BALL_DRAW_SCALE)
    for _, t in ipairs(fb) do
      local quad = player:tileQuad(row.tileset, t.tile)
      if quad then
        local sx = t.xflip and -1 or 1
        local sy = t.yflip and -1 or 1
        -- The block's own 16x16 box is centred on the throw position: its
        -- tile offsets run 0..8, so the box is laid out from -8,-8.
        G.draw(img, quad,
               -8 + (t.x or 0) + (sx < 0 and 8 or 0),
               -8 + (t.y or 0) + (sy < 0 and 8 or 0),
               0, sx, sy)
      end
    end
    G.pop()
    return true
  end

  -- One frame of the native ball, centred on screen (cx,cy). `open` uses
  -- the pose the native object switches to when the throw lands
  -- (BATTLE_ANIM_FRAMESET_POKE_BALL_3) instead of the in-flight tumble;
  -- it falls back to the in-flight frameset if that data is absent.
  -- Returns false when the cache/sheet is unavailable, so the caller can
  -- draw the primitive fallback instead.
  local function drawNativeBall(screen, cx, cy, elapsed, open)
    -- Gen 2's object/frameset contract only.  A Gen 1 boot draws its OWN
    -- native ball instead (drawGen1NativeBall above) -- never Gen 2's
    -- asset (user rule) -- and only falls through to drawPokeball's
    -- primitive when even the Gen 1 data is missing.
    if not N.isGen2 then return drawGen1NativeBall(screen, cx, cy) end
    if not BattleAnimView then return false end
    local anims = N.animData(screen.data)
    local object = anims and anims.objects and
      anims.objects["BATTLE_ANIM_OBJ_POKE_BALL"]
    if not object then return false end
    local function oamsetAt(framesetName)
      local plan = ballFramesetPlan(anims, framesetName)
      local frame = plan and ballFrameAt(plan, elapsed)
      return frame and frame.oamset and anims.oamsets and
        anims.oamsets[frame.oamset], frame
    end
    local oamset, frame = oamsetAt(open and "BATTLE_ANIM_FRAMESET_POKE_BALL_3"
      or object.frameset)
    if not oamset and open then oamset, frame = oamsetAt(object.frameset) end
    if not oamset then return false end
    local sheet = anims.gfx and anims.gfx[object.gfx]
    if not sheet then return false end
    screen.animView = screen.animView or
      BattleAnimView.new(anims, N.paletteData(screen.data))
    local view = screen.animView
    local image = view:image(sheet.image)
    if not image then return false end
    local frameFlip = (frame and frame.flip) or 0
    local xFlip = bit.band(frameFlip, BALL_OAM_XFLIP) ~= 0
    local yFlip = bit.band(frameFlip, BALL_OAM_YFLIP) ~= 0
    local entries = {}
    for _, sprite in ipairs(oamset.sprites or {}) do
      local ex, ey = s8(sprite.x), s8(sprite.y)
      if xFlip then ex = -(ex + 8) end
      if yFlip then ey = -(ey + 8) end
      entries[#entries + 1] = {
        x = BALL_LOCAL_X + ex,
        y = BALL_LOCAL_Y + ey,
        tile = (oamset.vtile or 0) + (sprite.tile or 0),
        attr = bit.band(bit.bxor(sprite.attr or 0, frameFlip), 0xe0) +
          bit.band(sprite.attr or 0, BALL_OAM_PAL1),
        palette = object.palette,
      }
    end
    -- BattleAnimView:drawObjects takes the runner by duck type: it only
    -- reads runner:oam() and runner.loaded (sheetForTile's own list). No
    -- AnimRunner instance is needed to draw a still frame -- and none
    -- could place it here anyway, its motion is vanilla's fixed one.
    local runner = {
      loaded = { { tile = 0, tiles = sheet.tiles, gfx = object.gfx } },
      oam = function() return entries end,
    }
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(BALL_DRAW_SCALE, BALL_DRAW_SCALE)
    view:drawObjects(runner, nil)
    love.graphics.pop()
    return true
  end

  -- 0..1 scale for a mon materializing at the end of a pokeball throw
  -- (nil when that slot has no active throw -- i.e. draw at full size).
  -- A revealed slot draws through this so the mon grows out of the
  -- ground exactly where the ball landed, over BALL_APPEAR seconds after
  -- the poof.
  local function ballAppearFor(screen, side, slot)
    local bt = screen.ballThrow
    if not bt or bt.side ~= side or bt.slot ~= slot then return nil end
    if bt.t < BALL_FLIGHT + BALL_POOF then return 0 end
    local ta = math.min(1, (bt.t - BALL_FLIGHT - BALL_POOF) / BALL_APPEAR)
    return 1 - (1 - ta) * (1 - ta)
  end

  -- Draws text shrunk by `scale` (a plain graphics transform around the
  -- normal Font.draw calls, not a second font) -- the only way to fit
  -- this mod's own longer species names (GOTHITELLE, SIZZLIPEDE...)
  -- alongside "LvNN" + gender without truncating them, now that the box
  -- itself is shorter and can't just grow to make room.
  local function drawScaledText(text, x, y, scale)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(scale, scale)
    Font.draw(text, 0, 0)
    love.graphics.pop()
  end

  -- Same technique as drawScaledText, for a single glyph code (the
  -- cursor arrow) -- Font.drawCode has no scale parameter of its own
  -- and always draws at native (~8px) size, which swallowed adjacent
  -- 0.5-scale cross-mode text almost entirely (screenshot-reported).
  local function drawScaledCode(code, x, y, scale)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(scale, scale)
    Font.drawCode(code, 0, 0)
    love.graphics.pop()
  end

  -- The cart's own textbox frame, drawn as GEOMETRY instead of glyphs.
  --
  -- Font.BORDER hands back $79-$7E of whichever font page the RUNNING
  -- generation loaded, and the two generations do not agree on that art.
  -- Gold's extra page carries the clean double-line GSC textbox (the
  -- extractor blits frames.png row 0 -- the default frame -- into it, and
  -- Font's framePages/useBattleExtra resolve the player's choice from
  -- there), while a Red/Blue/Yellow boot has no frames sheet at all and
  -- falls through to Red's own font_extra border: the ornate,
  -- clover-cornered double line.  Same calls, two different boxes -- so on
  -- Gen 1 this scene read as a Gen 1 text box rather than the Gen 2 one it
  -- exists to be.
  --
  -- This draws the Gen 2 frame itself, so F and E look like the cart's own
  -- textbox on BOTH generations: no font asset to ship, no page registered,
  -- nothing global -- the engine's Font state is untouched, so every other
  -- text box in the game keeps its own generation's art.
  --
  -- It is the extracted default frame read as geometry, edge for edge.  The
  -- tile art is NOT a tidy 1-2-1 sandwich: the horizontal tile carries a 1px
  -- outer line, a 1px paper gap, then a 2px inner line, while the vertical
  -- tile carries 1px and 1px.  The engine draws the horizontal tile at the
  -- TOP and, unflipped, at the BOTTOM (so the bottom band is the vertical
  -- mirror of the top: 2px outer, 1px inner), and the vertical tile
  -- unflipped on BOTH sides (so the right pair sits 1px further in than the
  -- left).  Reusing the same measure the engine's own Font.drawBox produces
  -- with these exact tiles is the whole point -- a "cleaned up" symmetric
  -- box would be a different box.
  --
  -- The corners are the tile's own 3-step rounding: the outer line comes in
  -- one pixel per row across three rows (4 -> 3 -> 2 on the left) and the
  -- inner line across two, plus the single-pixel nub where the inner corner
  -- turns.  At 3x DS those steps are what read as "GSC rounded" instead of
  -- "two rectangles".
  --
  -- Rects also free the frame from tile alignment.  Font.drawBox's border
  -- glyphs are 8px tiles that only interlock on an integer grid, which is
  -- exactly why the old drawBoxNoGap had to math.ceil BOTTOM_H's fractional
  -- 6.5 tiles to stop the side border breaking with a gap; at pixel level
  -- 6.5 tiles is simply 52px and nothing needs rounding.  Takes TILE coords
  -- (like Font.drawBox, and like Screen:pos's own return), converts once.
  local function drawNativeFrame(tx, ty, tw, th)
    local r, g, b, a = love.graphics.getColor()
    local x0, y0 = tx * 8, ty * 8
    local w, h = tw * 8, th * 8
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x0, y0, w, h)
    love.graphics.setColor(0, 0, 0, 1)
    -- Top band: 1px outer line, then the 2px inner line.
    love.graphics.rectangle("fill", x0 + 4, y0 + 2, w - 9, 1)
    love.graphics.rectangle("fill", x0 + 5, y0 + 4, w - 11, 1)
    love.graphics.rectangle("fill", x0 + 4, y0 + 5, w - 9, 1)
    -- Bottom band: the same tile drawn unflipped -- 2px outer, 1px inner.
    love.graphics.rectangle("fill", x0 + 3, y0 + h - 4, w - 7, 1)
    love.graphics.rectangle("fill", x0 + 4, y0 + h - 3, w - 9, 1)
    love.graphics.rectangle("fill", x0 + 5, y0 + h - 6, w - 11, 1)
    -- Left pair (the v tile at its own column).
    love.graphics.rectangle("fill", x0 + 2, y0 + 4, 1, h - 8)
    love.graphics.rectangle("fill", x0 + 4, y0 + 5, 1, h - 11)
    -- Right pair: the same unflipped v tile, so 1px further in.
    love.graphics.rectangle("fill", x0 + w - 4, y0 + 4, 1, h - 8)
    love.graphics.rectangle("fill", x0 + w - 6, y0 + 5, 1, h - 11)
    -- Top corners' stepped rounding + inner nub.  The bottom corners have no
    -- nub: the bl/br tiles are not vertical mirrors of tl/tr (the cart's own
    -- asymmetry), so the bottom is a clean 1px step.
    for _, c in ipairs({
      { x0 + 3, y0 + 3 }, { x0 + w - 5, y0 + 3 },
      { x0 + 3, y0 + h - 5 }, { x0 + w - 5, y0 + h - 5 },
      { x0 + 5, y0 + 6 }, { x0 + w - 7, y0 + 6 },
    }) do
      love.graphics.rectangle("fill", c[1], c[2], 1, 1)
    end
    love.graphics.setColor(r, g, b, a)
  end

  -- The menu window's own left edge, drawn OVER the message box the way the
  -- cart stacks the two: BattleState:drawBottom draws Chrome.box(0, 12,
  -- 20+ox, 6) for the whole bottom and then the menu window straight over
  -- its right end, so the pair reads as ONE box with a divider instead of
  -- two boxes butted together.  That doubled border -- F's right edge and
  -- E's left edge running a couple of pixels apart -- was the most visible
  -- way the old pair stopped looking native.
  --
  -- Verticals only: the horizontal lines belong to the bottom box; the menu
  -- window's own tl/bl tiles add just the 1px corner step and the inner nub
  -- at each end (the four single cells below), which is the little notch the
  -- cart shows where the window edge meets the border.
  --
  -- Takes TILE coords, like drawNativeFrame above.
  local function drawNativeDivider(tx, ty, th)
    local r, g, b, a = love.graphics.getColor()
    local x0, y0 = tx * 8, ty * 8
    local h = th * 8
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", x0 + 2, y0 + 4, 1, h - 8)
    love.graphics.rectangle("fill", x0 + 4, y0 + 5, 1, h - 11)
    love.graphics.rectangle("fill", x0 + 3, y0 + 3, 1, 1)
    love.graphics.rectangle("fill", x0 + 3, y0 + h - 5, 1, 1)
    love.graphics.rectangle("fill", x0 + 5, y0 + 6, 1, 1)
    love.graphics.setColor(r, g, b, a)
  end

  -- Run `fn` with BattleHud's tile draws keyed instead of plain.
  --
  -- Every BattleHud draw goes through GbcPalette.with (the plain
  -- shade-substitution shader), whose output keeps shade 0 -- the white the
  -- HUD tiles carry as their cell background -- fully opaque. With the
  -- readouts now sitting over the pokemon sprites, that white has to fall
  -- out and let the sprite through instead, which is exactly what
  -- GbcPalette.keyedWith does (its KEYED shader sends shade 0 to alpha 0).
  -- BattleHud does not expose a knob for choosing the keyed path, so the
  -- two entry points it calls through -- GbcPalette.with, the only one its
  -- drawTile uses -- are swapped for the duration of ONE hud draw and
  -- restored immediately. pcall-guarded and only when keyedWith is actually
  -- present, so an engine build without the keyed shader keeps the old
  -- opaque behaviour rather than erroring mid-battle.
  local function drawHudKeyed(fn)
    local G = GbcPalette
    if not (G and G.keyedWith) or G.with == G.keyedWith then return fn() end
    local plain = G.with
    G.with = G.keyedWith
    local ok, err = pcall(fn)
    G.with = plain
    if not ok then error(err, 0) end
  end

  -- FALLBACK ONLY (used when BattleHud cannot load the cart's tiles): the HP
  -- fill alone -- no black frame, no white backing rectangle --
  -- at a caller-chosen width rather than the cart's fixed 48px. Reuses
  -- HpBar.pixels/.palette/.colors for the real green/yellow/red state
  -- and RGB (ratio-based thresholds, so they're correct at any width),
  -- but draws just the coloured rectangle itself.
  local function drawHpFill(palettes, hp, maxHp, x, y, width, height)
    local canonicalPixels = HpBar.pixels(hp, maxHp)
    local _, fillColor = HpBar.colors(palettes, HpBar.palette(canonicalPixels))
    local hpVal, maxVal = math.max(0, hp or 0), math.max(0, maxHp or 0)
    local fillW = 0
    if hpVal > 0 and maxVal > 0 then
      fillW = math.max(1, math.min(width, math.floor(hpVal * width / maxVal)))
    end
    if fillW <= 0 then return end
    if fillColor then
      love.graphics.setColor(fillColor[1] / 255, fillColor[2] / 255, fillColor[3] / 255, 1)
    else
      love.graphics.setColor(0.2, 0.8, 0.2, 1)
    end
    love.graphics.rectangle("fill", x, y, fillW, height)
    love.graphics.setColor(0, 0, 0, 1)
  end

  -- The cart's <LV> level glyph: tile $6E of the battle-extra font page
  -- (Font.useBattleExtra swaps $60-$78 to that sheet -- Font.lua's own
  -- BATTLE_EXTRA_TILES note). Drawn as a CODE, not typed as text: the <LV>
  -- markup the native HUD prints is expanded by Chrome, not by Font, so a
  -- caller drawing the glyph itself has to place the tile.
  local LV_GLYPH = 0x6E

  -- PlaceNonFaintStatus's five tags, in the cart's own priority order (PSN,
  -- BRN, FRZ, PAR, SLP). Toxic is the poison bit worn harder and shares the
  -- PSN tag; confusion is a battle substatus and never reaches the HUD.
  -- Mirrors src/ui/gen2/BattleState.lua's own STATUS_TAGS table.
  local STATUS_TAGS = {
    poison = "PSN", toxic = "PSN", burn = "BRN",
    freeze = "FRZ", paralyze = "PAR", sleep = "SLP",
  }

  -- The text that stands where the level goes while a mon carries a major
  -- status, or nil for a healthy one. Reads this session's merged
  -- gen2Statuses record first (so a mod-registered status' own hudLabel
  -- wins), then the built-in Battle.STATUSES table; a record flagged
  -- `substatus` returns nil, exactly as BattleState:statusTag does.
  -- On Gen 1 the backend answers from the native Status registry's own
  -- label (`Status.hudLabelFor(data.statuses, "PSN")`), which is the same
  -- text the Gen 1 HUD prints.
  local function statusTag(mon, data)
    local status = mon and mon.status
    if not status then return nil end
    if not N.isGen2 then return N.statusLabel(mon, data) end
    local authored = N.statusesData(data) and N.statusesData(data)[status]
    local builtin = Battle.STATUSES and Battle.STATUSES[status]
    local record = authored or builtin
    if record and record.substatus then return nil end
    if authored then
      -- The merge's plain no-op register shares the built-in table object
      -- (the same identity BattleState checks): its label is still the raw
      -- marker and needs the lookup, while a mod's own record is already
      -- complete authored text and must not be looked up a second time.
      if authored == builtin then
        return Strings(authored.hudLabel or authored.label)
      end
      return authored.hudLabel or authored.label
    end
    local tag = STATUS_TAGS[status]
    return tag and Strings(tag) or nil
  end

  -- The exp bar's fill fraction: THIS level's share of the span between its
  -- own exp threshold and the next level's -- a share of the level's span,
  -- not of the mon's total experience (CalcExpBar, engine/battle/core.asm:
  -- 7555). Mirrored from BattleState:expPixels and computed off the same
  -- growth records Mon.gainExperience used, so the bar can never disagree
  -- with the level printed beside it.
  local function expFraction(mon, data)
    local def = data and data.pokemon and data.pokemon[Mon.partySpecies(mon)]
    local growth = Mon.growthFor(data, def and def.growthRate)
    if not growth then return 0 end
    local level = math.max(1, math.min(Mon.MAX_LEVEL, mon.level or 1))
    local base = Mon.experienceForLevel(growth, level)
    local nextExp = Mon.experienceForLevel(growth, level + 1)
    if not base or not nextExp or nextExp <= base then return 0 end
    local into = math.max(0, math.min(nextExp - base,
      N.monExp(mon) - base))
    return math.floor(into * BattleHud.EXP_LENGTH_PX / (nextExp - base))
      / BattleHud.EXP_LENGTH_PX
  end

  -- Drawn box height, tiles, BEFORE BOX_SCALE -- PER SIDE, because the cart's
  -- two HUDs are not the same height. The enemy readout is name + bar (two
  -- content rows); the player's carries the numeric HP on its own row under
  -- the bar AND the exp bar under that (four). The height still counts the
  -- two border tiles the box used to draw (one top, one bottom) so these
  -- constants -- and therefore every asset's position -- are unchanged now
  -- that the frame is gone: enemy 2 + 2 = 4; player 4 + 2 = 6.
  local GUI_BOX_H_ENEMY = 4
  local GUI_BOX_H_PLAYER = 6
  -- BOX_SCALE -- the readout's 47% shrink, anchored at the box's own
  -- top-left tile corner -- is declared up in the GUI placement block
  -- (just above GUI_BOX_W), because the centring maths there needs the
  -- readout's real drawn width; this group just reads that local.
  -- There is no per-side stack spacing any more: readouts are one box per
  -- slot now, laid out in a single spread row at one shared height (see
  -- drawContent's HUD pass).

  -- The compact name/level/gender/HP readout -- the cart's native assets
  -- only, with NO box frame around them: the black rule square that used
  -- to enclose them was removed, leaving just the tiles/text.
  -- The asset layout still starts one full 8px tile in from (tx,ty), the
  -- inset it had while Font.drawBox's border glyphs (a full tile at each
  -- edge, Font.lua:544-558) were still drawn, so no asset moved.
  --
  -- A fainted battler draws NOTHING here at all -- not even a readout
  -- -- rather than assets that still stand there reading FAINTED. That
  -- makes an empty slot genuinely read as empty, which matters most
  -- against an NPC trainer team where a downed mon sits out until the
  -- trainer sends the next one in.
  --
  -- `shownHp` is the DISPLAYED hit points -- Screen:shownHpOf's chasing
  -- value while a turn is being narrated, the live mon.hp otherwise (see
  -- Screen:stepHpAnim's own header). Everything hp-derived in here reads
  -- it rather than mon.hp: the bar's fill width, the bar's own green/
  -- yellow/red palette (native keys that to the DISPLAYED bar too, for
  -- the same reason -- src/ui/gen2/BattleState.lua:1161), the numeric
  -- readout, AND the empty-slot test above. That last one matters: the
  -- whole turn's damage is already committed to the real mons before the
  -- first line of text shows (Screen:advanceResolving), so testing
  -- mon.hp made a fainted battler's box wink out before its own "X
  -- fainted!" line had even been announced.
  --
  -- The readout is now the cart's own assets, imported one element at a
  -- time into this scene's box rather than the whole native screen:
  --   Line 1: name (shrunk to fit -- see drawScaledText/fitName), then the
  --     native level readout -- the <LV> tile + the digits, or the status
  --     tag in its place while a mon is statused -- then the gender glyph.
  --   Line 2: the native HP bar (the "HP:" badge, six cells, end cap),
  --     coloured off the DISPLAYED HP.
  --   Line 3 (player only, showNumeric=true): the numeric current/max,
  --     right-aligned, as the cart prints it under the bar.
  --   Line 4 (player only): the native exp bar, grown from the right.
  -- For the enemy that is name + bar only -- the numeric and exp bar are
  -- deliberately withheld (showNumeric=false), matching every real Pokemon
  -- game's own enemy HUD.
  -- anchorRight=true shrinks toward the box's own TOP-RIGHT corner
  -- instead of its top-left -- needed so a right-aligned box's rendered
  -- right edge lands exactly at (tx+tw)*8 regardless of BOX_SCALE,
  -- matching another unscaled box's edge at that same tile position
  -- (e.g. the player GUI column lining up with E's own right edge).
  -- Anchoring at top-left instead would shrink the box back toward tx,
  -- leaving its right edge short of the target -- confirmed live as
  -- exactly why the two didn't line up before this fix.
  -- sizeMul: a plain multiplier on BOX_SCALE (1.0 = default; applied on
  -- top of BOX_SCALE, not instead of it, so the box's own established
  -- 47%-shrink baseline is unchanged when sizeMul is left at 1.0).
  -- `th` is the box's own drawn height in tiles (GUI_BOX_H_ENEMY/_PLAYER --
  -- the caller picks, since the two sides differ); `hud` is the screen's
  -- BattleHud instance, which supplies the native tiles and falls back to
  -- the plain coloured fill when a dataset cannot load them.
  local function drawGuiBox(tx, ty, tw, th, battler, data, showNumeric, anchorRight, sizeMul, shownHp, hud)
    local mon = battler and battler.mon
    if not mon then return end
    -- `battler.caught` is still checked by name (Screen:throwBall sets it
    -- alongside .fainted on a mon that was caught at full health, so
    -- "is its bar empty" would not catch that case), but .fainted itself
    -- deliberately is not: it is set the instant resolution finishes,
    -- which is exactly the beat this whole change exists to stop
    -- trusting.
    if battler.caught then return end
    if shownHp == nil then shownHp = mon.hp or 0 end
    if shownHp <= 0 then return end

    local effectiveScale = BOX_SCALE * (sizeMul or 1)
    local anchorX = anchorRight and ((tx + tw) * 8) or (tx * 8)
    love.graphics.push()
    love.graphics.translate(anchorX, ty * 8)
    love.graphics.scale(effectiveScale, effectiveScale)
    love.graphics.translate(-anchorX, -ty * 8)

    -- No frame at all any more: the readout is just its native assets now.
    -- The black rule square that used to enclose them (drawn border-only,
    -- with Font.drawBox's white fill already skipped) was removed so the
    -- mon shows through completely. The asset offsets below keep the
    -- one-tile inset they had while the frame existed, so nothing moved.
    love.graphics.setColor(0, 0, 0, 1)

    -- The cart's stat glyphs -- the <LV> tile and the HP/exp bar cells --
    -- live in the battle-extra font page, so every native draw below happens
    -- with that page swapped in, then swapped back. This is exactly how the
    -- native HUD brackets its own draws (BattleState:drawEnemyHud's
    -- Font.useBattleExtra(true) ... (wasBattle)). Ordinary letters sit
    -- outside the swapped $60-$78 range, so the name is unaffected.
    local wasBattleExtra = Font.useBattleExtra(true)
    local hudReady = hud and hud:available()

    local NAME_SCALE = 0.75
    local interiorL = (tx + 1) * 8
    local interiorR = (tx + tw - 1) * 8
    local interiorW = interiorR - interiorL
    local rowY = (ty + 1) * 8

    -- Line 1: the name, then the native level readout -- the cart's own <LV>
    -- tile followed by the digits -- then the gender glyph. A statused mon
    -- prints the 3-letter tag where the level goes and drops the level
    -- entirely, matching PlaceNonFaintStatus / DrawEnemyHUD's skip_level arm.
    -- The <LV> tile is one 8px glyph, so the suffix's own advance is (tile +
    -- digits + gender) at NAME_SCALE; fitName shrinks the name against
    -- exactly that, so a long name can never strike through the level
    -- readout or the box's right border.
    local tag = statusTag(mon, data)
    local lvText = tag or tostring(mon.level or 0)
    local gender = GENDER_SYMBOL[mon.gender] or ""
    local lvW = (tag and 0 or 8) + Font.width(lvText) + Font.width(gender)
    -- fitName measures in the SAME units it is given: maxWidth is the
    -- interior converted back to native px (divide by NAME_SCALE), so the
    -- suffix it subtracts must be native px too -- NOT pre-scaled, or a long
    -- name would look like it fits and then push the level past the border.
    local name = fitName(displayName(mon), interiorW / NAME_SCALE,
      lvW + 4)
    drawScaledText(name, interiorL + 2, rowY + 1, NAME_SCALE)
    local penX = interiorL + 2 + (Font.width(name) + 4) * NAME_SCALE
    if not tag then
      drawScaledCode(LV_GLYPH, penX, rowY + 1, NAME_SCALE)
      penX = penX + 8 * NAME_SCALE
    end
    drawScaledText(lvText, penX, rowY + 1, NAME_SCALE)
    penX = penX + Font.width(lvText) * NAME_SCALE
    drawScaledText(gender, penX, rowY + 1, NAME_SCALE)

    -- Line 2: the HP bar -- the cart's own assembly, coloured through the
    -- hpBar palette for the displayed HP's green/yellow/red state, so it
    -- matches every native bar exactly. Falls back to the plain coloured
    -- fill only when the menu gfx cannot supply the tiles.
    local palettes = N.paletteData(data)
    if hudReady then
      -- Keyed (shade 0 transparent) so the mon behind the readout shows
      -- through the bar's own cell backgrounds -- see drawHudKeyed.
      drawHudKeyed(function()
        hud:drawHpBar(shownHp, maxHpOf(mon), tx + 1, ty + 2)
      end)
    elseif palettes then
      drawHpFill(palettes, shownHp, maxHpOf(mon), interiorL, rowY + 10,
        interiorW, 3)
    end

    if showNumeric then
      -- Line 3: current/max, right-aligned to the interior's own right edge,
      -- under the bar -- where the cart prints it.
      local label = string.format("%d/%d", shownHp, maxHpOf(mon))
      drawScaledText(label, interiorR - 2 - Font.width(label) * 0.75,
        rowY + 16, 0.75)

      -- Line 4: the exp bar, grown from the right exactly as FillInExpBar
      -- does. The fraction is this level's share of the span to the next
      -- level (see expFraction), so the bar agrees with the level shown.
      if hudReady then
        drawHudKeyed(function()
          hud:drawExpBar(expFraction(mon, data), tx + 1, ty + 4)
        end)
      end
    end

    Font.useBattleExtra(wasBattleExtra)
    love.graphics.pop()
  end

  function Screen.new(game, world, payload, combat, gameData, battle, g9dex)
    local self = setmetatable({}, Screen)
    self.game = game
    self.world = world
    self.combat = combat
    self.data = gameData
    -- The cart's own battle HUD, built over this session's menu gfx/palettes
    -- -- it caches the tile sheets and answers :available() so drawGuiBox can
    -- fall back to the plain coloured HP fill on a dataset that cannot supply
    -- them. One instance per battle, matching native (BattleState's own hud).
    self.hud = BattleHud.new(N.menuGfxData(self.data),
      N.paletteData(self.data))
    -- The real native Battle instance and the g9-battle-engine mod
    -- reference -- both required for every turn's resolution now (see
    -- Combat.resolveTurn). Constructed by pushDoubleBattleScreen, not
    -- here, since building one needs game.save/game.data before this
    -- constructor's own arguments are assembled.
    self.battle = battle
    self.g9dex = g9dex
    -- Read fresh from this mod's own active layout preset (layouts.lua)
    -- rather than baked in -- see that file's own header for the preset
    -- file shape/naming and how the active one is chosen. Read up here,
    -- before the roster loops, because the preset's own enemyCount is
    -- what decides how many enemies are actually OUT (see below).
    local activeLayout = mod.exports.getActiveLayoutData and mod.exports.getActiveLayoutData()
    self.layout = (activeLayout and activeLayout.layout) or {}
    -- Grid exceptions, read from the preset: `boss` puts the lone enemy at
    -- column e5 (col 5) and gives it a BOSS_MUL-tall slot; `horde` puts a
    -- lone ally at a2 (col 2).
    self.isBoss = (activeLayout and activeLayout.boss) and true or false
    self.isHorde = (activeLayout and activeLayout.horde) and true or false
    -- THIS battle's sprite scale, PER SIDE, from the preset's own optional
    -- `spriteScaleFront` / `spriteScaleBack` override (or the legacy single
    -- `spriteScale`, which sets both), else this file's own defaults -- read
    -- once here and threaded into every drawSprite call. Each side is then
    -- drawn at its own scale x its OWN pixels, so relative sizes within a
    -- side are preserved while the two teams resize independently.
    local legacyScale = tonumber(activeLayout and activeLayout.spriteScale)
    self.spriteScaleFront = tonumber(activeLayout and activeLayout.spriteScaleFront)
      or legacyScale or SPRITE_SCALE_FRONT
    self.spriteScaleBack = tonumber(activeLayout and activeLayout.spriteScaleBack)
      or legacyScale or SPRITE_SCALE_BACK
    -- Looped, not hardcoded to exactly 2 -- combat.lua's own logic
    -- (isAlive/chooseAiAction/orderActions/sideDefeated/etc) already
    -- just iterates these arrays with ipairs, so rendering (drawContent,
    -- below) is written the same N-agnostic way rather than assuming a
    -- fixed pair.
    --
    -- A TRAINER's roster can be longer than the preset's own enemyCount
    -- -- its "how many enemies this formation actually stands on the
    -- field" field (bossFight = 1 for its 4v1, doubles = 2, triples = 3).
    -- Anything past that is the enemy BENCH, held back here and pulled in
    -- one at a time as an active slot faints (Screen:
    -- advanceEnemyReplacement). Because every draw, target and turn-order
    -- path on this screen reads self.enemyBattlers and nothing else, a
    -- benched boss is never drawn, never selectable as a target and never
    -- takes a turn -- a two-Pokemon bossFight puts exactly ONE boss out at
    -- a time instead of stacking both. A WILD fight (or a preset that
    -- declares no enemyCount) keeps every enemy active, exactly as
    -- before: there is no trainer to send a replacement, so benching one
    -- would make a multi-enemy wild impossible to finish.
    self.enemyBattlers = {}
    self.enemyBench = {}
    local roster = payload.enemies or {}
    local enemyCap = #roster
    if type(payload.trainer) == "table" then
      local declared = tonumber(activeLayout and activeLayout.enemyCount)
      if declared and declared >= 1 and declared < enemyCap then enemyCap = declared end
    end
    for i = 1, #roster do
      if i <= enemyCap then
        self.enemyBattlers[#self.enemyBattlers + 1] = combat.newBattler(roster[i], "enemy")
      else
        self.enemyBench[#self.enemyBench + 1] = roster[i]
      end
    end
    self.playerBattlers = {}
    for i, mon in ipairs(payload.players) do
      self.playerBattlers[i] = combat.newBattler(mon, "player")
    end
    self.message = nil
    -- Kept for anything reading it, though the 1.5x trainer EXP bonus
    -- itself now comes free from battle:awardExperience -- it reads the
    -- real Battle instance's own opts.trainer (see buildBattle), not
    -- this flag.
    self.isTrainerBattle = payload.trainer ~= nil and payload.trainer ~= false
    -- The raw payload.trainer, kept for the intro/outro narration
    -- ("{TRAINER} wants to battle!", "You defeated {TRAINER}!") -- nil for
    -- a wild fight, true for a legacy nameless trainer, else the real
    -- trainer table (buildBattle's own header documents its shape).
    self.trainerData = payload.trainer
    -- The turn's events, whole tables, NOT just their .text -- see
    -- Screen:advanceResolving for why the rest of each event now matters.
    self.pendingEvents = {}
    -- The chasing HP the HUD actually draws, keyed by the real mon table
    -- (see Screen:snapshotHp for why the mon and not the battler and not
    -- the side). Screen:shownHpOf reads it; Screen:stepHpAnim walks it.
    self.shownHp = {}
    self.hpAnim = nil
    -- Damage Numbers (option-gated by g9-battle-engine's
    -- "damage_numbers" option -- see Screen:spawnDmgNumber): a short list
    -- of { mon, text, color, t } floating HP-change labels. Emptied and
    -- never touched when the option is off.
    self.dmgNumbers = {}
    -- E menu (FIGHT/BAG/PKMN/RUN[/custom]) layout mode + optional 5th
    -- button, read fresh from this mod's own settings.lua at its root
    -- (loadSettingsFile's own header). menuOrder is the LIST-mode item
    -- order only -- grid/cross modes use GRID2_ROWS/CROSS_SLOTS instead,
    -- both module-level and unaffected by this setting.
    local settings = loadSettingsFile()
    self.menuLayout = (settings.menuLayout == "grid") and "grid" or "list"
    self.customButtonLabel = (type(settings.customButtonLabel) == "string"
      and settings.customButtonLabel ~= "") and settings.customButtonLabel or nil
    self.menuOrder = { "FIGHT", "BAG", "PKMN", "RUN" }
    if self.customButtonLabel then self.menuOrder[#self.menuOrder + 1] = "CUSTOM" end
    -- SWITCH -- the positional ally swap -- is a LAYOUT capability, not a
    -- per-turn one: it exists only where there is another living ally to
    -- trade places with (two or more allies on the field) and the
    -- bossFight preset turns it off outright, its four allies
    -- notwithstanding. Decided once here, from the roster the preset
    -- actually shipped, and read by every menu/layout path below so the
    -- button can never appear where the swap has no meaning.
    local livingAllies = 0
    for _, b in ipairs(self.playerBattlers) do
      if self.combat.isAlive(b) then livingAllies = livingAllies + 1 end
    end
    self.swapEnabled = (not self.isBoss) and livingAllies >= 2
    if self.swapEnabled then table.insert(self.menuOrder, 2, "SWITCH") end
    -- The E-cell layout tables this screen draws/navigates (grid/cross
    -- modes; list mode reads self.menuOrder directly). Built per screen
    -- because the SWITCH cell is conditional; the shared module constants
    -- stay the no-SWITCH shapes so existing behaviour is untouched.
    if self.menuLayout == "grid" then
      if self.customButtonLabel then
        self.crossSlots = self.swapEnabled and CROSS_SLOTS_SW or CROSS_SLOTS
      else
        self.gridRows = self.swapEnabled and GRID2_ROWS_SW or GRID2_ROWS
      end
    end
    -- Battlers that own a queued (not yet resolved) positional swap, kept
    -- so the field can keep showing WHO is behind each swap after the
    -- target has been picked (a frame arrow, drawSwapMark). Cleared every
    -- turn and as each swap resolves.
    self.swapOwnerMarks = {}
    -- FORMS ownership (see the GIMMICK SELECT section's own FORMS OWNER
    -- block): the player battler whose action menu the CUSTOM/FORMS cell was
    -- opened from, and the transform it confirmed. Kept here, not on
    -- battle_forms' own arm state -- that state records WHICH mechanic is
    -- armed and nothing about WHO armed it, because its native cell has only
    -- one battler to be about. Cleared each turn (Screen:beginTurn) and after
    -- the turn_started activation, so a stale owner can never fire.
    self.gimmickActorMon = nil
    self.gimmickActorSlot = nil
    self.gimmickOwnerMon = nil
    self.gimmickOwnerSlot = nil
    self.gimmickOwnerId = nil
    self.gimmickOwnerLabel = nil
    -- Move-animation state: spriteAnchor is filled in every drawContent
    -- pass (see drawSprite's own return value) with each battler's real
    -- on-screen bottom-center this frame -- Screen:startMoveAnim reads
    -- it to anchor an animation at wherever a sprite ACTUALLY is, not a
    -- guessed position. moveAnim is nil when nothing is playing.
    self.spriteAnchor = {}
    self.moveAnim = nil
    self:installEventProbe()
    -- Real vanilla entry sequence: narration lines ("Wild X appeared!"
    -- / "{TRAINER} wants to battle!" + sent-out lines), then "Go! P!"
    -- per player battler thrown from a pokeball, and only then the first
    -- action menu. A battle with no narration at all (no enemies?) skips
    -- straight to the menu.
    -- Trainer-intro state (native-faithful order): in a TRAINER battle
    -- both trainer pics stand in their slots while "{TRAINER} wants to
    -- battle!" reads, the enemy trainer's class front-pic slides off
    -- right before each enemy mon is sent out (thrown from a pokeball),
    -- the player trainer's back-pic slides off left before each "Go! P!"
    -- (also a pokeball throw), and only then do the mons' own sprites/
    -- HUDs exist. In a WILD battle there is no enemy trainer -- each
    -- wild mon fades in place at its final sprite position (invisible ->
    -- visible), and the player back-pic leads (native's
    -- BattleIntroSlidingPics).
    -- enemyRevealed/playerRevealed gate each slot's sprite AND HUD box
    -- (both hidden until that mon is actually sent out); reveal flags
    -- are read by drawContent and set by advanceIntro's beats / the
    -- entrance clocks' completion.
    self.showPlayerTrainer = false
    self.showEnemyTrainer = false
    self.playerTrainerImage = nil
    self.enemyTrainerImage = nil
    -- The pics' colour data, filled in by resolveTrainerArt below (a
    -- TrainerPalettes row + a trueColor flag per pic -- see drawRawImage).
    self.playerTrainerColors = nil
    self.enemyTrainerColors = nil
    self.playerTrainerTrueColor = false
    self.enemyTrainerTrueColor = false
    self.trainerSlide = nil
    self.backpicSlide = nil
    self.enemyRevealed = {}
    self.playerRevealed = {}
    self:resolveTrainerArt()
    -- WILD mons are NOT pre-revealed: their "fade" intro beat leaves each
    -- one in place at its final sprite position and fades its sprite from
    -- invisible to visible (see buildIntroSequence), which is what gates
    -- sprite AND HUD until the fade completes.
    self.introSequence = self:buildIntroSequence()
    self.introIdx = 0
    self.ballThrow = nil
    self.wildFade = nil
    self.outroT = nil
    if #self.introSequence > 0 then
      self.phase = "intro"
      self:advanceIntro()
    else
      self:finishIntro()
    end
    return self
  end

  ------------------------------------------------------------------
  -- TURN PACING -- the display lags the resolution
  --
  -- The engine mod owns turn resolution and resolves the WHOLE turn in
  -- one call (Combat.resolveTurn -> g9-battle-engine's
  -- mod.exports.resolveTurnActions, combat/turn_order.lua:298), so every
  -- hit point this turn will ever cost is already gone from the real mon
  -- tables before a single line of text is on screen. Nothing below
  -- changes that -- splitting resolution per action is the ENGINE mod's
  -- contract to change, not this one's, and the honest cost of faking it
  -- from here (re-deriving priority/Speed/Trick Room/RNG order to feed
  -- resolveTurnActions one actor at a time) is a second, silently
  -- diverging copy of the exact math turn_order.lua's own header spends
  -- fifty lines explaining why nobody should write. Rejected.
  --
  -- What changes instead is the DISPLAY: the HUD chases the real numbers
  -- one narrated step at a time, which is what the cart does anyway.
  -- native's own Gen 2 screen is built exactly this way and says so --
  -- "The engine has already finished the whole turn's math by the time
  -- the first message shows, so drawing mon.hp directly would spoil
  -- every hit before its own line ran" (src/ui/gen2/BattleState.lua:435-
  -- 440). This is that same shownHp chase, widened from two fixed sides
  -- to an arbitrary roster.
  --
  -- ATTRIBUTION, the part that is not just a port. native keys its chase
  -- off event.side, which cannot work here: Battle:sideOf is the hard
  -- binary `(mon == self.player) and "player" or "enemy"`
  -- (src/battle/gen2/Battle.lua:447-449), so in a bossFight (layouts/
  -- bossFight.lua, allyCount = 4) every battler that is not literally
  -- battle.player is tagged "enemy" and all four player bars would chase
  -- one number. The engine mod hit the identical wall on the Speed side
  -- and documented it (combat/turn_order.lua:258-272, "sideOf is a hard
  -- binary ... corrupting stat-stage boosts across unrelated battlers").
  -- Damage/heal events carry `hp` but no mon reference at all
  -- (Battle.lua:1267-1271, :1327-1328), so there is nothing on the event
  -- to key on and no repair to make short of patching the engine.
  --
  -- So this does not try to attribute anything. It records, at the
  -- moment each event is EMITTED -- which is the moment its own hit
  -- point cost has just landed and nothing after it has -- a snapshot of
  -- every roster mon's hp. Attribution becomes unnecessary: the display
  -- replays the whole HP vector, and whichever bars moved between one
  -- event and the next are exactly the bars that animate. A spread move
  -- that hits three battlers drains three bars at once, correctly, with
  -- no per-event side tag existing anywhere.
  --
  -- Keyed by the real mon TABLE, not the battler wrapper: a switch
  -- replaces self.playerBattlers[slot] with a brand new wrapper
  -- (Screen:advanceResolving), so wrapper identity does not survive a
  -- turn, while a mon table does.
  ------------------------------------------------------------------

  -- Every roster mon's hp, right now. Cheap enough to run per emitted
  -- event: a turn emits tens of events and a roster is at most a
  -- handful of mons.
  function Screen:snapshotHp()
    local snap = {}
    for _, b in ipairs(self.enemyBattlers) do
      if b.mon then snap[b.mon] = b.mon.hp or 0 end
    end
    for _, b in ipairs(self.playerBattlers) do
      if b.mon then snap[b.mon] = b.mon.hp or 0 end
    end
    return snap
  end

  -- Shadows Battle:emit (Battle.lua:404-407) on THIS ONE INSTANCE only:
  -- assigning the field raw on the battle table wins over the class
  -- method the metatable would otherwise reach, so the shared engine
  -- file is untouched and every other Battle in the process is
  -- unaffected -- the same instance-only override technique
  -- Screen:startMoveAnim already uses on an AnimRunner's object pool.
  -- Safe to do blind: every event this mod ever sees goes through
  -- battle:emit, confirmed by direct read of both the engine
  -- (Battle.lua) and g9-battle-engine (its combat/ and abilities/
  -- files call battle:emit / self:emit and never push to battle.events
  -- themselves), and nothing on either side reassigns battle.emit.
  --
  -- Also carries the attacker/defender through: Battle:useMove is where
  -- the engine mod drives every action (turn_order.lua:325) and its
  -- signature is (attacker, defender, moveId), so wrapping it names the
  -- two battlers every event emitted underneath it belongs to. That is
  -- the identity `side` cannot give -- used by Screen:startMoveAnimFor
  -- to point a move animation at the right pair of sprites in a 4v1.
  function Screen:installEventProbe()
    local battle = self.battle
    if not battle or self.eventProbeInstalled then return end
    self.eventProbeInstalled = true
    local screen = self
    local baseEmit = battle.emit
    if type(baseEmit) == "function" then
      battle.emit = function(b, event)
        if type(event) == "table" then
          -- Never overwrite: an event handed back through emit twice
          -- (nothing does today) must keep its FIRST, earliest snapshot.
          if event.g9SceneHp == nil then event.g9SceneHp = screen:snapshotHp() end
          if event.g9SceneActor == nil then
            event.g9SceneActor = screen.probeAttacker
            event.g9SceneTarget = screen.probeDefender
          end
        end
        return baseEmit(b, event)
      end
    end
    local baseUseMove = battle.useMove
    if type(baseUseMove) == "function" then
      battle.useMove = function(b, attacker, defender, moveId, ...)
        local prevA, prevD = screen.probeAttacker, screen.probeDefender
        screen.probeAttacker, screen.probeDefender = attacker, defender
        -- pcall'd so a raise inside the engine's own pipeline cannot
        -- leave the probe pointing at a stale pair for the rest of the
        -- battle; the error is re-raised unchanged afterward. Safe to
        -- wrap in a pcall specifically because nothing under useMove
        -- yields -- checked, not assumed: neither src/battle/gen2/
        -- Battle.lua nor g9-battle-engine's combat/ uses coroutines
        -- at all (switch_primitives.lua's own header explains why the
        -- one place that wanted to could not).
        local ok, a, bb, c = pcall(baseUseMove, b, attacker, defender, moveId, ...)
        screen.probeAttacker, screen.probeDefender = prevA, prevD
        if not ok then error(a, 0) end
        return a, bb, c
      end
    end
  end

  -- The battler wrapper standing on a given mon table, or nil. Linear
  -- over a roster that is never more than a handful long.
  function Screen:battlerFor(mon)
    if not mon then return nil end
    for _, b in ipairs(self.playerBattlers) do
      if b.mon == mon then return b end
    end
    for _, b in ipairs(self.enemyBattlers) do
      if b.mon == mon then return b end
    end
    return nil
  end

  -- What the HUD draws for `mon`. Only the resolving phase lags: outside
  -- it nothing is being narrated, so the live value is the honest one --
  -- and it also means a Potion thrown from the BAG, a catch, or a switch
  -- (all of which move hp with no event behind them) shows immediately
  -- instead of needing its own snapshot plumbing.
  function Screen:shownHpOf(mon)
    if not mon then return 0 end
    if self.phase ~= "resolving" then return mon.hp or 0 end
    local shown = self.shownHp[mon]
    if shown == nil then return mon.hp or 0 end
    return shown
  end

  -- Seeds the chase from the live roster -- called once, at the top of a
  -- resolution pass, BEFORE any of this turn's math has run.
  function Screen:syncShownHp()
    self.shownHp = {}
    self.hpAnim = nil
    self.hpAnimHolds = false
    for mon, hp in pairs(self:snapshotHp()) do self.shownHp[mon] = hp end
  end

  -- Points the chase at `snapshot` (an event's g9SceneHp). A mon the
  -- chase has never seen -- switched in mid-turn by a U-turn/Roar the
  -- engine drove itself -- snaps rather than sliding in from a value
  -- that was never on screen, the same way native snaps a bar on `send`
  -- (src/ui/gen2/BattleState.lua:1545-1547).
  function Screen:armHpAnim(snapshot)
    if type(snapshot) ~= "table" then return end
    local pending = nil
    for mon, hp in pairs(snapshot) do
      if self.shownHp[mon] == nil then
        self.shownHp[mon] = hp
      elseif self.shownHp[mon] ~= hp then
        -- A bar the chase has already seen is moving: the signed
        -- difference IS this event's HP change, so spawn a floating
        -- number for it (a no-op unless the engine's damage-numbers
        -- option is on -- see Screen:spawnDmgNumber).
        self:spawnDmgNumber(mon, hp - self.shownHp[mon])
        pending = pending or {}
        pending[mon] = hp
      end
    end
    self.hpAnim = pending
  end

  -- One frame of the chase, over every bar at once.
  --
  -- Step size is the cart's own, per mon: under 48 max HP the bar moves
  -- one hit point a frame (_AnimateHPBar's ShortAnim_UpdateVariables);
  -- from 48 up it moves one PIXEL a frame, i.e. maxHp/48 hit points
  -- (LongAnim_UpdateVariables) -- engine/battle/anim_hp_bar.asm:42-82,
  -- ported here off src/ui/gen2/BattleState.lua:1013-1039 rather than
  -- reinvented as a seconds-based lerp, so a bar drains at exactly the
  -- rate the native screen drains it at. Screen:update, like
  -- BattleState:update(_dt) (:2113), ignores dt and runs once a frame,
  -- so "a frame" means the same thing on both screens.
  --
  -- Widened from native's single anim.side to every mon with a pending
  -- target, because a spread move legitimately drains several bars in
  -- the same beat here and there is no reason to serialize them.
  --
  -- Returns true while it still had work, so the caller can hold the
  -- message queue the way AnimateHPBar's own loop holds the cart
  -- (BattleState.lua:2183-2185).
  function Screen:stepHpAnim()
    local pending = self.hpAnim
    if not pending then return false end
    local moved, remaining = false, false
    for mon, target in pairs(pending) do
      local shown = self.shownHp[mon]
      if shown == nil then
        self.shownHp[mon] = target
      elseif shown ~= target then
        local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
        local step = 1
        if maxHp >= HpBar.LENGTH_PX then
          step = math.max(1, math.ceil(maxHp / HpBar.LENGTH_PX))
        end
        if shown < target then
          shown = math.min(target, shown + step)
        else
          shown = math.max(target, shown - step)
        end
        self.shownHp[mon] = shown
        moved = true
        if shown ~= target then remaining = true end
      end
    end
    -- Cleared on the same frame the last hit point lands, so the hold
    -- ends the instant the bars are honest again. Every walk above is a
    -- clamped integer step of at least 1 toward a fixed target, so this
    -- always terminates -- the chase cannot stall a battle even if an
    -- event ever carried a nonsense number.
    if not remaining then self.hpAnim = nil end
    return moved
  end

  -- The escape hatch. Anything that can hold the queue has to be
  -- skippable, or a bad snapshot is a hung battle with no way out --
  -- so A/B during a drain finishes it on the spot instead of being
  -- swallowed.
  function Screen:snapHpAnim()
    local pending = self.hpAnim
    if not pending then return end
    for mon, target in pairs(pending) do self.shownHp[mon] = target end
    self.hpAnim = nil
  end

  ------------------------------------------------------------------
  -- DAMAGE NUMBERS (round 105). The engine option
  -- g9-battle-engine's "damage_numbers" is exposed to this screen
  -- as g9dex.exports.damageNumbersEnabled(); when it is on, every HP
  -- change the resolution pass reveals gets a floating label over that
  -- mon's own HP bar -- a red "-N" for damage taken, a green "+N" for
  -- HP recovered. The value is the signed change between the bar's
  -- current displayed value and the event's own HP snapshot
  -- (Screen:armHpAnim computes exactly that delta for the chase), so
  -- nothing extra has to be sent across: the engine already stamps every
  -- emitted event with this screen's full HP vector (event.g9SceneHp,
  -- Screen:installEventProbe), which is the same source the bars chase.
  -- Each label lives DMG_NUMBER_LIFE seconds and fades linearly to
  -- invisible over that time (alpha 1 -> 0).
  ------------------------------------------------------------------
  local DMG_NUMBER_LIFE = 1.0
  local DMG_NUMBER_DAMAGE = { 0.85, 0.13, 0.13 }
  local DMG_NUMBER_HEAL = { 0.10, 0.65, 0.18 }

  function Screen:damageNumbersEnabled()
    local eng = self.g9dex and self.g9dex.exports
    local fn = eng and eng.damageNumbersEnabled
    return type(fn) == "function" and fn() == true
  end

  -- Spawns one floating label for `delta` hp on `mon` (negative = damage
  -- taken, positive = recovered); a no-op for a zero delta, a missing
  -- mon, or when the engine option is off.
  function Screen:spawnDmgNumber(mon, delta)
    if not mon or not delta or delta == 0 then return end
    if not self:damageNumbersEnabled() then return end
    local list = self.dmgNumbers
    if not list then list = {}; self.dmgNumbers = list end
    local damage = delta < 0
    list[#list + 1] = {
      mon = mon,
      text = (damage and "-" or "+") .. tostring(math.abs(delta)),
      color = damage and DMG_NUMBER_DAMAGE or DMG_NUMBER_HEAL,
      t = 0,
    }
  end

  -- Ages every live label; drops the ones that have finished fading.
  -- dt is the real frame delta Screen:update is handed.
  function Screen:stepDmgNumbers(dt)
    local list = self.dmgNumbers
    if not list or #list == 0 then return end
    local step = dt or 0
    for i = #list, 1, -1 do
      local e = list[i]
      e.t = e.t + step
      if e.t >= DMG_NUMBER_LIFE then table.remove(list, i) end
    end
  end

  -- Draws every live label under its own mon's readout box, centred on the
  -- HP bar's own fill channel (the 6 cells, 48px wide, whose centre sits 48
  -- box-local px in from the box's left edge), at the HP-bar font's own
  -- size (the numeric readout in drawGuiBox is drawn at 0.75 inside the
  -- 0.47-scaled box, so 0.75 * BOX_SCALE * sizeMul here matches it exactly)
  -- and fading out. The y is the readout box's own EMPTY bottom band (7px
  -- above its bottom edge): the bar's fill cells end 24px down, so the label
  -- sits under the bar without ever superimposing the bar, the numeric
  -- current/max readout or the exp bar. pcall'd end-to-end: a malformed
  -- entry must never take the battle down, it just clears the list.
  function Screen:drawDmgNumbers()
    local list = self.dmgNumbers
    if not list or #list == 0 or not self.hudMark then return end
    local ok = pcall(function()
      for i = 1, #list do
        local e = list[i]
        local battler = self:battlerFor(e.mon)
        local mark = battler and self.hudMark[battler]
        if mark and mark.visible and mark.left and mark.gs and mark.top then
          local eff = BOX_SCALE * mark.gs
          local scale = eff * 0.75
          local cx = mark.left + 48 * eff
          -- box height per side (enemy 4 tiles, player 6); sit the label in
          -- the box's own empty bottom band, 7px above its lower edge.
          local h = mark.h or 32
          local y = mark.top + (h - 7) * eff
          local alpha = math.max(0, 1 - e.t / DMG_NUMBER_LIFE)
          love.graphics.setColor(e.color[1], e.color[2], e.color[3], alpha)
          drawScaledText(e.text, cx - Font.width(e.text) * scale / 2, y, scale)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
    if not ok then self.dmgNumbers = {} end
  end

  -- Real vanilla battle-exit sequence, mirrored from World:startBattle's
  -- own onDone closure (World.lua:5865-5972) -- confirmed by direct read,
  -- not guessed. g2-Battle-Scene never called any of this (Screen:exit
  -- only ever cleared battleActive), which is exactly the desync this
  -- fixes: the battle theme kept playing after the screen popped, and
  -- nothing reset the wild-encounter cooldown or VAR.BATTLERESULT-
  -- equivalent state real scripts/systems read afterward.
  --
  -- Deliberately NOT included, flagged rather than silently added: the
  -- LOSS consequences (heal party, halve money, warp to spawn -- the
  -- "a loss warps home... because it IS a whiteout" branch, :5912-5945).
  -- That's real save/warp mutation, a materially bigger and riskier
  -- change than "stop the music and reset battle-adjacent state," and
  -- wasn't what was asked for here -- a defeated party currently stays
  -- exactly where the battle found them, unhealed. Real gap, not solved
  -- by this pass.
  -- Called explicitly, inline, at every real exit site (updateOver's
  -- pop, chooseMenuItem's RUN pop) -- the SAME shape native's own
  -- World:startBattle onDone closure uses (World.lua:5865-5972: the
  -- screen's own callback does the pop AND the cleanup together, in one
  -- place, rather than a generic post-pop lifecycle hook). Also still
  -- wired into Screen:exit below as a safety net -- guarded by
  -- self.exited so calling both never double-fires Music.play/restore.
  function Screen:finishBattleExit()
    if self.exited or not self.world then return end
    self.exited = true

    -- THE ONE EVENT THIS SCREEN NEVER SENT.
    --
    -- `battle.ended` is emitted in exactly one place in the engine --
    -- Battle:endBattle (src/battle/gen2/Battle.lua) -- and this screen never
    -- calls it: finishTurn, throwBall and RUN each just set `self.outcome`
    -- and `self.phase = "over"`.  So for any fight drawn here the event
    -- simply never happened, and every listener waiting on it waited for
    -- ever.  Including this file's own: the mod.events:on("battle.ended")
    -- above, which clears the mon.multiSide tag combat.lua sets, has never
    -- once fired for a battle this screen drew.
    --
    -- Confirmed consequences outside this mod, in wild_forms:
    --
    --   * static legendaries retire and despawn on this event, so a boss
    --     beaten in a scene fight stayed standing on the map for ever and
    --     could not be spoken to again.
    --   * its two-phase bosses take their raised HP ceiling back down here,
    --     so an Eternamax ceiling could persist onto the caught Pokemon.
    --   * its diagnostic trace flushes here, so the end of every scene fight
    --     was missing from the log.
    --
    -- Emitted rather than routed through Battle:endBattle, deliberately: that
    -- method also drives native's own end-of-battle bookkeeping for a screen
    -- this mod is standing in for, and calling it here would run that
    -- bookkeeping twice.  The payload is the same one it sends, so a listener
    -- cannot tell the difference.
    --
    -- Once per battle: `exited` above is already the guard every other line
    -- in this function relies on.  pcall'd because a raising listener in some
    -- other mod must not strand the player in a battle that cannot exit --
    -- every line below this one still has to run.
    local okEnded, errEnded = pcall(function()
      Runtime.emit("battle.ended", { battle = self.battle, result = self.outcome })
    end)
    if not okEnded then
      mod.log:warn("g9_Battle_Scene: a battle.ended listener raised: %s",
        tostring(errEnded))
    end

    self.world.battleActive = nil
    -- WildBattleScript's reloadmapafterbattle: only a wild fight sets
    -- this (a trainer rematch has its own, separate cooldown handling
    -- this mod doesn't touch).
    if not self.isTrainerBattle then
      self.world.wildCooldown = 5
    end
    -- wBattleResult: WIN 0, LOSE 1 -- native's own binary (run/catch/draw
    -- all read as "not a loss," matching World.lua's own comment that
    -- the real engine "never forfeits or draws a battle").
    self.world.lastBattleResult = (self.outcome == "lose") and 1 or 0
    -- RestartMapMusic: the map theme comes back over whatever the battle
    -- left playing, unconditionally (World.lua:5946-5958's own comment
    -- explains why this can't be conditional on a one-shot flag this mod
    -- has no equivalent of anyway).
    if self.world.restoreMapMusic then self.world:restoreMapMusic() end
  end

  -- Real vanilla battle-exit sequence, mirrored from World:startBattle's
  -- own onDone closure (World.lua:5865-5972) -- confirmed by direct read,
  -- not guessed. g2-Battle-Scene never called any of this (Screen:exit
  -- only ever cleared battleActive), which is exactly the desync this
  -- fixes: the battle theme kept playing after the screen popped, and
  -- nothing reset the wild-encounter cooldown or VAR.BATTLERESULT-
  -- equivalent state real scripts/systems read afterward.
  --
  -- Deliberately NOT included, flagged rather than silently added: the
  -- LOSS consequences (heal party, halve money, warp to spawn -- the
  -- "a loss warps home... because it IS a whiteout" branch, :5912-5945).
  -- That's real save/warp mutation, a materially bigger and riskier
  -- change than "stop the music and reset battle-adjacent state," and
  -- wasn't what was asked for here -- a defeated party currently stays
  -- exactly where the battle found them, unhealed. Real gap, not solved
  -- by this pass.
  --
  -- Kept as a safety net (StateStack:pop() always calls this,
  -- src/core/StateStack.lua:37-45) in case something ever pops this
  -- screen from OUTSIDE its own update loop -- but the real, primary
  -- call is finishBattleExit above, invoked explicitly at the actual
  -- exit sites, the same place-and-timing native's own onDone uses.
  -- The OTHER half of native's exit closure, and the reason a scene
  -- TRAINER battle used to strand the player: handing control back to the
  -- overworld SCRIPT that opened the fight.
  --
  -- A scripted battle (a sight-trainer approach, a talk, a `startbattle`)
  -- runs on the World's script VM. The VM's `startbattle` opcode yields a
  -- {kind="battle"} request and PARKS (src/script/gen2/Vm.lua:1040);
  -- Vm:resume then calls the World's startBattle hook and hands it an
  -- `onDone(outcome)` thunk whose only job is `vm:resume(outcome)`
  -- (Vm.lua:2686). Native runs that thunk at the very end of its own
  -- battle-exit closure (World:startBattle's onDone). A caller that routes
  -- the battle through THIS screen instead -- registerTrainer's combatType,
  -- Sample-Battle-Scene-G9's tryDoublesTrainer, wild_forms's boss scene --
  -- returns before native ever runs, so that thunk was dropped: the VM
  -- stayed parked, vm:running() stayed true, World:busy() kept refusing
  -- overworld input, and the player could not move after the fight. A wild
  -- STEP encounter parks no script, which is exactly why those recovered
  -- fine on their own.
  --
  -- Resumed here rather than through a caller-supplied callback because the
  -- scene is the ONE place every routed battle leaves through, and it
  -- already mirrors the rest of native's exit closure in finishBattleExit
  -- (battleActive, wildCooldown, lastBattleResult, restoreMapMusic). This is
  -- the last missing piece of that same closure. The parked request is read
  -- straight off world.vm.pending -- nil (or a non-battle kind) for a wild
  -- encounter or any battle this screen drew that no script opened, so
  -- nothing is resumed in those cases and an unrelated parked request can
  -- never be resumed by a battle screen coming down.
  --
  -- Called from Screen:exit -- i.e. the state-stack POP -- and NOT from
  -- finishBattleExit, deliberately: native pops the screen and only THEN
  -- calls onDone, and a resumed script can itself push a screen (a rematch
  -- `startbattle`, a reloadmap that opens the map-name box). Resuming
  -- before the pop would let THIS screen's pop take that new screen back
  -- down instead of leaving it on top of the overworld.
  function Screen:resumeParkedWorldScript()
    if self.worldScriptResumed then return end
    self.worldScriptResumed = true
    local world = self.world
    local vm = world and world.vm
    if not (vm and vm.running and vm.resume) then return end
    local okRunning, running = pcall(vm.running, vm)
    if not okRunning or not running then return end
    local req = vm.pending
    if type(req) ~= "table" or req.kind ~= "battle" then return end
    -- Native hands the VM the branch's own raw outcome string
    -- (BattleState.lua:2412 -- `onDone(self.battle.outcome)`), NOT a
    -- pre-collapsed win/lose: the VM's startbattle arm maps it through
    -- BATTLE_RESULTS = {win=0, lose=1, draw=2} with an `or .win` fallback
    -- for anything else (run, caught), and scripts branch on the resulting
    -- wScriptVar via iftrue/iffalse (Vm.lua:1040-1051). Passing
    -- self.outcome verbatim reproduces that mapping exactly -- including a
    -- real DRAW mapping to 2 (truthy), which a win/lose collapse would
    -- have silently turned into a win. nil is the only value with no native
    -- battle equivalent here, and it is guarded because a nil resume is the
    -- VM's own "script aborted" signal (the same branch a nil onDone hits).
    local outcome = self.outcome or "win"
    local ok, err = pcall(vm.resume, vm, outcome)
    if not ok then
      mod.log:warn("g9_Battle_Scene: could not resume the parked world script: %s",
        tostring(err))
    end
  end

  function Screen:exit()
    self:finishBattleExit()
    -- After finishBattleExit, i.e. during the pop: see
    -- resumeParkedWorldScript's own header for why this ordering is the
    -- one that matters.
    self:resumeParkedWorldScript()
  end

  -- Returns the EFFECTIVE tx,ty for a layout element `id`: the tuned
  -- override baked into self.layout (Screen.new) if one exists for it,
  -- otherwise the layout's own computed default.
  function Screen:pos(id, defaultTx, defaultTy)
    -- A preset may override either coordinate alone (e.g. bossFight only
    -- moves its sprite's ground line), so fall back PER FIELD rather than
    -- requiring a tx override before a ty override is honoured.
    local saved = self.layout[id]
    if saved then return saved.tx or defaultTx, saved.ty or defaultTy end
    return defaultTx, defaultTy
  end

  -- The size multiplier for `id` -- 1.0 (unchanged) unless self.layout
  -- has a tuned override for it.
  function Screen:sizeMul(id)
    local saved = self.layout[id]
    if saved and saved.size then return saved.size end
    return 1.0
  end

  -- Runs fn() inside a scale transform anchored at (tx*8,ty*8), by
  -- id's own current sizeMul -- the SAME technique drawGuiBox's own
  -- BOX_SCALE already uses (draw everything at its normal, INTEGER
  -- default size, then scale the whole finished result as one unit).
  -- Border-only scaling (passing a fractional tw/th straight into
  -- Font.drawBox) was tried for F/E first and broke live: Font.drawBox's
  -- corner/edge glyphs are each a full 8px tile meant to tile together
  -- on an integer grid (Font.lua:544-558), so a fractional tw/th lands
  -- them at non-tile-aligned pixel offsets -- visible gaps in the frame.
  -- Wrapping the WHOLE draw (border AND every Font.draw call inside it)
  -- in one transform instead keeps every glyph's own proportions intact
  -- -- the entire box, text included, scales as a single image -- which
  -- also fixes the other real gap this same pass found: F/E's own text
  -- never scaled with the box at all before this.
  function Screen:withScale(id, tx, ty, fn)
    local mul = self:sizeMul(id)
    local anchorX, anchorY = tx * 8, ty * 8
    love.graphics.push()
    love.graphics.translate(anchorX, anchorY)
    love.graphics.scale(mul, mul)
    love.graphics.translate(-anchorX, -anchorY)
    fn()
    love.graphics.pop()
  end

  function Screen:catchAllowed()
    local alive = 0
    for _, e in ipairs(self.enemyBattlers) do
      if self.combat.isAlive(e) then alive = alive + 1 end
    end
    return alive < 2
  end

  ------------------------------------------------------------------
  -- Per-turn action selection: one action menu (FIGHT/BAG/PKMN/RUN --
  -- the same 4 options a real single battle always shows) per living
  -- player battler, in slot order, then AI actions, then one ordered
  -- resolution pass. Replaces the earlier design's single whole-turn
  -- menu, which is what let PKMN apply a switch instantly instead of
  -- queuing it as that slot's action -- see Screen:trySwitchIn below.
  ------------------------------------------------------------------
  function Screen:beginTurn()
    self.turnSlots = {}
    for i, b in ipairs(self.playerBattlers) do
      if self.combat.isAlive(b) then self.turnSlots[#self.turnSlots + 1] = i end
    end
    self.queuedActions = {}
    self.swapOwnerMarks = {}
    -- A FORM is armed for the turn it was picked in, and no longer: a new
    -- turn starts with no owner, so a mechanic that was somehow left armed
    -- (battle_forms' own once-per-battle state refuses a spent id, but a
    -- refused activation deliberately keeps it armed) is announced as this
    -- turn's, if anything, rather than last turn's.
    self.gimmickActorMon = nil
    self.gimmickActorSlot = nil
    self.gimmickOwnerMon = nil
    self.gimmickOwnerSlot = nil
    self.gimmickOwnerId = nil
    self.gimmickOwnerLabel = nil
    self.slotPtr = 1
    if #self.turnSlots == 0 then
      -- Both player battlers already down with no switch made -- still
      -- let the enemy side act rather than freeze the battle.
      self:beginResolving()
      return
    end
    self:enterActionMenu()
  end

  -- Loads the trainer intro pics the native screen shows before any mon
  -- is sent out: the PLAYER trainer's back-pic standing in the player
  -- slot, and for a trainer battle the ENEMY trainer's class front-pic
  -- standing in the enemy slot. Mirrors native's own lookups
  -- (src/ui/gen2/BattleState.lua:430-511): playerBack -- playerBackFemale
  -- for a female hero (Gen2Save.isFemale == save.player.gender "female")
  -- -- and trainerArt(data, classId) with classId = trainer.classId or
  -- trainer.class. Any missing/unloadable art leaves its flag false and
  -- the intro just skips that slide -- the same graceful fallback native
  -- uses when a cache has no trainer pic (the mon stands in for the
  -- whole intro).
  --
  -- COLOUR, resolved here alongside the image (the reason this exists as
  -- one function): each pic's own TrainerPalettes row plus its trueColor
  -- flag, both taken from the same sources native reads, and handed to
  -- drawRawImage so the grayscale sheet is remapped to the cart's colours.
  -- See drawRawImage and the Palettes/Sprites requires near the top.
  function Screen:resolveTrainerArt()
    local save = self.game and self.game.save
    -- Per-generation source (native.lua): Gen 2 reads gen2MenuGfx.battleHud and
    -- colours through TrainerPalettes; Gen 1 reads the native field.playerPics
    -- back-pic seam and the trainers registry's class pic.  Returns
    -- path, trueColor, colours.
    local backPath, backTrueColor, backColors =
      N.playerBackArt(self.data, save, self.battle)
    local backImg = backPath and loadSprite(backPath)
    if backImg then
      self.playerTrainerImage = backImg
      self.showPlayerTrainer = true
      self.playerTrainerColors = backColors
      self.playerTrainerTrueColor = backTrueColor and true or false
    end
    if self.isTrainerBattle and type(self.trainerData) == "table" then
      local path, trueColor, colors =
        N.enemyTrainerArt(self.data, self.trainerData)
      local img = path and loadSprite(path)
      if img then
        self.enemyTrainerImage = img
        self.showEnemyTrainer = true
        self.enemyTrainerColors = colors
        self.enemyTrainerTrueColor = trueColor and true or false
      end
    end
  end

  -- Reference note for the Gen 2 arm -- kept because it documents exactly which
  -- native lookups each resolved value came from (the backend above performs
  -- these same reads, and the Gen 2 path is behaviourally identical):
  --   local hud = self.data.gen2MenuGfx.battleHud
  --   playerBack -- playerBackFemale for a female hero (save.player.gender)
  --   trainerArt(data, classId) with classId = trainer.classId or trainer.class
  --   colours = Palettes.trainerColors(palettes, classId) through GbcPalette.
  -- Any missing/unloadable art leaves its flag false and the intro skips that
  -- slide, the same graceful fallback native uses.

  -- The vanilla intro beats for THIS battle, in order -- the full
  -- native sequence, not just the narration lines (the order the user
  -- asked for: trainer pics first, then mons):
  --   TRAINER: "{TRAINER} wants to battle!" -> trainerSlide (enemy class
  --     front-pic slides off right, only when art loaded) -> one
  --     "sent out X!" per enemy (each is THROWN from a pokeball onto
  --     its platform) -> backpicSlide (player back-pic slides off left,
  --     only when art loaded) -> one "Go! P!" per living player battler
  --     (also thrown from a pokeball).
  --   WILD:   one "Wild X appeared!" per enemy -- each appears in place
  --     at its final sprite position and fades from invisible to visible
  --     (there is no slide-in at all) -> backpicSlide -> "Go! P!" per
  --     player battler (pokeball throw).
  -- A battle with no enemies at all skips straight to the menu (empty
  -- sequence). Kinds: "msg" narration only, "trainerSlide"/"backpicSlide"
  -- start a pic's slide-off (the next beat advances when it completes),
  -- "fade" fades the wild enemy in slot `slot` in place (invisible ->
  -- visible over WILD_FADE_DURATION),
  -- "throw" throws a pokeball from side `side` ("player"/"enemy") to
  -- slot `slot`'s platform and materializes that battler there.
  function Screen:buildIntroSequence()
    local seq = {}
    local tName = self:trainerDisplayName()
    if tName then
      seq[#seq + 1] = { text = tName .. " wants to battle!", kind = "msg" }
      if self.showEnemyTrainer then
        seq[#seq + 1] = { kind = "trainerSlide" }
      end
      for i, b in ipairs(self.enemyBattlers) do
        seq[#seq + 1] = { text = tName .. " sent out " .. displayName(b.mon) .. "!",
          kind = "throw", side = "enemy", slot = i }
      end
    else
      for i, b in ipairs(self.enemyBattlers) do
        seq[#seq + 1] = { text = "Wild " .. displayName(b.mon) .. " appeared!",
          kind = "fade", slot = i }
      end
    end
    if self.showPlayerTrainer then
      seq[#seq + 1] = { kind = "backpicSlide" }
    end
    for i, b in ipairs(self.playerBattlers) do
      if self.combat.isAlive(b) then
        seq[#seq + 1] = { text = "Go! " .. displayName(b.mon) .. "!",
          kind = "throw", side = "player", slot = i }
      end
    end
    return seq
  end

  -- The trainer's name as the intro/outro should say it -- the real
  -- name if the caller supplied one, else the class, else nil (a wild
  -- fight). A legacy `true` trainer nobody could name falls back to the
  -- generic "TRAINER".
  function Screen:trainerDisplayName()
    local t = self.trainerData
    if t == true then return "TRAINER" end
    if type(t) ~= "table" then return nil end
    if type(t.name) == "string" and t.name ~= "" then return t.name end
    if type(t.class) == "string" and t.class ~= "" then return t.class end
    return nil
  end

  -- Shows the next intro beat, or hands off to the real turn loop when
  -- the narration runs out. A "throw" beat arms the pokeball clock (ball
  -- arcs to the mon's platform, lands, materializes the mon -- revealed
  -- only when the ball lands, drawn in drawContent/drawBallThrow) AND
  -- pre-warms that battler's sheet for the ball's whole flight (see
  -- Screen:prewarmSlot), so the mon's own frames are baked before it is
  -- revealed; a "fade" beat arms the wild fade clock (that enemy mon fades
  -- in place).
  -- The slide beats just arm their clocks (the dt stepper
  -- in Screen:update and the A/B snap in updateIntro both finish them and
  -- then call advanceIntro again for the NEXT beat -- so a pic slides
  -- fully off before the next line reads, exactly like native's own held
  -- queue).
  function Screen:advanceIntro()
    self.introIdx = self.introIdx + 1
    local step = self.introSequence[self.introIdx]
    if not step then
      self:finishIntro()
      return
    end
    self.currentMessage = step.text or nil
    if step.kind == "throw" then
      self.ballThrow = { side = step.side, slot = step.slot, t = 0 }
      -- Begin the sheet bake NOW, during the ball's flight, so the mon's own
      -- frames are ready when the ball lands (see Screen:prewarmSlot).
      self:prewarmSlot(step.side, step.slot)
    elseif step.kind == "fade" then
      self.wildFade = { slot = step.slot, t = 0 }
    elseif step.kind == "trainerSlide" then
      self.trainerSlide = 0
    elseif step.kind == "backpicSlide" then
      self.backpicSlide = 0
    end
  end

  -- A wild fade-in has completed: reveal that battler (sprite + HUD
  -- gate) and clear the entrance state. Called from the dt stepper once
  -- the fade's clock passes its duration. (The pokeball throw reveals
  -- and clears itself inline in Screen:update -- the reveal on landing,
  -- the clear at the very end.)
  function Screen:finishEntrance()
    if self.wildFade then
      self.enemyRevealed[self.wildFade.slot] = true
      self.wildFade = nil
    end
  end

  -- The last intro beat is over: every reveal flag is now true (so
  -- nothing is left half-hidden if a battle somehow ended up mid-intro),
  -- the slide clocks are dead, both trainer pics are off, and the real
  -- turn loop takes over.
  function Screen:finishIntro()
    self.ballThrow = nil
    self.wildFade = nil
    self.trainerSlide = nil
    self.backpicSlide = nil
    self.showPlayerTrainer = false
    self.showEnemyTrainer = false
    for i in ipairs(self.enemyBattlers) do self.enemyRevealed[i] = true end
    for i in ipairs(self.playerBattlers) do self.playerRevealed[i] = true end
    self.currentMessage = nil
    self:beginTurn()
  end

  -- Intro input: A/B advances the narration exactly like resolving's
  -- message pump -- but a press during a hold (the pokeball throw or wild
  -- fade-in, either trainer pic's slide-off) snaps it to done (the same
  -- rule as every other hold: a press ends the hold and nothing else,
  -- never skipping the line underneath it).
  function Screen:updateIntro(input)
    if input:wasPressed("a") or input:wasPressed("b") then
      if self.ballThrow and self.ballThrow.t < BALL_THROW_TOTAL then
        self.ballThrow.t = BALL_THROW_TOTAL
        return
      end
      if self.wildFade and self.wildFade.t < WILD_FADE_DURATION then
        self.wildFade.t = WILD_FADE_DURATION
        return
      end
      if self.trainerSlide ~= nil and self.trainerSlide < TRAINER_SLIDE_DURATION then
        self.trainerSlide = TRAINER_SLIDE_DURATION
        return
      end
      if self.backpicSlide ~= nil and self.backpicSlide < BACKPIC_SLIDE_DURATION then
        self.backpicSlide = BACKPIC_SLIDE_DURATION
        return
      end
      self:advanceIntro()
    end
  end

  function Screen:enterActionMenu()
    self.actingSlotIdx = self.turnSlots[self.slotPtr]
    self.menuCursor = "FIGHT"
    self.message = nil
    self.phase = "actionMenu"
  end

  -- CUSTOM ("FORMS", per this mod's own settings.lua default) opens a
  -- real picker over battle_forms's own transform registry -- explicit
  -- user request: "battle forms is the mod that will own the call for
  -- 'custom' button from gen9 battle scene," then, after an initial
  -- auto-pick-first wiring instead showed only Dynamax and skipped
  -- battle_forms's own normal picker workflow: "inspect why gimmick
  -- button is firing only dynamax and not the menu for the list of
  -- gimmicks." Fixed by adding a real gimmickSelect phase (Screen:
  -- enterGimmickSelect/updateGimmickSelect/drawGimmickSelect below),
  -- built the same shape moveSelect/targetSelect already are -- a
  -- cursor over a list, A confirms, B cancels back to the action menu --
  -- rather than deciding for the player.
  function Screen:chooseMenuItem(id)
    if id == "RUN" then
      self.outcome = "run"
      self:finishBattleExit()
      self.game.stack:pop()
    elseif id == "BAG" then
      self:openBag()
    elseif id == "PKMN" then
      self:openSwitchMenu()
    elseif id == "SWITCH" then
      self:enterSwapSelect()
    elseif id == "FIGHT" then
      self:enterMoveSelect()
    elseif id == "CUSTOM" then
      mod.events:emit(CUSTOM_BUTTON_EVENT, { game = self.game, world = self.world })
      self:enterGimmickSelect()
    end
  end

  ------------------------------------------------------------------
  -- GIMMICK SELECT -- battle_forms's own mod.exports.transforms Registry
  -- (src/transforms.lua -- :all() returns every registered mechanic:
  -- Mega, Dynamax, and whatever else that mod registers, in the same
  -- cycle order its own native-screen cell uses), each entry carrying
  -- available(battle)/activate(battle)/optionally arm(battle)/
  -- disarm(battle) -- confirmed real via src/mega.lua's own M.entry, the
  -- shape every mechanic in that registry uses.
  --
  -- available(battle)/activate(battle) both read battle.player directly
  -- (confirmed, src/mega.lua:84,120) -- battle_forms's own single-
  -- battler assumption, the same class of gap as native's own
  -- Battle:sideOf this mod already works around elsewhere. self.battle
  -- (the real Battle instance this screen constructs) has a real
  -- .player field (buildBattle's own Battle.new assembly), so this is
  -- correct for the common case -- the acting battler being that same
  -- mon -- and knowingly not multi-battler-correct beyond it.
  --
  -- Scope stated plainly: arms+activates immediately on confirm, not the
  -- real games' own "arm now, actually transform when the move resolves"
  -- timing -- a real transform is functionally in effect for the whole
  -- turn either way, which is what actually matters for combat
  -- correctness; the exact animation beat is real future work.
  ------------------------------------------------------------------
  -- Fixed 2x2 grid, matching the action menu's own GRID2_ROWS convention
  -- (up/down/left/right coordinate math, not a linear cycle) -- explicit
  -- user request. A real slot count above 4 is capped, not silently
  -- dropped: battle_forms's registry can in principle carry more than
  -- four mechanics (Mega, Dynamax, Tera, Z-Move, Primal, Fusion, Ultra
  -- Burst), but the trainer's own real one-transform-per-battle limit
  -- means more than a handful being simultaneously AVAILABLE for one mon
  -- is already an edge case, and four slots is what was asked for.
  local GIMMICK_GRID_ROWS = { {1, 2}, {3, 4} }

  ------------------------------------------------------------------
  -- FORMS OWNER -- which Pokemon a FORMS/CUSTOM pick belongs to
  ------------------------------------------------------------------
  -- battle_forms reads `battle.player` for every decision it makes:
  -- formapi.gimmicks resolves each mechanic's `available(battle)` against it,
  -- src/dynamax.lua's own `arm` substitutes that battler's moves, and
  -- src/resolve.lua's onTurnStarted activates against it. This scene
  -- deliberately pins `battle.player` to the FIRST player battler for the
  -- engine's own reads (native.lua's buildBattle: `state.player =
  -- byMon[data.players[1]]`), so on a doubles/native-multi layout a FORM
  -- picked from any other mon's action menu used to land on slot 1 -- read
  -- and confirmed in formapi.gimmicks / mega.activate / dynamax.arm.
  -- Explicit user request: "make sure that we are matching its activation to
  -- the pokemon owner of the turn".
  --
  -- We CAN control the pairing, and this is how: every battle_forms call the
  -- FORMS bridge makes runs with `battle.player` focused on the mon whose
  -- action menu the pick came from -- eligibility when the list is built,
  -- arm() when it is confirmed (so a Max Move/Z-Move substitution lands on
  -- the right moveset) and the real battle.turn_started activation. The pin
  -- is restored the instant each call returns, so nothing else that reads
  -- battle.player sees the focus.
  --
  -- The mon is ALSO announced to other mods (FORMS_EVENT above), precisely
  -- because the focus is transient: a peer that reads battle.player later
  -- cannot assume it names the FORM's owner, so the announcement carries the
  -- mon explicitly instead.
  local function nativePlayerFor(self, mon)
    if not mon then return nil end
    -- Gen 2's battle.player IS the mon; Gen 1's is the native battler the mon
    -- was built into (battle_forms' own battlerof.mon reverses that again).
    if N.isGen2 then return mon end
    local byMon = self.battle and self.battle.battlersByMon
    return byMon and byMon[mon] or nil
  end

  -- Runs `fn` with battle.player pointed at `mon`, restoring the baseline
  -- afterward whether fn returns or raises -- pcall'd so a raising
  -- battle_forms call can never leave the field pointed at the wrong mon.
  local function focusBattlePlayer(self, mon, fn)
    local battle = self.battle
    local focused = mon and nativePlayerFor(self, mon)
    if not (battle and focused) then return fn() end
    local saved = battle.player
    battle.player = focused
    local ok, a, b = pcall(fn)
    battle.player = saved
    if not ok then error(a, 0) end
    return a, b
  end

  -- formapi's own published `armed()` (the internals are not the peer
  -- contract). The armed id disappearing between two reads is also the signal
  -- that battle.turn_started actually consumed it; staying armed means the
  -- entry's activate() refused and the option is deliberately kept.
  local function battleFormsArmedId()
    local battleForms = mod:find("battle_forms")
    local api = battleForms and battleForms.exports
    if not (api and type(api.armed) == "function") then return nil end
    local ok, id = pcall(api.armed)
    return ok and id or nil
  end

  -- The phase announcement described on FORMS_EVENT.
  local function emitFormsEvent(self, phase, fields)
    fields = fields or {}
    local mon = fields.mon
    local ok, err = pcall(mod.events.emit, mod.events, FORMS_EVENT,
      { phase = phase, mon = mon, species = mon and mon.species or nil,
        slot = fields.slot, id = fields.id, label = fields.label,
        reason = fields.reason, battle = self.battle, game = self.game,
        world = self.world })
    if not ok then
      mod.log:warn("g9_Battle_Scene: FORMS %s event could not be emitted (%s)",
        tostring(phase), tostring(err))
    end
  end

  -- Drops the recorded owner without an announcement -- for the paths that
  -- have already announced something else about it.
  local function clearGimmickOwner(self)
    self.gimmickOwnerMon = nil
    self.gimmickOwnerSlot = nil
    self.gimmickOwnerId = nil
    self.gimmickOwnerLabel = nil
  end

  -- Corrected same day: user asked what happened to battle_forms's own
  -- once-per-battle limit -- the first version of this bridge called
  -- entry.activate(battle) directly, which performs a transformation but
  -- never marks it spent (confirmed: src/resolve.lua:212-223's
  -- M.onTurnStarted is the ONLY real caller of activate anywhere in that
  -- mod, and state:consume(id) -- the ONE place spentAny gets recorded --
  -- only ever runs paired with it, right there). The real surface is
  -- armState:toggle(id) to ARM a choice (real move-substitution included,
  -- via src/arm.lua's own arm/disarm dispatch) plus a real
  -- "battle.turn_started" emit at the right point in the turn (see
  -- Screen:advanceResolving) so battle_forms's own existing listener
  -- performs the actual activate+consume itself, respecting the limit
  -- exactly as it already does for a native-turn-loop battle.
  function Screen:enterGimmickSelect()
    local battleForms = mod:find("battle_forms")
    local api = battleForms and battleForms.exports
    -- Which mon's action menu this pick came from -- captured up here so the
    -- arm and cancel paths always have it (see the FORMS OWNER block above).
    local actor = self.playerBattlers[self.actingSlotIdx]
    local actorMon = actor and actor.mon
    self.gimmickActorMon = actorMon
    self.gimmickActorSlot = self.actingSlotIdx
    -- battle_forms publishes a DOCUMENTED api (src/formapi.lua): gimmicks(),
    -- arm(), armed(). It does NOT publish transforms/armState -- those are
    -- its internal dep names, and asking for them found nil, which is why this
    -- menu answered "No Gimmicks available." for every mon regardless of what
    -- the trainer was carrying. Shimmed to the real surface rather than the
    -- other way round: formapi.lua's header states plainly that the internals
    -- are not the peer contract.
    if not (api and type(api.gimmicks) == "function" and type(api.arm) == "function") then
      self.message = "No FORMS available."
      self.phase = "actionMenu"
      return
    end
    -- gimmicks(battle) already applies this mod's own eligibility AND the
    -- barred-species rule, and returns { id, label, available } rows.
    -- Focused on the acting mon so eligibility is resolved against it rather
    -- than the engine's pinned slot-1 battler (see FORMS OWNER above).
    local okList, rows = pcall(function()
      return focusBattlePlayer(self, actorMon, function()
        return api.gimmicks(self.battle)
      end)
    end)
    if not okList or type(rows) ~= "table" then rows = {} end
    local registry = { all = function()
      local out = {}
      for _, row in ipairs(rows) do
        local ready = row.available and true or false
        out[#out + 1] = { id = row.id, label = row.label,
                          available = function() return ready end }
      end
      return out
    end }
    -- The once-per-battle limit is enforced by arm() itself: State:toggle
    -- validates the spent flag, so a spent id refuses and the caller's own
    -- "couldn't be armed" branch reports it. usedAny/used are not published,
    -- so they answer false here rather than guessing at internal state.
    local armState = {
      usedAny = function() return false end,
      used = function() return false end,
      toggle = function(_, id) return api.arm(id) == true end,
    }
    -- The once-per-battle limit itself: spentAny (any mechanic already
    -- used this battle) or this specific id already spent both mean the
    -- cell has nothing to offer, matching src/overlay.lua's own "every
    -- other reason the cell is absent" role (arm.lua's own header) --
    -- available(battle) alone, confirmed by reading it, never checks
    -- either.
    if armState:usedAny() then
      self.message = "Already used a FORM this battle."
      self.phase = "actionMenu"
      return
    end
    local candidates = {}
    for _, entry in ipairs(registry:all()) do
      if not armState:used(entry.id) then
        local ok, available = pcall(entry.available, self.battle)
        if ok and available then candidates[#candidates + 1] = entry end
        if #candidates == 4 then break end
      end
    end
    if #candidates == 0 then
      self.message = "No FORM available right now."
      self.phase = "actionMenu"
      return
    end
    self.gimmickCandidates = candidates
    self.gimmickArmState = armState
    self.gimmickCursor = 1
    self.phase = "gimmickSelect"
  end

  function Screen:updateGimmickSelect(input)
    if input:wasPressed("b") then
      -- Nothing armed yet at this point -- back to the action menu with
      -- no side effect, same as moveSelect's own B. Announced, so a peer
      -- watching for the FORM this turn picked a mon for knows the pick was
      -- backed out of rather than expecting an activation (FORMS_EVENT).
      emitFormsEvent(self, "cancelled", { mon = self.gimmickActorMon,
        slot = self.gimmickActorSlot, reason = "backed-out" })
      self.gimmickCandidates = nil
      self.gimmickArmState = nil
      self.phase = "actionMenu"
      return
    end
    if input:wasPressed("a") then
      local chosen = self.gimmickCandidates[self.gimmickCursor]
      local ownerMon = self.gimmickActorMon
      -- Armed only -- the real transformation happens later, at
      -- battle.turn_started (Screen:advanceResolving), the same timing
      -- battle_forms's own resolve.onTurnStarted always used. Focused on the
      -- owner because State:toggle dispatches the mechanic's own arm() hook
      -- (src/arm.lua's retarget), and for a move-substituting mechanic
      -- (Dynamax's Max Moves, a Z-Move) that hook replaces battle.player's
      -- move array -- so it has to be the right battler.
      local ok, armed = pcall(function()
        return focusBattlePlayer(self, ownerMon, function()
          return self.gimmickArmState:toggle(chosen.id)
        end)
      end)
      if ok and armed then
        -- A previous pick this turn (a second mon's FORMS, or a second cell)
        -- is superseded: announced before the new owner so a peer never sees
        -- two live "armed" announcements for one battle.
        if self.gimmickOwnerMon then
          emitFormsEvent(self, "cancelled", { mon = self.gimmickOwnerMon,
            slot = self.gimmickOwnerSlot, id = self.gimmickOwnerId,
            label = self.gimmickOwnerLabel, reason = "replaced" })
        end
        self.gimmickOwnerMon = ownerMon
        self.gimmickOwnerSlot = self.gimmickActorSlot
        self.gimmickOwnerId = chosen.id
        self.gimmickOwnerLabel = chosen.label
        -- Names the Pokemon that used it, so the player line says the same
        -- thing the FORMS_EVENT payload does.
        self.message = ownerMon
          and (displayName(ownerMon) .. " armed " .. chosen.label .. "!")
          or (chosen.label .. " armed!")
        emitFormsEvent(self, "armed", { mon = ownerMon,
          slot = self.gimmickActorSlot, id = chosen.id, label = chosen.label })
      else
        -- Toggling the already-armed cell off, or battle_forms refusing it.
        -- Either way nothing is left armed for an earlier owner to claim.
        clearGimmickOwner(self)
        self.message = "That FORM couldn't be armed."
        emitFormsEvent(self, "cancelled", { mon = ownerMon,
          slot = self.gimmickActorSlot, id = chosen.id, label = chosen.label,
          reason = "arm-refused" })
      end
      self.gimmickCandidates = nil
      self.gimmickArmState = nil
      self.phase = "actionMenu"
      return
    end
    -- Row/col coordinate math over the fixed 2x2 grid -- same pattern
    -- Screen:moveMenuCursorGrid already uses for the action menu, cursor
    -- only ever lands on a slot that actually has a candidate in it.
    local row, col
    for r = 1, 2 do
      for c = 1, 2 do
        if GIMMICK_GRID_ROWS[r][c] == self.gimmickCursor then row, col = r, c end
      end
    end
    row, col = row or 1, col or 1
    local moved = false
    if input:wasPressed("left") or input:wasPressed("right") then
      col = col == 1 and 2 or 1
      moved = true
    elseif input:wasPressed("up") or input:wasPressed("down") then
      row = row == 1 and 2 or 1
      moved = true
    end
    if moved and self.gimmickCandidates[GIMMICK_GRID_ROWS[row][col]] then
      self.gimmickCursor = GIMMICK_GRID_ROWS[row][col]
    end
  end

  -- No header text -- explicit user request. Same 2x2 layout math as
  -- Screen:drawActionMenuEGrid's own plain (non-cross) branch, just drawn
  -- into F's own wider box instead of E's, so column 2 sits at half F's
  -- own interior width rather than that function's own GRID_SLOT_2
  -- (tuned for E specifically).
  function Screen:drawGimmickSelect()
    local colX = { self.fTextX + 12, self.fTextX + 12 + 104 }
    for i = 1, 4 do
      local entry = self.gimmickCandidates[i]
      if entry then
        local row = math.floor((i - 1) / 2) + 1
        local col = (i - 1) % 2 + 1
        local x, y = colX[col], self.fTextY + (row - 1) * 9
        Font.draw(entry.label, x, y)
        if i == self.gimmickCursor then
          Font.drawCode(CURSOR_CODE, x - 12, y)
        end
      end
    end
  end

  -- Moves self.menuCursor one step through self.menuOrder (LIST mode
  -- only), wrapping at either end. Returns true iff a directional key
  -- was actually pressed, so the caller knows whether to clear
  -- self.message.
  function Screen:moveMenuCursorList(input)
    local idx = 1
    for i, id in ipairs(self.menuOrder) do
      if id == self.menuCursor then idx = i break end
    end
    if input:wasPressed("up") then
      idx = idx > 1 and idx - 1 or #self.menuOrder
    elseif input:wasPressed("down") then
      idx = idx < #self.menuOrder and idx + 1 or 1
    else
      return false
    end
    self.menuCursor = self.menuOrder[idx]
    return true
  end

  -- One step forward (delta=1) or backward (delta=-1) through `list`
  -- from `current`, wrapping. Shared by both cross cycles below.
  local function cycleStep(list, current, delta)
    local idx = 1
    for i, id in ipairs(list) do if id == current then idx = i break end end
    idx = ((idx - 1 + delta) % #list) + 1
    return list[idx]
  end

  -- Locate an id in a rectangular grid whose rows may contain nil holes.
  local function findCell(grid, id)
    for r = 1, #grid do
      for c = 1, #grid[r] do
        if grid[r][c] == id then return r, c end
      end
    end
  end

  -- One grid step that SKIPS empty cells and wraps: walk in the (dr, dc)
  -- direction until a real cell is met, wrapping around the grid at each
  -- edge, and give up after a full lap (returning the start) so a heading
  -- that only ever meets empty cells is a no-op, not a hang. This is what
  -- lets the SWITCH cross reach its centre cell by plain coordinate
  -- movement -- the original cross could not (a step from any corner lands
  -- on an empty cell and carries straight through to the opposite corner),
  -- which is why that shape needed the explicit cycles below.
  local function stepCell(grid, r, c, dr, dc)
    local rows = #grid
    local cols = 1
    for i = 1, rows do if #grid[i] > cols then cols = #grid[i] end end
    local sr, sc = r, c
    for _ = 1, rows * cols do
      r = ((r - 1 + dr) % rows) + 1
      c = ((c - 1 + dc) % cols) + 1
      if r == sr and c == sc then break end
      if grid[r] and grid[r][c] then return r, c end
    end
    return sr, sc
  end

  -- Moves self.menuCursor for GRID mode -- the SWITCH cross and the plain
  -- grids by coordinate movement (stepCell), or, when SWITCH is off and a
  -- custom button is set, the original 5-cell cross and its two explicit
  -- cycles. Same true/false return contract as moveMenuCursorList.
  function Screen:moveMenuCursorGrid(input)
    if self.customButtonLabel and not self.swapEnabled then
      if input:wasPressed("right") then
        self.menuCursor = cycleStep(CROSS_RIGHT_CYCLE, self.menuCursor, 1)
      elseif input:wasPressed("left") then
        self.menuCursor = cycleStep(CROSS_RIGHT_CYCLE, self.menuCursor, -1)
      elseif input:wasPressed("down") then
        self.menuCursor = cycleStep(CROSS_DOWN_CYCLE, self.menuCursor, 1)
      elseif input:wasPressed("up") then
        self.menuCursor = cycleStep(CROSS_DOWN_CYCLE, self.menuCursor, -1)
      else
        return false
      end
      return true
    end
    local grid = self.crossSlots or self.gridRows
    local row, col = findCell(grid, self.menuCursor)
    if not row then return false end
    local nr, nc
    if input:wasPressed("left") then
      nr, nc = stepCell(grid, row, col, 0, -1)
    elseif input:wasPressed("right") then
      nr, nc = stepCell(grid, row, col, 0, 1)
    elseif input:wasPressed("up") then
      nr, nc = stepCell(grid, row, col, -1, 0)
    elseif input:wasPressed("down") then
      nr, nc = stepCell(grid, row, col, 1, 0)
    else
      return false
    end
    self.menuCursor = grid[nr][nc] or self.menuCursor
    return true
  end

  function Screen:updateActionMenu(input)
    if input:wasPressed("b") then
      -- Back up to the PREVIOUS slot's action menu, undoing whatever it
      -- queued, so it can be reconsidered -- no-op on the very first
      -- slot, since there is nothing before it to back into (matches
      -- the real games: you can't cancel out of the first Pokemon's own
      -- menu either).
      if self.slotPtr > 1 then
        self.slotPtr = self.slotPtr - 1
        local undone = table.remove(self.queuedActions)
        -- Undoing a queued SWITCH drops its owner cue too -- the swap is
        -- no longer happening.
        if undone and undone.kind == "swap" then
          self:clearSwapOwnerMark(undone.actor)
        end
        self:enterActionMenu()
      end
      return
    end
    if input:wasPressed("a") then
      self:chooseMenuItem(self.menuCursor)
      return
    end
    local moved = (self.menuLayout == "grid")
      and self:moveMenuCursorGrid(input)
      or self:moveMenuCursorList(input)
    if moved then self.message = nil end
  end

  -- Split in two (E's menu list vs F's message/prompt) because F and E
  -- are independently resizable now -- each half has to run inside its
  -- OWN box's own Screen:withScale block (see drawContent), not a
  -- single function drawing into both at once.
  function Screen:drawActionMenuE()
    if self.menuLayout == "grid" then
      self:drawActionMenuEGrid()
    else
      self:drawActionMenuEList()
    end
  end

  -- E's own text budget in px, the width every grid/cross slot below is
  -- solved against.  E_TW*8=96px of box, minus the text inset eTextX
  -- already applies (2px past the frame's own 4px left edge, its formula
  -- in Screen:drawContent) and a 2px margin back from the right edge, is
  -- 84px of true interior for round eighty-one's rect-drawn frame; 78 is
  -- the tuned budget kept from the tile-border era, i.e. 6px of slack --
  -- deliberately, since these slots carry the cursor gutter and the
  -- label's own scaling.  FIGHT/BAG/PKMN/RUN are fixed 8px/glyph text
  -- (Font.lua), so a label's pixel width is just #chars*8 -- confirmed by
  -- direct measurement, not assumed, after a flat 44px column-gap guess
  -- broke "PKMN" out of the box border live (screenshot-reported).
  local E_INTERIOR_W = 78

  -- Rows are native-spaced at native size normally. SWITCH adds a row, and
  -- with the custom button too that is six rows inside the box's ~42px of
  -- text interior -- 11px spacing would run out through the bottom border
  -- -- so a SWITCH-enabled list uses the cross layout's own 0.5 scale on a
  -- 7px pitch (6 rows: 5*7 + 4 = 39px, inside 42).
  local LIST_ROW_GAP = 11
  local LIST_ROW_GAP_SW = 7

  function Screen:drawActionMenuEList()
    local scale = self.swapEnabled and CROSS_TEXT_SCALE or nil
    local gap = self.swapEnabled and LIST_ROW_GAP_SW or LIST_ROW_GAP
    local cursorRow = 1
    for i, id in ipairs(self.menuOrder) do
      local label
      if id == "CUSTOM" then
        label = scale
          and fitName(self.customButtonLabel, (E_INTERIOR_W - 10) / scale, 0)
          or fitName(self.customButtonLabel, E_INTERIOR_W - 10, 0)
      else
        label = MENU_LABELS[id]
      end
      local y = self.eTextY + (i - 1) * gap
      if scale then
        drawScaledText(label, self.eTextX + 10, y, scale)
      else
        Font.draw(label, self.eTextX + 10, y)
      end
      if id == self.menuCursor then cursorRow = i end
    end
    local cy = self.eTextY + (cursorRow - 1) * gap
    if scale then
      drawScaledCode(CURSOR_CODE, self.eTextX, cy, scale)
    else
      Font.drawCode(CURSOR_CODE, self.eTextX, cy)
    end
  end

  -- Row gap is PER MODE, not shared: BOTTOM_H was cut to 2/3 height
  -- after this row spacing was first tuned, and nobody rechecked cross
  -- mode's 3 rows against the new shorter box -- row 3 (BAG/RUN) ran
  -- past the bottom border (screenshot-reported). 2 rows at 18px still
  -- fits the shorter box fine (confirmed, untouched); 3 rows needed a
  -- real recompute: interior height (BOTTOM_H-2)*8=32px, minus eTextY's
  -- own ~2px inset and a safety margin leaves ~26px, and row3 sits at
  -- GRID_Y_OFFSET+2*gap plus the scaled glyph's own ~4px height (8px
  -- cell * CROSS_TEXT_SCALE=0.5) -- solving 3+2*gap+4<=26 gives gap<=9.5.
  local GRID_ROW_GAP_2 = 18
  local GRID_ROW_GAP_3 = 9
  local GRID_TEXT_SCALE_2 = 0.65
  local CROSS_TEXT_SCALE = 0.5
  local GRID_Y_OFFSET = 3
  -- Column slots are EVEN fractions of the usable width for plain 2x2.
  -- FIGHT/BAG (col1) and PKMN/RUN (col2) are DIFFERENT widths, so
  -- left-aligning both rows at the same slot x (an earlier pass) put
  -- them at the same LEFT EDGE, not the same CENTER -- FIGHT and BAG
  -- visibly didn't line up. Each label is centered within its own
  -- column's slot instead, which puts FIGHT/BAG (and PKMN/RUN) on the
  -- same center line regardless of their own widths.
  --
  -- The 2-column BLOCK itself is centered in the box too (a later bug:
  -- col1 used to start at a flat +10, using all the slack as a one-
  -- sided cursor margin with nothing on the right, so the whole grid
  -- sat visibly off-center toward the right edge -- screenshot-
  -- reported). Same margin-solving as the cross layout below: total
  -- width 2*34=68 inside the 78px interior leaves margin=(78-68)/2=5
  -- on both sides.
  local GRID_SLOT_2 = (E_INTERIOR_W - 10) / 2
  local GRID_MARGIN_2 = (E_INTERIOR_W - 2 * GRID_SLOT_2) / 2
  -- Worst case a label fills its whole slot (0 centering offset within
  -- it), landing right at col1_x = eTextX+GRID_MARGIN_2 -- offset must
  -- clear back to the true left border (eTextX-2) without going past
  -- it, so <= GRID_MARGIN_2+2 = 7; 6 leaves a 1px margin.
  local GRID_CURSOR_OFFSET_2 = 6

  -- Cross mode's 3 columns are NOT evenly split: corners (FIGHT/BAG/
  -- PKMN/RUN) get just enough room for their own fixed text, and the
  -- CENTER (custom, arbitrary user text) gets whatever's left over.
  -- Slot X/width are solved so the WHOLE 3-column block sits centered
  -- in the box: box true center = E_INTERIOR_W/2 = 39. margin(m) +
  -- FIGHT(20) + gap(g) + CENTER_budget(B) + gap(g) + PKMN(16) +
  -- margin(m) = E_INTERIOR_W=78, i.e. 2m+2g+B=42; picking g=2 (a
  -- visible gap) and B=34 (comfortably fits "FORMS", 5 chars = 40px
  -- unscaled at this 0.5 scale) leaves m=2: col1 x=2 w=20 (2 to 22),
  -- col2 x=24 w=34 (24 to 58), col3 x=60 w=16 (60 to 76) -- 2px margin
  -- on both sides. (An earlier pass dropped the gap between col2 and
  -- col3, landing col3 at 58 instead of 60 -- fixed here.)
  --
  -- Each corner slot's own width matches its WIDER row's label (FIGHT
  -- for col1, PKMN for col3) exactly, so the shorter row (BAG, RUN)
  -- centers inside it instead of sharing the same left edge -- BAG
  -- wasn't lining up under FIGHT, same bug the 2x2 branch below had
  -- (screenshot-reported).
  local CROSS_SLOT_X = { 2, 24, 60 }
  local CROSS_SLOT_W = { 20, 34, 16 }
  local CROSS_CENTER_BUDGET = CROSS_SLOT_W[2]
  -- Font.drawCode has no scale of its own (native ~8px) -- drawn
  -- through drawScaledCode now so the cursor shrinks with the text
  -- instead of swallowing it (screenshot-reported: the arrow covered
  -- most of "FORMS"). 4px, not 2 or 10: needs to clear the smaller
  -- scaled glyph without going negative off col1's own left edge (col1
  -- sits only 2px into the interior, eTextX-2 is the true border).
  local CROSS_CURSOR_OFFSET = 4

  -- SWITCH-ENABLED MENUS. When the battle has two or more living allies
  -- (and is not a bossFight), one extra E cell carries SWITCH, placed
  -- directly UNDER FIGHT in every layout: second in the list order, the
  -- middle-left cell of the cross, the second row's left cell of the
  -- plain grid. Nothing else moves -- the cross keeps FIGHT/PKMN/BAG/RUN
  -- on their own corners and CUSTOM centred, the plain grid keeps its own
  -- top row -- so the only new fact is the cell itself.
  --
  -- Cross geometry: column 1 widens 20 -> 24 to fit "SWITCH" (6 glyphs at
  -- CROSS_TEXT_SCALE=0.5 is exactly 24px), paid for by the centre budget
  -- 34 -> 30, so the 3-column block still measures 78px with a 2px margin
  -- either side: 2 + 24 + 2 + 30 + 2 + 16 + 2 = 78. (The SWITCH slot grids
  -- themselves -- CROSS_SLOTS_SW / GRID2_ROWS_SW -- are declared up with
  -- the other menu shapes, before Screen.new reads them.)
  local CROSS_SLOT_X_SW = { 2, 28, 60 }
  local CROSS_SLOT_W_SW = { 24, 30, 16 }
  local CROSS_CENTER_BUDGET_SW = CROSS_SLOT_W_SW[2]

  -- Explicit numeric bounds, NOT ipairs -- CROSS_SLOTS rows have real
  -- nil holes ({"FIGHT", nil, "PKMN"}), and ipairs stops dead at the
  -- first nil, so it would never reach the third column at all.
  function Screen:drawActionMenuEGrid()
    if self.customButtonLabel then
      -- Column geometry swaps to the wider-col-1 SWITCH variant when this
      -- battle offers SWITCH; the plain/cross shapes are chosen by
      -- Screen.new (self.crossSlots) and the two column tables below stay
      -- in lockstep with them.
      local slotColX = self.swapEnabled and CROSS_SLOT_X_SW or CROSS_SLOT_X
      local slotColW = self.swapEnabled and CROSS_SLOT_W_SW or CROSS_SLOT_W
      local centerBudget = self.swapEnabled and CROSS_CENTER_BUDGET_SW or CROSS_CENTER_BUDGET
      for r = 1, 3 do
        for c = 1, 3 do
          local id = self.crossSlots[r] and self.crossSlots[r][c]
          if id then
            local label = (id == "CUSTOM")
              and fitName(self.customButtonLabel, centerBudget / CROSS_TEXT_SCALE, 0)
              or MENU_LABELS[id]
            local slotX = self.eTextX + slotColX[c]
            local x = slotX + (slotColW[c] - Font.width(label) * CROSS_TEXT_SCALE) / 2
            local y = self.eTextY + GRID_Y_OFFSET + (r - 1) * GRID_ROW_GAP_3
            drawScaledText(label, x, y, CROSS_TEXT_SCALE)
            if id == self.menuCursor then
              drawScaledCode(CURSOR_CODE, x - CROSS_CURSOR_OFFSET, y, CROSS_TEXT_SCALE)
            end
          end
        end
      end
      return
    end
    -- Plain grid: the original 2x2 at GRID_ROW_GAP_2/GRID_TEXT_SCALE_2, or
    -- the 3-row SWITCH shape at the cross's own tighter gap/scale -- a 3rd
    -- row at the 2-row spacing would run past the shorter bottom box.
    local grid = self.gridRows
    local scale = self.swapEnabled and CROSS_TEXT_SCALE or GRID_TEXT_SCALE_2
    local gap = self.swapEnabled and GRID_ROW_GAP_3 or GRID_ROW_GAP_2
    for r = 1, #grid do
      for c = 1, 2 do
        local id = grid[r] and grid[r][c]
        if id then
          local label = MENU_LABELS[id]
          local slotX = self.eTextX + GRID_MARGIN_2 + (c - 1) * GRID_SLOT_2
          local x = slotX + (GRID_SLOT_2 - Font.width(label) * scale) / 2
          local y = self.eTextY + GRID_Y_OFFSET + (r - 1) * gap
          drawScaledText(label, x, y, scale)
          if id == self.menuCursor then
            if self.swapEnabled then
              drawScaledCode(CURSOR_CODE, x - CROSS_CURSOR_OFFSET, y, scale)
            else
              Font.drawCode(CURSOR_CODE, x - GRID_CURSOR_OFFSET_2, y)
            end
          end
        end
      end
    end
  end

  function Screen:drawActionMenuF()
    -- Blank, matching the real cart's own behavior -- confirmed directly
    -- against src/ui/gen2/BattleState.lua:1300-1304's own comment: "Gen 2
    -- has no 'What will X do?' line... the half of the box beside the
    -- 2x2 menu is BLANK on the cart" (BattleMenu runs
    -- EmptyBattleTextbox before LoadBattleMenu). This mod previously
    -- invented its own "<name>'s turn:" prompt here -- not vanilla,
    -- replaced on request.
    if self.message then
      drawWrapped(self.message, self.fTextX, self.fTextY, self.fChars)
    end
  end

  ------------------------------------------------------------------
  -- BAG: the real native pack UI (Gen2PackMenu), same call shape its
  -- own real battle call site uses (BattleState:openPack,
  -- src/ui/gen2/BattleState.lua:2171-2185) -- battle=true so picking an
  -- item goes straight to onChoose with no submenu, world={} matching
  -- that real call verbatim. Only ball items (def.pocket == "BALL",
  -- the same field BattleState:useItem itself branches on) do anything
  -- here yet -- every other item is a stated stub, not silently ignored.
  --
  -- suppressInputFrame (set in every callback below that returns
  -- control to this screen) guards against a real bug found live: B
  -- closing the native sub-menu and this screen's OWN B-handling both
  -- reading the same physical press on the very next update -- without
  -- it, cancelling out of the bag or party screen double-popped the
  -- stack and dropped straight back to the overworld instead of
  -- returning to this battle. See Screen:update's own check.
  ------------------------------------------------------------------
  function Screen:openBag()
    self.phase = "submenu"
    -- Gen 1's native BagMenu throws through the native BattleState, not this
    -- scene's model, so the backend opens a ball-only ListMenu wired straight
    -- to this screen's own throwBall instead (see native.lua).
    if not N.isGen2 then
      N.openBag(self)
      return
    end
    Screens.push(self.game, N.packMenuId(), {
      save = self.game.save,
      battle = true,
      world = {},
      onClose = function()
        self.game.stack:pop()
        self.suppressInputFrame = true
        self.phase = "actionMenu"
      end,
      onChoose = function(itemId)
        self.game.stack:pop()
        self.suppressInputFrame = true
        self:useItem(itemId)
      end,
    })
  end

  function Screen:useItem(itemId)
    local def = self.data.items and self.data.items[itemId]
    if not N.isBall(itemId, def) then
      self.message = "Can't use that here yet."
      self.phase = "actionMenu"
      return
    end
    if not self:catchAllowed() then
      self.message = "Can't throw a ball -- 2+ foes still standing!"
      self.phase = "actionMenu"
      return
    end
    self:throwBall(itemId)
  end

  -- The BALL is thrown at whichever single enemy is still alive --
  -- catchAllowed already guarantees at most one is.  This is the real native
  -- throw: the ball itself is the cart's own ANIM_THROW_POKE_BALL object, in
  -- the ball's native colour (N.ballPalette), flown from the thrower's own
  -- sprite onto the target's OWN on-screen sprite position, and the script's
  -- own catch loop then wobbles it to match -- the exact number of shakes the
  -- selected formula rolled (SV, Gen II or Gen I; see the CATCH FORMULA mod
  -- option and native.lua's CATCH RATE block) -- before the answer comes back;
  -- see Screen:startCatchAnim.  The catch
  -- RESOLVES on the frame that animation ends (Screen:resolveCatchAnim), so a
  -- ball thrown here looks like the cart's own rather than an instant dice
  -- roll.  When the animation cannot run -- a stock Gen 1 boot with no Gen 2
  -- anim data -- the catch resolves on the spot exactly as it always used to.
  --
  -- The ball LEAVES THE BAG on every valid throw (miss or catch), through
  -- N.consumeItem -- UseDisposableItem on Gen 2, Bag.remove on Gen 1.  The
  -- screen used to state the opposite as a known gap; the cart only ever
  -- spends the ball, so that gap is now closed.  Either way a miss still
  -- consumes this slot's action for the turn, the same as a move would.
  function Screen:throwBall(ballId)
    local target = nil
    for _, e in ipairs(self.enemyBattlers) do
      if self.combat.isAlive(e) then target = e break end
    end
    if not target then
      self.message = "No target to catch!"
      self.phase = "actionMenu"
      return
    end
    ballId = ballId or "POKE_BALL"
    N.consumeItem(self.game.save, ballId)
    -- The selected catch formula, in the backend -- see the CATCH RATE block
    -- in native.lua (the CATCH FORMULA mod option picks Gen IX, Gen II or
    -- Gen I).  The options carry the whole formula's context: the HP and
    -- species rate, the wild mon's level and status, and what the conditional
    -- balls read (the player's lead, its gender/species, weight, typing,
    -- fishing and dex state).  Terms with no Gen 1/Gen 2 counterpart (badges,
    -- dark grass, capture power) are simply absent and stay neutral.  Passing
    -- a real `battle` keeps the Gen 2 captured tail: Battle:caught on a
    -- success (Transform reload, the battle.catch_exp hook).  The raw dex
    -- `weight` (tenths of a pound) rides alongside `weightKg` because the Gen
    -- II Heavy Ball reads the cart's own tenths-of-a-pound value.
    local def = self.data.pokemon and self.data.pokemon[target.mon.species]
    local dexEntry = def and def.dexEntry
    local lead = self.playerBattlers[self.actingSlotIdx or 1]
      or self.playerBattlers[1]
    local leadMon = lead and lead.mon
    local dex = self.game.save and self.game.save.pokedex
    local caughtDex = dex and (dex.caught or dex.owned)
    local caught, shakes, a, chance = N.catchAttempt({
      ball = ballId,
      mon = target.mon,
      def = def,
      hp = target.mon.hp,
      maxHp = maxHpOf(target.mon),
      catchRate = def and def.catchRate,
      status = target.mon.status,
      level = target.mon.level,
      playerLevel = leadMon and leadMon.level,
      speed = target.mon.stats and target.mon.stats.speed,
      species = target.mon.species,
      playerSpecies = leadMon and leadMon.species,
      types = def and (def.types or def.type),
      weightKg = dexEntry and dexEntry.weight
        and (dexEntry.weight * 0.045359237) or nil,
      weight = dexEntry and dexEntry.weight,
      gender = target.mon.gender,
      playerGender = self.game.save and self.game.save.player
        and self.game.save.player.gender,
      fishing = self.battle and self.battle.fishing,
      registered = caughtDex and caughtDex[target.mon.species] and true or false,
      turn = self.battle and self.battle.turn,
      battle = self.battle,
      random = self.battle and self.battle.random,
    })
    -- BOSS CATCH: a wild boss is always caught.  Forced onto the pending
    -- result BEFORE startCatchAnim below, so the native ball plays the
    -- wobble count it is actually reporting (three shakes and a click)
    -- rather than a losing roll that was about to be overridden anyway.
    -- See special_boss.lua's own header for the option and the 1-HP half.
    local specialBoss = mod.exports.specialBoss
    if specialBoss and specialBoss.bossCatchApplies
        and specialBoss.bossCatchApplies(self.battle, target.mon) then
      caught, shakes = true, 3
    end
    local pending = {
      ballId = ballId,
      target = target,
      caught = caught and true or false,
      shakes = shakes or 0,
      rate = a or 0,
      chance = chance,
    }
    -- Play the game's own throw/catch animation first when the native anim
    -- data is there; the answer is held on self.catchPending and reported
    -- back by Screen:resolveCatchAnim the frame the animation ends.
    if self:startCatchAnim(pending) then
      self.catchPending = pending
      return
    end
    self:finishBallThrow(pending)
  end

  -- The outcome half of a ball throw, run once the cartoon is over (or
  -- immediately, when Screen:startCatchAnim could not run).  Split out so the
  -- same code serves both paths -- the native animation must not change WHAT a
  -- catch does, only how it is shown.
  function Screen:finishBallThrow(pending)
    local target, caught = pending.target, pending.caught
    local name = target.mon.nickname or target.mon.name or target.mon.species
    if not caught then
      -- The cart's own line for this wobble count, in the voice of whichever
      -- generation the CATCH FORMULA option selected (the backend owns the
      -- wording).  The old debug "(rate N/255)" is gone -- the rate is a
      -- property of the throw, not of how close the ball came, and the shake
      -- count IS the roll's own check result.
      self.message = N.ballMissMessage(pending.shakes)
      self:advanceSlotOrResolve()
      return
    end
    target.fainted = true
    target.caught = true
    -- Party filing: pure save-management, not combat logic, so it stays
    -- here rather than needing its own file. Same "added"/"full" shape
    -- g2-Battle-Scene's own catch.lua used.
    self.game.save.party = self.game.save.party or {}
    if #self.game.save.party < 6 then
      self.game.save.party[#self.game.save.party + 1] = target.mon
      self.overMessage = N.caughtMessage(name)
    else
      -- A full party sends the catch to the CURRENT BOX, the same as
      -- `.SendToPC` / `predef SendMonIntoBox` (item_effects.asm:548-550, 604).
      -- The exact storage API is generation-specific and lives in the backend
      -- (native.lua): Gen 2 inserts at the head of gen2 Boxes; Gen 1 uses the
      -- native src/pokemon/Boxes.lua deposit.
      local okBox, where = N.depositCatch(self.game.save, target.mon)
      if okBox then
        self.overMessage = N.caughtMessage(name) .. (where or "")
      else
        -- Said honestly rather than claiming a catch that did not happen.
        self.overMessage = N.caughtMessage(name)
          .. " ...but the PC could not be reached."
      end
    end
    self.outcome = "caught"
    self.phase = "over"
  end

  ------------------------------------------------------------------
  -- PKMN: a voluntary switch is QUEUED as this slot's action for the
  -- turn, not applied instantly -- it resolves at its own place in turn
  -- order (a synthetic high priority, always ahead of any move, the
  -- same rule the real games use, see Screen:advanceResolving), and
  -- the newly-sent-out mon does not act again this same turn. The slot
  -- being replaced is simply whichever one PKMN was chosen from -- no
  -- separate "which slot" step needed.
  --
  -- Opens the real native party UI (Gen2PartyMenu) the same way
  -- BattleState:openParty(forced=false) does (battleSubmenu=true --
  -- src/ui/gen2/BattleState.lua:2091-2101): picking a mon there opens
  -- STATS/SWITCH/CANCEL, and SWITCH is what calls onChoose(index, mon)
  -- back here. Validity (not fainted, not already active) is checked
  -- here after the fact, the same order BattleState's own real call
  -- does it in.
  ------------------------------------------------------------------
  function Screen:openSwitchMenu()
    self.phase = "submenu"
    local save = self.game.save
    if not N.isGen2 then
      -- Gen 1's native PartyMenu with forceSwitch/pickOnly and NO battle model:
      -- pressing A on a mon pops the menu and calls onSwitch, which is exactly
      -- this screen's own pick-a-switch-target flow (validity is checked in
      -- trySwitchIn below).  Passing the native battle would route the pick
      -- through the native BattleState instead of this scene.
      Screens.push(self.game, N.partyMenuId(), {
        save = save,
        party = save.party,
        forceSwitch = true,
        pickOnly = true,
        onSwitch = function(mon)
          self.suppressInputFrame = true
          self:trySwitchIn(mon)
        end,
        onCancel = function()
          self.suppressInputFrame = true
          self.phase = "actionMenu"
        end,
      })
      return
    end
    Screens.push(self.game, N.partyMenuId(), {
      save = save,
      party = save.party,
      prompt = "choose",
      battleSubmenu = true,
      onCancel = function()
        self.game.stack:pop()
        self.suppressInputFrame = true
        self.phase = "actionMenu"
      end,
      onChoose = function(index, mon)
        self.game.stack:pop()
        self.suppressInputFrame = true
        self:trySwitchIn(mon)
      end,
    })
  end

  function Screen:trySwitchIn(mon)
    for _, b in ipairs(self.playerBattlers) do
      if mon == b.mon then
        self.message = displayName(mon) .. " is already in battle!"
        self.phase = "actionMenu"
        return
      end
    end
    if (mon.hp or 0) <= 0 then
      self.message = displayName(mon) .. " has no energy left to battle!"
      self.phase = "actionMenu"
      return
    end
    self.queuedActions[#self.queuedActions + 1] = {
      kind = "switch",
      actorSlot = self.actingSlotIdx,
      mon = mon,
      actor = self.playerBattlers[self.actingSlotIdx], -- outgoing battler, turn-order speed only
      def = { priority = 99, name = "Switch" },
    }
    self:advanceSlotOrResolve()
  end

  ------------------------------------------------------------------
  -- FIGHT: pick a move (and a target, when 2 enemies are alive) for
  -- the current acting slot, queue it, then move to the next slot.
  ------------------------------------------------------------------
  function Screen:enterMoveSelect()
    local battler = self.playerBattlers[self.actingSlotIdx]
    local all = self.combat.allMoves(battler, self.data)
    -- Only a genuinely PP-less slot is skipped: native never opens the list
    -- when nothing has PP left. A slot whose only PP-legal moves are
    -- ENGINE-blocked (Choice lock, item move-type ban, unmet condition) still
    -- opens the list, so the player can be told why.
    local anyPp = false
    for _, entry in ipairs(all) do
      if (entry.slot.pp or 0) > 0 then anyPp = true break end
    end
    if not anyPp then
      -- Out of PP everywhere -- an explicit Phase 2 gap (no real
      -- Struggle yet): this slot simply can't act this turn. Native
      -- also never opens the list in this case (it goes straight to
      -- Struggle), so no 0-PP-only menu is ever shown.
      self:advanceSlotOrResolve()
      return
    end
    self.moveListCache = all
    -- Open the cursor on the first move the engine allows, so a Choice-locked
    -- mon lands on its locked move instead of a refused row.
    self.moveCursor = 1
    for i, entry in ipairs(all) do
      if entry.usable then self.moveCursor = i break end
    end
    self.moveSwapIndex = nil
    self.message = nil
    self.phase = "moveSelect"
  end

  function Screen:advanceSlotOrResolve()
    self.slotPtr = self.slotPtr + 1
    if self.slotPtr <= #self.turnSlots then
      self:enterActionMenu()
    else
      self:beginResolving()
    end
  end

  function Screen:queueAction(picked, target)
    local battler = self.playerBattlers[self.actingSlotIdx]
    self.queuedActions[#self.queuedActions + 1] = {
      kind = "fight",
      actor = battler, index = picked.index, slot = picked.slot, def = picked.def, target = target,
    }
  end

  -- Does this picked move hit every enemy at once (needs no target
  -- picker)? Authoritative answer: g9-battle-engine's isSpreadMove
  -- (national_dex target archetype) -- trusted when the engine has it.
  -- An OLD engine mod predating that export falls back to the move
  -- def's own `target` field when one is present, then to the
  -- module-local SPREAD_MOVE_IDS list -- so the picker is skipped even
  -- with a stale engine. (The engine's resolveTurnActions still
  -- re-resolves the full roster at resolution time either way, so
  -- skipping the picker never limits who actually gets hit.)
  function Screen:isSpreadMove(picked)
    if not picked then return false end
    local id = picked.slot and picked.slot.id
    local eng = self.g9dex and self.g9dex.exports and self.g9dex.exports.isSpreadMove
    if eng then
      local ok, res = pcall(eng, id)
      if ok then return res == true end
    end
    local tgt = picked.def and picked.def.target
    if tgt == "all-opponents" or tgt == "all-other-pokemon" then return true end
    return id and SPREAD_MOVE_IDS[id] == true or false
  end

  -- ROUND 26 (2026-09-10): can this picked move legally be aimed at one
  -- of the caster's OWN living teammates? Authoritative answer:
  -- g9-battle-engine's isAllyTargetable (national_dex's own target
  -- archetype plus the selected-pokemon/heal records like Heal Pulse).
  -- Trusted when the engine has it; an OLD engine predating that export
  -- falls back to the move def's own target/healing fields, so the
  -- picker still offers allies with a stale engine. Used only to widen
  -- the target picker -- the ENGINE still decides at resolution time
  -- whether a fainted ally means the move redirects (foe) or fails (ally).
  function Screen:isAllyTargetable(picked)
    if not picked then return false end
    local id = picked.slot and picked.slot.id
    local eng = self.g9dex and self.g9dex.exports and self.g9dex.exports.isAllyTargetable
    if eng then
      local ok, res = pcall(eng, id)
      if ok then return res == true end
    end
    local def = picked.def
    if def then
      if def.target == "ally" or def.target == "user-or-ally" then return true end
      if def.target == "selected-pokemon"
          and ((def.healing or 0) > 0 or def.category == "heal") then
        return true
      end
    end
    return false
  end

  function Screen:updateMoveSelect(input)
    -- A refusal (a 0-PP move was chosen) is showing in F: any press
    -- acknowledges it and drops straight back to the list, which is
    -- still exactly where it was (moveListCache/moveCursor untouched).
    -- Same "message + a press clears it" shape the action menu uses.
    if self.message then
      if input:wasPressed("a") or input:wasPressed("b")
          or input:wasPressed("up") or input:wasPressed("down") then
        self.message = nil
      end
      return
    end
    local count = #self.moveListCache
    if input:wasPressed("up") then
      self.moveCursor = self.moveCursor > 1 and self.moveCursor - 1 or count
    elseif input:wasPressed("down") then
      self.moveCursor = self.moveCursor < count and self.moveCursor + 1 or 1
    elseif input:wasPressed("select") then
      -- Vanilla's own move-reorder (src/ui/gen2/BattleState.lua's
      -- `.pressed_select`, MoveSelectionScreen): SELECT marks the move
      -- under the cursor, moving the cursor to another slot and pressing
      -- SELECT again swaps the two -- permanently, since this mod's
      -- battler holds the real save-party moves table by reference, same
      -- as the native swap reordering the party struct. Vanilla also
      -- refuses this while Transformed (borrowed moves, nothing of the
      -- mon's own to reorder) -- not modeled here since this mod's own
      -- Phase 2 scope has no Transform.
      local cursorEntry = self.moveListCache[self.moveCursor]
      if cursorEntry then
        if self.moveSwapIndex then
          if self.moveSwapIndex ~= cursorEntry.index then
            local battler = self.playerBattlers[self.actingSlotIdx]
            local moves = battler.mon.moves
            moves[self.moveSwapIndex], moves[cursorEntry.index] =
              moves[cursorEntry.index], moves[self.moveSwapIndex]
            self.moveListCache = self.combat.allMoves(battler, self.data)
          end
          self.moveSwapIndex = nil
        else
          self.moveSwapIndex = cursorEntry.index
        end
      end
    elseif input:wasPressed("b") then
      -- Back to THIS slot's own FIGHT/BAG/PKMN/RUN menu -- nothing has
      -- been queued yet at this point, so there's nothing to undo. A
      -- pending swap mark never survives leaving the list either.
      self.moveSwapIndex = nil
      self:enterActionMenu()
    elseif input:wasPressed("a") then
      -- Choosing a move cancels a pending swap rather than performing it
      -- (vanilla's own `xor a / ld [wSwappingMove], a` on the A arm).
      self.moveSwapIndex = nil
      local picked = self.moveListCache[self.moveCursor]
      if picked and not picked.usable then
        -- The move stays on the list exactly as native keeps it, but an
        -- unusable pick is refused instead of resolving: the ENGINE's own
        -- reason (Choice lock / item move-type ban / unmet move condition)
        -- when it gave one, else native's own "No PP left for this move!"
        -- arm. Show the message and stay in the list. The engine's
        -- executeAction refuses it too, but refusing at the menu is what
        -- the native screens do, and it keeps the player told.
        self.message = picked.invalidReason or MOVE_NO_PP_TEXT
        return
      end
      local aliveEnemies = {}
      for _, e in ipairs(self.enemyBattlers) do
        if self.combat.isAlive(e) then aliveEnemies[#aliveEnemies + 1] = e end
      end
      -- ROUND 26: a move that can legally be aimed at an ally (Heal Pulse,
      -- Helping Hand, Aromatherapy-shaped support -- the engine's own
      -- isAllyTargetable is the authority) also offers the acting
      -- battler's OWN living teammates in the picker, listed first, so the
      -- player can choose who to heal/support. Every other move keeps the
      -- enemy-only picker exactly as before.
      local candidates = aliveEnemies
      if self:isAllyTargetable(picked) then
        candidates = {}
        local caster = self.playerBattlers[self.actingSlotIdx]
        for _, a in ipairs(self.playerBattlers) do
          if a ~= caster and self.combat.isAlive(a) then
            candidates[#candidates + 1] = a
          end
        end
        for _, e in ipairs(aliveEnemies) do
          candidates[#candidates + 1] = e
        end
      end
      if #candidates > 1 then
        -- A move that targets every adjacent enemy by itself (LEER, Muddy
        -- Water, Earthquake, ...) has nothing to choose -- the picker is
        -- skipped entirely and the first alive enemy is queued as a
        -- placeholder target; g9-battle-engine's resolveTurnActions
        -- re-resolves the full roster (resolveMoveTargets) at resolution
        -- time, so the placeholder never limits who actually gets hit.
        if self:isSpreadMove(picked) then
          self:queueAction(picked, aliveEnemies[1] or candidates[1])
          self:advanceSlotOrResolve()
        else
          self.pendingPick = picked
          self.targetCandidates = candidates
          self.targetCursor = 1
          self.phase = "targetSelect"
        end
      elseif #candidates == 1 then
        self:queueAction(picked, candidates[1])
        self:advanceSlotOrResolve()
      else
        -- Nobody left to target -- shouldn't reach here (the battle would
        -- already have ended), kept defensive rather than assumed.
        self:beginResolving()
      end
    end
  end

  function Screen:drawMoveSelect()
    -- A refusal (0-PP pick) takes over F until acknowledged, the way the
    -- native screen's message box replaces the move list.
    if self.message then
      drawWrapped(self.message, self.fTextX, self.fTextY, self.fChars)
      return
    end
    -- No "<name>'s move:" header -- the move list starts right at
    -- fTextY instead of fTextY+9, using the row that line used to sit
    -- on rather than leaving it blank. Every known move is listed,
    -- including 0-PP ones (the PP column is what says so).
    for i, entry in ipairs(self.moveListCache) do
      local label = string.format("%-10s PP %d/%d",
        entry.def.name or entry.def.id, entry.slot.pp,
        self.combat.maxPpOf(entry.slot, entry.def))
      Font.draw(label, self.fTextX + 12, self.fTextY + (i - 1) * 9)
      if self.moveSwapIndex == entry.index then
        Font.drawCode(SWAP_MARKER_CODE, self.fTextX + 6, self.fTextY + (i - 1) * 9)
      end
    end
    Font.drawCode(CURSOR_CODE, self.fTextX, self.fTextY + (self.moveCursor - 1) * 9)
  end

  ------------------------------------------------------------------
  -- TARGET SELECT -- entered when there is more than one candidate: two
  -- or more living enemies, or an ally-targetable move (Heal Pulse and
  -- friends) whose own living teammates join the list beside the foes
  -- (round 26). B cancels back to the move list; A queues the pick.
  --
  -- ROUND EIGHTY-TWO (user request): the picker is read off the FIELD, not
  -- off a list. F carries only its "Choose a target:" prompt and the cursor
  -- is an arrow drawn over whichever mon is selected (Screen:drawTargetMark)
  -- -- so each candidate is identified by its own sprite's position, exactly
  -- as the user asked ("the text box should only say 'Choose a target:' and
  -- we move the enemy selection arrow to cycle through sprite pos"). Both
  -- axes cycle the cursor, since the candidates are laid out horizontally: a
  -- side-by-side row of mons reads naturally with left/right.
  ------------------------------------------------------------------
  function Screen:updateTargetSelect(input)
    local count = #self.targetCandidates
    if input:wasPressed("up") or input:wasPressed("left") then
      self.targetCursor = self.targetCursor > 1 and self.targetCursor - 1 or count
    elseif input:wasPressed("down") or input:wasPressed("right") then
      self.targetCursor = self.targetCursor < count and self.targetCursor + 1 or 1
    elseif input:wasPressed("b") then
      -- Back to move selection -- moveListCache/moveCursor are still
      -- exactly as they were, so the player lands right back where they
      -- left off rather than restarting the move list from the top.
      self.pendingPick = nil
      self.phase = "moveSelect"
    elseif input:wasPressed("a") then
      local target = self.targetCandidates[self.targetCursor]
      self:queueAction(self.pendingPick, target)
      self.pendingPick = nil
      self:advanceSlotOrResolve()
    end
  end

  -- F's whole contribution to the picker: the prompt, and nothing else. The
  -- per-candidate name/HP list that used to sit under it is gone (round
  -- eighty-two) -- the stat readouts over the mons already carry that, and
  -- the selection is shown on the field by drawTargetMark.
  function Screen:drawTargetSelect()
    Font.draw("Choose a target:", self.fTextX, self.fTextY)
  end

  -- The picker's cursor, drawn on the FIELD: a small down-pointing triangle
  -- sitting just above the stat readout of whichever candidate
  -- `targetCursor` is on, so the arrow cycles across the enemy (or ally)
  -- sprites' own positions. The x is that battler's own readout centre --
  -- which, now that the sprite grid's pitch IS the readout's pitch, is also
  -- the mon's own centre. A one-pixel bob keeps the eye on it.
  --
  -- Drawn as GEOMETRY (five one-pixel rectangles), not a font glyph: the
  -- engine's cursor glyph is a RIGHT-pointing arrow, and rotating it would
  -- depend on the running generation's font page, whereas a few rectangles
  -- are the same arrow on both. self.hudMark (filled by drawContent's HUD
  -- pass this frame) supplies the anchor; the 8px lift clears the readout's
  -- own top edge, and the clamp keeps it on-canvas for a very tall mon whose
  -- readout has been pushed up off the top of the field.
  --
  -- The same arrow shape serves the SWITCH cue below: `outline` draws only
  -- each row's two edge pixels (and the tip) so the OWNER of a swap can be
  -- marked with a hollow frame of exactly the selection arrow's size.
  local function drawArrowGlyph(cx, top, outline)
    love.graphics.setColor(0, 0, 0, 1)
    for row = 0, 4 do
      local half = 4 - row
      if outline and half > 0 then
        love.graphics.rectangle("fill", cx - half, top + row, 1, 1)
        love.graphics.rectangle("fill", cx + half, top + row, 1, 1)
      else
        love.graphics.rectangle("fill", cx - half, top + row, half * 2 + 1, 1)
      end
    end
  end

  function Screen:drawTargetMark()
    if self.phase ~= "targetSelect" then return end
    local target = self.targetCandidates and self.targetCandidates[self.targetCursor]
    local mark = target and self.hudMark and self.hudMark[target]
    if not mark then return end
    local bob = math.floor(love.timer.getTime() * 4) % 2
    local cx = math.floor(mark.x + 0.5)
    local top = math.max(0, math.floor(mark.top) - 8 - bob)
    drawArrowGlyph(cx, top, false)
  end

  ------------------------------------------------------------------
  -- SWITCH -- a POSITIONAL swap between ADJACENT allies, not the PKMN
  -- recall-and-replace switch that button owns. It exists only where the
  -- preset actually put two or more living allies on the field and the
  -- battle is not a bossFight (self.swapEnabled, decided once in
  -- Screen.new from the shipped roster), so the button can never appear
  -- where a swap has no meaning. The OWNER is the battler whose turn this
  -- is; its adjacent living allies are the candidates. Choosing one
  -- queues it as this slot's action (kind="swap"); the field is
  -- re-shuffled at resolution, before the PKMN switch queue, so the new
  -- positions hold for the rest of the turn. The enemy side gets the same
  -- swap through the exported mod.exports.swapPositions.
  ------------------------------------------------------------------
  function Screen:enterSwapSelect()
    local owner = self.playerBattlers[self.actingSlotIdx]
    local candidates = {}
    for _, slot in ipairs({ self.actingSlotIdx - 1, self.actingSlotIdx + 1 }) do
      local ally = self.playerBattlers[slot]
      if ally and self.combat.isAlive(ally) then candidates[#candidates + 1] = slot end
    end
    if #candidates == 0 then
      self.message = (owner and displayName(owner.mon) or "That Pokemon")
        .. " has no adjacent ally to switch with."
      self.phase = "actionMenu"
      return
    end
    self.swapCandidates = candidates
    self.swapCursor = 1
    self.message = nil
    self.phase = "swapSelect"
  end

  function Screen:updateSwapSelect(input)
    local count = #self.swapCandidates
    if input:wasPressed("up") or input:wasPressed("left") then
      self.swapCursor = self.swapCursor > 1 and self.swapCursor - 1 or count
    elseif input:wasPressed("down") or input:wasPressed("right") then
      self.swapCursor = self.swapCursor < count and self.swapCursor + 1 or 1
    elseif input:wasPressed("b") then
      -- Back to this slot's own action menu -- nothing has been queued,
      -- so there is nothing to undo.
      self.swapCandidates = nil
      self:enterActionMenu()
    elseif input:wasPressed("a") then
      self:queueSwapAction(self.actingSlotIdx, self.swapCandidates[self.swapCursor])
      self.swapCandidates = nil
      self:advanceSlotOrResolve()
    end
  end

  -- F carries only the prompt, exactly as the target picker does -- the
  -- field arrows (drawSwapMark) say the rest.
  function Screen:drawSwapSelect()
    Font.draw("Switch with whom?", self.fTextX, self.fTextY)
  end

  function Screen:queueSwapAction(slotA, slotB)
    local owner = self.playerBattlers[slotA]
    self.queuedActions[#self.queuedActions + 1] = {
      kind = "swap",
      actorSlot = slotA,
      targetSlot = slotB,
      actor = owner,
      def = { priority = 99, name = "Switch" },
    }
    -- Kept so the field keeps showing WHO owns the swap after the target
    -- is picked (drawSwapMark) -- dropped again as the swap resolves.
    if owner then self.swapOwnerMarks[#self.swapOwnerMarks + 1] = owner end
  end

  function Screen:clearSwapOwnerMark(battler)
    if not battler then return end
    for i, b in ipairs(self.swapOwnerMarks) do
      if b == battler then table.remove(self.swapOwnerMarks, i) break end
    end
  end

  -- The field cue: a FILLED arrow over the candidate under the cursor (the
  -- swap's TARGET) and a HOLLOW frame arrow of the same size over the
  -- battler that OWNS the swap -- the acting slot while the choice is
  -- being made, and any owner whose swap is queued but not yet resolved
  -- (self.swapOwnerMarks) -- so the cue stays on the mon that called it
  -- ("leave on owner's sprite a black frame arrow ... for visual cue of
  -- who is owning the swap").
  function Screen:drawSwapMark()
    if not self.hudMark then return end
    local bob = math.floor(love.timer.getTime() * 4) % 2
    local function markFor(battler, outline)
      local m = battler and self.hudMark[battler]
      if not m then return end
      local cx = math.floor(m.x + 0.5)
      local top = math.max(0, math.floor(m.top) - 8 - bob)
      drawArrowGlyph(cx, top, outline)
    end
    if self.phase == "swapSelect" then
      markFor(self.playerBattlers[self.actingSlotIdx], true)
      local target = self.swapCandidates
        and self.playerBattlers[self.swapCandidates[self.swapCursor]]
      markFor(target, false)
    end
    for _, battler in ipairs(self.swapOwnerMarks or {}) do
      markFor(battler, true)
    end
  end

  ------------------------------------------------------------------
  -- RESOLVING: enemy AI actions are chosen here, combined with the
  -- queued player actions, ordered once by combat.lua, then executed
  -- and displayed one message at a time (advance on A/B) -- lazily, so
  -- an actor or target that faints mid-turn is checked at the moment
  -- its own action would run, not decided upfront.
  ------------------------------------------------------------------

  -- Vanilla's own single-battle pic anchors (src/ui/gen2/BattleState.lua
  -- :593-598's own PLAYER_PIC_TILE_X/Y=2,6 and ENEMY_PIC_TILE_X/Y=12,0,
  -- both 6/7-tile boxes), reduced to a bottom-center point the same way
  -- this mod's own drawSprite anchors things -- what every move
  -- animation script's own baked x/y coordinates assume they're near.
  local VANILLA_PLAYER_ANCHOR = { x = 40, y = 96 }
  local VANILLA_ENEMY_ANCHOR = { x = 124, y = 56 }

  -- ROUND 62 (2026-09-10): where a SPREAD move's animation should land.
  -- A spread move hits a whole SIDE at once, so anchoring its animation on
  -- whichever single mon combat.lua's turn_order happened to loop to (it
  -- emits one useMove/move event per expanded target -- see that file's own
  -- resolveTurnActions) is wrong: the animation would visibly snap to one
  -- victim instead of washing over the side. The user's rule: a spread move
  -- is cast on the MIDDLE of the OPPOSING side's sprite area -- an enemy's
  -- spread move centres over the PLAYER's side, a player's over the ENEMY's.
  -- The middle is the mean of each drawn sprite's centre-x and its vertical
  -- centre (top + drawn height/2) -- a real centre-of-mass of what is on
  -- screen, not a fixed grid slot, so an under-strength or horde side still
  -- centres on the mons actually there. Returns nil (caller falls back to
  -- the single-target anchor) when no sprite on that side is drawn yet.
  -- `top`/`h` are stamped into self.spriteAnchor by drawContent's sprite pass.
  local function sideSpriteCentre(screen, side)
    local list = (side == "player") and screen.playerBattlers or screen.enemyBattlers
    local sx, sy, n = 0, 0, 0
    for _, b in ipairs(list or {}) do
      local a = screen.spriteAnchor[b]
      if a and a.h then
        sx = sx + a.x
        sy = sy + a.top + a.h / 2
        n = n + 1
      end
    end
    if n == 0 then return nil end
    return { x = sx / n, y = sy / n }
  end

  -- Is this move a spread move, asked by BARE STRING ID (not a picked slot)?
  -- startMoveAnim only has the resolved { id = ... } def, so it can't call
  -- Screen:isSpreadMove (which reads a picked slot). Same authority order as
  -- that method: the engine's exported isSpreadMove first, then the
  -- module-local SPREAD_MOVE_IDS last-resort list.
  local function isSpreadMoveId(screen, id)
    if not id then return false end
    local eng = screen.g9dex and screen.g9dex.exports and screen.g9dex.exports.isSpreadMove
    if eng then
      local ok, res = pcall(eng, id)
      if ok then return res == true end
    end
    return SPREAD_MOVE_IDS[id] == true
  end

  -- Does the running animation's own native BG layer have this side's mon
  -- hidden right now?  BATTLE_BG_EFFECT_HIDE_MON is how the cart's
  -- ANIM_THROW_POKE_BALL sucks the target into the ball once it lands (and
  -- SHOW_MON how it puts the mon back on a breakout), and the cart's battle
  -- screen reads it straight off the same bg table (BattleState:picBoxCleared
  -- -> animPicState, src/ui/gen2/BattleState.lua:1720-1722).  THIS screen
  -- draws its own sprites rather than going through BattleAnimView's battler
  -- pics, so it has to honour that flag itself.  Scoped to the BALL throw --
  -- the one animation this file starts expecting it -- so no existing move
  -- animation's look changes.
  local function animHidesMon(screen, side)
    local anim = screen.moveAnim
    if not anim then return false end
    -- Gen 1's arm hides the ENEMY mon itself (the ball's target), driven by
    -- the animation's own HIDEPIC_ANIM/SHOWPIC_ANIM rows -- the native
    -- equivalent of BattleState.enemyHidden (src/battle/BattleState.lua:
    -- 1487-1492).  Only an enemy is ever caught, so that is the only side.
    if anim.gen1 then
      return anim.hiddenEnemy == true and side == "enemy"
    end
    if not anim.isBall then return false end
    local bg = anim.runner and anim.runner.bg
    return (bg and bg.hidden and bg.hidden[side]) == true
  end

  -- Starts def's real move-animation -- Gen 2's own AnimRunner/
  -- AnimObjects engine (this file's own header explains why this mod
  -- can drive it directly, no native BattleState class needed), remapped
  -- to originate from the ACTOR's real on-screen position in THIS mod's
  -- own widescreen layout (self.spriteAnchor, filled in by drawContent's
  -- own drawSprite calls) instead of vanilla's fixed single-battle spot.
  --
  -- Only WHERE it starts is remapped, by a flat (offsetX, offsetY)
  -- translate applied around the whole draw (see drawContent) -- the
  -- animation's own internal motion (how far it travels, its arc) is
  -- still vanilla's own calibrated distance for that move. A target
  -- sitting outside vanilla's normal single-battle spacing (this mod's
  -- own doubled/widescreen layout routinely does) used to only travel
  -- vanilla's own fixed distance (a flat translate never changed HOW
  -- FAR anything moved) -- user-reported and confirmed via screenshot:
  -- the water droplets stopped about halfway to the target. Fixed below
  -- with a non-uniform SCALE around the translate, computed from the
  -- real actor-target gap vs. vanilla's own, so the same underlying
  -- per-frame motion (AnimObjects.lua's stepToTarget etc., untouched)
  -- now covers the real distance -- a pure rendering-layer fix, not a
  -- change to shared step-function logic every other move also uses.
  -- Known remaining rough edge: the splash's own TRIGGER (AnimObjects.
  -- lua's `st.yOffset >= 0x18`) is a fixed Y-offset threshold, unrelated
  -- to this new scale, so a heavily stretched/shrunk gap can still show
  -- the splash a little early or late relative to the stretched travel.
  --
  -- No sound/cry hooks wired -- this mod's own audio call shape was not
  -- confirmed, so this stays visual-only rather than a guessed call into
  -- an unverified API; every hook is a safe, silent no-op.
  --
  -- Spread moves (ROUND 62): a move that hits a whole side ignores this
  -- per-target anchor and instead aims at the OPPOSING side's sprite-area
  -- centre, so one invocation washes over the side instead of snapping to
  -- a single victim -- see sideSpriteCentre above.
  function Screen:startMoveAnim(def, actor, target)
    -- Gen 2 drives AnimRunner/BattleAnimView; when those are absent this is
    -- a Gen 1 boot, whose own AnimPlayer arm plays the move instead.
    if not (AnimRunner and BattleAnimView) then
      return self:startMoveAnimGen1(def, actor, target)
    end
    local animsData = N.animData(self.data)
    if not (animsData and def and def.id) then return end
    -- KEYED BY THE MOVE'S OWN STRING ID ("WATER_GUN"), NOT its numeric
    -- ROM index -- confirmed directly against the real extracted data
    -- (gold/data/generated/battle_anims.lua's own `moves = { ABSORB=,
    -- ACID=, ... }` table). AnimObjects.lua:312 confirms animId is
    -- compared against string ids directly (`animId == "KINESIS"`), so
    -- this is used for both the lookup AND the animId passed below.
    local key = AnimRunner.scriptForMove(animsData, def.id)
    if not key then return end
    local anchor = self.spriteAnchor[actor]
    if not anchor then return end
    local vanillaActorAnchor = (actor.side == "player") and VANILLA_PLAYER_ANCHOR or VANILLA_ENEMY_ANCHOR
    local vanillaTargetAnchor = (actor.side == "player") and VANILLA_ENEMY_ANCHOR or VANILLA_PLAYER_ANCHOR
    -- Scale factor per axis: real gap / vanilla's own assumed gap.
    -- Falls back to 1 (vanilla's own untouched distance) when the
    -- target's own anchor isn't known yet or vanilla's own axis gap is
    -- zero (would divide by zero) -- a plain, safe default, not a crash.
    local scaleX, scaleY = 1, 1
    -- A SPREAD move lands on the whole OPPOSING side, not one victim: aim
    -- it at that side's sprite-area centre (ROUND 62 rule above), falling
    -- back to the single target's own anchor if the side isn't drawn yet.
    local targetAnchor
    if isSpreadMoveId(self, def.id) then
      targetAnchor = sideSpriteCentre(self, (actor.side == "player") and "enemy" or "player")
    end
    targetAnchor = targetAnchor or self.spriteAnchor[target]
    if targetAnchor then
      local vdx = vanillaTargetAnchor.x - vanillaActorAnchor.x
      local vdy = vanillaTargetAnchor.y - vanillaActorAnchor.y
      if vdx ~= 0 then scaleX = (targetAnchor.x - anchor.x) / vdx end
      if vdy ~= 0 then scaleY = (targetAnchor.y - anchor.y) / vdy end
    end
    self.animView = self.animView or BattleAnimView.new(animsData, N.paletteData(self.data))
    local runner = AnimRunner.new({
      data = animsData,
      constants = N.constantsData(self.data),
      battleTurn = (actor.side == "player") and 0 or 1,
      animId = def.id,
      param = 0,
      sfxOrder = self.data.audio and self.data.audio.sfxOrder,
      hooks = {
        sound = function() end,
        cry = function() end,
        pokeballWobble = function() return false end,
      },
    })
    runner:start(key)
    -- Instance-only override (shadows the class method on just this one
    -- pool via Lua's normal metatable __index fallback -- the shared
    -- engine file itself is untouched, and every other runner/battle
    -- keeps the original): tags each OAM entry this struct contributes
    -- with the struct table itself. A struct's own table is allocated
    -- once and reused for its whole lifetime, so this is a stable
    -- identity to later group entries by -- needed because a single
    -- struct's own frame can legitimately emit more than one entry (a
    -- multi-tile composite picture, e.g. a splash), and the pool's own
    -- flattened OAM list keeps no such reference on its own.
    local pool = runner.objects
    local poolUpdateOam = pool.updateOam
    pool.updateOam = function(self, st)
      local before = #self.oam
      local result = poolUpdateOam(self, st)
      for i = before + 1, #self.oam do
        self.oam[i].moveAnimStruct = st
      end
      return result
    end
    -- BattleAnimView:objPalette(name, battle) reads battle.player/.enemy
    -- (mon-shaped: .species/.shiny) for the PAL_BATTLE_OB_PLAYER/ENEMY
    -- palette names -- the actual mons in THIS exchange, not just
    -- whichever battler happens to be in slot 1 of a multi-battler side.
    local battleForPalette = (actor.side == "player")
      and { player = actor.mon, enemy = target and target.mon }
      or { player = target and target.mon, enemy = actor.mon }
    self.moveAnim = {
      runner = runner,
      anchorX = anchor.x,
      anchorY = anchor.y,
      vanillaAnchorX = vanillaActorAnchor.x,
      vanillaAnchorY = vanillaActorAnchor.y,
      scaleX = scaleX,
      scaleY = scaleY,
      battle = battleForPalette,
    }
  end

  ------------------------------------------------------------------
  -- THE THROWN BALL'S OWN ANIMATION -- the cart's ANIM_THROW_POKE_BALL.
  --
  -- Round eighty-nine, explicit user request: the ball a catch is thrown
  -- with must be the game's own throw -- native asset, in the ball's own
  -- native colour, flown to the POKEMON'S OWN sprite position -- with the
  -- game's own catch animation (the ball landing, sucking the mon in, then
  -- the wobbles) playing before the catch is resolved.
  --
  -- This is not a second animation engine: it is the SAME native
  -- AnimRunner/BattleAnimView contract Screen:startMoveAnim already drives,
  -- with the shared ANIM_* id instead of a move's script key.  Everything
  -- the cart's own screen hands that runner is handed here too:
  --   * ballPalette -- N.ballPalette(ballId), the PAL_BATTLE_OB_* name the
  --     ball's object function stamps onto every ball frame (the "native
  --     colour");
  --   * param       -- N.ballAnimParam, wBattleAnimParam, which the script's
  --     anim_if_param_equal rows branch on;
  --   * hBattleTurn -- 0 regardless of turn order, because the ball is always
  --     thrown from the player's side (src/ui/gen2/BattleState.lua:3286-3294);
  --   * pokeballWobble -- the catch answer this screen already computed,
  --     replayed as the modern formula's own shake count
  --     (N.ballWobbleFromChecks), so the cartoon and the dice agree instead of
  --     the wobble count being re-rolled independently of the rate.
  --
  -- POSITION.  The native script's ball flies vanilla's fixed single-battle
  -- arc, but a doubles landing spot is a per-slot platform, so the object
  -- positions are remapped exactly as Screen:startMoveAnim remaps a move's:
  -- the thrower's real on-screen anchor pins the start and the real
  -- thrower->target gap scales the rest, so the ball leaves the acting mon's
  -- own sprite and lands ON the target's own sprite (its self.spriteAnchor
  -- bottom-centre, the same point the sprite pass bottom-anchors the mon to).
  -- The catch itself then ends through Screen:resolveCatchAnim.
  --
  -- Returns false when the animation cannot run at all (a stock Gen 1 boot,
  -- or a cache without the anim/its sheet), so Screen:throwBall falls back to
  -- its old instant resolution rather than stalling.
  function Screen:startCatchAnim(pending)
    -- Gen 2's AnimRunner/BattleAnimView contract; a Gen 1 boot has no Gen 2
    -- anim data, so its own native ball chain takes over instead.
    if not (AnimRunner and BattleAnimView) then
      return self:startCatchAnimGen1(pending)
    end
    local animsData = N.animData(self.data)
    local key = animsData and animsData.ids
      and animsData.ids.ANIM_THROW_POKE_BALL
    if not key then return false end
    local target = pending.target
    local targetAnchor = self.spriteAnchor[target]
    if not targetAnchor then return false end
    -- The thrower is the mon whose action menu the BAG was opened from -- the
    -- very slot this ball's turn is spent on.  Fall back to the first living
    -- battler when the throw came from outside a turn (the askBattleChoice
    -- primitive), which is the acting mon in every ordinary single-battle
    -- fight anyway.
    local thrower = self.playerBattlers[self.actingSlotIdx or 1]
      or self.playerBattlers[1]
    local throwerAnchor = thrower and self.spriteAnchor[thrower]
    local actorAnchor = throwerAnchor or VANILLA_PLAYER_ANCHOR
    local vanillaActorAnchor = VANILLA_PLAYER_ANCHOR
    local vanillaTargetAnchor = VANILLA_ENEMY_ANCHOR
    -- Scale per axis: real gap / vanilla's own assumed gap, so the vanilla
    -- arc's own shape covers the real distance (a flat translate could never
    -- change how FAR anything moved).  A zero vanilla axis gap would divide by
    -- zero, so it keeps vanilla's own 1.
    local scaleX, scaleY = 1, 1
    local vdx = vanillaTargetAnchor.x - vanillaActorAnchor.x
    local vdy = vanillaTargetAnchor.y - vanillaActorAnchor.y
    if vdx ~= 0 then scaleX = (targetAnchor.x - actorAnchor.x) / vdx end
    if vdy ~= 0 then scaleY = (targetAnchor.y - actorAnchor.y) / vdy end
    self.animView = self.animView or
      BattleAnimView.new(animsData, N.paletteData(self.data))
    -- The modern formula decided the wobble count (its four shake checks);
    -- this hands the ball's own script that exact count, so the cartoon and
    -- the dice agree -- a caught mon wobbles three times and clicks, a
    -- failure wobbles 0-3 times and breaks free.
    local wobble = N.ballWobbleFromChecks(pending.caught, pending.shakes)
    local runner = AnimRunner.new({
      data = animsData,
      constants = N.constantsData(self.data),
      battleTurn = 0,
      animId = "ANIM_THROW_POKE_BALL",
      param = N.ballAnimParam(self.data, pending.ballId),
      sfxOrder = self.data.audio and self.data.audio.sfxOrder,
      ballPalette = N.ballPalette(pending.ballId),
      hooks = {
        -- The throw's own SFX_THROW_BALL / SFX_BALL_POOF, through the one
        -- ungated stereo path (native's own startAnim sound hook).
        sound = function(name)
          if N.playAnimSfx then N.playAnimSfx(self.data, name) end
        end,
        -- No cry in this animation, and no pitch shift in this port anyway.
        cry = function() end,
        -- GetPokeBallWobble's answer, which the ball's own script branches on.
        pokeballWobble = wobble,
      },
    })
    runner:start(key)
    -- The same instance-only OAM tag Screen:startMoveAnim applies, for the
    -- same reason: Screen:drawMoveAnimObjects groups entries by the struct
    -- that emitted them, and the pool keeps no such reference of its own.
    local pool = runner.objects
    local poolUpdateOam = pool.updateOam
    pool.updateOam = function(self, st)
      local before = #self.oam
      local result = poolUpdateOam(self, st)
      for i = before + 1, #self.oam do
        self.oam[i].moveAnimStruct = st
      end
      return result
    end
    self.moveAnim = {
      -- Marks this runner as a BALL throw, which is what lets the sprite pass
      -- honour the animation's own hide/show-mon BG effects (see
      -- animHidesMon) without changing how any move animation draws.
      isBall = true,
      runner = runner,
      anchorX = actorAnchor.x,
      anchorY = actorAnchor.y,
      vanillaAnchorX = vanillaActorAnchor.x,
      vanillaAnchorY = vanillaActorAnchor.y,
      scaleX = scaleX,
      scaleY = scaleY,
      -- Only read by BattleAnimView:objPalette for the two battler palettes;
      -- the ball's own palette is the fixed battleObjects block, so this is
      -- just the pair of mons in this throw.
      battle = { player = thrower and thrower.mon, enemy = target and target.mon },
      -- Run once the animation genuinely ends (see Screen:update), so the
      -- catch is reported at the same beat the cart reports it.
      onFinish = function() self:resolveCatchAnim() end,
    }
    return true
  end

  -- The frame the throw/catch animation ends: hand the held answer to the
  -- normal resolution.  Kept separate from finishBallThrow so the anim's own
  -- onFinish reads as exactly one step.
  function Screen:resolveCatchAnim()
    local pending = self.catchPending
    self.catchPending = nil
    if pending then self:finishBallThrow(pending) end
  end

  -- Which loaded sheet a tile id falls in -- BattleAnimView.lua's own
  -- local helper (:81-89, not exported on the class), copied verbatim
  -- rather than reached into, since drawMoveAnimObjects below needs it
  -- too and there's no public path to it.
  local function sheetForTile(runner, tile)
    for i = #runner.loaded, 1, -1 do
      local entry = runner.loaded[i]
      if tile >= entry.tile and tile < entry.tile + math.max(entry.tiles, 1) then
        return entry, tile - entry.tile
      end
    end
    return nil
  end

  local MOVE_ANIM_OAM_X_BIAS, MOVE_ANIM_OAM_Y_BIAS = 8, 16
  local MOVE_ANIM_OAM_XFLIP, MOVE_ANIM_OAM_YFLIP = 0x20, 0x40

  -- A faithful copy of BattleAnimView:drawObjects (src/ui/gen2/
  -- BattleAnimView.lua:108-147), with one change: each object's own
  -- SCREEN position is remapped through Screen:startMoveAnim's own
  -- anchor/scale (the real attacker position and the real attacker-
  -- target gap) instead of drawn at vanilla's raw, fixed single-battle
  -- coordinate. Deliberately NOT a love.graphics.scale() around the
  -- whole draw call instead -- that would also stretch each droplet
  -- SPRITE itself (elongating/squashing the tile image), not just where
  -- it lands; this remaps position only; :image/:quad/:objPalette are
  -- BattleAnimView's real public methods, reused as-is via self.animView.
  --
  -- One struct's frame can emit MORE THAN ONE of these OAM entries (the
  -- engine's own animation pool builds a struct's whole oamset --
  -- multiple tiles fused into one composite picture, e.g. a splash --
  -- from a single base position plus small fixed per-tile offsets).
  -- Remapping each entry independently around the shared anchor scales
  -- those small fixed offsets too whenever scaleX/scaleY isn't exactly
  -- 1, prying a composite sprite's own tiles apart. A first attempt at
  -- fixing that by grouping entries purely by ON-SCREEN PROXIMITY,
  -- recomputed fresh every frame, traded that bug for a worse one: as
  -- independent droplets converge toward the same landing point their
  -- ad hoc groupings change frame to frame, so the shared delta jumps
  -- discontinuously even though each droplet's own position is moving
  -- smoothly -- reported as the sprites warping/teleporting rather than
  -- following a fluid arc. Entries are grouped by their true source
  -- struct instead (tagged onto each entry by the updateOam override
  -- above), which is a stable identity for that droplet's whole
  -- lifetime, so the group's reference position is that struct's own
  -- x/y -- evolving continuously frame to frame exactly as the struct
  -- itself moves, with no dependence on any other object's position.
  function Screen:drawMoveAnimObjects()
    local view = self.animView
    local anim = self.moveAnim
    -- Gen 1's own arm draws its own compiled OAM steps (see
    -- Screen:drawGen1AnimSprites below).
    if anim.gen1 then return self:drawGen1AnimSprites(anim) end
    local runner, battle = anim.runner, anim.battle
    local G = love.graphics
    G.setColor(1, 1, 1, 1)

    local order = {}
    local groups = {}
    for _, obj in ipairs(runner:oam()) do
      local st = obj.moveAnimStruct
      local group = groups[st]
      if not group then
        group = {}
        groups[st] = group
        order[#order + 1] = st
      end
      group[#group + 1] = obj
    end

    for _, st in ipairs(order) do
      local cluster = groups[st]
      local refScreenX = st.x - MOVE_ANIM_OAM_X_BIAS
      local refScreenY = st.y - MOVE_ANIM_OAM_Y_BIAS
      local deltaX = (anim.anchorX + anim.scaleX * (refScreenX - anim.vanillaAnchorX)) - refScreenX
      local deltaY = (anim.anchorY + anim.scaleY * (refScreenY - anim.vanillaAnchorY)) - refScreenY

      for _, obj in ipairs(cluster) do
        local entry, index = sheetForTile(runner, obj.tile)
        if entry and not entry.battler then
          local sheet = (view.data.gfx or {})[entry.gfx]
          local image = sheet and view:image(sheet.image)
          if image then
            local wide = sheet.wide or 8
            local quad = view:quad(entry.gfx, index, wide, image)
            local _, sy = quad:getViewport()
            local _, ih = image:getDimensions()
            if sy < ih then
              local x = (obj.x - MOVE_ANIM_OAM_X_BIAS) + deltaX
              local y = (obj.y - MOVE_ANIM_OAM_Y_BIAS) + deltaY
              local sxScale = bit.band(obj.attr, MOVE_ANIM_OAM_XFLIP) ~= 0 and -1 or 1
              local syScale = bit.band(obj.attr, MOVE_ANIM_OAM_YFLIP) ~= 0 and -1 or 1
              local ox = sxScale < 0 and 8 or 0
              local oy = syScale < 0 and 8 or 0
              local colors = view:objPalette(obj.palette, battle)
              local function body()
                G.draw(image, quad, x + ox, y + oy, 0, sxScale, syScale)
              end
              if colors and GbcPalette.available() then
                GbcPalette.with(colors, body)
              else
                body()
              end
            end
          end
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- GEN 1'S OWN ANIMATION ARM -- src/battle/AnimPlayer.lua.
  --
  -- A stock Red/Blue/Yellow boot has no Gen 2 anim tables, so the
  -- AnimRunner/BattleAnimView arm above cannot run there.  But Gen 1 is
  -- NOT animationless: the cart's own BattleState drives
  -- src/battle/AnimPlayer.lua (src/battle/BattleState.lua:1399-1405),
  -- which compiles a move's `data.battle_anims` moveAnims rows into timed
  -- OAM steps and ticks them with :update()/:isDone().  This block drives
  -- that same native engine, with the same inputs the cart hands it:
  --   * :start(moveId, attackerIsPlayer, opts), opts { shakes, ball,
  --     ballFlicker } on the ball rows (DoBallShake / DoBallToss);
  --   * :pollEffects() routed into the same sound + enemy-pic-hide hooks
  --     BattleState:applyAnimEffect implements;
  --   * a move's own sound bytes through BattleState:playAnimSound's rule
  --     (N.playMoveAnimSound), and a ball toss's SFX_BALL_POOF/Tink.
  --
  -- POSITION.  AnimPlayer's OAM sprites are in vanilla 160x144 space, so
  -- they get the SAME kind of remap Screen:drawMoveAnimObjects gives the
  -- Gen 2 objects: the actor's real on-screen anchor and the real
  -- actor->target gap drive a per-axis scale, so the animation starts at
  -- the actor and actually reaches the target (a flat translate could
  -- never change how far the ball flies).  AnimPlayer's steps are flat
  -- sprite lists with no per-object identity, so sprites are grouped into
  -- connected components by OAM adjacency before remapping -- that keeps
  -- a multi-tile composite (a 16x16 ball is four tiles) rigid instead of
  -- prying its tiles apart under a non-unit scale, the same guarantee the
  -- Gen 2 arm gets from its own per-struct OAM tagging.
  --
  -- The ball chain is native's own (BattleState:ballChain, :5478-5496):
  -- toss -> POOF -> (HIDEPIC -> SHAKE) when it landed, and on a breakout
  -- POOF -> SHOWPIC puts the mon back; a capture ends with the closed ball
  -- held in OAM through the caught text (AnimPlayer:finalSprites, native's
  -- lockedBall).  Each row is a separate :start, walked as a FIFO queue.
  local function gen1AnimRemap(anchor, landAnchor, vanillaActor, vanillaLand)
    local scaleX, scaleY = 1, 1
    if anchor and landAnchor and vanillaActor and vanillaLand then
      local vdx = vanillaLand.x - vanillaActor.x
      local vdy = vanillaLand.y - vanillaActor.y
      if vdx ~= 0 then scaleX = (landAnchor.x - anchor.x) / vdx end
      if vdy ~= 0 then scaleY = (landAnchor.y - anchor.y) / vdy end
    end
    return scaleX, scaleY
  end

  -- Connected components of a step's on-screen sprites, joined when their
  -- OAM positions are 8px-grid adjacent.  Off-screen (hardware-clipped)
  -- sprites are dropped first, exactly as AnimPlayer:drawSprites hides them.
  local function gen1AnimGroups(sprites)
    local live = {}
    for i = 1, #sprites do
      local s = sprites[i]
      if s.x > 0 and s.x < 168 and s.y > 0 and s.y < 160 then
        live[#live + 1] = s
      end
    end
    local n = #live
    local parent = {}
    for i = 1, n do parent[i] = i end
    local function find(i)
      while parent[i] ~= i do
        parent[i] = parent[parent[i]]
        i = parent[i]
      end
      return i
    end
    for i = 1, n do
      for j = i + 1, n do
        local a, b = live[i], live[j]
        if math.abs(a.x - b.x) <= 8 and math.abs(a.y - b.y) <= 8 then
          parent[find(j)] = find(i)
        end
      end
    end
    local groups, byRoot = {}, {}
    for i = 1, n do
      local root = find(i)
      local group = byRoot[root]
      if not group then
        group = {}
        byRoot[root] = group
        groups[#groups + 1] = group
      end
      group[#group + 1] = live[i]
    end
    return groups
  end

  -- Start one queued native animation row.  Mirrors BattleState's own row
  -- handling (:1483-1512): POOF_ANIM plays SFX_BALL_POOF, HIDEPIC/SHOWPIC
  -- flip enemyHidden, and a toss row carries the ball item (which is what
  -- makes a Master/Ultra toss flicker).
  function Screen:startGen1AnimStep(anim, step)
    if not step then return end
    if step.name == "POOF_ANIM" then
      if N.playAnimSfx then N.playAnimSfx(self.data, "Ball_Poof") end
    elseif step.name == "HIDEPIC_ANIM" then
      anim.hiddenEnemy = true
    elseif step.name == "SHOWPIC_ANIM" then
      anim.hiddenEnemy = false
    end
    anim.animName = step.name
    anim.playing = true
    local opts
    if step.shakes or step.ball then
      opts = {
        shakes = step.shakes,
        ball = step.ball,
        ballFlicker = step.ball and N.ballFlicker(step.ball) or nil,
      }
    end
    -- pcall'd for the same reason every other art/data lookup here is: a
    -- missing or malformed animation is a battle that plays no animation,
    -- never a battle that crashes.
    local ok, err = pcall(anim.player.start, anim.player, step.name,
      step.isPlayer, opts)
    if not ok then
      anim.playing = false
      anim.queue = {}
      mod.log:warn("g9_Battle_Scene: gen1 animation %s failed: %s",
        tostring(step.name), tostring(err))
      return
    end
    -- Frame-0 rows (the first sound/effect) fire before the first tick,
    -- exactly as BattleState drains them right after :start.
    self:applyGen1AnimEvents(anim, anim.player:pollEffects())
  end

  function Screen:applyGen1AnimEvent(anim, ev)
    if ev.sound then
      if N.playMoveAnimSound then
        N.playMoveAnimSound(self.data, ev.sound,
          { animName = anim.animName, crySpecies = anim.crySpecies })
      end
      return
    end
    local e = ev.effect
    if e == "SFX_TINK" then
      -- each ball shake opens with a tink (DoBallShakeSpecialEffects)
      if N.playAnimSfx then N.playAnimSfx(self.data, "Tink") end
    elseif anim.isBall and e == "SE_HIDE_ENEMY_MON_PIC" then
      anim.hiddenEnemy = true
    elseif anim.isBall and e == "SE_SHOW_ENEMY_MON_PIC" then
      anim.hiddenEnemy = false
    end
  end

  function Screen:applyGen1AnimEvents(anim, events)
    for _, ev in ipairs(events or {}) do
      self:applyGen1AnimEvent(anim, ev)
    end
  end

  -- Advance the Gen 1 arm one frame; true once the WHOLE chain is spent.
  function Screen:stepGen1Anim(anim)
    local player = anim.player
    if not anim.playing then return true end
    player:update()
    self:applyGen1AnimEvents(anim, player:pollEffects())
    -- Consume finished rows eagerly: the chain is a FIFO, and a row that is
    -- already over (a missing or empty animation) must not stall it.
    while player:isDone() and #anim.queue > 0 do
      table.remove(anim.queue, 1)
      self:startGen1AnimStep(anim, anim.queue[1])
      if not anim.playing then break end
    end
    return #anim.queue == 0 and player:isDone()
  end

  function Screen:drawGen1AnimSprites(anim)
    local player = anim.player
    local sprites
    if anim.playing then
      local step = player.steps[player.stepIndex]
      sprites = step and step.sprites
    end
    -- A captured ball's chain keeps its closed-ball OAM through the caught
    -- text (native's lockedBall): once the chain is spent, that resting
    -- frame is what stays on screen.
    if not sprites and anim.keepSprites then
      sprites = player:finalSprites()
    end
    if not sprites then return end
    local G = love.graphics
    G.setColor(1, 1, 1, 1)
    for _, group in ipairs(gen1AnimGroups(sprites)) do
      local ref = group[1]
      local refX = ref.x - MOVE_ANIM_OAM_X_BIAS
      local refY = ref.y - MOVE_ANIM_OAM_Y_BIAS
      local deltaX = (anim.anchorX + anim.scaleX * (refX - anim.vanillaAnchorX)) - refX
      local deltaY = (anim.anchorY + anim.scaleY * (refY - anim.vanillaAnchorY)) - refY
      for _, s in ipairs(group) do
        local img = player:sheetImage(s.ts)
        local quad = img and player:tileQuad(s.ts, s.tile)
        if quad then
          local x = (s.x - MOVE_ANIM_OAM_X_BIAS) + deltaX
          local y = (s.y - MOVE_ANIM_OAM_Y_BIAS) + deltaY
          local sxScale = s.xf and -1 or 1
          local syScale = s.yf and -1 or 1
          G.draw(img, quad,
                 x + (sxScale < 0 and 8 or 0),
                 y + (syScale < 0 and 8 or 0),
                 0, sxScale, syScale)
        end
      end
    end
  end

  -- Screen:startMoveAnim's Gen 1 arm: play def's own native move animation
  -- from the actor's real on-screen position (spread moves still aim at the
  -- opposing side's centre, exactly as the Gen 2 arm does).
  function Screen:startMoveAnimGen1(def, actor, target)
    if not (AnimPlayer and def and def.id) then return end
    local animsData = N.gen1AnimData(self.data)
    if not (animsData and animsData.moveAnims) then return end
    local anchor = self.spriteAnchor[actor]
    if not anchor then return end
    local vanillaActor = (actor.side == "player") and VANILLA_PLAYER_ANCHOR or VANILLA_ENEMY_ANCHOR
    local vanillaTarget = (actor.side == "player") and VANILLA_ENEMY_ANCHOR or VANILLA_PLAYER_ANCHOR
    local targetAnchor
    if isSpreadMoveId(self, def.id) then
      targetAnchor = sideSpriteCentre(self, (actor.side == "player") and "enemy" or "player")
    end
    targetAnchor = targetAnchor or self.spriteAnchor[target]
    local scaleX, scaleY = gen1AnimRemap(anchor, targetAnchor, vanillaActor, vanillaTarget)
    local anim = {
      gen1 = true,
      player = AnimPlayer.new(animsData),
      queue = { { name = def.id, isPlayer = actor.side == "player" } },
      playing = false,
      hiddenEnemy = false,
      anchorX = anchor.x,
      anchorY = anchor.y,
      vanillaAnchorX = vanillaActor.x,
      vanillaAnchorY = vanillaActor.y,
      scaleX = scaleX,
      scaleY = scaleY,
      -- The running animation's id + its attacker's species, read by
      -- N.playMoveAnimSound for GROWL/ROAR (GetMoveSound's IsCryMove).
      animName = def.id,
      crySpecies = actor.mon and actor.mon.species,
    }
    self.moveAnim = anim
    self:startGen1AnimStep(anim, anim.queue[1])
  end

  -- Screen:startCatchAnim's Gen 1 arm: the native ball chain, remapped so
  -- the toss leaves the thrower's own sprite and lands on the target's.
  function Screen:startCatchAnimGen1(pending)
    if not (AnimPlayer and pending) then return false end
    local animsData = N.gen1AnimData(self.data)
    if not (animsData and animsData.moveAnims) then return false end
    local target = pending.target
    local targetAnchor = self.spriteAnchor[target]
    if not targetAnchor then return false end
    local thrower = self.playerBattlers[self.actingSlotIdx or 1]
      or self.playerBattlers[1]
    local throwerAnchor = thrower and self.spriteAnchor[thrower]
    local actorAnchor = throwerAnchor or VANILLA_PLAYER_ANCHOR
    local scaleX, scaleY = gen1AnimRemap(actorAnchor, targetAnchor,
      VANILLA_PLAYER_ANCHOR, VANILLA_ENEMY_ANCHOR)
    local ball = pending.ballId or "POKE_BALL"
    -- The modern formula's own wobble count (its four shake checks), which
    -- the native SHAKE_ANIM plays once per wobble.
    local shakes = pending.shakes or 0
    -- BattleState:ballChain's own decision tree (:5478-5496): a clean miss
    -- (not caught, zero shakes) stops after the poof with the mon never
    -- hiding; anything else hides the mon and shakes it; a breakout then
    -- poofs and shows the mon again; a capture just leaves the ball resting.
    local landed = pending.caught or shakes ~= 0
    local queue = {
      { name = N.ballTossAnim(ball), isPlayer = true, ball = ball },
      { name = "POOF_ANIM", isPlayer = true },
    }
    if landed then
      queue[#queue + 1] = { name = "HIDEPIC_ANIM", isPlayer = true }
      queue[#queue + 1] = { name = "SHAKE_ANIM", isPlayer = true, shakes = shakes }
    end
    if landed and not pending.caught then
      queue[#queue + 1] = { name = "POOF_ANIM", isPlayer = true }
      queue[#queue + 1] = { name = "SHOWPIC_ANIM", isPlayer = true }
    end
    self.moveAnim = {
      gen1 = true,
      isBall = true,
      player = AnimPlayer.new(animsData),
      queue = queue,
      playing = false,
      hiddenEnemy = false,
      anchorX = actorAnchor.x,
      anchorY = actorAnchor.y,
      vanillaAnchorX = VANILLA_PLAYER_ANCHOR.x,
      vanillaAnchorY = VANILLA_PLAYER_ANCHOR.y,
      scaleX = scaleX,
      scaleY = scaleY,
      animName = queue[1].name,
      crySpecies = nil,
      -- Native keeps the closed ball in OAM through the caught text.
      keepSprites = pending.caught and true or false,
      onFinish = function() self:resolveCatchAnim() end,
    }
    self:startGen1AnimStep(self.moveAnim, queue[1])
    return true
  end

  function Screen:beginResolving()
    -- Switches always resolve before any move (real Gen 2 rule -- not a
    -- speed/priority comparison at all), so they're pulled out of the
    -- queue and applied first, one at a time, in Screen:advanceResolving
    -- below -- not part of g9-battle-engine's resolveTurnActions
    -- contract, which is moves only.
    local moveActions, switchActions, swapActions = {}, {}, {}
    for _, a in ipairs(self.queuedActions) do
      if a.kind == "switch" then switchActions[#switchActions + 1] = a
      elseif a.kind == "swap" then swapActions[#swapActions + 1] = a
      else moveActions[#moveActions + 1] = a end
    end
    for _, enemy in ipairs(self.enemyBattlers) do
      if self.combat.isAlive(enemy) then
        local ai = self.combat.chooseAiAction(enemy, self.playerBattlers, self.data)
        if ai then moveActions[#moveActions + 1] = ai end
      end
    end
    self.switchQueue = switchActions
    self.swapQueue = swapActions
    self.moveQueue = moveActions
    self.movesResolved = false
    self.currentMessage = nil
    self.pendingEvents = {}
    self.phase = "resolving"
    -- Seeded BEFORE anything resolves, so the bars start this pass
    -- showing what the player was looking at when they picked their
    -- moves -- the whole point of the chase. Must come after
    -- phase = "resolving": Screen:shownHpOf only lags in that phase.
    self:syncShownHp()
    self:advanceResolving()
  end

  -- Consumes the turn one VISIBLE step at a time. A step ends when
  -- something changed on screen that the player is owed a look at:
  -- either a new line of text, or a bar that has started moving.
  --
  -- Before this, the whole turn's events were flattened to their .text
  -- and everything else on them thrown away, which is what left the
  -- HUD showing the turn's final numbers from the very first frame.
  -- Events are queued whole now and dequeued here in emit order, so a
  -- textless damage/heal event -- of which there are many; the engine
  -- emits the number separately from the line that explains it
  -- (Battle.lua:1267-1292) -- becomes its own beat: it arms the drain
  -- and leaves the line that CAUSED it standing while the bar moves.
  -- That is the ordering the cart has ("X used TACKLE!" stays up while
  -- the bar empties underneath it), and it falls out of emit order for
  -- free rather than needing the events reordered or looked ahead at.
  function Screen:advanceResolving()
    self.hpAnimHolds = false
    while #self.pendingEvents > 0 do
      local event = table.remove(self.pendingEvents, 1)
      self:armHpAnim(event.g9SceneHp)
      if event.kind == "move" then self:startMoveAnimFor(event) end
      if event.text then
        self.currentMessage = event.text
        return
      end
      -- No text: whatever is already on screen stays there. Hold only
      -- if this event actually moved a bar -- an event that is neither
      -- seen nor heard is not a step, and making the player press A for
      -- each one would turn a turn into a dozen empty presses.
      if self.hpAnim then
        self.hpAnimHolds = true
        return
      end
    end
    if #self.swapQueue > 0 then
      -- Positional ally swaps resolve FIRST, ahead of both the PKMN
      -- recall queue and any move: the field has to be in its new shape
      -- before anything that might read positions (a spread move's
      -- centre, move-animation anchors) or the PKMN switch queue (which
      -- places an incoming mon at its slot index) runs.
      local action = table.remove(self.swapQueue, 1)
      local a, b = action.actorSlot, action.targetSlot
      local list = self.playerBattlers
      local owner, target = list[a], list[b]
      if owner and target
          and self.combat.isAlive(owner) and self.combat.isAlive(target) then
        list[a], list[b] = target, owner
        self.currentMessage = displayName(owner.mon) .. " switched places with "
          .. displayName(target.mon) .. "!"
      end
      -- Resolved either way -- this owner's cue is done.
      self:clearSwapOwnerMark(action.actor)
      return
    end
    if #self.switchQueue > 0 then
      -- The newly-sent-out mon simply has no action queued of its own
      -- this turn, so it never gets to act again until next turn.
      local action = table.remove(self.switchQueue, 1)
      local outgoing = self.playerBattlers[action.actorSlot]
      self.playerBattlers[action.actorSlot] = self.combat.newBattler(action.mon, "player")
      -- The real, shared engine event bus: announce the switch so
      -- engine-side per-battler bookkeeping keyed to a switch-in runs for
      -- a scene-driven battle exactly as it does for a native one. Without
      -- this the engine never learns the switch happened at all -- the
      -- scene owns the switch and `battle.started` is not re-raised
      -- mid-battle -- so combat/move_usability.lua kept the outgoing mon's
      -- Choice lock and combat/modern_action_order.lua kept counting its
      -- past actions. In-game that showed up as a Choice-locked mon staying
      -- locked after switching out (the user's own "switch in re-enables
      -- swapping moves") and a freshly switched-in mon still being refused
      -- Fake Out/First Impression. previous = the mon leaving (its lock and
      -- action counter are cleared), battler = the mon arriving (its action
      -- counter resets to 0). Runtime is the same shared bus this screen
      -- already raises battle.turn_started on.
      if Runtime and Runtime.emit then
        Runtime.emit("battle.battler_switched", {
          battle = self.battle,
          previous = outgoing and outgoing.mon or nil,
          battler = action.mon,
        })
      end
      -- The incoming mon has never been on this screen, so the chase has
      -- no entry for it -- seed it at its real hp so its bar is right
      -- from the "Go, X!" line onward. Without this it would fall
      -- through to the live value anyway (Screen:shownHpOf's own
      -- fallback), but only until the first snapshot that mentions it,
      -- which would then slide the bar from wherever the fallback left
      -- it rather than from where it was actually drawn.
      self.shownHp[action.mon] = action.mon.hp or 0
      self.currentMessage = "Go, " .. displayName(action.mon) .. "!"
      return
    end
    if not self.movesResolved then
      self.movesResolved = true
      -- Real "battle.turn_started" -- matches native's own turn-loop
      -- timing, right before this turn's actions actually run. This is
      -- what lets battle_forms's own real battle.turn_started listener
      -- (src/resolve.lua's M.onTurnStarted) perform whatever's armed
      -- (Screen:updateGimmickSelect) and mark it spent, respecting the
      -- once-per-battle limit exactly as it would for a battle native's
      -- own runTurn drove. Nothing here assumes battle_forms specifically
      -- -- any mod keying real per-turn work off this real, standard
      -- event benefits the same way.
      --
      -- Focused on the FORM's owner for the activation itself (see the
      -- GIMMICK SELECT section's FORMS OWNER block): battle_forms' entry
      -- activate() reads battle.player, so without this a FORM armed from
      -- any slot but the first would transform slot 1 instead. Restored the
      -- moment the listener returns.
      local formsMon = self.gimmickOwnerMon
      local armedBefore = battleFormsArmedId()
      focusBattlePlayer(self, formsMon, function()
        Runtime.emit("battle.turn_started", { battle = self.battle })
      end)
      if formsMon and armedBefore ~= nil then
        -- Consuming clears the armed id; battle_forms only consumes when the
        -- entry actually activated, so a still-armed id is a refusal.
        if battleFormsArmedId() == nil then
          emitFormsEvent(self, "used", { mon = formsMon,
            slot = self.gimmickOwnerSlot, id = self.gimmickOwnerId,
            label = self.gimmickOwnerLabel })
        else
          emitFormsEvent(self, "cancelled", { mon = formsMon,
            slot = self.gimmickOwnerSlot, id = self.gimmickOwnerId,
            label = self.gimmickOwnerLabel, reason = "activation-refused" })
        end
      end
      clearGimmickOwner(self)
      -- The WHOLE remaining turn's moves resolve in ONE call now --
      -- g9-battle-engine's own resolveTurnActions derives priority/
      -- Speed/order/RNG itself and drives battle:useMove per battler
      -- (STAB/Tera/Protect/damage/accuracy/every sub-effect -- all its
      -- pipeline, not this mod's). This only translates its drained
      -- events into the existing message-pacing queue.
      --
      -- The move animation trigger this comment used to record as
      -- deferred ("gated on resolveAction's own per-action success/
      -- failure signal, which collapsing to one per-turn call no longer
      -- exposes per-action") is back, from a different seam: the
      -- per-action signal was in the drained events all along, on the
      -- `move` event the engine emits once per action that actually got
      -- to run. Screen:startMoveAnimFor fires off it as the event is
      -- dequeued, so the animation plays under its own announcement
      -- rather than after the whole turn.
      local events = self.combat.resolveTurn(self.g9dex, self.battle, self.moveQueue)
      -- EXP: real native Battle:awardExperience, fired for each enemy
      -- newly fainted by the moves just resolved -- `.fainted` doubles
      -- as an "already awarded" guard here (Combat.isAlive checks
      -- mon.hp directly too, so this repurposing doesn't affect
      -- aliveness checks elsewhere).
      --
      -- awardExperience splits across battle.participants, rebuilt from the
      -- real roster every time, right before awarding, so EXP splits across
      -- whichever of OUR playerBattlers fought this battle.  The KEY SHAPE is
      -- generation-specific (Gen 2 indexes the roster by party slot, Gen 1 by
      -- the mon table itself), so the backend builds it -- see native.lua.
      if next(self.enemyBattlers) then
        N.setParticipants(self.battle, self.playerBattlers, self.game.save,
          self.combat)
      end
      for _, enemy in ipairs(self.enemyBattlers) do
        if enemy.mon and (enemy.mon.hp or 0) <= 0 and not enemy.fainted then
          enemy.fainted = true
          N.awardExperience(self.battle, enemy.mon)
        end
      end
      for _, e in ipairs(N.takeEvents(self.battle)) do events[#events + 1] = e end
      -- Queued WHOLE, in emit order -- not flattened to .text any more.
      -- Screen:installEventProbe has already stamped each one with the
      -- HP vector as of its own emit, which is the entire reason the
      -- bars can now lag the math they were spoiling.
      for _, event in ipairs(events) do
        self.pendingEvents[#self.pendingEvents + 1] = event
      end
      -- Straight back to the top: movesResolved is already true, so this
      -- cannot loop, and a proper tail call costs no stack.
      return self:advanceResolving()
    end
    -- A trainer's active wave can be down while its bench still holds a
    -- healthy mon -- send the next one out and hold on that beat rather
    -- than falling into finishTurn, which would declare the trainer
    -- beaten with a full reserve team unused. Returns false (and lets
    -- finishTurn run) when there is nothing left to send.
    -- A player battler can faint with a healthy party reserve still in hand.
    -- Native answers that by opening the party list and refusing to let the
    -- player back out before the turn is allowed to be declared over -- see
    -- Screen:advancePlayerReplacement. Sits ahead of the enemy replacement so
    -- the player is back in the fight before the trainer answers.
    if self:advancePlayerReplacement() then return end
    if self:advanceEnemyReplacement() then return end
    self:finishTurn()
  end

  -- True only when NO enemy is left anywhere -- neither an active battler
  -- nor a still-healthy mon waiting on the bench. Screen:finishTurn reads
  -- this instead of a bare sideDefeated(self.enemyBattlers), so a trainer
  -- with a reserve team is not declared beaten the instant its FIRST wave
  -- faints -- the battle is over only when the last bench mon is down too.
  -- A wild fight (empty bench) is unchanged: this reduces to exactly the
  -- old sideDefeated check.
  function Screen:enemySideDefeated()
    if not self.combat.sideDefeated(self.enemyBattlers) then return false end
    for _, mon in ipairs(self.enemyBench) do
      if (mon.hp or 0) > 0 then return false end
    end
    return true
  end

  -- Pops the next still-healthy benched enemy, or nil when the bench is
  -- empty or exhausted. Removed from the bench as it is taken, so the
  -- same mon is never sent out twice.
  function Screen:takeNextEnemyBenchMon()
    for i, mon in ipairs(self.enemyBench) do
      if (mon.hp or 0) > 0 then
        table.remove(self.enemyBench, i)
        return mon
      end
    end
    return nil
  end

  -- Sends ONE benched enemy into the first fainted active enemy slot -- the
  -- trainer-battle counterpart of an active enemy fainting (native does the
  -- same in Battle:offerEnemySwitch, Battle.lua:3560-3578: clear the
  -- outgoing mon's volatile state, repoint enemyIndex/enemy at the mon
  -- coming IN, reset the enemy side's stat stages, then narrate the send).
  -- Returns true if a mon was sent out -- the caller then holds on the
  -- send-out beat instead of ending the battle -- and false otherwise.
  --
  -- At most ONE send per call, deliberately: a multi-slot layout (doubles,
  -- triples) can lose two active enemies on the SAME turn, and narrating
  -- both at once would clobber the single ballThrow/currentMessage state
  -- and leave the second replacement permanently hidden (only one slot can
  -- own a throw). Returning after the first send makes the next call --
  -- the player's next press, once that send's own beat is done -- fill the
  -- next empty slot, each with its own ball and its own "{TRAINER} sent out
  -- X!" line, exactly as native walks its own send queue.
  --
  -- The player side already being down means no replacement: the battle
  -- is over (draw/loss), and sending a fresh boss out against an already-
  -- defeated party would be wrong. finishTurn's own enemySideDefeated
  -- check is only reached once this returns false.
  --
  -- The real Battle model is repointed at the mon actually out because
  -- more than narration reads it: modern_held_items_phase2's Black Sludge
  -- tick iterates {battle.player, battle.enemy}, and battle.stages.enemy
  -- is what the engine's stat-stage math reads -- a stale model would
  -- tick the wrong mon and fight with the previous boss's stat drops.
  function Screen:advanceEnemyReplacement()
    if self.combat.sideDefeated(self.playerBattlers) then return false end
    for slot, battler in ipairs(self.enemyBattlers) do
      if not self.combat.isAlive(battler) then
        local mon = self:takeNextEnemyBenchMon()
        if not mon then return false end
        self.enemyBattlers[slot] = self.combat.newBattler(mon, "enemy")
        self.shownHp[mon] = mon.hp or 0
        -- Hidden until the ball lands (Screen:update's own throw stepper
        -- reveals it at t >= BALL_FLIGHT), exactly like the intro send.
        self.enemyRevealed[slot] = false
        if self.battle then
          for index, partyMon in ipairs(self.battle.enemyParty or {}) do
            if partyMon == mon then self.battle.enemyIndex = index break end
          end
          -- pcall'd for the same reason every other engine call on this
          -- screen is: a model without one of these helpers costs the
          -- battle an edge case, never the whole fight.
          pcall(function()
            if self.battle.clearVolatile then self.battle:clearVolatile(mon) end
            if self.battle.stages then self.battle.stages.enemy = N.newStages() end
          end)
          self.battle.enemy = mon
        end
        -- Same switch-in announcement the player's own PKMN switch raises
        -- (see advanceResolving): the engine's per-mon switch-in bookkeeping
        -- (the arriving mon's Fake Out/First Impression counter, and the
        -- departing mon's Choice lock) has to run for an enemy replacement
        -- too, or an enemy boss that fainted a Choice holder would leave the
        -- lock on a mon that is no longer on the field.
        if Runtime and Runtime.emit then
          Runtime.emit("battle.battler_switched", {
            battle = self.battle,
            previous = battler and battler.mon or nil,
            battler = mon,
          })
        end
        self.currentMessage = (self:trainerDisplayName() or "TRAINER")
          .. " sent out " .. displayName(mon) .. "!"
        self.ballThrow = { side = "enemy", slot = slot, t = 0 }
        return true
      end
    end
    return false
  end

  ------------------------------------------------------------------
  -- FORCED PLAYER REPLACEMENT -- a fielded battler faints while the party
  -- still holds a healthy mon. What native does about it: the party list
  -- opens and the player is NOT allowed to back out (Gen 2's own
  -- "forced-switch" phase, src/ui/gen2/BattleState.lua:2906-2926 and
  -- :3048-3117). This screen drives its own turn loop, so it has to raise
  -- that prompt itself -- the tail of Screen:advanceResolving calls
  -- Screen:advancePlayerReplacement before the turn can be declared over.
  --
  -- A pick fills the FAINTED SLOT (self.playerBattlers[slot]) rather than
  -- appending: the field keeps its shape and the incoming mon stands exactly
  -- where the one it replaced stood. One slot at a time -- two battlers can
  -- faint on the same turn, and each gets its own prompt and its own "Go, X!"
  -- beat rather than both being clobbered together.
  ------------------------------------------------------------------
  local FORCED_SWITCH_TEXT = "choose your next pokemon"

  -- The player's still-usable reserve: every party mon that is neither on the
  -- field nor already down. Identity against the battler wrappers, because the
  -- active mons ARE save.party entries (they share the table) -- a fainted
  -- active mon must never count as its own replacement.
  function Screen:playerBench()
    local bench = {}
    local party = (self.game.save and self.game.save.party) or {}
    for _, mon in ipairs(party) do
      if (mon.hp or 0) > 0 then
        local active = false
        for _, b in ipairs(self.playerBattlers) do
          if b.mon == mon then active = true break end
        end
        if not active then bench[#bench + 1] = mon end
      end
    end
    return bench
  end

  -- The player is beaten only when the field AND the reserve are both down --
  -- the whole party fainted, not just the mons that happened to be out.
  -- Screen:finishTurn reads this instead of a bare sideDefeated, so a battle is
  -- not lost while a healthy mon is still sitting in the party.
  function Screen:playerSideDefeated()
    if not self.combat.sideDefeated(self.playerBattlers) then return false end
    return #self:playerBench() == 0
  end

  -- Fills the first fainted active slot with a forced pick. Returns true while
  -- a pick is pending (the caller holds the turn) and false when there is
  -- nothing to do, so the tail can fall through to the enemy replacement and
  -- finishTurn. A no-op when the enemy side is already finished: winning ends
  -- the battle, and forcing a replacement into a won fight would be wrong.
  function Screen:advancePlayerReplacement()
    if self:enemySideDefeated() then return false end
    if #self:playerBench() == 0 then return false end
    for slot, battler in ipairs(self.playerBattlers) do
      if not self.combat.isAlive(battler) then
        self:openForcedSwitch(slot)
        return true
      end
    end
    return false
  end

  -- Opens the native party list in its forced dress -- no cancel: a cancel
  -- attempt prints FORCED_SWITCH_TEXT and the player is put back on the list.
  -- `open` is kept on the screen so a Gen 1 cancel (which closes the native
  -- list before telling us) can reopen it.
  function Screen:openForcedSwitch(slot)
    local save = self.game.save
    local open
    open = function()
      local list
      if N.isGen2 then
        -- No BattleMonMenu, so A answers straight away, and the list owns its
        -- own update -- B / the CANCEL row calls onCancel and leaves the list
        -- standing, which is the "stay put" the refusal wants.
        list = Screens.push(self.game, N.partyMenuId(), {
          save = save,
          party = save.party,
          prompt = "which",
          onCancel = function() self:refuseForcedCancel(slot, list) end,
          onChoose = function(index, mon) self:chooseForcedMon(slot, mon, list) end,
        })
      else
        -- forceSwitch + pickOnly makes A call onSwitch immediately; keepOpen
        -- stops the picker closing itself so a refused pick stays on screen
        -- (the same shape the medicine flow uses). B still pops the list
        -- before onCancel -- refuseForcedCancel puts the player back.
        list = Screens.push(self.game, N.partyMenuId(), {
          save = save,
          party = save.party,
          forceSwitch = true,
          pickOnly = true,
          keepOpen = true,
          onSwitch = function(mon, menu) self:chooseForcedMon(slot, mon, list) end,
          onCancel = function() self:refuseForcedCancel(slot, list) end,
        })
      end
    end
    self.forcedSwitchOpen = open
    self.phase = "submenu"
    if not (self.game and self.game.stack) then
      -- No state stack to open a list on (headless): take the first healthy
      -- reserve mon so the turn can never deadlock on an unseen prompt.
      local bench = self:playerBench()
      if bench[1] then self:applyForcedSwitch(slot, bench[1]) end
      return
    end
    open()
  end

  -- A pick from the forced list. The two refusals mirror Screen:trySwitchIn's
  -- own -- a fainted mon, or one already standing on the field -- and leave the
  -- list up so the player keeps choosing.
  function Screen:chooseForcedMon(slot, mon, list)
    local reason
    if (mon.hp or 0) <= 0 then
      reason = displayName(mon) .. " has no energy left to battle!"
    else
      for _, b in ipairs(self.playerBattlers) do
        if b.mon == mon and self.combat.isAlive(b) then
          reason = displayName(mon) .. " is already in battle!"
          break
        end
      end
    end
    if reason then
      if list then list:refuse(reason) end
      return
    end
    if list then
      if N.isGen2 then self.game.stack:pop()
      elseif list.close then list:close()
      else self.game.stack:pop() end
    end
    self:applyForcedSwitch(slot, mon)
  end

  -- "We return player to party screen." Gen 2's list is still standing under
  -- its own refusal, so the line prints in place; Gen 1 already closed itself,
  -- so the line gets its own box and the list is reopened behind it.
  function Screen:refuseForcedCancel(slot, list)
    if N.isGen2 then
      if list then list:refuse(FORCED_SWITCH_TEXT) end
      return
    end
    local TextBox = require("src.render.TextBox")
    self.game.stack:push(TextBox.new(self.game, FORCED_SWITCH_TEXT, function()
      self.suppressInputFrame = true
      if self.forcedSwitchOpen then self.forcedSwitchOpen() end
    end))
  end

  -- Puts `mon` into the fainted slot and hands control back to the turn chaser.
  -- The "Go, X!" line is a normal resolving beat: the NEXT press runs
  -- Screen:advanceResolving again, which fills any further empty slot before
  -- the enemy replacement and finishTurn get their turn.
  function Screen:applyForcedSwitch(slot, mon)
    local outgoing = self.playerBattlers[slot]
    self.playerBattlers[slot] = self.combat.newBattler(mon, "player")
    -- Same switch-in announcement the voluntary switch and the enemy
    -- replacement raise (see Screen:advanceResolving): the engine's per-mon
    -- switch-in bookkeeping (the arriving mon's Fake Out/First Impression
    -- counter, the departing mon's Choice lock) has to run here too.
    if Runtime and Runtime.emit then
      Runtime.emit("battle.battler_switched", {
        battle = self.battle,
        previous = outgoing and outgoing.mon or nil,
        battler = mon,
      })
    end
    self.shownHp[mon] = mon.hp or 0
    self.currentMessage = "Go, " .. displayName(mon) .. "!"
    self.forcedSwitchOpen = nil
    -- The press that confirmed the pick must not also be read as the press
    -- that acknowledges the "Go, X!" line -- the same one-frame guard every
    -- other native-menu callback in this file sets.
    self.suppressInputFrame = true
    self.phase = "resolving"
  end

  -- A beaten trainer pays up -- the one thing native's win sequence does that
  -- a scene battle otherwise never did.  A battle drawn through this screen
  -- replaces native's own, so nothing else pays: native Gen 2 hands it out in
  -- WinTrainerBattle (Battle:awardPrizeMoney) and native Gen 1 in
  -- BattleState:enemyMonFainted, and both run on the battle screen this scene
  -- stands in for.  The routine is the generation's own, reached through the
  -- backend (N.awardTrainerPrize -- the engine's Prize module on Gen 2, Gen 1's
  -- baseMoney x level on Gen 1), so the amount is vanilla rather than an
  -- approximation.  Wild fights, a run and a loss pay nothing; a legacy
  -- nameless trainer (self.trainerData == true) has no baseMoney and so no
  -- payout either.  Idempotent against self.prize so a second call -- the
  -- screen can only reach this once, but the guard costs nothing -- cannot pay
  -- twice.  The line native prints is folded into the over screen's own
  -- message, since this screen's over screen is a single field the player
  -- reads before pressing A out of the battle.
  function Screen:awardTrainerPrize()
    if self.prize ~= nil then return self.prize end
    self.prize = false
    if not (self.outcome == "win" and self.isTrainerBattle) then return false end
    local award = N.awardTrainerPrize(self.battle, self.game.save,
      self.trainerData)
    if not award then return false end
    self.prize = award
    if award.text and award.text ~= "" then
      self.overMessage = (self.overMessage or "")
        .. (self.overMessage and self.overMessage ~= "" and " " or "")
        .. award.text
    end
    return award
  end

  function Screen:finishTurn()
    local enemiesDown = self:enemySideDefeated()
    local playersDown = self:playerSideDefeated()
    if enemiesDown or playersDown then
      self.phase = "over"
      -- Starred here, not in updateOver: the blackout clock runs for the
      -- whole over phase (update steps it independently of input), so it
      -- reads as a continuous slow fade even while the player is mashing.
      self.outroT = 0
      if enemiesDown and playersDown then
        self.overMessage = "Both sides down -- draw!"
        self.outcome = "draw"
      elseif enemiesDown then
        -- Vanilla: "You won the battle!" for a wild fight, "You defeated
        -- {TRAINER}!" for a trainer's team.
        local tn = self:trainerDisplayName()
        if tn then
          self.overMessage = "You defeated " .. tn .. "!"
        else
          self.overMessage = "You won the battle!"
        end
        self.outcome = "win"
        -- A beaten trainer pays up (see Screen:awardTrainerPrize): the money
        -- lands before the screen exits -- "at the end of the fight, after
        -- defeating the enemy", native's own beat -- and its line joins the
        -- over screen's message.
        self:awardTrainerPrize()
      else
        self.overMessage = "Your team was defeated..."
        self.outcome = "lose"
      end
      return
    end
    self:beginTurn()
  end

  -- Three things can be holding a narrated turn, in the same priority
  -- order native's own battle loop holds it in (src/ui/gen2/BattleState
  -- .lua:2176-2185): a move animation owns the screen while it runs,
  -- then the bar drain owns it, and only then does the line wait for a
  -- button.
  --
  -- Every one of those holds is skippable with the SAME A/B the player
  -- is already pressing, and none of them can outlast a press --
  -- deliberately, because a hold that only ends on its own terms is a
  -- hung battle with no way out the moment anything upstream misbehaves.
  -- A press during a hold ends that hold and nothing else; it never also
  -- eats the line underneath, so no message can be skipped unread.
  function Screen:updateResolving(input)
    local pressed = input:wasPressed("a") or input:wasPressed("b")
    -- Screen:update already stepped self.moveAnim this frame and cleared
    -- it if the runner reported itself finished.
    if self.moveAnim then
      if pressed then self.moveAnim = nil end
      return
    end
    if self.hpAnim then
      if pressed then
        self:snapHpAnim()
      else
        self:stepHpAnim()
      end
      if self.hpAnim then return end
      -- The drain has landed. If it was the thing holding the queue --
      -- a textless damage/heal beat, with the line that caused it still
      -- on screen -- carry on to the next step by itself rather than
      -- charging the player a press for a beat that had no line of its
      -- own to read.
      if self.hpAnimHolds then
        self.hpAnimHolds = false
        self:advanceResolving()
      end
      return
    end
    if pressed then
      -- A trainer's replacement send is a hold like the intro's own
      -- throw: mid-flight, a press snaps the ball to landed (which the
      -- phase-independent stepper in Screen:update then turns into the
      -- reveal and clears) rather than eating the "sent out X!" line
      -- underneath it. Reached only after any hpAnim/moveAnim above.
      if self.ballThrow and self.ballThrow.t < BALL_THROW_TOTAL then
        self.ballThrow.t = BALL_THROW_TOTAL
        return
      end
      self:advanceResolving()
    end
  end

  -- Plays the real Gen 2 move animation for a dequeued `move` event.
  --
  -- This is the trigger Screen:advanceResolving's own header used to say
  -- was "deferred, not carried over from g2-Battle-Scene ... real future
  -- work, not silently dropped": startMoveAnim itself was already
  -- written and already wired into Screen:update/Screen:drawContent, and
  -- only the call was missing, because collapsing to one whole-turn
  -- resolveTurnActions call left nothing per-action to hang it off. The
  -- events were always that per-action signal; nothing was reading them.
  --
  -- Fires on the `move` event, which IS the "X used Y!" line, so the
  -- animation plays under its own announcement the way the cart's does.
  -- A move that missed or failed plays nothing: the engine keeps that
  -- event around specifically so the miss paths can mark it
  -- (Battle.lua:1370, :1470-1478), because
  -- BattleCommand_MoveAnimNoSub opens on `ld a, [wAttackMissed] / and a
  -- / jp nz, BattleCommand_MoveDelay` (engine/battle/effect_commands
  -- .asm:1958) and burns the delay instead. Same gate the native screen
  -- uses (src/ui/gen2/BattleState.lua:1753). The whole turn has already
  -- resolved by the time this event is dequeued, so `.missed` is final.
  --
  -- Not carried through, and not pretended otherwise: event.animParam
  -- (Battle.lua:1591, FLY/DIG's charge frame) and event.effectiveness,
  -- both of which the native screen feeds its own animForMove.
  -- Screen:startMoveAnim hardcodes param = 0 and has no hit-sound path
  -- at all, so there is nothing here to hand them to yet.
  --
  -- Both battlers come from the probe, not from event.side: side is the
  -- hard player/enemy binary that cannot name one of four allies (see
  -- the TURN PACING header). Screen:startMoveAnim needs real battler
  -- WRAPPERS -- it reads .side for the animation's own turn flag and
  -- indexes self.spriteAnchor by wrapper -- so both are mapped back
  -- through Screen:battlerFor. No attacker, no animation: guessing which
  -- sprite to throw a Water Gun from is worse than throwing none.
  function Screen:startMoveAnimFor(event)
    if not (event and event.move) or event.missed then return end
    local actor = self:battlerFor(event.g9SceneActor)
    if not actor then return end
    local target = self:battlerFor(event.g9SceneTarget)
    -- pcall'd for the same reason every other art/data lookup on this
    -- screen is: a missing or malformed animation script is a battle
    -- that plays no animation, never a battle that crashes.
    local ok, err = pcall(function()
      self:startMoveAnim({ id = event.move }, actor, target)
    end)
    if not ok then
      self.moveAnim = nil
      mod.log:warn("g9_Battle_Scene: move animation for %s failed: %s",
        tostring(event.move), tostring(err))
    end
  end

  ------------------------------------------------------------------
  -- OVER
  ------------------------------------------------------------------
  function Screen:updateOver(input)
    if input:wasPressed("a") or input:wasPressed("b") then
      -- Called explicitly, right here, before the pop -- the same place
      -- native's own onDone closure does its cleanup (World.lua:5865:
      -- the callback pops the screen AND restores the map music itself,
      -- not a generic post-pop hook).
      self:finishBattleExit()
      self.game.stack:pop()
    end
  end

  ------------------------------------------------------------------
  -- TWO-CHOICE PROMPT -- a PRIMITIVE any mod can raise on this screen,
  -- deliberately not a policy. The caller supplies the question, the two
  -- labels and a callback; nothing below knows or cares which species,
  -- HP threshold, trainer class or story flag made the question worth
  -- asking. Baking one consumer's trigger rule in here would impose that
  -- rule on every other consumer, which is exactly the mistake this mod
  -- already refuses to make everywhere else (layouts.lua's own header:
  -- "this mod never builds the roster itself"; this file's own: it owns
  -- no encounter-trigger logic at all).
  --
  -- The motivating case -- a boss at its 1 HP last stand offering
  -- "CATCH it" / "LEAVE it", with BOTH answers ending the battle -- is
  -- implementable entirely as a CALLER, and is deliberately not in this
  -- file. Its two answers reach for two methods this screen already had
  -- before this feature existed, both public on the instance handed to
  -- the callback:
  --   * catch  -> screen:throwBall(ballId), which runs the modern
  --     (Scarlet/Violet) formula and, on Gen 2, the native captured tail
  --     (Battle:caught) on success -- and spends one ball from the bag -- and
  --     sets self.outcome="caught" / self.phase="over" on success.
  --   * leave  -> screen:chooseMenuItem("RUN"), which sets
  --     self.outcome="run", calls self:finishBattleExit() and pops.
  --
  -- REJECTED: adding answerWithCatch/answerWithRun helpers to this API.
  -- They would be exactly one line each, and each one is a POLICY
  -- decision (which ball? which enemy? is running even allowed here?)
  -- dressed up as a primitive -- the first consumer that wants an ULTRA
  -- BALL, or a third answer, or a catch that does not end the battle,
  -- would need the helper widened or bypassed. The two methods are
  -- already public and already documented above; a helper would add
  -- surface without adding capability. The API reports the answer and
  -- gets out of the way.
  --
  -- REJECTED: a separate battle_prompt.lua sibling file (the shape the
  -- sibling mod's own native-screen version of this feature takes, see
  -- Gen9Dex combat/battle_prompt.lua). That one had to be a separate
  -- file because it works by WRAPPING a class it does not own. This
  -- screen is ours: the prompt is a phase, and a phase here means a
  -- branch in Screen:update's own dispatch chain and two branches in
  -- Screen:drawContent's own F/E chains, plus reads of self.fTextX/
  -- fChars/eTextX. Splitting it out would mean publishing the Screen
  -- class table purely so another file could reach back into it -- a
  -- bigger structural change than the feature, for no isolation gain.
  -- It lives beside gimmickSelect, the phase it is most like.
  --
  -- Built in this screen's ONE input idiom, the one Screen:
  -- chooseMenuItem's own header already names -- "a cursor over a list,
  -- A confirms, B cancels" -- and drawn in this screen's own vanilla
  -- text-box-plus-menu split: the question wraps into F exactly the way
  -- a resolving message does, the two labels sit in E exactly the way
  -- FIGHT/BAG/PKMN/RUN do, same 11px rows and same cursor column
  -- (Screen:drawActionMenuEList). No second input style, no second
  -- chrome.
  --
  -- REJECTED: the sibling mod's "hold the question for one A/B press
  -- before the box opens" step. That mirrors native BattleState's own
  -- messageTimer, which five engine ask-* prompts key off and which this
  -- screen has no equivalent of at all -- every one of this screen's own
  -- list phases (moveSelect, targetSelect, gimmickSelect) is live on the
  -- frame it opens, and a prompt that needed an extra press first would
  -- be the odd one out here rather than the familiar one.
  ------------------------------------------------------------------

  -- The only two phases a prompt may interrupt, both quiescent by
  -- definition: "actionMenu" is this screen parked on FIGHT/BAG/PKMN/RUN
  -- waiting for the player, "resolving" is the message pump waiting for
  -- an A/B between lines. Everything else is excluded for a real reason,
  -- not by omission:
  --   * moveSelect/targetSelect/gimmickSelect -- the player is already
  --     mid-question with their own cursor state; interrupting one with
  --     a second question is the rudeness this file would be adding.
  --   * submenu -- Gen2PackMenu/Gen2PartyMenu is on top of the stack and
  --     owns update() entirely (StateStack only updates its top state,
  --     see Screen:update's own note), so this screen would not even be
  --     running the frame the box was supposed to appear.
  --   * over -- terminal: the outcome is already decided and overMessage
  --     is already on screen. A pending prompt that reaches this is
  --     DROPPED with a log, never answered with an invented index (see
  --     Screen:promotePendingPrompt).
  local PROMPT_INTERRUPTIBLE = { actionMenu = true, resolving = true }

  -- Same 11px rows and same cursor column drawActionMenuEList uses --
  -- referenced by name rather than repeated as a literal so the prompt
  -- can never drift out of alignment with the action menu it sits in
  -- place of.
  local PROMPT_ROW_GAP = 11
  local PROMPT_LABEL_INSET = 10

  -- "The screen owns this frame for something the player is watching."
  -- Only moveAnim qualifies: Screen:update steps it independently of
  -- phase (its own note: an animation keeps stepping underneath the
  -- message text), so promoting mid-animation would drop a question over
  -- a move still playing out. suppressInputFrame is in here too because
  -- it means a native sub-menu popped back THIS frame and the physical
  -- press that closed it has not been consumed yet -- see Screen:
  -- openBag's own header for the double-pop bug that flag exists for.
  function Screen:promptBusy()
    return self.moveAnim ~= nil or self.suppressInputFrame == true
  end

  -- raise() writes exactly ONE field of the screen, self.phase, which is
  -- what makes restore() below trivially its exact inverse. The question
  -- text and the labels live on the record, and drawPromptF/drawPromptE
  -- read them from there -- deliberately NOT staged through self.message
  -- / self.currentMessage, which would displace a line the player has
  -- not read yet and give restore() three fields to get right instead of
  -- one. While the prompt is up, F and E are drawn entirely by the two
  -- prompt draws, so nothing else is competing for them anyway.
  function Screen:raisePrompt(ask)
    ask.savedPhase = self.phase
    self.prompt = ask
    self.phase = PROMPT_PHASE
    -- The same guard every callback in this file that hands control back
    -- to this screen sets (openBag/openSwitchMenu's own onClose/onChoose
    -- closures): the press that CAUSED the prompt -- the A that advanced
    -- a resolving message into the listener that asked -- must not also
    -- be readable as the press that ANSWERS it. One skipped frame, the
    -- house fix for exactly this class of bug.
    self.suppressInputFrame = true
  end

  function Screen:restorePrompt(ask)
    self.phase = ask.savedPhase
  end

  -- Restore FIRST, then call onAnswer -- chosen deliberately over its
  -- inverse ("call, then restore only if the callback did not move the
  -- phase"). Restoring first means:
  --   * a callback that ends the battle (screen:throwBall(...),
  --     screen:chooseMenuItem("RUN")) simply writes over a phase that
  --     was already valid, and needs no cooperation from this file;
  --   * a callback that does nothing leaves the battle exactly where the
  --     question interrupted it;
  --   * a callback that THROWS still cannot strand the battle, because
  --     the screen was already back in a phase Screen:update dispatches
  --     before the callback ever ran. The inverse ordering has no such
  --     guarantee -- it would have to inspect self.phase after an error
  --     to work out what the callback half-did, which is unknowable.
  -- The pcall is the same "a broken consumer degrades to a warning, not
  -- a broken battle" contract this file already applies to every other
  -- foreign call it makes (Screen:enterGimmickSelect pcalls every single
  -- battle_forms entry point).
  function Screen:answerPrompt(index)
    local ask = self.prompt
    if ask == nil then return end
    self.prompt = nil
    self:restorePrompt(ask)
    self.suppressInputFrame = true
    local ok, err = pcall(ask.onAnswer, index, self, ask.request)
    if not ok then
      mod.log:warn("g9_Battle_Scene: battle prompt %s onAnswer(%d) errored: %s",
        tostring(ask.id), index, tostring(err))
    end
  end

  function Screen:updatePrompt(input)
    local ask = self.prompt
    -- WATCHDOG. The phase is set but the record is not -- reachable only
    -- via a bug in this file or another mod writing self.phase directly.
    -- Screen:update's dispatch chain has no trailing else and
    -- drawContent's F/E chains have no default branch, so an unhandled
    -- phase here is not merely undrawn, it is a hard softlock: no input
    -- is read and no queue advances, forever, with the battle still on
    -- screen. Recovered into beginTurn rather than into a bare
    -- self.phase="actionMenu": enterActionMenu reads self.turnSlots[self
    -- .slotPtr], which after a mid-resolution strand is past the end of
    -- the array, so actingSlotIdx would be nil and the first FIGHT would
    -- index playerBattlers[nil]. beginTurn rebuilds turnSlots from the
    -- live roster and falls through to beginResolving when nobody can
    -- act, so it is valid from ANY state -- the price is re-picking this
    -- turn's actions, which is the right price for an impossible state.
    if ask == nil then
      mod.log:warn("g9_Battle_Scene: recovered a stranded battle-prompt phase")
      self:beginTurn()
      return
    end
    if input:wasPressed("b") then
      -- B answers rather than being swallowed, matching every other
      -- two-option box in the games. A caller that genuinely must not be
      -- escaped passes cancel=false, and B then does nothing at all --
      -- the prompt is still answerable, only not dismissable.
      if ask.cancel then self:answerPrompt(ask.cancel) end
      return
    end
    if input:wasPressed("a") then
      self:answerPrompt(ask.index)
      return
    end
    -- Exactly two rows, so every direction is the same toggle: there is
    -- only ever one other place to be. The same shortcut Screen:
    -- updateGimmickSelect takes over its own fixed 2x2 ("row = row == 1
    -- and 2 or 1"), and left/right are accepted for the same reason it
    -- accepts them -- a player who nudges the stick sideways at a
    -- two-option box means "the other one", not "nothing".
    if input:wasPressed("up") or input:wasPressed("down")
        or input:wasPressed("left") or input:wasPressed("right") then
      ask.index = ask.index == 1 and 2 or 1
    end
  end

  -- F: the question, wrapped to F's own real interior width exactly the
  -- way a resolving message is (drawWrapped, self.fChars) -- so a long
  -- question degrades to more lines, never to text running past the box
  -- border. Both draws no-op on a nil record so the one frame between a
  -- stranded phase and the watchdog clearing it draws an empty box
  -- rather than erroring inside love.graphics.
  function Screen:drawPromptF()
    local ask = self.prompt
    if not ask then return end
    drawWrapped(ask.text, self.fTextX, self.fTextY, self.fChars)
  end

  -- E: the two labels where FIGHT/BAG/PKMN/RUN normally sit, same rows,
  -- same cursor column. Truncated through fitName (glyph advances, not
  -- byte count) against the same E_INTERIOR_W-10 budget the CUSTOM
  -- button's own arbitrary user text already uses -- an over-long label
  -- clips instead of running past E's border, and neither the box nor
  -- the cursor moves under it.
  function Screen:drawPromptE()
    local ask = self.prompt
    if not ask then return end
    for i = 1, 2 do
      local label = fitName(ask.choices[i], E_INTERIOR_W - PROMPT_LABEL_INSET, 0)
      Font.draw(label, self.eTextX + PROMPT_LABEL_INSET,
        self.eTextY + (i - 1) * PROMPT_ROW_GAP)
    end
    Font.drawCode(CURSOR_CODE, self.eTextX, self.eTextY + (ask.index - 1) * PROMPT_ROW_GAP)
  end

  -- Promotion runs at the TAIL of Screen:update, after the phase
  -- dispatch, never before it. The dispatch is what settles self.phase
  -- for this frame, so asking first would test last frame's screen -- and
  -- the motivating consumer asks from INSIDE the dispatch (a listener
  -- firing during resolveTurnActions, which runs inside updateResolving),
  -- so promoting afterwards puts the box up on the very same frame the
  -- question was asked instead of one frame later.
  --
  -- REJECTED: waiting for the resolving message queue to drain before
  -- promoting, so the interrupted line gets read first. It sounds
  -- politer and is actually worse: the queue does not drain into an idle
  -- "resolving", it drains into finishTurn, which for a turn that ended
  -- the battle goes straight to "over" -- and a prompt whose whole
  -- premise is "this mon is down to its last" would then be dropped for
  -- being too late, every time, which is the one case the feature
  -- exists for. Displacing the current line and putting it back verbatim
  -- afterwards (restorePrompt leaves self.currentMessage untouched, so
  -- the very next resolving frame redraws the same line) costs the
  -- player one extra A press and never loses the question.
  function Screen:promotePendingPrompt()
    local pending = self.pendingPrompt
    if pending == nil then return end
    if self.exited or self.phase == "over" then
      -- Dropped with a log rather than answered with a synthetic index:
      -- a caller cannot tell a real answer from an invented one, and
      -- "CATCH it" fired at a battle that is already over is worse than
      -- silence. mod.exports.battleChoiceActive is how a caller checks.
      self.pendingPrompt = nil
      mod.log:warn("g9_Battle_Scene: battle prompt %s dropped, battle ended first",
        tostring(pending.id))
      return
    end
    if PROMPT_INTERRUPTIBLE[self.phase] and not self:promptBusy() then
      self.pendingPrompt = nil
      self:raisePrompt(pending)
    end
  end

  ------------------------------------------------------------------
  -- dispatch
  ------------------------------------------------------------------
  function Screen:update(dt)
    -- Damage-number lifetimes are wall-clock, independent of phase or
    -- input -- a label fades out over DMG_NUMBER_LIFE seconds whatever
    -- else is happening (see Screen:stepDmgNumbers).
    self:stepDmgNumbers(dt)
    -- Independent of input/phase -- a move animation keeps stepping
    -- underneath the message text the same way it does in every real
    -- Pokemon battle. Runner:step() returns false once the animation
    -- has genuinely finished (its own header note).
    if self.moveAnim then
      local anim = self.moveAnim
      if not anim.done then
        -- Gen 1 drives its own native AnimPlayer (a FIFO of row :starts);
        -- Gen 2 steps its runner.  Both report true here once finished.
        local finished
        if anim.gen1 then
          finished = self:stepGen1Anim(anim)
        else
          finished = not anim.runner:step()
        end
        if finished then
          anim.done = true
          -- A ball throw holds its own answer (self.catchPending) and reports
          -- it here, so the catch resolves on the beat the animation ends
          -- rather than a frame early -- see Screen:startCatchAnim.
          local onFinish = anim.onFinish
          anim.onFinish = nil
          if onFinish then onFinish() end
          -- A caught ball's own animation asks for its resting closed ball to
          -- stay in OAM through the caught text (Gen 2's anim_keepsprites;
          -- Gen 1's lockedBall = finalSprites).  Honour it by keeping the
          -- finished animation on screen; anything else clears normally.
          local keep = (anim.gen1 and anim.keepSprites)
                    or (anim.runner and anim.runner.keepSprites)
          if not keep then self.moveAnim = nil end
        end
      end
    end

    -- Same phase-independent stepping for the intro entrances (a pokeball
    -- throw or wild fade-in finishes its animation even if the player
    -- holds A) and the lose outro's blackout clock. A throw reveals its
    -- battler the instant the ball lands (t >= BALL_FLIGHT -- the poof
    -- and the mon's materialize phase then read over the HUD, matching
    -- native) and clears itself at the very end.
    if self.ballThrow then
      local bt = self.ballThrow
      bt.t = math.min(BALL_THROW_TOTAL, bt.t + dt)
      if bt.t >= BALL_FLIGHT and not bt.revealed then
        bt.revealed = true
        if bt.side == "player" then self.playerRevealed[bt.slot] = true
        else self.enemyRevealed[bt.slot] = true end
      end
      if bt.t >= BALL_THROW_TOTAL then self.ballThrow = nil end
    end
    if self.wildFade then
      self.wildFade.t = self.wildFade.t + dt
      if self.wildFade.t >= WILD_FADE_DURATION then self:finishEntrance() end
    end
    -- Same phase-independent stepping for the trainer-pic slide-offs:
    -- the enemy trainer's class front-pic slides right off (then the
    -- enemy mons are sent out), the player trainer's back-pic slides
    -- left off (then "Go! P!" beats run). A completed slide hides its
    -- pic (native: trainerSlide >= TRAINER_SLIDE_FRAMES ->
    -- showEnemyTrainer = false, same for backpicSlide) and advances the
    -- intro to the NEXT beat, so a slide never stalls the queue.
    if self.trainerSlide ~= nil then
      self.trainerSlide = self.trainerSlide + dt
      if self.trainerSlide >= TRAINER_SLIDE_DURATION then
        self.trainerSlide = nil
        self.showEnemyTrainer = false
        self:advanceIntro()
      end
    end
    if self.backpicSlide ~= nil then
      self.backpicSlide = self.backpicSlide + dt
      if self.backpicSlide >= BACKPIC_SLIDE_DURATION then
        self.backpicSlide = nil
        self.showPlayerTrainer = false
        self:advanceIntro()
      end
    end
    if self.outroT ~= nil then self.outroT = self.outroT + dt end

    local input = self.game.input
    if not input then
      -- No input device at all (a headless boot, a test harness) can
      -- never answer a question, so a prompt that is up here would hold
      -- the battle open forever. Answered with its own cancel index --
      -- what a player who refuses to engage with the box would press --
      -- rather than left hanging or dropped silently. A prompt raised
      -- with cancel=false has no such answer, so it falls back to the
      -- row the cursor is actually on, which is the only other honest
      -- reading of "nobody can press anything".
      if self.phase == PROMPT_PHASE and self.prompt then
        local ask = self.prompt
        mod.log:warn("g9_Battle_Scene: battle prompt %s answered %d, no input device",
          tostring(ask.id), ask.cancel or ask.index)
        self:answerPrompt(ask.cancel or ask.index)
      end
      return
    end
    -- See Screen:openBag's own note: the frame right after a native
    -- sub-menu (Gen2PackMenu/Gen2PartyMenu) pops back to this screen
    -- skips input entirely, so the same physical B/A press that closed
    -- the sub-menu can't ALSO be read here as a fresh press on this
    -- screen's own handlers -- confirmed live as the cause of cancel
    -- dropping straight back to the overworld instead of returning to
    -- the battle.
    if self.suppressInputFrame then
      self.suppressInputFrame = false
      return
    end

    if self.phase == "intro" then self:updateIntro(input)
    elseif self.phase == "actionMenu" then self:updateActionMenu(input)
    elseif self.phase == "moveSelect" then self:updateMoveSelect(input)
    elseif self.phase == "targetSelect" then self:updateTargetSelect(input)
    elseif self.phase == "swapSelect" then self:updateSwapSelect(input)
    elseif self.phase == "gimmickSelect" then self:updateGimmickSelect(input)
    elseif self.phase == PROMPT_PHASE then self:updatePrompt(input)
    elseif self.phase == "resolving" then self:updateResolving(input)
    elseif self.phase == "over" then self:updateOver(input)
    -- "submenu": Gen2PackMenu/Gen2PartyMenu is on top of the stack and
    -- owns update() entirely (StateStack only updates its top state) --
    -- this branch is never actually reached while that's true, kept
    -- only so an unexpected extra frame here is a no-op, not an error.
    end

    -- After the dispatch, never before it -- see Screen:
    -- promotePendingPrompt's own header for why, and for why this is the
    -- one placement that lets a question asked from inside the dispatch
    -- (the motivating case) appear on the same frame it was asked.
    self:promotePendingPrompt()
  end

  -- The pokeball itself: arcs from the thrower's side to the mon's
  -- platform (a quadratic bezier through the arc apex), then a white poof
  -- at the landing spot. The mon materializing is drawn by drawContent's
  -- own sprite path through ballAppearFor -- this pass is only the ball
  -- and the flash. A/B (updateIntro) can snap the whole thing to done.
  function Screen:drawBallThrow()
    local bt = self.ballThrow
    if not bt then return end
    local t = bt.t
    local r
    if bt.side == "player" then
      local cols = sideColumns(#self.playerBattlers, "player", false, self.isHorde)
      r = slotRect(cols, cols[bt.slot] or cols[1], ALLY_FEET_T, ROW_H, "ally")
    elseif self.isBoss and bt.slot == 1 then
      r = bossSlot()
    else
      local cols = sideColumns(#self.enemyBattlers, "enemy", self.isBoss, false)
      r = slotRect(cols, cols[bt.slot] or cols[1], ENEMY_FEET_T, ROW_H, "enemy")
    end
    -- Landing spot = where drawSprite actually bottom-anchored the mon
    -- this frame (self.spriteAnchor, filled by drawContent's sprite pass,
    -- which runs before this) -- the slot's own bottom-center, which is
    -- what the mon's own feet land on. Falling back to it only covers
    -- the very first frame, before any anchor exists.
    local tb = (bt.side == "player") and self.playerBattlers[bt.slot]
      or self.enemyBattlers[bt.slot]
    local anchor = tb and self.spriteAnchor[tb]
    local tx, ty
    if anchor then
      tx, ty = anchor.x, anchor.y
    else
      tx = r.x + r.w / 2
      ty = r.y + r.h
    end
    if t < BALL_FLIGHT then
      local p = t / BALL_FLIGHT
      local ox, oy, ax, ay
      if bt.side == "player" then
        ox, oy, ax, ay = BALL_PLAYER_OX, BALL_PLAYER_OY, BALL_PLAYER_AX, BALL_PLAYER_AY
      else
        ox, oy, ax, ay = BALL_ENEMY_OX, BALL_ENEMY_OY, BALL_ENEMY_AX, BALL_ENEMY_AY
      end
      local q = 1 - p
      local x = q * q * ox + 2 * q * p * ax + p * p * tx
      local y = q * q * oy + 2 * q * p * ay + p * p * ty
      -- The game's own ball as it flies this screen's arc: Gen 2's native
      -- object tumbling on its POKE_BALL_1 frameset, or Gen 1's own ball
      -- frame (drawPokeball only if that data isn't in the cache).
      if not drawNativeBall(self, x, y, t, false) then
        drawPokeball(x, y, BALL_RADIUS, p)
      end
    elseif t < BALL_FLIGHT + BALL_POOF then
      -- Landed: show the ball on the platform (lifted so it sits on the
      -- ground, not half-buried) under the white flash that fades as the
      -- mon materializes -- Gen 2's own opening pose, or Gen 1's own ball.
      drawNativeBall(self, tx, ty - BALL_LAND_LIFT, 0, true)
      local tp = (t - BALL_FLIGHT) / BALL_POOF
      love.graphics.setColor(1, 1, 1, 1 - tp)
      love.graphics.circle("fill", tx, ty, 4 + tp * 20)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- The two teams' slot rects for this frame, exactly the grid the sprite pass
  -- draws on (sideColumns/slotRect/bossSlot). Factored out of drawContent so
  -- Screen:prewarmSlot can resolve a sprite's seam inputs during the UPDATE
  -- phase and request the VERY sheet the draw pass will use -- the bake key
  -- is built from these rects, so a pre-warm computed from any other rect
  -- would bake a second, unused sheet.
  function Screen:slotRects()
    local enemyCols = sideColumns(#self.enemyBattlers, "enemy", self.isBoss, false)
    local playerCols = sideColumns(#self.playerBattlers, "player", false, self.isHorde)
    local enemyRects, playerRects = {}, {}
    for i = 1, #self.enemyBattlers do
      enemyRects[i] = (self.isBoss and i == 1)
        and bossSlot()
        or slotRect(enemyCols, enemyCols[i], ENEMY_FEET_T, ROW_H, "enemy")
    end
    for i = 1, #self.playerBattlers do
      playerRects[i] = slotRect(playerCols, playerCols[i], ALLY_FEET_T, ROW_H, "ally")
    end
    return enemyRects, playerRects
  end

  -- Start a battler's sheet BAKING during its pokeball's flight, instead of on
  -- the frame the ball lands (which is when the sprite pass first asks for it).
  -- The sprite mod spreads a sheet's scan/bake over frames under a per-update
  -- budget, so a first-look sheet is not ready for a good fraction of a second
  -- -- the ball's 0.45s airtime is exactly the head start it needs. resolveSprite
  -- is drawSprite's own resolve step, so this requests the same sheet key the
  -- draw pass will (same rect, hence the same bake key), and the result is thrown
  -- away: the side effect, the bake, is the whole point. Without it a managed
  -- species' first send-out materializes with its sprite still baking -- and
  -- now that the vanilla pic is suppressed during a build, the mon would pop
  -- in mid-grow instead of growing with its art.
  function Screen:prewarmSlot(side, slot)
    if not Runtime.wantsHook("battle.mon_pic") then return end
    local enemyRects, playerRects = self:slotRects()
    if side == "enemy" then
      local battler, r = self.enemyBattlers[slot], enemyRects[slot]
      if battler and r then
        resolveSprite(r, self.isBoss and slot == 1, battler, "spriteFront",
          self.data, self.spriteScaleFront)
      end
    else
      local battler, r = self.playerBattlers[slot], playerRects[slot]
      if battler and r then
        resolveSprite(r, false, battler, "spriteBack",
          self.data, self.spriteScaleBack)
      end
    end
  end

  function Screen:drawContent()
    -- Sprite positions come from the shared 8-column grid (sideColumns/
    -- slotRect) -- standardized, not per-preset; HUD and F/E positions still
    -- go through self:pos(id, defaultTx, defaultTy) so a preset may nudge
    -- one box. Looped over however many battlers are actually on each side
    -- (combat.lua's own logic iterates these same arrays with ipairs).
    --
    -- Draw order is deliberate: every SPRITE first (both teams), then the
    -- HUD boxes, then the ball/move animation, then F/E. HUD boxes on top
    -- of the field is what keeps a crowded team readable -- a tall sprite
    -- passes behind an HP box instead of covering it -- and it is why a
    -- preset can no longer hide a HUD under a sprite.
    -- -- sprites -------------------------------------------------------
    -- Each side's slots come straight from the grid (sideColumns/slotRect),
    -- so the allies fill rightward from a1 and the enemies leftward from e6,
    -- leaving the OUTER columns of an under-strength side empty. A slot is an
    -- ANCHOR (its centre-x, its ground
    -- line), not a size -- each sprite is drawn at its own size on it. The
    -- boss's lone enemy takes the boss slot, centred on e5. Screen:slotRects
    -- owns this computation (prewarmSlot asks it for the very same rects).
    local enemyRects, playerRects = self:slotRects()

    -- Where each mon's head actually lands THIS frame, in design px, keyed by
    -- battler -- filled as the sprite pass below draws each one, then read by
    -- the HUD pass to set each side's readout column down on its own mons'
    -- heads. The line is taken from the sprite's FULL-SIZE height (`fullH`)
    -- with the ground line it currently stands on (top + height), NOT from
    -- its drawn box this frame: the send-out materialize scales the sprite
    -- about its feet, so using the drawn height would let the readout ride
    -- up over BALL_APPEAR as the mon grows. A key is absent while a battler
    -- has no sprite on the field at all (its trainer pic still stands in the
    -- slot, or its ball/wild drop has not landed), which sideHeadY turns into
    -- the side's ground-line fallback -- its HUD is hidden until then anyway.
    local headLines = {}
    local function noteHead(battler, top, height, fullHeight)
      if top then
        headLines[battler] = top + height - GUI_HEAD_PCT * fullHeight
      end
    end

    for i, battler in ipairs(self.enemyBattlers) do
      local r = enemyRects[i]
      local boss = self.isBoss and i == 1
      -- Trainer-battle intro: the enemy trainer's class front-pic stands
      -- in the enemy slot (native's InitEnemyTrainer) while "{TRAINER}
      -- wants to battle!" reads, then slides right off in 8px steps
      -- (native's SlideBattlePicOut) before the first mon is sent out.
      if self.showEnemyTrainer and self.enemyTrainerImage and i == 1 then
        drawRawImage(self.enemyTrainerImage, r,
          slideStepPx(self.trainerSlide, TRAINER_SLIDE_DURATION, TRAINER_SLIDE_STEPS),
          true, self.enemyTrainerColors, self.enemyTrainerTrueColor)
      elseif self.wildFade and self.wildFade.slot == i
          and (self:shownHpOf(battler.mon) or 0) > 0 and not battler.caught then
        -- Wild entry: the wild mon appears IN PLACE at its final sprite
        -- position from the very first frame (no drop-in, no offY) and
        -- fades from completely invisible to completely visible over
        -- WILD_FADE_DURATION -- the user's rule (round sixty-three).
        -- Every other mon in the intro is thrown from a pokeball; this is
        -- the one that simply materializes. HUD + sprite are revealed only
        -- once the fade ends, exactly as the old drop gated them on landing.
        local p = math.min(1, self.wildFade.t / WILD_FADE_DURATION)
        local ax, ay, dty, dth, dfull = drawSprite(r, boss, battler, "spriteFront", self.data, true, 0, 0, nil, self.spriteScaleFront, p)
        if ax then
          self.spriteAnchor[battler] = { x = ax, y = ay, top = dty, h = dth }
          noteHead(battler, dty, dth, dfull)
        end
      elseif self.enemyRevealed[i] and (self:shownHpOf(battler.mon) or 0) > 0
          and not battler.caught and not animHidesMon(self, "enemy") then
        -- A fainted/caught battler's sprite is gone -- the box already hides
        -- on its own (drawGuiBox) and the sprite must follow, so a downed
        -- mon reads as an empty slot and the outro's win/defeat line plays
        -- over an empty field. Keyed off the CHASING hp (shownHpOf), so the
        -- sprite vanishes exactly when its bar drains to zero under the
        -- fainted narration, not the frame the whole turn's math commits.
        local appear = ballAppearFor(self, "enemy", i)
        local ax, ay, dty, dth, dfull = drawSprite(r, boss, battler, "spriteFront", self.data, true, 0, 0, appear, self.spriteScaleFront)
        if ax then
          self.spriteAnchor[battler] = { x = ax, y = ay, top = dty, h = dth }
          noteHead(battler, dty, dth, dfull)
        end
      end
    end

    for i, battler in ipairs(self.playerBattlers) do
      local r = playerRects[i]
      -- Intro lead-in: the player trainer's back-pic stands in the player
      -- slot (native's GetTrainerBackpic) until the very end of the
      -- intro, then slides left off in 8px steps (native's backpic-slide)
      -- just before the first "Go! P!". Only then is this mon drawn.
      if self.showPlayerTrainer and self.playerTrainerImage and i == 1 then
        drawRawImage(self.playerTrainerImage, r,
          -slideStepPx(self.backpicSlide, BACKPIC_SLIDE_DURATION, BACKPIC_SLIDE_STEPS),
          nil, self.playerTrainerColors, self.playerTrainerTrueColor)
      elseif self.playerRevealed[i] and (self:shownHpOf(battler.mon) or 0) > 0
          and not battler.caught and not animHidesMon(self, "player") then
        -- Pokeball send-out: the mon materializes at its platform (the
        -- ball itself is drawn by drawBallThrow) -- scaled in from the
        -- ground via ballAppearFor while its own "Go! P!" line reads.
        local appear = ballAppearFor(self, "player", i)
        local ax, ay, dty, dth, dfull = drawSprite(r, false, battler, "spriteBack", self.data, false, 0, 0, appear, self.spriteScaleBack)
        if ax then
          self.spriteAnchor[battler] = { x = ax, y = ay, top = dty, h = dth }
          noteHead(battler, dty, dth, dfull)
        end
      end
    end

    -- -- HUD boxes (over the field, under the ball/move anim) ----------
    -- ONE READOUT PER SLOT, in a single row per side, all at the side's one
    -- head line (see the placement header far above): each box is centred on
    -- its own slot's centre-x -- the point drawSprite centres that mon's
    -- sprite on, so the readout travels with it -- and the grid's pitch is
    -- the readout's own pitch (COL_W), so neighbouring boxes never overlap
    -- and no re-spread is needed. spreadBoxCentres still runs as the safety
    -- net for an overlapping row. Both draw from their LEFT edge
    -- (anchorRight=false), which is what guiTxOn's (centre - half width)
    -- arithmetic assumes.
    local enemyCentres, playerCentres = {}, {}
    for i = 1, #self.enemyBattlers do
      enemyCentres[i] = enemyRects[i].x + enemyRects[i].w / 2
    end
    for i = 1, #self.playerBattlers do
      playerCentres[i] = playerRects[i].x + playerRects[i].w / 2
    end
    local enemyRow = spreadBoxCentres(enemyCentres)
    local playerRow = spreadBoxCentres(playerCentres)
    -- One head line per side -- the mean of the heads of the sprites DRAWN
    -- for it this frame (sideHeadY/headLines) -- so every box on the side
    -- keeps the same height. Each box puts its BOTTOM edge on that line
    -- (one box per slot now, so both sides place their single row the same
    -- way); a side with nothing drawn yet falls back to its own ground line
    -- (its HUD is hidden until then anyway).
    local GUI_HEADLINE_ENEMY = sideHeadY(self.enemyBattlers, headLines, ENEMY_FEET_T * 8)
    local GUI_HEADLINE_ALLY = sideHeadY(self.playerBattlers, headLines, ALLY_FEET_T * 8)
    local GUI_TOP_ENEMY = GUI_HEADLINE_ENEMY - GUI_BOX_H_ENEMY * BOX_SCALE * 8
    local GUI_TOP_ALLY = GUI_HEADLINE_ALLY - GUI_BOX_H_PLAYER * BOX_SCALE * 8
    -- Where each battler's readout actually landed this frame (its centre-x,
    -- the box's own top-left tile x and top edge, and the box's sizeMul, all
    -- design px), keyed by battler. Screen:drawTargetMark drops its arrow just
    -- above the selected candidate's readout, and Screen:drawDmgNumbers
    -- centres a floating HP-change label under the candidate's HP bar.
    -- Recorded from the FINAL, preset-nudged tile position (and the box's own
    -- sizeMul) so a layout that moves or scales a readout takes both with it.
    -- `visible` mirrors that slot's own reveal flag, so a label is never drawn
    -- over a readout the HUD is deliberately hiding.
    self.hudMark = {}
    for i, battler in ipairs(self.enemyBattlers) do
      local gx, gy = self:pos("enemyGui" .. i, guiTxOn(enemyRow[i]), GUI_TOP_ENEMY / 8)
      local gs = self:sizeMul("enemyGui" .. i)
      self.hudMark[battler] = { x = gx * 8 + GUI_BOX_HALF_W * gs, top = gy * 8,
        left = gx * 8, gs = gs, h = GUI_BOX_H_ENEMY * 8,
        visible = self.enemyRevealed[i] and true or false }
      -- HUD box hidden until this mon is actually sent out (a trainer
      -- battle's intro shows the trainer's pic, not the mon, in this
      -- slot) -- drawGuiBox still hides it on its own for fainted/caught.
      if self.enemyRevealed[i] then
        drawGuiBox(gx, gy, GUI_TW, GUI_BOX_H_ENEMY, battler, self.data, false,
          false, gs, self:shownHpOf(battler.mon), self.hud)
      end
    end
    for i, battler in ipairs(self.playerBattlers) do
      local gx, gy = self:pos("playerGui" .. i, guiTxOn(playerRow[i]), GUI_TOP_ALLY / 8)
      local gs = self:sizeMul("playerGui" .. i)
      self.hudMark[battler] = { x = gx * 8 + GUI_BOX_HALF_W * gs, top = gy * 8,
        left = gx * 8, gs = gs, h = GUI_BOX_H_PLAYER * 8,
        visible = self.playerRevealed[i] and true or false }
      if self.playerRevealed[i] then
        drawGuiBox(gx, gy, GUI_TW, GUI_BOX_H_PLAYER, battler, self.data, true,
          false, gs, self:shownHpOf(battler.mon), self.hud)
      end
    end

    -- The target picker's field cursor (a no-op in every other phase), drawn
    -- on top of the readouts it sits above.
    self:drawTargetMark()
    -- The SWITCH cue (a no-op unless a swap is being chosen or is queued),
    -- same layer -- filled arrow on the target, hollow frame on the owner.
    self:drawSwapMark()

    -- Floating HP-change labels (a no-op unless the engine's damage-numbers
    -- option is on), drawn over the readouts they belong to and under the
    -- field effects below.
    self:drawDmgNumbers()

    -- Pokeball throw, drawn over every mon/GUI box but under F/E (so the
    -- flying ball and its landing flash read above the field, below the
    -- narration/menu).
    if self.ballThrow then
      self:drawBallThrow()
    end

    -- Move animation, on top of every sprite/GUI box but under F/E (so
    -- the message text and menu stay legible over it). Screen:
    -- drawMoveAnimObjects (its own header explains why it's a position-
    -- only remap, not a love.graphics.scale around BattleAnimView's own
    -- drawObjects) maps each object so p=vanillaAnchor lands exactly on
    -- the real attacker position, and the real attacker-target gap
    -- scales the rest -- fixes droplets stopping halfway (screenshot-
    -- reported) without stretching the droplet sprites themselves.
    if self.moveAnim then
      self:drawMoveAnimObjects()
    end

    -- Lose outro blackout: the canvas slowly fills from the bottom while
    -- the defeat message sits over it (vanilla's faint-to-black after
    -- your last mon falls). Drawn under F/E so the box stays legible.
    if self.phase == "over" and self.outcome == "lose" and self.outroT then
      local cover = math.min(VH, self.outroT / OUTRO_BLACKOUT_DURATION * VH)
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, VH - cover, VW, cover)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- Bottom: F (message/move/target, wide) beside E (FIGHT/BAG/PKMN/RUN,
    -- narrow), the two panes of the cart's own bottom box. Both go through
    -- Screen:withScale to apply their tuned size (see its own header for
    -- why the whole draw is scaled as one unit rather than the geometry
    -- being pre-scaled). self.fTextX/fTextY/eTextX/eTextY stay the box's
    -- own UNSCALED default text origin -- correct because they're read only
    -- from INSIDE that same withScale block below, where the transform
    -- itself does the scaling; fChars is the fixed default (F's own tile
    -- capacity doesn't change, only its on-screen size does).
    --
    -- ONE box, TWO panes (round eighty-one): the frame is drawn once,
    -- across both panes, with the menu window's left edge drawn over it as
    -- a divider -- the cart's own shape (drawNativeDivider's header).  F
    -- and E used to be two separately framed boxes, so their facing borders
    -- ran two pixels apart down the middle of the band and every corner of
    -- both frames sat at the junction; now there is one continuous frame
    -- and a single divider line, which is what makes the pair read as the
    -- native bottom box.
    --
    -- Intro/outro narration draws a FULL-WIDTH message box -- vanilla spans
    -- its battle text across the whole bottom row and only splits off the E
    -- menu (FIGHT/BAG/PKMN/RUN) once the action menu is up.  F grows by
    -- E_TW; E is skipped entirely.
    local narrationW = (self.phase == "intro" or self.phase == "over")
    local fx, fy = self:pos("fBox", 0, BOTTOM_Y)
    local ex, ey = self:pos("eBox", F_TW, BOTTOM_Y)
    local fw = narrationW and (F_TW + E_TW) or F_TW
    -- F and E still share an edge, so they are one box.  A layout preset
    -- that moves one of them away instead gets two separate frames rather
    -- than a divider drawn in mid-air.
    local joined = (fy == ey) and (fx + fw == ex)
    self.fTextX, self.fTextY = (fx + 1) * 8 + 2, (fy + 1) * 8 + 2
    self.eTextX, self.eTextY = (ex + 1) * 8 + 2, (ey + 1) * 8 + 2
    self.fChars = fw - 4

    self:withScale("fBox", fx, fy, function()
      love.graphics.setColor(1, 1, 1, 1)
      if joined then
        drawNativeFrame(fx, fy, fw + E_TW, BOTTOM_H)
        drawNativeDivider(ex, fy, BOTTOM_H)
      else
        drawNativeFrame(fx, fy, fw, BOTTOM_H)
      end
      love.graphics.setColor(0, 0, 0, 1)
      if self.phase == "intro" then
        drawWrapped(self.currentMessage or "", self.fTextX, self.fTextY, self.fChars)
      elseif self.phase == "actionMenu" then
        self:drawActionMenuF()
      elseif self.phase == "moveSelect" then
        self:drawMoveSelect()
      elseif self.phase == "targetSelect" then
        self:drawTargetSelect()
      elseif self.phase == "swapSelect" then
        self:drawSwapSelect()
      elseif self.phase == "gimmickSelect" then
        self:drawGimmickSelect()
      elseif self.phase == PROMPT_PHASE then
        self:drawPromptF()
      elseif self.phase == "resolving" then
        drawWrapped(self.currentMessage or "", self.fTextX, self.fTextY, self.fChars)
      elseif self.phase == "over" then
        drawWrapped(self.overMessage or "", self.fTextX, self.fTextY, self.fChars)
      end
    end)

    if not narrationW then
      self:withScale("eBox", ex, ey, function()
        if not joined then
          love.graphics.setColor(1, 1, 1, 1)
          drawNativeFrame(ex, ey, E_TW, BOTTOM_H)
        end
        love.graphics.setColor(0, 0, 0, 1)
        -- The prompt's two labels go where FIGHT/BAG/PKMN/RUN normally sit
        -- -- the same vanilla text-box-plus-menu split this box exists for
        -- (see drawContent's own note above), so a question reads as the
        -- action menu temporarily offering two different actions rather
        -- than as a foreign box dropped on the field.
        if self.phase == "actionMenu" then self:drawActionMenuE()
        elseif self.phase == PROMPT_PHASE then self:drawPromptE() end
      end)
    end
  end

  function Screen:draw()
    -- GEN 1'S PATH.  src/core/Game.lua has no drawWidescreen channel (that
    -- is Game2's), so on Gen 1 the engine calls this instead, into the UI
    -- surface it sized from Screen:uiSize -- which is CANVAS_W x CANVAS_H,
    -- so the fit below resolves to scale 1 and drawContent lands on that
    -- surface 1:1, filling it edge to edge.  It still degrades sanely if the
    -- engine ever hands the scene a different surface (it fits whatever it
    -- is drawing into).  On Gen 2 this method is never called -- Game2
    -- resolves the surround through drawsWidescreen/drawWidescreen.
    --
    -- ASK FOR THE SURFACE, NOT THE WINDOW.  The engine owns the window: it
    -- sizes a UI surface from Screen:uiSize (Renderer:setUISize) and blits
    -- that surface into the window itself, exactly as it does for its own
    -- wide battle -- and src/battle/WideBattle.lua draws that composition in
    -- NATIVE SURFACE PIXELS and never asks how big the window is.
    -- love.graphics.getDimensions() reports the WINDOW, so the fit that used
    -- to be here sized the 320x180 field against the window: on any window
    -- larger than the surface the field was drawn OVERSIZED into the 960x540
    -- canvas, and the canvas' own bottom and right edges then sliced it.
    -- That is what pushed the bottom message/menu band out of the picture --
    -- user-reported, with a screenshot: "F and E box being pushed out of
    -- screen".  The F box kept only its top border sliver and lost the rest
    -- of its frame; the E box additionally lost its right edge, because the
    -- field was cut past design x246 and E's own right border sits at 312.
    -- The live canvas is the literal answer (Renderer:beginFrame sets it to
    -- the UI surface), Renderer:uiSize() is the size the engine allocated it
    -- from, and getDimensions() stays the last resort for the no-canvas case
    -- -- drawing straight to the window, e.g. a headless test.
    local w, h
    local canvas = love.graphics.getCanvas and love.graphics.getCanvas()
    if canvas and canvas.getWidth and canvas.getHeight then
      w, h = canvas:getWidth(), canvas:getHeight()
    end
    if not (w and h and w > 0 and h > 0) then
      local ok, Renderer = pcall(require, "src.render.Renderer")
      if ok and type(Renderer) == "table" and Renderer.uiSize then
        w, h = Renderer:uiSize()
      end
    end
    if not (w and h and w > 0 and h > 0) then
      w, h = love.graphics.getDimensions()
    end
    local scale = fitScale(w, h)
    local ox, oy = fitOrigin(w, h, scale)
    love.graphics.push()
    love.graphics.translate(ox, oy)
    -- Window px per CANVAS px (scale) times CANVAS px per DESIGN px (DS):
    -- drawContent is authored in the 320x180 design field and lands on the
    -- 960x540 canvas, which is then scaled to the window.
    love.graphics.scale(scale * DS, scale * DS)
    self:drawContent()
    love.graphics.pop()
  end

  function Screen:wantsFillScale() return true end
  function Screen:drawsWidescreen() return true end

  function Screen:drawWidescreen(winW, winH)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, winW, winH)
    local scale = fitScale(winW, winH)
    local ox, oy = fitOrigin(winW, winH, scale)
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale * DS, scale * DS)
    self:drawContent()
    love.graphics.pop()
  end

  ------------------------------------------------------------------
  -- WIDESCREEN CONTRACT (Gen 1).
  --
  -- src/core/Game.lua's renderer is built around a fixed UI SURFACE that a
  -- state may widen, not around a state painting its own window.  Its
  -- widescreen battle is exactly this: BattleState:isWideBattleLayout +
  -- BattleState:uiSize ask Renderer:setUISize for a 304x144 canvas, the
  -- state draws into it in native pixels, and endFrame blits it (filled to
  -- the window via wantsFillScale/BATTLE SIZE "fill").  Gen 1 has no
  -- drawWidescreen hook, so this scene joins that mechanism instead of
  -- inventing a second one: the surface IS the scene's own 960x540 canvas,
  -- so Screen:draw needs no rescale and every engine service the wide battle
  -- already gets -- the fill scale, the palette-zone pass, the letterbox,
  -- the centring of any classic state pushed over it -- applies unchanged.
  --
  -- The Gen 2 path is untouched by every member below: Game2 resolves its
  -- surround through drawsWidescreen/drawWidescreen and never reads
  -- isWideBattleLayout/uiSize/sgbPalettes/letterboxWhite/holdsUIAnchors
  -- (they are Gen-1-only names in the engine -- see src/mods/Gen2Compat.lua's
  -- own absent lists), so the scene renders on Gold exactly as it did.

  -- Owns the whole screen, so the renderer must keep drawing IT when an
  -- opaque classic state (a native text box, a menu) is pushed over it --
  -- the same "a wide battle owns the surface until it leaves the stack"
  -- rule Game.drawBaseInStack applies to the native wide layout.
  function Screen:isWideBattleLayout() return true end

  -- The surface Renderer:setUISize allocates for this state: the scene's own
  -- canvas, so drawContent's design->canvas scale (DS, see Screen:draw) lands
  -- it there 1:1 rather than being letterboxed into a Game Boy screen.
  function Screen:uiSize() return CANVAS_W, CANVAS_H end

  -- Mirrors src/battle/WideBattle.zones() for a scene that resolves its own
  -- colours: one whole-surface trueColor zone, so the engine's shade-remap
  -- shader never runs over art that is already the colour it should be.  A
  -- nil answer here would let PaletteFX.ensureZones invent a 160x144 zone in
  -- the forced-mono modes, which would remap only the top-left corner of a
  -- 960x540 surface -- the WideBattle module stores the same opt-out for the
  -- same reason.
  function Screen:sgbPalettes()
    return { { colors = false, x = 0, y = 0, w = CANVAS_W, h = CANVAS_H } }
  end

  -- The scene paints its own opaque field edge to edge; a window that is not
  -- 16:9 gets the display mode's paper in its bars rather than black, which
  -- is what drawWidescreen's own window fill does on Gen 2.
  Screen.letterboxWhite = true

  -- A battle composes its own screen, so engine UI anchors (dialogue boxes,
  -- the START menu) must not dock to the window edge over it -- the native
  -- wide battle sets this for the same reason.
  Screen.holdsUIAnchors = true

  -- The engine bounds a state's requested surface to Renderer.MAX_UI_WIDTH/
  -- MAX_UI_HEIGHT (640x576, sized for its own 304x144 wide battle), which
  -- would clamp this scene's 960x540 request back to 160x144.  Widen the
  -- bound additively and once, to exactly this file's canvas: the guard's
  -- intent (never allocate an unbounded canvas) is preserved, and it is done
  -- only on Gen 1 -- Game2 never calls Renderer:setUISize, so Gen 2's render
  -- path never reads this value at all.
  if not N.isGen2 then
    local ok, Renderer = pcall(require, "src.render.Renderer")
    if ok and type(Renderer) == "table" then
      Renderer.MAX_UI_WIDTH = math.max(Renderer.MAX_UI_WIDTH or 0, CANVAS_W)
      Renderer.MAX_UI_HEIGHT = math.max(Renderer.MAX_UI_HEIGHT or 0, CANVAS_H)
    end
  end

  -- Real vanilla entry sequence, owned here so every caller (Sample-
  -- Battle-Scene's wild trigger today, any future bossFight/horde caller
  -- tomorrow) gets it automatically instead of each one having to
  -- remember it separately -- user-reported: a battle pushed through
  -- this mod skipped straight to the scene with no fade/flash and no
  -- battle music, because the caller's own encounter-trap technique
  -- (temporarily stubbing World.startBattle to capture its opts) never
  -- lets the REAL startBattle run, which is where both live natively
  -- (World.lua:5787 playBattleMusic, :5800 pushBattleTransition, :5821
  -- startBattle's own header: "PlayBattleMusic runs BEFORE the
  -- transition, which is why the battle theme is already going while
  -- the wipe is still spinning" -- replicated in that order below).
  -- Both are real, public World methods, nil-guarded so a headless/
  -- test call without a live World still works exactly as before.
  -- data.trainer (optional) is forwarded as opts.trainer for a future
  -- trainer-battle caller -- wild callers simply omit it.
  -- Real native Battle, constructed the same way World:startBattle
  -- assembles one (World.lua:5827-5846) -- data/party/random, plus
  -- wild/trainer so Mon.refreshStats runs over the real roster and
  -- Runtime.emit("battle.started",...) fires for anything hooking it.
  --
  -- Honest limitation, not hidden: Battle.new only accepts a SINGLE
  -- `wild` mon (self.enemyParty = {opts.wild}, Battle.lua:262-270) or a
  -- trainer-shaped party array (self.enemyParty = trainer.party,
  -- :271-291) -- there is no "N wild mons" constructor shape. A true
  -- wild encounter with more than one enemy has to go through the
  -- trainer-shaped path to get every enemy into self.enemyParty (and
  -- therefore through Mon.refreshStats), which means Battle:self.wild
  -- reads false for it -- a real, structural gap in the native
  -- constructor this fork works around rather than papers over. Combat
  -- resolution itself is unaffected either way (resolveTurnActions never
  -- reads battle.player/battle.enemy/battle.wild at all).
  -- data.trainer accepts either a plain `true` (legacy -- every caller
  -- before this fix, including this mod's own multi-enemy wild case) or
  -- the REAL trainer definition table
  -- ({class=,name=,baseMoney=,...}, the same shape World:startBattle's
  -- own opts.trainer always carried) -- explicit fix, since the plain-
  -- boolean path always synthesized a fake {class="TRAINER",name="",
  -- baseMoney=0} trainer, silently losing the real payout amount, class
  -- (gym-leader happiness bonus, Battle.lua:332-334) and name for any
  -- caller routing a REAL trainer battle through this screen -- not a
  -- gap that mattered while nothing did that, but Sample-Battle-Scene-G9
  -- now does. `party` is always overridden to data.enemies (the real
  -- roster this screen is actually rendering, e.g. just 2 of a trainer's
  -- full team for a doubles subset) rather than trusting whatever the
  -- real trainer table's own `party` field says.
  local function buildBattle(game, data)
    local opts = {
      data = game.data,
      party = data.players,
      save = game.save,
    }
    if #data.enemies <= 1 and not data.trainer then
      opts.wild = data.enemies[1]
    elseif type(data.trainer) == "table" then
      opts.trainer = {}
      for k, v in pairs(data.trainer) do opts.trainer[k] = v end
      opts.trainer.party = data.enemies
    else
      opts.trainer = { class = "TRAINER", name = "", party = data.enemies, baseMoney = 0 }
    end
    return N.buildBattle(opts, game, data)
  end

  mod.exports.pushDoubleBattleScreen = function(game, world, data)
    local combat = mod.exports.combat
    local g9dex = mod:find("g9-battle-engine")
    -- Gen 2 resolves turns through g9-battle-engine and needs it.  Gen 1
    -- has no model the engine can drive (see native.lua's combat-authority
    -- note), so the engine mod is optional there and the native Gen 1 engine
    -- resolves instead -- the assert is Gen 2 only.
    if N.isGen2 then
      assert(g9dex and g9dex.exports and g9dex.exports.resolveTurnActions,
        "g9-Battle-Scene: g9-battle-engine not loaded or missing resolveTurnActions")
    end
    -- A SCENE MUST REPLACE A BATTLE, NEVER LAYER OVER ONE.
    --
    -- buildBattle below calls Battle.new, and Battle.new emits
    -- `battle.started` from inside its own constructor
    -- (src/battle/gen2/Battle.lua) with no way to opt out.  That is correct
    -- and wanted: this IS the battle being played, and peers like
    -- battle_forms need the event to set themselves up for it.
    --
    -- It is only wrong when the caller has ALSO let the engine start one.
    -- Then two Battle objects are live for one encounter, `battle.started`
    -- fires twice, and every peer that remembers the battle it was told
    -- about is now holding the one that is not on screen.  That is not
    -- hypothetical: it cost a real player their transformation menu for a
    -- whole session, and it is invisible from in-game -- battle_forms'
    -- diagnostic said `armState=another battle ... offered=0` while every
    -- input it reported was correct.
    --
    -- `world.battleActive` is the engine's own "a battle screen this world
    -- pushed is up" flag, set by World:startBattle at the moment it pushes
    -- (src/world/gen2/World.lua) and cleared on the way out, and this file
    -- already sets and clears it too.  So it answers the question exactly.
    --
    -- A warning, not a refusal: the scene is what the caller asked for and
    -- the player is better served by the fight they were promised than by a
    -- silent no.  What this buys is that the mistake is loud at the moment
    -- it is made, instead of being diagnosed days later from a peer's own
    -- trace.
    if world.battleActive then
      mod.log:warn("g9_Battle_Scene: a battle was already running when this "
        .. "scene was pushed -- the caller should replace the engine's "
        .. "battle, not layer over it. Two Battle objects are now live for "
        .. "one encounter, so battle.started has fired twice and any mod "
        .. "holding the battle it was told about is holding the wrong one.")
    end
    local battle = buildBattle(game, data)
    -- Wild-boss special properties (SPECIAL BOSSES / SHINY BOSS) and the
    -- BOSS CATCH marker -- see special_boss.lua's own header.  Runs BEFORE
    -- Screen.new on purpose: the shiny flag decides which sprite the intro
    -- fades in, the engine's stored tera/dynamax fields are what the screen
    -- and the eventual catch both read, and the boss's stats are recomputed
    -- here so the first HP bar matches.  A non-boss layout, or a TRAINER
    -- routed to the bossFight layout, is left completely alone.
    if mod.exports.specialBoss and mod.exports.specialBoss.applyWildBoss then
      pcall(mod.exports.specialBoss.applyWildBoss, battle, game, data)
    end
    -- Hand the engine's move-validity query and this live battle to the
    -- combat module so its move lists can be annotated (Choice move-lock,
    -- item move-type ban, Taunt/Torment, unmet move conditions). combat.engine
    -- is nil on a boot that lacks the mod, in which case every annotation is
    -- skipped and everything else is unchanged.
    combat.engine = g9dex and g9dex.exports or nil
    combat.battle = battle
    local inst = Screen.new(game, world, data, combat, game.data, battle, g9dex)
    -- Also what mod.exports.askBattleChoice resolves against -- see
    -- resolvePromptTarget, which reads this same reference rather than
    -- keeping a second one of its own.
    lastScreen = inst
    world.battleActive = true
    local opts = { trainer = data.trainer }
    if world.playBattleMusic then world:playBattleMusic(opts) end
    local transitioned = world.pushBattleTransition
      and world:pushBattleTransition(nil, opts, function() game.stack:push(inst) end)
    if not transitioned then
      game.stack:push(inst)
    end
    return inst
  end

  ------------------------------------------------------------------
  -- TWO-CHOICE PROMPT: the public API. See the "TWO-CHOICE PROMPT"
  -- section above for the design and for what was rejected.
  ------------------------------------------------------------------

  -- `target` may be this mod's own battle Screen (what the callback is
  -- handed, and what pushLayoutBattle/pushDoubleBattleScreen return), a
  -- native Battle model (what every battle.* event payload carries -- a
  -- listener holds the model and never the screen), or nil for "whatever
  -- battle is on screen".
  --
  -- A Battle resolves ONLY while it is the one actually being played:
  -- aiming a question at a backgrounded or finished battle and having it
  -- land on the live screen would put the box on the wrong fight, which
  -- is worse than refusing.
  -- `lastScreen` is deliberately never cleared (see its own header), so a
  -- reference to a FINISHED battle can outlive it. `exited` -- the flag
  -- Screen:finishBattleExit already sets as its first act, and which every
  -- other line in that function relies on -- is what separates "the screen
  -- being played" from "the last screen that was". Parking a question on a
  -- screen one frame from being popped would silently drop it.
  local function resolvePromptTarget(target)
    local live = lastScreen
    if live ~= nil and live.exited then live = nil end
    if target == nil then return live end
    if type(target) == "table" and getmetatable(target) == Screen then return target end
    if live ~= nil and live.battle == target then return live end
    return nil
  end

  -- askBattleChoice(target, request) -> true | false, reason
  --
  --   target   this mod's battle Screen, a Battle, or nil (see above).
  --   request  { text     = "ETERNATUS is barely standing!",  -- required
  --              choices  = { "CATCH it", "LEAVE it" },       -- required, 2
  --              onAnswer = function(index, screen, request) end, -- required
  --              default  = 1,      -- optional, row the cursor opens on
  --              cancel   = 2,      -- optional, index B answers with;
  --                                 -- false makes B inert
  --              id       = "..." } -- optional, appears in this mod's logs
  --
  -- onAnswer receives the 1-based index of the chosen label, the Screen,
  -- and the caller's own request table back, and is called with the
  -- battle ALREADY restored to the phase the question interrupted. That
  -- is the whole contract: the answer is reported and the callback does
  -- whatever it wants with a screen that is in a valid, running state --
  -- nothing, or something that ends the battle. Both real endings are
  -- one public method call, and neither is wrapped in a helper here (the
  -- section header explains why):
  --
  --   screen:throwBall("POKE_BALL")   -- modern SV catch formula;
  --       spends one ball, and on a catch files the mon, sets
  --       outcome="caught" and moves
  --       to "over" (the player presses A and the screen pops); on a
  --       break-free it consumes the acting slot's action and resolves
  --       the turn, exactly as a ball thrown from the BAG would. Note it
  --       does NOT re-check Screen:catchAllowed -- that gate belongs to
  --       Screen:useItem, the BAG path. A caller offering a catch is by
  --       definition asserting a catch is allowed right now; this API
  --       does not second-guess it.
  --   screen:chooseMenuItem("RUN")    -- outcome="run", finishBattleExit,
  --       stack pop. Ends the battle immediately, with no further press.
  --
  -- Standing gap a consumer of this API has to know about, found while
  -- reading those two paths and NOT fixed here (out of scope, flagged
  -- rather than silently worked around): this screen never emits
  -- "battle.ended" for any ending at all. finishTurn, throwBall and the
  -- RUN branch each just set self.outcome and self.phase="over";
  -- Battle:endBattle -- the only Runtime.emit("battle.ended") site in
  -- the engine -- is never reached from here. So a caller must NOT wait
  -- on battle.ended to learn that its own answer ended the battle: the
  -- onAnswer call itself is the signal, and screen.outcome is readable
  -- from inside it the moment the ending method returns.
  --
  -- Returns false plus a reason string rather than throwing. Every
  -- refusal below is a condition a caller can legitimately hit at
  -- runtime (no battle on screen, a battle that ended a frame earlier, a
  -- second question while one is up) and none of them is a programming
  -- error worth killing a battle over.
  mod.exports.askBattleChoice = function(target, request)
    if type(request) ~= "table" then return false, "request must be a table" end
    local choices = request.choices
    if type(choices) ~= "table" or #choices ~= 2
        or type(choices[1]) ~= "string" or type(choices[2]) ~= "string" then
      return false, "request.choices must be exactly two strings"
    end
    if type(request.onAnswer) ~= "function" then
      return false, "request.onAnswer must be a function"
    end
    if type(request.text) ~= "string" or request.text == "" then
      return false, "request.text must be a non-empty string"
    end
    local screen = resolvePromptTarget(target)
    if screen == nil then return false, "no live g9-Battle-Scene battle screen" end
    if screen.exited or screen.phase == "over" then return false, "battle is over" end
    -- One question at a time. Stacking would mean the second raise saving
    -- the FIRST prompt's phase (PROMPT_PHASE itself) as the context to
    -- restore to, which puts the screen back into the prompt phase with
    -- no record -- the exact stranded state Screen:updatePrompt's
    -- watchdog exists to clean up after. Refusing is cheaper than
    -- recovering.
    if screen.prompt ~= nil or screen.pendingPrompt ~= nil then
      return false, "a prompt is already up"
    end
    local ask = {
      id = request.id or "unnamed",
      request = request,
      text = request.text,
      -- Copied, not aliased: the caller's table stays theirs to mutate,
      -- and a label changing between the raise and the next draw would
      -- move the cursor's own row labels under the player.
      choices = { choices[1], choices[2] },
      index = (request.default == 2) and 2 or 1,
      onAnswer = request.onAnswer,
    }
    -- cancel=false disables B outright; anything else (nil included)
    -- defaults to 2, matching every two-option box in the games where B
    -- is the second/negative option.
    if request.cancel == false then
      ask.cancel = nil
    elseif request.cancel == 1 then
      ask.cancel = 1
    else
      ask.cancel = 2
    end
    -- Parked, not raised on the spot: Screen:promotePendingPrompt raises
    -- it on the first frame the screen is genuinely interruptible, so a
    -- caller may ask from anywhere -- a battle.damage listener firing
    -- mid-resolution, a faint handler mid-animation -- without having to
    -- know anything about this screen's phases.
    screen.pendingPrompt = ask
    return true
  end

  -- "pending" (asked for, waiting for an interruptible frame) and
  -- "active" (the box is up) are reported separately because they mean
  -- different things to a caller: a pending prompt may still be dropped
  -- if the battle ends first, an active one will always reach onAnswer.
  mod.exports.battleChoiceActive = function(target)
    local screen = resolvePromptTarget(target)
    if screen == nil then return nil end
    if screen.prompt ~= nil then return "active" end
    if screen.pendingPrompt ~= nil then return "pending" end
    return nil
  end

  -- Withdraws a question without answering it -- for a caller whose own
  -- reason for asking evaporated (the mon it was about fainted to
  -- residual damage while the box was up). onAnswer is NOT called: there
  -- was no answer. The displaced phase is put back exactly as an answer
  -- would put it back, so this is always safe to call.
  mod.exports.cancelBattleChoice = function(target)
    local screen = resolvePromptTarget(target)
    if screen == nil then return false end
    if screen.pendingPrompt ~= nil then
      screen.pendingPrompt = nil
      return true
    end
    local ask = screen.prompt
    if ask == nil then return false end
    screen.prompt = nil
    screen:restorePrompt(ask)
    return true
  end

  ------------------------------------------------------------------
  -- POSITIONAL SWITCH (public API). The SAME swap the player's own
  -- SWITCH button performs, exposed so an enemy-side AI -- or any script
  -- -- can trade the places of two ADJACENT mons. Enemy allies occupy
  -- roster slots exactly as player allies do (sideColumns fills the
  -- enemy half leftward from e6 in index order), so "adjacent" is index
  -- adjacency on either side and one validation serves both. Applied
  -- immediately: a swap is pure position, so nothing needs to wait for
  -- the turn to resolve and an AI can reposition mid-turn, the field
  -- updating on the next frame.
  -- ------------------------------------------------------------------

  -- swapPositions(target, side, slotA, slotB) -> true | false, reason
  --   target  this mod's battle Screen, a Battle, or nil for the live one.
  --   side    "enemy" or "player".
  --   slots   two ADJACENT roster indices (|slotA - slotB| == 1) holding
  --           living battlers.
  mod.exports.swapPositions = function(target, side, slotA, slotB)
    if side ~= "enemy" and side ~= "player" then
      return false, "side must be 'enemy' or 'player'"
    end
    if type(slotA) ~= "number" or type(slotB) ~= "number" then
      return false, "slotA and slotB must be numbers"
    end
    local screen = resolvePromptTarget(target)
    if screen == nil then return false, "no live g9-Battle-Scene battle screen" end
    if screen.exited or screen.phase == "over" then return false, "battle is over" end
    if math.abs(slotA - slotB) ~= 1 then return false, "slots must be adjacent" end
    local list = (side == "enemy") and screen.enemyBattlers or screen.playerBattlers
    local a, b = list[slotA], list[slotB]
    if not (a and b) then return false, "no battler in that slot" end
    if not screen.combat.isAlive(a) or not screen.combat.isAlive(b) then
      return false, "a battler in that slot has fainted"
    end
    list[slotA], list[slotB] = b, a
    return true
  end

  -- swapCandidates(target, side, slot) -> array of slot indices | nil, reason
  -- The query an enemy AI pairs with swapPositions: which of `slot`'s
  -- neighbours it can legally trade places with, empty when none.
  mod.exports.swapCandidates = function(target, side, slot)
    if side ~= "enemy" and side ~= "player" then
      return nil, "side must be 'enemy' or 'player'"
    end
    if type(slot) ~= "number" then return nil, "slot must be a number" end
    local screen = resolvePromptTarget(target)
    if screen == nil then return nil, "no live g9-Battle-Scene battle screen" end
    local list = (side == "enemy") and screen.enemyBattlers or screen.playerBattlers
    local out = {}
    for _, j in ipairs({ slot - 1, slot + 1 }) do
      local b = list[j]
      if b and screen.combat.isAlive(b) then out[#out + 1] = j end
    end
    return out
  end

  mod.log:info("g9_Battle_Scene: battle_screen installed (prompt API: askBattleChoice, battleChoiceActive, cancelBattleChoice; switch API: swapPositions, swapCandidates)")
end
