# g9-battle-scenes
modern battle layouts, doubles, triples, 4v1 boss fight

Runs on **both** generations:

- **Gen 2 (Gold/Silver)** -- the original home. Turn resolution calls
  `g9-battle-engine`; EXP calls the real native Gen 2 primitive
  (`Battle:awardExperience`). The catch maths is the selectable CATCH FORMULA
  option -- **AUTO (the default), which follows the running game**, or an
  explicit Generation 9 (Scarlet/Violet), Generation 2 (Gold/Silver) or
  Generation 1 (Red/Blue/Yellow) override -- on BOTH generations (see
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
| `cancelled` | the SAME slot re-picks a different gimmick | `replaced` |
| `cancelled` | battle_forms refused the arm | `arm-refused` |
| `cancelled` | the armed id survived the turn-start | `activation-refused` |

"Consumed" is read off battle_forms' own published `armed()`: it clears the
armed id only when the entry actually activated, so a still-armed id after the
emit is a refusal.  A `replaced` is announced **before** the replacing `armed`,
so a peer never sees two live owners for one SLOT.  (Since v3.8.6 a pick in a
DIFFERENT slot no longer replaces anything -- the scene keeps one armed gimmick
per acting Pokemon and fires them all in action order; see the GIMMICK SEQUENCE
block.)  The on-screen line names the mon too: `CHARMANDER armed MEGA EVOLVE!`.
Confirming a FORM also parks the action box cursor back on **FIGHT**
(`menuCursor = "FIGHT"` on the successful-arm path, v3.8.7), so the FORMS detour
ends where the turn continues rather than leaving the cursor on the CUSTOM cell;
a refused arm or a B cancel leaves the cursor where it was.

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
AUTO
```

`AUTO` (**the default**) follows the running game -- `GENERATION 1`'s
`ItemUseBall` on a Red/Blue/Yellow boot, `GENERATION 2`'s `PokeBallEffect` on a
Gold/Silver/Crystal boot -- so each ball uses its own generation's real catch
data. `GENERATION 9` (the current Scarlet/Violet formula the scene used to be
hard-wired to), `GENERATION 2` and `GENERATION 1` remain as explicit overrides.
`N.catchFormula()` reads the option afresh on every throw, so a change lands on
the very next ball with no reload, and resolves `auto`/absent/unknown through
`N.isGen2`; `N.catchAttemptForMode(mode, opts)` is the one dispatcher all three
share. Every arm returns the same four values -- `caught, shakes (0-3 shown),
a, chance` -- so the animation, the failure line and the `catch.rate` seam never
learn which one ran.

The ball's own catch factor is read from the game's **merged ball registry**
(`data.balls` / `data.gen2Balls`, filled by the game's own
`src/battle/Catching.lua:registerInto`) before this scene's fallback tables, in
the same order the game's own `Catching.rate`/`Catching.attempt` use -- a Gen 1
ball's `randMax`/`hpFactor`/`wobbleFactor`/`autoCatch`, a Gen 2 ball's
`multiplier`/`specialty`/`autoCatch` -- so a registered or mod-added ball's real
catch multiplier is what lands.

The three arms are transcribed from the games' own algorithms (Bulbapedia's
"Capture method" pages, cross-checked against the engine's own
`src/battle/Catching.lua` and `src/battle/gen2/Catching.lua`, which in turn
transcribe pret/pokered and pret/pokegold).

**Generation IX** (an explicit override; `N.modernCatchAttempt`):

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
sleep/freeze, capped at 255. The check is one byte: a roll in `0..255` under
`a` catches, i.e. `a/256` (`a == 255` is certain). On a failure the ball runs up to
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
option read returning each key and defaulting to `auto` on a bad value; the
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
  `data/megas.lua`, transcribed into `special_boss.lua`; the single-value MEGA
  option falls back to a plain Dynamax for a species with no mega, so a boss
  this option was asked to make special is never left silently ordinary.
- **ALL** -- an even roll over the special properties this boss can actually
  take. TERA and DYNAMAX are always in the pool (DYNAMAX upgrading to
  Gigantamax when the species is eligible); MEGA joins it only when the species
  really has a Mega Stone. An inapplicable property is dropped rather than
  collapsing onto another -- so a boss that can be neither Gigantamaxed nor
  Mega-evolved gets an even **50/50 TERA vs DYNAMAX**, while a Mega species
  keeps a 1/3 roll. (Before the round-151 fix the mega slot fell back to
  Dynamax, which gave Dynamax two of the three slots and made the "neither"
  case 1/3 tera / 2/3 dynamax instead of 50/50.)

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

**The announcement and the sprite now agree (v2.8.1).** Precisely *because* a
wild boss's gimmick is never activated, `g9-battle-sprites`' live read found
nothing for it: the opening F-box said "You have found a Tera WATER Krabby
raid!" while the boss drew ordinary (the announcement and the sprite came from
two different places). The scene now also hands the sprite mod the declaration it
already stamped. `pushBattleBattleScreen` copies `battle.g9BossKind` onto the
boss battler as `g9RaidGimmick` right after the screen is built, and
`resolveSprite` forwards it on the `battle.mon_pic` seam as `ctx.boss = true` and
`ctx.bossGimmick = { kind, detail }` (boss slot only). `g9-battle-sprites` paints
the declared crystal film / Dynamax cloud from it when its own live read is
empty. It is a VISUAL fallback only: no gimmick is activated, the mon is
untouched, a real live transformation still wins, and a screen that sends no
declaration (or an older sprite mod that ignores the keys) behaves exactly as
before.

**SHINY BOSS** (`shiny_boss`: OFF / x1.5 / x2 / x3 / x4 / x5; OFF by default)
multiplies the vanilla 1-in-8192 roll by one unit roll. `mon.shiny` is a plain
stored field (the base engine's `Mon.isShiny` derives it from DVs and
`Mon.refreshStats` only ever ORs it in), so a successful roll both makes this
battle's sprite shiny and makes the property stick to the caught mon. A boss the
game already rolled shiny is left as it is.

Verified under fengari (`scratch/tests/special_boss_test.lua` +
`run_special_boss.mjs`): **34/34** checks green -- the option readers and their
defaults/fallbacks; wild-boss detection (no boss layout, a trainer on the boss
layout, the wild boss itself); the shiny multiplier's hit/miss/off and an
already-shiny mon; each SPECIAL BOSSES arm (tera stores a type and maxes
exactly 3 IVs; dynamax always sets level 10 and sets the G-Max factor only when
eligible; mega holds one of the species' own stones and falls back to Dynamax
for a species with none; ALL rolls only the properties the boss can actually
take -- see the round-151 section below); a caller-set max HP multiplier
surviving the HP-IV delta; and the `battle.damage` clamp (lethal -> `hp - 1`,
non-lethal passthrough, a boss on 1 HP taking 0, and an unmarked battle or a
different target left alone). The shipped `src/g9-Battle-Scene.zip` is rebuilt
(20 entries: 2 dirs + 18 files, `special_boss.lua` included) and every one of
its 18 files inflates byte-identical to this working tree.

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

## Battle backgrounds -- the tag-driven drop-in folder (v2.3.0)

The scene has always painted its field plain white (`Screen:draw` /
`Screen:drawWidescreen` fill the surface, then `drawContent` paints the
sprites). With the pack's true-colour, DS-era animated sprites that white field
was the one place the scene still looked unfinished, so there is now a
**near-top-down ground plane** behind the sprites: the fight is staged on the
ground it actually happens on, and the mons stand on a surface instead of
floating over a white void.

**No art ships; the folder is yours.** The mod deliberately bundles **no**
background images. `assets/backgrounds/` is empty of art (it holds only its
`README.md`, which is still shipped so the folder exists in the zip), and the
player drops in whatever PNGs they want, named by **the fight they are for**.
This also retires the earlier generated four-PNG set and its `CREDITS.md`:
nothing third-party is redistributed and nothing is ripped from a commercial
game.

**The tag scheme.** A file's name (before its extension) is its tag:
`grass`, `water`, `cave`, `gym`, `gym1`..`gym16`, `elitefour1`..`elitefour4`,
`champion`, `red`, `rival`, `rocket`, `ho-oh`, `lugia`, `suicune`, `fated`.
`gym` is the generic gym ground, used as a fallback (see below).
`fated` is the catch-all for any other legendary or scripted/static encounter.
A file may carry a **variant suffix** -- `gym1-2.png`, `gym1-23.png`,
`grass-2.png` -- meaning "another asset for the tag before the dash"; when
several files share a tag **one is rolled at random per battle and kept for
that whole fight** (two files = 50/50; N files = 1/N). The number after the
dash is only a disambiguator, not a weight. Tag matching is longest-name-first,
so `gym10-3` is gym 10, not gym 1. `.png` / `.jpg` / `.jpeg` / `.webp` are
accepted; `README.md` and dot-files are ignored.

**How a tag is chosen.** `background.lua` resolves a battle in priority order:
(1) **trainer class** -- gym leader → `gym1`..`gym16` (both Gen 1's `OPP_*`
names and Gen 2's bare names; **Giovanni** is `gym8` on Viridian Gym and
`rocket` everywhere else), Elite Four → `elitefour1`..`elitefour4` (Gen 1's
Lorelei/Bruno/Agatha/Lance and Gen 2's Will/Koga/Bruno/Karen, each in league
order), Champion → `champion`, Red → `red`, rival → `rival`, any Rocket grunt
→ `rocket`; (2) **opposing species** -- Ho-Oh/Lugia/Suicune by name, any other
legendary → `fated`; (3) **wild terrain** -- the engine's own encounter roll
supplies `"grass"` / `"water"` / `"indoor"` (hooked via `encounter.roll`,
`encounter.species` and `encounter.fishing`), so a grass/water/indoor wild
battle maps straight to
`grass` / `water` / `cave`. Gen 2 spells this differently -- it rolls only
`"grass"` / `"water"` and carries the cave/indoor case in the map header, so
the roll's own `ctx.environment` turns a `"grass"` roll on a `CAVE` /
`DUNGEON` / `INDOOR` / `GATE` map into `cave`. **The map the fight is on right
now outranks the roll**: a live water/cave fight is `water`/`cave` whatever the
roll says (so a session that opened in the grass can never repaint a later
surf/cave battle, and vice versa), and the roll only refines a grass-looking
map -- fishing from the shore is water, a Gen 2 `"grass"` roll on a cave map is
cave. Each roll is **spent by the one battle it belongs to**, so a leftover can
never pin a later fight to an earlier terrain (the v2.9.0 fix); (4)
**static/scripted** -- a wild battle with no encounter roll behind it (nothing
left to spend) → `fated`; (5) **map fallback** --
a gym map with no class match still gives its gym number, otherwise the
map/player decides (`water` while surfing, `cave` for `CAVERN`/`CAVE` tilesets
or a cave/dungeon/indoor map environment, and indoor maps via the engine's own
`indoorEncounters.firstIndoorMap` / `excludedTileset` test, else `grass`).
Surfing is detected on **both** generations -- Gen 1's `player.surfing`, Gen 2's
`world.playerState` (`"surf"` / `"surf_pika"`), or simply the water cell under
the player, which only a surfing player ever stands on. **A gym, Elite Four or Champion tag with no art walks its own fallback chain**
— `gym<N>` / `elitefour<N>` / `champion` → `gym.png` → `grass.png` (see
v4.0.5), so one of those fights never goes white or borrows the map's `cave`
ground.

**Any other tag with no art falls back to the map's terrain tag** (when it is
not itself a terrain tag), so a missing `champion.png` on an outdoor map still
shows that map's ground rather than white.

**Gym numbering** is badge order per generation: Gen 1 is 1 Pewter … 8
Viridian; Gen 2 is 1–8 the Johto gyms in badge order and 9–16 the Kanto gyms
in badge order, matching the sixteen badges Gold/Silver hands out.

**Option.** The row is `BACKGROUND` (`battle_background` in `options.lua`).
**AUTO** (default) does all of the above; **OFF** draws nothing at all, so a
run that leaves it off is pixel-for-pixel the old white field. A raw tag name
is also accepted as the option value, to pin every battle to one backdrop.

**How it draws.** `background.lua` scans `assets/backgrounds/` once at load
(`mod:list`), groups files by tag, and decodes a PNG through the same three
routes every image-loading mod here uses (mod-folder path, own bytes, the
`Image:getData` detour), caching the result. It filters **nearest** and hangs
the image from the field's **top edge** — its ROOF flush with the screen's roof,
so no white ever shows above it — scaled to **cover** the band from there down to
the **middle of the F/E box** (design y=154; the F/E box owns the field's last
6.5 tiles, so its middle is 26px above the field's bottom edge). Concretely
`s = max(320 / imageWidth, 154 / imageHeight)` and the image is drawn at
`x = (320 - imageWidth*s)/2, y = 0`. In the **320x180 design field** that means
a source at least as broad as the band (~2.08:1) is zoomed until its feet land
on the F/E box's middle and its sides crop (centred), while a **taller** source
(16:9 or narrower) keeps its full width and runs its lower overflow behind the
F/E box. Either way the backdrop always reaches the top of the screen. The draw
is the first thing `Screen:drawContent` does, so every sprite, HUD readout and
F/E box paints on top of the backdrop exactly as it did on the white field. A
soft
**contact shadow** is then drawn under every sprite already on the field (an
ellipse ~0.36 x 0.085 of the sprite height, at its feet), read from the anchor
the previous frame's sprite pass recorded on the `Screen`, so the mons read as
standing on the ground. `battle_screen.lua` grew one method --
`Screen:drawBattleBackground()`, called as the **first** statement of
`Screen:drawContent()` -- so every sprite, HUD readout and F/E box paints on top
of the backdrop exactly as it did on the white field.

**Never fatal.** A missing folder, no files, a broken PNG, an unknown option
value, or a harness with no `love.image` all degrade to the old white field:
the decode fails once (one `mod.log:warn`, remembered so it is not retried per
frame) and the call site is `pcall`'d, so field art can never abort a turn.

Verified under fengari (`scratch/tests/scene_background_test.lua` +
`run_scene_background.mjs`): **73/73** checks green -- the folder scans into
tags (variant suffixes resolve to their base tag, longest-name-first, so
`gym10-3` is gym 10 not gym 1; `README.md`/dot-files/txt ignored; once, not per
frame); the tag resolver maps every trainer class (both gens' gym leaders and
Elite Four in league order, Champion, Red, rival, Rocket grunts, and Giovanni
as `gym8` on Viridian Gym but `rocket` elsewhere), the opposing species
(Ho-Oh/Lugia/Suicune by name, any other legendary -- including via a form's
`baseSpecies` -- to `fated`), and the recorded wild terrain (grass/water/indoor
rolls, fishing, a live water/cave map outranking a stale roll, the per-battle
roll spend, a 60 s freshness window, and `fated` for a wild battle with no roll
behind it); the map fallback (surfing -> water, `CAVERN`/`CAVE` and indoor
maps -> cave, gym map -> its gym number per generation); the **Gen 2 terrain
signals** (surfing via `playerState` `"surf"`/`"surf_pika"` or the water cell
underfoot; cave/dungeon/indoor via `def.environment`; a Gen 2 grass roll on a
CAVE map still resolving to cave, and a water roll outranking the environment);
`resolvedTag` for off/auto/a pinned tag/junk; pickFile over one file, a 50/50
two-file tag, and an N-file tag, with a non-terrain tag falling back to the
map's terrain tag and a terrain tag staying white; draw caching the tag + file
(a multi-file tag stays fixed for a fight, two Screens may differ -- and a
**reused** Screen drops the file when the tag re-resolves, so a later battle's
environment can never be stuck with the first one's backdrop) and hanging the
image from the screen's roof (y=0) scaled to cover the F/E box's middle line
(`s = max(320/w, 154/h)`, so a ~2.08:1-or-broader source's feet land on y=154
and a taller one runs its overflow behind the box), with the white `setColor`
and nearest filter; OFF and no-art
drawing nothing; the contact-shadow pass over a populated `spriteAnchor`; and a
broken file (or an all-broken decode) warning once and staying white without
throwing. A second fengari suite, `scratch/tests/scene_bg_session.lua` +
`run_scene_bg_session.mjs` (**7/7**), drives the REAL engine `Hooks.lua` /
`Runtime.lua` through whole play sessions of consecutive battles and proves the
terrain follows each fight -- grass then water then cave, water then grass, a
reused Screen (now asserting the picked FILE, not just the tag -- the
sticky-backdrop regression), `now()==0`, a spent roll that must not leak, a
roll-less fight on
water, and fishing from the shore. (The suite also covers the life-buoy pass
(v2.5.0, tilted in v2.6.0 -- see the Life buoys sections below), which is where
the buoy checks live.)
`background.lua` / `main.lua` / `options.lua` / `battle_screen.lua` are
luaparse 5.1 clean, `manifest.json` + `files.json` are JSON-valid at **3.0.0**,
and the committed `src/g9-Battle-Scene.zip` is rebuilt with every listed file
inflating byte-identical to this tree. In-game confirmation is still the user's
(the mod only runs in LÖVE); the folder should be play-tested on a real battle.

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

## SPECIAL BOSSES: ALL only rolls what the boss can become (v2.4.0)

The `all` arm of SPECIAL BOSSES used to roll uniformly over three fixed
properties -- TERA, DYNAMAX and MEGA -- and then fall back when one could not
apply: a species with no Mega Stone had its "mega" roll collapse onto Dynamax.
That silently double-weighted Dynamax, so a boss that could be neither
Gigantamaxed nor Mega-evolved -- the case this fix exists for -- came out
**1/3 Tera / 2/3 Dynamax** instead of a 50/50.

`special_boss.lua` now builds the pool from what this boss can actually take
*before* it rolls: **TERA** and **DYNAMAX** are always in it (DYNAMAX still
upgrades to Gigantamax when the species is Gigantamax-eligible), and **MEGA**
joins it only when the species really has a Mega Stone. An inapplicable property
is dropped, not collapsed onto another. So:

- a boss that can be neither Gigantamaxed nor Mega-evolved -> **50/50 Tera vs
  Dynamax**;
- a Gigantamax-eligible boss with no Mega -> 50/50 Tera vs Dynamax, where the
  Dynamax result carries the G-Max factor (i.e. Gigantamax);
- a species with a Mega Stone -> the original even 1/3 roll over Tera / Dynamax
  / Mega.

The eligibility test is a new `megaEntryForSpecies` -- the old
`stoneForSpecies` lookup split in two, so testing eligibility does not consume
an RNG draw for a species with several stones; `stoneForSpecies` still picks one
entry from the list for the MEGA option. TERA remains the one arm that can
genuinely decline (a species the running game's data cannot resolve a type for),
and now falls back to Dynamax rather than leaving the boss ordinary. The
single-value MEGA option is unchanged: for a species with no Mega it still falls
back to a plain Dynamax, because that option is a direct request rather than a
roll.

Verified under fengari (`scratch/tests/special_boss_test.lua` +
`run_special_boss.mjs`): **34/34** checks green, six of them new -- the
neither-G-Max-nor-Mega boss rolls exactly `{tera, dynamax}` with MEGA
unreachable (roll 1 -> tera, roll 2 -> dynamax, and the old roll-3 collapse is
gone); a 1000-roll distribution over such a boss produces only tera/dynamax and
stays inside a 40/60 band; a Gigantamax-eligible no-Mega boss still reaches
Gigantamax; a Mega species keeps its 3-way pool; and a TERA that cannot resolve
falls back to Dynamax. `special_boss.lua` / `options.lua` are luaparse 5.1
clean, `manifest.json` + `files.json` are JSON-valid at **2.6.0**, and the
committed `src/g9-Battle-Scene.zip` is rebuilt with every listed file inflating
byte-identical to this tree. In-game confirmation is still the user's (the mod
only runs in LÖVE).

## Life buoys on water -- flightless mons float (v2.5.0)

A water fight (the `water` tag -- and, since v2.7.1, the water actually on the
field, tag or the map terrain its art falls back to; see *Life buoys follow the
field terrain*) stages every battler on the surface, which is
right for a Water type, right for a Flyer and right for a natural hoverer, and
wrong for everything else -- a Charmander would be standing on the open sea.
Now every battler that neither swims, flies nor hovers is given a **life ring
worn on its lower body**, so a fight on water reads as afloat even on a stock
install with no field art.

**Who needs one.** `needsBuoy` is the complement of `g9-battle-sprites`'
`data/dbk_float.lua` FLOAT set: a mon needs a ring when it is **not** Water,
**not** Flying (minus the flightless walkers DODUO/DODRIO/FARFETCHD/SKARMORY/
DELIBIRD/HAWLUCHA/FLAMIGO/ROWLET, which cannot fly themselves out of the
water), and **not** a known hoverer (Levitate, magnet/balloon bodies, the
floating Ghosts -- the same species list, mirrored here as `FLOATER`). Type
`"Water"` (a Gen 1 records) and `"WATER"` (a Gen 2 one) are both normalised, a
form's `_N` suffix is stripped before the lookup, and a battler with **no type
data at all** is left alone rather than guessed at (so a missing dex record
never rings a Water type).

**Worn, not behind: two passes.** The ring's **far half** is painted in the
background pass -- as the first thing `Screen:drawBattleBackground` does, so it
sits behind the sprite -- and its **near half** is painted after the sprite
pass, from the scene's new `Screen:drawBattleBackgroundFront()` (called
immediately after the player-battler sprite loop and before the HUD boxes), so
the front rim crosses the mon's feet and the ring reads as *around* it rather
than a disc stuck behind it. `background.lua` exposes the two halves as
`M.draw` (far) and the new `M.drawFront` (near); `battle_screen.lua`'s sprite
pass now also records each sprite's drawn width on the `Screen`, so the ring
has the anchor it needs without any new plumbing.

**Geometry** (all in multiples of the sprite's own drawn size, design px): outer
diameter = **1.20 x** `max(sprite width, sprite height)`, centre **0.28** of the
sprite height above the feet, hole diameter **0.55** of the outer. A wide mon
gets a wide ring; the ring dips a little onto the water.

**Art is a player drop-in**, like a background: `assets/lifebuoys/` (and
`assets/`) are scanned once for a PNG named `lifebuoy` / `buoy` / `lifering` /
`life-ring` / `life-buoy` (an optional `-<n>` variant suffix is fine; several
files are rolled one per battle). With **no art** the ring is drawn from
primitives instead -- a flat annulus built from polygons (`annulusSector`) as
four dark sectors under four colour sectors a half, so it needs nothing but
`love.graphics.polygon` (an `arc`/pie fill cannot make a hole, and `arc` would
tie us to a LÖVE version). The art path uses two `newQuad` halves; a build
without quads falls back to drawing the **whole** primitive ring behind the mon
(the old look) rather than the ring twice.

**Never fatal**, like everything else here: no folder, no art, an unreadable
PNG (one `mod.log:warn`, remembered), a missing pokemon record, or a harness
without `love.graphics` all degrade to "no ring drawn" and never abort a frame;
both passes are `pcall`'d at the call site.

**Docs.** `assets/lifebuoys/README.md` is the folder's reference (drop-in names,
variants, the worn-ring geometry, who gets one); this section is the code
summary.

Verified under fengari (`scratch/tests/scene_background_test.lua` +
`run_scene_background.mjs`, loading the REAL `background.lua`): the suite is now
**55/55** green, the 13 new checks covering the buoys -- a water fight rings
Charmander, the flightless Doduo and Machop but not Squirtle/Gyarados/Pidgey/
Gastly/Abra/Magnemite; `M.drawFront` draws exactly the near half at the ring's
centre line and nothing before the sprite pass; a grass fight rings nobody; no
art draws the eight-sector primitive ring (8 polygons behind, 8 in front); the
ring is keyed off the resolved tag, not off a field file; the drop-in is found
in `assets/lifebuoys`; a width-less anchor falls back to height; a missing
record, a form suffix and a pure-Water mon get no ring; an unreadable PNG warns
once and falls back; a build without quads draws the whole ring behind; and no
anchors means no rings. `background.lua` / `battle_screen.lua` are luaparse 5.1
clean; `manifest.json` + `files.json` are JSON-valid at **2.5.0** (`files.json`
now lists **21** files, adding `assets/lifebuoys/README.md`); and the rebuilt
`src/g9-Battle-Scene.zip` (**26** entries: 5 dirs + 21 files) inflates every
listed file **byte-identical** to this tree. In-game confirmation is still the
user's (the mod only runs in LÖVE).

**User action.** Re-export **`g9-battle-scene`** and unzip over
`mods/g9-Battle-Scene/`. Water fights now float the mons that need it with a
built-in ring out of the box; drop a wide (2.8:1) transparent PNG at
`mods/g9-Battle-Scene/assets/lifebuoys/lifebuoy.png` to use your own.

## Life buoys are tilted to the water plane (v2.6.0)

The v2.5.0 ring was drawn as a **full circle**, but it lies flat on the water --
so it should obey the same oblique overhead foreshortening the water plane does,
not stand up like a hoop. The ring is now an **ellipse**, **1/2.8** as tall as it
is wide (`BUOY_SQUASH`), and it sits lower on the body: its centre is **0.08** of
the sprite height above the feet (was 0.28), so it hugs the ankles with its near
rim dipping onto the water instead of riding like a hula hoop. `BUOY_DIAM` is
now the outer **width** (1.20 x the sprite's larger dimension) rather than a
diameter.

**Both paths tilt.** The drop-in art is drawn at whatever aspect the PNG has --
`drawBuoys` now sizes each half's height from the image's **own** `getHeight()`,
so a 2.8:1 PNG yields a 2.8:1 ring (a square PNG still yields a circle). The
built-in primitive ring is squashed to match: `annulusSector` takes a `ys`
vertical scale and `halfRing` passes `BUOY_SQUASH`, so the eight sectors become
an **elliptical** annulus. Nothing about the two-pass split changed.

**Two rule corrections.**

- **Ghost** types now get **no** ring (`GHOST_TYPE`, checked with Water): they
  pass over water, so a non-hovering Ghost like Shedinja or Phantump no longer
  wears a buoy. (The *floating* Ghosts were already excluded via `FLOATER`.)
- **`BUOY_CURATED`** is a new hand-editable override for species the type/ability
  data gets wrong: `FORBID` never rings, `FORCE` always rings, FORBID wins. It is
  empty by default and is also exposed at runtime as
  `battleSceneBackground.buoyCurated`, so a tweak needs no file edit. (This is the
  hook for the user's "curated pokemon" list -- they haven't supplied the species
  yet.)

**Docs.** `assets/lifebuoys/README.md` now describes the 2.8:1 tilt, the new
centre height, the Ghost exclusion and `BUOY_CURATED`, and tells authors to draw
a wide flat PNG.

Verified under fengari: the suite is now **59/59** green (4 new checks -- a
non-hovering Ghost gets no ring; `BUOY_CURATED` FORBID/FORCE work; the art's own
aspect sets the tilt; and the primitive ring's far-half vertical extent is
exactly `rOut / 2.8`, i.e. it really is squashed). The existing buoy checks were
retargeted to a **256x91** mock PNG so they exercise the tilted path.
`background.lua` / `battle_screen.lua` are luaparse 5.1 clean; `manifest.json` +
`files.json` are JSON-valid at **2.6.0** (`files.json` still lists **21** files);
and the rebuilt `src/g9-Battle-Scene.zip` (**26** entries) inflates every listed
file **byte-identical** to this tree. The angled art and the primitive ring were
both composed against the real ocean backdrop and eye-checked (near half in
front of the legs, far half behind, no seams). In-game confirmation is still the
user's (the mod only runs in LÖVE).

**User action.** Re-export **`g9-battle-scene`** and unzip over
`mods/g9-Battle-Scene/`, then drop the approved angled PNG in as
`mods/g9-Battle-Scene/assets/lifebuoys/lifebuoy.png`.

## Gen 2 terrains: surfing and caves (v2.7.0)

**The bug.** A Gen 2 surf fight (and a Gen 2 cave fight) could miss its
`water` / `cave` backdrop. Gen 2 does not describe terrain the way Gen 1 does:
its encounter roll only ever passes `"grass"` or `"water"` -- a **cave is a
`"grass"` roll** there, with the cave/indoor fact living in the map header's
`def.environment` byte instead -- and its surf state lives in
`world.playerState` (`"surf"` / `"surf_pika"`), not in a `player.surfing` flag.
So the Gen 1-shaped reads the tag resolver used left both cases on `grass`.

**The fix (`background.lua`).** The resolver now reads both generations' own
signals:

- The encounter probe records the roll's **`ctx.environment`** beside its
  `ctx.terrain`, and now hangs on **`encounter.roll`** as well as
  `encounter.species` (the engine always calls the roll first), so a mod that
  short-circuits the species chain can no longer drop the terrain.
  `terrainTagOf(terrain, environment)` settles the cave case: a `"grass"` roll
  on a `CAVE` / `DUNGEON` / `INDOOR` / `GATE` map is `cave`.
- `inferTerrain` (the map/player fallback, and the override `tagFor` applies
  when a record says `grass`) detects surfing three ways -- Gen 1's
  `player.surfing`, Gen 2's `world.playerState`, and the water cell under the
  player (only a surfing player ever stands on one, so it is safe on land) --
  and caves via Gen 1's `CAVERN`/`CAVE` tileset + indoor test **or** Gen 2's
  `def.environment` (`CAVE` / `DUNGEON` / `INDOOR` / `GATE`).
- When a fresh record says `grass` but the map itself says water or cave, the
  map wins: that is exactly the Gen 2 cave case, where the roll and the map
  disagree and the map is right.

Everything stays defensive: the tile check is `pcall`'d and every read is
type-guarded, so a headless screen with no `world`/`map`/`player` still infers
`grass` exactly as before, and Gen 1's behaviour is unchanged.

**Verified.** The fengari suite is **67/67** green (8 new: Gen 2 surfing from
`playerState` and from the tile underfoot; Gen 2 `CAVE`/`DUNGEON`/`INDOOR`
environments -> cave with `TOWN` still grass; a Gen 2 grass roll carrying its
`CAVE` environment -> cave; a Gen 2 grass record with no environment letting
the map's cave, or surfing, win; a Gen 2 water roll outranking the map
environment; and the `encounter.roll` probe recording the terrain on its own).
The `scratch/tests/run_scene_probe_real.mjs` integration harness drives the
REAL engine `Hooks`/`Runtime` and is **5/5** green, including the case where a
higher-priority mod short-circuits `encounter.species`: the `encounter.roll`
probe still records. `background.lua` + `battle_screen.lua` are luaparse 5.1
clean;
`manifest.json` + `files.json` are JSON-valid at **2.7.0** (`files.json` still
lists **21** files); the rebuilt `src/g9-Battle-Scene.zip` inflates every
listed file byte-identical to this tree. In-game confirmation is still the
user's (the mod only runs in LÖVE).

**User action.** Re-export **`g9-battle-scene`** and unzip over
`mods/g9-Battle-Scene/`. Surf in Gold/Silver/Crystal and the fight takes the
`water` backdrop (with life rings); walk a cave and it takes `cave`.

## Life buoys follow the field terrain, not the raw tag (v2.7.1)

**The bug.** The life rings were gated on the battle's RAW resolved tag
(`if t == "water"` in both `M.draw` and `M.drawFront`), but `pickFile` does not
gallery only on the tag: when a tag has no art of its own it **falls back to the
map's terrain art** (`if #list == 0 and not TERRAIN_TAGS[t] then list =
filesFor(inferTerrain(screen)) end`). The two therefore disagree for any fight
whose tag is not literally `water` yet whose field is: most commonly a
**static/scripted wild fight** (no encounter roll behind it, so `tagFor` yields
`fated`), a class/legend encounter, or a gym-map tag. Those fights drew the
water backdrop -- borrowed from the map -- but skipped the ring pass entirely,
so a Zigzagoon standing on the ocean wore nothing.

**The fix (`background.lua`).** A new module-local `fieldTag(screen)` returns
the terrain whose art is ACTUALLY on the field: the cached tag when it has art
of its own (or is itself a terrain tag), otherwise `inferTerrain(screen)` -- the
very fallback `pickFile` uses. Both `M.draw`'s far-half pass and `M.drawFront`'s
near-half pass now read `fieldTag(screen) == "water"` instead of the raw tag.
`M.draw` still uses the raw tag for `pickFile`, so backdrop selection is
unchanged; only the ring gate moved. One more data correction rode along:
`typeSet` now also reads `src.curTypes`, Gen 1's own name for a mon's live type
list (Gen 2 uses `types`), so a mon can be rung/spared from itself even with no
reachable dex record.

**Verified.** The fengari suite is **70/70** green (3 new: a water fight whose
TAG falls back to the map terrain still rings; a tag with its own art does not
ring even while the player surfs; a mon's own `curTypes` ring/spare it with the
record missing). `background.lua` is luaparse 5.1 clean; `manifest.json` +
`files.json` are JSON-valid at **2.7.1** (`files.json` still lists **21**
files); the rebuilt `src/g9-Battle-Scene.zip` (**26** entries) inflates every
listed file byte-identical to this tree. In-game confirmation is still the
user's (the mod only runs in LÖVE).

**User action.** Re-export **`g9-battle-scene`** and unzip over
`mods/g9-Battle-Scene/`.

## A special boss announces itself at battle start (v2.8.0)

**What it does.** When a WILD boss turns out to be a special Pokemon -- SPECIAL
BOSSES `TERA` / `DYNAMAX` / `MEGA` / `ALL` -- the battle's **opening F-box
line** now names the raid before anything else, e.g.:

- `You have found a Tera FIRE Charizard raid!`
- `You have found a Mega Charizard raid!`
- `You have found a Dynamax Snorlax raid!`
- `You have found a Gigantamax Pikachu raid!`

**How it works.** `special_boss.lua` now stamps the applied result on the
battle as `g9BossKind` (the same table `applyKind` already returns --
`{ kind = "tera"|"mega"|"dynamax"|"gigantamax", detail = ... }`, where a Tera's
`detail` is its type id), and exports `bossAnnouncement(battle, name)`, which
builds the line from it and returns `nil` when the battle has no applied
property. `battle_screen.lua`'s `buildIntroSequence` reads that lazily (the
same way the screen already reads the module) and, when there is a line,
prepends a plain `"msg"` narration beat -- so the announcement is the very first
thing the F box shows, and A/B advances it into the normal "Wild X appeared!"
beat. A Tera's type id is upper-cased and any `_TYPE` suffix dropped, so a
Gen 1 `"Fire"` and a Gen 2 `"WATER_TYPE"` both read cleanly. An ordinary boss,
a trainer, or SPECIAL BOSSES = `normal` produces no line, so every other
fight's intro is byte-for-byte what it was.

**Verified.** The fengari suite for `special_boss.lua`
(`scratch/tests/special_boss_test.lua` + `run_special_boss.mjs`) is **41/41**
green (8 new: the Tera/Mega/Dynamax/Gigantamax wordings, type-id normalisation,
the no-property/nameless cases, the stamp `applyWildBoss` writes, and the Tera
that declines to Dynamax announcing Dynamax). `special_boss.lua`,
`battle_screen.lua` and `options.lua` are luaparse 5.1 clean; the other scene
suites are unchanged and green (background 70/70, guard 15/15, prize 19/19,
forced switch 42/42, real-engine probe 5/5). `manifest.json` + `files.json` are
JSON-valid at **2.8.0** (`files.json` still lists **21** files); the rebuilt
`src/g9-Battle-Scene.zip` (**26** entries) inflates every listed file
byte-identical to this tree. In-game confirmation is still the user's (the mod
only runs in LÖVE).

**User action.** Re-export **`g9-battle-scene`** and unzip over
`mods/g9-Battle-Scene/`.

## A wild raid boss's sprite gets its declared gimmick (v2.8.1)

**What it fixes.** A wild Tera raid boss drew ordinary while the F box announced
it as Tera. `g9-battle-sprites` paints its crystal film / Dynamax cloud from the
LIVE tera/dynamax state, and this scene deliberately never activates a wild
boss's gimmick (see the SPECIAL BOSSES section above), so there was no live
state to read -- the announcement and the sprite came from two different places.

**How it works.** `pushBattleBattleScreen` now copies the stamp it already
writes -- `battle.g9BossKind` (`{ kind, detail }`) -- onto the boss battler as
`g9RaidGimmick`, right after `Screen.new`. `resolveSprite` forwards it on the
`battle.mon_pic` seam as `ctx.boss = true` (boss slot only) and
`ctx.bossGimmick = battler.g9RaidGimmick`, which `g9-battle-sprites` (v3.0.1+)
paints when its own live read is empty. Visual only: no gimmick is activated, the
mon is untouched, a real live transformation still wins, and a screen that sends
no declaration (or an older sprite mod) behaves exactly as before.

**Verified.** `battle_screen.lua` and `special_boss.lua` are luaparse 5.1 clean.
The `boss_announce` suite (which loads the REAL `battle_screen.lua`) is **16/16**
green, including 3 new checks that drive the real `resolveSprite` and read the
`battle.mon_pic` ctx it raises -- a boss slot carries `boss = true` and the exact
`g9RaidGimmick` table, a non-boss slot carries neither, and a declared Dynamax
carries its kind. The other scene suites are unchanged and green (special boss
41/41, background 70/70, guard 15/15, prize 19/19, forced switch 42/42,
real-engine probe 5/5). The sprite mod's own suites cover the consumption
(tera film 52/52, dynamax cloud 46/46). `manifest.json` + `files.json` are
JSON-valid at **2.8.1** (`files.json` still lists **21** files); the rebuilt
`src/g9-Battle-Scene.zip` (**26** entries) inflates every listed file
byte-identical to this tree. In-game confirmation is still the user's (the mod
only runs in LÖVE).

**User action.** Re-export **`g9-battle-scene`** and unzip over
`mods/g9-Battle-Scene/`. Also re-export **`g9-battle-sprites`** (v3.0.1) -- the
declared film/cloud only appears with the matching sprite-mod build.

## The background follows each fight, not the session's first one (v2.9.0)

**The bug (user report).** The backdrop was sticking to the first terrain the
play session rolled: a session that opened in the grass kept drawing `grass`
even on the water, and one that opened surfing kept drawing `water` even on
the grass. `M.tagFor` preferred a recorded encounter roll over the map the
fight was happening on, and that record was never consumed, so a leftover roll
from an earlier battle could outrank the live terrain for the 60 s freshness
window -- and a water/cave record was returned unconditionally, so the map
could not override it.

**The fix (`background.lua`).**
1. `M.tagFor` resolves the live terrain first and, for a wild battle,
   **returns it outright when it is `water` or `cave`** -- where the fight is
   right now beats anything an old roll says. The roll is only consulted on a
   grass-looking map, where it refines the answer (fishing from the shore ->
   water; a Gen 2 `"grass"` roll on a cave map -> cave) and a plain `"grass"`
   roll is just grass.
2. The record is **spent by the one battle it belongs to**: `tagFor` takes
   `lastEncounter` and immediately clears it, so a leftover from a previous
   fight can never reach the next one. A battle with no roll behind it (and not
   on water/cave) is a scripted/static fight -> `fated`, exactly as documented.
3. The per-Screen tag/file cache is keyed on a roll counter (`rollSeq`, bumped
   by every recorded roll), so a Screen reused across two fights -- or one whose
   battle changed under it -- re-resolves for the new battle instead of handing
   back the first one's tag, while the per-frame draw still costs a single
   resolver call. `M.draw`'s picked file is cached under the same key (a
   remembered `false`, "no art", is a valid entry). The old
   `elseif probeInstalled then return "fated"` branch a stale record used to
   reach is gone -- the spend above replaced it. The file-header "HOW A TAG IS
   CHOSEN" paragraph, the priority list above and the `M.tagFor` header comment
   were rewritten to match.

**Verified.** `scratch/tests/scene_bg_session.lua` + `run_scene_bg_session.mjs`
(**7/7**) drive the REAL `Hooks.lua` / `Runtime.lua` and the shipped
`background.lua` through whole sessions: grass->water->cave and water->grass
with a fresh Screen per battle, a single Screen reused across two fights, a
build with `now()==0`, a spent roll that must not leak onto a later roll-less
grass fight (-> `fated`), a roll-less fight on water (-> `water`, live terrain
wins), and fishing from the shore (-> `water`). The main suite is **70/70**
(the stale-record check again expects `fated`; the two buoy checks now reach
their "tag with no art / tag with art" cases through a legendary, since a
terrain fight no longer resolves to `fated` on the water). `background.lua`
is luaparse 5.1 clean and loads under fengari. `manifest.json` +
`files.json` are `2.8.1 -> 2.9.0` (`files.json` still lists **21** files); the
rebuilt `src/g9-Battle-Scene.zip` (**26** entries) inflates every listed file
byte-identical to this tree.

**User action.** Re-export **`g9-battle-scene`** only (v2.9.0) and unzip over
`mods/g9-Battle-Scene/`; the engine / sample / sprite builds are unchanged.

## The backdrop's feet sit on the F/E box's middle (v3.0.0)

**The change (user request).** The backdrop used to be drawn top-left at
`(0, 0)`, so the ground's own base ran all the way down the field and a source
taller than 16:9 had its **foreground** -- the ground the mons stand on --
clipped at the bottom edge. `background.lua`'s `M.draw` now anchors the image
by its **bottom edge** (its *feet*): the scaled image height is subtracted from
the anchor, so the feet are planted on the **middle of the F/E box** (the
bottom message + FIGHT/BAG/PKMN/RUN band, whose own `BOTTOM_H` is 6.5 tiles =
52 design px, flush with the field's bottom edge -> its middle is design
**y = 154**; `GROUND_FEET_Y = VH - BOTTOM_H*8/2`). The scale is unchanged
(`320 / imageWidth`), so a 16:9 source's top edge now sits at **y = -26** (just
past the field's top) and a **taller** source keeps its foreground visible and
clips the scenery at the **top** instead. `BOTTOM_H` is duplicated in
`background.lua` with a comment to keep it in step with `battle_screen.lua`'s.

**Verified.** `scratch/tests/scene_background_test.lua` +
`run_scene_background.mjs` is now **71/71**: the draw check asserts the foot
line (`y == 154 - 270*(320/480)`, i.e. -26 for a 480x270 source), and a new
check proves a **taller** (4:3 320x240) source draws at `y = 154 - 240` so its
ground stays on screen. All other scene suites are green
(`scene_bg_session` 7/7, `scene_probe_real` 5/5, `forced_switch` 42/42,
`scene_guard` 15/15, `scene_prize` 19/19, `special_boss` 41/41,
`sprites_anchor` 23/23, `sample_verify` 135/135). `background.lua` is luaparse
5.1 clean.

## A raid boss's announcement replaces the wild message (v3.0.0)

**The change (user request).** A SPECIAL BOSS's raid line ("You have found a
Tera FIRE Charizard raid!") used to be its own leading narration beat, so a
raid boss showed the raid line and *then* the native "Wild X appeared!" line
for the same mon -- two messages for one entrance. `battle_screen.lua`'s
`Screen:buildIntroSequence` now folds the raid line into the first (and, for a
boss fight, only) enemy's own appearing beat: the `fade` beat's text IS the
raid line, shown while the boss fades in, and "Wild X appeared!" never renders
for that mon. An ordinary boss, or `SPECIAL BOSSES = normal`, still yields no
line, so every other fight's intro is byte-for-byte what it was. A **trainer**
fight (which `special_boss.lua` never touches, and which has no "Wild X
appeared!" to replace) keeps the raid line as a leading `msg` beat, unchanged.
The `WILD` sequence comment above `buildIntroSequence` documents the fold.

**Verified.** `scratch/tests/boss_announce_test.lua` + `run_boss_announce.mjs`
is now **17/17**: the Tera test asserts a single beat (`#seq == 1`) whose kind
is `fade` and whose text is the raid line, and a new test locks a trainer fight
keeping a (hypothetical) raid line as a leading `msg` beat before "wants to
battle!". `battle_screen.lua` is luaparse 5.1 clean and loads under fengari.

**User action.** Re-export **`g9-battle-scene`** only (v3.0.0) and unzip over
`mods/g9-Battle-Scene/`; the engine / sample / sprite builds are unchanged.

## The backdrop reaches the roof, and follows every battle (v3.0.1)

**The two changes (user requests).** (1) *"match roof of background to roof of
screen, we are getting white space over background."* (2) *"background is STILL
getting fixed to either water/grass/whatever based on the first environment
triggered ... you are preserving/storing this background statically."*

**1. The backdrop's ROOF now meets the screen's roof.** v3.0.0 had anchored the
image by its **bottom edge** at the F/E box's middle, which for any source
**broader** than the 320x154 band (i.e. wider than ~2.08:1) left the image's top
edge *below* the screen's top edge -- a strip of the white field showed above it.
`background.lua`'s `M.draw` now hangs the image from the **top edge instead**
and scales it to **cover** the band `[0 .. GROUND_FEET_Y]`:
`s = max(VW/imageWidth, GROUND_FEET_Y/imageHeight)`, drawn at
`x = (VW - imageWidth*s)/2, y = 0`. So the roof is always flush with the
screen's roof (no white above it, for any aspect), and a source broad enough to
reach the F/E box lands its **feet exactly on that middle line** (design y=154)
with its sides centred and cropped; a narrower/taller (16:9-or-taller) source
keeps its full width and its lower overflow simply runs behind the F/E box.
`GROUND_FEET_Y` is unchanged (`VH - BOTTOM_H*8/2` = 154).

**2. The backdrop no longer sticks to the session's first environment.** The
tag ALWAYS re-resolved for each new battle (detection was fine) but the picked
**file** did not: `cachedTag` sets `screen.__g9bgSeq = rollSeq` when it
re-resolves a reused Screen, and `M.draw` tests exactly that seq before reusing
`screen.__g9bgFile` -- so on the new battle's first frame the seq already looked
"current" beside the *previous* battle's file, and the first backdrop stayed for
the whole session. `cachedTag` now clears `screen.__g9bgFile` on every
re-resolve, so the file is always re-picked beside the tag it belongs to (the
tag itself keeps re-resolving once per battle, keyed on `rollSeq`).

**Verified.** `scratch/tests/scene_background_test.lua` + `run_scene_background.mjs`
is now **73/73**: the draw check asserts the roof anchor (`y == 0`) and the
covering scale, a new check proves a broader (480x180) source is zoomed to the
band (`sx == 154/180`) with its feet on y=154 and centred side-crop, the 4:3
check now proves a taller source keeps scale 1 and runs behind the box, and a
new **"a reused Screen re-resolves its backdrop for each new battle"** check
fails against the pre-fix source (confirmed by running the harness on the
mutation) and passes now. `scratch/tests/scene_bg_session.lua` +
`run_scene_bg_session.mjs` (**7/7**) drives the REAL engine hooks through whole
sessions and its reused-Screen case now asserts the picked **file** as well as
the tag. All other scene suites are green (`scene_probe_real` 5/5,
`forced_switch` 42/42, `scene_guard` 15/15, `scene_prize` 19/19,
`special_boss` 41/41, `sprites_anchor` 23/23, `sample_verify` 135/135).
`background.lua` is luaparse 5.1 clean; `manifest.json` + `files.json` are
JSON-valid at **3.0.1** (`files.json` still lists 21 files).

**User action.** Re-export **`g9-battle-scene`** only (v3.0.1) and unzip over
`mods/g9-Battle-Scene/`; the engine / sample / sprite builds are unchanged.

## Transform / Illusion now show here: the scene reads the display species (v3.0.5)

`g9-battle-engine` 4.4.2 records a Transformer's display species on the MON
(`mon.__g9DisplaySpecies`) and its display name as `mon.__g9DisplayName`, because
this screen never draws through `BattleState:drawPicsLayer` — it resolves every
pic itself in `Screen:resolveSprite` and prints names with `displayName(mon)`.

`resolveSprite` now resolves the species it draws as
`shown = battler.__g9DisplaySpecies or mon.__g9DisplaySpecies or mon.species`,
uses `shown` for `data.pokemon[shown]` and for the `species` field of BOTH seams
(`pokemon.sprite` and `battle.mon_pic`), and raises those seams with
`mon.species` temporarily pointed at `shown` — the sprite pack keys its sheet off
`mon.species` (`monStem` -> `resolveStem(mon.species)`), so the swap is what makes
it bake the target's frames. A new `withShownSpecies` guard restores the real
species immediately, on the error path too, so the mon is never left mutated.
`displayName(mon)` prefers `mon.__g9DisplayName`, so the HUD and every scene
message (intro, "sent out", switch, faint reasons) follow the override.

**Nothing else changes.** A mon with no display override has
`mon.__g9DisplaySpecies == nil`, so `shown` is its real species and the swap is a
no-op — byte-for-byte the previous behaviour. `g9-battle-sprites` is unchanged:
this screen hands it the display species, and its own paths follow.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`; the engine harness
boots 146/146 and `scratch/sim/probe_transforms.lua` evaluates this screen's own
`displayName` / `shown` expressions verbatim against a scene-shaped
`{ mon = ... }` wrapper (all green), including the mon-field clear on
switch-out / battle end. LÖVE cannot run in the preview, so in-game confirmation
is the user's.

**User action.** Re-export **`g9-battle-scene`** (v3.0.5) and **`g9-battle-engine`**
(v4.4.2); `g9-battle-sprites` is unchanged.

## Gen-1 turns now resolve one action at a time (v3.0.6)

`g9-battle-engine` 4.4.3 splits the Gen-1 turn into `beginTurnActionsForGen1` /
`resolveNextActionForGen1`, and this screen now drives them: `Combat.beginTurn`
starts the turn and `Combat.resolveNextAction` runs ONE actor per pass. Before
this the screen asked `combat.resolveTurn` for the whole turn in one call, so
every actor's `battle:useMove` ran back to back and a Transform's
`TRANSFORM_EFFECT` (sprite + stat replacement) was committed during the first
action -- before that action's animation had even been shown. The message order
was already correct; the state application was not.

`Screen:advanceResolving` records `self.movesBegun` / `self.stepwise` alongside
`movesResolved`: the first pass runs the existing turn-head reset, gimmick
emission and `Combat.beginTurn`, then each following pass resolves one action,
queues that action's events and recurses to display them until the order is
exhausted -- then the faint EXP award runs and the turn closes exactly as before.
The former inline EXP block is now `Screen:awardFaintExp(events)`, shared by both
paths.

**Gen 2 is untouched.** `native.lua` installs `N.beginTurn` / `N.resolveNextAction`
in its Gen-1 arm only, so on Gen 2 `Combat.beginTurn` returns false and
`advanceResolving` falls back to the original whole-turn `resolveTurn` batch --
byte-for-byte the previous behaviour.

**Verified.** `luaparse 5.1` clean on `native.lua`, `combat.lua`, `battle_screen.lua`.
`scratch/sim/probe_gen1_preturn.lua` (which loads this screen's real `native.lua`)
passes: `N.beginTurn` true (backed by the engine) and `N.resolveNextAction`
returns `(events, done)` with the cursor advancing, skipping a dead actor, and
firing the end-of-turn block exactly once on `done`; the no-begin fallback clears
flinches once and runs the batch. The engine harness is 146/146. LÖVE cannot run
in the preview, so in-game confirmation is the user's.

**User action.** Re-export **`g9-battle-scene`** (v3.0.6) and **`g9-battle-engine`**
(v4.4.3); `g9-battle-sprites` is unchanged.

## Input pacing: a 0.7s commit window and resolving beat holds (v3.0.8)

A mash used to be able to walk FIGHT -> move -> resolve -> the next battler's
menu inside a second, because the screen is a per-frame keyboard state machine
with no debounce of its own: a menu commit that changed `self.phase` left the
very next frame free to read the same physical press again
(`suppressInputFrame` only ever guarded a native sub-menu popping back). Three
constants in `battle_screen.lua` now pace it, per the user's spec:

- `INPUT_DELAY = 0.7` -- after any A/B **commit**, every *selection* phase
  (`actionMenu`, `moveSelect`, `targetSelect`, `swapSelect`, `gimmickSelect`,
  the two-choice prompt) is frozen for 0.7s. Directional input is deliberately
  exempt: hovering a menu is instant and never arms the window. It is armed
  `Screen:enterActionMenu` (so "turn resolve > 0.7 > action again" and the
  per-battler gap in a multi-battler turn are covered) and again at the tail of
  `Screen:update`, keyed off the phase the press **left** rather than the phase
  it entered -- so the last battler's move pick, which jumps straight into
  `resolving`, delays that first resolving beat too.
- `BEAT_HOLD_TEXT = BEAT_HOLD_MOVE = 0.3` -- `Screen:advanceResolving` stamps
  each text beat with a minimum display time before the next A/B may advance
  it. A move event whose animation actually started gets no extra hold (the
  animation paces itself); a move with `moveAnimations` off gets 0.3s, the
  user's "animation time defaults to 0.3 seconds".
- `HP_ANIM_DURATION = 0.4` -- the HP chase is now a fixed 0.4s wall-clock
  interpolation (`armHpAnim` records `hpAnimFrom`, `stepHpAnim(dt)` walks
  start->target) instead of the cart's frame-rate step, the user's "0.4 seconds
  duration of this depletion animation". A press no longer snaps it early.

A move animation now owns its whole duration too: `Screen:updateResolving` no
longer clears `self.moveAnim` on a press; only `MOVE_ANIM_SAFETY = 5` seconds
(a malformed script that never reports done) may be skipped, and `Screen:update`
accumulates `self.moveAnimTime` per animation. The ball/catch animation is
unaffected (it plays in a non-`resolving` phase and still resolves through its
own `onFinish`).

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`; a new fengari harness
(`scratch/tests/input_pacing_test.lua`, 30 checks) drives the real
`Screen:update` with a fake input and asserts the lock freezes/gates/expires,
that direction never arms it, the 0.3/0.4 holds, the animation-is-not-skipped
rule and the safety valve; the boss-announce harness is 17/17. LÖVE cannot run
in the preview, so in-game confirmation is the user's.

**User action.** Re-export **`g9-battle-scene`** (v3.0.8); `g9-battle-engine`
and `g9-battle-sprites` are unchanged.

## Input pacing revised: commit-only 0.3s delays (v3.0.9)

The user tightened the v3.0.8 pacing: *"reduce all waits to 0.3 and if the
layout + move requires selection, we only put delay after selection of target
is confirmed, no delay between fight > move selection > selecting target, only
after target is selected / no target selected but move was selected. Cancel to
return to previous menu mustn't trigger delay; only cancel that triggers delay
is when pressed to pass combat messages like fainted pokemon or effect message
or item activation message."*

So the blanket menu-commit window is gone. All waits are now 0.3s and the
commit window is armed **only where an action is actually queued**:

- `INPUT_DELAY = 0.3` (was 0.7). `Screen:enterActionMenu` no longer arms it, and
  the tail-of-`Screen:update` arming block (keyed off `phaseBefore`) is removed.
  Opening the action box, walking FIGHT -> move list, opening the target picker
  and hovering all add **no** delay.
- The window is now armed inside **`Screen:queueAction`** (a move whose target
  was just confirmed, or a move that needed no picker / had a single candidate /
  was a spread or no-choice move) and **`Screen:queueSwapAction`** (a confirmed
  positional swap), plus the FORMS arm path in `Screen:updateGimmickSelect`.
  Because `queueAction` runs *before* `advanceSlotOrResolve`, the 0.3s still
  covers the next battler's action box in a multi-battler turn and the first
  resolving beat after the last pick.
- A **B cancel** -- back out of `moveSelect`/`targetSelect`/`swapSelect`/FORMS
  to a previous menu -- queues nothing, arms nothing, and is instant. The only
  A/B that still waits is the one that **passes a combat message** during
  `resolving` (fainted / effect / item-activation lines), via the unchanged
  `beatHold`.
- `BEAT_HOLD_TEXT = BEAT_HOLD_MOVE = 0.3` (unchanged), `HP_ANIM_DURATION = 0.3`
  (was 0.4). `MOVE_ANIM_SAFETY = 5` is a safety valve, not a wait.

The v3.0.8 section above is **superseded** on the arming points, the 0.7s value
and the 0.4s HP drain; its beat-hold and move-animation rules still hold.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua` (7,571 lines); the
fengari harness (`scratch/tests/input_pacing_test.lua`) rewritten for the new
rules is **52/52** -- `enterActionMenu`/FIGHT/opening-the-picker add no delay,
opening the picker leaves the lock at 0 while the target confirm arms 0.3, a
no-choice or single-candidate move arms 0.3 on its own selection, every B
cancel (move/target/swap/FORMS) leaves the lock at 0, a swap confirm arms 0.3,
a running window still freezes the menu and expires, resolving's commit+beat
holds both gate the acknowledge press, and the 0.3s HP drain cannot be mashed.
Boss-announce harness stays **17/17**.

**User action.** Re-export **`g9-battle-scene`** (v3.0.9); `g9-battle-engine`
and `g9-battle-sprites` are unchanged.

## BAG opens the real bag: combat-usable items (v3.1.0)

The user: *"bag should open bag, it's just saying 'no pokeball to throw' which
is undesired as some items can be used in combat for healing pokemon."*  The
in-battle BAG had been a ball-only roster, so every potion / cure / revive was
unreachable mid-fight.  It now opens each generation's **real bag** and applies
every combat-usable item through the engine's own item knowledge.

**Gen 1 -- the cart's own `BagMenu`.** `native.lua`'s `N.openBag` no longer
builds a ball-only `ListMenu`; it pushes `Screens.push(game, "BagMenu", {battle=...})`,
the same menu the field uses.  That menu reads `game.data.items`, runs
`src.inventory.ItemEffects` itself, opens the real `PartyMenu` for a targeted
item, animates its own HP fill and prints every line.  When it is done it hands
the spent turn back through `battle:itemUsed(messages, opts)` (a non-ball) or
`battle:throwBall(id)` (a ball).  Those are *native* `BattleState` methods that
would drive the native battle loop against a different battle object, so
`N.openBag` shadows them **on this scene's own model instance only** (the same
instance-only override the model already uses for `state:useMove` /
`state:statusGate`): `battle.itemUsed -> screen:onBagItemUsed(messages, opts)`
and `battle.throwBall -> screen:throwBall(id, true)`.

- `Screen:throwBall(ballId, alreadySpent)` gained its second parameter: the
  Gen 1 `BagMenu` runs `consume()` on the ball *before* it calls
  `battle:throwBall`, so `alreadySpent` stops the screen spending a second copy.
  The screen's own paths (the Gen 2 pack) pass `false`.
- `Screen:openBag` snapshots each party mon's HP into `self.bagHpBefore`, so an
  item used out of the cart's bag can animate this screen's HP bar from the
  value the player was looking at when the bag opened.

**Gen 2 -- the pack's own battle arm.** The `Gen2PackMenu` was already pushed
(`battle=true`), but `Screen:useItem` only knew how to throw balls.  It now
routes a ball to `throwBall` and everything else to the new
`Screen:useItemGen2(itemId, def)`, which mirrors `src/ui/gen2/BattleState.lua`'s
own `BattleState:useItem` and never re-derives an effect or a refusal line:

- `Battle.X_ITEM_STATS` / `Battle.SUBSTATUS_ITEMS` (X ATTACK ... X ACCURACY,
  DIRE HIT, GUARD SPEC): the BATTLE applies the stage or substatus bit via
  `self.battle:useBattleItem(itemId)`; a refused re-use costs neither the item
  nor the turn.
- `battleMenu == "ITEMMENU_NOUSE"` (e.g. RARE CANDY): refused with *"That isn't
  going to help here."* -- the battle pack has no field-menu filter, so this
  gate has to sit in the scene, or a candy would level a mon mid-fight.
- `BITTER_BERRY`: `Screen:useBitterBerry` clears the active mon's confusion
  (refuses, spending nothing, if it is not confused).
- Everything else with an `ItemEffects.partyAction` (the potion line, the
  drinks, the status cures and their berries, REVIVE / MAX REVIVE, the
  ETHER / ELIXER family): `Screen:openItemTargetPicker` pushes the real
  `Gen2PartyMenu` (`prompt="useItem", battle=true`); the ETHER pair (`RESTORE_PP`
  with no `each`) opens `Gen2MoveDeleter` first; `Screen:applyPartyItem` then
  runs `ItemEffects.useOnMon` / `usePpItem`, consumes a copy via `N.consumeItem`,
  clears a `$ff`-mask healer's confusion on the active mon
  (`FULL_MASK_HEALERS`), and animates the party menu's own HP fill via
  `menu:showItemResult`.
- Backing out of the party list returns to the pack with nothing spent (the
  routine's `.SelectMon` carry path).

**Turn + beat plumbing.** An item spends the slot's action exactly as a move
does.  Both generations funnel into `Screen:queueItemResult(messages, target,
before)`, which:
- appends any screen-owed lines to `self.itemMessages`,
- seeds `self.preResolveShownHp[target]` from the pre-item HP, then
- calls `self:advanceSlotOrResolve()` (the same path a missed ball takes).

`Screen:beginResolving` was extended: after `syncShownHp()` it restores
`self.shownHp` from `preResolveShownHp` (so a healed bar animates across the
pass instead of snapping), and it prepends `itemMessages` as synthetic
`{text=..., g9SceneHp=snapshotHp()}` beats to `self.pendingEvents` **before**
`advanceResolving()`, so the item's line and HP fill show ahead of the enemy's
action.  (Most Gen 1 lines are already printed by the cart's BagMenu; this is
the belt-and-braces arm for the ones that are not.)

**Verified.** `luaparse 5.1` clean on `battle_screen.lua` (7,860 lines) and
`native.lua`; a new fengari harness (`scratch/tests/item_use_test.lua`, 54
checks) covers the Gen 1 delegation + HP snapshot, the Gen 2 pack push, ball vs.
non-ball routing, the multi-foe ball refusal, battle-stat items (use / consume /
queue and the refusal), the `ITEMMENU_NOUSE` gate, BITTER BERRY routing, the
party-item picker, apply success/refusal, the FULL_HEAL confusion clear,
`queueItemResult`, `onBagItemUsed`, the `beginResolving` injection and the
`alreadySpent` ball.  The full suite stays green: input-pacing **52/52**,
boss-announce **17/17**, special-boss **41/41**, forced-switch **42/42**,
scene-guard **15/15**, scene-probe **5/5**, background **73/73**, bg-session
**7/7**, scene-prize **19/19**, sample-verify **93/93**.

**User action.** Re-export **`g9-battle-scene`** (v3.1.0); `g9-battle-engine`
and `g9-battle-sprites` are unchanged.

## FANTASY COMBAT -- the modernized combat GUI (v3.2.0; box model v3.3.0; cursor v3.4.0)

A new on/off **FANTASY COMBAT** option replaces the bottom band with a
translucent panel GUI in the style of FINAL FANTASY XII: THE ZODIAC AGE -- the
same look the `g9-gui` mod gives the overworld menus and party/status screens.
OFF (the default) is byte-for-byte the native tile-font F/E box this scene has
always drawn; ON swaps in the new surfaces below.  The whole feature is one
file (`fantasy_combat.lua`) plus a handful of guarded seams in
`battle_screen.lua`, so nothing here can change a battle while the option is
off.

**Ownership split.** `fantasy_combat.lua` owns only the LOOK -- it draws
panels, bars and text from a plain data table.  `battle_screen.lua` still owns
what is on screen and when: `Screen:fantasyData()` reads the live screen state
(the party roster by SLOT, the current phase's cursor/list/menu state, and the
same `displayName`/`maxHpOf`/`expFraction`/`statusTag` helpers the native
readouts use) into that table, and `Screen:drawFantasyBottom()` hands it to
`Fantasy.draw`.  Because the fantasy list and the native readouts read the same
helpers, they can never disagree.

**Box model (v3.3.0).** Native authors the bottom band in the 320x180 design
space, so design y 128..180 is canvas y 384..540 and the 28/12-tile F/E split
is canvas x 0..672 / 672..960.  The party list takes the left (0,384,658x156)
and box E the right (672,384,288x156) -- E really does keep its ORIGINAL
place.  A first cut of this feature wrapped messages in F first (full-band
during intro/over, E's spot during resolving); the round that followed the
user's clip collapsed that: **every message the battle speaks, in every
phase, is drawn in box E's own rect and nowhere else.**  There is no
full-band message panel and no left-wide narration any more.

- **intro / over / resolving narration** -- the line is drawn in E, wrapped
  and auto-shrunk to fit E's own border, with an accent rule down its left
  edge.  The party list is untouched beside it.
- **prompt** -- the question AND both choices live inside E (question wrapped
  under a `RESPONSE` header, choices under it).
- **action menu / move list / FORMS picker** -- drawn in E; the party list
  stays visible beside them.
- **a refusal / failed-item line** can be live at the same time as the action
  menu: it takes the header's place at the top of E so the menu still fits.

`F.sanitize` scrubs the engine's `{PROMPT}`/`{DONE}` control tokens (and any
truly standalone `prompt` word) out of every string the panels print, the same
scrub the native tile-font `drawWrapped` does -- without it a flinched mon read
`... flinched!{PROMPT}` on screen.

**Selection cursor (v3.4.0).** Every menu row -- the action menu (list and
grid), the move list, the FORMS picker, the prompt's two choices -- marks its
cursor through ONE helper, `F.selectCursor`, so the four menus can no longer
drift apart.  It draws the lit row bar plus the double chevron, and nothing
else: a brighter 2px vertical accent bar used to sit at the lit row's left
edge, but at this size the bar and the chevron's own edge fused into a single
blob that read as a stray line stuck to the arrow (g9-gui's roster dropped the
same bar for the same reason).  The chevron is now centred on the label's own
line box -- which is also the bar's centre, and therefore the middle of the
row -- instead of the old ad-hoc `y + 1`/`y + 2`/`y + 3` offsets that left it
hanging about 6px above the text at Saira's metrics (the bar was already
centred; only the chevron was not).  And it is held a fixed `CURSOR_GAP` (6px)
clear of the label, so no amount of the chevron's pulse can put its tip on the
first glyph -- it used to reach ~2px INTO the first letter of the selected
option.  The bar's right edge is what the callers pass (`right`), and the bar
grows leftwards to enclose the cursor, so moving the cursor can never move the
text; the bar's height is fitted to the row pitch (`min(line height + 6,
pitch - 6)`), because Saira's line box is 1.57x its size and an unfitted bar
overlapped the neighbouring row's bar in the tight list/grid rhythms.
`F.selectRow` is gone -- it had exactly these three callers.

**The party list -- four fixed individual rows.** Each row is its OWN small
rounded panel (no corner brackets on a row -- `g9-gui` reserves those for a
window), laid out at FIXED slot positions `y = 388 + (i-1)*38`, so:
top row = on-field ally 1, then 2, 3, 4.  A slot draws **nothing at all**
unless a Pokemon is actually standing in it -- absent slots leave their band of
the list empty and the rows below do NOT slide up, so the list never re-flows
and always reads as "placement 1..4".  Each present row reads left to right:
name, a dim `HP` label, an HP bar with `current/max` centred inside it, `Lv N`,
a dim `EXP` label, a deliberately SHORTER exp bar with no number, a dim `EFF`
label, then the major status word (Paralyzed, Burned, Frozen, Asleep, Poisoned,
Badly Pois., Fainted).  The row being commanded this turn gets the lit fill and
the bright border.  A Pokemon only appears in the list once its send-out has
landed (`playerRevealed[slot]`, the same flag the sprite/HUD use).  Fainted
mons dim their name.  The ally sprites lose their over-the-head HP/exp readout entirely
-- `drawContent`'s HUD pass skips `drawGuiBox` for the player side when the
option is on, and fills `hudMark[battler]` from the sprite itself
(`spriteAnchor`) instead, so the target/swap arrows and floating damage numbers
still land on the mon.  Enemy readouts keep their native boxes (the option
removes only the ALLY ones).

**Move readout.** While a move is being chosen or a target picked, a floating
panel over the top-left of the field carries the move's name and `PP cur/max`,
`PWR` (or `--` for a status move), `ACC` (or `--`) and `EFF` -- the rider word
(Paralyze / Burn / Freeze / Sleep / Flinch / Confuse / Taunt / ...) derived
from whatever the registered move record carries (`status`, `secondary.status`,
or the effect tag).

**Target arrow.** `drawTargetMark` and `drawSwapMark` call
`Fantasy.drawTargetArrow` when the option is on: a translucent accent lozenge
over a downward chevron, drawn from vector geometry so it is identical on both
generations.  The swap cue's OWNER keeps its hollow-outline form and the
TARGET its filled form, exactly the pair the tile glyph drew.  It reads
`hudMark` (design px) and multiplies by DS itself, and floors so the whole
pointer stays on-canvas for a mon whose head sits near the top.

**Geometry + fonts.** `battle_screen.lua` authors the field in a 320x180 design
space drawn through one `scale(DS)` transform (DS=3).  The scene calls
`F.draw` from INSIDE that transform, so `F.draw` wraps its own draw in
`scale(1/DS)` -- canvas pixels land on the canvas 1:1 and text stays at canvas
resolution instead of being rendered at 1/3 size and blown back up.  The Saira
Regular + SemiBold cuts (the face `g9-gui` uses; SIL OFL 1.1, `assets/fonts/`)
are vendored into this mod and read through the mod's own sandboxed reader; if
they cannot be opened the module falls back to love's built-in font, so a
missing asset can never take a battle down.

**Verified.** `luaparse 5.1` clean on `fantasy_combat.lua`, `options.lua`,
`main.lua` and `battle_screen.lua`; a fengari harness
(`scratch/tests/fantasy_combat_test.lua`, **61/61**) covers the option read,
the font fallback, `F.sanitize` stripping `{PROMPT}`/`{DONE}`/`prompt`, the
four FIXED individual party row panels (an empty slot drawing no panel and
leaving no gap-filling row), the HP number staying inside its bar, `LV`/`EXP`/
`EFF` labels, `exp bar shorter than HP bar`, EVERY message source resolving to
box E (intro/over/resolving/refusal) with no full-band panel anywhere, the move
list + readout, the prompt entirely in E, the FORMS picker, the filled/hollow
arrows staying on-canvas, and `moveEffect`.  A canvas render harness
(`scratch/tests/render_fantasy_combined.mjs`) draws seven phases at 960x540 with
the real module and was **vision-checked** for each: 4 separate row panels with
all fields aligned and nothing crossing a border, every message panel sitting in
E's own column with the party list untouched beside it, the move readout fully
on-screen, and both arrows distinct and on the field.  A second canvas harness
(`scratch/tests/render_fantasy_zoom.mjs`) crops box E and upscales it 3x, and
every cursor (action grid, action list, move list, FORMS, prompt) was
pixel-checked and vision-confirmed to carry NO vertical accent bar, to sit
centred on its bar and its label, and to leave a clear gap to the first glyph.
The scene's other fengari
harnesses (boss announce, forced switch, input pacing, item use, special boss,
sprites anchor/g9page/shadow, background, guard, prize, bg session, sample
verify) all still pass.

**User action.** Re-export **`g9-battle-scene`** (v3.4.0) and turn FANTASY
COMBAT on in the mod manager to try it.  `g9-battle-engine` and
`g9-battle-sprites` are unchanged.

## EXP SHARE -- party-wide experience, by generation (v3.5.0; Gen 2 benched mons fixed v3.5.1; multi-faint pooling v3.5.3)

A new **EXP SHARE** option chooses how experience is shared across the party
after an enemy faints: **OFF** (default), **GENERATION 1**, **GENERATION 2**,
**GENERATION 3** or **GENERATION 6**.  OFF leaves the game's own award
untouched; each generation mode replaces the split with that generation's own
rules, on BOTH generations.  The whole feature is one new file
(`exp_share.lua`, ~220 lines) plus a small active-set tracker in
`battle_screen.lua` and one rewritten seam in `native.lua`.

**One seam, both games.** The engine already exposes `battle.exp_award` --
Gen 1's `BattleState:awardExp` and Gen 2's `Battle:awardExperience` both build
the same `ctx = { battle, participants, alive, applyShare }` and call it when
a mod is listening (Gen 2 adds `recipients`, `holders`, `halved`, `loser`).
The mod has always resolved Gen 1 exp itself (`native.lua`'s
`state:awardExperience`), and that override never raised the hook at all, so
nothing could ever hook Gen 1 exp on a scene-driven battle.  It now builds the
same ctx and calls the seam, which is what gives the option one hook point on
both generations.  `ctx.applyShare(mon, split, announce)` pays one mon through
the generation's own formula (`split` is the divisor) and -- on Gen 1 now too
-- raises `battle.exp_gained` for it, the event `g9-battle-engine`'s
EV-yield subscriber listens for.  The vanilla fallback (the mon-keyed
`participants` split) is byte-for-byte the old code, so OFF is unchanged.

**The generation rules.** With `E` the defeated enemy's full base exp, `n` the
active-mons divisor, `P` the party size and `H` the number of non-fainted
party mons (a fainted mon never receives anything, and a fainted ACTIVE mon
still divides -- its slice is lost, per the spec):

- **GEN 1 (Exp. All)** -- every non-fainted active mon gets `E/(2n)`, then
  every non-fainted party mon gets `E/(2nP)`.  The participant division is
  inherited by the party pass (the documented Gen 1 bug), which is why a
  fainted party member's slice is lost rather than re-spread.
- **GEN 2 (held Exp. Share)** -- 50% of `E` is split among the non-fainted
  actives (`E/(2n)` each) and 50% among the non-fainted party (`E/(2H)`
  each).  A mon that is both active and a recipient collects twice -- the
  cart's documented "shown twice" quirk, reproduced here.
- **GEN 3 (Gen III-V split)** -- numerically identical to GEN 2 (the Gen III-V
  level-exp rule is the same 50/50); the shares are announced once rather than
  per pass, which is the only difference.
- **GEN 6 (key item)** -- every non-fainted active mon gets the full `E`
  (100% each, undivided) and every other non-fainted party mon gets `E/2`.

**The active set.** "Active" is the scene's own notion, not the engine's
current participant list: a mon is active for an enemy if it stood on the
field at ANY point during that enemy's presence, and only an enemy
SWITCH-OUT (not a faint) resets the set -- the replacement enemy starts a
fresh one.  `battle_screen.lua` tracks this in `self.expActive` (keyed by the
enemy mon), seeded at battle start from the opening field, extended in
`Screen:expMarkActive` from the voluntary-switch, forced-switch and
enemy-replacement paths (`Screen:advanceEnemyReplacement` gives the incoming
enemy a fresh `expFieldSet()`), and handed to the seam as
`battle.expSharePending = { loser, active, party }` right before each award in
`Screen:awardFaintExp`, then cleared.  `exp_share.lua` reads it off
`ctx.battle`.  This is what makes the rule work per enemy in doubles, triples,
hordes and boss fights, and what keeps a fainted enemy's award using the set
that was live while it was still standing.

**EVs are untouched.** The spec keeps modern EV points whole in every
generation and changes only the level-experience amount, so the module never
scales an EV award: each mon that gains exp is paid through the engine's own
`applyShare` (or, on Gen 1, the scene's new one, which emits the same
`battle.exp_gained`), and the EV-yield subscriber does the rest.  Gen 2's own
`ctx.halved` tax (any real item holder halves the pool before `applyShare`
divides) is compensated (`f = 0.5`) so a mode's divisors are not taxed twice.

**Gen 2 benched mons (v3.5.1).** The party pass paid nothing on Gen 2: the
scene's `buildBattle` handed the engine's `Battle.new` the FIELD roster
(`data.players`) as `opts.party`, so `Battle.party` held only the mons a layout
sends out -- and Gen 2 reaches a mon's experience only through `Battle.party`
(`awardExperience`'s `applyShare` searches `self.party` for the mon by
identity; `giveExperiencePass` pays `self.party[index]`).  Every bench share
the option computed was therefore silently dropped (Gen 1 was never affected --
its seam reads `save.party` directly).  `buildBattle` now passes the WHOLE
`game.save.party`; the field roster stays `data.players`, which `Screen.new`
uses for `self.playerBattlers`, so layout and turn order are untouched.  The
same truncation had also hidden bench mons from the EXP.SHARE item holder scan,
the switch primitives' bench, and the in-battle item target picker.

**Condensed announcement (v3.5.2).** A generation mode no longer prints one
`X gained N EXP. Points!` box per recipient.  `exp_share.lua` pays every
share silently (an explicit `false` as `applyShare`'s third argument, which
Gen 2's seam reads as "pay it, do not print its line"), records each mon's
real gain off the shared `battle.exp_gained` event both generations raise
(with the return value of the scene's own Gen 1 `applyShare` as the
no-Runtime fallback), and emits exactly **two** summary lines for the award,
inserted at the FRONT of that award's events so they read as its header and
the "grew to level" lines follow them:

```
PIKACHU, CHARMELEON, BLASTOISE and VENUSAUR gained 120 EXP. Points!
EEVEE and SNORLAX gained 60 EXP. Points!
```

The split is ACTIVE vs the rest (the bench), matching the per-enemy active
rule: the first line lists every mon the active set counted, the second every
other party mon that was paid.  A mon that collects on BOTH passes (gen1/
gen2/gen3 -- the active mon also appears in the party pass) has its two
figures summed onto the active line, so each mon is named exactly once with
the total level-exp it actually gained from the award.  Within a line, equal
figures print once; a traded mon's 1.5x makes the line print a figure per
name instead.  OFF is untouched -- no summaries, the vanilla narration.  This
is what the user asked for: "condense exp distribution into two messages, exp
for active pokemon ... 100 exp points! then ... 50 exp points!".

**Multi-faint pooling (v3.5.3).** A horde -- or any layout that loses several
enemies on one turn -- used to fire one exp award (and so one pair of summary
lines) per enemy.  Per the user's rule the enemies' exp is now summed into ONE
pool first, the EXP SHARE config splits that pool once, and the turn narrates
ONE active line and ONE bench line:

```
PIKACHU gained 240 EXP. Points!          <- actives (union of every fainted enemy's set)
EEVEE and SNORLAX gained 120 EXP. Points!  <- bench
```

`Screen:awardFaintExp` collects the newly-fainted enemies; when more than one
fainted AND an EXP SHARE mode is selected it asks `native.lua`'s new
`N.expBatch(battle, losers)` for a synthetic stand-in loser -- a species def
carrying the summed single-participant exp as `baseExp` and the summed base
stats as `baseStats`, with a loser sitting at the engine's own divisor as its
level (so `Experience.apply`'s `floor(floor(baseExp / split) * level /
divisor)` collapses to exactly `floor(pool / split)`; the trainer/traded
multipliers stay OUT of the pool and are re-applied per recipient as for a
single faint).  The active set handed to the seam is the UNION of the fainted
enemies' own per-enemy sets, so a mon that stood against any of them counts as
active.  The synthetic def is parked in the live `data.pokemon` for that one
award and restored immediately (both backends capture `def` at the top of
`awardExperience`, so the restore cannot affect the recipients).
`Screen:payExpBatch` does the park/pay/restore via `pcall`.  A single faint, or
EXP SHARE = OFF, keeps the ordinary one-award-per-enemy path and narration.

**Harnesses.** `scratch/tests/exp_share_test.lua` (**32/32**) covers the pure
distribution for every mode (genes 1/2/3/6, fainted actives and party members,
the halved compensation, `distribute`, the `partyOf`/`activeSetOf` fallbacks,
the wrap's off/on/no-applyShare branches, and the condensed narration: the two
lines, multi-active joining, insertion ahead of the award's own events,
double-pass summing, per-name figures and the silent/no-list fallbacks);
`scratch/tests/exp_share_screen_test.lua` (**33/33**) loads the REAL
`battle_screen.lua` and drives `expFieldSet`/`expMarkActive`/`awardFaintExp`
(pending stashed per enemy and cleared), `advanceEnemyReplacement`'s fresh set,
both switch paths, and the multi-faint pool (one `N.expBatch` call, one award,
the union active set, the park/restore of the synthetic def, and OFF keeping
the per-enemy awards); `scratch/tests/exp_share_native_test.lua` (**14/14**)
loads the REAL `native.lua` and checks the Gen 1 seam's ctx, fallback, vanilla
callback and `exp_gained` emission; `scratch/tests/exp_share_e2e_test.lua`
(**9/9**) bridges the two -- the real `exp_share.lua` wrap driven through the
real `native.lua` seam with an engine-shaped Runtime -- for OFF/GEN 1/GEN 2/
GEN 6, plus `N.expBatch`'s summing and the pooled award's single split and two
lines; and `scratch/tests/exp_share_gen2_announce_test.lua` (**8/8**) loads
the REAL Gen 2 `Battle.lua` + `exp_share.lua` with a live event bus and
asserts the two summary lines (active, then bench), the double-pass sum, the
pooled multi-faint award, the level-up ordering and that OFF keeps its per-mon
line.  The full 15-harness scene sweep stays green.

**User action.** Re-export **`g9-battle-scene`** (v3.5.4) and set the EXP
SHARE row in the mod manager.  `g9-battle-engine` and `g9-battle-sprites` are
unchanged.

## Triple-battle adjacency + a shorter move-info bar (v3.5.4)

**The bug.** In a triple battle, spread moves (Surf, Earthquake, Muddy Water)
hit non-adjacent allies.  The scene has always known each battler's own slot
column -- `self.playerBattlers[i]` / `self.enemyBattlers[i]`, index-aligned by
`sideColumns` and already built N-agnostic -- but the `g9.request_adjacency`
handler it registers with `g9-battle-engine` reported the FULL roster on both
sides: every ally was "adjacent" to every other ally and every foe was
reachable from every slot, so a wing slot's Surf swept the whole row.

**The rule, now enforced for non-boss fights.**  Within a side, slot `i` is
adjacent to `i-1` and `i+1` only -- slot 1 and slot 3 are NOT adjacent, and the
same pattern holds on the enemy side.  Across sides, slot `i` reaches the
opposing columns `i-1`, `i`, `i+1`: a wing reaches two foes, the centre all
three.  Doubles and singles degrade to "everything" for free, since every index
is within 1 there.  A **boss fight** keeps the long-standing exception
(reaffirmed 2026-09-10): ALL allies count as adjacent to all allies, all foes
to all foes -- a non-empty `battle.bossFightFlags` table is the switch.

Two things had to change together, because the scene both *reports* the real
roster (resolution) and *offers* targets (the picker):

* **Resolution.**  The module-level `g9.request_adjacency` wrap in
  `battle_screen.lua` now filters both halves by the rule above instead of
  returning everything.  A `nil` `moveId` still answers the full roster -- that
  is the engine's own `allActiveBattlers` roster query and the switch-in /
  ally-scope ability seam (Intimidate, Hospitality), which MUST see every
  battler or they silently miss #2/#3, so nil is never treated as "a move use".
* **The picker.**  `Screen:updateMoveSelect` now builds its candidate list from
  new `Screen:reachableEnemies` / `Screen:reachableAllies` helpers (plus
  `Screen:isBossFight` / `canReachNonAdjacent` / `reachAllSlots` / `actingIndex`)
  instead of the raw rosters, so a triple-battle Surf no longer lets the player
  aim past a non-adjacent mon, and Heal Pulse no longer lists non-adjacent
  allies.  The full live-foe list is kept purely as the spread/field
  *placeholder* -- the engine re-resolves the real roster at resolution time, so
  a placeholder never limits who is actually hit.

**Distant moves.**  Flying/airborne attacks (Acrobatics, Aerial Ace, Aeroblast,
Air Slash, Bounce, Brave Bird, Chatter, Drill Peck, Fly, Flying Press, Gust,
Hurricane, Oblivion Wing, Peck, Pluck, Sky Attack, Sky Drop, Wing Attack,
Dragon Ascent), the pulse/aura family (Aura Sphere, Dark Pulse, Dragon Pulse,
Heal Pulse, Water Pulse) and the counter/revenge family (Counter, Mirror Coat,
Metal Burst, Bide, Destiny Bond, Grudge) may strike a NON-adjacent target, so
they open the whole board.  The capability is keyed on the MOVE'S OWN ID, never
its current type (the user's explicit clause): an Aerilate Normal move gains
nothing and a Normalize Air Slash keeps everything.  The curated id set is the
authority; `national_dex`'s own `distance` flag is consulted as a second source
when available (its generated table spells ids inconsistently -- `AERIALACE`
but `DRILL_PECK` -- so both the raw and separator-stripped spellings are tried).

**The move-info bar.**  The FORMS/fantasy move-info panel was 58px tall and
floated 12px below the canvas roof.  It is now 40px and flush with the top of
the canvas (`INFO = { x = 12, y = 0, w = 600, h = 40 }`), and its text is
centred on the 40px row -- the move name, the divider, and the label/value pair
all share one baseline computed from the row's own mid-line, instead of being
stacked from the top.

**Harnesses.**  `scratch/tests/triple_adjacency_test.lua` (**80/80**) loads the
REAL `battle_screen.lua` + `combat.lua`, captures the registered
`g9.request_adjacency` handler, and drives it directly: 3v3 Surf from every
player slot and every enemy slot (the full neighbour/column matrix), the
single-target reach, every distance id in several spellings, the boss-fight
exception, the `nil`-moveId full roster, doubles/singles degradation, fainted
exclusion on both sides, and the stale-screen fall-through; then the same cases
through the Screen helpers, plus the `distance`-flag path via a stubbed
`g9dex`.  `scratch/tests/fantasy_combat_test.lua` (**61/61**) re-asserts the
new 40px flush info panel.  The full 25-harness scene sweep (728 tests) is
green.

**User action.** Re-export **`g9-battle-scene`** (v3.5.4).  `g9-battle-engine`
and `g9-battle-sprites` are unchanged.

## Horde adjacency (v3.5.5)

**The bug.** The v3.5.4 positional adjacency rule was applied unconditionally,
so it also applied to a **Horde Encounter** -- one of yours against five wild
enemies.  In the horde grid the lone ally stands at a2 (column 2) and the swarm
at e2..e6 (columns 2..6), so the index-based neighbour rule (`|caster - j| <= 1`)
left only the first two foes reachable -- when the declared, unique behavior of
a horde is that, to the player's mon, EVERY enemy counts as adjacent.

**The rule.** A horde is its own exception, exactly like a boss fight: the scene
reports the whole roster on both sides.  It is keyed on the active layout's own
`horde` flag (`layouts/hordes.lua`'s `horde = true`, read as `screen.isHorde` /
`self.isHorde`) -- the SAME flag that fixes the swarm's e2..e6 grid -- never on
the enemy count, so an ordinary 1-vs-5 (or any 2-3 enemy) fight is never widened
by it.  Both halves changed together, as before:

* **Resolution.**  The module-level `g9.request_adjacency` wrap's `full` switch
  now includes `screen.isHorde`, alongside the boss-fight
  `battle.bossFightFlags` check, the `nil`-moveId roster query, and the
  distance-move set.
* **The picker.**  New `Screen:isHordeFight()` (reads `self.isHorde`) is OR-ed
  into `Screen:reachAllSlots`, so the target picker offers the whole horde row
  and a spread move sweeps it.

**Harnesses.**  `scratch/tests/triple_adjacency_test.lua` grew 80 -> **91**
checks: the horde resolution (P1's Surf/Tackle reaching all five, an enemy
caster seeing the whole swarm), the SAME 1v5 shape WITHOUT the flag staying
positional (proof it keys on the flag, not the count), fainted horde foes still
excluded, and the picker half (`isHordeFight`, `reachAllSlots`,
`reachableEnemies`).  The full 25-harness scene sweep is **744 tests, 0
failures**.

**User action.** Re-export **`g9-battle-scene`** (v3.5.5).  `g9-battle-engine`
and `g9-battle-sprites` are unchanged.

## Fantasy layout (v3.5.6; wide zig-zag + over-head readouts v3.5.8; lowered formation + fainted roster v3.5.9; hand-tuned enemy slots v3.5.10; paired ally column v3.5.11; fantasy asset size v3.5.12)

**What it is.** A new **FANTASY LAYOUT** row (OFF by default) that *replaces*
the horizontal placement every preset has always used with a vertical grouping
of the two sides. It is a placement/art switch only: rosters, turn order,
targeting, adjacency, combat rules and the presets themselves (singles 1v1,
doubles 2v2, triples 3v3, boss fights 4v1, hordes 1v5) are all untouched.
With the row OFF, every existing layout draws exactly as before.

**The arrangement.** Each side stands in a **zig-zag column**: the player's on
the **left** of the field, the enemy's on the **right**. The first Pokemon of
each side is placed **bottom-most**; the second sits above it, then the third,
then the fourth (the player's column stops at four). The enemy's column runs to
five for a horde. Consecutive slots **alternate horizontally** about the
column's centre by **40 design px** but step up only **15 design px** — slot 1
(the lead) and the other odd slots take the **outer** x (further from the
centre seam), the even slots the **inner** x — so the side reads as a **wide,
shallow** zig-zag running up the field rather than a tall plumb line (the swing
is deliberately wider than a readout box, and wider than the whole five-slot
rise, so the formation always reads wider than it is tall). Both sides start on
an outer slot, so the two zig-zags **mirror** each other. A column's later
slots are drawn **one layer further back**, so a mon never covers the one in
front of it — the lead mon at the bottom is painted last and reads as the
front-most.

**The formation is lowered (v3.5.9).** The whole arrangement sits a little
lower than before: the lead slot's ground line (`FANTASY.baseY`, 122 -> **134**)
now places the front-most Pokemon's **feet slightly UNDER the top edge of the
bottom HUD band** — the hp-bar row and the action box (`BOTTOM_Y = 128`) —
instead of just above it. A normal fight stands its ally's feet exactly ON that
line, so the fantasy lead now tucks a few pixels in behind the HUD, which is the
reference the layout was tuned against. Only `baseY` moved: `step`, `zig` and
the two column centres are untouched, so both sides keep exactly the same
spacing and ordering as before.

**Two hand-tuned enemy slots (v3.5.10).** On top of the uniform staircase a
couple of the **enemy** column's slots stand on absolute, hand-set ground
lines: **slots 4 and 5 are raised to the same line** (64 design px), so the two
highest enemies read as a level pair, and **in a HORDE only, slot 2 is moved**
to its own line (115 design px) -- the rest of the five-enemy column (and the
whole player side) keeps the plain `baseY - (slot-1)*step` staircase. The lines
live in `FANTASY.enemySlotY` / `FANTASY.hordeEnemySlotY` and are resolved by
`Screen.fantasyGroundY`, so a slot's x, its index and every index-aligned
consumer are untouched -- only the ground line a named enemy slot stands on.

**The ally column is paired (v3.5.11).** The player side's two even slots are
**lowered onto the odd slot below them** -- ally slot 2 onto ally slot 1's
line, ally slot 4 onto ally slot 3's -- so the player column now reads as
**pairs** (1+2, then 3+4) at one line each instead of a staircase. It is held
as the rule `FANTASY.playerPairsWithBelow` (not two literals) and resolved by
the same `Screen.fantasyGroundY`, so it keeps matching slot 1/slot 3 on its own
if `baseY` or `step` is ever retuned, and it leaves the enemy column alone.

**A fainted Pokemon is never sent out (v3.5.9).** `Screen.playerFieldRoster`
builds `self.playerBattlers`, and it skips a **fainted** party mon
(`(mon.hp or 0) <= 0`) entirely rather than fielding it. The caller's own
payload decides the field **size** (its length is what the formation stands
up), so a fainted mon in that payload is replaced by the **next healthy mon in
the party**, walked in order, keeping the field at the size the caller asked
for. Lookups are identity-guarded, so a caller that already sends a healthy
roster gets exactly what it sent (no backfill once the field is full, no
duplicate). If every candidate is fainted (the player has already lost) the
caller's own roster is kept as a degenerate fallback so the field is never
empty. The scene now owns this rule, so any caller benefits — it no longer
depends on the caller pre-filtering its roster.

**The art.** The player's column is drawn from each Pokemon's **FRONT** battle
sprite, mirrored horizontally (flipped about the y-axis) so both teams read from
the same front sheets, turned to face one another. The enemy's column keeps its
normal front sprite. The sprite's bottom-centre anchor is unchanged by the
mirror, so the stat readouts, the pokeball's landing spot and every move
animation still land where they always did.

**A fantasy-exclusive asset size (v3.5.12).** A new mod-manager row,
**FANTASY SIZE**, appears **only while FANTASY LAYOUT is ON** (it carries
`visible_if` for that row, so the manager hides it otherwise) and scales
**both sides' sprites** as a percentage of their normal size — 50% .. 200%,
default **100%**, which is exactly the size the horizontal layout draws. It is
a **multiplier on top of** each side's usual `spriteScaleFront` /
`spriteScaleBack` scale, so the per-side sizing is preserved underneath, and
it is **never read** with the layout off. A preset may also carry its own
fantasy-only override (`spriteScaleFantasy`, or the per-side
`spriteScaleFantasyFront` / `spriteScaleFantasyBack`), and the in-code default
is `Screen.FANTASY.spriteScale` (add `spriteScaleFront` /
`spriteScaleBack` there to size one side on its own). Every layer is a
multiplier defaulting to 1, so with none of them set the fantasy scene is
byte-for-byte what it was before.

**The readouts.** Each slot's HP/exp box now rides **directly over its own
mon's head**: the box is centred on that slot's centre-x and its bottom edge
sits on that mon's head line (`Screen.fantasyHeadY`, which reads the per-battler
head line the sprite pass records, falling back to `groundY - FANTASY.headLift`
if a mon has not been drawn yet). There is no separate readout column any more.
Because the zig-zag swings wider than a box and two slots in the same column
stand more than a box-height apart, the per-mon boxes can never collide, whatever
the team size — verified over every shipped shape (1v1/2v2/3v3/4v1/1v5/4v5).

**Under the hood.** `battle_screen.lua` gains `Screen.fantasyLayoutEnabled`
(the pcall'd option read), `Screen.FANTASY` (the column geometry — `baseY`,
`step`, `zig`, `headLift`, the two column x's, the v3.5.10 per-slot enemy
lines `enemySlotY`/`hordeEnemySlotY`, the v3.5.11 ally-pairing rule
`playerPairsWithBelow`, and the v3.5.12 asset-size multiplier
`spriteScale`), `Screen.fantasyGroundY` (the one ground-line lookup:
a named enemy slot's override, the ally side's even-slot pairing, else the
staircase `baseY - (slot-1)*step`), `Screen.fantasySlotX` (the
zig-zag's x for a slot + outward direction), `Screen.fantasySlot`,
`Screen.fantasyHeadY` (the per-mon head line the readouts ride, fed by
`drawContent`'s `headLines` map), `Screen:paintOrder` (N..1 when fantasy, 1..N
otherwise), `Screen:spriteArt` (which sheet + mirror each side uses) and
`Screen:slotRectFor`; `Screen:slotRects` gained the fantasy branch and
`drawSprite` gained the optional `flipX` blit. `Screen:battleSpriteScale`
(v3.5.12) now resolves every side's drawn scale — the old per-side
front/back expression, multiplied by the fantasy asset-size factor (the
preset's `spriteScaleFantasy*`, else `Screen.FANTASY.spriteScale*`, times
`Screen.fantasyAssetMul`) only when the layout is on — and `Screen.new`
reads one scale per side through it. The zig-zag is **purely
horizontal**, and the v3.5.10/v3.5.11 ground-line tweaks only move named enemy
slots and pair the ally column — a slot's index, and therefore every
index-aligned consumer (targets, turns, bench replacement, adjacency), is
unchanged.
`Screen.playerFieldRoster(players, party, combat)` (v3.5.9) is the
roster seam `Screen.new` calls to build `self.playerBattlers`; it is described
under the fainted-roster note above. The helpers live on the `Screen` class
rather than as module-level locals because that closure already sits at Lua
5.1's 200-active-local ceiling.

**Harnesses.** `scratch/tests/fantasy_layout_test.lua` (**117** checks) covers the
option read, the geometry (incl. the "swing wider than a box / same-column gap
clears the tallest box / wider-than-tall" guarantees, the absence of a readout
column, and the v3.5.9 `baseY = 134` that tucks the lead's feet under the 128
HUD-band top), the `fantasySlotX` zig-zag arithmetic, both layouts' `slotRects`
for 1v1/2v2/3v3/4v1/1v5, `Screen.fantasyHeadY`, `spriteArt`, `paintOrder`,
`slotRectFor`, a **no-collision + on-field** sweep of every shipped shape, a
**ground-line block** (`Screen.fantasyGroundY` applies the raised enemy slots
4/5, gates the horde slot-2 line on `horde`, keeps enemy slots 1/3 on the
staircase, pairs the ally column so slots 2/4 land on slots 1/3, and — for the
v3.5.11 rule — keeps pairing up the column, slot 6 onto slot 5; the concrete
horde rects 134/115/104/64/64; a non-horde five-enemy column keeps 119 for slot
2; the 4-slot ally column is 134/134/104/104), a new
`Screen.playerFieldRoster` block (a fainted slot is skipped and the next healthy
party mon takes its place; an all-healthy field is untouched; a fainted lead is
replaced; no backfill past the caller's count; the all-fainted fallback; a nil
payload is safe), and it proves the `g9.request_adjacency` hook returns identical
allies/enemies normal vs fantasy. A new v3.5.12 **asset-size block** proves
`Screen:battleSpriteScale` is the old front/back expression with the layout
off, that fantasy with no overrides matches it exactly, that
`Screen.FANTASY.spriteScale` (and its per-side keys), the preset's
`spriteScaleFantasy*` and the FANTASY SIZE option each multiply the right
side, that a per-side override beats the single value, and that the option
is ignored with the layout off; `Screen.fantasyAssetMul` is proven
defensive (missing/error/garbled/zero all fall back to 1). A render harness
(`scratch/tests/render_fantasy_zigzag.mjs`) draws the 1v5/4v5/3v3/4v1 placements
to PNGs (each box connector-coloured to its own mon), and
`scratch/tests/render_fantasy_clear.mjs` draws them large with a translucent
**bottom HUD band** over the mons so the v3.5.9 tuck is checkable; vision
confirmed the lead's feet sit slightly under the band top while every other mon
stays above it, boxes still over their own heads and non-overlapping, FOE 4 and
FOE 5 level at the top of the enemy column, and (for v3.5.11) ALLY 2 level with
ALLY 1 and ALLY 4 level with ALLY 3. The full scene sweep is **861 tests, 0
failures**.

**User action.** Re-export **`g9-battle-scene`** (v3.5.12), set the
**FANTASY LAYOUT** row in the mod manager to try it, then use the **FANTASY
SIZE** row that appears under it to resize both teams' sprites (100% =
today's size).  `g9-battle-engine` and `g9-battle-sprites` are unchanged.

## Mega evolution sequence (v3.6.0; trigger robustness + self-diagnosis v3.6.1; sprite swap + framing v3.6.2; 8-point light star v3.6.3)

**What it is.** A staged transformation that plays on the scene **before** the
mega form change lands, so the sprite swaps to its mega under a white flash
instead of popping instantly. It is built to match a reference clip the user
supplied and covers five named elements: a **rainbow DNA sphere**, a **rainbow
"overloading" aura** around the sprite, a **shining/whitening** of the sprite
itself, a **spherical glass shell that shatters** around it, and a **spherical
shockwave air-release with rainbow sparkles**.

**The clip module (`evolution_anim.lua`, new).** A self-contained sequence with
one export, `mod.exports.battleSceneEvolutionAnim` (`E`):

- `E.new(opts)` / `E.step(clip, dt)` / `E.draw(clip)` — build, advance and draw.
- `E.whiten(clip)` — 0..1 white amount for the sprite blit (1 at the reveal).
- `E.scaleMul(clip)` — the size multiplier (a small squash-and-stretch).
- `E.REVEAL_T = 1.95`, `E.END_T = 3.60` — the beat the form changes on, and the
  frame the turn is handed back.

`opts` is `{x, top, feet, w, h, side, seed, vw, vh}`, where `x` is the sprite's
centre-x, `top`/`feet` its head and ground lines and `w`/`h` its box. Every
radius derives from that box (`sphereR` off `min(w,h)`, `shellR`/`auraR` off
`max(w,h)`), so the same clip fits an enemy front sprite and a small player back
sprite, and the whole thing is deterministic from `seed` (an LCG), so it can be
reproduced exactly.

**The timeline (0 s -> 3.60 s).** A ground charge/aura builds from 0; the orb
forms (0.45) and the eight-point light star (0.95); pixel sparkles drift (0.80); the
whiten climbs to 1 across the reveal (peaking 1.70-2.45); the reveal is at
**1.95**; the glass shell bursts (2.12) into tumbling shards; the spherical
shockwave rings and the rainbow four-point stars release from 2.24-2.30; and a
small farewell orb drifts above the head from 2.95 to the end.

**The five elements.** (a) The **orb**: a rainbow hue-swept ring around a cyan
double helix with magenta/yellow rungs, sitting over a soft white core. (b) The
**aura**: a 30-segment hue rim plus a pulsing inner wash around the whole sprite
— the "overloading" read. (c) The **whiten**: `E.whiten` is fed to `drawSprite`
(this file's `drawSprite` gained a 13th `whiten` argument); the blit uses a
colour multiplier above 1 (`1 + wf*6`) **and** up to six additive passes, so the
flash reads even on a build that clamps `setColor` to 1. (d) The **glass shell**:
a lat/long 10x6 sheet of quads that is tilted orthographically and spun around
the sprite, then bursts into per-shard tumble/speed/hue fragments. (e) The
**shockwave**: two expanding ring pairs, plus rainbow four-point stars and
trailing pixel sparkles.

**Two rendering rules** are load-bearing and are recorded in the module so a
later editor does not re-break them: the rainbow rims/stars/pixel-sparkles and
the star's rays are drawn in **alpha** blend (additive hues over the bright
orb/sky sum to flat white), and the **star draws before the orb** (an alpha
ray over the orb veils its ring and helix to white).

**The staged beat (`battle_screen.lua`).** The change the resolve pass used to
perform inline now runs from the clip's reveal beat:

- `Screen:startEvolutionAnim(mon)` — builds the clip from the battler's own
  `spriteAnchor` (the box the sprite pass really drew, with `slotRectFor` as the
  frame-one fallback), wires `clip.onReveal`, sets the message
  `"<name> is Mega Evolving!"`, stores `self.evolve = {clip, owner, battler,
  applied}` and returns true. It answers false unless the active gimmick is
  `"mega"`, the animation module exists and there is an on-field battler.
- `Screen:updateEvolution(dt)` — run from `Screen:update` (phase-independent, so
  a held button cannot skip it). It steps the clip, and on `clip.done`, a raised
  step or `elapsed > Ev.SAFETY` (8.0 s) it runs the activation if it has
  not run, releases `self.evolve` and calls `advanceResolving`.
- `Screen:drawEvolution()` — run from `drawContent` just before the bottom F/E
  narration band, so the message stays readable over the clip (as the reference
  clip keeps its own text box legible).
- `Screen:revealEvolution()` — the reveal beat: idempotent (guarded by
  `applied`), pcall'd, runs `applyGimmickActivation`, and retitles the line to
  `"<name> Mega Evolved!"`.
- `Screen:applyGimmickActivation(formsMon)` — the old inline activation, lifted
  whole: sets `movesBegun`, emits `battle.turn_started` focused on the owner,
  consumes or refuses the FORMS `used` event, clears the gimmick owner and
  begins the stepwise turn.
- `Screen:evolutionFx(battler)` — the evolving battler's `whiten` and `scaleMul`
  for the sprite pass, or nil for everyone else.

Because `battle.turn_started` now fires at the **reveal** rather than the instant
the turn was armed, `battle_forms` performs and spends its armed id with native
turn-loop timing. `E.REVEAL_T` is what this file reads to know the frame the
sprite becomes the new form.

**Safety.** LÖVE cannot run in the preview, so the module is written never to
fatal: `step` and `draw` are pcall'd (a raise logs and still runs the
activation), a clip that never reports `done` is abandoned by the 8.0 s valve,
and a `Screen` without the module simply does not stage.

**Trigger robustness and self-diagnosis (v3.6.1).** Two fixes to make a mega
that is genuinely on its way impossible to silently skip:

- Staging is decided by *"is a mega about to happen"*, never by *"did this file
  record an owner"*. `startEvolutionAnim` accepts either this scene's own
  `gimmickOwnerId == "mega"` or battle_forms' own published `armed() == "mega"`,
  and `advanceResolving` stages for `Screen:megaStageMon()` when no owner was
  recorded (the owner, else the first player battler -- which is where the
  activation lands anyway when nothing re-focused `battle.player`).
- `drawEvolution` **no longer cancels the sequence on a draw failure**. The
  clip's reveal beat is what performs the form change, so clearing `self.evolve`
  on a raised draw silently dropped the whole transformation (no animation AND
  no mega). It now logs once and keeps stepping, so the change always lands.
- Every case where a mega is definitely coming but the animation cannot be built
  (no module, no on-field battler, no resolvable sprite box) now logs why, so a
  future failure names itself instead of being invisible.

**Harnesses.** `scratch/sim/run-evolution.js` renders 45 frames of the **real**
module through a mocked `love.graphics` into contact sheets, and vision
confirmed each element reads as intended (rainbow ring + helix, the eight-point
star, aura, whitening, angular glass shatter, spherical shockwave rings,
four-point stars, the farewell orb, and a sane fit on a small sprite — and that
the frames at t=1.92/1.98 are now solid white). The star was also measured
straight off the recorded draw commands: at t=1.28 the cardinal points are 71.8
design px and the diagonals 112.2, at t=1.83 they are 111.2 and 72.8 (the
out-of-phase breath, exact), every ray's silhouette ends in a single `(tip)`
vertex, and the wash composites to 0.60 at the sphere, 0.29 at 60, 0.08 at the
longest ray's tip (114) and 0 by ~145 — past every point.
`scratch/sim/iso-beams.js` renders the beam block alone on black (full-star and
8x tip close-ups) so a ray tip can be judged without the orb, aura, pixels or
story band in the way.
`scratch/sim/run-evolution-flow.js` extracts the real staged code out of this
file and drives it at 30fps through 12 groups — **48/48**: the change lands
exactly once, at `REVEAL_T`, with the sprite fully white; `battle.turn_started`
and the forms `used` event fire once; the turn is handed back once; `evolutionFx`
answers only the evolving battler; a non-mega gimmick stages nothing; a raising
step and a never-finishing clip both still land the change; the reveal is
idempotent; and the new groups prove `FLASH_IN < REVEAL_T < FLASH_OUT`, that the
flash is exactly 1 at the reveal, that `cx` follows a measured art shift (design
px, and `/DS` for a natural bake), that the clip FREEZES on the reveal beat while
the art is unavailable and resumes the moment it is ready, and that the hold is
capped by `Ev.HOLD_MAX`.
`scratch/sim/run-form-species.js` extracts `Ev.formSpecies` plus the form-event
listeners and drives them in fengari — **14/14**: a `form_applied` payload
records its `formId`, the sprite resolves to the form species and its own art, a
formId-less change derives `species_form`, an unknown form resolves to nil (base
art kept), a form with no pic for a side falls back to the base pic, and
`form_reverted` clears the record.

**The swap, the white, and the framing (v3.6.2).** Three defects the first
in-game look surfaced, fixed together:

- **The sprite now actually changes to the new form.** battle_forms never moves
  `mon.species` (its `src/forms.lua` is explicit: it writes the form record's own
  suffix into `mon.form`), so a mega landed with its stats and announcement but
  kept its base art. This file now listens for battle_forms' own published
  `form_applied` / `form_reverted` events and records the National Dex record key
  (`formId` -- e.g. `"CHARIZARD_MEGA_X"`) on the mon; `resolveSprite`'s species
  chain (display species -> recorded form key -> derived `species_form` -> base
  species) then feeds that key to BOTH art paths. A form whose record carries no
  pic for a side falls back to the base species' pic, and because `mon.species`
  is already swapped around the sprite seams the pack still receives the FORM's
  species -- which is what lets a sprite mod's own sheet replace the art.
- **The replacement happens under a genuinely white screen.** The flash now
  reaches SOLID white at 1.86s and holds it to 2.06s, and the reveal beat (1.95s)
  sits inside that window -- previously the peak was only ~65% opaque, so the
  swap was visible. `Evolution.flashAlpha` publishes the curve so the harness can
  assert the reveal is hidden.
- **And the white waits for the new art.** A sprite pack bakes a form's sheet
  lazily, so for a few frames after the change the new art does not exist. Once
  the change has landed, the clip is FROZEN on the reveal beat (the solid-white
  window) until `Ev.artReady` reports the new form can actually be drawn, or
  `Ev.HOLD_MAX` (2.0s) gives up -- so the art can no longer pop in after the
  white has gone. The 8.0s safety valve keeps running throughout.
- **The sequence is centred on the ART, not the sprite anchor.** A sprite pack
  bakes one union canvas per animation, so a creature that sits off-centre in
  its own frame had every circle drawn off to one side (user-reported). The clip
  now measures the opaque content of the frame it is about to draw (`Ev.art` ->
  `resolveSprite`, then `Ev.artShiftX` scans the image's pixels once per
  transformation) and centres the show there (`Ev.artShift`; a `naturalBake`
  image divides by `DS`). With no readable art the anchor is used unchanged, so
  nothing here can fail a transformation.
- **Housekeeping.** The form-art and evolution-costume helpers were gathered into
  one `Ev` namespace: PUC Lua caps a function at 200 active locals and this
  file's outer function had been pushed just over it (the whole scene would fail
  to load under `luac`/fengari; LÖVE's LuaJIT does not enforce the cap, but the
  static gate and the harnesses do).

**The 8-point light star (v3.6.3).** The old light pattern was four pale
wedges that all shimmered together and ended in flat far edges. Reworked:

- **Eight rays, two families, out of phase.** Four CARDINAL (up/down/left/right)
  and four SUBCARDINAL (the diagonals). One shared breath (`sin(t*4)`) drives
  them in opposition — cards `len = BASE*(1+AMP*b)`, diagonals
  `BASE*(1-AMP*b)` with `BASE=92`, `AMP=0.24` — so the cardinals extend while the
  diagonals retract, then the reverse. Measured: 72/112 px at t=1.28 against
  111/73 px at t=1.83.
- **Sharp tips.** Each ray is built from three NESTED five-vertex spikes — base,
  waist, `(tip)`, waist, base — a coloured body, a warmer mid layer and an
  additive white core, all sharing one waist fraction and all ending in the same
  single POINT, with the longest giving the silhouette. No strokes are used for
  the ray at all: a stroke's cap (or a clipped miter on a closed outline) is a
  flat edge, and a stroke that stops short of the apex leaves a notch — which is
  what made earlier cuts read truncated. (No polygon in the effect has a flat far
  edge any more.)
- **The wash.** Behind the rays is a radial glow of colour: 64 concentric discs
  whose alphas are solved so the composited result is exactly
  `A(r) = 0.60k * (1 - r/washR)^1.5` — fairly solid at the sphere, fading
  progressively to true transparency past the points (`washR = BASE*(1+AMP)*1.38
  ~ 157`; the outermost discs fall below the draw threshold, so the glow is
  effectively gone by ~145, past the longest the points ever get, 114). The
  gentle exponent keeps a visible trace of light out beyond the tips before it
  dies, so the glow is seen to outgrow them. Discs, not wedges: a radial glow has
  no straight edges anywhere, so none of it can read as a rectangular band, and
  it is the light seen between the bars. 64 (not 16) rings because each disc is a
  single flat colour, so the composite is a step function and too few steps read
  as visible concentric rings.

**User action.** Re-export **`g9-battle-scene`** (v3.6.3). `g9-battle-engine`
and `g9-battle-sprites` are unchanged. LÖVE cannot be run in the preview, so the
in-game confirmation is yours.

## Dynamax / Gigantamax sequence (v3.6.4)

**What it is.** A staged transformation that plays on the scene **before** the
Dynamax form change lands, built to match a reference clip the user supplied. It
shows the creature as a **black silhouette** standing inside a furnace of red
light while **dark-red and brighter-red energy ribbons** spiral inward and
**cumulus clouds** gather, then a white flash covers the beat the change lands
on. Two elements from the reference clip are deliberately **not** used: the red
orb that floats in front of the creature and the iridescent DNA orb that appears
at the end.

**The clip module (`dynamax_anim.lua`, new).** A self-contained sequence with
one export, `mod.exports.battleSceneDynamaxAnim` (`E`):

- `E.new(opts)` / `E.step(clip, dt, hold)` / `E.drawBack(clip)` / `E.draw(clip)`
  — build, advance, and draw the BACK and FRONT layers.
- `E.darken(clip)` — 0..1 darkening for the sprite blit (1 = full silhouette).
- `E.flashAlpha(clip)` / `E.flashColor(clip)` — the flash curve and colour.
- `E.REVEAL_T = 1.38`, `E.END_T = 3.10` — the beat the form changes on, and the
  frame the turn is handed back.

`opts` is `{x, cx, top, feet, w, h, side, seed, vw, vh}` — the same box the mega
clip takes, with `cx` carrying the measured art centre (see `Ev.artShift`). Every
radius derives from that box and the whole sequence is deterministic from `seed`.

**The timeline (0 s -> 3.10 s).** Dark-red and brighter-red **ribbons** spiral
inward from off-screen and gather (0.00-0.95), stopping at a hole
(`0.5*sqrt(w^2+h^2)`) so they never run over the creature; the sprite **darkens**
to a full silhouette by 1.05 and holds; **cumulus clouds** gather at a ring
outside the creature and burst outward as the flash begins (0.78-1.34); the
**flash** is solid white from 1.34 to 1.52 with the reveal at **1.38** inside it;
a **shockwave and embers** release after (1.52+); the sequence settles through
3.10.

**TWO layers, and why.** Light *behind* a creature is something a clip drawn
after the sprites can never fake, so the module splits in two. `drawBack` (the
dim, the red **furnace** glow, and the far half of the cloud) is raised by
`drawContent` **before** the sprite pass; `draw` (the ribbons, the near cloud,
the flash, the shockwave) is drawn where the mega sequence is — over the sprites
but under the F/E narration band. The **silhouette** is produced by darkening
the sprite in the blit (`Screen:dynamaxFx` -> `drawSprite`'s `darken`), not by
drawing a black shape, so the creature's own animation still shows through the
dark.

**The staged beat (`battle_screen.lua`).** The DYNAMAX block mirrors the MEGA
one:

- `Screen:startDynamaxAnim(mon)` — builds the clip from the battler's own box,
  wires `clip.onReveal`, sets `"<name> is Dynamaxing!"`, stores `self.dynamax`
  and returns true. It answers false unless the armed gimmick id names Dynamax
  (`Ev.dyn.isId`, matched by name so it cannot pin one spelling), the module
  exists and there is an on-field battler.
- `Screen:updateDynamax(dt)` — run from `Screen:update` (phase-independent, so a
  held button cannot skip it); steps the clip, holds the reveal beat while
  `Ev.artReady` is false (capped by `Ev.dyn.HOLD_MAX`, 2.0 s), and on `clip.done`,
  a raised step or `elapsed > Ev.dyn.SAFETY` (8.0 s) runs the activation if it
  has not, releases `self.dynamax` and calls `advanceResolving`.
- `Screen:drawDynamaxBack()` / `Screen:drawDynamax()` — the two layers.
- `Screen:revealDynamax()` — idempotent, pcall'd, runs `applyGimmickActivation`
  and retitles the line to `"<name> Gigantamaxed!"`.
- `Screen:dynamaxFx(battler)` — the growing battler's `darken`, or nil for
  everyone else.

**Consumes, never provides, the mechanic.** battle_forms owns the Dynamax
activation, the 3-turn clock, the Max Moves and the HP half; this scene only
watches for the armed id and costumés the change. The **size ladder** is
`g9-battle-sprites`' own (see its DYNAMAX GROW section) and starts when the
change lands.

**Safety.** LÖVE cannot run in the preview, so the module is written never to
fatal: `step` and both draw layers are pcall'd (a raise logs and still runs the
activation), a clip that never reports `done` is abandoned by the 8.0 s valve,
and a `Screen` without the module simply does not stage — the change happens the
old way and nothing here can ever gate a Dynamax.

**Harnesses.** `scratch/sim/run-dynamax.js` renders the **real** module through
a mocked `love.graphics` into contact sheets, applying the same darken to the
sprite layer, and vision confirms the black silhouette inside the red energy,
the spiralling ribbons, the churning cloud with front/back depth, the white
flash, and (second half) the creature returning to normal with no unwanted orb
or helix. `scratch/sim/run-dynamax-flow.js` extracts the real staged code out of
this file and drives it at 30fps — **66/66**: the change lands exactly once at
`REVEAL_T` with the creature fully dark; `battle.turn_started` and the forms
`used` event fire once; the turn is handed back once; `dynamaxFx` answers only
the staged battler; `Ev.dyn.isId` accepts every dynamax spelling and refuses
`mega`/`tera`/nil; a mega gimmick stages nothing; a raising step and a
never-finishing clip both still land the change; the reveal is idempotent;
`FLASH_IN < REVEAL_T < FLASH_OUT`; the clip freezes on the reveal beat while the
art is unavailable and the hold is capped; a build with no module performs the
change the old way; and an armed id with no recorded owner still stages.
`scratch/sim/run-evolution-flow.js` stays **48/48** (the mega path is
untouched).

**User action.** Re-export **`g9-battle-scene`** (v3.6.4) and
**`g9-battle-sprites`** (3.1.3). `g9-battle-engine` is unchanged. LÖVE cannot be
run in the preview, so the in-game confirmation is yours.

## Dynamax field FX + a held faint (v3.7.0)

**What it is.** Once a Dynamaxed/Gigantamaxed mon is standing on the field --
after the transformation clip has handed the turn back -- the scene keeps two
persistent effects up for as long as it is transformed: the whole background is
**darkened** under a deep maroon wash, and each transformed battler stands out
of a pulsing **red aura**. When the Dynamax ends -- the form reverts at the end
of its 3 turns, the mon faints, or it is switched out -- the effects ride the
sprite mod's shrink back down and fade out with it. A Dynamaxed mon that faints
does not vanish on the frame its HP hits zero: it is **held on screen, still
shrinking**, and only when the shrink-back finishes does it leave in a red
**burst**. A Dynamax that merely expires its turns, or is switched out, gets no
burst.

**The module (`dynamax_field.lua`, new).** A self-contained sibling, like
`dynamax_anim.lua`, with one export, `mod.exports.battleSceneDynamaxField` (`F`):

- `F.darkenOn()` / `F.auraOn()` -- read the two option rows (both ON by default).
- `F.charge(st)` -- a `dynamaxStateOf` record mapped to 0..1: the size factor
  1.00 -> 0, 1.50 -> 1. So the wash and the aura ramp IN through the grow, sit
  full while the mon is transformed, and ride back OUT through the shrink. If
  the sprite mod reports the mon transformed but is not tracking a size
  (DYNAMAX GROW off), `charge` answers 1 anyway, so these FX never silently
  depend on that other row.
- `F.drawDim(G, vw, vh, alpha)` -- the maroon field wash (one `alpha` rectangle).
- `F.drawAura(G, x, y, w, h, alpha, t)` -- the additive red glow plus a rim.
- `F.newBurst` / `F.stepBurst` / `F.drawBurst` -- the faint explosion (a
  white-hot pop, three expanding rings, a smoke haze and a deterministic ember
  spray), `F.BURST_LIFE = 0.75 s`.

It draws nothing by itself and owns no clock: the screen drives it, so every
function is pure. It is a sibling file so it can be replayed by the fengari
harness with only `love.graphics` mocked, and to keep `battle_screen.lua`'s
200-local ceiling for the code that really touches the engine.

**The wiring (`battle_screen.lua`).** The DYNAMAX FIELD block:

- `Screen:scanDynamaxStates()` -- reads every on-field battler's state once per
  draw through the sprite mod's `dynamaxStateOf`, keeps the map for the sprite
  pass, and marks any battler that has ever been transformed (`__g9DynWasActive`).
- `Screen:drawDynamaxField()` -- raised right after `drawDynamaxBack()`, i.e.
  BEFORE the sprite pass, so the wash and the auras sit behind the creatures.
- `Screen:spawnDynamaxBurst(battler)` / `Screen:stepDynamaxBursts(dt)` /
  `Screen:drawDynamaxFieldFront()` -- the burst, spawned at the battler's own
  last drawn box, stepped from `Screen:update` with the other staged sequences
  (a held button cannot skip it) and drawn over the sprites, under the F/E band.
- The **held faint** lives in both sprite loops: a battler whose shown HP is 0
  is kept drawn (`dynHold`) while the sprite mod still reports it transformed
  (`known`) -- which is exactly what lets the sprite mod start and finish the
  shrink -- and only when `known` clears does the scene spawn one burst
  (`__g9DynBurstDone` guarantees one) and drop the sprite.

**Ending the darkening.** The wash alpha is the strongest `charge` on the field,
so it fades to nothing on its own as the shrink runs. Turn expiry and switch-out
both make the mon stop reporting a transformed state, so the wash ends within
the same shrink; a switched-out mon leaves `scanDynamaxStates`' field list
entirely, so the wash ends at once. A faint holds the mon (and so the wash) only
through the shrink, then bursts and ends.

**Options.** Two new Mod Manager rows, both ON: **DYNAMAX DARKEN** (the maroon
field wash) and **DYNAMAX AURA** (the red aura AND the faint burst).

**Optional, and never fatal.** The state comes from `g9-battle-sprites`'
`dynamaxStateOf`; the scene declares it an `optional_dependencies` entry. With
the sprite mod absent, `stateOf` answers nothing, no battler is ever marked
transformed, and every mon is drawn normally -- the battle is unaffected. A
missing module, a stub `love.graphics`, a nil argument or a raised error all
degrade to "draws nothing"; each screen call is additionally pcall'd.

**Harnesses.** `scratch/sim/test-dynamax-field.js` replays the module through a
mocked `love.graphics` -- **47/47**: option gating, the `charge` mapping
(including the GROW-off fallback), the wash rect, the aura glow, and the burst
lifecycle/determinism. `scratch/sim/test-dynamax-hold.js` extracts the REAL
delayed-faint block out of `battle_screen.lua` and replays it -- **27/27**: a
healthy mon is not held, a fainting transformed mon is held while `known`, the
burst fires exactly once when `known` clears, a never-Dynamaxed faint and a
turn-expiry/switch-out get no burst. `run-dynamax-flow.js` stays **66/66** and
`run-evolution-flow.js` stays **48/48**.

**User action.** Re-export **`g9-battle-scene`** (v3.7.0) and
**`g9-battle-sprites`** (3.2.0). `g9-battle-engine` is unchanged. LÖVE cannot be
run in the preview, so the in-game confirmation is yours.

## Terastallization sequence (v3.8.0; crystal geometry + break reworked v3.8.1; shard-table crash fixed v3.8.2; cocoon built from the shards + reliable film v3.8.3; shard tip glint removed v3.8.4)

**What it is.** When a Pokemon Terastallizes -- the player's own activation, or
an **enemy/boss** whose tera `battle_forms` activates on its own turn -- the
scene now plays a full animated transformation before the crystal film appears.
It is built to match a reference clip the user supplied, whose first ten seconds
are the whole sequence: translucent crystal **shards** materialise around the
creature and gather; the **same shards** fly inward and lock together into a
faceted crystal **cocoon** that encloses it while the creature **whitens**
inside; the cocoon flares into a solid white-cyan **flash**; the **shards it is
made of** fly back outward and dissolve; and the creature stands **revealed**.
The persistent tera look the user keeps is unchanged -- it is still
`g9-battle-sprites`' cut-crystal voronoi film, in its own type colours -- but the
film is now placed on the creature at the moment the construct **breaks**, so the
sequence reveals the transformed Pokemon underneath it instead of the film being
worn from the first frame.

**The module (`tera_anim.lua`, new).** A self-contained sequence with one
export, `mod.exports.battleSceneTeraAnim` (`E`):

- `E.new(opts)` -- builds a clip from the battler's own box (`x`/`cx`/`top`/
  `feet`/`w`/`h`/`side`, plus `vw`/`vh` and an optional `seed`). Radii are
  ratios of the DRAWN sprite box, so a small mon and a hulking one get a
  proportionally sized show; nothing is a fixed pixel size.
- The timeline is exported and load-bearing: `E.REVEAL_T = 4.32`,
  `E.END_T = 6.00`, `E.SHELL_T = 1.50`, `E.SHELL_FULL = 2.90`,
  `E.FLASH_START/IN/OUT/END = 3.90/4.22/4.44/4.82`, `E.BREAK_T = 4.42`.
  (v3.8.1 lengthened the whole show to ~6s to match the reference and to give
  the completed dome a **held** beat on screen instead of flashing almost the
  moment it formed.)
- `E.step(clip, dt, hold)` -- advances the clock; `hold` freezes it (used to
  wait for the filmed sheet). It fires `clip.onReveal` **once**, clamped exactly
  to `REVEAL_T`, and sets `clip.done` at `END_T`.
- `E.whiten(clip)` -- 0..1: how white the creature is drawn inside the shell.
  Ramps in from 1.60s, holds through the flash, and is fully **released** by
  4.90s so the transformed creature's own colours return under the film.
- `E.flashAlpha(clip)` / `E.flashColor(clip)` -- the full-screen flash. Solid
  white from `FLASH_IN` to `FLASH_OUT` (the window the reveal sits inside), icy
  blue on the way in and pale cyan as it falls away.
- `E.drawBack(clip)` / `E.draw(clip)` -- the two draw layers (see below).

**How the crystal is built (v3.8.1; the cocoon is now the shards, v3.8.3).**
Nothing is a flat shape. *Shards* are pointed hexagonal **bipyramids** drawn as a
solid deep-blue back, a shadowed left half, a sheer lit right half that lets the
back show through, a hot top-right facet, a white specular spine, a tip glint and
a dark outline -- so each reads as a translucent gem point with real light/dark
facets. **There is no separate shell geometry.** v3.8.1 built the enclosure as a
triangulated dome (`buildShell`), and it read as its own object rather than as
the crystal the clip gathers -- so v3.8.3 deletes it: the same blue shards that
gather ARE the cocoon. Each shard carries a HOME on an ellipsoid around the
creature (a Fibonacci distribution over the unit sphere, mapped onto the
ellipsoid), and from `SHELL_T` to `SHELL_FULL` it flies inward, turns to lie
along the surface and locks there, so the assembled swarm reads as a closed
crystal shell with real depth. The shards on the far side of that ellipsoid
(`fz < 0`) are composited BEFORE the creature and the near ones AFTER -- the same
depth cue the gather ring used, now blended continuously as each shard crosses
the shell. At the break **those same shards** fly back outward along their own
normals, tumble, arc **down** under gravity, fade, and leave fine drifting dust
and a ground-squashed shockwave.

The shard field, the cocoon homes and the settling sparkles are frozen in the
clip from a small deterministic LCG (`seed` defaults to `20261020`), so the show
is stable frame to frame and the harness replays exactly what the game draws.
`E.whiten` is what lets the reveal read: for most of the show the creature is a
bright shape inside the cocoon, and it resolves back into colour as the shards
burst and the film lands. The timeline's beats, in order: `0.00-1.50` GATHER;
`1.50-2.90` COCOON; `2.90-3.90` HOLD; `3.90-4.22` flash in; `4.22-4.44` solid
flash (the reveal); `4.42-5.40` BREAK; `5.40-6.00` SETTLE.

**The wiring (`battle_screen.lua`).** The TERA block. (Every helper lives on
`Ev.tera` rather than in a file-level local: `battle_screen.lua`'s body is at
PUC Lua's 200-local ceiling, the same reason `dynamax_anim`/`dynamax_field`
hang off `Ev.dyn`.)

- `Ev.tera.isId(id)` -- does gimmick id `id` name Terastallization? Matches on
  the NAME (`"tera"` substring, or `"tstl"`) and refuses `mega`/`dynamax`, the
  same forgiving rule the other two blocks use.
- `Ev.tera.formsExports()` / `Ev.tera.liveOf(mon, battler)` -- `battle_forms`'
  own `describe()` (cached on success) and a forgiving "is this mon
  Terastallized RIGHT NOW?". Since v3.8.3 the live test is the **engine's own
  record first** -- `mon.teraActive`, then `g9-battle-engine`'s
  `isTerastallized(battle, mon)` -- because `describe()`'s payload is not a
  shape this scene can rely on; `describe()` is the fallback, and a missing
  mod/export, a raised error or a payload with no `tera` block all answer false.
- `Ev.tera.engineExports()` / `Ev.tera.engineTypeOf(mon)` -- the engine's public
  exports (cached) and the mon's Tera type as the engine knows it
  (`getTeraType(mon)`, else `mon.teraType`/`mon.battleFormsTeraType`). This is
  the same value the engine's own combat code uses.
- `Ev.tera.liveTypeOf(mon, battler)` -- the mon's live Tera **type**, or nil.
  Gated on `liveOf` (a stored Tera type is a property a mon has before it ever
  transforms), then engine-first with `describe()` as the fallback.
- `Screen:startTeraAnim(mon, already)` **stamps** that type on the battler as
  `liveTeraType`, and `resolveSprite` forwards it to the sprite seam as
  `ctx.liveTeraType` (a cheap per-draw read: the battler stamp, else the engine's
  type only while `mon.teraActive`). That is what makes the crystal film appear
  at the break regardless of `battle_forms`' payload shape.
- `Screen:teraStageMon()` -- which mon a tera on its way belongs to: the owner
  the screen recorded, else the first player battler.
- `Ev.tera.holdStamp()` -- the value written to `battler.__g9TeraHold`: an
  absolute deadline on the engine clock (`love.timer.getTime() + HOLD_LIMIT`,
  `Ev.tera.HOLD_LIMIT = 6.0`), or `true` when there is no clock to read. The
  sprite mod reads the very same number, so the hold is **self-expiring**: the
  reveal beat clears it long before, but if a clear is ever missed the film
  still lands inside the window instead of never.
- `Screen:startTeraAnim(mon, already)` -- builds the clip from the battler's own
  box and `artShift`, sets `battler.__g9TeraHold = Ev.tera.holdStamp()`, stores
  `self.tera`, wires `clip.onReveal = revealTera`, and sets `"<name> is
  Terastallizing!"`. `already` is true on both real paths, so the reveal beat
  must not run the activation a second time (the `false` path is kept only for
  a build that stages before activating).
- `Screen:revealTera()` -- the reveal beat (the frame the construct BREAKS). If
  the activation has not run yet it runs the real `applyGimmickActivation`;
  otherwise it is skipped. Either way it clears `__g9TeraHold` so the film is
  placed now, and sets `"<name> Terastallized!"`.
- `Screen:updateTera(dt)` -- run from `Screen:update` (phase-independent, so a
  held button cannot skip it), with the same reveal-wait cap the other clips
  use (`Ev.tera.HOLD_MAX = 2.0`) and the same `Ev.tera.SAFETY = 8.0` release, so
  a clip that never finishes still hands the turn back.
- `Screen:drawTeraBack()` / `Screen:drawTera()` -- the BACK layer (ground glow +
  far shards) is raised right after `drawDynamaxBack()`, i.e. before the sprite
  pass; the FRONT layer (near shards, beams, flash, break, sparkles) right
  after `drawDynamax()`, over the sprites and under the F/E band.
- `Screen:teraFx(battler)` -- the whitening the sprite pass should apply to the
  transforming battler this frame (both sprite loops fold it into their blit),
  or nil for every other battler.

**Staging the change -- one activation per acting Pokemon, then a turn-opening set piece (v3.8.5, multi-actor v3.8.6).**
Every gimmick armed this turn is activated at the head of the move phase, and
the scene then stages whatever actually transformed.  `advanceResolving` samples
every on-field battler's live state (`Screen:sampleGimmicks`), then runs one
activation per **armed actor** in the turn's own action order
(`Screen:armedActorsInActionOrder` -> `Screen:activateArmedGimmicks` ->
`Screen:applyGimmickActivation`), and diffs the sample
(`Screen:buildGimmickQueue`) into an ordered queue of the mons that changed.
A batch-only turn (no player gimmick) still raises the activation once, which is
where the enemy trainer's own choice lands (battle_forms' `turn_started`
listener) -- so the player's pick(s) AND the enemy's can all take effect on the
same turn.

**One gimmick per acting Pokemon (v3.8.6).** battle_forms holds a *single*
armed slot (`exports.arm()` toggles one id), which is why the old scene let a
second mon's FORMS pick **supersede** the first and only the last fired.  The
scene now keeps its own per-slot record (`self.gimmickArmed[slot] = {mon, id,
label}`, reset in `Screen:beginTurn` and when the set piece ends) and, at the
head of the turn, re-arms each actor's gimmick through that one slot (focused on
that actor, so a move-substituting Dynamax/Z-Move arms against the right
battler) and raises `battle.turn_started` for it.  So two or more Pokemon -- on
either side -- can transform on the same turn, and each fires exactly once.  A
gimmick battle_forms refuses to re-arm (already spent this battle) is skipped
alone; the others still fire.  The queue is sorted by the turn's own **action
order** (`combat.orderedActorMons`, exported by g9-battle-engine as
`orderedActionMonsForGen1`, else the engine's documented `battle.__g9Gen1Order`)
and the clips play in exactly that order, so whoever acts first transforms
first.

Every queued battler is put under its own hold up front (`__g9FormHold` /
`__g9DynHold` / `__g9TeraHold`) so a later one cannot flash its new form, film
or size while an earlier one plays; each hold is dropped at that clip's own
reveal beat.  The clips play one after another with the turn held the whole way
-- `Screen:advanceResolving` refuses to step the turn while any clip is live,
and `Screen:finishGimmickAnim` plays the next clip or hands the turn back -- so
no move's damage is delivered until the whole set piece (including the mega/Tera
**sprite swap** and the Tera **crystal-film deployment**) is really over.  A clip
that cannot be built drops that battler's hold so the change is at least
visible, and jumps to the next.
This supersedes the earlier "activate first, hide the film, reveal at the break"
staging and the player-before/enemy-after snapshot (see the v3.8.1-v3.8.3 notes
below for how the film itself reached the screen).  The activation is still
immediate and the film is still hidden by `__g9TeraHold` until the break.
An enemy/boss tera (or Dynamax, or mega) is caught by the same mechanism:
`battle_forms` activates it from its own `turn_started` listener
(`src/trainerai.lua`'s `onTurnStarted`), which runs *inside* the scene's first
activation emit -- the scene never sees the moment directly.  The before/after
diff (`Screen:sampleGimmicks` before, `Screen:buildGimmickQueue` after)
therefore catches the enemy gimmick exactly as it catches the player's own, and
stages it with `already = true` in action order.  `battle_forms` is a separate
public mod and is not edited for this.

**The sprite mod's part.** `g9-battle-sprites` paints the film from the same
state, read the same way (v3.8.3): `mon.teraActive` + the engine's `getTeraType`,
with the scene's `ctx.liveTeraType` declaration and `battle_forms`' `describe()`
as fallbacks. A mon whose tera is already active would otherwise wear the film
through the whole show, so `teraHoldActive` answers true while the battler
carries `__g9TeraHold` -- a boolean ("held until cleared") OR a number (an
absolute `love.timer` deadline, see `holdStamp`) -- and `teraTypeOf` answers nil
then, in both the live read and the declared-raid-boss branch. The scene sets the
flag on staging and clears it at the reveal break, so the crystal layer lands
exactly on the reveal the user asked for; the numeric deadline is the backstop
that stops a missed clear from hiding the film forever. With no flag the behavior
is unchanged, and an unreadable clock degrades to "paint". The voronoi crystal
asset and its type tinting are untouched.

**Crash fix -- a malformed shard table, and a depth guard so it can never
recur (v3.8.2).** The v3.8.1 shard spine built its vertex table as
`{ ax, ay, tx(w * 0.16, 0), dx, dy, tx(-w * 0.16, 0) }`. A function call in a
Lua table constructor's **last** field expands to *every* value it returns, so
that table handed `love.graphics.polygon` **seven** components, and LÖVE refuses
an odd count outright (`Number of vertex components must be a multiple of two`).
The throw came out of `shard`, out of `drawShards` -- *before* its own `G.pop()`
-- and into the caller's `pcall`, which only **warns** (once), so the failure was
silent and leaked **one** `love.graphics.push` per frame. Two layers (back +
front) leaked per frame, and ~1.1s into the ~6s clip the graphics stack hit
LÖVE's `MAX_USER_STACK_DEPTH` of 128; the next push anywhere in the game threw
`Maximum stack depth reached (more pushes than pops?)` -- which surfaced on the
battle screen at the first unrelated `push` (`drawScaledText`), not in this file.
Two fixes: the two waist points are **hoisted into locals**
(`local sx1, sy1 = tx(w * 0.16, 0)` ...) so the table is a clean eight, and
`E.drawBack`/`E.draw` now run each piece through a `part(fn, ...)` helper -- a
`pcall` that *also* restores the graphics stack to the depth it had before the
piece ran (`love.graphics.getStackDepth`, LÖVE 11+; a plain `pcall` where it is
missing). One failing piece can therefore no longer blank the rest of the show
**nor** leak a push, whatever the bug. The harness mocks in
`scratch/sim/tera_harness.lua` / `tera_depth.lua` now validate vertex tables the
way LÖVE does, and `scratch/sim/run-tera-depth.js` replays an arbitrary source
through them: the shipped 3.8.1 module reproduces the exact crash (first error at
`t=0.08s`, depth climbing to 643, ending in the reported message), while the
fixed module replays the full clip + reveal hold at **2024 pushes / 2024 pops,
final depth 0, 0 errors**.

**The white tip glint is gone (v3.8.4).** Each shard used to stamp a small white
four-pointed diamond over its sharp top point -- `shard()`'s final `G.polygon`
fill, a `±h*0.16` by `±w*0.20` rhombus centred on the top vertex, drawn last on
top of the lit/shadow halves, the dark outline and the slim white spine. It read
as a separate white blob on the tip rather than as part of the crystal, so at the
user's request the block is deleted: the point now ends in the shard's own
lit/shadow facets and the white specular spine, with nothing stamped over it. The
`part` depth guard, the cocoon build, the shard geometry and every other beat are
untouched.

**Optional, and never fatal.** The clip is a sibling file loaded by `main.lua`
(`loadSibling(mod, "tera_anim.lua")`) with its own export; a missing module, a
stub `love.graphics`, a nil field or a raised error all degrade to "draws
nothing", and `startTeraAnim`/`updateTera`/the draws are additionally pcall'd, so
a costume can never abort a turn. `g9-battle-sprites` remains an
`optional_dependencies` entry: with it absent the sequence still plays and the
turn still resolves, there is simply no film at the reveal. Since v3.8.2 each
drawn piece additionally runs through the depth-restoring `part` guard, so a
fault in one beat of the clip can neither abort the rest of the show nor leak a
graphics push.

**Harnesses.** `scratch/sim/run-tera.js` renders the **real** module through a
mocked `love.graphics` and contact-sheets every ~0.1s of the whole 6s show
(gather, cocoon + hold, flash, break, settle, and a small-size run), and was
iterated against the `vision` tool until the frames read as crystal -- v3.8.3
re-checked every sheet after the cocoon rework and `vision` confirms the
enclosure is a mass of separate angular blue shards with **no** smooth
dome/bubble, and that the shards burst outward and leave the creature revealed
(and that the creature is never hidden at the end). `scratch/
sim/run-tera-flow.js` extracts the REAL TERA block out of `battle_screen.lua`,
stands up every file-level name it closes over, loads the real `tera_anim.lua`,
and drives the Screen methods -- **54/54**: the timeline invariants (reveal
inside the flash, break after the reveal, flash ends before the clip), a clip
finishing with its whiten and flash released; the deferred player path (staged
-> hold set -> activation runs exactly once at the reveal -> hold cleared ->
released -> the turn advances once); the **real** player path (activate first ->
`startTeraAnim(mon, true)` -> hold set -> live read true -> NO re-activation at
the reveal -> hold cleared -> released); the enemy path (snapshot false ->
caught -> hold set -> activation NOT re-run -> cleared -> released); `isId`
accepting `tera`/`terastallize`/`tstl` and refusing `mega`/`dynamax`/nil; the
forgiving `liveOf`; the refusals (no mon, or a second start while one is
running); and (v3.8.3) the **engine live read** with `battle_forms` refusing to
be found -- `engineTypeOf`/`liveTypeOf`/`liveOf` answer from
`mon.teraActive` + the engine's `getTeraType`, a non-live mon answers nil/false,
a missing engine falls back to the mon's own `teraType`, and `startTeraAnim`
stamps `liveTeraType` on the battler. The sprite mod's own live read is
unit-tested against its real source the same way (`teraTypeOf`: engine-live ->
type, declaration via ctx/battler -> type, the hold suppresses both, `???` ->
nil, the `battle_forms` describe fallback still works, TERA ART off suppresses).
`compile-all.js` is green (sprites 6/6, scene 22/22).

**User action.** Re-export **`g9-battle-scene`** (v3.8.4) **and
`g9-battle-sprites`** (3.2.4) -- both changed this round (the scene's shard-tip
glint removal, the sprite mod's restored crystal-pattern loader). `g9-battle-engine`
is unchanged. LÖVE cannot be run in the preview, so the in-game confirmation is
yours.

## The save sanitizer -- a battle never leaves a cycle in the save (v3.8.8)

**The crash.** Saving a Crystal playthrough could die with
`src/core/SaveSerializer.lua:13: stack overflow` (the "Details saved to
lua-error.log" screen), reached from the update loop's menu handling. The
engine's save writer is a plain recursive table walk with **no cycle detection
and no depth cap on the write side** (its `MAX_DEPTH = 128` guard is in the
reader only), so it is only safe on a tree.

**Why a tree stops being a tree.** On Gen 2 `battle.party` **is** `save.party`,
so any field a battle writes onto a party mon is serialized verbatim on the next
save. Two of g9-battle-engine's battle-scoped fields hold an *object* rather
than a scalar:

- `mon.__g9AbilityBaselineBattle` -- the live battle, stored so the ability
  snapshot can be scoped to one battle (`abilities/ability_dispatch.lua`, the
  round-186 snapshot). That battle's `.party` is `save.party`, so
  `save.party[i] -> battle -> battle.party -> save.party[i]` closes a cycle.
- `mon.__g9TransformPre` -- the pre-transform snapshot, whose `.battler` is the
  live engine battler and whose `.mon` is this same mon
  (`combat/modern_transform.lua`).

Both are meant to be cleared by the engine's own whole-roster `battle.ended`
sweeps, and normally are -- which is why this only bites intermittently. When a
battle boundary is missed (a fight that ends through a path that does not reach
the sweep, or a mon the sweep does not visit), the reference survives, and the
**next save** of that playthrough recurses forever. The player loses the file,
not just the fight.

**The guard (`battle_screen.lua`, `installSaveSanitizer`).** Wired to the
engine's own `save.writing` event -- emitted by `Game` / `Game2` / `Game3`
immediately after the world snapshot is folded in and immediately before the
serializer runs, on every write the player can trigger -- the scene now, for
every mon in `save.party`, every `save.boxes[*]` and `save.daycare`:

1. Runs g9-battle-engine's own documented reverts for the two object fields
   (`restoreNaturalAbility(mon)`, `revertTransform(nil, mon)`) so a stale
   snapshot is put back correctly rather than merely dropped; if the export is
   absent it clears the raw ability-snapshot triple itself.
2. Drops any mon field that is unserializable by construction: a table that
   reaches the mon again within **4 hops** (a true cycle -- bounded so it can
   never walk an arbitrary live object graph), or a `function` / `userdata` /
   `thread` value (the writer errors on those too).

A field that is merely a *shared* reference (a DAG edge -- e.g. two mons sharing
one `ivs` table) is deliberately **kept**: only a back-edge is a cycle. So a
persistent `mon.form`, `mon.item` and the modern `ivs`/`evs`/`stats` blocks are
never touched, and a clean save round-trips byte-identical. A save cannot be
taken mid-battle (the battle owns input), so a mon still carrying battle-scoped
state at `save.writing` has already left the fight and putting it back is the
correct post-battle shape. The whole handler is `pcall`'d: a sanitizer bug can
never stop a save.

**Harness (`scratch/sim/run-save-sanitizer.js`, 22/22).** Loads the **real**
`SaveSerializer.lua` and extracts the **real** `installSaveSanitizer` region out
of `battle_screen.lua`, then: the raw cycle reproduces the exact `stack
overflow`; after the handler the same save serializes; the engine path restores
the ability and clears both pointers; the no-engine fallback still clears them;
a benign shared reference survives; a function field is dropped; a clean save is
byte-identical; and boxes + both daycare shapes are covered.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v3.8.8).
`g9-battle-sprites` and `g9-battle-engine` are unchanged. LÖVE cannot run in the
preview, so the in-game confirmation is yours.

## A triple-battle no-reach fails ALONE, and the Gen 2 100%-catch fix (v3.8.9)

Three reported battle bugs, all fixed this round.

**1. A slot that cannot reach any foe no longer skips its allies' move
selection.** In a triple battle, ROUND 83's positional adjacency can leave an
acting slot with **zero** reachable recipients (a wing whose only live foes sit
in non-adjacent columns). `Screen:updateMoveSelect`'s final `else` used to call
`beginResolving()`, which abandoned the whole per-slot selection loop -- the two
other fielded mons never got their move menus at all. Now that slot's move is
queued as an **intended fail** (`Screen:queueAction(picked, nil, true)`, the
`fail` flag rides through `combat.lua`'s `toActingBattlers`) and the cursor
**advances** to the next slot, so the allies still choose. The engine announces
"X used MOVE!" and prints "But it failed!" (spending one PP) for that one
action, at its own place in the order, while every other actor resolves
normally. A self/field/side move (Protect, Swords Dance, ...) has no recipient
to be missing, so it still acts, with the first live foe as the field-side
placeholder the other branches also use.

**2. Surf / spread moves no longer silently do nothing.** The engine's
`resolveTurnActions` (g9-battle-engine) guarded its "used and failed" tail with
`if #live == 0 and failed`, but the **spread** path never sets `failed` -- so a
spread move that expanded to zero live targets (Surf with no adjacent opponent)
resolved to **nothing**: no announcement, no PP spent, no line. That is the
reported "the mon just doesn't act". The guard is now `if #live == 0`, so the
spread case announces the move and prints "But it failed!" exactly like the
single-target no-recipient case. (Requires **g9-battle-engine 4.4.4**.)

**3. The Gen 2 100%-catch.** The scene hands the running battle's own
`random` to the catch maths, and the two generations use **different shapes**:

- Gen 1 `battle.rng(a, b)` -> `a..b`, inclusive (the scene's own `buildBattle`
  `state.random`, literally `love.math.random(a, b)`).
- Gen 2 `battle.random(n)` -> `0..n-1` (`gen2/Battle.lua`, whose default
  `rand(nil, n)` is `love.math.random(n) - 1`).

`native.lua`'s `modernRoll` **probed the arity** -- it tried `random(0, max-1)`
first and accepted any number back. On **Gen 2** that calls the one-argument
roll as `rng(0, n)`, and LÖVE's `RandomGenerator:random(l, u)` computes
`floor(r * l) + 1` when `u` is nil, so it is **not an error**: it returns 1
every time. Every check passed, and every throw -- with **all three** formulas
(Gen IX, Gen II, Gen I, since the RNG contract is a property of the battle, not
of the selected formula) -- was a guaranteed catch. `modernRoll` now decides
the shape from the **generation** (`N.isGen2`), exactly as g9-battle-engine's
own `percentRoll`/`rangeRoll` do, and clamps the roll into range. Gen 1 was
already correct (its two-argument random lands in `modernRoll`'s intended
branch); this only ever bit a Gen 2 game.

**Harnesses.** `scratch/tests/catch_throw_test.lua` (23/23) now stubs LÖVE's
exact `RandomGenerator:random` semantics (so `rng(0, n) == 1` is *visible*
instead of hidden behind `math.random(0)`'s "interval is empty") and drives
both the native catch arms and the **real** `Screen:throwBall` on a Gen-1 build
(2-arg rng) and a Gen-2 build (1-arg rng): gen9/gen2/gen1 all stay far from
100%, and the two contracts agree. `scratch/sim/probe_spread.lua` proves the
engine half: a spread move with zero live targets now emits a `move` event, a
"failed" `message`, and spends exactly 1 PP (was 0/0/0), and a `fail`-flagged
action fails alone while its two allies still resolve (`ctrl_useMove == 3`).
`scratch/tests/triple_adjacency_test.lua` (102/102) adds the menu half: a
no-reach attack and a no-reach spread move both queue a `fail` action and
**advance** (never `beginResolving`), a no-reach self move is queued normally,
and a reachable target keeps the normal path.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v3.8.9) **and
`g9-battle-engine`** (v4.4.4) -- both changed this round. `g9-battle-sprites`
is unchanged. LÖVE cannot run in the preview, so the in-game confirmation is
yours.

## Catch follows the game's own generation, and reads the game's own ball data (v3.9.0)

The reported "catch is still 100%" was not the roll this time -- it was the
**default formula**. The scene shipped with `catch_formula = "gen9"` on every
boot, so a Gen 1 or Gen 2 game was being caught with **Scarlet/Violet's**
maths. SV's `bonus_level` (`max((36 - 2*level)/10, 1)`, applied below level 13)
inflates the rate for exactly the low-level wild Pokemon both Gen 1 and Gen 2
field, and for the very many species whose catch rate is already 255 it pushes
`a` to 1044480 -- the certainty ceiling -- so a thrown Poke Ball was a
guaranteed catch. The Gen 3.8.9 roll fix was correct and necessary, but it
could not help while the wrong generation's formula was running.

**1. `AUTO` is now the default and follows the running game.** A
Red/Blue/Yellow boot throws with Gen I's ItemUseBall maths; a
Gold/Silver/Crystal boot with Gen II's PokeBallEffect maths. That is the
"proper path": each generation's own capture maths, which is what
`src/battle/Catching.lua` and `src/battle/gen2/Catching.lua` implement.
`GENERATION 1` / `GENERATION 2` / `GENERATION 9` remain as explicit overrides
(a Gen 1 game can still be asked for SV maths), and an absent or unknown value
resolves through `AUTO`.

**2. The ball's own data now comes from the GAME'S merged ball registry, not
only the scene's fallback tables.** The scene's Gen 1 and Gen 2 arms were
transcriptions of the game's own modules, but they consulted their hardcoded
tables first, so a ball the game's loader had actually registered -- or a
mod's ball with its own multiplier -- was short-circuited. Now:

- **Gen 1** reads `data.balls` (filled by the game's own
  `src/battle/Catching.lua:registerInto`) for the ball's `randMax` /
  `hpFactor` / `wobbleFactor`, and honours `autoCatch` (the cart's
  never-rolls Master Ball), exactly as the game's
  `Catching.attempt(opts)` resolves `opts.ballDef or BALLS[ball] or
  DEFAULT_BALL`.
- **Gen 2** resolves the ball through `data.gen2Balls` **first** -- flat
  `multiplier`, conditional `specialty` fn, or `autoCatch` -- and only then
  falls back to the scene's tables, which is the same order the game's
  `Catching.rate` uses (`Catching.recordFor` first). The Gen 9 arm reads the
  registry `autoCatch`/`multiplier` before its flat SV table too, so a ball
  record's real catch factor is what lands.

**3. The Gen 2 catch roll matches the cart exactly.** PokeBallEffect catches on
`roll < rate`, i.e. `rate/256`, not `roll <= rate`; the arm was one check too
generous. Now `< a`, with `chance = a/256`.

**4. The RNG is passed in the generation-independent two-argument form.**
`Screen:throwBall` now hands over `battle.rng or battle.random`. `battle.rng`
is `love.math.random(a, b)` on the Gen 1 model and `loveStyleRng(battle.random)`
on the Gen 2 `Battle` -- both `a..b` inclusive over the SAME stream as
`battle.random` -- so the shape can never be mis-called as `rng(0, n)` (which
LÖVE resolves to a constant 1). `.random` remains the fallback for a battle
that has no `.rng`. This retires the shape hazard at the call site; `modernRoll`
keeps its generation switch as a second line of defence.

The throw opts also carry `evolveItem` now (the Gen II Moon Ball's specialty
condition), the same value the game's own `catchOptions` derives.

**Harnesses.** New `scratch/tests/real_catch_compare.lua` loads the game's REAL
`src/battle/Catching.lua` and `src/battle/gen2/Catching.lua` (from
`scratch/research/gen1recomp/`), plus the real `native.lua`, and proves:
`AUTO` resolves to the running generation and an explicit override is honoured;
the scene's **Gen 1 arm matches the game's own `Catching.attempt` on 7
scenarios** and the **Gen 2 arm on 8** (all within noise, at 4000 trials each,
with the merged ball registry present); and a full-HP Poke Ball is never
near-certain under `AUTO` on either generation (the old default's level-3
rate-255 guarantee now rolls at ~35%). `scratch/tests/catch_throw_test.lua`
stays green (23/23). `scratch/tests/triple_adjacency_test.lua` (102/102),
`scratch/tests/item_use_test.lua` (54/54), `scratch/tests/input_pacing_test.lua`
(52/52), `scratch/tests/special_boss_test.lua` (41/41),
`scratch/tests/boss_announce_test.lua` (17/17),
`scratch/tests/forced_switch_test.lua` (42/42) and
`scratch/tests/exp_share_screen_test.lua` (33/33) are unchanged by this round.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v3.9.0). The engine
(`g9-battle-engine` v4.4.4) and `g9-battle-sprites` are unchanged this round.
LÖVE cannot run in the preview, so the in-game confirmation is yours.

## RUN is wild-only, and the move cursor remembers (v3.9.1)

Two independent player-facing changes: the RUN command gains a policy, and the
move list gains a session cursor memory.

### RUN policy -- wild-only, with a boss confirmation

**User request (verbatim).** "player can run away from trainer battles, that's
undesired behavior, player should only be able to run away from pokemon wild
battles, and if player is in a boss fight, run should trigger a confirmation
(yes/no) to actually run away (cursor starts at no)."

Three verbs, split deliberately so the public primitive keeps its old meaning
(`battle_screen.lua`, the "RUN POLICY" block):

- `Screen:doRun()` -- leave now, unconditionally.  This is what the public
  `chooseMenuItem("RUN")` does, and so what the two-choice prompt API's own
  documented "leave" answer still does.  An external caller that has already
  asked its own question is not asked a second one.
- `Screen:attemptRun()` -- the **player's** RUN, gated: a trainer battle
  refuses, a wild boss asks first, everything else leaves at once.  Only
  `updateActionMenu`'s A handler routes here.
- `Screen:confirmBossRun()` -- the wild-boss YES/NO, raised through
  `mod.exports.askBattleChoice` (the screen's own two-choice prompt primitive),
  so it uses the same F/E box as every other question in this scene: the
  question wraps in F, YES and NO sit in E, **B answers NO**, and
  `default = 2` parks the cursor on **NO**, exactly as asked.

The trainer refusal prints the cart's own line -- the same string the engine's
`Battle:tryRun` emits (`src/battle/gen2/Battle.lua`):
`No! There's no running from a trainer battle!`.

"Boss" is the screen's own `self.isBoss` -- the `bossFight` layout's `boss`
flag, read once in `Screen.new`.  A trainer routed to the bossFight layout is
still a trainer fight, so the trainer arm refuses it before the boss arm is
reached.

**Safeguards** (the user's "prevent stack overflow, specially sensible for
game speed up scenarios").  `doRun` is idempotent -- `finishBattleExit`
already guards on its own `exited` flag, and the explicit check keeps a
doubled A, or a re-entrant update under speed-up, from reaching
`game.stack:pop()` twice.  `confirmBossRun` refuses to raise a second question
while one is pending or up, and the prompt API itself refuses to stack -- no
path here recurses.

### Move-list cursor memory -- session, per player Pokemon

**User request (verbatim).** "move window in battle pos memory ... how this
memory will go: it's per session (no permanence, clears at closing game) ...
it's per battle field slot on player side (if pokemon switches, we switch the
cursor memory values with them) ... cursor memory must survive battles, just
clears up at game quit/close.  if battle field pos 1 uses move slot 2, next
time pos 1 is to select a move, the cursor starts at move pos 2 instead of
move pos 1."

`moveCursorMemory` (declared at **chunk scope**, outside the installer
closure, so it lives for the session and dies with the Lua state -- no save
write, no reload).  It is keyed by the **mon table**, not by a slot index,
which is what makes "if pokemon switches, we switch the cursor memory values
with them" true for *both* kinds of switch: a player mon IS its `save.party`
entry, so the remembered slot travels with it across a positional SWITCH
(`queueSwapAction` -> the `swapQueue` pass) and across an ordinary PKMN
switch-in alike, and the same table carries the memory from one battle into
the next.

- `Screen:queueAction` records `picked.index` (the move slot just **committed**
  -- "USES move slot 2", not merely highlighted).
- `Screen:enterMoveSelect` opens the cursor on that slot when it is still on
  the list and still usable; otherwise it falls back to the first usable row
  exactly as before.  The fallback keeps a Choice-locked mon landing on its
  locked move rather than on a refused row, and a remembered slot that was
  forgotten, reordered away, or drained to 0 PP degrades to a real row.

**Safeguards.** Weak keys with integer-only values; the table is reachable
from nowhere the save writer walks, so it can neither leak a battle into a
save (the round-275 `SaveSerializer` `stack overflow` class) nor grow past the
handful of party mons.  The read is one hash lookup plus a bounded scan of the
move list, the write is one assignment, and nothing calls back into the
screen -- so a sped-up frame can hoard no nested passes through this code.

### Verified

New `scratch/tests/run_and_move_memory_test.lua` (runner
`scratch/tests/run_and_move_memory.mjs`) loads the REAL `native.lua`,
`combat.lua` and `battle_screen.lua` and drives the real methods -- **26/26**:
the public `chooseMenuItem("RUN")` still leaves at once; the player's RUN in a
trainer battle is refused with the cart's line; a wild non-boss RUN leaves at
once; a wild boss RUN parks and then raises the confirmation with the cursor
on NO and YES/NO labels; answering NO (A or B) leaves the battle running and
answering YES runs; a re-entrant `confirmBossRun` raises exactly one prompt;
`doRun` twice exits once.  On the memory side: a first open starts on slot 1;
committing slot 2 makes a later battle open on slot 2; a different mon starts
fresh; after a positional swap each mon keeps its own remembered slot; the
memory survives battles and is per-mon; and a forgotten or 0-PP remembered
slot falls back to a usable row.  `catch_throw_test` (23/23),
`triple_adjacency` (102/102), `item_use` (54/54), `input_pacing` (52/52),
`special_boss` (41/41), `boss_announce` (17/17), `forced_switch` (42/42) and
`exp_share_screen` (33/33) are unchanged.  All 22 scene `.lua` files compile
clean.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v3.9.1). The engine
(`g9-battle-engine` v4.4.4) and `g9-battle-sprites` are unchanged.  LÖVE
cannot run in the preview, so the in-game confirmation is yours.

## A scene battle evolves what it levels (v3.9.2)

**User report (verbatim).** "battle scene in gen 1 and gen 2 is blocking
evolution".

**Root cause.** Evolution after a fight is not a separate system: it is the
battle SCREEN's own last act.  Gen 1 runs
`require("src.pokemon.Evolution").checkParty(game, onDone, self.leveledUp)` from
`BattleState:finish` (`end_of_battle.asm:42-45`), and Gen 2 runs
`BattleState:startEvolutions` -> `Evolution.plan` -> the native
`Gen2EvolutionAnim` when the battle is over (ExitBattle's WIN arm).  A battle
drawn by this scene never reaches either override -- `finishTurn`/`throwBall`
just set `outcome` and `phase`, and the screen is popped directly -- so the
sweep was simply never called.  Nothing else was suppressing evolution: neither
`g9-battle-engine` (which stopped owning evolution at 4.5.0) nor `g9-evolutions`
(which owns the evolution DATA, not the trigger) can run a battle's after-battle
beat.  The scene is the screen, so the scene owes the sweep.

**The fix -- the native WIN arm, restored.** `Screen:updateOver` no longer exits
straight away; it calls the new `Screen:beginAfterBattleExit`, which asks the
generation backend (`native.lua`) to run the after-battle sweep and, only once
that is done, performs the real exit (`finishBattleExit` + pop).  The evolution
screens are pushed ON TOP of this one and play there, exactly as native pushes
them over its own battle screen, so the map music / `battle.ended` timing keeps
its native relationship to the evolution movie.

- **Gen 2** -- `N.runAfterBattleEvolutions` reads `Screen.g9EvolvableFlags`
  (Gen 2's own `wEvolvableFlags`: one bit per party slot, now filled by
  `Screen:awardFaintExp` from the model's per-level `level` events, the exact
  moment the cart sets it), calls the engine's own
  `Evolution.plan(data, party, flags, {timeOfDay})`, and drives the resulting
  plans through the native `Gen2EvolutionAnim` one at a time -- the native
  screen's own chaining, verbatim.  `Evolution.runsAfterBattle` is the native
  ExitBattle gate.
- **Gen 1** -- `N.runAfterBattleEvolutions` calls the native
  `Evolution.checkParty(game, onDone, battle.g9LeveledUp)`, where
  `battle.g9LeveledUp` is the mon-keyed set the Gen 1 EXP arm now stamps
  whenever `Experience.apply` reports a level gained (the same gate the native
  screen keeps, so a B-cancel leaves the mon waiting for its next level rather
  than re-offering every fight).  `checkParty` owns the whole movie -- its own
  `EvolutionState` screens and the apply -- so nothing is driven here.
- **Condition.** `beginAfterBattleExit` only offers the sweep on a WIN
  (`ExitBattle`'s `and $f / jr nz`); a loss, a draw, a run and a catch leave at
  once, exactly as the cart does, and no exp was awarded on those outcomes
  anyway.
- **Save beat.** ExitBattle's `farcall GivePokerusAndConvertBerries` sits in
  the same WIN arm immediately after `EvolveAfterBattle`, so it was missing
  from a scene fight for the same reason.  `N.afterBattleSaveEffects` runs it
  (Gen 2 only -- Gen 1 has no Pokerus or berry juice) right before the exit,
  pcall'd so a save mutation can never strand the player.  Silent by design,
  exactly as native.

**Safeguards.** `beginAfterBattleExit` is guarded by its own
`afterBattleExitStarted` flag, and its `exit()` closure by `battleExitDone`, so
a doubled A press, a re-entrant update under speed-up, or the Gen 1 case where
`checkParty` calls its `onDone` synchronously AND still reports that it staged
the sweep, can never pop the screen twice.  The engine module and the `Screens`
registry are `tryRequire`d, and the whole sweep is pcall'd by the caller, so a
missing or raising module degrades to the old straight exit instead of a battle
that cannot close.

### Verified

Two fengari harnesses over the REAL files:

- `scratch/sim/after_battle_evolution_harness.lua`
  (`scratch/sim/run-after-battle-evolution.js`) loads the real `native.lua` in
  **both** generation arms with stubbed engine modules -- **29/29**: a staged
  Gen 2 plan pushes exactly one `Gen2EvolutionAnim` with the evolvable flags and
  the captured `timeOfDay`, does not call `onDone` until the animation resolves,
  then pops it and chains; no flags / an empty plan / a loss stage nothing; the
  Gen 2 save beat rolls berry + Pokerus on a win and is skipped on a loss; the
  Gen 1 arm hands `checkParty` the real game and the mon-keyed set by identity,
  and a raising `checkParty` is contained; the exit contract is idempotent
  (including the Gen 1 synchronous-`onDone` case); and `N.buildBattle` +
  `N.awardExperience` driven through the real Gen 1 model stamps
  `g9LeveledUp` only when a level was actually gained.
- `scratch/sim/run-after-battle-flow.js` extracts the REAL
  `Screen:awardFaintExp`, `Screen:beginAfterBattleExit` and `Screen:updateOver`
  out of `battle_screen.lua` and drives them -- **21/21**: level events (and
  only those) set `g9EvolvableFlags` by party index; a win with nothing staged
  exits once; a staged win does not exit until `onDone` (and a second press /
  second `onDone` is a no-op); a loss never offers the sweep; a raising sweep
  is contained and still exits once; `updateOver` fires only on a press.

All 22 scene `.lua` files compile clean (luaparse 5.1).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v3.9.2). The engine
(`g9-battle-engine` v4.5.3) and `g9-battle-sprites` are unchanged.  LÖVE cannot
run in the preview, so the in-game confirmation is yours.

## Action-menu and bag cursor memory (v4.0.0)

**User request (verbatim).** "further adjustment to battle scene cursor memory,
keep memory for (first pos only, the other pos start at FIGHT action position)
for action menu, add cursor memory to each bag slot, add safeguards to prevent
overflow and this cache saves are to be cleaned at game close/quit."

Two new session caches, declared at CHUNK scope beside `moveCursorMemory` (so
they live for the Lua state and die with it -- no save write, no reload):

- **`actionMenuMemory`** -- the action menu's own cursor memory.  Keyed by the
  player **field slot** index, but only the **FIRST** slot is ever written or
  read: a fresh action menu for field pos 1 re-opens on the action it last
  **committed** ("FIGHT", "BAG", "PKMN", ...), while every other field slot
  answers nil and so can only open on **FIGHT** -- exactly the requested
  "first pos only, the other pos start at FIGHT action position".
  - Written in `Screen:updateActionMenu`'s A handler, at the same
    "committed, not merely highlighted" moment the move memory uses.  A
    refused RUN and an empty bag are still commits (the menu simply stays
    where it is).
  - Read in `Screen:enterActionMenu`, and honoured only through the new
    `Screen:actionMenuHas(id)` -- which walks the ACTUAL menu this screen is
    drawing (`crossSlots`/`gridRows`, else `menuOrder`) -- so a remembered
    SWITCH or CUSTOM that this battle cannot offer (no second living ally, no
    FORMS button) falls through to FIGHT instead of stranding the cursor off
    the menu.

- **`bagCursorMemory`** -- the bag's cursor memory, **keyed by bag slot**: on
  Gen 2 a pocket id (`ITEM` / `BALL` / `KEY_ITEM` / `TM_HM`, plus an
  `__lastPocket` marker) and on Gen 1 the single bag (`BAG`).  The value is
  the row+scroll the battle bag was left on.  `Screen:openBag` now calls
  `Screen:recallBagCursor()` before either bag opens:
  - `captureBagCursor` copies the engine's own WRAM bytes (`game.packCursor`
    on Gen 2, `game.bagListScrollOffset`/`game.bagSavedMenuItem` on Gen 1)
    into the session table -- so the row the LAST battle bag was left on is
    always saved.  Missing bytes are skipped, so a boundary wipe cannot erase
    a good memory.
  - `seedBagCursor` refills those engine bytes from the session table, but
    **only where the engine has none**.  The engine's own, fresher memory
    always wins while it is present, so this can never drag a bag back to a
    stale row the engine itself had already moved on from; and it puts back
    exactly what a battle boundary wiped (Gen 2's `CleanUpBattleRAM`
    `clearMenuCursors`, Gen 1's `InitBattleVariables`/`end_of_battle`) --
    which is what makes each bag slot remember across battles.

**Safeguards** (the user's "add safeguards to prevent overflow").  Both tables
are reachable from nowhere the save writer walks, so they can neither leak a
battle into a save (the round-275 `SaveSerializer` `stack overflow` class) nor
grow past their fixed key sets (one used action key, one per pocket).  Every
remembered number goes through `boundedInt`, which rejects non-number, NaN and
infinite values and clamps to a sane range, so a hand-written save or a broken
caller cannot push a bogus index into a menu.  Every read is one hash lookup
plus a clamp, every write one assignment, and nothing calls back into the
screen -- so a sped-up frame can hoard no nested passes.  Both caches are
cleared by closing the game (`chunk` scope): "these cache saves are cleaned at
game close/quit".

### Verified

`scratch/tests/run_and_move_memory_test.lua` (`scratch/tests/run_and_move_memory.mjs`)
loads the REAL `native.lua`, `combat.lua` and `battle_screen.lua` and now drives
the new methods too -- **41/41** (up from 26).  Added checks: a first slot
re-opens on the last committed action while slot 2 always starts on FIGHT; a
committed BAG is remembered into a later battle; a remembered SWITCH falls back
to FIGHT when the menu (list OR grid) does not offer it and is honoured when it
does; a non-string cursor is refused (the memory is unchanged); Gen 1 refills a
wiped `bagSavedMenuItem`/`bagListScrollOffset` pair to the exact same row and
leaves a live engine value alone; a non-finite cursor cannot corrupt the
session memory; and the Gen 2 branch rebuilds `game.packCursor`, restores
`wLastPocket` and each pocket's row+scroll, leaves a live pocket row alone and
refills a wiped one.  The pre-existing 26 (RUN policy + move memory) still pass,
and `input_pacing` (52), `item_use` (54), `catch_throw` (23), `triple_adjacency`
(102), `forced_switch` (42), `special_boss` (41), `boss_announce` (17),
`scene_guard` (15), `scene_prize` (19), `exp_share_screen` (33), `exp_share`
(32), `exp_share_e2e` (9), `exp_share_full` (8), `exp_share_gen2` (5),
`exp_share_gen2_announce` (8), `exp_share_gen2_bench` (3), `exp_share_native`
(14), `fantasy_combat` (61), `fantasy_layout` (117), `scene_background` (73),
`scene_bg_session` (7), `scene_build_party` (7), `sprites_anchor` (23),
`sprites_g9page` (8), `sprites_shadow` (19), `national_dex_beldum` (32),
`real_catch_compare` (24), `sample_verify` (147) and `scene_probe_real` (5) are
unchanged.  All 22 scene `.lua` files compile clean (luaparse 5.1).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.0 -- a feature,
so the minor carries 3.9 -> 4.0 per the single-digit rule).  The engine
(`g9-battle-engine` v4.5.3) and `g9-battle-sprites` are unchanged.  LÖVE cannot
run in the preview, so the in-game confirmation is yours.

## A caught Pokemon registers to the POKéDEX (v4.0.1)

**User report (verbatim).** "battle scene catch is not registering caught to
pokedex completeness".

**Root cause.** Marking the POKéDEX is not a separate system: it is part of the
SAME native method that files the catch, and this scene replaces that screen.

- Gen 1 -- `BattleState:storeCaughtMon` runs `markOwned(game, species)` (which
  sets `pokedex.owned[species]` and `pokedex.seen[species]`) and `stampOT`.
- Gen 2 -- `BattleState:pushCaught` runs `CheckCaughtMon` /
  `SetSeenAndCaughtMon` (`pokedex.caught[species]` + `seen`), `Mon.stampOT`,
  `stampCaughtData` (met place/time/level) and `Unown.registerCatch`.

A scene catch went through `Screen:finishBallThrow`, which added the mon to the
party (or the PC) and set `outcome = "caught"` -- but ran **none** of that, so
`save.pokedex` was never touched and the caught count never moved.  (`native.lua`'s
Gen 1 `N.catchAttempt` even says so in its own comment: "no captured tail here:
the scene owns the party/box filing" -- and the filing did not own the dex.)

**The fix.** New `N.registerCatch(game, mon, opts)` in `native.lua` is the
caught tail both generations' screens used to own, generation-split:

- **Gen 1** -- marks `pokedex.owned` + `seen` (through the engine's own
  `BattleState.markOwned` when it is exported), then `BattleState.stampOT`.
- **Gen 2** -- `Mon.stampOT` first (exactly as `TryAddMonToParty` /
  `SendMonIntoBox` write `wPlayerName`/`wPlayerID` before filing), then
  `pokedex.caught` + `seen` (reading `knew` BEFORE stamping, the cart's
  `CheckCaughtMon` order), then `Catching.stampCaughtData` with the same opts
  `BattleState:stampCaughtData` builds (version/save/data/timeOfDay/map/
  backupMap/playerGender), then `Unown.registerCatch`.

It returns `(isNew, species)` -- `isNew` is whether the row was not already
caught, the flag the native screens read to decide whether to show their
"new POKéDEX data" beat.

`Screen:finishBallThrow` calls it right after the party/box filing and then
emits the native `pokemon.caught` event with the native payload
(`battle/mon/species/isNew/ball/destination/game`), pcall'd so a raising
listener can never strand the battle on the caught screen.  Every engine module
is `tryRequire`d and every call pcall'd, so a missing module degrades to the
direct dex marking rather than breaking the catch.

The same ownership gap broke the **seen** side of the dex: native stamps
`pokedex.seen[species]` while it LOADS each enemy mon (`LoadEnemyMon`'s "Saw
this mon" -- gen1 `BattleState.lua:781/912`, gen2 `BattleState:markSeen`), and
the scene never did.  New `N.markSeen(game, mon)` (spelled the same on both
generations, so no split) is called:

- in `Screen.new` for every enemy actually standing on the field, and
- in `Screen:advanceEnemyReplacement` for a benched trainer mon the moment it
  is really sent in -- matching native's per-send-in stamping, so a trainer's
  never-fielded Pokemon is not marked seen early.

### Verified

`scratch/tests/catch_throw_test.lua` (`scratch/tests/run_catch_throw.mjs`)
loads the REAL files and now covers the registration too -- **34/34** (up from
23).  Added checks: `N.registerCatch` on Gen 1 creates the dex when absent and
marks `owned`+`seen`, reports a repeat as not new, and survives a save with no
`pokedex` at all; the Gen 2 branch marks `caught`+`seen` and reports a repeat
as not new; `N.markSeen` creates the dex and stamps `seen` ONLY, and tolerates a
missing game/mon; and a REAL caught `Screen:finishBallThrow` adds the mon to the
party, registers `pokedex.owned`/`seen`, emits `pokemon.caught` with
`isNew = true` and `destination = "party"`, and ends in the over phase with
`outcome = "caught"`.  The pre-existing 23 (the catch formula/RNG contract and
the real `throwBall` rates) still pass, and all the other scene suites
(`run_and_move_memory` 41, `input_pacing` 52, `item_use` 54, `triple_adjacency`
102, `forced_switch` 42, `special_boss` 41, `boss_announce` 17, `scene_guard`
15, `scene_prize` 19, `exp_share_screen` 33, `exp_share` 32, `exp_share_e2e` 9,
`exp_share_full` 8, `exp_share_gen2` 5, `exp_share_gen2_announce` 8,
`exp_share_gen2_bench` 3, `exp_share_native` 14, `fantasy_combat` 61,
`fantasy_layout` 117, `scene_background` 73, `scene_bg_session` 7,
`scene_build_party` 7, `sprites_anchor` 23, `sprites_g9page` 8,
`sprites_shadow` 19, `national_dex_beldum` 32, `real_catch_compare` 24,
`sample_verify` 147, `scene_probe_real` 5) are unchanged.  All 22 scene `.lua`
files compile clean (luaparse 5.1).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.1 -- a fix).  The
engine (`g9-battle-engine` v4.5.3) and `g9-battle-sprites` are unchanged.  LÖVE
cannot run in the preview, so the in-game confirmation is yours.

## Real species names in battle, and lead pre-warm (v4.0.2)

**User report (verbatim).** "we need to show ... pokemon by their right species
name: there shouldn't be ponyta-galar, it should also by named ponyta ... only
exclusions are mega forms, zygarde, white kyurem, black kyurem."

**The name.** `battle_screen.lua`'s `displayName` -- the single funnel for every
send-out line, faint line, status line, gimmick line and HUD name box (30 call
sites) -- used to end its search with `mon.name or mon.species`, so a mon with
no nickname and no `name` field fell through to the raw species ID, which for an
alternate form is a data slug (`PONYTA_GALAR`).  It now prefers the species
record's own `name` (`Data.pokemon[shown].name`), resolving `shown` the same way
the sprite path does: a Transform's presented species, else the form the mon is
wearing, else its own species; `mon.name` is the last resort before `???`.

**Where the nice name comes from.** national_dex's own record for a form carries
the slug as its `name` (it only uppercases it), so the records are normalised
once at load by **g9-gui 3.0.4**'s `ui/display_names.lua`, which patches each
form record's `name` to its base species' name -- leaving `id` alone, and the
Mega/Zygarde/Kyurem families the only exceptions.  The scene reads whatever the
record says, so it is correct with or without that mod, and any future naming
source (a generator with its own spellings) flows through unchanged.

**Lead pre-warm.** `Screen:prewarmLeads()` now runs at the end of `Screen.new`,
asking g9-battle-sprites to bake both leads' sheets the moment the screen
exists.  The throw beat's own `prewarmSlot` already began the bake when the
ball's flight started, but any intro narration ahead of the throw was wasted
head start; asking at construction gives the sheet the whole intro.  Only the
two leads are pre-warmed -- the bench is sent out later, and warming the whole
roster at once would split the sprite mod's per-frame budget across sheets
nobody is waiting on.

### Verified

`luaparse 5.1` clean on all 22 scene `.lua`.  The g9-battle-sprites fengari
harness (which loads the REAL `main.lua` and now also drives the retry latch)
is green, and the scene's own suites are unchanged.  LÖVE cannot run in the
preview, so the in-game confirmation is yours.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.2 -- a fix).
Pair it with **`g9-gui` v3.0.4** (which normalises the record names) and
**`g9-battle-sprites` v3.3.1** (the faster, progressive send-out bake).  The
engine (`g9-battle-engine` v4.5.3) is unchanged.

## Pokemon learn moves during a scene battle (v4.0.3)

**User report (verbatim).** "pokemon should learn moves during combat in battle
scene (it should be asked an pause battle while the pokemon learns the move)
usual flow is that if pokemon level ups at the end of the turn and is to learn
a move by level, next turn doesn't follow until it's either decided not to
learn or learnt (learn flow resolved)."

**What was wrong.** A scene battle pays experience through its own award seam,
not the native screen's queue, and neither half of the learn flow existed there.
Gen 2's `awardExperience` already emitted a textless `{kind="choose-forget"}`
record for a full moveset, but `advanceResolving` had no branch for it, so the
record fell through the "no text" path and the fifth move was silently never
learned. Gen 1's scene arm called the pure `Experience.apply` directly, which
only levels -- it never re-issued the per-level move checks at all, so a Gen 1
scene battle neither announced a level-up nor learned anything.

**The flow now (both generations).** `native.lua`'s Gen 1 `applyShare` mirrors
the native queue (`BattleState:awardExp` -> `learnMove`): for each level the mon
reached it emits a `{kind="level", text="X grew to level N!"}` line and then,
per move that level grants (`Experience.movesLearnedAt`), either appends the
move and emits a `{kind="learn", text="X learned Y!"}` line when a slot is free,
or emits `{kind="choose-forget", mon=..., move=..., moveName=...}` when all four
are taken. (Gen 1 scene battles therefore now show level-up text they used to
omit.) Gen 2's engine emits the same family -- `level`, a `message` for a free
slot, and `choose-forget` with a party `index` and a move entry.

**The pause.** `Screen:beginMoveLearn(event)` (battle_screen.lua) resolves the
record to a mon + move id (Gen 1: the record's own `mon`/`move`; Gen 2: party
`index` + the move entry's `id`, read off `battle.party`, mirroring the engine's
own `Battle:resolveForget`), parks the turn in `self.learn`, and pushes the
game's own **`src.ui.MoveLearnMenu`** through the same `Screens.push` the bag
and party pickers use -- so the player answers with the games' real
TryingToLearn / forget-list / AbandonLearning flow, HM guard and all, rather
than a re-implementation. `Screen:advanceResolving` gained an early `if
self.learn then return end` and a `choose-forget` branch placed *before* the
text/last-resort branches, so a textless record now starts the pause instead of
being skipped. The screen stack only updates its top state, so the battle behind
the menu is genuinely frozen. The menu's `onDone` clears the park, raises
`pokemon.move_learned` when the move was taken (the engine raises it in
`Battle:resolveForget`; the menu writes the slot itself), re-points the in-play
battler's move list at the mon's table, and calls `advanceResolving` again -- so
the next queued beat (and only then the next turn) follows whether the player
learned the move or gave up on it.

### Verified

`luaparse 5.1` clean on both changed files. A new fengari suite
(`scratch/tests/learn_move_test.lua` + `run_learn_move.mjs`, **20/20 green**)
loads the REAL `native.lua`, `battle_screen.lua`, `combat.lua` and `hp_bar.lua`
in one Lua state and drives both halves: the Gen 1 award seam (free-slot learn
line + append + `pokemon.move_learned`, full-moveset `choose-forget` with
nothing appended, an already-known move skipped, multi-level gains learning
each level's move in order, no level-up meaning no learn events) and the screen
hook (`beginMoveLearn` pushing `MoveLearnMenu` and parking, `advanceResolving`
refusing to step while parked, learn/decline both resuming the queue via
`onDone`, a queued `choose-forget` consumed into a push, the Gen 2 `index` +
move-entry shape, and the guard cases that decline). The existing exp-share
suites stay green (native **14/14**, screen **33/33**), and both runner files
now raise fengari's local-variable limit for the scene file, whose factory
exceeds Lua's 200-local ceiling (LuaJIT, which LÖVE runs, accepts it).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.3 -- a feature).
The engine (`g9-battle-engine` v4.5.3), `g9-gui` (v3.0.4) and
`g9-battle-sprites` (v3.3.1) are unchanged.  LÖVE cannot run in the preview, so
the in-game confirmation is yours.

## The scene loads again, and a raid boss transforms as it appears (v4.0.4)

**What it fixes.** The Mod Manager reported

```
mods/g9-Battle-Scene/main.lua:48: mods/g9-Battle-Scene/battle_screen.lua:10964:
function at line 186 has more than 200 local variables
```

and marked the mod `[failed]`, so `g9-battle-sample` fell back to the native
screen for every layout battle (and the "BATTLE SCENE is ON but could not be
reached" line was the symptom, not a second bug).

**Why it happened.** The factory (line 186, `return function(mod)`) had **201
active locals**, one over the line.  LÖVE runs LuaJIT, and LuaJIT caps a
function at 200 active locals (`LJ_MAX_LOCVAR = 200`) -- exactly the ceiling the
test harnesses had been raising for fengari.  The v4.0.3 section's aside
("LuaJIT, which LÖVE runs, accepts it") was wrong, and the file had been one
helper away from that line for a while.

**The fix.** The factory's **58 top-level `local function` helpers are folded
into one table, `FN`** -- `local FN = {}` near the top, each helper written
`FN.name = function(...)`, and its call sites `FN.name(...)`.  Nothing else
changes: the helpers close over the same factory locals, and the scope-safe
rewrite left method definitions, table keys and function parameters alone.
The factory now sits at **145 active locals** (`battle_screen.lua` compiles
under fengari's stock 200 limit again), with the original headroom restored.

**And a wild raid boss now plays its transformation as it appears.** A wild
SPECIAL BOSS (`special_boss.lua`'s `battle.g9BossKind` -- tera / dynamax /
gigantamax / mega) used to fade in ALREADY transformed: the sprite mod painted
the declaration (v2.8.1) but nothing ever played the sequence.  It is now the
intro's own beat:

- `Screen:buildIntroSequence` appends `{ kind = "bossTransform" }` right after
  the boss's own `fade` beat, gated on `Screen:bossTransformKind()` (a BOSS
  layout plus a recognised declared kind).  An ordinary wild fight, a trainer,
  or SPECIAL BOSSES = `normal` appends nothing, so every other intro is
  byte-for-byte what it was.
- `Screen:holdBossTransform` (called from `Screen.new`, before the first beat)
  raises the declared hold -- the tera film, the Dynamax size ladder, the form
  art -- so the boss **appears as its ordinary self** and the clip is what
  performs the transformation, instead of fading in already filmed / already
  grown and then snapping back when the clip starts.  `Screen:finishIntro`
  clears any hold still up, and a beat that cannot be staged drops them as it
  is skipped, so a stray hold can never outlive the intro.
- `Screen:advanceIntro`'s `bossTransform` branch calls
  `Screen:startBossTransformAnim`, which starts the same clip a mid-battle set
  piece uses -- `mega` the evolution sequence, `dynamax`/`gigantamax` the
  Dynamax one, `tera` the crystal show -- always with `already = true` /
  `force = true` (the enemy/boss path: the reveal beat must not run an
  activation).  Nothing available to stage = the beat is skipped, holds
  dropped, narration on.
- `Screen:finishGimmickAnim` resumes the **narration** (`advanceIntro`) rather
  than the turn loop while a boss transform is playing (`self.bossTransformIntro`),
  so the intro carries on to the "Go!" beats when the clip reports done.  A clip
  that never reports done still ends via its own SAFETY valve, exactly as the
  mid-battle set piece does.
- `Screen:updateIntro` refuses to advance while `self.bossTransformIntro` is set,
  so a mashed A cannot skip the set piece or read a beat early -- the same rule
  the mid-battle set piece keeps in `Screen:advanceResolving`, which refuses to
  step a turn while any clip is live.

**It is costume only, deliberately.**  `special_boss.lua` still never activates
anything, and battle_forms is never asked to: it owns WHEN a gimmick fires, and
a wild mon never reaches its enemy-trainer path.  A raid boss's **MEGA** is the
one case with nothing behind the clip -- the stone is stored, the sprite mod
paints no mega declaration, and battle_forms only wires enemy megas through its
trainer AI -- so the evolution sequence plays over the base art and the form
does not actually change.  That is a battle_forms limitation, unchanged here;
all three other kinds (tera / dynamax / gigantamax) land their real declared
look on the clip's reveal.

### Verified

`luaparse 5.1` clean on `battle_screen.lua` and `special_boss.lua`;
`battle_screen.lua` compiles under fengari's **stock** 200-local limit.  A new
fengari suite (`scratch/tests/boss_transform_test.lua` +
`run_boss_transform.mjs`, **40/40 green**) loads the REAL `battle_screen.lua`
and drives the whole feature: the kind predicate (all four kinds, an unknown
kind, no declaration, a non-boss layout), the intro beat (appended once, right
after the fade; none without a declaration; none on a non-boss screen), the
holds (each kind raises its own, nothing raises none), the start (a tera boss
really builds its clip and sets the flag; a mega boss with no evolution module
refuses and sets nothing), `advanceIntro` (an unstageable beat falls through and
drops the holds; a stageable one starts its clip and does NOT read the next beat
yet), `finishGimmickAnim` (resumes the narration with the flag set, steps the
turn loop without it), `updateIntro` (a press cannot skip the clip; once it is
over a press advances) and the `finishIntro` backstop.  The existing scene
suites stay green (learn **20/20**, exp-share screen **33/33**, exp-share native
**14/14**).  `manifest.json` + `files.json` are JSON-valid at **4.0.4**
(`files.json` still lists **32** files).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.4 -- a fix plus a
feature) **and `g9-battle-sprites` (v3.3.2)**, whose declared-Dynamax read now
honours the scene's staging hold so a raid boss grows on the clip's reveal
rather than underneath it.  The engine (`g9-battle-engine` v4.5.3) and `g9-gui`
(v3.0.4) are unchanged.  LÖVE cannot run in the preview, so the in-game
confirmation is yours.

## Cave art dropped; gym/Elite Four/Champion fall back to gym.png then grass.png (v4.0.5)

**`cave.png` is no longer bundled.** The one bundled example backdrop is
removed, so `assets/backgrounds/` ships only its `README.md` again -- drop in
your own `cave.png` (plus `cave-2.png`, ...) to bring cave/indoor fights back.
A cave fight with no art of its own now draws the white field, exactly like any
other tag with no art.

**Gym, Elite Four and Champion fights gained an explicit fallback chain.**
Before, any tag with no art of its own borrowed the **map's terrain** -- and a
gym is an indoor map, so a missing `gym7.png` fell through to `cave`. The chain
is now: the fight's own numbered file (`gym1`..`gym16` / `elitefour1`..`4` /
`champion`) -> `gym.png` (a new generic tag) -> `grass.png` (the last fallback).
`gym.png` is a normal tag file (`gym-2.png`, `gym-3.png` are its variants), so a
player can drop in ONE generic gym ground and every gym / Elite Four / Champion
fight uses it, or drop in numbered files to override individual fights. The
chain is **final** -- when `gym.png` and `grass.png` are both absent the fight
draws nothing -- and every OTHER tag keeps the old single fallback (the map's
terrain), so a `fated` / `red` / `rival` / `rocket` fight still borrows the map.

**Where it lives.** `background.lua` gained a `FALLBACK` map (`gym` ->
`{grass}`, and `gym1`..`16` / `elitefour1`..`4` / `champion` ->
`{gym, grass}`), used by both `M.pickFile` (the draw) and `fieldTag` (the
life-ring terrain, so a fallback to water would still float the mons), and the
bare `gym` tag was added to the vocabulary so `gym.png` is discovered.
`options.lua`, the `assets/backgrounds/README.md` drop-in guide and this README
all name the new tag and chain. Nothing else changed.

### Verified

`luaparse 5.1` clean on `background.lua` and `options.lua`. The background
suite (`scratch/tests/scene_background_test.lua`, **78/78 green**) is extended
with the chain: `gym.png` is discovered as its own tag (and `gym-2.png` as its
variant); the tag vocabulary is the documented **32** tags; a gym / Elite Four /
Champion tag with no numbered file picks `gym.png` when present and `grass.png`
otherwise; a numbered file outranks the generic; and a gym tag with only
`cave.png` present draws NOTHING (the chain is final -- it does not fall through
to the map's cave art). `manifest.json` + `files.json` are JSON-valid at
**4.0.5** (`files.json` now lists **31** files -- `cave.png` removed).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.5). Drop a
`gym.png` into `assets/backgrounds/` if you want the generic gym ground. LÖVE
cannot run in the preview, so the in-game confirmation is yours.

## BACKGROUND is the scene's master on/off (v4.0.6)

`background.lua` now exports **`M.sceneWanted()`** -- `M.option() ~= "off"` --
the single question `g9-battle-sample` asks before it routes a fight. So the
**BACKGROUND** row is the scene's master switch: **AUTO** (the default) or a
pinned tag means the custom scene is used; **OFF** means the sample hands every
fight back to the game's own battle screen -- ground art and layout alike.

This pairs with **g9-battle-sample 1.2.5**, whose own battle row was renamed
**2v2/3v3/4v1** and now only picks the layout: ON (default) keeps the full
wild/trainer routing, OFF forces every fight onto the scene's **singles**
screen instead of native.

The scene's own drawing is unchanged -- asked to draw with no art it still
degrades to the white field -- so a caller that pushes a layout directly (not
through g9-battle-sample) is unaffected. `luaparse 5.1` clean on `background.lua`
and `options.lua`; the background suite stays **78/78 green**.
`manifest.json` + `files.json` are JSON-valid at **4.0.6**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.6) **and
`g9-battle-sample` (v1.2.5)**. LÖVE cannot run in the preview, so the in-game
confirmation is yours.

## Softer transformation flashes, a WHITE ROW option, and a muted HP-bar palette (v4.0.7; corrected v4.0.8)

**1. The transformation clips no longer flash-bang the viewer.** The MEGA
(`evolution_anim.lua`), DYNAMAX/GIGANTAMAX (`dynamax_anim.lua`) and TERA
(`tera_anim.lua`) clips each used to slam the screen to a SOLID white (alpha
1.0) partway through the sequence. Each file now carries a `FLASH_ALPHA`
constant fixed at **0.30**: the peak is a 30%-opaque white (70% transparent)
and the WHOLE flash curve -- the coloured wash in, the white window, the fade
-- scales with it, so the beat is dimmer throughout rather than only at its
peak. This is deliberately fixed; there is no option for it.

The reveal beat is untouched. `REVEAL_T` still sits inside
`FLASH_IN`..`FLASH_OUT`, and the creature is still masked across it -- a black
silhouette as it grows (Dynamax), a white one as it mega-evolves / Teras -- so
the form swap stays hidden even though the screen is no longer opaque. The
published `E.flashAlpha` now returns `0..FLASH_ALPHA` (`E.FLASH_ALPHA` is
exported so a harness can assert it).

**2. WHITE ROW.** A Mod Manager option (**OFF** by default) that repaints each
FANTASY COMBAT party row's own **background panel** as a translucent white
panel -- white, **40% transparent (60% opaque)** -- in place of the usual dark
surface, so the field reads through the row. Only the row's *background*
changes: the name, the HP bar, the level, the exp bar and the status tag
inside it all keep their own colours, and nothing changes at all unless
FANTASY COMBAT is on. It is read per draw by `fantasy_combat.lua`'s new
`F.whiteRow()` and used by `drawPartyRow` for the panel's `color` (`COL.whiteRow`);
the lit (active) row keeps its brighter border so the commanded mon still
reads.

> **v4.0.8 correction.** v4.0.7 shipped this as **WHITE HP BAR**, which
> whitened the HP bar itself. The user meant the *row background* -- so the row
> is now `white_row` / **WHITE ROW**, and the HP bar keeps a colour of its own
> (see 3 below). The whole native over-the-head white-bar path (the
> `battle_screen.lua` / `native.lua` machinery that suppressed the cart fill
> and repainted a white band) was removed with it.

**3. The HP bar's own palette is muted (v4.0.8).** The FANTASY COMBAT party
list's HP bar no longer uses the old bright green / yellow / red stoplight:
`fantasy_combat.lua`'s `COL.good` / `COL.warn` / `COL.bad` are now one shared
depth, anchored on the user's **#00A36D** -- the yellow and red are darkened to
that same saturation and value, so the bar reads as a single muted family
without losing the state the colour is there to show:

| state | colour | value |
| --- | --- | --- |
| good (HP > 50%) | #00A36D | `0.000, 0.639, 0.427` |
| warn (HP > 20%) | #A38F00 | `0.639, 0.561, 0.000` |
| bad (HP <= 20%) | #A30000 | `0.639, 0.000, 0.000` |

This colour is **always** used -- it is not tied to the WHITE ROW option, which
repaints only the panel behind the bar. The exp bar beside it keeps its own
colour.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`, `native.lua`,
`fantasy_combat.lua`, `options.lua` and the three animation files. New suite
`scratch/tests/white_row_test.lua` (runner `run_white_row.mjs`) drives the REAL
`fantasy_combat.lua` under a mock `love` -- green: the option read (on / off /
garbage), the panel's colour being the dark `COL.panel` when off and the
40%-transparent white `COL.whiteRow` when on, the HP bar keeping a *coloured*
fill in BOTH states, and the exact new green / yellow / red palette values
including each state's threshold boundary. The three animation modules are
asserted headlessly to peak at exactly 0.30 with the reveal still inside the
window. `fantasy_combat_test.lua` stays **61/61**, `learn_move` **20/20**,
`boss_transform` **40/40**, `exp_share_native` **14/14**, `exp_share_full`
**8/8**, `exp_share_screen` **33/33**, the sample suite **150/150** and the
background suite **78/78**. The fantasy party list was re-rendered with the
option off and on and vision-checked (dark rows vs. white rows, with the HP bar
keeping its own colour in both).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.8). Turn WHITE
ROW on in the Mod Manager to try it. LÖVE cannot run in the preview, so the
in-game confirmation is yours.

## CRITICAL: a switch-in takes the hit aimed at its slot (v4.0.9)

**The bug.** When the player switched a Pokemon out, a move already aimed at
that slot for the same turn landed on the mon **leaving** the field instead of
the mon **arriving**.

**Why.** g9-battle-engine captures a move's target as a real mon at QUEUE time
(`combat.lua`'s `toActingBattlers` reads `action.target.mon`), and the target is
resolved from that captured mon at resolution. An ordinary attack only
re-aims when its chosen target has **fainted** -- but a switched-out mon is
still alive, so nothing re-aimed it and the hit went to the Pokemon that was no
longer on the field.

**The fix.** `battle_screen.lua`'s switch branch (`Screen:advanceResolving`,
the `switchQueue` pass) now follows the **slot**: the instant it swaps
`playerBattlers[slot]` for the arriving battler it retargets every already-
queued action whose `target` is the outgoing battler to the arriving one --
`moveQueue` (what resolution consumes) and `queuedActions` (its source) both.
That covers the enemy's own move and any ally-directed move aimed at the
switching slot. Because the switch resolves before any move (the long-standing
rule this pass already implements), the retarget is always in place before the
turn is translated for the engine.

**Gen 1 companion.** `battlersByMon` is built from the **starting** field
roster, so a benched mon switched in had no engine battler -- and
`state:useMove` bails when `byMon[mon]` is nil, so the corrected target would
have been dropped in silence. `native.lua`'s Gen 1 `state:useMove` now builds
that battler the first time the mon is actually used (`addBattler(mon,
mon.multiSide ~= "enemy")`, idempotent), matching what native does on every
switch-in via `BattleState.makeBattler` and what g9-battle-engine's own docs
say the scene's `battlersByMon` cache is for.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`, `native.lua`,
`combat.lua`, `fantasy_combat.lua` and `options.lua`. The existing screen
harness gained a **switch-target** block and the native harness a **mid-battle
switch-in** block: `exp_share_screen` **33/33 -> 38/38** (the slot now holds
the arriving mon; the queued move follows it; `queuedActions` agrees; the
engine is handed the arriving mon, not the one leaving; an unrelated queued
target is left alone) and `exp_share_native` **14/14 -> 18/18** (the arriving
mon gets a native battler on first use, tagged by side, and a second use does
not rebuild it). `forced_switch` **42/42**, `fantasy_combat` **61/61**,
`white_row` **27/27**, `learn_move` **20/20**, `boss_transform` **40/40**,
`exp_share_full` **8/8**, the sample suite **150/150** and the background suite
**78/78** all stay green.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.0.9). LÖVE cannot
run in the preview, so the in-game confirmation is yours.

## Pivot self-switch timing (v4.1.0)

**The request.** A pivot move -- U-turn, Volt Switch, Flip Turn, or Teleport --
switches the user out. Which Pokemon should eat the opponent's move for that
turn? The answer falls out of the turn order: **the action that had not resolved
yet follows the SLOT.**

- **Teleport** is -6 priority, so it acts **last**: the user is hit first, then
  switches, and the switch-in is exposed only to entry hazards and other field
  conditions (sandstorm, etc.) -- nothing is left pending.
- **U-turn** can act **first**: it hurts the opponent, then switches, and the
  opponent's **not-yet-delivered** move lands on the switch-in.

**The problem.** g9-battle-engine's self-switch primitive
(`combat/switch_primitives.lua`'s `requestSwitch`) sets the real, public
`battle.forcedSwitch`, and the engine's own resolver honored that as "end the
round here" -- every actor that had not yet acted was skipped. A player pivot
therefore switched **nothing** on the field (the scene never opened a bench
pick), and a fast U-turn's switch-in never ate the opponent's move.

**The fix -- the engine half.** `combat/switch_primitives.lua` now parks the
leaving mon on `battle.__g9PendingSelfSwitch = { mon, side, reason }` before it
sets `forcedSwitch`. `combat/turn_order.lua`'s `resolveTurnActions` reads that
at the forced-switch break, and -- when the paired scene advertises
`battle.__g9SceneHandlesPivotSwitch` -- it stores the live order list on
`battle.__g9PivotPause`, emits a `{kind = "pivot-switch", mon, side}` event, and
**returns without running the end-of-turn**. A new
`mod.exports.resumeAfterPivot(battle, incoming, outgoing)` re-enters the SAME
round (the turn counter is deliberately **not** advanced a second time),
repoints every not-yet-acted actor whose chosen target was the mon that left
onto the mon that came in, and then finishes normally -- residuals included, so
the field ticks with the mon that actually came in. A scene that does **not**
advertise the flag, or an engine older than this one, keeps the old behaviour
exactly (the round ends at the switch), so the two mods remain independently
installable.

**The fix -- the scene half.** `battle_screen.lua`'s `Screen.new` sets
`battle.__g9SceneHandlesPivotSwitch = true`; `Screen:advanceResolving`'s event
drain loop handles a pending `pivot-switch` event by calling
`Screen:beginPivotSwitch(event)`, which finds the outgoing battler's slot,
opens a **mandatory** bench pick (`openPivotSwitch`, mirroring
`openForcedSwitch`) and refuses to cancel (`refusePivotCancel` prints the usual
forced-switch line and reopens the list). `Screen:applyPivotSwitch(mon)` swaps
`playerBattlers[slot]`, keeps the exp mark, repoints `battle.player` /
`playerIndex` when the outgoing mon was the active `battle.player`, emits
`battle.battler_switched`, seeds the shown HP, beats the "Go, X!" line, and
hands control back through `Combat.resumeAfterPivot`. `combat.lua` adds
`Combat.resumeAfterPivot` and `native.lua`'s Gen 2 arm adds
`N.resumeAfterPivot`, both guarded so an older engine simply ends the round
instead of stalling.

**Verified.** `luaparse 5.1` clean on all five changed `.lua` files
(`turn_order.lua`, `switch_primitives.lua`, `battle_screen.lua`, `combat.lua`,
`native.lua`). A new fengari driver `pivot_pause_test.lua` runs the REAL
`turn_order.lua` against a mock Gen-2 battle and asserts the three cases --
**19/19**: (A) U-turn acts first, the round pauses, only the pivot has acted,
the `pivot-switch` event fires, and on resume the pending `TACKLE` is repointed
from the outgoing mon to the switch-in and the turn counter does **not**
re-increment; (B) Teleport acts last (orderIndex at the end), so nothing is
pending on resume; (C) with no scene flag the old behaviour is preserved (no
pause, the remaining actor is skipped, the round closes). The screen harness
gained a PIVOT block: `exp_share_screen` **38/38 -> 46/46** (the pending event
pauses the drain loop; `applyPivotSwitch` swaps the slot and calls
`resumeAfterPivot(incoming, outgoing)`; the resumed events are queued; an
unknown outgoing mon resumes instead of stalling). `forced_switch` **42/42**,
`fantasy_combat` **61/61**, `white_row` **27/27**, `learn_move` **20/20**,
`boss_transform` **40/40**, `exp_share_full` **8/8**, `exp_share_native`
**18/18**, the sample suite **150/150** and the background suite **78/78** all
stay green, and the engine boot harness still reports 146/146 subsystems with 0
guarded failures.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.1.0) **and
`g9-battle-engine`** (v4.5.5 -- the pause/resume primitive lives there). LÖVE
cannot run in the preview, so the in-game confirmation is yours.

## The enemy readout matches the party list (v4.2.0)

**The request.** "hp bar colors of enemy need to match our changes to player's
pokemon hp bar color in stat row" and "enemy stat gui also needs a translucent
80% (20% solid) white rectangle (with softed-circle corners) so info is more
visible. this white rectangle follows coloring of row's background with a
setting named [Enemy Stat white] on/off, off makes the rectangle be matched to
row's dark background."

**What changed.**

1. **The enemy's HP bar takes the party list's muted family.** The enemy
   over-the-head readout's bar was still the native bright green / yellow / red;
   it now uses the same `COL.good` / `COL.warn` / `COL.bad` (#00A36D / #A38F00 /
   #A30000) and the same thresholds the FANTASY COMBAT rows use (`frac > 0.5`
   good, `> 0.2` warn, else bad).
2. **A new `ENEMY STAT WHITE` option (ON by default)** puts a rounded,
   translucent panel behind the enemy readout -- **white at 80% transparency
   (20% solid)** -- so the name, level and bar stay readable over a busy field.
   OFF draws that same panel in the party rows' own dark surface
   (`fantasy_combat.lua`'s `COL.panel`) instead, **and switches the readout's own
   text (name, level readout, gender glyph) to WHITE** -- black ink on that dark
   surface was unreadable (user-reported). Only the enemy readout gets either.

**Why the bar is repainted rather than re-paletted.** A per-draw swap of the
HUD's palette table cannot reach both generations: the Gen 2 `BattleHud` colours
its tiles from `self.palettes.hpBar`, but a Gen 1 boot draws the bar through
`HudTiles.drawHPBar`, whose fill comes from the SGB `GREENBAR` / `YELLOWBAR` /
`REDBAR` data. So the native bar is drawn exactly as before and its **fill is
then repainted** in the muted colour, which covers both paths with one rule.

**How.** `battle_screen.lua`'s `FN.drawGuiBox` gained a 12th `enemyStat`
argument; only the enemy call site passes it, so the player's readout is
byte-identical to before. The readout's ink is now chosen from the panel state
(`local ink = (enemyStat and not FN.enemyStatWhite()) and 1 or 0`) -- black as
always, white only for the enemy on the dark variant; every native draw after it
(the HP badge and bar cells) sets its own palette, so only the name, level and
gender take the ink. The new `FN` helpers (table fields, not module
locals -- the factory sits at Lua's 200-active-local ceiling): `FN.enemyStatWhite`
reads the option with the documented default, `FN.mutedHpColor` returns the party
list's own colour tables (so the two surfaces can never drift apart),
`FN.enemyPanelColors` picks white@0.20 or `COL.panel`, `FN.roundedRect` mirrors
`fantasy_combat.lua`'s own pcall-with-square-fallback idiom, `FN.drawEnemyStatPanel`
draws the rounded fill + 1px rounded border just inside the box's own tile
rectangle, and `FN.drawMutedHpFill` covers exactly the cart's own bar channel --
`(tx + 3) * 8, (ty + 2) * 8 + 2`, width `HpBar.pixels(hp, maxHp)`, height
`HpBar.CHANNEL_PX` -- so the EMPTY part of the bar keeps its keyed native tiles
and the mon still reads through it. On the no-tiles fallback path,
`FN.mutedPalettes()` hands `drawHpFill` the same muted colours in 0-255 form.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua` and `options.lua`. A
new fengari harness `enemy_stat_white_test.lua` (`run_enemy_stat_white.mjs`)
loads the REAL `battle_screen.lua` + `hp_bar.lua` under a mock engine with a
test-only tweak exposing `FN`, and is **51/51**: the option read (on / off /
unknown / no-options / a throwing getter), the muted thresholds and their table
identity with the party palette, the panel colours in both states, the
rounded-rect fallback, the panel's geometry and colours, the overlay's exact
fill span and width, the fallback palette's 0-255 values, the readout's own ink
(black on the white panel, WHITE on the dark one), and a full
`drawGuiBox` pass proving the enemy readout draws the panel BEFORE its assets
and the muted fill AFTER the native bar while the player readout draws neither.
`white_row` **27/27** stays green (the party palette itself is unchanged).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.2.0). LÖVE cannot
run in the preview, so the in-game confirmation is yours. The panel's exact
inset and corner radius are reasoned from the readout's own tile layout, so if
it reads a touch tight or loose against your backdrop they are two numbers in
`FN.drawEnemyStatPanel` (`0.55` / `0.5` / `1.1` / `1` insets and the radius `4`)
to nudge -- and the repainted fill's own channel offset lives in
`FN.drawMutedHpFill` (`(tx + 3) * 8, (ty + 2) * 8 + 2`, `HpBar.CHANNEL_PX` tall,
matching the mod's own `HpBar.drawWithLabel`).

## In-battle move learning prefers the modern learner (v4.3.0)

**User report (verbatim).** "battle scene move learning should call g9-gui move
learning screen first rather than native. if no g9-gui present it uses native
message like in screenshot but we replace the whole screen with a white
background (no pokemon in it) that lasts until relearn is over."

**What changed.** A level-up that wants a move and finds all four slots taken
no longer always drops to the engine's classic `src.ui.MoveLearnMenu`. When
**g9-gui** is installed, the scene pushes g9-gui's own modern learner instead
(its new `ui/move_learn.lua`, the same four-move forget screen painted as that
suite's opaque 540x360 page). When g9-gui is absent -- or installed but with
its MODERN UI switched off, or failed, or only partially installed -- the scene
keeps the engine's classic learner, but the whole field behind it becomes a
plain **WHITE sheet**: no Pokemon, no HUD, no terrain, because the "Delete an
older move to make room?" question *is* the screen and the battle has no
business being read behind it. The white field is up for exactly the pause
(from the moment the turn parks to the moment the player learns the move or
gives up on it) and then the battle returns.

**Why a published id, not a hard id.** g9-gui registers its page under the
engine's own `MoveLearnMenu` id and publishes `mod.exports.moveLearnScreenId`
only when the screen actually registered. Reading that export `mod.find`-style
is the same supported cross-mod route the engine mod already uses for g9-gui's
`shortHealChatEnabled`, and it answers the question the scene actually needs
("is a modern learner live?") without the scene knowing g9-gui's internals --
and without a hard dependency, so the two mods stay independently installable.

**How.** `battle_screen.lua`'s `Screen:beginMoveLearn` resolves the id with two
new `FN` helpers and pushes it:
`FN.guiMoveLearnId(game)` pcall-reads `mod.find("g9-gui").exports.moveLearnScreenId`
(lazily, at battle time); `FN.moveLearnOwned(game, id)` asks
`src.ui.Screens.get` whether the factory that id will build is a MOD's own
(the engine stamps registry-provided factories `__modOwned`), which covers
g9-gui and any other suite. `self.learn` now carries `owned`, and
`Screen:drawContent` opens with `if FN.drawLearnSheet(self) then return end`
-- `FN.drawLearnSheet` paints one white fill over the **320x180 design field**
(`VW`/`VH`) and returns true only when the pause is up AND no mod owns the
screen. A mod-owned learner paints its own opaque page, so the scene is simply
left as it was under it; the classic learner gets the sheet, and the engine
draws the battle scene as the BASE under the pushed classic menu
(`Game.drawBaseInStack` keeps a wide battle's surface through a menu), so the
one fill covers the whole screen. The engine's own messages still draw on top
of the sheet, exactly as in the screenshot. Three fields on `FN`, not new
module locals (the factory sits at Lua's 200-active-local ceiling).

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`. The existing fengari
suite (`scratch/tests/learn_move_test.lua` + `run_learn_move.mjs`) is extended
to **28/28** (was 20/20): the classic push is marked `owned = false`, a
g9-gui that publishes an id with a registry-owned screen is pushed by that id
and marked `owned = true`, an id whose screen did NOT register falls back to
`owned = false`, and `FN.drawLearnSheet` paints exactly one white
`fill` over `0,0,320,180` for the classic learner, paints nothing for an owned
one and nothing with no pause -- plus `drawContent` returning before any other
draw on the classic sheet. The scene regressions stay green: `enemy_stat_white`
**51/51**, `white_row` **27/27**, exp-share screen **46/46** and native
**18/18**, forced switch **42/42**, fantasy combat **61/61**. On the g9-gui
side, the studio's layout harness (`scratch/sim/gui_harness.lua` +
`scratch/sim/run-gui-layout.js`, now **220** shots, no errors) renders the new
page for real: `move_learn_ask`, `move_learn_list` and `gen2_move_learn` all
record **zero off-page primitives**, and a new check proves the instance is
stamped `__g9gui`, opaque, 540x360 on Gen 1 and on Gold's widescreen layer.
The only reported overlap is the suite's deliberate double-print on the
selected row (the same overlap every other selected-row page reports).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.3.0) **and
`g9-gui`** (v3.1.0 -- the modern learner file itself). The engine
(`g9-battle-engine` v4.6.0), `g9-battle-sample` (1.4.0), `g9-battle-sprites`
(3.3.2), `g9-evolutions` (0.6.0) and `g9-trainer-sample` are unchanged. LÖVE
cannot run in the preview, so the in-game confirmation is yours: with g9-gui
installed the learn question should appear on g9-gui's own page with no battle
behind it, and with g9-gui removed it should appear on a plain white screen.

## The scene's own rows decide the move learner (v4.4.0)

**User report (verbatim).** "it's not working, native move relearn is being
called over modernized when background in battle scene is enabled (auto). and
the called native is still NOT a white full screen background + message and
native sequence. NATIVE ONLY SHOULD BE CALLED WHEN BATTLE SCENE BACKGROUND IS
SET TO OFF and modern relearn is set to OFF in setting of battle scene."

**What changed.** The learner is no longer chosen by a bare "is g9-gui
installed?" probe. A new scene row, **MODERN MOVE LEARN** (ON by default),
joins **BACKGROUND** as a routing pair: the modern (g9-gui) learner runs only
while the custom scene is ON *and* MODERN MOVE LEARN is ON. A boot with either
row OFF now gets the game's **own** learner -- the TryingToLearn question, the
four-move forget list, the HM guard and the full "1, 2 and... Poof!" sequence
-- over a plain **WHITE** screen with no Pokemon, HUD or ground art behind it.

**Why.** Two problems, one cause. Choosing the screen from g9-gui's mere
presence meant a boot that *asked* for the modern learner could still end up on
the native one: `Screens.get` answers for the id's registered factory, so the
pause was marked `owned = true` before the screen was actually built -- and if
that build failed (engine `Screens.build` then silently degrades to the classic
screen) the native question was left standing over a *live* battlefield, with
the white sheet suppressed by an `owned` flag that described a page that never
appeared. The scene now decides from its own settings, and knows exactly which
screen it built.

**How.** New `FN.modernMoveLearn()` and `FN.backgroundOff()` read the two rows
live (`backgroundOff` goes through `background.lua`'s own `M.option()`, so it
can never disagree with g9-battle-sample's `sceneWanted`). New
`FN.pushLearner(game, mon, moveId, onDone)` is the single place the choice is
made: with both rows ON it resolves g9-gui's published id through
`src.ui.Screens` and pushes that page **only** when the factory is a registry
record (`__modOwned`) whose `new` actually succeeds; every other case -- either
row OFF, no suite, no published id, or a modern constructor that throws --
requires `src.ui.MoveLearnMenu` **by name** and pushes it directly, so a
registry record can never shadow the classic learner and a failed modern build
can never leave the native question over the battle. `Screen:beginMoveLearn`
sets `self.learn = { mon, moveId }` and stores `self.learn.owned` from the
push's own answer, so `FN.drawLearnSheet` (unchanged) whitens the field exactly
when the classic learner is what really went up. All three live on `FN`, not as
new module locals (the factory sits at Lua's 200-active-local ceiling).

**Verified.** `luaparse 5.1` clean on `battle_screen.lua` and `options.lua`.
The fengari suite (`scratch/tests/learn_move_test.lua` + `run_learn_move.mjs`)
is extended to **32/32** (was 28/28): the new cases are MODERN MOVE LEARN off
-> classic + `owned = false` even with g9-gui present; BACKGROUND off ->
classic + `owned = false` even with the modern row on; both rows on -> the
modern page + `owned = true`; and a modern factory whose `new` throws -> the
classic learner + `owned = false` (the white sheet still stands). The scene
regressions stay green: `enemy_stat_white` **51/51**, `white_row` **27/27**,
exp-share screen **46/46** and native **18/18**, forced switch **42/42**,
fantasy combat **61/61**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.0) **and
`g9-gui`** (v3.1.3 -- 3.1.1 is the Gold fix that lets the modern learner paint
over the battle, without which the page is invisible on Gold and only the
engine's own `TextBox` shows; 3.1.2 draws that box as a g9-gui card at the
page's own size instead of the cart's window at classic size; 3.1.3 keeps the
page up under the engine's closing narration -- `MoveLearnMenu:finish` pops the
screen before it pushes "1, 2 and... Poof!", so without the wrap the last screen
of the flow was the cart's white box over the battle). The engine
(`g9-battle-engine` v4.6.0), `g9-battle-sample` (1.4.0), `g9-battle-sprites`
(3.3.2), `g9-evolutions` (0.6.0) and `g9-trainer-sample` are unchanged. In the
Mod Manager set **MODERN MOVE LEARN** (ON by default) as you want it; the
native learner -- white screen, game's own messages -- appears only when that
row or **BACKGROUND** is OFF, or when g9-gui is absent or its MODERN UI is off.
LÖVE cannot run in the preview, so the in-game confirmation is yours.

## Multi-hit moves drop the HP bar once per landed hit (v4.4.1)

A two-hit move used to read as ONE HP drop. It should read as two, because
each landed hit rolls its own crit and so each landed hit is its own visible
event: the bar should come to rest at the first hit's total, then step again
to the second. The engine was never the problem -- it applies every hit before
the scene narrates any of them, and the *display* is a chase.

**Why a single drop happened (Gen 1).** The scene's HP bar is a chase, not a
snap. `Screen:advanceResolving` takes each queued event, calls
`Screen:armHpAnim(event.g9SceneHp)` to point the bars at that event's HP
vector, and `Screen:stepHpAnim(dt)` walks them there over
`HP_ANIM_DURATION`; while a textless event has moved a bar the advance holds,
so the drop is seen before the next line. A hit therefore animates only if its
OWN event carries its own HP vector. On Gen 1 the per-hit information existed
-- every landed hit funnels through `BattleState:applyDamage` ->
`self:drainNext(target, target.mon.hp)`, which queues a
`{ drain = true, battler = target, stopAt = <hp after THIS hit> }` row, one
per hit (the multi-hit loop in `EffectRegistry.runDamaging` calls
`applyDamage` once per hit) -- but `native.lua`'s `drainNativeMove`
forwarded only the queue rows that had `.text`. The per-hit drain rows were
dropped, so every `say` the scene saw already carried the FINAL total and the
bar played one drop.

**Gen 2 was already correct.** `gen2/Battle.lua`'s `useMove` calls
`self:hitOnce(...)` once per hit; `hitOnce` -> `dealDamage` decrements
`defender.hp` and then emits `{ kind = "damage", hp = defender.hp, ... }`,
so each landed hit already reaches the scene as its own event with its own HP.
The fix is Gen 1-only for that reason.

**How.** `state:drainNativeMove(moveId)` now walks `self.queue` in order and
emits a textless `{ kind = "damage", g9SceneHp = <snapshot> }` for every
drain row, stepping a copy of the pre-move HP vector forward with each row's
`stopAt` (so a recoil drain on the user lands after the target's, exactly as
the native queue orders them). `.text` rows still emit `say` -- now also
carrying the running snapshot -- and the per-action `move` beat is still last.
The seed vector is latched by `state:useMove` into
`self.__g9PreMoveSnap` (via the new `state.copyHpSnap`, a shallow copy so a
later row cannot mutate a vector the chase is still holding) and cleared when
the drain finishes; `Screen:installEventProbe` now publishes
`battle.g9Scene = screen` so the backend can reach `Screen:snapshotHp`. A
backend that never reads it is unaffected, and with no latch the beats fall
back to the probe's live snapshot exactly as before.

**Verified.** `luaparse 5.1` clean on `native.lua` and
`battle_screen.lua`. Four fengari harnesses, all green:

- `scratch/tests/multihit_hp_test.lua` + `run_multihit_hp.js` -- **15/15**.
  Scene-only: given per-hit snapshots the bar plays two separate chases and
  settles at 90 then 80; the negative control (both events carrying the final
  total) plays one chase. The discriminator is the number of chase runs and
  the settled values, not "did it draw 90" (interpolation passes through 90
  either way).
- `scratch/tests/gen1_multihit_beat_test.lua` + `run_gen1_multihit_beat.js` --
  **15/15**. Loads the real `native.lua` (+ `hp_bar.lua`) with mocks and
  checks two damage beats at hp 90/80, their order, distinct tables, a
  single-hit move emitting one beat, the no-snapshot fallback, and the
  `useMove` latch + clear.
- `scratch/tests/gen1_multihit_e2e_test.lua` + `run_gen1_multihit_e2e.js` --
  **11/11**. Real `native.lua` + `combat.lua` + `battle_screen.lua`;
  `installEventProbe` publishes `g9Scene`, then `drainNativeMove` ->
  events -> the real `advanceResolving`/`stepHpAnim` -> two chases, settling
  90 then 80.
- `scratch/tests/gen2_multihit_events_test.lua` + `run_gen2_multihit_events.js`
  -- **10/10**. Loads the real reference `gen2/Battle.lua` + `gen2/Effects.lua`
  + `gen2/Damage.lua` and calls `Battle.hitOnce` twice -> two damage events
  at hp 90/80 with the crit rolled once per hit (hit 2 crits; the crit message
  fires once).

The scene regressions stay green: `exp_share_screen` **46/46**,
`scene_guard` **15/15**, `forced_switch` **42/42**, `white_row` **27/27**,
`enemy_stat_white` **51/51**, `learn_move` **32/32**,
`scene_probe_real` **5/5**, `scene_prize` **19/19**, `special_boss`
**41/41**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.1). No other
suite changes -- the engine (`g9-battle-engine` v4.6.2), `g9-battle-sample`
(1.4.0), `g9-battle-sprites` (3.3.2), `g9-evolutions` (0.6.0) and
`g9-trainer-sample` are unchanged. LÖVE cannot run in the preview, so the
in-game confirmation -- a two-hit move resting the bar at the first hit, then
stepping to the second -- is yours.

## Enemy stat panel: 60% solid, and its dark text is real white (v4.4.2)

Two follow-ups from the v4.2.0 enemy readout.

**The white panel was too faint.** Its fill was white at 20% solid (80%
transparent), which read as barely there over a busy field. `FN.enemyPanelColors`
now returns `{ 1, 1, 1, 0.60 }` -- 60% solid, 40% transparent -- so the name,
level and HP bar sit on a solid-enough surface while the sprite still reads
through. The dark variant and the ally party rows are byte-identical to before.

**The dark variant's white text was never white.** With ENEMY STAT WHITE OFF the
readout is supposed to turn its name/level/gender WHITE on the dark panel, but it
came out black -- the user could not read it. The cause is in the cart's own font:
`Font.drawBox`'s header notes that the tile pages are BLACK glyphs on transparent,
so `love.graphics.setColor(1, 1, 1)` cannot lighten them -- black tinted any colour
is still black. `setColor` was always the wrong tool; the ink has to be
RECOLOURED. The fix is a one-line fragment shader, `FN.WHITE_INK_SHADER`, built
lazily by `FN.whiteInkShader()` (`pcall`-guarded and cached, so a build without
shader support falls back to the plain draw):

```lua
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  return vec4(1.0, 1.0, 1.0, Texel(tex, tc).a);
}
```

`FN.drawGuiBox` binds it only while `enemyStat` is set AND the panel is the dark
variant (`local darkInk = enemyStat and not FN.enemyStatWhite()`), and only
around the four ink draws -- the name, the `<LV>` tile, the level digits and the
gender glyph. It restores the previous shader immediately afterwards, before the
native HP badge and bar cells, which set their own palettes and must not be
whitened. The ON state (black ink on the white panel) and the player's readout
are unchanged.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua` and `options.lua`.
`scratch/tests/enemy_stat_white_test.lua` + `run_enemy_stat_white.mjs` -- **59/59**
(up from 51): the mock gained `newShader`/`getShader`/`setShader` and text records
now carry their `shader`, so the suite checks the 0.60 alpha and that the
shader is bound for exactly the enemy name/level/gender in the dark state, is not
bound in the ON state or for the player, and restores the previous shader. The
scene regressions stay green: `exp_share_screen` **46/46**, `scene_guard`
**15/15**, `forced_switch` **42/42**, `white_row` **27/27**, `learn_move`
**32/32**, `scene_probe_real` **5/5**, `scene_prize` **19/19**, `special_boss`
**41/41**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.2). The engine
(`g9-battle-engine` v4.6.3) also changed this round for the Bide fix -- see its
own README -- so replace that too if you want Bide; otherwise the engine half is
optional. `g9-battle-sample` (1.4.0), `g9-battle-sprites` (3.3.2),
`g9-evolutions` (0.6.0) and `g9-trainer-sample` are unchanged. LÖVE cannot run in
the preview, so the in-game confirmation -- a 60%-solid white panel, and white
text on the dark variant -- is yours.

## Dynamax and Gigantamax: told apart, and a draw-only HP skin (v4.4.3)

Two things the scene never actually did, both reported by the user.

**A plain Dynamax said "Gigantamaxed!".** The pre-reveal announcement was
hard-coded to the Gigantamax wording for every Dynamax. `Ev.dyn.kindOf(screen,
mon)` now answers `"gigantamax"` or `"dynamax"`, and both announcements are
kind-aware: `Screen:startDynamaxAnim` sets `"X is Dynamaxing!"` /
`"X is Gigantamaxing!"` and `Screen:revealDynamax` sets `"X Dynamaxed!"` /
`"X Gigantamaxed!"`. The kind is resolved in precedence order -- a declared
boss's `battle.g9BossKind.kind` first (authoritative on the intro beat, before
anything has changed), then a live `mon.form` (what battle_forms stamps for a
G-Max once the change has landed), then the engine's
`isGigantamaxEligibleSpecies`, else `"dynamax"`.

**The readout showed nothing for the multiplier.** battle_forms deliberately
never writes max/current HP: its `src/hpscale.lua` applies the `(30 + L)/20`
bonus as REDUCED INCOMING DAMAGE and paints its own readout through
`battle.overlay` -- a hook the VANILLA screen fires and this scene, which
*replaces* that screen, never does. So a Dynamaxed mon's real numbers never
moved here and the scene had no readout to show for the ×1.5–×2.

The scene's own answer is a DRAW-ONLY skin over the readout. A record
(`{ mon, num, den, t, kind, seen }`) is kept on the **SCREEN**, keyed to the
mon's table -- never on the mon -- and `FN.drawGuiBox` gained a 13th `hpSkin`
argument that scales the shown HP and the max AS IT DRAWS. Nothing assigns to
`mon.hp` / `mon.maxHp` / `mon.stats.hp`, so no save state is touched. The curve
is the user's spec, in seconds from the sequence's start:

- **0.0 – 1.0** the MAX climbs ×1 → `(30+L)/20`; the current is still ×1, so the
  bar's fill dips (a bigger pool, the same HP).
- **1.0 – 2.0** the CURRENT climbs to match, so the fill returns to its old
  ratio -- now read as `scaledCurrent/scaledMax`.
- After **2.0** both hold at the multiplier for the rest of the Dynamax.

`Screen:startDynamaxHpSkin` starts the record (and `startDynamaxAnim` calls it
the frame it stages a sequence); `Screen:updateDynamaxHpSkin(dt)` advances the
ramps from `Screen:update`, and drops the record the moment the mon stops being
Dynamaxed/Gigantamaxed -- **faint, switch-out, battle end and the 3-turn expiry
all clear it**, and a sequence that ends without the Dynamax ever landing clears
it too. A Dynamax that arrives with no staged clip (an enemy trainer's, a thin
install) is picked up on the next tick. After that the readout snaps back to the
real values.

**Damage reads as the raw hit.** Because the damage battle_forms lets through is
`dmg/M` and the skin multiplies the numbers back up by `M`, the floating damage
label would have understated the hit, so `Screen:armHpAnim` scales its own delta
by `M` (sign-preserving, integer) -- the label and the bar agree, and the player
reads the raw hit, exactly as specified. The FANTASY COMBAT party rows
(`Screen:fantasyData`) apply the same skin, so the party list matches the
over-the-head readouts.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`. New
`scratch/tests/dynamax_hp_skin_test.lua` + `run_dynamax_hp_skin.mjs` -- **72/72**:
the multiplier at L0/L5/L10 and its clamping, the engine per-mon / per-save /
battle_forms-stamp precedence, kind detection from every source (including a
declared Dynamax beating a leftover `mon.form`), the exact ramp values at
t = 0 / 0.5 / 1.0 / 1.5 / 2.0 / 9.0, the full lifecycle (kept in the sequence,
kept while live, cleared on revert, cleared when a sequence ends unlanded,
auto-picked-up, capped, nil-dt safe), the announcements for both kinds, the
readout scaling through `FN.drawGuiBox` (100/120 → 200/240 at ×2, the
mid-max-ramp dip at 100/180, rounding, a zero bar still suppressed), the
floating-label scaling (×2, ×1.5, a heal's sign), a runtime proof that no write
reaches `mon.hp` / `mon.maxHp` / `mon.stats.hp`, and the call sites carrying the
new 13th argument. The existing scene regressions stay green: `multihit_hp`
**15/15**, `scene_guard` **15/15**, `enemy_stat_white` **59/59** (four source-shape
assertions updated for the new 13th argument; the 55 functional checks unchanged),
`forced_switch` **42/42**, `white_row` **27/27**, `learn_move` **32/32**,
`scene_probe_real` **5/5**, `scene_prize` **19/19**, `special_boss` **41/41**,
`exp_share_screen` **46/46**, `gen1_multihit_beat` **15/15**,
`gen1_multihit_e2e` **11/11**, `gen2_multihit_events` **10/10**, `pivot_pause`
**19/19**, `and_move_memory` **3/3**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.3); the engine
(`g9-battle-engine` v4.6.3) is unchanged this round. `g9-battle-sample` (1.4.0),
`g9-battle-sprites` (3.3.2), `g9-evolutions` (0.6.0) and `g9-trainer-sample` are
unchanged. LÖVE cannot run in the preview, so the in-game confirmation -- a
Dynamax saying "Dynamaxing!"/"Dynamaxed!" while a Gigantamax says its own, and
the bar's max then current climbing over the two seconds -- is yours.

## The Gigantamax Factor as the battle-forms gate (v4.4.4)

The other half of the round-342 work, and the piece the 4.4.3 kind-detection
could only DESCRIBE: battle_forms decides Gigantamax purely from the mon's
**species**, so the engine's own per-mon `gigantamaxFactor` did nothing.

**Why species is the whole decision.** battle_forms' `src/dynamax.lua`
`activate()` reads `deps.gigantamax[mon.species]` for the form (its
`data/gigantamax.lua` map), and its `arm()` reads `deps.gmaxMoves(battle.data,
mon)` for the G-Max move substitution -- both keyed on `mon.species`, and
neither reads a Factor anywhere. Its `available()` only asks that `mon.species`
be non-nil and that the trainer hold the Dynamax Band. So a `gigantamaxFactor =
false` Charizard would have Gigantamaxed exactly like a `true` one.

**The gate.** The focused region `Screen:applyGimmickActivation` already builds
(`FN.focusBattlePlayer`, which points `battle.player` at the FORM's owner for
the arm AND the `battle.turn_started` emit) is now also wrapped by
`FN.withFormsSpecies` -- the OUTER wrapper, so battle_forms sees the stand-in
through both the arm and the activation:

- **No Factor** -> `mon.species` is temporarily swapped to
  `FN.FORMS_FALLBACK_SPECIES` (`"RATTATA"`). It is a REAL species, present in
  the data and absent from battle_forms' `data/gigantamax.lua`, so battle_forms
  runs its ordinary Dynamax path (ordinary Max Moves, the clock, the HP scale)
  and finds no G-Max record and no G-Max move. The mon Dynamaxes plainly.
- **Has the Factor** -> the real species is handed over, so an eligible one
  Gigantamaxes exactly as battle_forms already knows how.

The swap is bounded exactly the way `focusBattlePlayer` bounds `battle.player`:
a `pcall` restores the real species whether the wrapped call returns or RAISES,
so a raising battle_forms call can never leave a saved Pokemon's species
renamed. It is skipped entirely for a species that is not Gigantamax-capable
(nothing to gate), and the Factor is read through the engine's exported
`getGigantamaxFactor` / `isGigantamaxEligibleSpecies` with bare-field fallbacks,
so a build without g9-battle-engine still has a working answer.

**The announcement follows.** `Ev.dyn.kindOf` now requires the Factor as well as
eligibility, not eligibility alone: without it, an eligible Factor-less mon
would have been announced as "is Gigantamaxing!" and then, correctly, not been.
The HP skin's `kind` rides the same call, so the readout agrees too.

**Doc note.** The 4.4.3 section's precedence list said "then the engine's
`isGigantamaxEligibleSpecies`"; read it now as "then the engine's
`isGigantamaxEligibleSpecies` **when the mon carries the Factor**".

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`. The Dynamax HP-skin
harness gains a section 10 for the gate and is **82/82** (was 72): the stand-in
is a real species, an eligible Factor-less mon is swapped, an eligible Factor-ful
mon and a non-capable species are not, the swap is in force inside the region
and restored after it -- including when the region RAISES -- and `kindOf` agrees
both ways. Two existing kind checks were updated to the new truth (eligible +
no Factor -> `"dynamax"`). Scene regressions stay green: `special_boss` **41/41**,
`boss_transform` **40/40**, `enemy_stat_white` **59/59**, `scene_guard` **15/15**,
`scene_prize` **19/19**, `scene_probe_real` **5/5**, `forced_switch` **42/42**,
`pivot_pause` **19/19**, `learn_move` **32/32**, `and_move_memory` **3/3**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.4). The companion
**`g9-evolutions`** is **0.7.0** this round (it now registers the G-FACTOR item
and the PC MAX-FACTOR row that hands a Pokemon the Factor); the engine
(`g9-battle-engine`) is unchanged. LÖVE cannot run in the preview, so the
in-game confirmation -- a Factor-less Charizard Dynamaxing plainly, and the same
Charizard Gigantamaxing once it has eaten a G-FACTOR -- is yours.


## The move learner no longer faults to native on a differently-shaped options platform (v4.4.5)

**The report.** On Android, a level-up that wanted a fifth move during a scene
battle opened the game's own classic learner even with **MODERN MOVE LEARN** ON
and **BACKGROUND** AUTO -- while the same save on desktop used g9-gui's modern
page.

**The cause.** The scene's routing was right, but `FN.modernMoveLearn` compared
the stored option value to the exact string `"on"`. The Mod Manager stores a
choice's VALUE, so a normal desktop boot hands back `"on"` and everything
worked; a boot (or save) that reports the row as a boolean, a number or a
differently-cased string read as NOT on, so the classic learner went up over the
white field. That is the one platform-shaped assumption in the routing.

**The fix.**

- Both of the scene's routing rows now read through ONE normaliser,
  `FN.optionOnOff`: `on` / `true` / `yes` / `1`, the boolean `true`, and any
  non-zero number are ON; `off` / `false` / `no` / `0`, the boolean `false`
  and an empty string are OFF; and an unreadable value answers nil so the caller
  fails OPEN to the row's own default (ON), exactly as the previous code did.
  `FN.modernMoveLearn` is a two-line wrapper over it.
- `FN.pushLearner` now drops the screen registry's cache
  (`Screens.invalidate`) and re-resolves ONCE when the first lookup yields a
  non-mod-owned factory, so a builtin cached before g9-gui registered its
  record (a load-order race that can differ by platform) can never shadow the
  modern learner for the rest of the session.
- When the modern row is ON but no mod-owned screen could be resolved at all,
  the scene logs ONE warning naming the learner id it asked for. A silent
  native fallback is now a logged one, so any further platform difference is
  visible in the log instead of guesswork.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`. The scene's
`learn_move` suite gained five routing cases and is **37/37** (was 32): the
stored value `"ON"` still routes modern, the boolean `true` still routes
modern, the boolean `false` still routes classic, an unreadable value fails
open to modern, and a registry whose first lookup returns the builtin is
refreshed and re-resolved into the modern page. Regressions stay green:
`dynamax_hp_skin` **82/82**, `enemy_stat_white` **59/59**, `scene_guard`
**15/15**, `forced_switch` **42/42**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.5). If the modern
learner still does not open on that build, the game log now carries the exact
reason ("MODERN MOVE LEARN is ON but no modern learner could be built (g9-gui
id=...)`), which names whether g9-gui's screen registered on that platform.

## The optional edge that loaded this scene ahead of its own dependency (v4.4.6)

**The report.** A Gold boot logged `optional dependency loop broken at
g9-Battle-Scene` (and the same for `battle_forms` and `g9-battle-engine`), and
the scene's own load line appeared BEFORE `g9-battle-engine` -- the mod it hard
depends on.

**The cause.** `optional_dependencies` is not a soft hint: the loader folds each
entry into the SAME topological ordering as a hard dependency
(`src/mods/Loader.lua`'s `_mergeOrder`). This manifest listed
`g9-battle-sprites` there, and `g9-battle-sprites` lists this scene back, so the
two edges form a 2-cycle. A cycle has no order, so the loader breaks it by
dropping the edge whose mod has the higher id and logs
`optional dependency loop broken at <leftover>`. Here that dropped the wrong
half: the surviving edge put this scene (priority 100) before
`g9-battle-sprites`, which is fine, but the cycle as a whole also entangled the
scene with `g9-battle-engine`, and the resulting order put the engine after the
scene.

**The fix.** The `g9-battle-sprites` entry is removed from
`optional_dependencies`; the list is now empty. Nothing in the scene needs the
sprites mod loaded first -- `resolveSprite` resolves it lazily at battle time
and fails open when it is absent -- so the edge was purely declaratory and
dropping it is behaviour-free. The loader now orders `g9-battle-engine` before
the scene again and reports no cycle.

**Same shape, same boot.** `battle_forms` -> `g9-battle-engine` and
`g9-battle-engine` -> `g9-gui` were the other two pairs in that log; each is a
mutual pair where the LOWER-priority mod's edge contradicts its own priority, so
the lower-priority half's optional edge was removed in each. See those mods'
own notes.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.4.6). A Gold boot's
startup log should no longer carry any `optional dependency loop broken`
warning.

## The 4v4 layout and its exclusive adjacency ruleset (v4.5.0)

**User report (verbatim).** "to battle scene, add a 4v4 layout, it will be named
4v4. 4v4 exclusive rules (protect all other layouts from being edited by this
new ruleset): all allies are considered adjacent like in 4v1. but all enemies
are considered adjacent to each other so moves like lifedew heals all pokemon of
the user's team. rule 2: for offensive spread moves that doesn't attack ally
side, example: rockslide, it respects normal adjacency, so it can only hit 3
enemies, never the four enemies. rule 3: for offensive spread moves that also
damage allies, example: earthquake, these moves are to affect all allies and
still respect discussed rule 2. spread damage mitigation still applies as is,
only stops when there's only one enemy affected as per normal modifier
behavior."

**What it is.** A new preset, **`layouts/4v4.lua`** (four Pokemon per side), and
the ONE thing that makes it more than a formation: the preset's own
**`fourVFour` flag**, read only by `battle_screen.lua`, which switches on a
4v4-exclusive adjacency ruleset. The flag is the whole gate, so singles,
doubles, triples, hordes and boss fights -- and the very same 4v4-shaped roster
without the flag -- are byte-for-byte unchanged. Nothing is keyed on the enemy
COUNT.

**Rule 1 -- everyone on a side is adjacent.** In the resolution hook
(`mod.hooks:wrap("g9.request_adjacency", ...)`) the ally list is the WHOLE own
team and the enemy list the WHOLE opposing team: the same "all allies = all
allies" a boss fight has always reported, extended symmetrically ("all enemies
are considered adjacent to each other"), so an ally-scope move like Life Dew
reaches the whole team and a foes-scope switch-in ability reaches every foe.
The target picker's half (`Screen:reachAllSlots`) is widened on the same flag,
so a single-target move offers -- and a mid-turn redirect can pick -- any battler
on the field.

**Rules 2 & 3 -- the spread exception.** An OFFENSIVE SPREAD move is the one
carve-out: the engine's own `isSpreadMove` (national_dex's `target` archetype)
tells the hook when a move-use is `all-opponents` (Rock Slide, Muddy Water,
Surf) or `all-other-pokemon` (Earthquake), and those keep NORMAL positional
adjacency on the ENEMY side -- the same index rule a triple battle uses, so a
slot reaches its own column and the two beside it: **at most three of the four
enemies, never all four** (rule 2). An `all-other-pokemon` move still receives
the WHOLE ally list the hook already reports, so Earthquake damages every ally
the way the real move does and keeps that same three-enemy cap (rule 3). A
distance-capable move (Flying/pulse/counter ids and national_dex's `distance`
flag) opens the whole board before any of this, and a `nil` moveId (the roster
query / switch-in-ability seam) always answers full -- both unchanged. The hook
resolves the archetype through the engine's export when present and the move
def's own `target` otherwise, the same fallback the picker already uses. No
damage formula, spread-mitigation modifier or engine file is touched:
spread-damage reduction still rides to the engine on the resolved target count,
so it still only drops out when a single target was actually affected.

**Placement.** `layout` is empty on purpose -- the shared 8-column grid stands
four allies at a1..a4 and four enemies at e3..e6 at the normal sprite scale, on
the two disjoint vertical bands, exactly as it stands triples and hordes. The
preset ships no art and nudges no box.

**How to trigger it.** Layouts are chosen by the caller: any mod can route a
fight through `g9-Battle-Scene`'s `pushLayoutBattle("4v4", game, world,
{enemies=..., players=...})`. `g9-battle-sample`'s own band router is unchanged
this round, so a 4v4 is opt-in until a caller asks for that preset by name.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`, `layouts/4v4.lua` and
the extended harness. The existing fengari adjacency suite
(`scratch/tests/triple_adjacency_test.lua` + `run_triple_adjacency.mjs`) is
extended and green at **135/135** (was 99): rule 1 from every slot, rule 2's
per-slot three-foe cap for an `all-opponents` move (and a second move id, proving
it is the archetype and not one hard-coded id), rule 3's whole-ally-side
Earthquake, the engine-export path versus the move-def fallback, an enemy caster,
distance moves, the `nil`-moveId roster query, fainted-battler exclusion, the
picker helpers, and the negative control that the SAME 4v4-shaped roster WITHOUT
the flag stays ordinary positional adjacency. The scene regressions stay green:
`forced_switch` **42/42**, `fantasy_combat` **61/61**, `scene_guard` **15/15**,
`enemy_stat_white` **59/59**, `white_row` **27/27**, `pivot_pause` **19/19**,
`special_boss` **41/41**, `scene_prize` **19/19**, `learn_move` **37/37**.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.5.0). No other
suite changes -- the engine (`g9-battle-engine`), `g9-battle-sample`,
`g9-battle-sprites`, `g9-evolutions` and `g9-trainer-sample` are unchanged.
LÖVE cannot run in the preview, so the in-game confirmation is yours: route a
fight to the `4v4` preset and check the three rules (a Rock Slide hits three
foes at most; an Earthquake hits every ally and three foes; a single-target move
can pick any battler).

**One engine note.** The scene's half of rule 1 is "report the whole own team as
adjacent". The ally-wide HEAL itself (Life Dew's own effect in
`g9-battle-engine`) currently restores only the caster, in every layout -- that
is the engine's move effect, not the scene's targeting, and changing it is a
g9-battle-engine change that would not be scoped to this preset. Say the word if
you want the engine's ally-wide effects expanded too.

## The target picker aims at allies, and Imposter copies the foe opposite its slot (v4.5.1)

**User report (verbatim).** "another important fix, moves like helping hand,
heal pulse and others (selected adjacent ally) and transform (any adjacent
pokemon including allies, right now only can target enemies). right now, moves
that should usually be able to target allies, can't in scene, we need to adjust
cursor to allow it. imposter fix: Double Battles: A Pokemon with Imposter will
automatically transform into the opponent directly opposite its position. If no
opponent is standing in that exact slot, the ability fails completely and will
not target your ally."

**What it was.** The scene's picker has offered allies since round 26
(`Screen:isAllyTargetable`, `Screen:reachableAllies`, the allies-first candidate
list), but its authority is `g9-battle-engine`'s `isAllyTargetable`, and that
export only recognised the inherently ally-directed archetypes (`ally` /
`user-or-ally`) plus the selected-pokemon HEAL records. **Every other
selected-pokemon status/support move -- Transform, Thunder Wave, Toxic, Trick,
Skill Swap, Instruct, ... -- fell through and the picker listed foes only**, so
the cursor could not reach an adjacent ally for a move that should have one.
(Heal Pulse and Helping Hand worked through the heal half; Transform did not.)
Imposter was a separate bug: its transform target came from the engine's
`opposingOf`, which fell back through `battle.player` / `allActiveBattlers` --
an arbitrary or own-side mon in doubles -- and, because the scene builds its own
battle model (`native.lua`'s `buildBattle`) without ever calling the engine's
`newWild` / `newTrainer` constructors, a double-battle Imposter never fired at
all.

**The fix (engine, `g9-battle-engine` 4.6.8).**

- `combat/move_targeting.lua`'s `isAllyTargetable` now admits every
  **non-damaging** selected-pokemon move (national_dex's authoritative
  `damageClass == "status"`): Transform, Thunder Wave, Toxic, Trick, Skill Swap,
  Instruct and the rest of the status/support family can be aimed at an adjacent
  ally, while a variable-power DAMAGING move like Seismic Toss stays foe-only. A
  new **`isAllyOnlyMove`** marks the moves whose only legal recipient is an ally
  (`ally` -- Helping Hand, Aromatic Mist; `user-or-ally` -- Acupressure; and the
  selected-pokemon heals, Heal Pulse / Floral Healing): the picker must offer
  **no foe** for one of these, and in singles it is **used and fails** rather
  than being applied to the lone enemy. **Pollen Puff stays foe-only** -- its
  ally-heal half is still an unimplemented structural no-op, so offering an ally
  would run the damage path on it.
- A new **`requestOpposite(battle, caster)`** (with `nativeFallbackOpposite`) is
  the position query Imposter needs: it forwards to a scene's
  `g9.request_opposite` hook -- the same seam discipline as `requestAdjacency`,
  so the engine still tracks no position itself -- otherwise answers the native
  two-battler case, and returns the single directly-opposite foe or **nil**,
  **never an ally**. `combat/modern_transform.lua`'s `opposingOf` was replaced by
  `oppositeOpponentOf`, so the IMPOSTER branch transforms only into the foe in
  the user's own slot and does **nothing** when that slot is empty (Showdown's
  `if (!target) return false`).

**The fix (scene, `g9-Battle-Scene` 4.5.1).** `battle_screen.lua`:

- a new **`Screen:isAllyOnly(picked)`** trusts the engine's `isAllyOnlyMove`
  (with a move-def fallback on a stale engine), and `Screen:isAllyTargetable`'s
  stale-engine fallback also accepts `damageClass == "status"` / `power == 0`;
- the A-branch candidate build now offers **only** `reachableAllies` for an
  ally-only move (empty in singles -> used-and-failed), **allies first then
  foes** for an ally-targetable move, and foes alone for everything else;
- a new **`g9.request_opposite` hook answers the engine from the screen's own
  index-aligned `playerBattlers` / `enemyBattlers` arrays** -- the opponent in
  the caster's own column, or nil when that slot is empty or its occupant is
  fainted (`battlerArraysFor`'s `b.mon == mon` match resolves the RAW mon the
  engine hands in);
- **`Screen:finishIntro` now runs the engine's `runSwitchInAbilities` for every
  active battler** once the intro is over (idempotent), which is what makes a
  double-battle Imposter fire at all -- and, with the position seam, fire at the
  right mon.

**Verified.** `luaparse 5.1` clean on `battle_screen.lua`; the engine's
`combat/move_targeting.lua` and `combat/modern_transform.lua` likewise. The
engine's two new fengari probes are green: `scratch/sim/probe_ally_target.lua`
(rules + position query, all checks pass) and
`scratch/sim/probe_imposter_opposite.lua` (**14/14**: an Imposter copies the
ally-column foe by its own stat/type; a fainted opposite slot makes it do
nothing -- never the other foe, never the ally; an enemy-side Imposter answers
in reverse; the native fallback transforms in a 1-vs-1 and fails with no
opposing battler). The engine's full boot is unchanged at **147/147 subsystems,
0 guarded failures** on both a Gen 2 and a Gen 1 boot. The scene's own previous
regressions are untouched by this change (no other scene code path is modified).

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.5.1) **and**
**`g9-battle-engine`** (v4.6.8) -- the two halves ship together (the scene reads
the engine's new exports and answers its new hook). LÖVE cannot run in the
preview, so the in-game confirmation is yours: in a doubles battle, Transform /
Helping Hand / Heal Pulse should offer an adjacent ally in the cursor, and a
Ditto/Imposter sent out should copy the foe in its own slot (and do nothing if
that slot is empty).


## Symbol glyphs in translated names (v4.5.2)

A new `assets/fonts/g9-symbols.ttf` -- a four-glyph supplement (U+2640 FEMALE
SIGN, U+2642 MALE SIGN, U+2605 BLACK STAR) built from Noto Sans Symbols / Noto
Sans Symbols 2 -- is attached to every Saira face this mod bakes
(`fantasy_combat.lua`) as a LOVE 11.3 `Font:setFallbacks` fallback. A
translated Pokemon name, or the engine's own (which spells Nidoran FEMALE/MALE
and the star item names with those glyphs), therefore renders the symbol
instead of a tofu box in the HUD, a party row or a move label. The fallback only
ADDS glyphs; an engine without `setFallbacks` keeps the old behaviour. The same
supplement, with the same wiring, ships in g9-gui (whose translation layer
produces the names) and g9-evolutions.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.5.2). The added
glyphs are for names a game-translation mod or national_dex supplies; without
one, nothing visible changes.


## Rebuilt symbol supplement (v4.5.3)

The `assets/fonts/g9-symbols.ttf` supplement is REBUILT so the scene can render
every language g9-gui's translation layer now supports. Two catalogs were added
-- Japanese and Korean -- whose names use kana and Hangul that neither Saira nor
the old four-glyph file carried, so the supplement is regenerated from Noto Sans
JP / Noto Sans KR / Noto Sans Symbols 2: the three symbols (U+2640 FEMALE SIGN,
U+2642 MALE SIGN, U+2605 BLACK STAR), the kana a Japanese catalog needs and the
Hangul a Korean one needs -- 1086 glyphs, ~306 KB. The wiring is unchanged (it
is still attached to every Saira face `fantasy_combat.lua` bakes as a LOVE 11.3
`Font:setFallbacks` fallback) and the fallback only ever ADDS glyphs, so an
English boot renders exactly as before.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.5.3). The added
glyphs are for names a game-translation mod or national_dex supplies; without
one, nothing visible changes.


## Localized battle messages (v4.5.4)

The translation mod patches the ROM's text, but the messages this SCENE sends
itself stay English under it: the item/bag refusals (`Can't use that here
yet.`, `Can't throw a ball -- 2+ foes still standing!`), the FORM/gimmick
lines, the run and outcome lines (`You won the battle!`), the target and switch
prompts and the gimmick picker's DYNAMAX/TERA labels. A new fail-open
`FN.localize` resolves g9-gui's translation layer
(`mod.find("g9-gui").exports.translation.line`) and every message, outcome,
picker and gimmick label the scene draws passes through it; without g9-gui,
with the layer's TRANSLATION row off, or with no translation mod, the English
stands unchanged.

`FN.drawWrapped` now counts CODEPOINTS rather than bytes and breaks an
over-long, space-less run on UTF-8 boundaries -- a Japanese/Korean message has
no spaces to wrap on, so before this a translated line could only overflow the
box as one unbroken run. The `g9-symbols.ttf` supplement is rebuilt again (1093
glyphs) for the codepoints the new strings use.

**User action.** Re-export/replace **`g9-Battle-Scene`** (v4.5.4). Without
g9-gui and a translation mod installed, nothing visible changes.

## License

GNU General Public License v3.0 (GPL-3.0). Copyright (C) 2026
[tectorifter](https://github.com/tectorifter/). The full text ships as
`LICENSE` beside this file.

## Third-party notices

Pokemon and all related names, characters, creatures, moves, items, sprites and
other assets are the property of Nintendo, Creatures Inc., GAME FREAK inc. and
The Pokemon Company. This is an unofficial fan mod and is not affiliated with,
sponsored by or endorsed by them; it owns only its own Lua source (see
`LICENSE`). Third-party fonts, sprite packs, data and companion mods keep their
own licences. The full list ships in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
