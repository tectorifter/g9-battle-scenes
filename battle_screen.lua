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
-- Virtual canvas is still 320x144 (40x18 tiles), fit via drawWidescreen
-- against the real window.
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
  -- Real native Battle, constructed here so battle:useMove (driven
  -- through g9-battle-engine-beta's mod.exports.resolveTurnActions) has
  -- the type chart/stats/RNG/event-queue machinery it needs -- see
  -- pushDoubleBattleScreen's own comment for why battler roster/identity
  -- still stays this mod's own arrays, never battle.player/battle.enemy.
  local Battle = require("src.battle.gen2.Battle")
  -- Real catch formula/rate, replacing g2-Battle-Scene's own catch.lua
  -- (dropped entirely in this fork -- see manifest.json's description).
  local Catching = require("src.battle.gen2.Catching")
  -- Genuinely pure (data in, data out, no Battle-instance dependency) --
  -- confirmed by direct source read, the same standard this mod already
  -- held Damage.calc/Catching.attempt to. HpBar.pixels/.palette/.draw
  -- reproduce the cart's own ComputeHPBarPixels/GetHPPal exactly (the
  -- 48px-wide bar, its green/yellow/red thresholds, a live mon never
  -- showing a fully-empty bar), so this mod's bar reads identically to
  -- every native HP bar in the game rather than a reinvented one.
  local HpBar = require("src.battle.gen2.HpBar")
  -- The real move-animation engine, Gen 2's own -- separate from Gen 1's
  -- (src/battle/AnimPlayer.lua) and, confirmed by direct source read,
  -- NOT coupled to the native single-battle BattleState class at all:
  -- AnimRunner.new/:start/:step just needs data/constants/hooks (its own
  -- header says "Love-free"), and BattleAnimView:drawObjects(runner,
  -- battle) is the only half that touches love.graphics. The reference
  -- wiring this mirrors is src/ui/gen2/BattleState.lua:1064-1151
  -- (startAnim/animForMove).
  local AnimRunner = require("src.battle.gen2.AnimRunner")
  local BattleAnimView = require("src.ui.gen2.BattleAnimView")
  -- Both needed to draw a move animation's OBJ layer with the real
  -- attacker/target position remap (Screen:drawMoveAnimObjects) instead
  -- of BattleAnimView:drawObjects' own vanilla-fixed coordinates -- same
  -- require paths BattleAnimView.lua itself uses.
  local bit = require("bit")
  local GbcPalette = require("src.render.GbcPalette")

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
  -- comment) and already index-aligned with each layout preset's own
  -- enemySprite<i>/playerSprite<i> position slots -- this wrap is the
  -- missing piece connecting that real grid to g9-battle-engine-beta's
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
    -- loading, the same lazy-lookup convention g9-battle-engine-beta's
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

  local VW, VH = 320, 160
  local CURSOR_CODE = 0xED
  -- Theme.cursorHollow (src/ui/Theme.lua:12, charmap.asm $EC) -- the same
  -- hollow-arrow marker the engine's own party/list reordering leaves on
  -- a picked-up row (src/ui/ListMenu.lua, src/ui/PartyMenu.lua), reused
  -- here for the same purpose on a picked-up move.
  local SWAP_MARKER_CODE = 0xEC
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
  local MENU_LABELS = { FIGHT = "FIGHT", BAG = "BAG", PKMN = "PKMN", RUN = "RUN" }

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

  -- Row geometry, tiles. ROW_H=5 (40px) stays fixed -- widening it to fit
  -- a taller GUI box would eat into the bottom area's own already-tight
  -- budget (see BOTTOM_H below), so the GUI box's real HP bar + gender
  -- symbol land within the SAME 2-line, 24px-interior box the plain-text
  -- version used, not a taller one.
  local ROW_H = 5
  -- GUI_TW=15 (interior (15-2)*8=104px) is sized for line 2: the 48px HP
  -- bar plus, for the player's own box only, "NNN/NNN" beside it --
  -- 48+6(gap)+40(text)=94px, needing real margin past GUI_TW=13's 88px.
  local GUI_TW = 15
  local GUI_GAP = 1
  -- How many tiles lower the SECOND box of a pair sits, stacked
  -- DIRECTLY under the first at the SAME tx -- not side by side, per
  -- the user's own reference image (both boxes flush against the row's
  -- left/right edge, one under the other, no horizontal offset at all).
  -- Set to GUI_BOX_H*BOX_SCALE (defined below) so the two boxes sit
  -- flush against each other with no gap and no overlap; kept as its
  -- own named constant since it's computed from values declared later
  -- in the file. GUI_BOX_H=5, BOX_SCALE=0.47 -> rendered height 18.8px,
  -- so 2 stacked = 37.6px, safely under the row's own 40px (ROW_H*8) --
  -- BOX_SCALE was 0.6 briefly, which rendered a stacked pair at 48px,
  -- 8px TALLER than the row, and visibly overlapped the FIGHT/BAG/PKMN/
  -- RUN box below it live.
  local GUI_STACK_TY = 2.35
  -- Sprite-zone geometry is UNCHANGED from the original two-column
  -- layout -- explicitly reverted after a prior pass "fixed" this gap
  -- without being asked to, which moved every sprite's position as a
  -- side effect. The dead strip between the (now single, stacked) GUI
  -- column and the sprite zone is left as-is on purpose: only the GUI
  -- boxes were asked to move, nothing about the sprites.
  local SPRITE_ZONE_TW = VW / 8 - (GUI_TW * 2 + GUI_GAP) -- 9
  -- px square a mon's sprite is scaled to fit inside, bottom-anchored in
  -- its row.
  local SPRITE_BOX = 34

  local BOTTOM_Y = ROW_H * 2
  -- 2/3 of the original full-row height (VH/8-BOTTOM_Y = 10 tiles at the
  -- current VH=160), floored to stay an integer tile count, plus a
  -- standalone +0.5 tile (4px) bump. Font.drawBox's own border math
  -- (Font.lua:544-558) places the bottom border tile at (th-1)*8, which
  -- lines up exactly with the fill's own bottom edge (th*8) for ANY real
  -- th, not just integers -- fractional th is fine for a box that isn't
  -- edge-aligning against a SEPARATE element (unlike the stacked-GUI-box
  -- case elsewhere in this file, where that alignment does matter). Only
  -- the border's own bottom edge moves: self.fTextY/eTextY are computed
  -- from fy/ey (the box's TOP), never from this constant, so growing it
  -- pushes the box's bottom out without moving the text at all.
  local BOTTOM_H = math.floor((VH / 8 - BOTTOM_Y) * 2 / 3) + 0.5
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

  local function fitScale(winW, winH)
    return math.max(1, math.floor(math.min((winW or 0) / VW, (winH or 0) / VH)))
  end

  local function fitOrigin(winW, winH, scale)
    return math.floor((winW - VW * scale) / 2), math.floor((winH - VH * scale) / 2)
  end

  local function displayName(mon)
    return mon.nickname or mon.name or mon.species or "???"
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
    local line = ""
    local row = 0
    for word in tostring(text or ""):gmatch("%S+") do
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

  -- Floats a mon's sprite freely inside a zone (tx,ty,tw,th) -- no
  -- border of its own. anchorRight=false anchors it to the zone's own
  -- left edge, true to its right edge -- both enemy sprites and both
  -- player sprites share the SAME zone per row (see drawContent), so
  -- this is what lets the two sprites in a row sit close together
  -- (a few px apart) instead of pinned to opposite ends of the canvas.
  -- sizeMul: a plain multiplier on SPRITE_BOX (1.0 = default; the tuned
  -- default may override it via self.layout) -- the sprite still scales
  -- to fit that box uniformly by its own aspect ratio, never distorted.
  -- Returns the sprite's own bottom-center screen position (post-draw),
  -- or nil if nothing was drawn -- callers that need to know WHERE a
  -- battler's sprite actually landed this frame (move animations, see
  -- Screen:startMoveAnim) read this instead of re-deriving the same
  -- tx/ty/scale math a second time.
  local function drawSprite(tx, ty, tw, th, battler, spriteField, data, anchorRight, sizeMul)
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
    -- Animated art arrives through a SECOND seam: pokemon.sprite above picks
    -- the file, battle.mon_pic swaps the current frame into the image on its
    -- way to the screen -- which is why a sprite mod's animated sets showed
    -- here as a still first frame. An animator keys its clock off the battler
    -- it is handed and advances on its own, so raising this once per draw is
    -- the whole of it; there is no tick to run here.
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
      }
      local ok, swapped = pcall(Runtime.call, "battle.mon_pic",
        function(value) return value end, img, pctx)
      if ok and swapped then img = swapped end
    end
    local iw, ih = img:getDimensions()
    local scale = (SPRITE_BOX * (sizeMul or 1)) / math.max(iw, ih)
    local dw, dh = iw * scale, ih * scale
    local slotX, slotY, slotW, slotH = tx * 8, ty * 8, tw * 8, th * 8
    local dx = anchorRight and (slotX + slotW - dw) or slotX
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, dx, slotY + slotH - dh, 0, scale, scale)
    return dx + dw / 2, slotY + slotH
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

  -- Font.drawBox's own side-border loop (Font.lua:555-558) is
  -- `for j = 1, th - 2 do`, which Lua's numeric for truncates to the
  -- last INTEGER <= th-2 -- fine for an integer th, but BOTTOM_H is now
  -- a fractional tile count (+0.5 for a 4px height bump), so that loop
  -- stops half a tile short of the bottom corner and leaves a visible
  -- gap in the left/right border lines right above it (screenshot-
  -- reported: the frame broke). This is the same box, drawn the same
  -- way, except the side-tile count is math.ceil'd instead of
  -- truncated -- the last tile then overlaps the bottom corner by a
  -- few px instead of leaving a gap, which is invisible for a solid
  -- straight-line border glyph.
  local function drawBoxNoGap(tx, ty, tw, th, fill)
    local r, g, b, a = love.graphics.getColor()
    if type(fill) == "table" and fill[1] and fill[2] and fill[3] then
      love.graphics.setColor(fill[1] / 255, fill[2] / 255, fill[3] / 255, 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
    love.graphics.setColor(r, g, b, a)
    local B = Font.BORDER
    Font.drawCode(B.tl, tx * 8, ty * 8)
    Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
    Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
    Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
    for i = 1, tw - 2 do
      Font.drawCode(B.h, (tx + i) * 8, ty * 8)
      Font.drawCode(B.h, (tx + i) * 8, (ty + th - 1) * 8)
    end
    for j = 1, math.ceil(th - 2) do
      Font.drawCode(B.v, tx * 8, (ty + j) * 8)
      Font.drawCode(B.v, (tx + tw - 1) * 8, (ty + j) * 8)
    end
  end

  -- The HP fill only -- no black frame, no white backing rectangle --
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

  -- Drawn box height, tiles, BEFORE the whole-box 60% shrink below --
  -- tall enough for 3 real lines (name, bar, player's own numeric HP on
  -- its own line under the bar, no overlap) at the line spacing used
  -- inside. The final on-screen size is BOX_SCALE of this.
  local GUI_BOX_H = 5
  -- Shrinks the ENTIRE box -- border, name, bar, numeric HP, all of it
  -- -- to 60% size, anchored at the box's own top-left tile corner (that
  -- point stays fixed; everything else scales toward it) via a plain
  -- graphics transform around the whole draw, rather than recomputing
  -- every dimension by hand.
  local BOX_SCALE = 0.47

  -- The compact bordered name/level/gender/HP readout.
  -- Font.drawBox's border glyphs occupy a full 8px tile at each edge
  -- (Font.lua:544-558), so the safe interior starts one full tile in
  -- from (tx,ty), not a few px past the box's outer edge -- confirmed
  -- live after an earlier pass's text visibly struck through both
  -- borders by assuming a thin rule instead.
  --
  -- A fainted battler draws NOTHING here at all -- not even the border
  -- -- rather than a box that still stands there reading FAINTED. That
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
  -- Line 1: name (shrunk to fit -- see drawScaledText/fitName) + "LvNN"
  -- + gender. Line 2: the real HP bar, unlabeled, 3px thick, stretched
  -- to nearly the box's own width -- and for the enemy, that's the
  -- WHOLE readout: the numeric current/max is deliberately withheld
  -- (showNumeric=false), matching every real Pokemon game's own enemy
  -- HUD. Line 3 (player only, showNumeric=true): the numeric HP on its
  -- OWN line under the bar, not overlaid on it.
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
  local function drawGuiBox(tx, ty, tw, th, battler, data, showNumeric, anchorRight, sizeMul, shownHp)
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

    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(tx, ty, tw, GUI_BOX_H)
    love.graphics.setColor(0, 0, 0, 1)
    local textX, textY = (tx + 1) * 8 + 2, (ty + 1) * 8 + 1
    local interiorW = (tw - 2) * 8 - 2

    local NAME_SCALE = 0.75
    local suffix = string.format(" Lv%d%s", mon.level or 0, GENDER_SYMBOL[mon.gender] or "")
    local name = fitName(displayName(mon), interiorW / NAME_SCALE, Font.width(suffix))
    drawScaledText(name .. suffix, textX, textY, NAME_SCALE)

    local barW = interiorW - 2
    local barH = 3
    local barY = textY + 9
    local palettes = data and data.gen2Palettes
    if palettes then
      drawHpFill(palettes, shownHp, mon.maxHp, textX, barY, barW, barH)
    end
    if showNumeric then
      local label = string.format("%d/%d", shownHp, mon.maxHp or 0)
      drawScaledText(label, textX, barY + barH + 3, 0.75)
    end

    love.graphics.pop()
  end

  function Screen.new(game, world, payload, combat, gameData, battle, g9dex)
    local self = setmetatable({}, Screen)
    self.game = game
    self.world = world
    self.combat = combat
    self.data = gameData
    -- The real native Battle instance and the g9-battle-engine-beta mod
    -- reference -- both required for every turn's resolution now (see
    -- Combat.resolveTurn). Constructed by pushDoubleBattleScreen, not
    -- here, since building one needs game.save/game.data before this
    -- constructor's own arguments are assembled.
    self.battle = battle
    self.g9dex = g9dex
    -- Looped, not hardcoded to exactly 2 -- combat.lua's own logic
    -- (isAlive/chooseAiAction/orderActions/sideDefeated/etc) already
    -- just iterates these arrays with ipairs, so rendering (drawContent,
    -- below) is written the same N-agnostic way rather than assuming a
    -- fixed pair.
    self.enemyBattlers = {}
    for i, mon in ipairs(payload.enemies) do
      self.enemyBattlers[i] = combat.newBattler(mon, "enemy")
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
    -- The turn's events, whole tables, NOT just their .text -- see
    -- Screen:advanceResolving for why the rest of each event now matters.
    self.pendingEvents = {}
    -- The chasing HP the HUD actually draws, keyed by the real mon table
    -- (see Screen:snapshotHp for why the mon and not the battler and not
    -- the side). Screen:shownHpOf reads it; Screen:stepHpAnim walks it.
    self.shownHp = {}
    self.hpAnim = nil
    -- Read fresh from this mod's own active layout preset (layouts.lua)
    -- rather than baked in -- see that file's own header for the preset
    -- file shape/naming and how the active one is chosen.
    local activeLayout = mod.exports.getActiveLayoutData and mod.exports.getActiveLayoutData()
    self.layout = (activeLayout and activeLayout.layout) or {}
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
    -- Move-animation state: spriteAnchor is filled in every drawContent
    -- pass (see drawSprite's own return value) with each battler's real
    -- on-screen bottom-center this frame -- Screen:startMoveAnim reads
    -- it to anchor an animation at wherever a sprite ACTUALLY is, not a
    -- guessed position. moveAnim is nil when nothing is playing.
    self.spriteAnchor = {}
    self.moveAnim = nil
    self:installEventProbe()
    self:beginTurn()
    return self
  end

  ------------------------------------------------------------------
  -- TURN PACING -- the display lags the resolution
  --
  -- The engine mod owns turn resolution and resolves the WHOLE turn in
  -- one call (Combat.resolveTurn -> g9-battle-engine-beta's
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
  -- (Battle.lua) and g9-battle-engine-beta (its combat/ and abilities/
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
        -- Battle.lua nor g9-battle-engine-beta's combat/ uses coroutines
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
  function Screen:exit()
    self:finishBattleExit()
  end

  -- Returns the EFFECTIVE tx,ty for a layout element `id`: the tuned
  -- override baked into self.layout (Screen.new) if one exists for it,
  -- otherwise the layout's own computed default.
  function Screen:pos(id, defaultTx, defaultTy)
    local saved = self.layout[id]
    if saved and saved.tx then return saved.tx, saved.ty end
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
    self.slotPtr = 1
    if #self.turnSlots == 0 then
      -- Both player battlers already down with no switch made -- still
      -- let the enemy side act rather than freeze the battle.
      self:beginResolving()
      return
    end
    self:enterActionMenu()
  end

  function Screen:enterActionMenu()
    self.actingSlotIdx = self.turnSlots[self.slotPtr]
    self.menuCursor = "FIGHT"
    self.message = nil
    self.phase = "actionMenu"
  end

  -- CUSTOM ("Gimmicks", per this mod's own settings.lua default) opens a
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
    -- battle_forms publishes a DOCUMENTED api (src/formapi.lua): gimmicks(),
    -- arm(), armed(). It does NOT publish transforms/armState -- those are
    -- its internal dep names, and asking for them found nil, which is why this
    -- menu answered "No Gimmicks available." for every mon regardless of what
    -- the trainer was carrying. Shimmed to the real surface rather than the
    -- other way round: formapi.lua's header states plainly that the internals
    -- are not the peer contract.
    if not (api and type(api.gimmicks) == "function" and type(api.arm) == "function") then
      self.message = "No Gimmicks available."
      self.phase = "actionMenu"
      return
    end
    -- gimmicks(battle) already applies this mod's own eligibility AND the
    -- barred-species rule, and returns { id, label, available } rows.
    local okList, rows = pcall(api.gimmicks, self.battle)
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
      self.message = "Already used a Gimmick this battle."
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
      self.message = "No Gimmick available right now."
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
      -- no side effect, same as moveSelect's own B.
      self.gimmickCandidates = nil
      self.gimmickArmState = nil
      self.phase = "actionMenu"
      return
    end
    if input:wasPressed("a") then
      local chosen = self.gimmickCandidates[self.gimmickCursor]
      -- Armed only -- the real transformation happens later, at
      -- battle.turn_started (Screen:advanceResolving), the same timing
      -- battle_forms's own resolve.onTurnStarted always used.
      local ok, armed = pcall(function() return self.gimmickArmState:toggle(chosen.id) end)
      self.message = (ok and armed) and (chosen.label .. " armed!")
        or "That Gimmick couldn't be armed."
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

  -- Moves self.menuCursor for GRID mode -- either the plain 2x2 (real
  -- row/col toggle, GRID2_ROWS) or, when a custom button is set, the
  -- 5-cell cross (the two explicit CROSS_*_CYCLE orders, module header
  -- explains why coordinate math can't be used there). Same true/false
  -- return contract as moveMenuCursorList.
  function Screen:moveMenuCursorGrid(input)
    if self.customButtonLabel then
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
    local row, col
    for r = 1, 2 do
      for c = 1, 2 do
        if GRID2_ROWS[r][c] == self.menuCursor then row, col = r, c end
      end
    end
    row, col = row or 1, col or 1
    if input:wasPressed("left") or input:wasPressed("right") then
      col = col == 1 and 2 or 1
    elseif input:wasPressed("up") or input:wasPressed("down") then
      row = row == 1 and 2 or 1
    else
      return false
    end
    self.menuCursor = GRID2_ROWS[row][col]
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
        table.remove(self.queuedActions)
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

  -- E's own real interior width in px, computed from E_TW (not
  -- guessed): border glyphs eat one full tile per edge (Font.lua's own
  -- convention, see this file's header), so the interior spans
  -- (E_TW-2)*8=80px; eTextX already sits 2px into that (its own formula,
  -- Screen:drawContent), leaving ~78px out to the right border. FIGHT/
  -- BAG/PKMN/RUN are fixed 8px/glyph text (Font.lua), so a label's
  -- pixel width is just #chars*8 -- confirmed by direct measurement,
  -- not assumed, after a flat 44px column-gap guess broke "PKMN" out of
  -- the box border live (screenshot-reported).
  local E_INTERIOR_W = 78

  function Screen:drawActionMenuEList()
    for i, id in ipairs(self.menuOrder) do
      local label = (id == "CUSTOM")
        and fitName(self.customButtonLabel, E_INTERIOR_W - 10, 0)
        or MENU_LABELS[id]
      Font.draw(label, self.eTextX + 10, self.eTextY + (i - 1) * 11)
    end
    local cursorRow = 1
    for i, id in ipairs(self.menuOrder) do if id == self.menuCursor then cursorRow = i break end end
    Font.drawCode(CURSOR_CODE, self.eTextX, self.eTextY + (cursorRow - 1) * 11)
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
  -- visible gap) and B=34 (comfortably fits "Gimmicks", 8 chars = 64px
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
  -- most of "Gimmicks"). 4px, not 2 or 10: needs to clear the smaller
  -- scaled glyph without going negative off col1's own left edge (col1
  -- sits only 2px into the interior, eTextX-2 is the true border).
  local CROSS_CURSOR_OFFSET = 4

  -- Explicit numeric bounds, NOT ipairs -- CROSS_SLOTS rows have real
  -- nil holes ({"FIGHT", nil, "PKMN"}), and ipairs stops dead at the
  -- first nil, so it would never reach the third column at all.
  function Screen:drawActionMenuEGrid()
    if self.customButtonLabel then
      for r = 1, 3 do
        for c = 1, 3 do
          local id = CROSS_SLOTS[r][c]
          if id then
            local label = (id == "CUSTOM")
              and fitName(self.customButtonLabel, CROSS_CENTER_BUDGET / CROSS_TEXT_SCALE, 0)
              or MENU_LABELS[id]
            local slotX = self.eTextX + CROSS_SLOT_X[c]
            local x = slotX + (CROSS_SLOT_W[c] - Font.width(label) * CROSS_TEXT_SCALE) / 2
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
    for r = 1, 2 do
      for c = 1, 2 do
        local id = GRID2_ROWS[r][c]
        local label = MENU_LABELS[id]
        local slotX = self.eTextX + GRID_MARGIN_2 + (c - 1) * GRID_SLOT_2
        local x = slotX + (GRID_SLOT_2 - Font.width(label) * GRID_TEXT_SCALE_2) / 2
        local y = self.eTextY + GRID_Y_OFFSET + (r - 1) * GRID_ROW_GAP_2
        drawScaledText(label, x, y, GRID_TEXT_SCALE_2)
        if id == self.menuCursor then
          Font.drawCode(CURSOR_CODE, x - GRID_CURSOR_OFFSET_2, y)
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
    Screens.push(self.game, "Gen2PackMenu", {
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
    if not (def and def.pocket == "BALL") then
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

  -- Thrown at whichever single enemy is still alive -- catchAllowed
  -- already guarantees at most one is. See catch.lua's own header for
  -- the full scope (no PC box yet). Not yet decremented from the bag --
  -- save's real item-count shape wasn't confirmed against this session's
  -- own research, and writing a guessed shape risks corrupting the save
  -- outright, so this is an explicit, stated gap rather than a silent
  -- guess. Resolves immediately (real Gen 2 never queues a ball throw
  -- into turn order either); a miss still consumes this slot's action
  -- for the turn, the same as a move would.
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
    -- Real native catch formula (src/battle/gen2/Catching.lua), same
    -- options shape g2-Battle-Scene's own (now-dropped) catch.lua always
    -- built. Passing a real `battle` here is the one upgrade native
    -- gives us: Catching.attempt calls battle:caught(mon) itself on a
    -- successful catch (Transform reload, the battle.catch_exp hook) --
    -- confirmed real, gen2/Catching.lua:380-382 -- which a battle-free
    -- caller never got.
    local def = self.data.pokemon and self.data.pokemon[target.mon.species]
    local caught, rate = Catching.attempt({
      ball = ballId or "POKE_BALL",
      mon = target.mon,
      def = def,
      hp = target.mon.hp,
      maxHp = target.mon.maxHp,
      catchRate = def and def.catchRate,
      status = target.mon.status,
      battle = self.battle,
      random = self.battle.random,
    })
    local name = target.mon.nickname or target.mon.name or target.mon.species
    if not caught then
      self.message = name .. " broke free! (rate " .. tostring(rate) .. "/255)"
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
      self.overMessage = "Gotcha! " .. name .. " was caught!"
    else
      -- A full party sends the catch to the CURRENT BOX, the same as
      -- `.SendToPC` / `predef SendMonIntoBox` (item_effects.asm:548-550, 604)
      -- and the same as native's own pushCaught
      -- (src/ui/gen2/BattleState.lua:2882-2900).
      --
      -- This used to say "no PC yet" and then drop the mon on the floor: the
      -- message claimed a catch, the battle recorded `outcome = "caught"`,
      -- and nothing was ever written anywhere.  A player who caught something
      -- with six in the party simply lost it.
      --
      -- Inserted at the HEAD, not appended, because SendMonIntoBox's species
      -- loop cascades every existing entry one slot down (move_mon.asm:954-965)
      -- so the catch lands in slot 1.  Boxes.deposit is deliberately NOT used:
      -- that is the PC's own party-to-box move and carries the last-healthy-mon
      -- and mail refusals, which have nothing to do with a capture.
      local okBox = pcall(function()
        local Boxes = require("src.core.gen2.Boxes")
        local save = self.game.save
        local index = math.max(1, math.min(Boxes.NUM_BOXES,
          math.floor(tonumber(save.currentBox) or 1)))
        local box = Boxes.box(save, index)
        table.insert(box, 1, target.mon)
        -- SendMonIntoBox refills the boxed slot's PP before it closes SRAM
        -- (move_mon.asm:1062-1063).
        if type(Boxes.enterBox) == "function" then Boxes.enterBox(target.mon) end
        self.overMessage = "Gotcha! " .. name .. " was caught! It was sent to "
          .. (Boxes.name and Boxes.name(save, index) or "the PC") .. "."
      end)
      if not okBox then
        -- Said honestly rather than claiming a catch that did not happen.
        self.overMessage = "Gotcha! " .. name
          .. " was caught! ...but the PC could not be reached."
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
    Screens.push(self.game, "Gen2PartyMenu", {
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
    local usable = self.combat.usableMoves(battler, self.data)
    if #usable == 0 then
      -- Out of PP everywhere -- an explicit Phase 2 gap (no real
      -- Struggle yet): this slot simply can't act this turn.
      self:advanceSlotOrResolve()
      return
    end
    self.usableMovesCache = usable
    self.moveCursor = 1
    self.moveSwapIndex = nil
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

  function Screen:updateMoveSelect(input)
    local count = #self.usableMovesCache
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
      local cursorEntry = self.usableMovesCache[self.moveCursor]
      if cursorEntry then
        if self.moveSwapIndex then
          if self.moveSwapIndex ~= cursorEntry.index then
            local battler = self.playerBattlers[self.actingSlotIdx]
            local moves = battler.mon.moves
            moves[self.moveSwapIndex], moves[cursorEntry.index] =
              moves[cursorEntry.index], moves[self.moveSwapIndex]
            self.usableMovesCache = self.combat.usableMoves(battler, self.data)
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
      local picked = self.usableMovesCache[self.moveCursor]
      local aliveEnemies = {}
      for _, e in ipairs(self.enemyBattlers) do
        if self.combat.isAlive(e) then aliveEnemies[#aliveEnemies + 1] = e end
      end
      if #aliveEnemies > 1 then
        self.pendingPick = picked
        self.targetCandidates = aliveEnemies
        self.targetCursor = 1
        self.phase = "targetSelect"
      elseif #aliveEnemies == 1 then
        self:queueAction(picked, aliveEnemies[1])
        self:advanceSlotOrResolve()
      else
        -- Both enemies already down -- shouldn't reach here (the battle
        -- would already have ended), kept defensive rather than assumed.
        self:beginResolving()
      end
    end
  end

  function Screen:drawMoveSelect()
    -- No "<name>'s move:" header -- the move list starts right at
    -- fTextY instead of fTextY+9, using the row that line used to sit
    -- on rather than leaving it blank.
    for i, entry in ipairs(self.usableMovesCache) do
      local label = string.format("%-10s PP %d/%d",
        entry.def.name or entry.def.id, entry.slot.pp, entry.slot.maxPp or entry.slot.pp)
      Font.draw(label, self.fTextX + 12, self.fTextY + (i - 1) * 9)
      if self.moveSwapIndex == entry.index then
        Font.drawCode(SWAP_MARKER_CODE, self.fTextX + 6, self.fTextY + (i - 1) * 9)
      end
    end
    Font.drawCode(CURSOR_CODE, self.fTextX, self.fTextY + (self.moveCursor - 1) * 9)
  end

  ------------------------------------------------------------------
  -- TARGET SELECT (only entered when 2 enemies are alive)
  ------------------------------------------------------------------
  function Screen:updateTargetSelect(input)
    local count = #self.targetCandidates
    if input:wasPressed("up") then
      self.targetCursor = self.targetCursor > 1 and self.targetCursor - 1 or count
    elseif input:wasPressed("down") then
      self.targetCursor = self.targetCursor < count and self.targetCursor + 1 or 1
    elseif input:wasPressed("b") then
      -- Back to move selection -- usableMovesCache/moveCursor are still
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

  function Screen:drawTargetSelect()
    Font.draw("Choose a target:", self.fTextX, self.fTextY)
    for i, battler in ipairs(self.targetCandidates) do
      local mon = battler.mon
      local label = string.format("%-10s HP %d/%d", displayName(mon), mon.hp or 0, mon.maxHp or 0)
      Font.draw(label, self.fTextX + 12, self.fTextY + 9 + (i - 1) * 9)
    end
    Font.drawCode(CURSOR_CODE, self.fTextX, self.fTextY + 9 + (self.targetCursor - 1) * 9)
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
  function Screen:startMoveAnim(def, actor, target)
    local animsData = self.data.gen2BattleAnims
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
    local targetAnchor = self.spriteAnchor[target]
    if targetAnchor then
      local vdx = vanillaTargetAnchor.x - vanillaActorAnchor.x
      local vdy = vanillaTargetAnchor.y - vanillaActorAnchor.y
      if vdx ~= 0 then scaleX = (targetAnchor.x - anchor.x) / vdx end
      if vdy ~= 0 then scaleY = (targetAnchor.y - anchor.y) / vdy end
    end
    self.animView = self.animView or BattleAnimView.new(animsData, self.data.gen2Palettes)
    local runner = AnimRunner.new({
      data = animsData,
      constants = self.data.gen2Constants,
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

  function Screen:beginResolving()
    -- Switches always resolve before any move (real Gen 2 rule -- not a
    -- speed/priority comparison at all), so they're pulled out of the
    -- queue and applied first, one at a time, in Screen:advanceResolving
    -- below -- not part of g9-battle-engine-beta's resolveTurnActions
    -- contract, which is moves only.
    local moveActions, switchActions = {}, {}
    for _, a in ipairs(self.queuedActions) do
      if a.kind == "switch" then switchActions[#switchActions + 1] = a
      else moveActions[#moveActions + 1] = a end
    end
    for _, enemy in ipairs(self.enemyBattlers) do
      if self.combat.isAlive(enemy) then
        local ai = self.combat.chooseAiAction(enemy, self.playerBattlers, self.data)
        if ai then moveActions[#moveActions + 1] = ai end
      end
    end
    self.switchQueue = switchActions
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
    if #self.switchQueue > 0 then
      -- The newly-sent-out mon simply has no action queued of its own
      -- this turn, so it never gets to act again until next turn.
      local action = table.remove(self.switchQueue, 1)
      self.playerBattlers[action.actorSlot] = self.combat.newBattler(action.mon, "player")
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
      Runtime.emit("battle.turn_started", { battle = self.battle })
      -- The WHOLE remaining turn's moves resolve in ONE call now --
      -- g9-battle-engine-beta's own resolveTurnActions derives priority/
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
      -- awardExperience splits across battle.participants -- a table
      -- keyed by PARTY INDEX, populated by native's own switch-in flow
      -- (Battle.new's constructor seeds just self.playerIndex; nothing
      -- else ever adds to it here, since this mod drives its own roster
      -- rather than native's switchIn). Rebuilt from the real roster
      -- every time, right before awarding, so EXP actually splits across
      -- whichever of OUR playerBattlers fought this battle rather than
      -- always crediting whatever party slot Battle.new happened to pick
      -- as its own single "primary" mon.
      if next(self.enemyBattlers) then
        self.battle.participants = {}
        for _, p in ipairs(self.playerBattlers) do
          if self.combat.isAlive(p) then
            for index, mon in ipairs(self.game.save.party) do
              if mon == p.mon then
                self.battle.participants[index] = true
                break
              end
            end
          end
        end
      end
      for _, enemy in ipairs(self.enemyBattlers) do
        if enemy.mon and (enemy.mon.hp or 0) <= 0 and not enemy.fainted then
          enemy.fainted = true
          self.battle:awardExperience(enemy.mon)
        end
      end
      for _, e in ipairs(self.battle:takeEvents()) do events[#events + 1] = e end
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
    self:finishTurn()
  end

  function Screen:finishTurn()
    local enemiesDown = self.combat.sideDefeated(self.enemyBattlers)
    local playersDown = self.combat.sideDefeated(self.playerBattlers)
    if enemiesDown or playersDown then
      self.phase = "over"
      if enemiesDown and playersDown then
        self.overMessage = "Both sides down -- draw!"
        self.outcome = "draw"
      elseif enemiesDown then
        self.overMessage = "You won the battle!"
        self.outcome = "win"
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
  --   * catch  -> screen:throwBall(ballId), which runs the real native
  --     formula (Catching.attempt calls battle:caught(mon) itself) and
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
    -- Independent of input/phase -- a move animation keeps stepping
    -- underneath the message text the same way it does in every real
    -- Pokemon battle. Runner:step() returns false once the animation
    -- has genuinely finished (its own header note).
    if self.moveAnim then
      if not self.moveAnim.runner:step() then self.moveAnim = nil end
    end

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

    if self.phase == "actionMenu" then self:updateActionMenu(input)
    elseif self.phase == "moveSelect" then self:updateMoveSelect(input)
    elseif self.phase == "targetSelect" then self:updateTargetSelect(input)
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

  function Screen:drawContent()
    -- Every position below goes through self:pos(id, defaultTx,
    -- defaultTy): a tuned override baked into self.layout (Screen.new)
    -- if one exists for that id, otherwise the same computed default
    -- this layout has always used. Looped over however many battlers are
    -- actually on each side (the real wild flow always hands over 2 per
    -- side; the loop is just written N-agnostic, matching combat.lua's
    -- own logic): GUI boxes stack (i-1)*GUI_STACK_TY tiles lower per
    -- index; sprites spread evenly left to right across their zone.
    local enemyZoneTx = GUI_TW * 2 + GUI_GAP
    for i, battler in ipairs(self.enemyBattlers) do
      local gx, gy = self:pos("enemyGui" .. i, 0, (i - 1) * GUI_STACK_TY)
      local gs = self:sizeMul("enemyGui" .. i)
      drawGuiBox(gx, gy, GUI_TW, ROW_H, battler, self.data, false, false, gs,
        self:shownHpOf(battler.mon))

      local slotW = SPRITE_ZONE_TW / #self.enemyBattlers
      local sx, sy = self:pos("enemySprite" .. i, enemyZoneTx + (i - 1) * slotW, 0)
      local ss = self:sizeMul("enemySprite" .. i)
      local ax, ay = drawSprite(sx, sy, slotW, ROW_H, battler, "spriteFront", self.data, false, ss)
      if ax then self.spriteAnchor[battler] = { x = ax, y = ay } end
    end

    for i, battler in ipairs(self.playerBattlers) do
      local slotW = SPRITE_ZONE_TW / #self.playerBattlers
      local sx, sy = self:pos("playerSprite" .. i, (i - 1) * slotW, ROW_H)
      local ss = self:sizeMul("playerSprite" .. i)
      local ax, ay = drawSprite(sx, sy, slotW, ROW_H, battler, "spriteBack", self.data, false, ss)
      if ax then self.spriteAnchor[battler] = { x = ax, y = ay } end

      local gx, gy = self:pos("playerGui" .. i, GUI_RIGHT_TX, ROW_H + (i - 1) * GUI_STACK_TY)
      local gs = self:sizeMul("playerGui" .. i)
      drawGuiBox(gx, gy, GUI_TW, ROW_H, battler, self.data, true, true, gs,
        self:shownHpOf(battler.mon))
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

    -- Bottom: F (message/move/target, wide) beside E (FIGHT/BAG/PKMN/RUN,
    -- narrow) -- vanilla's own text-box-plus-menu split, not one shared
    -- full-width box. Both go through Screen:withScale to apply their
    -- tuned size (see its own header for why: border+text drawn together
    -- at their normal INTEGER default size, F_TW/E_TW/BOTTOM_H, then the
    -- whole finished result scaled as one unit -- passing a scaled tw/th
    -- straight into Font.drawBox instead visibly broke the frame's own
    -- tiling live). self.fTextX/fTextY/eTextX/eTextY stay the box's own
    -- UNSCALED default text origin -- correct because they're read only
    -- from INSIDE that same withScale block below, where the transform
    -- itself does the scaling; fChars is the fixed default (F's own tile
    -- capacity doesn't change, only its on-screen size does).
    local fx, fy = self:pos("fBox", 0, BOTTOM_Y)
    local ex, ey = self:pos("eBox", F_TW, BOTTOM_Y)
    self.fTextX, self.fTextY = (fx + 1) * 8 + 2, (fy + 1) * 8 + 2
    self.eTextX, self.eTextY = (ex + 1) * 8 + 2, (ey + 1) * 8 + 2
    self.fChars = F_TW - 4

    self:withScale("fBox", fx, fy, function()
      love.graphics.setColor(1, 1, 1, 1)
      drawBoxNoGap(fx, fy, F_TW, BOTTOM_H)
      love.graphics.setColor(0, 0, 0, 1)
      if self.phase == "actionMenu" then
        self:drawActionMenuF()
      elseif self.phase == "moveSelect" then
        self:drawMoveSelect()
      elseif self.phase == "targetSelect" then
        self:drawTargetSelect()
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

    self:withScale("eBox", ex, ey, function()
      love.graphics.setColor(1, 1, 1, 1)
      drawBoxNoGap(ex, ey, E_TW, BOTTOM_H)
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

  function Screen:draw()
    -- Fallback path only, see this file's earlier header note: only
    -- reached if something is ever stacked on top of this screen.
    local w, h = love.graphics.getDimensions()
    local scale = fitScale(w, h)
    local ox, oy = fitOrigin(w, h, scale)
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
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
    love.graphics.scale(scale, scale)
    self:drawContent()
    love.graphics.pop()
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
  -- before this fix, including this mod's own wildEncounter multi-enemy
  -- case) or the REAL trainer definition table
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
    return Battle.new(opts)
  end

  mod.exports.pushDoubleBattleScreen = function(game, world, data)
    local combat = mod.exports.combat
    local g9dex = mod:find("g9-battle-engine-beta")
    assert(g9dex and g9dex.exports and g9dex.exports.resolveTurnActions,
      "g9-Battle-Scene: g9-battle-engine-beta not loaded or missing resolveTurnActions")
    local battle = buildBattle(game, data)
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
  --   screen:throwBall("POKE_BALL")   -- real native Catching.attempt;
  --       on a catch it files the mon, sets outcome="caught" and moves
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

  mod.log:info("g9_Battle_Scene: battle_screen installed (prompt API: askBattleChoice, battleChoiceActive, cancelBattleChoice)")
end
