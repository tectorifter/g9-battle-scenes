# g9-battle-scenes
modern battle layouts, doubles, triples, 4v1 boss fight

Runs on **both** generations:

- **Gen 2 (Gold/Silver)** -- the original home. Turn resolution calls
  `g9-battle-engine`; EXP/catch call the real native Gen 2 primitives.
  Unchanged by the Gen 1 work.
- **Gen 1 (Red/Blue/Yellow)** -- turn resolution calls the GAME'S OWN Gen 1
  engine (`BattleState:performMove` sequenced by `src.battle.TurnOrder`),
  because `g9-battle-engine` is a Gen 2 engine and cannot drive a Gen 1
  battle. EXP uses `src.pokemon.Growth` + `Experience.apply`; catch uses
  `src.battle.Catching.attempt`.

A generation backend (`native.lua`, loaded first by `main.lua`) detects the
running generation and hands the scene one shim for the handful of engine
surfaces it touches, so `battle_screen.lua` never branches on generation
itself.

## Gen 2 assets on a Gen 1 boot

A stock Red/Blue/Yellow boot carries no `data.gen2*` tables (the engine loads
them only for a Gold/Silver boot). When the live game data DOES carry them --
an engine that bundles Gold's data, or a content mod that merges a `data.gen2*`
registry -- the Gen 1 arm detects that at load and calls the whole Gen 2 asset
set into Gen 1:

- palette / menu-gfx / status / trainer / constants / anim tables, read from
  the same `data.gen2*` fields the Gen 2 arm reads;
- the real Gen 2 battle HUD (`src.ui.gen2.BattleHud`), so Gen 1 gets the cart's
  `$60-$78` tiles and a real exp bar back;
- the Gen 2 move-animation engine (`src.battle.gen2.AnimRunner` +
  `src.ui.gen2.BattleAnimView`);
- Gen 2 trainer art and its palette rows (player back-pic off
  `gen2MenuGfx.battleHud`, class front-pic off `gen2Trainers`/menu-gfx), so the
  intro pics are GBC-coloured rather than raw;
- authored Gen 2 status labels.

When no Gen 2 assets are present none of those modules are even loaded and
every path keeps its Gen 1 behaviour. Species battle pics cannot come from Gen
2 either way: `data.gen2Sprites` holds overworld/icon sheets, not the
`data.pokemon[species].spriteFront/spriteBack` battle art the scene draws.

## Gen 1 gaps (honest, per-feature)

- With no Gen 2 assets present: **move animations and the thrown-ball catch run
  on Gen 1's OWN native engine** (`src/battle/AnimPlayer.lua` — see the v2.1.2
  section); no exp bar (Gen 1 has no in-battle exp bar); trainer intro art draws
  raw.
- The BAG is a ball-only native `ListMenu` wired straight to the scene's own
  `throwBall` (Gen 1's native `BagMenu` throws through the native
  `BattleState`, not this scene's model).
- Switching uses the native `PartyMenu`.

IT'S STILL A WIP.

## Rendering: how the 960x540 canvas reaches the window

The scene draws ONE canvas -- 320x180 design field x3 (see `DS` in
`battle_screen.lua`). How it gets to the window is the one thing the
generations do differently, and both paths live in that file:

- **Gen 2** -- Game2's renderer resolves the scene through
  `drawsWidescreen`/`drawWidescreen` and blits the canvas window-filling.
  Unchanged.
- **Gen 1** -- `src/core/Game.lua` has no `drawWidescreen` path at all: it
  asks each state for the UI SURFACE it wants (`uiSize` ->
  `Renderer:setUISize`) and draws the state into it. The Screen therefore
  also implements the engine's own wide-battle contract
  (`isWideBattleLayout`/`uiSize`/`sgbPalettes`) plus `letterboxWhite` and
  `holdsUIAnchors`, so Gen 1 allocates the scene's 960x540 surface,
  `Screen:draw` lands `drawContent` on it 1:1 and `wantsFillScale` fills the
  window. `Renderer.MAX_UI_WIDTH/MAX_UI_HEIGHT` are widened once, additively
  and only on Gen 1, from the engine's 640x576 bound to 960x540 so
  `setUISize` accepts the request.

The Gen 2 path reads none of those Gen 1-only members.

## Rendering: the bottom band's frame (v1.9.1)

F (the message/move/target pane) and E (FIGHT/BAG/PKMN/RUN) draw as the
cart's own Gen 2 text box, on **both** generations.

The old band went through `Font.drawBox`, whose border comes from glyphs
`$79-$7E` of whichever font page the running generation loaded -- and the two
generations do not agree on that art. Gold's frames sheet carries the clean
GSC double-line box; a Red/Blue/Yellow boot has no frames sheet at all and
falls through to Red's own `font_extra` border, the ornate clover-cornered
double line. So on Gen 1 the band read as a Gen 1 text box.

`battle_screen.lua`'s `drawNativeFrame`/`drawNativeDivider` now draw that
frame as plain rectangles, edge-for-edge from the measures the engine's own
`Font.drawBox` produces with the default Gold frame tiles:

- horizontal tile: 1px outer line, 1px paper gap, 2px inner line;
- vertical tile: a 1px/1px pair, drawn unflipped on both sides;
- corners: the tile's own 3-step rounding, plus the bottom corners' clean 1px
  step (the cart's `bl`/`br` tiles are not vertical mirrors of `tl`/`tr`).

No ROM-derived art ships, no font page is registered, nothing is global --
the engine's `Font` state is untouched, so every other text box keeps its own
generation's art. Rectangles also free the frame from tile alignment (6.5
tiles is just 52px; the old `math.ceil` tile-rounding is gone).

F and E are **one** box with the menu window's left edge drawn over it as a
divider -- the cart's own shape (`BattleState:drawBottom` draws a full-width
message box and then the menu window over its right end) -- rather than two
separately framed boxes whose facing borders ran two pixels apart. A preset
that moves one pane away from the other still gets two separate frames.

The custom action-menu button is labelled **FORMS** (`settings.lua`'s
`customButtonLabel`), and player-facing strings say FORM. E label scales are
unchanged: a 12-tile pane cannot fit native-size 2x2/cross text.

## Target picker + sprite/HUD alignment (v1.9.2)

Two user-reported fixes, both in `battle_screen.lua`.

**1. The picker is read off the field.** F's target box used to list every
candidate (name + HP) with a cursor glyph beside the rows; it now carries only
its `Choose a target:` prompt. The cursor is an arrow drawn over whichever mon
is selected -- `Screen:drawTargetMark`, five stacked 1px rectangles forming a
downward triangle (widths 9/7/5/3/1) sitting just above that battler's own
readout, with a one-pixel bob. `self.hudMark` (stamped by `drawContent`'s HUD
pass this frame) is the anchor, so the arrow follows a preset that moves or
scales a readout. `updateTargetSelect` cycles on **either** axis
(up/left previous, down/right next), since the candidates are a horizontal row.

**2. The sprite pitch is the readout pitch.** A readout is 56.4px wide
(`GUI_TW` 15 tiles x `BOX_SCALE` 0.47), so two need 58.4px centre-to-centre.
The old grid pitch was only ~40.5px -- narrower than a readout -- so
`spreadBoxCentres` had to widen the readout row to stop boxes overlapping, and
the row's outer boxes then drifted off their own mons; worst in a five-mon
horde, where the GUI spread too wide to match the sprite positions.

`COL_W` is now `HUD_W + 2` = 58.4px, so each column is exactly one
non-overlapping readout apart:

- enemy team anchors at **e6 = 276.8px** and fills leftward
  (horde = e2..e6, centres 43.5 / 101.5 / 160.5 / 218.5 / 276.5);
- ally team anchors at **a1 = 35px** and fills rightward (the old +50px
  `ALLY_X_SHIFT` is folded into this anchor, so a lone ally does not move);
- a boss takes **e5 = 218.4px**; a horde's lone ally takes **a2 = 93.4px**.

`spreadBoxCentres` is now normally the identity -- a shipped row comes back
bit-for-bit on its slot centres -- and survives only as the safety net for an
over-full row that really does overlap. Verified in the Lua harness: for every
preset, each side's readout marks equal that side's slot centres exactly
(horde enemies and readouts both `43.5,101.5,160.5,218.5,276.5`), on both
generations.

## 0-PP moves stay on the move list (v1.9.3)

The player's move menu is now built from `Combat.allMoves` (every move the
battler still knows) instead of the AI's PP-filtered `Combat.usableMoves`, so a
move that has run out of PP keeps its row instead of disappearing. This is what
both native move menus do: the cursor still travels onto a 0-PP move, and
choosing it prints `No PP left for this move!` and returns to the list -- the
move is never dropped off it.

- `combat.lua` gained `Combat.allMoves(battler, data)`, identical to
  `usableMoves` except it keeps every move with a real def and stamps each
  entry with `usable = (slot.pp or 0) > 0`. `usableMoves` is unchanged and is
  still the AI's picker (`Combat.chooseAiAction`) and the "does this slot have
  any move left at all" test.
- `Screen:enterMoveSelect` fills `self.moveListCache` from `allMoves` and only
  skips the slot (the stated no-Struggle Phase 2 gap) when **no** move has PP
  left -- native never opens the list in that case either, so a menu of nothing
  but depleted moves is never shown.
- `Screen:updateMoveSelect` shows the refusal from the `MOVE_NO_PP_TEXT`
  constant when A is pressed on a 0-PP row (no action is queued, the phase
  stays `moveSelect`), and any press acknowledges it and returns to the list at
  the same cursor position -- the same "message + a press clears it" shape the
  action menu uses. `Screen:drawMoveSelect` draws that message in F in place of
  the rows until acknowledged. SELECT-swap still works on any row, PP or not,
  matching the native reorder.

## SWITCH: positional ally swap (v2.0.0)

The action menu gains a **SWITCH** button -- a POSITIONAL trade of places
between two ADJACENT allies, not the PKMN button's recall-and-replace switch.

**It is a layout capability, not a per-turn one.** `Screen.new` decides it once
from the roster the preset actually shipped:

```lua
self.swapEnabled = (not self.isBoss) and livingAllies >= 2
```

So doubles and triples get SWITCH, singles and hordes do not (only one living
ally), and a `bossFight` never does however many allies it fields. Every
menu/layout/draw/update path reads that one flag, so the button can never
appear where a swap has no meaning.

**Where the cell sits** -- directly UNDER FIGHT in every layout:

- **cross** (grid + `customButtonLabel`): the empty middle-left cell is filled
  -- `FIGHT/-/PKMN`, `SWITCH/FORMS/-`, `BAG/-/RUN`. Column 1 widens 20 -> 24px
  to fit six glyphs at the 0.5 scale, paid for by the centre budget 34 -> 30px,
  so the three-column block still measures 78px with a 2px margin each side.
- **plain grid** (grid, no custom button): a middle row --
  `FIGHT/PKMN`, `SWITCH/BAG`, `RUN/-`.
- **list**: inserted second in `self.menuOrder`; six rows at the cross's 0.5
  scale on a 7px pitch (the box only has ~42px of text interior -- native
  spacing would run out through the bottom border).

Cross/grid navigation goes through `stepCell`, a coordinate step that SKIPS
empty cells and wraps, so the SWITCH cross reaches its centre cell by plain
movement (the old 5-cell cross needed explicit cycles because a raw step from
any corner lands on a skipped cell and carries through to the opposite
corner). When SWITCH is off and a custom button is set, the original
`CROSS_RIGHT_CYCLE`/`CROSS_DOWN_CYCLE` behaviour is kept exactly.

**Choosing it** opens the `swapSelect` phase: F reads `Switch with whom?` and
the candidates are the owner's adjacent living allies (`slot +/- 1`). Up/left
and down/right cycle; A confirms; B returns to the action menu. If the owner
has no living neighbour the press is refused with
`<owner> has no adjacent ally to switch with.`

**Field cue.** A FILLED arrow (the same five-rectangle triangle the target
picker draws -- `drawArrowGlyph`) sits over the candidate under the cursor, and
a HOLLOW frame arrow of exactly the same size is left over the OWNER's sprite
-- the acting battler while choosing, and any queued owner
(`self.swapOwnerMarks`) until its swap resolves -- so the field always shows
who owns each swap.

**Resolution.** The swap queues as `kind = "swap"` (owner + slots + a
placeholder `def` so it survives the same queue paths) and resolves FIRST in
`Screen:beginResolving`/`Screen:advanceResolving` -- ahead of both move
resolution and the PKMN switch queue -- exchanging the two `playerBattlers`
entries so the new positions hold for the rest of the turn and anything that
reads positions (a spread move's centre, move-animation anchors) sees the new
shape. The message names both mons (`X switched places with Y!`) and the owner
cue clears as it resolves. B on the next slot's action menu undoes a queued
swap and drops its cue with it.

**Enemy-side export API.** The same swap is exposed so an enemy AI (or any
script) can reposition adjacent mons:

```lua
mod.exports.swapPositions(target, side, slotA, slotB) -- true | false, reason
mod.exports.swapCandidates(target, side, slot)        -- { slot indices }
```

`side` is `"enemy"` or `"player"`; both sides are index-adjacent (the sprite
grid fills the enemy half leftward from e6 in index order), so one validation
serves both: adjacent indices only, both battlers present and alive, battle not
over. Applied immediately -- a swap is pure position, so nothing needs to wait
for the turn to resolve and an AI can reposition mid-turn, the field updating
on the next frame.

Verified in the Lua harness (both generations): SWITCH enabled for the cross,
plain-grid and list doubles shapes and disabled for singles and bossFight; the
SWITCH cell in its documented position in each shape; `FIGHT <-> SWITCH` and
`SWITCH -> FORMS` cursor travel; `swapSelect` candidates, queued `kind="swap"`,
owner cue, B-undo; the resolve actually exchanging the two roster entries and
naming both; and `swapPositions`/`swapCandidates` on the enemy and player sides
including the non-adjacent, bad-side and fainted refusals.

## FORMS picks follow the mon that chose them (v2.1.0)

The CUSTOM ("FORMS") cell opens `Screen:enterGimmickSelect`, which bridges to
the `battle_forms` mod's documented surface (`formapi.gimmicks/arm/armed`).
**battle_forms decides everything off `battle.player`**:

- `formapi.gimmicks(battle)` resolves each mechanic's `available(battle)`
  against it when the list is built;
- its `arm()` hook dispatches the mechanic's own arm step, and a
  move-substituting mechanic (Dynamax's Max Moves, a Z-Move) rewrites
  *that battler's* move array there;
- its real `activate()` runs at `battle.turn_started` and reads
  `battle.player` again.

This scene pins `battle.player` to the **first** player battler
(`native.lua`'s `buildBattle`: `state.player = byMon[data.players[1]]`), so
before this a FORM picked from any other mon's action menu armed and activated
slot 1 instead of the mon that chose it.

**The pairing is controllable, and the scene now controls it.** Every
`battle_forms` call the bridge makes runs with `battle.player` focused on the
acting mon:

```lua
local function focusBattlePlayer(self, mon, fn)  -- pcall'd swap + restore
```

- `nativePlayerFor(self, mon)` maps a mon to what `battle.player` must BE:
  the mon itself on Gen 2, the native battler wrapper (`battle.battlersByMon`)
  on Gen 1.
- The pin is restored the instant the call returns, **whether `fn` returns or
  raises** (the whole thing is `pcall`'d and re-raises), so a raising
  battle_forms call can never leave the field pointed at the wrong mon.
- Focus points: eligibility when the list is built, `arm()` when a pick is
  confirmed, and the real `battle.turn_started` emit in
  `Screen:advanceResolving` (which is what actually triggers activation).

**Announcement (so peers are aware regardless).** Because the focus is
transient, a peer that reads `battle.player` later cannot assume it names the
FORM's owner -- so the scene emits its own event at every step:

```lua
FORMS_EVENT = "mod.g9-Battle-Scene.forms"   -- separate from CUSTOM_BUTTON_EVENT
-- payload: { phase, mon, species, slot, id, label, reason, battle, game, world }
```

| phase | when | reason |
| --- | --- | --- |
| `armed` | a pick is confirmed | -- |
| `used` | `battle.turn_started` consumed the armed id | -- |
| `cancelled` | B backs out of the menu | `backed-out` |
| `cancelled` | a second pick supersedes the first | `replaced` |
| `cancelled` | battle_forms refused the arm | `arm-refused` |
| `cancelled` | the armed id survived the turn-start | `activation-refused` |

"Consumed" is read off battle_forms' own published `armed()`: it clears the
armed id only when the entry actually activated, so a still-armed id after the
emit is a refusal. A `replaced` is announced **before** the superseding
`armed`, so a peer never sees two live owners for one battle. The on-screen
line names the mon too: `CHARMANDER armed MEGA EVOLVE!`.

Verified in the Lua harness (both generations): `gimmicks()` and `arm()` both
run with `battle.player` focused on the slot-2 mon (not the slot-1 pin) and the
pin is restored right after; the owner is recorded and the message names it;
every phase above (including `replaced` ordering) emits the documented payload;
and the real `battle.turn_started` emit runs focused on the owner, announcing
`used` when the stub consumes and `activation-refused` when it does not.

## Native ball throw + native catch animation (v2.1.1)

A thrown ball no longer resolves the instant A is pressed. `Screen:throwBall`
now **holds** the answer and plays the cart's own ball animation first, then
reports it the frame that animation genuinely ends (`Screen:resolveCatchAnim`):

- **The native animation.** `Screen:startCatchAnim` starts Gen 2's real
  `ANIM_THROW_POKE_BALL` through the same `src.battle.gen2.AnimRunner` +
  `src.ui.gen2.BattleAnimView` engine the move animations already use -- the
  ball is the engine's own object art, not a hand-drawn substitute. It refused
  the throw (and `throwBall` resolves on the spot) whenever the engine's anim
  tables, a target anchor, or the runner are unavailable, so the old behaviour
  is the fallback.
- **Native colour.** The ball is coloured by `N.ballPalette(ballId)` -- the
  ball's own battle-object palette (`PAL_BATTLE_OB_RED` for a Poke Ball, `_BLUE`
  Great Ball, `_YELLOW` Ultra Ball, `_GREEN` Master Ball, and so on; an unknown
  id falls back to the grey default). The ball's own script consumes it
  (`env.ballPalette`), which is why a Great Ball flies blue.
- **Flown to the target's real sprite position.** Vanilla's throw is calibrated
  for the fixed single-battle spots, so the re-aim is a per-axis SCALE, not a
  flat translate: `scaleX = (targetAnchor.x - actorAnchor.x) / (VANILLA_ENEMY.x
  - VANILLA_PLAYER.x)` (and likewise for y), with the runner's origin at the
  acting mon's own anchor (`self.spriteAnchor`). The ball therefore covers the
  real distance from the thrower to the target on this widescreen field instead
  of vanilla's own fixed gap.
- **Native catch animation.** `N.ballWobble` reproduces the cart's
  `GetPokeBallWobble`: the wobble hook the ball's own script calls draws from
  the per-ball probability table (Poke Ball / Great Ball / Ultra Ball rows, all
  255-based), returns 0 (stay in) or 2 (break out), and guarantees a catch on
  the 4th shake. The target is sucked in and hidden by the animation's own
  `BATTLE_BG_EFFECT_HIDE_MON`/`SHOW_MON`, which this screen's sprite pass honours
  directly (`animHidesMon` -- the flag is read off the running ball runner's
  `bg.hidden[side]`, exactly as `src/ui/gen2/BattleState.lua` reads
  `animPicState`), so a held mon's sprite (and its anchor) really leaves the
  field and comes back on a breakout. A **caught** ball's `anim_keepsprites`
  keeps the resting ball after the script ends.
- **The outcome lands on the cart's beat.** Caught -> the mon is filed and the
  screen moves to `over` with `Gotcha! X was caught!`; a break free -> `X broke
  free!` and the turn machine advances (`advanceSlotOrResolve`).

Gen 1 has no Gen 2 `AnimRunner`/`BattleAnimView`, but it is NOT animationless
-- see the next section for its own native arm (v2.1.2).

## Bag cancel returns to the action menu (v2.1.1)

B in the bag puts the player back on the battle's action menu normally:

- **Gen 2** pushes the native `Gen2PackMenu`, whose own B path calls `onClose`;
  the scene's `onClose` pops the pack and sets `suppressInputFrame` so the
  action menu underneath cannot read the same frame's B and back out again.
- **Gen 1** pushes a ball-only native `ListMenu`; B goes through `onCancel`,
  and the CANCEL row's `onChoose` (previously inert) now closes the list and
  returns to `phase = "actionMenu"` too -- with the same input-frame suppress.

Verified in the Lua harness (both generations): the Gen 2 ball starts
`ANIM_THROW_POKE_BALL` with param 5 / `PAL_BATTLE_OB_RED`, aimed from the real
thrower anchor `60:120` to the real target anchor `200:80`; the answer is held
until the runner finishes and then reported (caught -> filed + `over` + the
Gotcha line; break-free -> named + the slot spent); the sprite pass drops the
target's sprite/anchor while `bg.hidden.enemy` is set and restores it after;
the wobble sequence is `0,0,0,1,0` for a caught 255-rate ball, `0,0,0,2,0` for
a doomed one, and `2,2,2,2,2` when every roll breaks out; and the bag's B/A
cancel returns to `actionMenu` on both generations with the input frame
suppressed exactly once; on Gen 1 the ball plays the native chain instead (see
below).

## Gen 1's own native animation arm (v2.1.2)

A stock Red/Blue/Yellow boot has no Gen 2 anim tables, but it is not
animationless: **Gen 1 has its own native battle-animation engine,
`src/battle/AnimPlayer.lua`** -- the subanimation player its own `BattleState`
drives (`src/battle/BattleState.lua:1399-1405`). The scene now drives that
engine whenever the Gen 2 `AnimRunner`/`BattleAnimView` pair is absent, so both
move animations and the thrown-ball catch run natively on Gen 1.

- **Same contract the cart uses.** `N.AnimPlayer = src.battle.AnimPlayer` and
  `N.gen1AnimData(data) = data.battle_anims` (a BASE Gen 1 generated module, so
  present on every R/B/Y boot). `Screen:startGen1AnimStep` calls
  `player:start(name, attackerIsPlayer, opts)` -- `opts = { shakes, ball,
  ballFlicker }` on the ball rows, straight off `BattleState`'s own handling
  (`:1483-1512`): `POOF_ANIM` plays `SFX_BALL_POOF`, `HIDEPIC_ANIM`/`SHOWPIC_ANIM`
  flip `enemyHidden`, and a toss row carries the ball item (a Master/Ultra toss
  flickers its OBJ palette). `player:pollEffects()` is drained before the first
  tick and after every `:update()`, exactly as `BattleState:applyAnimEffect`
  drains it; a row's sound byte routes through `BattleState:playAnimSound`'s
  rule (`N.playMoveAnimSound`, GROWL/ROAR play the attacker's cry) and each ball
  shake opens with a `Tink`.
- **The ball chain is native's own** (`BattleState:ballChain`, `:5478-5496`,
  walked as a FIFO): `tossAnimFor` -> `POOF_ANIM` -> (`HIDEPIC_ANIM` ->
  `SHAKE_ANIM` with the real shake count from `Catching.attempt`) when the ball
  landed, and on a breakout `POOF_ANIM` -> `SHOWPIC_ANIM` puts the mon back; a
  clean miss (0 shakes) stops after the poof with the mon never hiding; a
  capture ends with `AnimPlayer:finalSprites()` left resting in OAM through the
  caught text (native's `lockedBall`). `N.ballTossAnim` / `N.ballFlicker` read
  the toss arc and the Master/Ultra flicker off `Catching.BALLS`.
- **Position.** `AnimPlayer`'s OAM sprites are in vanilla 160x144 space, so
  `Screen:drawGen1AnimSprites` remaps them exactly as the Gen 2 arm remaps its
  objects: the actor's real `spriteAnchor` and the real actor-target gap drive a
  per-axis scale, so the ball leaves the thrower's own sprite and lands on the
  target's. Because `AnimPlayer`'s compiled steps are flat sprite lists with no
  per-object identity, `gen1AnimGroups` first groups a step's sprites into
  connected components by OAM adjacency -- that keeps a multi-tile composite (a
  16x16 ball is four tiles) rigid under a non-unit scale, the same guarantee the
  Gen 2 arm gets from its own per-struct OAM tagging.
- **Move animations** take the same arm: `Screen:startMoveAnimGen1` plays the
  move's own `battle_anims` id from the actor's real anchor, with spread moves
  still aimed at the opposing side's centre. `Screen:update` dispatches the
  Gen 1 `stepGen1Anim` (FIFO) or the Gen 2 `runner:step()`; a caught ball keeps
  `self.moveAnim` alive via `keepSprites`, a move or breakout clears it.

Verified in the Lua harness (Gen 1): a caught throw (shakes 3) starts
`TOSS_ANIM,POOF_ANIM,HIDEPIC_ANIM,SHAKE_ANIM` with `opts.ball = POKE_BALL` and
`opts.shakes = 3`, holds the answer until the chain ends, then files the mon,
moves to `over`, and keeps the resting ball (`keepSprites`); a breakout (shakes
1) adds `POOF_ANIM,SHOWPIC_ANIM`, files nothing and spends the slot; a clean
miss (0 shakes) is just `TOSS_ANIM,POOF_ANIM`; a `TACKLE` move animation goes
through the same arm and clears when done; and drawing the arm (with no tile
image) and honouring `hiddenEnemy` both run without error. Gen 2's report is
unchanged (all `ball*` assertions still pass), and `luaparse 5.1` is clean.

## Gen 1's send-out ball is Gen 1's own ball (v2.1.2)

The summon throw (`Screen:drawBallThrow`, the intro send-out for every
trainer-battle mon) used to fall back to the hand-drawn `drawPokeball`
primitives on Gen 1, because the native ball it draws on Gen 2 is Gen 2's own
object (`BATTLE_ANIM_OBJ_POKE_BALL` in `data.gen2BattleAnims`), which a
Red/Blue/Yellow boot does not have. Gen 1 is not ball-less: the ball its own
cart tosses is `TOSS_ANIM`'s first frame block.

- **The asset is Gen 1's.** `data.battle_anims.moveAnims.TOSS_ANIM` (a BASE
  Gen 1 module) -> `seq[1].subanim` -> `subanims[..].blocks[1].block` ->
  `frameBlocks[..]` = `FRAMEBLOCK_03`: a 2x2 16x16 composite of tiles `$02`
  (upper half) and `$12` (lower half) out of anim tileset 0
  (`data/battle_anims/frame_blocks.asm`; reached via `Subanim_0BallTossHigh`,
  which `data/moves/animations.asm` `BallTossAnim` points at). That is the
  very tile the catch arm's own ball flies, drawn through the same
  sheet/quad path (`Screen:drawGen1AnimSprites`'s
  `AnimPlayer:sheetImage`/`tileQuad`) -- one object, one rendering.
- **Gen 2's asset is deliberately never read here** (user rule: Gen 1 uses Gen
  1's native ball). `drawNativeBall` now branches on `N.isGen2` first: Gen 1
  -> `drawGen1NativeBall`, Gen 2 -> the object/frameset path, byte-for-byte
  unchanged.
- **Nothing native tumbles it.** The GB's toss walks a static ball graphic
  along a base-coordinate list, so the flight is a plain translate of the
  block along this screen's own bezier, at the same 0.6 scale the Gen 2 ball
  uses (~10px, next to 56px mons). `drawPokeball`'s primitives remain the
  fallback only for a boot whose anim data or tilesheet is missing, so a
  send-out always reads as a ball.

Verified in the Lua harness against the shipped function (14/14): the four
native tiles land as a 16x16 box centred on the throw position (upper half
`$02`, lower half `$12`, right column x-flipped), the block is walked out of
the data (a different subanim block draws its own tiles/flips), a missing
tilesheet / frame block / `TOSS_ANIM` / `AnimPlayer` each returns false so the
caller keeps the primitive, the per-screen `AnimPlayer` is built once and
reused, the Gen-1 `drawNativeBall` dispatch positions through the translate
((10,20) -> the local box at (-8,-8)), and Gen 2's object/frameset path is
unchanged. Both existing regression probes re-run clean: the Gen-1 pre-turn
battery (15 keys, `pass: true`) and the Gen-2 `resolveTurnActions`/sanitizer
probe (flinch -> 0 uses with one `canAct`, spread -> 2 uses with one
`canAct`). `luaparse 5.1` clean.
