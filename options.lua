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
    default = "gen9",
    choices = {
      { "GENERATION 1", "gen1" },
      { "GENERATION 2", "gen2" },
      { "GENERATION 9", "gen9" },
    },
    description = "Which generation's capture maths a thrown ball uses. "
      .. "GENERATION 9 (default) is the current Scarlet/Violet formula; "
      .. "GENERATION 2 is Gold/Silver's modified catch rate plus its "
      .. "shake-probability table; GENERATION 1 is Red/Blue/Yellow's two-roll "
      .. "ItemUseBall with its per-ball roll ceiling. The ball's own wobble "
      .. "count and the failure line both follow the chosen generation.",
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
      .. "grass, water, cave, gym1..gym16, elitefour1..elitefour4, champion, "
      .. "red, rival, rocket, ho-oh, lugia, suicune, and fated (any other "
      .. "legendary or static encounter). AUTO (default) reads each battle "
      .. "and draws the matching file; add more than one for a tag (gym1-2, "
      .. "gym1-23, ...) and one is rolled per fight. OFF keeps the plain "
      .. "white field this scene has always drawn.",
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
}
