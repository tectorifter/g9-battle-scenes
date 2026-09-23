-- g9-Battle-Scene -- battle BACKGROUNDS: a ground plane drawn behind the
-- sprites, HUD readouts and F/E boxes, chosen from the encounter the scene is
-- rendering.
--
-- WHAT THIS FILE OWNS.  The scene has always painted its field plain white
-- (Screen:draw / Screen:drawWidescreen fill the surface, then drawContent
-- paints the sprites).  With true-colour, DS-era animated sprites a white
-- field is the one place the scene still looks unfinished, so this sibling
-- draws a backdrop behind everything -- and picks WHICH backdrop from the
-- encounter: a wild grass fight, a surfing fight, a cave fight, gym 1..16,
-- each Elite Four member, the Champion, Red, the rival, any Team Rocket
-- fight, the box legends, and a catch-all for other legends/statics.
--
-- NO ART SHIPS.  This mod deliberately ships NO background images.  The
-- folder assets/backgrounds/ is EMPTY (bar this folder's README) and the
-- player drops in whatever PNGs they want, named by the tag scheme below.
-- Nothing here is ripped from a commercial game, and nothing third-party is
-- redistributed.
--
-- THE TAG SCHEME.  Every file in assets/backgrounds/ is named by the fight it
-- is for:
--
--   grass              wild encounter in grass
--   water              wild encounter on water (surfing or fishing)
--   cave               wild encounter in a cave / indoor encounter
--   gym                the GENERIC gym ground -- a fallback for a gym/Elite
--                      Four/Champion fight (see FALLBACKS below)
--   gym1 .. gym16      gym 1 through gym 16 (badge order; see below)
--   elitefour1 .. 4    the four Elite Four members, in league order
--   champion           the Champion
--   red                Red
--   rival              a rival battle
--   rocket             any Team Rocket fight
--   ho-oh              Ho-Oh
--   lugia              Lugia
--   suicune            Suicune
--   fated              any other legendary or scripted/static encounter
--
-- MULTIPLE FILES PER TAG.  A file may carry a variant suffix -- `gym1-2.png`,
-- `gym1-23.png`, `grass-2.png`, `ho-oh-2.png` -- meaning "another asset for
-- the tag before the dash".  When several files share a tag, ONE is picked at
-- random per battle and kept for that whole fight; with two files that is a
-- 50/50 (with N files, 1/N each).  The number after the dash is only a
-- disambiguator, not a weight.
--
--   assets/backgrounds/grass.png        -> GRASS, the only one
--   assets/backgrounds/grass-2.png      -> GRASS, second of two (50/50)
--   assets/backgrounds/gym1.png         -> gym 1
--   assets/backgrounds/gym1-2.png       -> gym 1, second file
--
-- GYM NUMBERING.  Badge order, per generation.  Gen 1: 1 Pewter, 2 Cerulean,
-- 3 Vermilion, 4 Celadon, 5 Fuchsia, 6 Saffron, 7 Cinnabar, 8 Viridian.
-- Gen 2: 1-8 are the Johto gyms in badge order (Violet..Blackthorn) and 9-16
-- the Kanto gyms in badge order (Pewter..Viridian), matching the sixteen
-- badges Gold/Silver actually hands out.
--
-- FALLBACKS.  A gym, Elite Four or Champion fight whose own numbered file is
-- absent does not go white or borrow the map's cave ground: it walks, in order,
-- its own tag -> gym.png (the generic gym ground) -> grass.png (the grass
-- ground).  So a missing gym7.png shows gym.png when you have one, grass.png
-- otherwise, and never the cave art an indoor gym map would otherwise infer.
-- Every other tag keeps the older single fallback: the map's terrain (see
-- M.pickFile and fieldTag).
--
-- HOW A TAG IS CHOSEN.  See M.tagFor -- in short: the battle's trainer class
-- decides a gym/Elite Four/Champion/Red/rival/Rocket tag; otherwise a battle
-- whose opponents include a named legend gives ho-oh/lugia/suicune, any other
-- legendary gives fated, and a plain wild fight gives grass/water/cave from
-- the engine's own terrain (both generations -- see inferTerrain for how
-- Gen 2's own `playerState` / map `environment` spell what Gen 1's
-- `player.surfing` / tileset do).  For a wild fight the map it is happening on
-- RIGHT NOW outranks the recorded encounter roll, so a live water/cave fight
-- can never inherit the terrain of a session's earlier battle; the roll only
-- refines a grass-looking map (fishing from the shore, or Gen 2's "grass" roll
-- for a cave), and it is spent by the one battle it belongs to.  A wild fight
-- with no encounter roll behind it at all is a scripted/static fight -> fated.
-- A trainer fight in none of those groups falls back to the map's terrain, and
-- a gym map with no class match still gives its gym number.
--
-- OPTION.  BACKGROUND defaults to AUTO (the tagging above); a raw tag name is
-- also accepted, to pin every battle to one backdrop.  OFF is the scene's
-- MASTER SWITCH: g9-battle-sample reads it (M.sceneWanted) and hands every
-- fight back to the game's own battle screen -- no ground art and no custom
-- layout.  (The scene's own drawing still degrades to the plain white field
-- when it is asked to draw with no art, but with g9-battle-sample routing OFF
-- means native.)
--
-- NEVER FATAL.  A missing folder, no files, a broken PNG, an unknown option
-- value, or a scene harness with no love.image all degrade to the old white
-- field -- draw returns without drawing.  Background drawing is pcall'd at the
-- call site (battle_screen.lua), so field art can never abort a turn.
return function(mod)
  local DIR = "assets/backgrounds"
  local VW, VH = 320, 180
  -- WHERE THE GROUND PLANE HANGS FROM.  battle_screen.lua's F/E box -- the
  -- bottom message + FIGHT/BAG/PKMN/RUN band -- owns the field's last
  -- BOTTOM_H (6.5 tiles = 52 design px) and is flush with the field's own
  -- bottom edge, so its vertical middle is HALF that band above the edge.
  -- The backdrop is hung from the field's TOP edge -- its ROOF flush with the
  -- screen's roof, so no white ever shows above it -- and scaled to COVER the
  -- band from there down to that F/E-box middle line (see M.draw).  A source
  -- broad enough to reach the line (any aspect >= the band's own ~2.08:1)
  -- lands its feet on it, its sides centred and cropped; a narrower/taller
  -- source keeps its full width and runs its overflow behind the F/E box.
  -- Keep BOTTOM_H in step with battle_screen.lua's own BOTTOM_H (both 6.5
  -- tiles).
  local BOTTOM_H = 6.5
  local GROUND_FEET_Y = VH - BOTTOM_H * 8 / 2 -- 154: the F/E box's own middle

  -- The full tag vocabulary, plus the ones the option treats specially.
  local TAGS = {}
  local function tag(t) TAGS[t] = true end
  tag("grass"); tag("water"); tag("cave")
  tag("gym")               -- the GENERIC gym ground, a fallback (see FALLBACK)
  for i = 1, 16 do tag("gym" .. i) end
  for i = 1, 4 do tag("elitefour" .. i) end
  tag("champion"); tag("red"); tag("rival"); tag("rocket")
  tag("ho-oh"); tag("lugia"); tag("suicune"); tag("fated")
  local TERRAIN_TAGS = { grass = true, water = true, cave = true }

  -- FALLBACK CHAINS.  A fight tagged with one of these whose own art is missing
  -- walks the chain in order before giving up, instead of dropping straight to
  -- the map's terrain (which, for an indoor gym, is the cave ground).  A gym /
  -- Elite Four / Champion fight therefore reads: its own numbered file
  -- (gym1..gym16 / elitefour1..4 / champion) -> the generic gym ground
  -- (gym.png, its own tag above) -> the grass ground (grass.png).  A tag NOT
  -- listed here keeps the older single fallback (the map's terrain) -- see
  -- M.pickFile and fieldTag.
  local FALLBACK = { gym = { "grass" }, champion = { "gym", "grass" } }
  for i = 1, 16 do FALLBACK["gym" .. i] = { "gym", "grass" } end
  for i = 1, 4 do FALLBACK["elitefour" .. i] = { "gym", "grass" } end

  -- Longest first, so `gym10` is tried before `gym1` when matching a stem.
  local TAGS_SORTED = {}
  for t in pairs(TAGS) do TAGS_SORTED[#TAGS_SORTED + 1] = t end
  table.sort(TAGS_SORTED, function(a, b) return #a > #b end)

  -- File name -> the tag it belongs to, or nil when it is not a background.
  -- `stem` is the lower-cased name without its extension.  Exact match, or a
  -- known tag followed by "-<variant>".
  local function tagOfStem(stem)
    if TAGS[stem] then return stem end
    for _, t in ipairs(TAGS_SORTED) do
      if stem:sub(1, #t + 1) == t .. "-" then return t end
    end
    return nil
  end

  -- Encounter terrain -> tag.  Gen 1's OverworldState:rollEncounter passes
  -- exactly "grass" / "water" / "indoor"; fishing is always water.  Gen 2
  -- passes only "grass" / "water" -- a cave is still a "grass" roll there --
  -- so its own `ctx.environment` is what settles the cave case.
  local TERRAIN_TAG = {
    grass = "grass", water = "water", ocean = "water",
    indoor = "cave", cave = "cave",
  }

  -- Map environments whose encounters are cave/indoor fights.  Gen 2 carries
  -- this in the map header (`def.environment`); Gen 1 has no equivalent byte
  -- and spells the same idea "indoor" in the roll instead.
  local CAVE_ENV = { CAVE = true, DUNGEON = true, INDOOR = true, GATE = true }

  -- One encounter roll -> tag.  `terrain` alone answers Gen 1; Gen 2's
  -- grass/cave ambiguity is settled by `environment`.
  local function terrainTagOf(terrain, environment)
    local t = type(terrain) == "string" and terrain:lower() or nil
    if t == "water" or t == "ocean" then return "water" end
    if t == "indoor" or t == "cave" then return "cave" end
    if type(environment) == "string" and CAVE_ENV[environment:upper()] then
      return "cave"
    end
    if t and TERRAIN_TAG[t] then return TERRAIN_TAG[t] end
    return nil
  end

  -- Trainer class -> tag.  Gen 1 spells its classes OPP_*; Gen 2 does not, so
  -- the two live in disjoint namespaces.  Gen 2's LEAGUE order is
  -- Will/Koga/Bruno/Karen; Gen 1's is Lorelei/Bruno/Agatha/Lance.  Giovanni is
  -- both the Viridian leader and the Rocket boss -- the map decides which.
  local GYM_CLASS = {
    OPP_BROCK = "gym1", OPP_MISTY = "gym2", OPP_LT_SURGE = "gym3",
    OPP_ERIKA = "gym4", OPP_KOGA = "gym5", OPP_SABRINA = "gym6",
    OPP_BLAINE = "gym7", OPP_GIOVANNI = "gym8",
    FALKNER = "gym1", BUGSY = "gym2", WHITNEY = "gym3", MORTY = "gym4",
    CHUCK = "gym5", JASMINE = "gym6", PRYCE = "gym7", CLAIR = "gym8",
    BROCK = "gym9", MISTY = "gym10", LT_SURGE = "gym11", ERIKA = "gym12",
    JANINE = "gym13", SABRINA = "gym14", BLAINE = "gym15", BLUE = "gym16",
  }
  local E4_CLASS = {
    OPP_LORELEI = "elitefour1", OPP_BRUNO = "elitefour2",
    OPP_AGATHA = "elitefour3", OPP_LANCE = "elitefour4",
    WILL = "elitefour1", KOGA = "elitefour2",
    BRUNO = "elitefour3", KAREN = "elitefour4",
  }
  local SPECIAL_CLASS = {
    OPP_RIVAL1 = "rival", OPP_RIVAL2 = "rival",
    RIVAL1 = "rival", RIVAL2 = "rival",
    OPP_RIVAL3 = "champion", CHAMPION = "champion", RED = "red",
    OPP_ROCKET = "rocket", ROCKET = "rocket",
    GRUNTM = "rocket", GRUNTF = "rocket", GIOVANNI = "rocket",
  }

  -- Map id token -> gym number.  A city gym carries the city name and "GYM";
  -- the Kanto cities exist in both games, so the entry holds [1] for a Gen 1
  -- boot and [2] for a Gen 2 one (Gen 2's Kanto gyms are badges 9-16).
  local GYM_MAP = {
    PEWTER = { 1, 9 }, CERULEAN = { 2, 10 }, VERMILION = { 3, 11 },
    CELADON = { 4, 12 }, FUCHSIA = { 5, 13 }, SAFFRON = { 6, 14 },
    CINNABAR = { 7, 15 }, VIRIDIAN = { 8, 16 },
    VIOLET = { 1 }, AZALEA = { 2 }, GOLDENROD = { 3 }, ECRUTEAK = { 4 },
    CIANWOOD = { 5 }, OLIVINE = { 6 }, MAHOGANY = { 7 }, BLACKTHORN = { 8 },
  }

  -- Named legends, and the broader legendary set for the `fated` catch-all
  -- (a form is caught through its own record's baseSpecies).
  local NAMED_LEGEND = { HO_OH = "ho-oh", LUGIA = "lugia", SUICUNE = "suicune" }
  local LEGENDARY = {
    ARTICUNO = true, ZAPDOS = true, MOLTRES = true, MEWTWO = true, MEW = true,
    RAIKOU = true, ENTEI = true, SUICUNE = true, LUGIA = true, HO_OH = true,
    CELEBI = true,
    REGIROCK = true, REGICE = true, REGISTEEL = true, LATIAS = true,
    LATIOS = true, KYOGRE = true, GROUDON = true, RAYQUAZA = true,
    JIRACHI = true, DEOXYS = true,
    UXIE = true, MESPRIT = true, AZELF = true, DIALGA = true, PALKIA = true,
    HEATRAN = true, REGIGIGAS = true, GIRATINA = true, CRESSELIA = true,
    PHIONE = true, MANAPHY = true, DARKRAI = true, SHAYMIN = true,
    ARCEUS = true,
    VICTINI = true, COBALION = true, TERRAKION = true, VIRIZION = true,
    TORNADUS = true, THUNDURUS = true, RESHIRAM = true, ZEKROM = true,
    LANDORUS = true, KYUREM = true, KELDEO = true, MELOETTA = true,
    GENESECT = true,
    XERNEAS = true, YVELTAL = true, ZYGARDE = true, DIANCIE = true,
    HOOPA = true, VOLCANION = true,
    TAPU_KOKO = true, TAPU_LELE = true, TAPU_BULU = true, TAPU_FINI = true,
    COSMOG = true, COSMOEM = true, SOLGALEO = true, LUNALA = true,
    NIHILEGO = true, BUZZWOLE = true, PHEROMOSA = true, XURKITREE = true,
    CELESTEELA = true, KARTANA = true, GUZZLORD = true, NECROZMA = true,
    MAGEARNA = true, MARSHADOW = true, POIPOLE = true, NAGANADEL = true,
    STAKATAKA = true, BLACEPHALON = true, ZERAORA = true, MELTAN = true,
    MELMETAL = true,
    ZACIAN = true, ZAMAZENTA = true, ETERNATUS = true, KUBFU = true,
    URSHIFU = true, ZARUDE = true, REGIELEKI = true, REGIDRAGO = true,
    GLASTRIER = true, SPECTRIER = true, CALYREX = true, ENAMORUS = true,
    KORAIDON = true, MIRAIDON = true, WO_CHIEN = true, CHIEN_PAO = true,
    TING_LU = true, CHI_YU = true, OKIDOGI = true, MUNKIDORI = true,
    FEZANDIPITI = true, OGERPON = true, TERAPAGOS = true,
  }

  -- Same defensive option read the other siblings use: pcall'd, string-only,
  -- falling back when the mod is disabled or running under a harness.
  local function optionString(key, fallback)
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(function() return options:get(key) end)
      if ok and type(value) == "string" and value ~= "" then return value end
    end
    return fallback
  end

  local function randInt(hi)
    if hi < 1 then return 1 end
    if love and love.math and love.math.random then return love.math.random(hi) end
    return math.random(hi)
  end

  local function now()
    if love and love.timer and love.timer.getTime then return love.timer.getTime() end
    if os and os.clock then return os.clock() end
    return 0
  end

  local cachedGen
  local function gameGen()
    if cachedGen then return cachedGen end
    cachedGen = 1
    if type(require) == "function" then
      local ok, GameVersion = pcall(require, "src.core.GameVersion")
      if ok and type(GameVersion) == "table"
          and type(GameVersion.generation) == "function" then
        local ok2, v = pcall(GameVersion.generation)
        if ok2 and (v == 1 or v == 2) then cachedGen = v end
      end
    end
    return cachedGen
  end

  -- ---------------------------------------------------------------------------
  -- PNG -> LÖVE Image, through the same three routes every image-loading mod
  -- in this codebase uses (path, then own bytes, then a GPU detour), because
  -- no single decoder can be assumed on every build.
  -- ---------------------------------------------------------------------------
  local function assetPath(rel)
    local assets = mod.assets
    if not (assets and type(assets.path) == "function") then return nil end
    local ok, full = pcall(assets.path, assets, rel)
    if ok and type(full) == "string" and full ~= "" then return full end
    return nil
  end

  local function newImageFromData(imageData)
    local g = love and love.graphics
    if not (g and g.newImage) then return nil, "no love.graphics" end
    local ok, img = pcall(g.newImage, imageData)
    if not (ok and img) then return nil, "newImage: " .. tostring(ok and "nil" or img) end
    if type(img.setFilter) == "function" then
      pcall(img.setFilter, img, "nearest", "nearest")
    end
    return img
  end

  local function decode(rel)
    local img = love and love.image
    local path = assetPath(rel)
    -- A. the engine's blessed route: decode straight from the mod's folder.
    if img and img.newImageData and path then
      local ok, id = pcall(img.newImageData, path)
      if ok and id then
        local out = newImageFromData(id)
        if out then return out end
      end
    end
    -- B. via the file's own bytes (no path needed).
    local g = love and love.graphics
    if img and img.newImageData then
      local okr, bytes = pcall(mod.read, mod, rel)
      if okr and type(bytes) == "string" and #bytes > 0 then
        local fd
        local dm = love and love.data
        if dm and dm.newFileData then
          local okf, res = pcall(dm.newFileData, bytes, rel)
          if okf and res then fd = res end
        end
        if not fd and love and love.filesystem and love.filesystem.newFileData then
          local okf, res = pcall(love.filesystem.newFileData, bytes, rel)
          if okf and res then fd = res end
        end
        if fd then
          local ok, id = pcall(img.newImageData, fd)
          if ok and id then
            local out = newImageFromData(id)
            if out then return out end
          end
        end
      end
    end
    -- C. last resort: let graphics load it, then take its pixel data.
    if g and g.newImage and path then
      local ok, image = pcall(g.newImage, path)
      if ok and image and type(image.getData) == "function" then
        local okd, id = pcall(image.getData, image)
        if okd and id then
          local out = newImageFromData(id)
          if out then return out end
        end
      end
    end
    return nil
  end

  local images = {}    -- file -> Image, or false once a failure is known
  local warned = {}    -- file -> true, so a broken file warns only once

  local function imageFor(file)
    local cached = images[file]
    if cached ~= nil then return cached end
    local img = decode(file)
    if not img then
      images[file] = false
      if not warned[file] then
        warned[file] = true
        if mod.log and mod.log.warn then
          mod.log:warn("g9-Battle-Scene: background '%s' could not be read "
            .. "-- the field will stay white", tostring(file))
        end
      end
      return false
    end
    images[file] = img
    return img
  end

  -- ---------------------------------------------------------------------------
  -- The folder.  Scanned once (mods do not gain files mid-session) into
  -- byTag[tag] = { file, file, ... } plus a flat list for a caller's own UI.
  -- ---------------------------------------------------------------------------
  local byTag, allFiles, scanned

  local function scan()
    if scanned then return end
    scanned = true
    byTag, allFiles = {}, {}
    local names
    if mod and type(mod.list) == "function" then
      local ok, list = pcall(mod.list, mod, DIR)
      if ok and type(list) == "table" then names = list end
    end
    if type(names) ~= "table" then return end
    for _, name in ipairs(names) do
      if type(name) == "string" and name:sub(1, 1) ~= "." then
        local lower = name:lower()
        local stem = lower:match("^(.-)%.(png)$") or lower:match("^(.-)%.(jpg)$")
          or lower:match("^(.-)%.(jpeg)$") or lower:match("^(.-)%.(webp)$")
        if stem then
          local t = tagOfStem(stem)
          if t then
            local file = DIR .. "/" .. name
            local list = byTag[t]
            if not list then list = {}; byTag[t] = list end
            list[#list + 1] = file
            allFiles[#allFiles + 1] = { tag = t, file = file }
          end
        end
      end
    end
  end

  local function filesFor(t)
    scan()
    return (byTag and byTag[t]) or {}
  end

  -- ---------------------------------------------------------------------------
  -- Which tag a battle is.  The hooks below record the engine's OWN terrain
  -- for a wild encounter (the reliable signal); everything else is read from
  -- the trainer class, the opposing species and the map.
  -- ---------------------------------------------------------------------------
  local lastEncounter = nil   -- { terrain=, environment=, mapId=, species=, at= }
  local FRESH = 60            -- seconds a recorded roll stays usable
  local rollSeq = 0           -- bumped by every roll; a per-Screen tag cache uses
                              -- it to tell "same battle" from "a later one"

  local function recordEncounter(terrain, mapId, species, environment)
    lastEncounter = { terrain = terrain, environment = environment,
                      mapId = mapId, species = species, at = now() }
    rollSeq = rollSeq + 1
  end

  local probeInstalled = false
  local function installEncounterProbe()
    if not (mod.hooks and type(mod.hooks.wrap) == "function") then return end
    pcall(function()
      mod.hooks:wrap("encounter.roll", function(nextFn, a, ctx)
        local result = nextFn(a, ctx)
        if type(result) == "table" and result.species ~= nil then
          recordEncounter(ctx and ctx.terrain, ctx and ctx.mapId,
            result.species, ctx and ctx.environment)
        end
        return result
      end, 0)
    end)
    pcall(function()
      mod.hooks:wrap("encounter.species", function(nextFn, enc, ctx)
        local result = nextFn(enc, ctx)
        if type(result) == "table" and result.species ~= nil then
          recordEncounter(ctx and ctx.terrain, ctx and ctx.mapId,
            result.species, ctx and ctx.environment)
        end
        return result
      end, 0)
    end)
    pcall(function()
      mod.hooks:wrap("encounter.fishing", function(nextFn, rod, mapId, candidates, ctx)
        local result = nextFn(rod, mapId, candidates, ctx)
        if type(result) == "table" and result.species ~= nil then
          recordEncounter("water", mapId, result.species)
        end
        return result
      end, 0)
    end)
    probeInstalled = true
  end

  local function isTrainerBattle(screen)
    if screen and screen.isTrainerBattle ~= nil then
      return screen.isTrainerBattle and true or false
    end
    return (screen and screen.trainerData ~= nil) and true or false
  end

  local function mapIdOf(screen)
    local world = screen and screen.world
    local map = world and world.map
    return map and map.id or nil
  end

  local function classOf(screen)
    local t = screen and screen.trainerData
    if type(t) ~= "table" then return nil end
    return t.classId or t.class or t.id
  end

  local function gymTagFromMap(mapId)
    if type(mapId) ~= "string" then return nil end
    local upper = mapId:upper()
    if not upper:find("GYM", 1, true) then return nil end
    for city, nums in pairs(GYM_MAP) do
      if upper:find(city, 1, true) then
        local n = nums[gameGen()] or nums[1]
        if n then return "gym" .. n end
      end
    end
    return nil
  end

  local function isIndoor(def, game)
    local data = game and game.data
    local indoor = data and data.field and data.field.indoorEncounters
    if not (indoor and def) then return false end
    local idx = tonumber(def.index)
    local first = tonumber(indoor.firstIndoorMap)
    if not (idx and first) then return false end
    if idx < first then return false end
    if indoor.excludedTileset and def.tileset == indoor.excludedTileset then
      return false
    end
    return true
  end

  -- The terrain a battle falls back to when no tag outranks it: surfing ->
  -- water, a cave/dungeon/indoor map -> cave, else grass.  It reads BOTH
  -- generations' own signals, because they do not spell them the same way:
  -- Gen 1 flags the player (`player.surfing`) and marks a cave with the
  -- CAVERN/CAVE tileset or the indoor-encounters test, while Gen 2 keeps the
  -- surf state in `world.playerState` ("surf"/"surf_pika") and the cave/indoor
  -- case in the map header's `def.environment`.  The tile under the player is
  -- checked last as a generation-neutral backstop -- only a surfing player ever
  -- stands on a water cell, so it can never misfire on dry land.
  local function inferTerrain(screen)
    local world = screen and screen.world
    local map = world and world.map
    local def = map and map.def
    local player = world and world.player
    if player and (player.surfing or player.swimming) then return "water" end
    local state = world and world.playerState
    if type(state) == "string" and state:lower():find("surf", 1, true) then
      return "water"
    end
    if player and map and type(map.isWaterCell) == "function" then
      local ok, onWater = pcall(map.isWaterCell, map, player.cellX, player.cellY)
      if ok and onWater then return "water" end
    end
    if def then
      if def.tileset == "CAVERN" or def.tileset == "CAVE" then return "cave" end
      local env = def.environment
      if type(env) == "string" and CAVE_ENV[env:upper()] then return "cave" end
    end
    if isIndoor(def, screen and screen.game) then return "cave" end
    return "grass"
  end

  local function speciesOf(mon)
    local sp = mon and mon.species
    if type(sp) ~= "string" then return nil end
    if not LEGENDARY[sp] then
      local rec = (mon and mon.baseSpecies) or nil
      if type(rec) == "string" then sp = rec end
    end
    return sp
  end

  -- A tag for the opposing team's species (legends/statics), or nil.
  local function legendTag(screen)
    local list = screen and screen.enemyBattlers
    local function check(mon)
      if type(mon) ~= "table" then return nil end
      local sp = speciesOf(mon)
      if not sp then return nil end
      local named = NAMED_LEGEND[sp]
      if named then return named end
      if LEGENDARY[sp] then return "fated" end
      return nil
    end
    if type(list) == "table" then
      for _, b in ipairs(list) do
        local got = check(b and b.mon)
        if got then return got end
      end
    end
    if lastEncounter and lastEncounter.species then
      local sp = lastEncounter.species
      local named = NAMED_LEGEND[sp]
      if named then return named end
      if LEGENDARY[sp] then return "fated" end
    end
    return nil
  end

  local function classTag(screen)
    local class = classOf(screen)
    if type(class) ~= "string" then return nil end
    local mapId = mapIdOf(screen)
    -- Giovanni: the Viridian leader on his gym map, the Rocket boss anywhere
    -- else (Hideout, Silph Co, ...).
    if class == "OPP_GIOVANNI" or class == "GIOVANNI" then
      if mapId and tostring(mapId):upper():find("VIRIDIAN", 1, true) then
        return "gym8"
      end
      return "rocket"
    end
    local g = GYM_CLASS[class]
    if g then return g end
    local e = E4_CLASS[class]
    if e then return e end
    return SPECIAL_CLASS[class]
  end

  -- The public seam, read lazily by battle_screen.lua's Screen:drawContent.
  local M = {}

  -- The tag vocabulary (a sorted copy, for docs/UI).
  function M.tags()
    local out = {}
    for t in pairs(TAGS) do out[#out + 1] = t end
    table.sort(out)
    return out
  end

  -- The discovered assets: { { tag=, file= }, ... }.
  function M.list()
    scan()
    return allFiles or {}
  end

  -- The raw option value, defaulting to auto.
  function M.option() return optionString("battle_background", "auto") end

  -- Does the player want the custom battle SCENE at all?  This is the master
  -- routing switch g9-battle-sample consults before it takes a fight over:
  -- BACKGROUND = OFF now means "use the game's own battle screen" -- no custom
  -- scene at all, ground art and layouts alike -- while AUTO (the default) or
  -- a pinned tag keeps the scene.  The scene's own drawing is unchanged (with
  -- nothing to draw it still degrades to the white field); this is purely the
  -- answer a caller reads before routing.
  function M.sceneWanted() return M.option() ~= "off" end

  -- The tag this battle should use, or nil.  Priority: trainer class
  -- (gym/Elite Four/Champion/Red/rival/Rocket), the opposing species
  -- (legends), then the WILD TERRAIN -- and there the map the fight is
  -- actually on RIGHT NOW outranks the recorded roll, so a battle on
  -- water/cave can never inherit the terrain of a session's earlier fight;
  -- the record only refines a grass-looking map (fishing from the shore is
  -- water while the player stands on land, and Gen 2 rolls "grass" for a
  -- cave's every-tile encounters).  A wild battle with no roll behind it at
  -- all is a scripted/static fight -> `fated`.  Then a gym map with no class
  -- match, then the map/player terrain.
  function M.tagFor(screen)
    local byClass = classTag(screen)
    if byClass then return byClass end
    local byLegend = legendTag(screen)
    if byLegend then return byLegend end
    local inferred = inferTerrain(screen)
    if not isTrainerBattle(screen) then
      -- SPEND the recorded roll: one roll belongs to exactly one battle, so a
      -- leftover can never pin a later fight to an earlier terrain.
      local rec = lastEncounter
      lastEncounter = nil
      if rec and (now() - rec.at) > FRESH then rec = nil end
      -- A live water or cave map is where the fight IS right now, so it wins
      -- outright: a session that began in the grass can never repaint a fight
      -- that is happening on the water (or in a cave), and vice versa.
      if inferred == "water" or inferred == "cave" then return inferred end
      -- The rest of this is a grass-looking map, where THIS battle's own roll
      -- refines the answer: fishing from the shore is water, a Gen 2 "grass"
      -- roll on a cave map is cave, and a plain grass roll is just grass.
      if rec then
        local k = terrainTagOf(rec.terrain, rec.environment)
        if k then return k end
      end
      -- No roll behind this battle at all: a scripted/static fight.
      if probeInstalled then return "fated" end
    end
    local byMap = gymTagFromMap(mapIdOf(screen))
    if byMap then return byMap end
    return inferred
  end

  -- Resolve the OPTION to a tag, or false for "draw nothing".  A known tag
  -- value pins every battle to it; anything else (auto / junk) uses the
  -- encounter.
  function M.resolvedTag(screen)
    local value = M.option()
    if value == "off" then return false end
    if TAGS[value] then return value end
    return M.tagFor(screen)
  end

  -- Kept for callers/tests written against the earlier seam.
  function M.selectedId(screen) return M.resolvedTag(screen) end

  -- Pick the file for a tag (one per tag, random, stable for a battle), or nil.
  -- A tag in FALLBACK whose own art is missing walks its explicit chain first
  -- (gym/Elite Four/Champion: the generic gym art, then grass); any other
  -- non-terrain tag with no art falls back to the map's terrain, so a missing
  -- gym1.png still shows a gym/grass backdrop rather than white.
  function M.pickFile(t, screen)
    local list = filesFor(t)
    if #list == 0 then
      local chain = FALLBACK[t]
      if chain then
        for i = 1, #chain do
          list = filesFor(chain[i])
          if #list > 0 then break end
        end
      elseif not TERRAIN_TAGS[t] then
        list = filesFor(inferTerrain(screen))
      end
    end
    if #list == 0 then return nil end
    return list[randInt(#list)]
  end

  -- Is a background currently selectable (a tag resolves AND art exists)?
  function M.enabled(screen)
    local t = M.resolvedTag(screen)
    return t ~= false and M.pickFile(t, screen) ~= nil
  end

  -- A soft contact shadow under every sprite already on the field, so the
  -- mons read as standing on the ground.  Read from the Screen's spriteAnchor
  -- (filled by the PREVIOUS frame's sprite pass) so it needs no extra plumbing
  -- from battle_screen.lua.
  local function drawShadows(screen)
    local g = love and love.graphics
    if not (g and g.ellipse) then return end
    local anchors = screen and screen.spriteAnchor
    if type(anchors) ~= "table" then return end
    g.setColor(0, 0, 0, 0.30)
    for _, a in pairs(anchors) do
      local x, y, h = a and a.x, a and a.y, a and a.h
      if type(x) == "number" and type(y) == "number"
          and type(h) == "number" and h > 0 then
        g.ellipse("fill", x, y - 0.7, h * 0.36, h * 0.085)
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  -- ---------------------------------------------------------------------------
  -- LIFE BUOYS.  A fight on water -- meaning the water actually ON the field,
  -- which is the tag's art or the map terrain its art falls back to, never the
  -- raw tag alone (see fieldTag below) -- stands every battler on the surface,
  -- which is right for a Water type, right for a Flyer and right for a natural
  -- hoverer, and wrong for everything else -- a Charmander would be standing on
  -- the open sea.  So each battler that needs one gets a life ring
  -- WORN on its lower body: the ring's far half is painted here, in the
  -- background pass, so it sits BEHIND the sprite; the near half is painted by
  -- M.drawFront, which battle_screen.lua calls after the sprite pass -- so the
  -- ring's front rim crosses the mon and the thing reads as a ring around it
  -- rather than a disc stuck behind it.
  --
  -- WHERE THE RING COMES FROM.  Art is a player drop-in, like a background:
  -- drop a PNG into assets/lifebuoys/ whose name is `lifebuoy`, `buoy`,
  -- `lifering`, `life-ring` or `life-buoy` (an optional `-2` variant suffix is
  -- fine) and it is used; with several files one is picked per battle.  With NO
  -- art the ring is drawn from primitives instead (see halfRing), so water
  -- battles read correctly on a stock install with nothing dropped in.
  --
  -- WHAT IT LOOKS LIKE.  The ring lies flat on the water, so the oblique
  -- overhead view turns it into an ellipse: BUOY_SQUASH of a full circle.  A
  -- dropped-in PNG is drawn as-is (draw it at that tilt), and the built-in
  -- primitive ring is squashed to match, so both read the same.
  --
  -- WHO NEEDS ONE.  needsBuoy is the complement of the sprite mod's own FLOAT
  -- set (src/g9-battle-sprites/data/dbk_float.lua): a mon needs a ring when it
  -- is not Water, not Ghost, not Flying (minus the flightless walkers) and not
  -- one of the natural hoverers named in FLOATER (levitate, magnet/balloon
  -- bodies and floating Ghosts) -- i.e. species that neither swim nor get off
  -- the ground.  BUOY_CURATED overrides either way for individual species the
  -- data gets wrong.
  --
  -- NEVER FATAL, like everything else here: no folder, no art, an unreadable
  -- PNG, a missing pokemon record or a harness without love.graphics all
  -- degrade to "no ring drawn" and never abort a frame.
  local BUOY_DIR = "assets/lifebuoys"
  local BUOY_STEMS = {
    ["lifebuoy"] = true, ["buoy"] = true, ["lifering"] = true,
    ["life-ring"] = true, ["life-buoy"] = true,
  }
  -- Localised type ids are not a thing here, but the two spellings the engine
  -- hands round ("Water" from a Gen 1 record, "WATER" from a Gen 2 one) are --
  -- normalise by upper-casing and dropping a trailing _TYPE.
  local WATER_TYPE = "WATER"
  local FLYING_TYPE = "FLYING"
  local GHOST_TYPE = "GHOST"
  -- Flying types that WALK: the sprite mod refuses to float these, so they
  -- need the ring here too (a Doduo cannot fly itself out of the water).
  local GROUNDED_FLYING = {
    DODUO = true, DODRIO = true, FARFETCHD = true, SKARMORY = true,
    DELIBIRD = true, HAWLUCHA = true, FLAMIGO = true, ROWLET = true,
  }
  -- Every species the sprite mod floats or flies, by base species id
  -- (generated from that mod's dbk_float stems -- keep the two in step).
  local FLOATER = {
    ["AEGISLASH"]=true, ["AERODACTYL"]=true, ["ALTARIA"]=true,
    ["ARCHEN"]=true, ["ARCHEOPS"]=true, ["ARTICUNO"]=true,
    ["AZELF"]=true, ["BALTOY"]=true, ["BANETTE"]=true,
    ["BEAUTIFLY"]=true, ["BEEDRILL"]=true, ["BELDUM"]=true,
    ["BOMBIRDIER"]=true, ["BRAVIARY"]=true, ["BRONZONG"]=true,
    ["BRONZOR"]=true, ["BUTTERFREE"]=true, ["CARNIVINE"]=true,
    ["CASTFORM"]=true, ["CELESTEELA"]=true, ["CHANDELURE"]=true,
    ["CHARIZARD"]=true, ["CHATOT"]=true, ["CHIMECHO"]=true,
    ["CHINGLING"]=true, ["CLAYDOL"]=true, ["COFAGRIGUS"]=true,
    ["COMBEE"]=true, ["COMFEY"]=true, ["CORVIKNIGHT"]=true,
    ["CORVISQUIRE"]=true, ["CRAMORANT"]=true, ["CRESSELIA"]=true,
    ["CROBAT"]=true, ["CRYOGONAL"]=true, ["CURSOLA"]=true,
    ["DARTRIX"]=true, ["DEOXYS"]=true, ["DHELMISE"]=true,
    ["DOUBLADE"]=true, ["DRAGONITE"]=true, ["DRIFBLIM"]=true,
    ["DRIFLOON"]=true, ["DUCKLETT"]=true, ["DUOSION"]=true,
    ["DUSCLOPS"]=true, ["DUSKNOIR"]=true, ["DUSKULL"]=true,
    ["EELEKTRIK"]=true, ["EELEKTROSS"]=true, ["EMOLGA"]=true,
    ["ENAMORUS"]=true, ["FEAROW"]=true, ["FLETCHINDER"]=true,
    ["FLETCHLING"]=true, ["FLUTTERMANE"]=true, ["FLYGON"]=true,
    ["FROSLASS"]=true, ["GASTLY"]=true, ["GENGAR"]=true,
    ["GIRATINA"]=true, ["GLIGAR"]=true, ["GLISCOR"]=true,
    ["GOLBAT"]=true, ["GOLETT"]=true, ["GOLURK"]=true,
    ["GOUGINGFIRE"]=true, ["GOURGEIST"]=true, ["GYARADOS"]=true,
    ["HAUNTER"]=true, ["HONCHKROW"]=true, ["HONEDGE"]=true,
    ["HOOH"]=true, ["HOOTHOOT"]=true, ["HOPPIP"]=true,
    ["HYDREIGON"]=true, ["IRONBUNDLE"]=true, ["IRONCROWN"]=true,
    ["IRONJUGULIS"]=true, ["IRONLEAVES"]=true, ["IRONMOTH"]=true,
    ["IRONVALIANT"]=true, ["JUMPLUFF"]=true, ["KILOWATTREL"]=true,
    ["KLANG"]=true, ["KLINK"]=true, ["KLINKLANG"]=true,
    ["KOFFING"]=true, ["LAMPENT"]=true, ["LANDORUS"]=true,
    ["LATIAS"]=true, ["LATIOS"]=true, ["LEDIAN"]=true,
    ["LEDYBA"]=true, ["LITWICK"]=true, ["LUGIA"]=true,
    ["LUNATONE"]=true, ["MAGNEMITE"]=true, ["MAGNETON"]=true,
    ["MAGNEZONE"]=true, ["MANDIBUZZ"]=true, ["MANTINE"]=true,
    ["MANTYKE"]=true, ["MASQUERAIN"]=true, ["MESPRIT"]=true,
    ["METAGROSS"]=true, ["METANG"]=true, ["MINIOR"]=true,
    ["MISDREAVUS"]=true, ["MISMAGIUS"]=true, ["MOLTRES"]=true,
    ["MOTHIM"]=true, ["MURKROW"]=true, ["NATU"]=true,
    ["NINJASK"]=true, ["NOCTOWL"]=true, ["NOIBAT"]=true,
    ["NOIVERN"]=true, ["ORBEETLE"]=true, ["ORICORIO"]=true,
    ["PELIPPER"]=true, ["PIDGEOT"]=true, ["PIDGEOTTO"]=true,
    ["PIDGEY"]=true, ["PIDOVE"]=true, ["PIKIPEK"]=true,
    ["PORYGON"]=true, ["PORYGON2"]=true, ["PUMPKABOO"]=true,
    ["RAGINGBOLT"]=true, ["RAYQUAZA"]=true, ["REUNICLUS"]=true,
    ["ROARINGMOON"]=true, ["ROOKIDEE"]=true, ["ROTOM"]=true,
    ["RUFFLET"]=true, ["SABLEYE"]=true, ["SALAMENCE"]=true,
    ["SCYTHER"]=true, ["SHAYMIN"]=true, ["SHUPPET"]=true,
    ["SIGILYPH"]=true, ["SKIPLOOM"]=true, ["SLITHERWING"]=true,
    ["SOLOSIS"]=true, ["SOLROCK"]=true, ["SPEAROW"]=true,
    ["SPIRITOMB"]=true, ["SQUAWKABILLY"]=true, ["STARAPTOR"]=true,
    ["STARAVIA"]=true, ["STARLY"]=true, ["SWABLU"]=true,
    ["SWANNA"]=true, ["SWELLOW"]=true, ["SWOOBAT"]=true,
    ["TAILLOW"]=true, ["TALONFLAME"]=true, ["THUNDURUS"]=true,
    ["TOGEKISS"]=true, ["TOGETIC"]=true, ["TORNADUS"]=true,
    ["TOUCANNON"]=true, ["TRANQUILL"]=true, ["TROPIUS"]=true,
    ["TRUMBEAK"]=true, ["TYNAMO"]=true, ["UNFEZANT"]=true,
    ["UNOWN"]=true, ["UXIE"]=true, ["VANILLISH"]=true,
    ["VANILLITE"]=true, ["VANILLUXE"]=true, ["VESPIQUEN"]=true,
    ["VIBRAVA"]=true, ["VIKAVOLT"]=true, ["VIVILLON"]=true,
    ["VULLABY"]=true, ["WATTREL"]=true, ["WEEZING"]=true,
    ["WINGULL"]=true, ["WOOBAT"]=true, ["XATU"]=true,
    ["YAMASK"]=true, ["YANMA"]=true, ["YANMEGA"]=true,
    ["YVELTAL"]=true, ["ZAPDOS"]=true, ["ZUBAT"]=true,
  }

  -- A hand-editable escape hatch for the type/ability rules below, for the odd
  -- species the data gets wrong.  Keys are upper-cased species ids exactly as
  -- they appear in that mod's float list (a trailing _1 form suffix is dropped
  -- before lookup).  FORBID wins over FORCE.  Empty by default -- add entries
  -- here rather than touching needsBuoy, so the two stay easy to diff.
  local BUOY_CURATED = {
    FORBID = {
      -- e.g. SHEDINJA = true,  -- Ghost, but never a floater either
    },
    FORCE = {
      -- e.g. DODUO = true,     -- force a ring on a species a rule would skip
    },
  }

  -- Ring geometry, in multiples of the sprite's own drawn size (design px).
  -- The ring is WORN on the mon's lower body, so its outer WIDTH follows the
  -- sprite's larger dimension (a wide mon gets a wide ring, a Diglett a small
  -- one), its centre sits LIFT up the body, and its near rim dips a little
  -- below the feet line, onto the water.
  --
  -- The ring lies FLAT on the water, so the oblique overhead view makes it an
  -- ellipse: its height is BUOY_SQUASH of its width (the same foreshortening
  -- the water plane itself has -- a ring lying on that plane obeys it).  A
  -- drop-in PNG should be drawn at that tilt already; the built-in primitive
  -- ring is squashed by BUOY_SQUASH to match.  All three are safe to tune.
  local BUOY_DIAM = 1.20     -- outer WIDTH / max(sprite width, sprite height)
  local BUOY_LIFT = 0.08     -- ring centre, fraction of sprite height above the feet
  local BUOY_SQUASH = 1 / 2.8 -- ring height / ring width (the water's viewing angle)
  local BUOY_INNER = 0.55    -- hole diameter / outer diameter

  -- Normalise one type token: "Water" -> WATER, "WATER_TYPE" -> WATER.
  local function normType(t)
    if type(t) ~= "string" then return nil end
    local u = t:upper():gsub("^%s+", ""):gsub("%s+$", "")
    u = u:gsub("_TYPE$", "")
    if u == "" then return nil end
    return u
  end

  -- The type set of a pokemon record (or of a mon, which carries its own on
  -- some builds), as a set keyed by the normalised id.  A mon's LIVE type
  -- list is `types` on Gen 2 and `curTypes` on Gen 1 (the engine's own
  -- convention -- see its curTypesOf), so both are read: a mon with no
  -- reachable dex record can still be rung (or spared) from itself.
  local function typeSet(src)
    local out = {}
    if type(src) ~= "table" then return out end
    local list = src.types or src.type or src.curTypes
    if type(list) ~= "table" then list = list and { list } or {} end
    for _, t in ipairs(list) do
      local u = normType(t)
      if u then out[u] = true end
    end
    return out
  end

  -- The species id a mon should be keyed by, upper-cased and with a trailing
  -- form number dropped (CHARIZARD_1 -> CHARIZARD).
  local function speciesKey(mon)
    local sp = mon and mon.species
    if type(sp) ~= "string" or sp == "" then return nil end
    return sp:upper():gsub("_%d+$", "")
  end

  local function recordFor(screen, key)
    local dex = screen and screen.data and screen.data.pokemon
    if type(dex) ~= "table" or not key then return nil end
    return dex[key] or dex[key:gsub("_%d+$", "")]
  end

  -- Does this mon levitate?  The ability may hang off the mon or its record.
  local function levitates(mon, rec)
    local ability = (mon and mon.ability) or (rec and rec.ability)
    if type(ability) ~= "string" then return false end
    local u = ability:upper():gsub("%s", ""):gsub("_", "")
    return u == "LEVITATE" or u == "LEVITATION"
  end

  -- Does this battler need holding up out of the water?
  local function needsBuoy(mon, screen)
    if type(mon) ~= "table" then return false end
    local key = speciesKey(mon)
    local base = mon.baseSpecies
    if type(base) == "string" and base ~= "" then
      base = base:upper():gsub("_%d+$", "")
    else
      base = key
    end
    -- 0. the hand-editable override wins over everything: an explicit FORBID
    --    takes the mon off the ring, an explicit FORCE puts it on one.
    local forbid = BUOY_CURATED.FORBID
    if (key and forbid[key]) or (base and forbid[base]) then return false end
    local force = BUOY_CURATED.FORCE
    if (key and force[key]) or (base and force[base]) then return true end
    -- 1. a known hoverer never needs one.
    if (key and FLOATER[key]) or (base and FLOATER[base]) then return false end
    local rec = recordFor(screen, key)
    -- 2. nor does anything with Levitate.
    if levitates(mon, rec) then return false end
    -- 3. nor a Flyer, unless it is one of the walkers that cannot actually fly.
    local types = typeSet(rec)
    for k in pairs(typeSet(mon)) do types[k] = true end
    -- With no type data at all we cannot tell -- leave the mon on its feet
    -- rather than ring a Water type whose record is missing.
    if next(types) == nil then return false end
    local grounded = (key and GROUNDED_FLYING[key]) or (base and GROUNDED_FLYING[base])
    if types[FLYING_TYPE] and not grounded then return false end
    -- 4. nor a Water type, which swims, nor a Ghost, which passes over water.
    if types[WATER_TYPE] or types[GHOST_TYPE] then return false end
    return true
  end

  ---------------------------------------------------------------------------
  -- The ring itself.
  ---------------------------------------------------------------------------
  local BUOY_ORANGE = { 0.96, 0.46, 0.06 }
  local BUOY_WHITE = { 0.97, 0.96, 0.91 }
  local BUOY_DARK = { 0.11, 0.13, 0.19 }

  -- One flat annulus sector as a single polygon: the outer arc out, the inner
  -- arc back.  Pure polygon maths, so a primitive ring needs nothing but
  -- love.graphics.polygon (arc/pie fills cannot make a hole).  `ys` squashes
  -- the arc vertically, turning the disc into the tilted ellipse the water
  -- plane implies.
  local function annulusSector(g, cx, cy, rIn, rOut, a0, a1, ys)
    ys = ys or 1
    local pts = {}
    local steps = math.max(2, math.ceil((a1 - a0) / 0.25))
    local n = 0
    for i = 0, steps do
      local a = a0 + (a1 - a0) * i / steps
      n = n + 1; pts[n] = cx + math.cos(a) * rOut
      n = n + 1; pts[n] = cy + math.sin(a) * rOut * ys
    end
    for i = steps, 0, -1 do
      local a = a0 + (a1 - a0) * i / steps
      n = n + 1; pts[n] = cx + math.cos(a) * rIn
      n = n + 1; pts[n] = cy + math.sin(a) * rIn * ys
    end
    g.polygon("fill", pts)
  end

  -- Half of the built-in ring: four 45-degree sectors over a dark base, so the
  -- inset colour reads as having a dark outline (both rims come free with the
  -- inset).  Screen y grows DOWN, so angles 0..pi are the NEAR (lower) half and
  -- pi..2pi the FAR (upper) one; the far half is drawn behind the mon and the
  -- near half over it.  Colour alternation runs across both halves unchanged,
  -- so the two halves tile into the same eight-segment ring.  Every sector is
  -- squashed by BUOY_SQUASH so the ring matches the tilted drop-in art.
  local function halfRing(g, cx, cy, rOut, far)
    local ys = BUOY_SQUASH
    local rIn = rOut * BUOY_INNER
    local line = math.max(0.5, rOut * 0.10)
    local gap = math.max(0.05, 1.1 / math.max(rOut, 1))
    local step = math.pi / 4
    local first = far and 4 or 0
    local last = first + 4
    g.setColor(BUOY_DARK[1], BUOY_DARK[2], BUOY_DARK[3], 1)
    for i = first, last - 1 do
      annulusSector(g, cx, cy, rIn, rOut, i * step, (i + 1) * step, ys)
    end
    for i = first, last - 1 do
      local c = (i % 2 == 0) and BUOY_ORANGE or BUOY_WHITE
      g.setColor(c[1], c[2], c[3], 1)
      annulusSector(g, cx, cy, rIn + line, rOut - line,
        i * step + gap, (i + 1) * step - gap, ys)
    end
  end

  ---------------------------------------------------------------------------
  -- The drop-in art.
  ---------------------------------------------------------------------------
  local buoyFiles, buoyScanned
  local function scanBuoys()
    if buoyScanned then return end
    buoyScanned = true
    buoyFiles = {}
    for _, dir in ipairs({ BUOY_DIR, "assets" }) do
      if mod and type(mod.list) == "function" then
        local ok, names = pcall(mod.list, mod, dir)
        if ok and type(names) == "table" then
          for _, name in ipairs(names) do
            if type(name) == "string" and name:sub(1, 1) ~= "." then
              local lower = name:lower()
              local stem = lower:match("^(.-)%.(png)$") or lower:match("^(.-)%.(jpg)$")
                or lower:match("^(.-)%.(jpeg)$") or lower:match("^(.-)%.(webp)$")
              if stem then
                stem = stem:gsub("_", "-"):gsub("%-%d+$", "")
                if BUOY_STEMS[stem] then
                  buoyFiles[#buoyFiles + 1] = dir .. "/" .. name
                end
              end
            end
          end
        end
      end
    end
  end

  -- One file per battle, stable for the fight (like a multi-file background).
  local function buoyFile(screen)
    scanBuoys()
    if #buoyFiles == 0 then return nil end
    local cached = screen and screen.__g9buoyFile
    if cached ~= nil then return cached or nil end
    local pick = buoyFiles[randInt(#buoyFiles)]
    if screen then screen.__g9buoyFile = pick end
    return pick
  end

  local buoyImages = {}
  local function buoyImage(file)
    local cached = buoyImages[file]
    if cached ~= nil then return cached or nil end
    local img = decode(file)
    buoyImages[file] = img or false
    if not img and mod.log and mod.log.warn then
      mod.log:warn("g9-Battle-Scene: life-buoy '%s' could not be read -- "
        .. "the built-in ring is used instead", tostring(file))
    end
    return img
  end

  -- The art's two halves as quads, so the near half can be drawn over the mon
  -- and the far half behind it.  A build without quads just draws the whole
  -- ring behind the mon (the old look) rather than the ring twice.
  local buoyQuads = {}
  local function halvesOf(img)
    local cached = buoyQuads[img]
    if cached ~= nil then return cached or nil end
    local g = love and love.graphics
    local w = img.getWidth and img:getWidth()
    local h = img.getHeight and img:getHeight()
    if not (g and g.newQuad and type(w) == "number" and type(h) == "number"
        and w > 0 and h > 0) then
      buoyQuads[img] = false
      return nil
    end
    local half = math.floor(h / 2)
    local ok, far = pcall(g.newQuad, 0, 0, w, half, w, h)
    local ok2, near = pcall(g.newQuad, 0, half, w, h - half, w, h)
    if not (ok and ok2 and far and near) then
      buoyQuads[img] = false
      return nil
    end
    local made = { far = far, near = near }
    buoyQuads[img] = made
    return made
  end

  -- A ring under every battler that needs one, read from the Screen's
  -- spriteAnchor (filled by the PREVIOUS frame's sprite pass, exactly like the
  -- contact shadows) so it needs no plumbing of its own.  `front` false draws
  -- each ring's far half (behind the mon), true its near half (over it).
  local function drawBuoys(screen, front)
    local anchors = screen and screen.spriteAnchor
    if type(anchors) ~= "table" then return end
    local g = love and love.graphics
    if not (g and g.draw and g.polygon) then return end
    local file = buoyFile(screen)
    local img = file and buoyImage(file) or nil
    local iw = img and img.getWidth and img:getWidth() or 0
    local ih = img and img.getHeight and img:getHeight() or 0
    if img and not (type(iw) == "number" and iw > 0) then img = nil end
    if img and not (type(ih) == "number" and ih > 0) then ih = iw end
    local halves = img and halvesOf(img) or nil
    if img and front and not halves then return end
    for _, list in ipairs({ screen.enemyBattlers, screen.playerBattlers }) do
      if type(list) == "table" then
        for _, battler in ipairs(list) do
          local a = anchors[battler]
          if type(a) == "table" and needsBuoy(battler and battler.mon, screen) then
            local x, y = a.x, a.y
            local w = a.w or a.h
            local h = a.h
            if type(x) == "number" and type(y) == "number"
                and type(w) == "number" and w > 1 then
              local big = w
              if type(h) == "number" and h > big then big = h end
              local size = big * BUOY_DIAM        -- the ring's WIDTH, design px
              local dh = size * (ih / iw)         -- ...and its tilted height
              local cy = y - (type(h) == "number" and h or 0) * BUOY_LIFT
              if halves then
                local s = size / iw
                g.setColor(1, 1, 1, 1)
                if front then
                  g.draw(img, halves.near, x - size / 2, cy, 0, s, s)
                else
                  g.draw(img, halves.far, x - size / 2, cy - dh / 2, 0, s, s)
                end
              elseif img then
                if not front then
                  local s = size / iw
                  g.setColor(1, 1, 1, 1)
                  g.draw(img, x - size / 2, cy - dh / 2, 0, s, s)
                end
              else
                halfRing(g, x, cy, size / 2, not front)
              end
            end
          end
        end
      end
    end
    g.setColor(1, 1, 1, 1)
  end

  -- The tag for the battle `screen` is drawing, resolved ONCE per battle and
  -- cached on the Screen.  The cache is keyed on `rollSeq`, the counter every
  -- recorded encounter roll bumps: a Screen that is somehow reused across two
  -- fights -- or one whose battle changed under it -- re-resolves for the new
  -- battle instead of handing back the first one's tag, while the per-frame
  -- draw still costs a single resolver call.  A remembered `false` (a battle
  -- that resolves to no tag at all) is a valid cache entry.  A re-resolve also
  -- DROPS the picked file (below), because the file is only meaningful beside
  -- the tag it was chosen for.
  local function cachedTag(screen)
    if screen and screen.__g9bgSeq == rollSeq and screen.__g9bgTag ~= nil then
      return screen.__g9bgTag
    end
    local t = M.resolvedTag(screen)
    if screen then
      screen.__g9bgTag = t or false
      screen.__g9bgSeq = rollSeq
      -- A miss means a NEW battle on a reused Screen, so the file picked for
      -- the old one must go with it.  Without this, M.draw would see a
      -- "current" seq (set on the line above) beside that stale file and reuse
      -- it, pinning the backdrop to the first battle's environment for the
      -- rest of the session.
      screen.__g9bgFile = nil
    end
    return t
  end

  -- The tag whose ART is actually on the field: the resolved tag when it has
  -- art of its own (or is itself a terrain tag), otherwise the first tag in its
  -- FALLBACK chain that has art (gym/Elite Four/Champion: gym.png then
  -- grass.png), otherwise the map's terrain that pickFile falls back to.  The
  -- life rings key off THIS rather than the
  -- raw tag, because the two can disagree: a static/scripted wild fight
  -- resolves to `fated` (no encounter roll behind it) and then borrows the
  -- map's water art, and a fight standing on water must float its mons
  -- whichever of the two said so.
  local function fieldTag(screen)
    local t = cachedTag(screen)
    if not t then return false end
    if #filesFor(t) > 0 or TERRAIN_TAGS[t] then return t end
    local chain = FALLBACK[t]
    if chain then
      for i = 1, #chain do
        if #filesFor(chain[i]) > 0 then return chain[i] end
      end
      return false
    end
    return inferTerrain(screen)
  end

  -- Draw the chosen backdrop behind the F/E box's own middle line (see
  -- GROUND_FEET_Y) plus its contact shadows.  `screen` caches its tag and its
  -- picked file for the life of that battle, which keeps a multi-file tag
  -- stable for the whole fight; the tag cache is keyed on the current roll
  -- (cachedTag), so a Screen reused for a LATER battle picks that battle up
  -- correctly.  Returns true when something was drawn.
  function M.draw(screen)
    local t = cachedTag(screen)
    if not t then return false end
    local file
    if screen and screen.__g9bgSeq == rollSeq and screen.__g9bgFile ~= nil then
      file = screen.__g9bgFile
    else
      file = M.pickFile(t, screen)
      if screen then screen.__g9bgFile = file or false end
    end
    local drew = false
    local img = file and imageFor(file) or nil
    local g = love and love.graphics
    if img and g then
      local w = img.getWidth and img:getWidth() or VW
      local h = img.getHeight and img:getHeight() or VH
      if w and w > 0 and h and h > 0 then
        -- Cover the band from the SCREEN'S ROOF (y = 0) down to the F/E box's
        -- middle (GROUND_FEET_Y): scale to the field's full width or to that
        -- band's height, whichever needs more, and hang the image from the
        -- top edge, so its roof is flush with the screen's roof and no white
        -- ever shows above it.  A source broad enough to reach the F/E box
        -- (any aspect >= the band's own ~2.08:1) lands its feet exactly on
        -- that middle line, its sides centred and cropped; a narrower/taller
        -- source keeps its full width and runs its overflow behind the F/E
        -- box.
        local s = math.max(VW / w, GROUND_FEET_Y / h)
        local x = (VW - w * s) / 2
        g.setColor(1, 1, 1, 1)
        g.draw(img, x, 0, 0, s, s)
        drew = true
      end
    end
    -- Contact shadows ride the backdrop, as they always have.
    if drew then pcall(drawShadows, screen) end
    -- A fight on water floats anything that cannot swim, fly or hover -- and
    -- "on water" here means the field's own terrain (fieldTag), so a scripted
    -- fight that resolves to a non-water tag yet borrows the map's water art
    -- still floats its mons.  It keys off that terrain, not off whether a
    -- backdrop file was found, so the mons also read as afloat on an install
    -- with no field art.  This is the ring's FAR half only; M.drawFront paints
    -- the near half over the mons, once battle_screen.lua has drawn them.
    if fieldTag(screen) == "water" then pcall(drawBuoys, screen, false) end
    return drew
  end

  -- The NEAR half of every life ring, over the mons' own lower bodies.  The
  -- scene calls this immediately after its sprite pass (and before the HUD
  -- boxes), which is the whole reason a water fight reads as "worn" rather
  -- than "a disc behind the mon".  Same defensive shape as draw: pcall'd at
  -- the call site there, and a no-op unless this is a water fight.
  function M.drawFront(screen)
    if fieldTag(screen) == "water" then pcall(drawBuoys, screen, true) end
  end

  -- The life-ring rules' public escape hatch (see BUOY_CURATED above): edit the
  -- FORBID/FORCE sets here at runtime, or in the file, to correct a species.
  M.buoyCurated = BUOY_CURATED

  installEncounterProbe()
  mod.exports.battleSceneBackground = M
end
