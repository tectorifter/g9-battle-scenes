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
      .. "hold; ALL rolls one of those three at an equal 1/3 chance each. "
      .. "Every special boss also rolls 3 of its 6 IVs to the maximum 31, "
      .. "and keeps everything it was given after you catch it.",
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
}
