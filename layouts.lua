-- Named layout preset system: preset files live in this mod's own
-- layouts/<name>.lua (e.g. layouts/wildEncounter.lua, layouts/
-- bossFight.lua, layouts/horde.lua), each shaped exactly like the dev
-- tool's own SELECT>SAVE export (g2-Battle-Scene-Dev/dev_layout.lua's
-- EXPORT_KEY): { enemyCount, allyCount, layout }.
--
-- The NAME is the whole point: another mod that owns its own encounter-
-- trigger logic (wild grass, a boss tile, a horde spawn...) picks which
-- visual preset a battle uses by name, one call --
-- mod.exports.pushLayoutBattle("bossFight", game, world,
-- {enemies={boss}, players=party}). This mod never builds the roster
-- itself: the caller already knows what a "boss" or a "horde" is and
-- hands over real Mon objects. A layout only decides WHERE things sit on
-- screen (positions/sizes) -- enemyCount/allyCount in the file are
-- informational (the roster size that preset was tuned against), not
-- something this mod enforces or auto-generates for an arbitrary caller.
-- This mod owns no encounter-trigger logic of its own at all -- every
-- caller (Sample-Battle-Scene's own wild-encounter hook included) reads
-- these two fields as an input to ITS OWN roster-building and supplies
-- the final Mon array; this mod never builds one itself.
return function(mod)
  local ACTIVE_LAYOUT = "wildEncounter"
  mod.exports.ACTIVE_LAYOUT = ACTIVE_LAYOUT

  local LAYOUT_DIR = "layouts"

  local function fileNameFor(name)
    return LAYOUT_DIR .. "/" .. tostring(name) .. ".lua"
  end

  -- Re-read and re-parsed fresh every call, deliberately not cached: a
  -- preset file only gets read once per battle start (not per-frame), so
  -- the cost is negligible, and caching a failed read (a mid-edit file,
  -- a typo since fixed) would otherwise poison that name to the 2v2
  -- default for the rest of the process's life with no way to recover
  -- short of a full relaunch -- confirmed as a real bug this session.
  local function loadLayoutFile(name)
    local path = fileNameFor(name)
    local body = mod:read(path)
    if not body then return nil end
    local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. path)
    if not chunk then
      mod.log:warn("g9_Battle_Scene: %s failed to parse: %s", path, tostring(err))
      return nil
    end
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then
      mod.log:warn("g9_Battle_Scene: %s did not return a table", path)
      return nil
    end
    return data
  end

  -- What every battle falls back to when the active preset's file isn't
  -- present -- plain 2v2, no position/size overrides, i.e. this mod's own
  -- computed defaults (battle_screen.lua's Screen:pos/sizeMul already
  -- degrade to those when self.layout has no entry for an id).
  local DEFAULT_LAYOUT = { enemyCount = 2, allyCount = 2, layout = {} }

  -- Exposed so a caller can pick the active preset without going through
  -- pushLayoutBattle (e.g. to pre-warm/validate one before battle starts).
  function mod.exports.setActiveLayout(name)
    ACTIVE_LAYOUT = name
    mod.exports.ACTIVE_LAYOUT = name
  end

  -- Always reads mod.exports.ACTIVE_LAYOUT (not the local ACTIVE_LAYOUT
  -- upvalue) so a caller that pokes the field directly, instead of going
  -- through setActiveLayout, still takes effect.
  function mod.exports.getActiveLayoutData()
    return loadLayoutFile(mod.exports.ACTIVE_LAYOUT or ACTIVE_LAYOUT) or DEFAULT_LAYOUT
  end

  -- Reads a SPECIFIC named preset's data without touching ACTIVE_LAYOUT --
  -- for a caller that needs one preset's own enemyCount/allyCount (e.g.
  -- Sample-Battle-Scene sizing its own wild-encounter roster) without
  -- racing whatever preset some other caller most recently activated.
  -- Returns nil, NOT the generic DEFAULT_LAYOUT, when the file is
  -- missing/broken -- a caller that has its own vanilla-combat fallback
  -- needs to be able to tell "preset genuinely absent" apart from
  -- "preset present, describes a 2v2", which DEFAULT_LAYOUT's silent
  -- substitution used to hide.
  function mod.exports.getLayoutData(name)
    return loadLayoutFile(name)
  end

  -- Every layouts/<name>.lua file actually present, names only (no
  -- extension) -- a real directory listing (mod:list, the sandboxed
  -- stand-in for love.filesystem.getDirectoryItems), not a guessed range.
  function mod.exports.listLayouts()
    local names = {}
    for _, filename in ipairs(mod:list(LAYOUT_DIR) or {}) do
      local name = filename:match("^(.+)%.lua$")
      if name then names[#names + 1] = name end
    end
    return names
  end

  -- The one call another mod's own encounter-trigger logic needs: picks
  -- the named visual preset and pushes the battle screen with the exact
  -- roster the caller already built. payload is the same {enemies=,
  -- players=} shape pushDoubleBattleScreen always took -- this is a thin
  -- wrapper around it, not a replacement.
  --
  -- Refuses (returns nil, pushes nothing) when layoutName has no real
  -- preset file -- vanilla combat is the default state; this mod's own
  -- custom scene only ever appears behind a genuine, successful API call
  -- for a specific, present layout, never as a silent generic
  -- substitute. A caller gets nil back and is expected to fall through to
  -- its own vanilla-combat path (Sample-Battle-Scene's own wildEncounter
  -- trigger does exactly this when its preset is missing).
  function mod.exports.pushLayoutBattle(layoutName, game, world, payload)
    if not mod.exports.getLayoutData(layoutName) then
      mod.log:warn("g9_Battle_Scene: pushLayoutBattle(%s) -- no such layout preset, refusing",
        tostring(layoutName))
      return nil
    end
    mod.exports.setActiveLayout(layoutName)
    local pushFn = mod.exports.pushDoubleBattleScreen
    if not pushFn then
      mod.log:warn("g9_Battle_Scene: pushLayoutBattle(%s) -- battle_screen not installed",
        tostring(layoutName))
      return nil
    end
    return pushFn(game, world, payload)
  end

  mod.log:info("g9_Battle_Scene: layout system ready (%d preset(s) found, active=%s)",
    #mod.exports.listLayouts(), tostring(ACTIVE_LAYOUT))
end
