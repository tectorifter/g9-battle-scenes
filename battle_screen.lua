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
  local function drawGuiBox(tx, ty, tw, th, battler, data, showNumeric, anchorRight, sizeMul)
    local mon = battler and battler.mon
    if not mon or battler.fainted or (mon.hp or 0) <= 0 then return end

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
      drawHpFill(palettes, mon.hp, mon.maxHp, textX, barY, barW, barH)
    end
    if showNumeric then
      local label = string.format("%d/%d", mon.hp or 0, mon.maxHp or 0)
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
    self.pendingMessages = {}
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
    self:beginTurn()
    return self
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
      self.overMessage = "Gotcha! " .. name .. " was caught! Party's full -- no PC yet."
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
    self.pendingMessages = {}
    self.phase = "resolving"
    self:advanceResolving()
  end

  function Screen:advanceResolving()
    if #self.pendingMessages > 0 then
      self.currentMessage = table.remove(self.pendingMessages, 1)
      return
    end
    if #self.switchQueue > 0 then
      -- The newly-sent-out mon simply has no action queued of its own
      -- this turn, so it never gets to act again until next turn.
      local action = table.remove(self.switchQueue, 1)
      self.playerBattlers[action.actorSlot] = self.combat.newBattler(action.mon, "player")
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
      -- Deferred, not carried over from g2-Battle-Scene: the WATER_GUN-
      -- only move animation trigger. That gated on resolveAction's own
      -- per-action success/failure signal, which collapsing to one
      -- per-turn call no longer exposes per-action -- real future work,
      -- not silently dropped without saying so.
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
      for _, event in ipairs(events) do
        if event.text then self.pendingMessages[#self.pendingMessages + 1] = event.text end
      end
      if #self.pendingMessages > 0 then
        self.currentMessage = table.remove(self.pendingMessages, 1)
        return
      end
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

  function Screen:updateResolving(input)
    if input:wasPressed("a") or input:wasPressed("b") then
      self:advanceResolving()
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
    if not input then return end
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
    elseif self.phase == "resolving" then self:updateResolving(input)
    elseif self.phase == "over" then self:updateOver(input)
    -- "submenu": Gen2PackMenu/Gen2PartyMenu is on top of the stack and
    -- owns update() entirely (StateStack only updates its top state) --
    -- this branch is never actually reached while that's true, kept
    -- only so an unexpected extra frame here is a no-op, not an error.
    end
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
      drawGuiBox(gx, gy, GUI_TW, ROW_H, battler, self.data, false, false, gs)

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
      drawGuiBox(gx, gy, GUI_TW, ROW_H, battler, self.data, true, true, gs)
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
      if self.phase == "actionMenu" then self:drawActionMenuE() end
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

  mod.log:info("g9_Battle_Scene: battle_screen installed")
end
