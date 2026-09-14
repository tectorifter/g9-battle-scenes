# g9-battle-scenes
modern battle layouts, doubles, triples, 4v1 boss fight

Runs on **both** generations:

- **Gen 2 (Gold/Silver)** -- the original home. Turn resolution calls
  `g9-battle-engine`; EXP calls the real native Gen 2 primitive
  (`Battle:awardExperience`). The catch maths is the selectable CATCH FORMULA
  option -- Generation 9 (Scarlet/Violet, the default), Generation 2
  (Gold/Silver) or Generation 1 (Red/Blue/Yellow) -- on BOTH generations (see
  "Catch formula"). Otherwise unchanged by the Gen 1 work.
- **Gen 1 (Red/Blue/Yellow)** -- turn resolution calls the GAME'S OWN Gen 1
  engine (`BattleState:performMove` sequenced by `src.battle.TurnOrder`),
  because `g9-battle-engine` is a Gen 2 engine and cannot drive a Gen 1
  battle. EXP uses `src.pokemon.Growth` + `Experience.apply`.

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
- **Catch animation paired to the formula.** `N.ballWobbleFromChecks` replays
  the selected formula's OWN shake count to the ball's script (0 = wobble again,
  1 = click, 2 = break free): a catch wobbles three times and clicks and a
  failure wobbles 0-3 times and breaks free, so the cartoon and the dice agree
  instead of the wobble count being re-rolled independently of the rate. The
  target is sucked in and hidden by the animation's own
  `BATTLE_BG_EFFECT_HIDE_MON`/`SHOW_MON`, which this screen's sprite pass honours
  directly (`animHidesMon` -- the flag is read off the running ball runner's
  `bg.hidden[side]`, exactly as `src/ui/gen2/BattleState.lua` reads
  `animPicState`), so a held mon's sprite (and its anchor) really leaves the
  field and comes back on a breakout. A **caught** ball's `anim_keepsprites`
  keeps the resting ball after the script ends.
- **The outcome lands on the cart's beat.** Caught -> the mon is filed and the
  screen moves to `over` with the selected formula's caught line
  (`N.caughtMessage`: Gen 1's "All right! X was caught!", Gen 2/9's "Gotcha! X
  was caught!"); a break free -> the cart's own line for that shake count
  (`N.ballMissMessage`, mode-aware: the four `common_3.asm` lines "Oh no! The
  POKéMON broke free!" / "Aww! It appeared to be caught!" / "Aargh! Almost had
  it!" / "Shoot! It was so close too!", or Gen 1's own `text_6.asm` set, where
  0 shakes really is "You missed the POKéMON!") and the turn machine advances
  (`advanceSlotOrResolve`). The old debug `(rate N/255)` text is gone.

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
the wobble hook is now driven by the formula's own shake count
(`0,0,0,1` for a catch, `0,0,2` for a two-shake failure, `2` for a zero-shake
failure); and the bag's B/A
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

## Player step guard -- base-engine crash fix (v2.1.2)

`player_guard.lua` is the one file here that is not scene machinery: it is a
crash fix for the **base engine's player**, installed by `main.lua` before any
other sibling, so the wrap is in place before any frame can run.

`Player:update`'s step-completion branch runs
`self.cellX, self.cellY = self.targetX, self.targetY` and then
`self.px, self.py = self.cellX * 16, ...` (`src/world/Player.lua:237-240`;
`src/world/gen2/Player.lua` carries the same branch at its own completion
line). A real step always has a target. But the engine can also move an entity
with **no target at all**: `OverworldState:marchInPlace` pushes an `inPlace`
scriptMove (`OverworldController.lua:5448-5452`) and `updateScriptMoves` arms
`moving = true, marching = true` with no `targetX`/`targetY` (:5476-5480);
`Commands.march_in_place`'s ambient `marchers` loop re-arms that same state
every frame (:5498-5506); `WorldAPI`'s `handle:marchInPlace()`
(`src/world/WorldAPI.lua:493`) reaches both. `NPC:update` HAS an arm for that
state (`src/world/NPC.lua:99-106`, `src/world/gen2/Npc.lua:584-590`) --
`Player:update` has none, so the very next frame assigns `cellX = nil` and the
frame after that dies on
`src/world/Player.lua:239: attempt to perform arithmetic on a nil value (field
'cellX')`, taking the whole overworld down with it.

Nothing in vanilla marches the PLAYER (`npcByIndex` resolves only
`self.npcs`, and the player is not in that table), so the state is only ever
reached by a mod that holds a `WorldAPI` handle onto the hero -- e.g. the
game/engine-controlled movement a script plays over the player around a fight,
once the parked world script is resumed at battle exit. This mod is the one
every routed battle leaves through, and it is a hard dependency of the battle
sample that first carried this guard, so the wrap lives here once for every
caller instead of in each of them.

For the marching case it mirrors `NPC:update`'s in-place beat (one walk cycle,
no translation) so the queued scriptMove can retire and `updateScriptMoves`
still fires its `onDone`; for a target-less non-march it puts the entity back
on its own cell; every healthy call -- a step with a target, or no movement at
all -- is handed straight to the engine's own `update`, so normal play is
untouched. Idempotent (`Player.g9StepGuard`, so a caller that also guards
cannot double-wrap) and a clean no-op when the player module cannot be
resolved.

Verified standalone (15/15 under fengari): both generations install on their
own module only; a phantom move is cleared and an in-place march retires
without either reaching the engine's update; a real step and an idle frame
each reach it exactly once; a second install does not double-wrap; an
unresolvable or update-less module is a clean no-op -- plus the engine's own
`src/world/Player.lua` driven end to end: unguarded it dies with exactly the
message above, guarded the same march survives and retires while a real step
still lands. `luaparse 5.1` clean.

## Forced switch-in when a battler faints (v2.1.2)

The bug: a fielded player battler could faint with healthy mons still sitting
in the party, and the scene simply left the slot empty. Two battlers down in a
double ended the battle outright -- even with a full reserve unused -- because
`Screen:finishTurn` asked `combat.sideDefeated(self.playerBattlers)`, a
question about the FIELD only. And there was no player-side counterpart to
`Screen:advanceEnemyReplacement` at all, so a fainted slot was never refilled.

Native's answer is the forced party list (`BattleState`'s own "forced-switch"
phase, `src/ui/gen2/BattleState.lua:2906-2926` / `:3048-3117`), which this
scene now raises for itself:

* **`Screen:playerBench()`** -- the usable reserve: every `save.party` mon that
  is neither on the field nor already down. Identity against the battler
  wrappers, because the active mons *are* the `save.party` entries (they share
  the table), so a fainted active mon can never count as its own replacement.
* **`Screen:playerSideDefeated()`** -- beaten only when the field AND the
  reserve are both down. `Screen:finishTurn` reads this instead of a bare
  `sideDefeated`, which is the "battle must not end until the whole party is
  fainted" rule.
* **`Screen:advancePlayerReplacement()`** -- called from the tail of
  `Screen:advanceResolving`, ahead of `advanceEnemyReplacement`, so the player
  is back in the fight before the trainer answers. Opens the picker for the
  first fainted slot when a healthy reserve exists, holds the turn, and is a
  no-op otherwise. Deliberately skips when the enemy side is already finished:
  winning ends the battle, and forcing a replacement into a won fight would be
  wrong.
* **`Screen:openForcedSwitch(slot)` / `chooseForcedMon` / `refuseForcedCancel`
  / `applyForcedSwitch`** -- the picker itself. **Gen 2**: `Gen2PartyMenu` with
  `prompt="which"` and no `battleSubmenu`, so A answers straight away; a B /
  CANCEL row calls `onCancel`, which prints `choose your next pokemon` in the
  list's own box and leaves it standing. **Gen 1**: `PartyMenu` with
  `forceSwitch` + `pickOnly` + `keepOpen`, so A calls `onSwitch` immediately and
  a refused pick stays on screen; B pops the list before `onCancel`, so the
  line gets its own `TextBox` and the picker is reopened behind it.
* A pick fills the **fainted slot in place** (`self.playerBattlers[slot]`), so
  the field keeps its shape and the incoming mon stands where the one it
  replaced stood. One slot at a time: two battlers can faint on the same turn
  and each gets its own prompt and its own `Go, X!` beat. The switch raises the
  same `battle.battler_switched` event the voluntary switch does, seeds
  `shownHp`, and sets `suppressInputFrame` so the confirming press is not read
  again as the beat's acknowledgement.
* A headless caller with no state stack auto-picks the first healthy reserve so
  the turn can never deadlock on a prompt nobody can see.

Verified under fengari against the real `battle_screen.lua` + `combat.lua` with
a mock engine (42/42): bench/defeat predicates; the picker triggering and its
three guards (no faint / no reserve / already won); both generations' pick,
refusals and cancel; in-place slot fill with position preserved; the
`battle.battler_switched` event; two faints in one turn prompting twice; the
headless fallback; `finishTurn` losing only when the whole party is down and a
win never misread as a loss; and `advanceResolving`'s tail order
(player -> enemy -> finish, with a held pick stopping the tail).
`luaparse 5.1` clean.

## Catch formula -- Generation 1 / 2 / 9 (post-2.1.2, version deliberately unbumped)

The catch maths is a user setting. The **CATCH FORMULA** mod option is declared
in two places that must stay in sync: `options.lua`, which the manifest names as
its `options_schema` (so the manager can render the row even while this mod is
disabled), and `main.lua`, which loads the same file and calls
`mod.options:define` at load time (which is what gives `mod.options:get` its
defaults). The row is the manager's native `choice` shape -- the label over the
current value, Left/Right to cycle:

```
CATCH FORMULA
GENERATION 9
```

`GENERATION 9` is the current Scarlet/Violet formula the scene used to be
hard-wired to; `GENERATION 2` is Gold/Silver's `PokeBallEffect` and
`GENERATION 1` is Red/Blue/Yellow's `ItemUseBall`. `N.catchFormula()` reads the
option afresh on every throw, so a change lands on the very next ball with no
reload; `N.catchAttemptForMode(mode, opts)` is the one dispatcher all three
share. Every arm returns the same four values -- `caught, shakes (0-3 shown),
a, chance` -- so the animation, the failure line and the `catch.rate` seam never
learn which one ran.

The three arms are transcribed from the games' own algorithms (Bulbapedia's
"Capture method" pages, cross-checked against the engine's own
`src/battle/Catching.lua` and `src/battle/gen2/Catching.lua`, which in turn
transcribe pret/pokered and pret/pokegold).

**Generation IX** (the default; `N.modernCatchAttempt`):

```
a = floor( (3*maxHp - 2*hp) / (3*maxHp) * 4096 * darkGrass
           * rate_modified * bonus_ball * badgePenalty )
      * bonus_level * bonus_status * bonus_misc
```

clamped to `[1, 1044480]` (`4096 * 255`). `a == 1044480` is certain (a Master
Ball, or a rate that saturates). `rate_modified` is the species `catchRate`
plus the Heavy Ball's weight adjustment; `bonus_ball` is the ball table below;
`bonus_status` is sleep/freeze 2.5 and poison/burn/paralysis/toxic 1.5 (the
Gen VIII+ numbers); `bonus_level` is SV's `max((36 - 2*level)/10, 1)`,
naturally 1 at level 13 and above; and `darkGrass`, `badgePenalty` and
`bonus_misc` have no Gen 1/Gen 2 counterpart and stay 1 (still accepted as
`opts` so a caller that knows them can pass them). The shake model is
generation VI+'s: `b = floor(65536 * (a/1044480)^(3/16))`, four rolls in
`0..65535` with a check passing when `roll < b`; the mon is caught when all
four pass, and the wobbles SHOWN are the checks that passed before the first
failure, capped at three.

**Generation II** (`N.gen2CatchAttempt`) is `PokeBallEffect`. The species rate
is multiplied by the ball (`ULTRA_BALL` 2, `GREAT_BALL`/`SAFARI`/`PARK` 1.5,
`POKE`/`FRIEND` 1) or by the conditional apricorn arm, then clamped to
`[1, 255]`; `a = max(1, floor((3*maxHp - 2*hp) * rate / (3*maxHp)))` plus 10 for
sleep/freeze, capped at 255. The check is one byte: a roll in `0..255` of at
most `a` catches (`a == 255` is certain). On a failure the ball runs up to
three shake checks against `b(a)`, the cart's `WobbleProbabilities` table
(`gen2ShakeB`), and the number that pass IS the wobble count. Three cart bugs
are kept deliberately because the engine's own Gen 2 module keeps them and a
"fix" would catch mons the real game never would: the `3*maxHp >= 256` 8-bit
truncation, the status bonus being sleep/freeze-only (burn/poison/paralysis
give 0, not the intended 5), and the conditional balls' own bugs (Fast Ball only
knows Magnemite/Grimer/Tangela, Love Ball boosts SAME-sex pairs, Moon Ball
compares against `BURN_HEAL` so it never boosts).

**Generation I** (`N.gen1CatchAttempt`) is `ItemUseBall`, a two-roll routine
with a per-ball roll ceiling. `N` is drawn from `0..255` for a Poké Ball,
`0..200` Great, `0..150` Ultra/Safari; a status threshold is subtracted (25
sleep/freeze, 12 poison/burn/paralysis) and an underflow catches on the status
alone. Otherwise `N - threshold > catchRate` breaks free. If not, `M` is drawn
from `0..255`, the HP factor
`f = clamp(floor(floor(maxHp*255/ballFactor) / max(1, floor(hp/4))), 1, 255)`
is computed (`ballFactor` 8 Great else 12) and `M <= f` catches. On a break
free the shakes come from `Y = floor(catchRate*100/ballFactor2)` and
`Z = floor(f*Y/255) + statusShake` (10 sleep/freeze, 5 other): `Z < 10` -> 0
shakes (the ball misses), `< 30` -> 1, `< 70` -> 2, else 3. This is why a
Gen 1 failure can honestly read "You missed the POKéMON!".

**The wobble count is the formula's own.** `N.ballWobbleFromChecks` replays
whichever count the arm rolled to the ball's script (0 = wobble again, 1 =
click, 2 = break free), so both the Gen 2 `ANIM_THROW_POKE_BALL` script and the
Gen 1 `SHAKE_ANIM` chain play exactly the shakes the dice produced.
(`N.ballWobble`, the old `GetPokeBallWobble` re-roll, is gone -- two live
sources of truth for one shake is what this replaces; the Gen 2 arm's own
`gen2ShakeB` table is that same cart data, now feeding the shared contract
instead of a separate loop.)

**The ball table** (`N.ballBonus`, Gen IX only) is the Gen VIII/IX set: Poke 1,
Great 1.5, Ultra 2, Safari/Sport 1.5, Premier/Luxury/Heal/Friend/Cherish 1,
Master and Park certain; Dream 4 asleep; Dive 3.5 fishing/surf; Dusk 3 at night
or in a cave; Net 3.5 vs Water/Bug; Repeat 3.5 if already caught; Timer
`min(1 + 0.3*turns, 4)`; Quick 5 on turn 1; Nest `clamp((41-level)/10, 1, 4)`;
Beast 5 for an Ultra Beast else 0.1; and Gen 2's apricorns at their modern
values -- Level 2/4/8 on the level ratio, Lure 3 fishing, Heavy the additive
weight bands (under 100 kg -20, then 0/+20/+30/+40 at 100/200/300/400 kg), Fast
4 at Speed >= 100, Moon 3 for the Moon Stone families, Love 8 for an opposite-
gender same-species pair. A ball id this table does not know falls back to a
mod's merged `balls` registry record (a numeric `multiplier` or `autoCatch`)
and then to a plain 1. Gen 2's own multipliers/arms cover the same ids with the
cart's numbers. `opts` carries the context these read (level, playerLevel,
speed, species, playerSpecies, gender, playerGender, types, weightKg (kg, for
the modern Heavy Ball), weight (tenths of a pound, for the Gen 2 Heavy Ball),
fishing, registered, turn, status).

**The ball is spent.** `Screen:throwBall` calls `N.consumeItem` on every valid
throw -- Gen 2's `UseDisposableItem` shape (decrement, nil at 0), Gen 1's
`Bag.remove` (which also fixes `save.bagOrder`) -- so a miss costs a ball
exactly as the cart's does.

**The wording follows the formula.** `finishBallThrow` prints the caught line
through `N.caughtMessage(name)` -- Gen 1's "All right! X was caught!"
(`data/text/text_6.asm:29`, ItemUseBallText05) or Gen 2/9's "Gotcha! X was
caught!" (`common_3.asm:265`) -- and the break-free line through
`N.ballMissMessage(shakes)`, which is Gen 1's own `text_6.asm` set ("You missed
the POKéMON!" / "Darn! The POKéMON broke free!" / "Aww! It appeared to be
caught!" / "Shoot! It was so close too!") or the shared `common_3.asm` set
("Oh no! The POKéMON broke free!" / "Aww! It appeared to be caught!" / "Aargh!
Almost had it!" / "Shoot! It was so close too!") for Gen 2 and Gen 9. The old
debug `(rate N/255)` text is gone.

**The mod seam is unchanged in shape.** `catch.rate` still receives
`(ball, mon, def, opts)` and still returns `caught, rate` -- with `rate` the
selected arm's final value (`a` for Gen 9, `f` for Gen 1) -- and the wrapper
additionally forwards `shakes` and `chance`, so a pass-through mod chain keeps
the exact wobble count the arm rolled; a mod that returns only `caught, rate`
has its shake count re-derived from the rate it chose (`N.shakesFor`, the
modern four-check model). `battle.ball_thrown` is still emitted with
`{ battle, ball, caught, shakes, rate, chance, mon, species }` on both
generations.

Verified under fengari: `luaparse 5.1` clean on every `.lua`; the three arms
plus dispatch and messages pass hand-computed cases (Gen I full-HP fail / 1-HP
Great catch / sleep status-alone catch / burn 1-shake; Gen II full-HP catch,
0/1/3-shake failures, 1-HP Ultra, sleep, certain-rate, a Level Ball 8x; the
option read returning each key and defaulting to `gen9` on a bad value; the
per-mode caught and failure lines) AND a **400/400** randomized cross-check
against an independent JS transcription of the pret/pokered and pret/pokegold
routines. The shipped `src/g9-Battle-Scene.zip` is rebuilt (19 entries: 2 dirs
+ 17 files, `options.lua` included) and every one of its 17 files inflates
byte-identical to this working tree, with the manifest still at **2.1.2** (no
version gate; the user only re-copies the zip).

## Wild-boss options -- BOSS CATCH / SPECIAL BOSSES / SHINY BOSS (post-2.1.2, version deliberately unbumped)

Three more Manager rows, all read by the new sibling `special_boss.lua` and all
scoped to exactly one thing: a **WILD** encounter whose active layout is the
`bossFight` preset. A wild encounter's screen payload carries no trainer table;
a TRAINER routed to the same layout (the sample's Champion/Red) carries one and
is never touched. Detection is the pair `layout.boss and not trainer`, read
through the same `getActiveLayoutData()` the screen itself uses.

```
BOSS CATCH          SPECIAL BOSSES      SHINY BOSS
ON (default)        NORMAL (default)    OFF (default)
```

**BOSS CATCH** (`boss_catch`, ON by default). While it is on, the boss is
marked on the battle table (`g9BossCatchMon`) and two things follow. First, a
`battle.damage` wrap at priority `1000000` -- the outermost wrap there is, above
the engine's own damage brain at 500 -- caps the FINAL number the whole chain
returns: a hit that would take the marked boss to 0 is reduced to `hp - 1`, the
same "survive on 1" shape as Sturdy, but unconditional (not full-HP-only),
because the option's promise is that a wild boss is never knocked out at all.
`next(ctx)` still runs every stage, so Protect, type immunity and every other
part of the pipeline decide whether the hit lands; the wrap only refuses to let
a landing hit be lethal. Second, `Screen:throwBall` asks
`specialBoss.bossCatchApplies(self.battle, target.mon)` and, when true, forces
the pending result to caught with a three-shake animation BEFORE the ball's own
catch animation starts -- so the native wobble plays the catch it is reporting.
OFF restores ordinary combat.

**SPECIAL BOSSES** (`special_bosses`: NORMAL / TERA / DYNAMAX / MEGA / ALL;
NORMAL is the default and is exactly today's behaviour) gives the wild boss one
persistent special property:

- **TERA** -- a Tera Type, stored through the engine's own
  `getTeraType`/`setTeraType` (which also mirrors battle_forms' per-mon override
  stamp, exactly as the engine's public API does).
- **DYNAMAX** -- Dynamax Level 10 via `setMonDynamaxLevel`; when the species is
  Gigantamax-eligible (`isGigantamaxEligibleSpecies`), the Gigantamax Factor is
  set too -- the "gigantamaxed, if possible" half of the request.
- **MEGA** -- the species' own Mega Stone, set as the boss's held item, so it
  holds that stone after capture. The pairing table is battle_forms'
  `data/megas.lua`, transcribed into `special_boss.lua`; a species with no mega
  falls back to a plain Dynamax so a boss this option rolled "mega" for is still
  special rather than silently ordinary.
- **ALL** -- one of the three at an equal 1/3 roll.

Every special boss additionally rolls **3 of its 6 IVs to 31**. The write goes
through the engine's `ModernStats`, the five non-HP battle stats are updated
from the new IVs, and the HP stat is adjusted by the DIFFERENCE the HP IV makes
(an additive delta) -- so a max-HP multiplier the caller already applied to the
boss (the sample's own x1..x5 boss scaling) survives untouched.

Deliberately NOT done, and stated rather than discovered later: this file never
decides WHEN a transformation activates. Dynamax, Gigantamax, Terastallization
and Mega Evolution are battle_forms' to trigger (the project's standing rule --
the engine consumes that trigger, it does not author one), and a wild Pokemon
never reaches battle_forms' enemy-trainer AI path. The boss is given the same
STORED properties a player's Pokemon would carry, which the game's own gimmick
systems deploy when they deploy and which survive the catch either way.

**SHINY BOSS** (`shiny_boss`: OFF / x1.5 / x2 / x3 / x4 / x5; OFF by default)
multiplies the vanilla 1-in-8192 roll by one unit roll. `mon.shiny` is a plain
stored field (the base engine's `Mon.isShiny` derives it from DVs and
`Mon.refreshStats` only ever ORs it in), so a successful roll both makes this
battle's sprite shiny and makes the property stick to the caught mon. A boss the
game already rolled shiny is left as it is.

Verified under fengari (`scratch/tests/special_boss_test.lua` +
`run_special_boss.mjs`): **28/28** checks green -- the option readers and their
defaults/fallbacks; wild-boss detection (no boss layout, a trainer on the boss
layout, the wild boss itself); the shiny multiplier's hit/miss/off and an
already-shiny mon; each SPECIAL BOSSES arm (tera stores a type and maxes
exactly 3 IVs; dynamax always sets level 10 and sets the G-Max factor only when
eligible; mega holds one of the species' own stones and falls back to Dynamax
for a species with none; ALL picks each of the three in turn under a scripted
roll); a caller-set max HP multiplier surviving the HP-IV delta; and the
`battle.damage` clamp (lethal -> `hp - 1`, non-lethal passthrough, a boss on
1 HP taking 0, and an unmarked battle or a different target left alone). The
shipped `src/g9-Battle-Scene.zip` is rebuilt (20 entries: 2 dirs + 18 files,
`special_boss.lua` included) and every one of its 18 files inflates
byte-identical to this working tree, manifest still **2.1.2**.

## Beat a trainer, get paid (post-2.1.2, version deliberately unbumped)

A trainer win now pays prize money in the scene, at the beat vanilla pays it:
the end of the fight, after the last enemy faints, folded into the over
screen's message. This screen stands in for the native battle screen, and
native is where the payout normally happens -- Gen 2 in
`Battle:awardPrizeMoney` / `WinTrainerBattle`, Gen 1 in
`BattleState:enemyMonFainted` -- so a routed fight used to hand a beaten
trainer's money to nobody. The scene pays it for both generations and for
every caller (this sample, `wild_forms`' boss path, anything else routed
through here), not only the one mod that happened to patch it.

The routine is each generation's OWN, not a re-derivation, reached through
`native.lua`'s `N.awardTrainerPrize(battle, save, trainer)`:

- **Gen 2** calls the engine's `src.battle.gen2.Prize` (`Prize.award` =
  ComputeTrainerReward + WinTrainerBattle): `baseMoney x wCurPartyLevel`, the
  level being `Prize.rewardLevel(enemyParty)` -- the LAST roster row, the mon
  whose faint ended the fight -- with the Amulet Coin doubling before the four
  quarters are split between the wallet (`save.player.money`) and the Bank of
  Mom (`save.mom.savedMoney`). The line is `Prize.message`, the cart's own text.
- **Gen 1** calls Gen 1's routine: `(trainer.baseMoney or 0) x last-roster-level`
  added straight to `save.money`, no quarter split and no Bank of Mom (those are
  Gen 2's), with the line built through `src.core.Strings`
  (`"%s got ¥%d for winning!"`, the same string the decoded
  `BattleState:enemyMonFainted` uses).

`trainer` is passed explicitly because the Gen 1 model carries no `.trainer`
field at all; `battle.trainer` is the fallback for engines that do. The seam
returns `nil` when there is nothing to pay (no battle/save, a legacy nameless
`true` trainer with no `baseMoney`, an empty roster, a zero figure, or -- Gen 2
only -- a missing `Prize` module), so `Screen:awardTrainerPrize` can never print
a line for money that was not handed over. It only pays a trainer fight won by
the player (`self.outcome == "win" and self.isTrainerBattle`) and is idempotent
against `self.prize`, so a second call cannot pay twice.

`g9-battle-sample` 0.5.7 removes its interim Gen 1 payout -- the scene is the
single payer now, so a Gen 1 scene win is paid exactly once.

Verified under fengari (`scratch/tests/scene_prize_test.lua` +
`run_scene_prize.mjs`): **19/19** checks green -- both arms installed and
exporting the seam; Gen 1 last-level (not first), explicit-trainer precedence,
`battle.trainer` fallback, zero/legacy-`true`/empty-roster/missing-`money`
cases, and a clean nil for no battle or no save; Gen 2 the engine's own four
quarters, the Amulet Coin doubling, the Bank of Mom quarter, a missing-`Prize`
degrade, legacy-`true`, no-player and zero-base cases; and the two arms paying
the same figure (`Gen1 x 4 == Gen2`). The shipped `src/g9-Battle-Scene.zip` is
rebuilt (20 entries: 2 dirs + 18 files) and every one of its 18 files inflates
byte-identical to this working tree, manifest still **2.1.2**.
