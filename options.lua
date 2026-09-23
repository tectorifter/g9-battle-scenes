-- Mod Manager option schema for g9-Battle-Scene.
--
-- Declared in manifest.json's "options_schema" field, so the manager (and
-- native launchers reading mod_option_schemas.json) can render these rows
-- even while this mod is disabled. main.lua calls mod.options:define() with
-- the IDENTICAL table at load time, which is what gives mod.options:get()
-- its defaults. Keep the two copies in sync (the engine's documented
-- convention for a mod that ships an options schema).
--
-- Row shapes are the engine's own (src/mods/ManagerState.lua buildOptionRows):
--   choice : { key, label, type = "choice", default = value,
--              choices = { { "LABEL", value }, ... } }
-- A choice row renders as the label line over the current value line, and
-- Left/Right cycles the value.  This is the row the catch maths reads: see
-- native.lua's CATCH RATE block (N.catchFormula / N.catchAttemptForMode).
--
-- A row may also carry `visible_if = { key = <other row>, equals = <value>
-- (or not_equals = <value>) }`: the manager then hides the row from its list
-- (and keeps it in the schema + stored options) unless that other row holds
-- the value.  FANTASY SIZE uses it to exist only while FANTASY LAYOUT is ON.
return {
  {
    key = "catch_formula",
    label = "CATCH FORMULA",
    type = "choice",
    default = "auto",
    choices = {
      { "AUTO", "auto" },
      { "GENERATION 1", "gen1" },
      { "GENERATION 2", "gen2" },
      { "GENERATION 9", "gen9" },
    },
    description = "Which generation's capture maths a thrown ball uses. "
      .. "AUTO (default) follows the game being played -- Generation 1's "
      .. "ItemUseBall maths on Red/Blue/Yellow, Generation 2's PokeBallEffect "
      .. "maths on Gold/Silver/Crystal -- so each ball uses its own "
      .. "generation's real catch data. GENERATION 9 forces the current "
      .. "Scarlet/Violet formula on any game; GENERATION 2 is Gold/Silver's "
      .. "modified catch rate plus its shake-probability table; GENERATION 1 "
      .. "is Red/Blue/Yellow's two-roll ItemUseBall with its per-ball roll "
      .. "ceiling. The ball's own wobble count and the failure line both "
      .. "follow the chosen generation.",
  },
  -- The three wild-boss rows below are read by special_boss.lua and apply
  -- ONLY to a WILD encounter whose layout is the bossFight preset -- a
  -- trainer routed to that layout (the sample's Champion/Red) is never
  -- touched.  See special_boss.lua's own header for the full contract.
  {
    key = "boss_catch",
    label = "BOSS CATCH",
    type = "choice",
    default = "on",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "ON (default): a WILD boss can never be knocked out -- "
      .. "every hit that would faint it is capped so it survives on 1 HP -- "
      .. "and any ball thrown at it is a guaranteed catch. OFF restores "
      .. "ordinary combat, where the boss can faint like any other wild "
      .. "Pokemon. Only affects a wild encounter's boss fight.",
  },
  {
    key = "special_bosses",
    label = "SPECIAL BOSSES",
    type = "choice",
    default = "normal",
    choices = {
      { "NORMAL", "normal" },
      { "TERA", "tera" },
      { "DYNAMAX", "dynamax" },
      { "MEGA", "mega" },
      { "ALL", "all" },
    },
    description = "Makes a WILD boss a special Pokemon. NORMAL (default) is "
      .. "how it works today. TERA gives it a Tera Type; DYNAMAX sets its "
      .. "Dynamax Level to 10 (and its Gigantamax Factor too, when its "
      .. "species has a G-Max form); MEGA gives it its own Mega Stone to "
      .. "hold; ALL rolls one of the special properties that boss can "
      .. "actually take, at an equal chance each -- a boss that can be "
      .. "neither Gigantamaxed nor Mega-evolved is therefore a 50/50 between "
      .. "Tera and Dynamax. Every special boss also rolls 3 of its 6 IVs to "
      .. "the maximum 31, keeps everything it was given after you catch it, "
      .. "and announces itself in the battle's opening message, e.g. "
      .. "\"You have found a Tera FIRE Charizard raid!\".",
  },
  {
    key = "shiny_boss",
    label = "SHINY BOSS",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "x1.5", "1.5" },
      { "x2", "2" },
      { "x3", "3" },
      { "x4", "4" },
      { "x5", "5" },
    },
    description = "Multiplies a WILD boss's shiny odds above the game's own "
      .. "1-in-8192. OFF (default) leaves the vanilla chance alone; x1.5 "
      .. "through x5 make it that many times as likely. Only applies to "
      .. "the boss of a wild encounter -- ordinary wild Pokemon and every "
      .. "trainer battle are unaffected.",
  },
  -- The ground plane behind the sprites.  This mod ships NO background art:
  -- the player drops PNGs into assets/backgrounds/, named by the fight they
  -- are for, and background.lua picks one from the encounter.  AUTO (default)
  -- reads the battle and draws the matching file; OFF keeps the old plain
  -- white field.  See assets/backgrounds/README.md for the tag list.
  {
    key = "battle_background",
    label = "BACKGROUND",
    type = "choice",
    default = "auto",
    choices = {
      { "AUTO", "auto" },
      { "OFF", "off" },
    },
    description = "The ground the battle is fought on, seen from above. "
      .. "This mod ships no art: put background PNGs in the mod's "
      .. "assets/backgrounds/ folder, named by the fight they are for -- "
      .. "grass, water, cave, gym, gym1..gym16, elitefour1..elitefour4, "
      .. "champion, red, rival, rocket, ho-oh, lugia, suicune, and fated "
      .. "(any other legendary or static encounter). AUTO (default) reads "
      .. "each battle and draws the matching file; add more than one for a "
      .. "tag (gym1-2, gym1-23, ...) and one is rolled per fight. A gym/"
      .. "Elite Four/Champion fight with no numbered file falls back to "
      .. "gym.png, then grass.png. OFF is the scene's MASTER SWITCH: "
      .. "g9-battle-sample then routes EVERY fight to the game's own battle "
      .. "screen -- no ground art and no custom layout at all -- so leave it "
      .. "on AUTO to keep the custom scene.",
  },
  -- MOVE LEARNER (v4.4.0).  Which screen answers a mid-battle level-up that
  -- wants a fifth move.  Read live by battle_screen.lua's routing with the
  -- BACKGROUND row: the MODERN (g9-gui) learner runs only when the custom
  -- scene is on (BACKGROUND not OFF) AND this row is ON; either one OFF is
  -- the game's own classic src.ui.MoveLearnMenu, drawn over a plain WHITE
  -- field with its own native messages (no Pokemon, HUD or terrain behind
  -- it -- the user's rule).  See battle_screen.lua's FN.pushLearner.
  {
    key = "modern_move_learn",
    label = "MODERN MOVE LEARN",
    type = "choice",
    default = "on",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "Which screen asks which move to forget when a Pokemon "
      .. "levels into a fifth move. ON (default): with g9-gui installed, "
      .. "the learn question opens on that suite's own modern page (its "
      .. "540x360 move learner), and the battle is left untouched behind "
      .. "it. OFF: the game's own learner runs instead -- its "
      .. "\"A is trying to learn B! ... Delete an older move?\" question, "
      .. "the four-move forget list, the HM guard and the whole native "
      .. "\"1, 2 and... Poof!\" sequence -- on a plain WHITE screen, with no "
      .. "Pokemon, HUD or ground art visible behind it. The game's own "
      .. "learner also runs when BACKGROUND (above) is OFF: that row is the "
      .. "scene's master switch, so the fight is already on the game's own "
      .. "battle screen and nothing here can change. g9-gui absent, failed "
      .. "or with MODERN UI off also falls back to the game's own learner "
      .. "on the same white screen, never a bare battle.",
  },
  -- The modernized combat GUI (fantasy_combat.lua). OFF (default) is the
  -- native tile-font F/E box pair this scene has always drawn. ON replaces
  -- the bottom band with the Final Fantasy XII: The Zodiac Age style the
  -- g9-gui mod uses: a translucent party status bar across the bottom in
  -- place of the old message box, a floating action panel and a floating
  -- message/prompt panel that only appear when they have something to say,
  -- a move-info readout (PP / power / accuracy / effect) over the field,
  -- and a modernized target arrow -- see fantasy_combat.lua's own header.
  {
    key = "fantasy_combat",
    label = "FANTASY COMBAT",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "ON replaces the bottom message/menu box with a "
      .. "modernized, translucent combat GUI in the style of FINAL FANTASY "
      .. "XII: THE ZODIAC AGE (the same look the g9-gui mod gives the menus): "
      .. "a party status bar along the bottom shows each Pokemon on the field "
      .. "with its name, HP bar and current/max HP, level, exp bar and status "
      .. "effect, the action menu and the message/prompt box become panels "
      .. "that appear only when needed, the hovered move shows its PP, power, "
      .. "accuracy and effect over the field, and the target arrow and battle "
      .. "messages are drawn in the same face. OFF (default) keeps the "
      .. "original native-tile bottom box.",
  },
  -- Fantasy layout (battle_screen.lua's FANTASY LAYOUT geometry).  OFF
  -- (default) is the horizontal field this scene has always drawn: allies in
  -- a row filling rightward from a1, enemies in a row filling leftward from
  -- e6, the two sides on disjoint vertical bands.  ON replaces that
  -- placement for EVERY preset -- singles/doubles/triples/hordes/bossFight
  -- alike -- with a grouped field: each side stands in a wide, shallow
  -- ZIG-ZAG -- the player's on the LEFT, the enemy's on the RIGHT, first
  -- battler at the bottom and later ones stepping up and outward (drawn a
  -- layer further back, so the one in front never covers the one below),
  -- consecutive slots alternating left/right about the column centre so the
  -- side reads as a zig-zag rather than a plumb line.  The player's side is
  -- drawn with each Pokemon's FRONT battle sprite mirrored horizontally (the
  -- same art the enemy side shows, turned to face it) instead of its back
  -- sprite, so both teams read from the same sheet set.  Each Pokemon's
  -- HP/exp readout sits directly OVER its own head.  Only the placement and
  -- the player-side art change: same rosters, same adjacency, same combat,
  -- same presets.  See battle_screen.lua's FANTASY LAYOUT block.
  {
    key = "fantasy_layout",
    label = "FANTASY LAYOUT",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "ON changes how the two teams are arranged on the field: " 
      .. "instead of the usual horizontal rows, each side stands in a wide, " 
      .. "shallow ZIG-ZAG -- your party on the LEFT, the enemy's on the " 
      .. "RIGHT -- with the lead Pokemon at the bottom and the rest stepping " 
      .. "up and further outward, alternating left and right as they rise and " 
      .. "each one a layer further back so the mon in front stays fully " 
      .. "visible. Each Pokemon's HP/exp readout sits directly over its own " 
      .. "head. Your side is drawn with its FRONT battle sprites, " 
      .. "mirrored horizontally, so both sides face each other with the same " 
      .. "art. Singles is 1v1, doubles 2v2, triples 3v3, boss fights 4v1 and " 
      .. "hordes 1v5, exactly as before -- only where the Pokemon stand and " 
      .. "which art they use changes. OFF (default) keeps the horizontal " 
      .. "layout this scene has always drawn.",
  },
  -- The fantasy-exclusive ASSET SIZE (v3.5.12).  A row that exists ONLY for
  -- the FANTASY LAYOUT: `visible_if` keeps it off the manager's list unless
  -- fantasy_layout is "on", and battle_screen.lua only ever reads it once
  -- self.fantasyLayout is true -- so it can never touch a normal battle.  It
  -- is a MULTIPLIER on the size each side already draws at (the per-side
  -- front/back scales), so 100% is exactly today's sizes and the usual
  -- front/back tuning is preserved underneath.  Stored as a plain multiplier
  -- string ("0.75", "1", "1.5").  See battle_screen.lua's
  -- Screen:battleSpriteScale / Screen.fantasyAssetMul.
  {
    key = "fantasy_asset_size",
    label = "FANTASY SIZE",
    type = "choice",
    default = "1",
    visible_if = { key = "fantasy_layout", equals = "on" },
    choices = {
      { "50%", "0.5" },
      { "75%", "0.75" },
      { "100%", "1" },
      { "125%", "1.25" },
      { "150%", "1.5" },
      { "200%", "2" },
    },
    description = "The size of the Pokemon sprites while FANTASY LAYOUT "
      .. "is on, as a percentage of their normal size. 100% (default) draws "
      .. "them at exactly the size the usual horizontal layout uses, so the "
      .. "per-side sprite sizes are untouched; 50% shrinks both teams to "
      .. "half, 200% doubles them. This row only appears -- and only has any "
      .. "effect -- while FANTASY LAYOUT is ON.",
  },
  -- Party-wide experience (exp_share.lua).  OFF (default) defers to the
  -- game's own award.  Each generation mode replaces the split with that
  -- generation's own rules: GEN 1 the Exp. All (the fighters' half, then a
  -- whole-party split that inherits the participant division), GEN 2 and
  -- GEN 3 the held Exp. Share (50% to the fighters, 50% to the party -- GEN 2
  -- also shows the double share twice, its documented quirk), GEN 6 every
  -- battler the full amount and every idle party member half.  Modern EV
  -- points stay whole in every mode; only the level-experience split changes.
  {
    key = "exp_share",
    label = "EXP SHARE",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "GENERATION 1", "gen1" },
      { "GENERATION 2", "gen2" },
      { "GENERATION 3", "gen3" },
      { "GENERATION 6", "gen6" },
    },
    description = "How experience is shared across the party after an "
      .. "enemy faints. OFF (default) leaves the game's own award alone. "
      .. "GENERATION 1 is the Exp. All: the Pokemon that fought split half "
      .. "the exp, then the whole party splits the other half, still divided "
      .. "by the fighter count (the original game's bug), so a fainted party "
      .. "member's slice is lost. GENERATION 2 is the held Exp. Share: half "
      .. "to the fighters, half to the party, and a Pokemon that both fought "
      .. "and shares collects twice (the cart shows its gain twice). "
      .. "GENERATION 3 is the same split without the double display. "
      .. "GENERATION 6 is the modern key item: every Pokemon that battled "
      .. "gets the full amount, and every other healthy party member gets "
      .. "half; a Pokemon counts as having battled only while it was on the "
      .. "field during the fainted enemy's stay, and an enemy switching out "
      .. "(not fainting) is what resets that. EV points are always awarded in "
      .. "full; only the level-experience split changes.",
  },
  -- The persistent Dynamax visuals (v3.7.0).  While a battler is Dynamaxed or
  -- Gigantamaxed -- or is shrinking back from it -- the scene darkens the field
  -- and rings the creature with a red aura.  The transformation clip itself
  -- (dynamax_anim.lua) is unchanged, and the size ladder is g9-battle-sprites'.
  -- Both rows are read by dynamax_field.lua, per call.
  {
    key = "dynamax_darken",
    label = "DYNAMAX DARKEN",
    type = "choice",
    default = "on",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "ON (default): while a Pokemon is Dynamaxed or "
      .. "Gigantamaxed, the battlefield sinks under a deep maroon wash so the "
      .. "transformed creature reads against a dim ground. The wash clears as "
      .. "the Pokemon shrinks back to its normal size when the transformation "
      .. "ends, and at once if it switches out. OFF leaves the field at its "
      .. "ordinary brightness.",
  },
  {
    key = "dynamax_aura",
    label = "DYNAMAX AURA",
    type = "choice",
    default = "on",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "ON (default): a Dynamaxed or Gigantamaxed Pokemon wears a "
      .. "pulsing red aura while it is transformed, and one that FAINTS bursts "
      .. "in red Galar energy. The burst plays only after the Pokemon's own "
      .. "shrink-back has finished, so the faint is held until the "
      .. "transformation has fully wound down; a Dynamax that simply runs out "
      .. "its three turns, or is switched out, gets no burst. OFF removes "
      .. "both the aura and the burst.",
  },
  -- WHITE ROW (v4.0.8).  Read live by fantasy_combat.lua, which draws the
  -- FANTASY COMBAT party status list.  It repaints each party row's own
  -- BACKGROUND panel -- not the HP bar inside it, and not any other element.
  {
    key = "white_row",
    label = "WHITE ROW",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "OFF (default): each Pokemon's party row in FANTASY "
      .. "COMBAT keeps the usual dark translucent panel behind it. ON draws "
      .. "that row's own BACKGROUND as a translucent WHITE panel (white at "
      .. "40% opacity) instead, so the field reads through the row. Only the "
      .. "row background changes: the name, the HP bar, the level, the exp bar "
      .. "and the status tag all keep their own colours, and nothing changes "
      .. "at all unless FANTASY COMBAT is on.",
  },
  -- ENEMY STAT WHITE (v4.2.0).  Read live by battle_screen.lua, which draws
  -- the ENEMY's own over-the-head stat readout: it sets the rounded panel
  -- BEHIND that readout and nothing else.  In either state the enemy's HP
  -- bar takes the party list's own muted colour family (the row's
  -- COL.good/warn/bad), so the enemy surface matches the ally rows.
  {
    key = "enemy_stat_white",
    label = "ENEMY STAT WHITE",
    type = "choice",
    default = "on",
    choices = {
      { "OFF", "off" },
      { "ON", "on" },
    },
    description = "ON (default): the enemy's over-the-head stat readout sits "
      .. "on a translucent rounded panel -- white at 40% transparency (60% "
      .. "solid) -- so its name, level and HP bar stay readable over a busy "
      .. "field. OFF matches that panel to the party rows' usual dark "
      .. "background instead, and the readout's own text (the name, the level "
      .. "readout and the gender glyph) is drawn WHITE -- recoloured, not "
      .. "tinted, because the cart's font glyphs are black -- so it stays "
      .. "readable on that dark surface. The enemy's HP bar takes the same "
      .. "muted green / yellow / red the FANTASY COMBAT party rows use in "
      .. "both states.",
  },
}
