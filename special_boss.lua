-- Wild-boss special properties: BOSS CATCH, SPECIAL BOSSES and SHINY BOSS.
--
-- All three apply to exactly one thing: a WILD encounter whose active layout
-- is the bossFight preset (layouts/bossFight.lua, `boss = true`).  A wild
-- encounter has no trainer table on the screen's payload; a TRAINER routed
-- to the same layout (the sample's Champion/Red) carries one, and is
-- deliberately never touched here.  Detection is therefore the pair
-- `layout.boss and not trainer`, read from the SAME getActiveLayoutData the
-- screen itself reads, so the two can never disagree about what a boss is.
--
-- BOSS CATCH (boss_catch, default ON).  A wild boss survives on 1 HP and any
-- ball catches it.  The 1-HP half is a `battle.damage` wrap: that hook is the
-- one shared, cross-generation damage choke the engine mod already documents
-- (Gen 2's modern formula and Gen 1's native computeDamage both run through
-- Runtime.call("battle.damage", ...)), and it fires BEFORE the hit is applied
-- on both.  The wrap only clamps the FINAL number -- it calls next(ctx) and
-- caps the value that comes back -- so Protect, type immunity, Sturdy and
-- every other stage of the real pipeline still decide whether the hit lands
-- at all.  A hit that would take the boss to 0 is capped to `hp - 1`, the
-- same "survive on 1" shape as Sturdy, but unconditional rather than
-- full-HP-only, because the option's promise is that a wild boss is never
-- knocked out at all.  The battle table carries `g9BossCatchMon` -- the mon
-- this applies to -- and the wrap reads it, so an ordinary wild encounter, a
-- trainer fight or a second battle never sees the cap.
--
-- The 100%-catch half is the screen's own throw path: Screen:throwBall asks
-- bossCatchApplies(battle, target.mon) and, when true, forces the pending
-- result to caught with a full three-shake animation.  It is applied to the
-- pending result BEFORE the ball animation starts, so the native wobble
-- plays the catch it is actually reporting rather than a random one.
--
-- SPECIAL BOSSES (special_bosses: normal/tera/dynamax/mega/all; default
-- normal) attaches a persistent special property to the wild boss:
--
--   tera     -- a Tera Type (the engine's own getTeraType rolls one of the
--               species' real types on first read, and setTeraType stores
--               it, mirroring battle_forms' per-mon override stamp exactly
--               as the engine's own API does).
--   dynamax  -- Dynamax Level 10, via the engine's setMonDynamaxLevel (which
--               also mirrors battle_forms' own level stamp).  If the species
--               is Gigantamax-eligible (the engine's own
--               isGigantamaxEligibleSpecies), the Gigantamax Factor is set
--               too -- the "gigantamaxed (if possible)" half of the request.
--   mega     -- the species' own Mega Stone, set as its held item, so it
--               holds that stone after capture.  The pairing table is
--               battle_forms' data/megas.lua, transcribed below; a species
--               with no mega falls back to a plain Dynamax so a boss the
--               option rolled "mega" for is still special rather than
--               silently ordinary.
--   all      -- one of the three at an equal 1/3 roll, as requested.
--
-- Every special boss also rolls 3 of its 6 IVs to the maximum 31.  The IV
-- write goes through the engine's own ModernStats when it is loaded, and the
-- five non-HP battle stats are updated from those IVs in place; the HP stat
-- is adjusted by the DIFFERENCE the new HP IV makes (an additive delta), so
-- whatever max-HP multiplier the caller already applied to the boss -- the
-- sample's own x1..x5 boss scaling, for instance -- is preserved rather than
-- recomputed away.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO, stated rather than discovered
-- later: it never decides WHEN a transformation activates.  Dynamax,
-- Gigantamax, Terastallization and Mega Evolution are battle_forms' to
-- trigger (the standing project rule -- the engine mod consumes that
-- trigger, it does not author one), and a wild Pokemon never reaches its
-- enemy-trainer AI path.  So this file gives the boss the same STORED
-- properties a player's Pokemon would carry, which the game's own gimmick
-- systems deploy when they deploy, and which survive the catch either way.
-- That is the honest scope: the boss IS a Tera/Dynamax/Gigantamax/Mega
-- Pokemon and stays one; the fight around it is still the game's own.
--
-- SHINY BOSS (shiny_boss: off/1.5/2/3/4/5; default off) multiplies the
-- vanilla 1-in-8192 shiny roll.  mon.shiny is a plain stored field (the base
-- engine's Mon.isShiny derives it from DVs and Mon.refreshStats only ever
-- ORs it in), so setting it true both makes this battle's sprite shiny and
-- makes the property stick to the caught mon.
local MEGA_STONES = {
  ABOMASNOW = "ABOMASITE",
  ABSOL = { "ABSOLITE", "ABSOLITE_Z" },
  AERODACTYL = "AERODACTYLITE",
  AGGRON = "AGGRONITE",
  ALAKAZAM = "ALAKAZITE",
  ALTARIA = "ALTARIANITE",
  AMPHAROS = "AMPHAROSITE",
  AUDINO = "AUDINITE",
  BANETTE = "BANETTITE",
  BARBARACLE = "BARBARACLITE",
  BAXCALIBUR = "BAXCALIBURITE",
  BEEDRILL = "BEEDRILLITE",
  BLASTOISE = "BLASTOISINITE",
  BLAZIKEN = "BLAZIKENITE",
  CAMERUPT = "CAMERUPTITE",
  CHANDELURE = "CHANDELURITE",
  CHARIZARD = { "CHARIZARDITE_X", "CHARIZARDITE_Y" },
  CHESNAUGHT = "CHESNAUGHTITE",
  CHIMECHO = "CHIMECHOITE",
  CLEFABLE = "CLEFABLITE",
  CRABOMINABLE = "CRABOMINABLITE",
  DARKRAI = "DARKRAIITE",
  DELPHOX = "DELPHOXITE",
  DIANCIE = "DIANCITE",
  DRAGALGE = "DRAGALGITE",
  DRAGONITE = "DRAGONITITE",
  DRAMPA = "DRAMPAITE",
  EELEKTROSS = "EELEKTROSSITE",
  EMBOAR = "EMBOARITE",
  EXCADRILL = "EXCADRILLITE",
  FALINKS = "FALINKSITE",
  FERALIGATR = "FERALIGATRITE",
  FLOETTE = "FLOETTITE",
  FROSLASS = "FROSLASSITE",
  GALLADE = "GALLADITE",
  GARCHOMP = { "GARCHOMPITE", "GARCHOMPITE_Z" },
  GARDEVOIR = "GARDEVOIRITE",
  GENGAR = "GENGARITE",
  GLALIE = "GLALITITE",
  GLIMMORA = "GLIMMORAITE",
  GOLISOPOD = "GOLISOPODITE",
  GOLURK = "GOLURKITE",
  GRENINJA = "GRENINJAITE",
  GYARADOS = "GYARADOSITE",
  HAWLUCHA = "HAWLUCHAITE",
  HEATRAN = "HEATRANITE",
  HERACROSS = "HERACRONITE",
  HOUNDOOM = "HOUNDOOMINITE",
  KANGASKHAN = "KANGASKHANITE",
  LATIAS = "LATIASITE",
  LATIOS = "LATIOSITE",
  LOPUNNY = "LOPUNNITE",
  LUCARIO = { "LUCARIONITE", "LUCARIOITE_Z" },
  MAGEARNA = { "MAGEARNAITE", "MAGEARNAITE_ORIGINAL" },
  MALAMAR = "MALAMARITE",
  MANECTRIC = "MANECTITE",
  MAWILE = "MAWILITE",
  MEDICHAM = "MEDICHAMITE",
  MEGANIUM = "MEGANIUMITE",
  MEOWSTIC = "MEOWSTICITE_MALE",
  METAGROSS = "METAGROSSITE",
  MEWTWO = { "MEWTWONITE_X", "MEWTWONITE_Y" },
  PIDGEOT = "PIDGEOTITE",
  PINSIR = "PINSIRITE",
  PYROAR = "PYROARITE",
  RAICHU = { "RAICHUITE_X", "RAICHUITE_Y" },
  SABLEYE = "SABLENITE",
  SALAMENCE = "SALAMENCITE",
  SCEPTILE = "SCEPTILITE",
  SCIZOR = "SCIZORITE",
  SCOLIPEDE = "SCOLIPEDITE",
  SCOVILLAIN = "SCOVILLAINITE",
  SCRAFTY = "SCRAFTYITE",
  SHARPEDO = "SHARPEDONITE",
  SKARMORY = "SKARMORYITE",
  SLOWBRO = "SLOWBRONITE",
  STARAPTOR = "STARAPTORITE",
  STARMIE = "STARMIITE",
  STEELIX = "STEELIXITE",
  SWAMPERT = "SWAMPERTITE",
  TATSUGIRI = { "TATSUGIRIITE_CURLY", "TATSUGIRIITE_DROOPY", "TATSUGIRIITE_STRETCHY" },
  TYRANITAR = "TYRANITARITE",
  VENUSAUR = "VENUSAURITE",
  VICTREEBEL = "VICTREEBELITE",
  ZERAORA = "ZERAORAITE",
  ZYGARDE = "ZYGARDITE",
}

return function(mod)
  local SPECIAL_VALUES = { normal = true, tera = true, dynamax = true, mega = true, all = true }
  local VANILLA_SHINY_ODDS = 8192
  local MAX_IV = 31

  -- Same love.math.random/math.random shape the engine's own modules use --
  -- love is the real one in game, math.random is the harness fallback.
  local function randInt(lo, hi)
    if love and love.math and love.math.random then return love.math.random(lo, hi) end
    return math.random(lo, hi)
  end
  local function randUnit()
    if love and love.math and love.math.random then return love.math.random() end
    return math.random()
  end

  local function optionString(key, fallback)
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(function() return options:get(key) end)
      if ok and type(value) == "string" and value ~= "" then return value end
    end
    return fallback
  end

  local M = {}
  mod.exports.specialBoss = M

  function M.bossCatchEnabled()
    return optionString("boss_catch", "on") == "on"
  end
  function M.specialBossMode()
    local value = optionString("special_bosses", "normal")
    if SPECIAL_VALUES[value] then return value end
    return "normal"
  end
  function M.shinyBossMultiplier()
    return tonumber(optionString("shiny_boss", "off")) or 0
  end

  local function engineExports()
    local engine = mod.find and mod.find("g9-battle-engine")
    return engine and engine.exports or nil
  end

  -- The species' own Mega Stone, or nil for a species with no mega.  Handles
  -- a form id (e.g. a regional or battle form) by asking national_dex for its
  -- base species first, then falling back to the plain `BASE_SUFFIX` split --
  -- the same two-step resolution battle_forms' own eligibility code uses.
  local function stoneForSpecies(species)
    if type(species) ~= "string" or species == "" then return nil end
    local entry = MEGA_STONES[species]
    if entry == nil then
      local nd = mod.find and mod.find("national_dex")
      local statsBySpecies = nd and nd.exports and nd.exports.statsBySpecies
      if type(statsBySpecies) == "function" then
        local ok, rec = pcall(statsBySpecies, species)
        local base = ok and rec and rec.baseSpecies
        if base then entry = MEGA_STONES[base] end
      end
    end
    if entry == nil then
      local base = species:match("^([A-Z0-9]+)_")
      if base then entry = MEGA_STONES[base] end
    end
    if type(entry) == "string" then return entry end
    if type(entry) == "table" and #entry > 0 then return entry[randInt(1, #entry)] end
    return nil
  end

  local function isGmaxEligible(species)
    local engine = engineExports()
    local fn = engine and engine.isGigantamaxEligibleSpecies
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, species)
    return ok and result == true
  end

  local function setDynamaxLevel(mon, level)
    local engine = engineExports()
    local fn = engine and engine.setMonDynamaxLevel
    if type(fn) == "function" then
      local ok = pcall(fn, mon, level)
      if ok then return true end
    end
    mon.dynamaxLevel = level
    mon.battleFormsDynamaxLevel = level
    return true
  end

  local function setGmaxFactor(mon)
    local engine = engineExports()
    local fn = engine and engine.setGigantamaxFactor
    if type(fn) == "function" then
      local ok = pcall(fn, mon, true)
      if ok then return true end
    end
    mon.gigantamaxFactor = true
    return true
  end

  local function setTeraType(mon, battle)
    local engine = engineExports()
    local getter = engine and engine.getTeraType
    local setter = engine and engine.setTeraType
    local typeId
    if type(getter) == "function" then
      local ok, value = pcall(getter, mon, battle)
      if ok and type(value) == "string" and value ~= "" then typeId = value end
    end
    if not typeId then
      local rec = battle and battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
      local types = rec and rec.types
      if type(types) == "table" and types[1] then typeId = types[1] end
    end
    if not typeId then return nil end
    if type(setter) == "function" then
      local ok, stored = pcall(setter, mon, typeId, battle)
      if ok and stored ~= false then return stored end
    end
    mon.teraType = typeId
    mon.battleFormsTeraType = typeId
    return typeId
  end

  -- The five non-HP stats are overwritten straight from the new IVs; the HP
  -- stat gets only the DELTA the new HP IV adds, added to the current cap, so
  -- a caller-set max-HP multiplier survives untouched.
  local function maxThreeIvs(mon, game)
    if type(mon) ~= "table" then return end
    local engine = engineExports()
    local MS = engine and engine.ModernStats
    local order = MS and MS.ORDER
    if type(order) ~= "table" or #order == 0 then
      order = { "hp", "atk", "def", "spa", "spd", "spe" }
      MS = nil
    end
    if MS and type(MS.initialize) == "function" and mon.modernStatsInitialized ~= true then
      local ok = pcall(MS.initialize, mon)
      if not ok then MS = nil end
    end
    mon.ivs = mon.ivs or {}
    local old = {}
    for _, key in ipairs(order) do old[key] = mon.ivs[key] end
    local pool = {}
    for i = 1, #order do pool[i] = order[i] end
    for i = #pool, 2, -1 do
      local j = randInt(1, i)
      pool[i], pool[j] = pool[j], pool[i]
    end
    for i = 1, math.min(3, #pool) do mon.ivs[pool[i]] = MAX_IV end
    if not (MS and type(MS.resolveBase) == "function" and type(MS.computeAll) == "function" and mon.stats) then
      return
    end
    local pokemonData = game and game.data and game.data.pokemon
    local fallbackDef = pokemonData and pokemonData[mon.species]
    local nd = mod.find and mod.find("national_dex")
    local okBase, def = pcall(MS.resolveBase, mon.species, fallbackDef, nd and nd.exports)
    if not (okBase and type(def) == "table" and type(def.baseStats) == "table") then return end
    local evs = mon.evs or {}
    local okOld, oldC = pcall(MS.computeAll, def.baseStats, old, evs, mon.level, mon.nature)
    local okNew, newC = pcall(MS.computeAll, def.baseStats, mon.ivs, evs, mon.level, mon.nature)
    if not (okOld and okNew and type(oldC) == "table" and type(newC) == "table") then return end
    for _, key in ipairs({ "attack", "defense", "speed", "spa", "spd" }) do
      if newC[key] then mon.stats[key] = newC[key] end
    end
    local delta = (newC.hp or 0) - (oldC.hp or 0)
    if delta ~= 0 and mon.stats.hp then
      local wasFull = (mon.hp or 0) >= (mon.maxHp or mon.stats.hp)
      mon.stats.hp = mon.stats.hp + delta
      if mon.maxHp then mon.maxHp = mon.maxHp + delta end
      if wasFull and mon.hp then mon.hp = mon.hp + delta end
    end
  end

  -- One of the three, or nil when it genuinely cannot be applied (a species
  -- the running game's data cannot resolve a Tera type for).
  local function applyKind(kind, mon, battle, game)
    if kind == "tera" then
      local typeId = setTeraType(mon, battle)
      if not typeId then return nil end
      return { kind = "tera", detail = typeId }
    end
    if kind == "dynamax" then
      setDynamaxLevel(mon, 10)
      if isGmaxEligible(mon.species) then
        setGmaxFactor(mon)
        return { kind = "gigantamax" }
      end
      return { kind = "dynamax" }
    end
    if kind == "mega" then
      local stone = stoneForSpecies(mon.species)
      if stone then
        mon.item = stone
        return { kind = "mega", detail = stone }
      end
      return applyKind("dynamax", mon, battle, game)
    end
    return nil
  end

  -- SHINY BOSS: one boosted roll on top of whatever the game already rolled.
  -- A boss already shiny stays shiny and is not re-rolled.
  function M.rollShiny(mon)
    if type(mon) ~= "table" then return false end
    if mon.shiny then return true end
    local mult = M.shinyBossMultiplier()
    if mult <= 0 then return false end
    if randUnit() < (mult / VANILLA_SHINY_ODDS) then
      mon.shiny = true
      return true
    end
    return false
  end

  function M.bossCatchApplies(battle, mon)
    if not M.bossCatchEnabled() then return false end
    if type(battle) ~= "table" or type(mon) ~= "table" then return false end
    return battle.g9BossCatchMon == mon
  end

  -- The one entry the scene calls, from pushDoubleBattleScreen, after the
  -- Battle model exists (so the engine's per-mon setters have a battle to
  -- check a tera type against) and before Screen.new (so the shiny flag is
  -- settled before the intro resolves which sprite to fade in).
  --
  -- Returns true when this was recognised as a wild boss -- even with every
  -- option OFF -- so a caller can tell "not a wild boss" from "nothing to do".
  function M.applyWildBoss(battle, game, data)
    if type(battle) ~= "table" then return false end
    local layout = mod.exports.getActiveLayoutData and mod.exports.getActiveLayoutData()
    if not (layout and layout.boss) then return false end
    local trainer = data and data.trainer
    if trainer ~= nil and trainer ~= false then return false end
    local enemies = data and data.enemies
    local mon = type(enemies) == "table" and enemies[1] or nil
    if type(mon) ~= "table" then return false end
    if M.bossCatchEnabled() then battle.g9BossCatchMon = mon end
    M.rollShiny(mon)
    local mode = M.specialBossMode()
    if mode ~= "normal" then
      local kind = mode
      if mode == "all" then
        local roll = randInt(1, 3)
        kind = (roll == 1 and "tera") or (roll == 2 and "dynamax") or "mega"
      end
      local applied = applyKind(kind, mon, battle, game)
      if applied then maxThreeIvs(mon, game) end
    end
    return true
  end

  -- BOSS CATCH's 1-HP half.  Highest priority so it is the outermost wrap and
  -- clamps the number the whole chain finally returns (the engine's own
  -- damage brain sits at 500).  It never suppresses the hit -- next(ctx) runs
  -- everything -- it only refuses to let that number be lethal to the marked
  -- boss while the boss is still standing.
  mod.hooks:wrap("battle.damage", function(next, ctx)
    local damage, info = next(ctx)
    if type(damage) ~= "number" or damage <= 0 then return damage, info end
    local battle = ctx and ctx.battle
    local bossMon = type(battle) == "table" and battle.g9BossCatchMon or nil
    if type(bossMon) ~= "table" then return damage, info end
    local target = ctx and ctx.target
    local mon = target and (target.mon or target) or nil
    if mon ~= bossMon then return damage, info end
    local hp = tonumber(bossMon.hp) or 0
    if hp > 0 and damage >= hp then damage = hp - 1 end
    return damage, info
  end, 1000000)

  mod.log:info("g9_Battle_Scene: wild-boss options ready (BOSS CATCH, SPECIAL BOSSES, SHINY BOSS)")
end
