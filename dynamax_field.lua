-- g9-Battle-Scene -- the persistent DYNAMAX FIELD FX (v3.7.0).
--
-- WHAT THIS OWNS.  The Dynamax TRANSFORMATION itself is dynamax_anim.lua's
-- staged clip (gather -> flash -> burst), and the SIZE LADDER -- x1 to x1.5 in
-- four phases, and back down at the same rates when the transformation ends --
-- is g9-battle-sprites'.  What is left is what a Dynamaxed creature looks like
-- while it simply STANDS there, and that is this module:
--
--   * the DARKENED FIELD   a deep maroon wash over the whole scene, so the
--                          transformed battler reads against a dim ground;
--   * the RED AURA         a pulsing red glow behind each transformed battler;
--   * the FAINT BURST      the red explosion a Dynamaxed Pokemon leaves when it
--                          is knocked out.
--
-- It draws nothing by itself and owns no clock of its own: battle_screen.lua
-- drives it (see that file's DYNAMAX FIELD block), so everything here is a
-- pure function of the state the screen hands it.  It is a sibling file rather
-- than more lines in battle_screen.lua for the same reason dynamax_anim.lua is:
-- it needs not one engine call, so the fengari harness in scratch/sim can
-- replay it with only love.graphics mocked, and it keeps the 200-local ceiling
-- of battle_screen.lua for the code that really does touch the engine.
--
-- THE FIELD IS DRAWN BEHIND THE SPRITES.  The dim and the aura both belong
-- behind the creature -- the aura is a glow the mon stands out of, not a film
-- over it -- so battle_screen raises drawDim/drawAura from its back layer,
-- before its sprite pass, exactly where its transformation clip puts its own
-- dim and furnace (see dynamax_anim.lua's drawBack).
--
-- NEVER FATAL.  Every entry point degrades to "draws nothing" on a stub
-- love.graphics, a nil argument or a missing module export; battle_screen.lua
-- additionally pcall's each call.  Costume must never abort a turn.
return function(mod)
  local F = {}

  ----------------------------------------------------------------------
  -- options (read lazily, per call, exactly like every other row here)
  ----------------------------------------------------------------------
  local function opt(key, default)
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(function() return options:get(key) end)
      if ok and value ~= nil then return value end
    end
    return default
  end
  -- DYNAMAX DARKEN: the maroon field wash.  ON by default.
  function F.darkenOn() return opt("dynamax_darken", "on") ~= "off" end
  -- DYNAMAX AURA: the red aura AND the faint burst.  ON by default.
  function F.auraOn() return opt("dynamax_aura", "on") ~= "off" end

  ----------------------------------------------------------------------
  -- the charge: how "Dynamaxed" a battler looks right now
  ----------------------------------------------------------------------
  -- A dynamaxStateOf record (g9-battle-sprites) says whether a battler is
  -- transformed and what size factor the ladder currently holds.  The charge is
  -- that factor mapped from the ladder's own range: 1.00 -> 0, 1.50 -> 1.  So
  -- the dim and the aura ramp IN through the grow, sit full while the mon is
  -- transformed, and ride back OUT through the shrink -- the whole reverse
  -- dramatic process is one number.
  function F.charge(st)
    if type(st) ~= "table" then return 0 end
    local g = tonumber(st.grow) or 1
    local c = (g - 1) / 0.5
    if c < 0 then c = 0 elseif c > 1 then c = 1 end
    -- Transformed but the ladder is not tracking a size -- DYNAMAX GROW is off,
    -- so the factor sits at 1: still charge the aura and the field fully, so
    -- the FX do not silently depend on that other mod's row.
    if st.active and g <= 1.001 then c = 1 end
    return c
  end

  ----------------------------------------------------------------------
  -- the darkened field
  ----------------------------------------------------------------------
  -- A single translucent wash of the clip's own maroon (see dynamax_anim.lua's
  -- drawDim), scaled by `alpha` (0..1).  Drawn over the whole design canvas,
  -- BEFORE the sprites, so the battlers themselves stay full-colour.
  function F.drawDim(G, vw, vh, alpha)
    if not (G and G.push) then return end
    if not alpha or alpha <= 0.005 then return end
    if alpha > 1 then alpha = 1 end
    G.push("all")
    G.setBlendMode("alpha")
    G.setColor(0.06, 0.004, 0.014, 0.5 * alpha)
    G.rectangle("fill", 0, 0, vw or 320, vh or 180)
    G.pop()
  end

  ----------------------------------------------------------------------
  -- the red aura
  ----------------------------------------------------------------------
  -- A soft radial glow behind the creature (additive, so it reads as light)
  -- plus a hotter rim at the silhouette's own edge.  `x` is the sprite's
  -- bottom-centre anchor, `w`/`h` its drawn box; `t` is wall-clock seconds, so
  -- the pulse stays alive from frame to frame without any state here.
  function F.drawAura(G, x, y, w, h, alpha, t)
    if not (G and G.push) then return end
    if not alpha or alpha <= 0.005 then return end
    if alpha > 1 then alpha = 1 end
    local cx = x or 0
    local cy = y or 0
    local R = math.max(w or 0, h or 0) * 0.60
    if R <= 0.5 then return end
    local pulse = 0.86 + 0.14 * math.sin((t or 0) * 3.4)
    G.push("all")
    G.setBlendMode("add")
    local N = 8
    for i = N, 1, -1 do
      local f = i / N                                  -- 1 = rim, 1/N = core
      local r = R * (0.48 + 0.72 * f)
      local cr = 0.66 * (1 - 0.40 * f)
      local cg = 0.04 + 0.22 * (1 - f)
      local cb = 0.07 + 0.14 * (1 - f)
      G.setColor(cr, cg, cb, 0.095 * (1 - 0.55 * f) * alpha * pulse)
      G.circle("fill", cx, cy, r)
    end
    G.setLineWidth(1.4)
    G.setColor(1.0, 0.44, 0.34, 0.10 * alpha * pulse)
    G.circle("line", cx, cy, R * 0.99)
    G.pop()
  end

  ----------------------------------------------------------------------
  -- the faint burst
  ----------------------------------------------------------------------
  F.BURST_LIFE = 0.75

  -- A tiny deterministic LCG, so a burst is stable frame to frame and the
  -- harness replays exactly what the game draws.
  local function rng(seed)
    local s = (seed or 1) % 2147483648
    if s <= 0 then s = s + 2147483647 end
    return function()
      s = (s * 1103515245 + 12345) % 2147483648
      return s / 2147483648
    end
  end
  local function easeOut(t) local u = 1 - t return 1 - u * u * u end

  -- opts: { x, y (the sprite's own centre), w, h, seed }.  Frozen per burst so
  -- the ember spray is motion, never reshuffling.
  function F.newBurst(opts)
    opts = opts or {}
    local r = rng(opts.seed or 4242)
    local b = {
      t = 0, done = false,
      x = opts.x or 160, y = opts.y or 90,
      w = opts.w or 48, h = opts.h or 48,
      embers = {},
    }
    b.R = math.max(b.w, b.h) * 0.95
    local n = 26
    for i = 1, n do
      local a = (i / n) * 2 * math.pi + (r() - 0.5) * 0.5
      b.embers[i] = { a = a, sp = 1.3 + r() * 2.3, sz = 1.0 + r() * 2.2,
                      w = 0.6 + r() * 0.9 }
    end
    return b
  end

  function F.stepBurst(b, dt)
    if not (type(b) == "table") or b.done then return end
    b.t = b.t + (dt or 0)
    if b.t >= F.BURST_LIFE then b.done = true end
  end

  -- The burst itself: a white-hot pop, three expanding rings, a short smoke
  -- haze and a spray of embers -- the transformation clip's own vocabulary
  -- (see dynamax_anim.lua's drawShock / drawEmbers), turned loose all at once.
  function F.drawBurst(G, b)
    if not (G and G.push) then return end
    if type(b) ~= "table" or b.done then return end
    local t = b.t
    local f = t / F.BURST_LIFE
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    G.push("all")
    G.setBlendMode("add")
    -- core flash: a very short, very bright pop
    if t < 0.13 then
      local k = 1 - t / 0.13
      G.setColor(1, 0.92, 0.86, 0.85 * k)
      G.circle("fill", b.x, b.y, b.R * (0.35 + 1.05 * (1 - k)))
      G.setColor(1, 1, 1, 0.7 * k)
      G.circle("fill", b.x, b.y, b.R * 0.35 * (0.5 + 0.5 * k))
    end
    -- the rings
    for i = 1, 3 do
      local fa = (t - (i - 1) * 0.055) / F.BURST_LIFE
      if fa > 0 and fa < 1 then
        local rr = b.R * (0.15 + 1.75 * easeOut(fa))
        local a = (1 - fa) * (1 - fa)
        G.setColor(0.98, 0.24, 0.19, 0.72 * a)
        G.setLineWidth(3.4 * (1 - fa) + 0.4)
        G.circle("line", b.x, b.y, rr)
        G.setColor(1.0, 0.74, 0.60, 0.52 * a)
        G.setLineWidth(1.2 * (1 - fa) + 0.25)
        G.circle("line", b.x, b.y, math.max(0.6, rr - 2))
      end
    end
    -- the haze
    for i = 1, 5 do
      G.setColor(0.70, 0.08, 0.10, (1 - f) * 0.06 * (1 - i / 6))
      G.circle("fill", b.x, b.y, b.R * (0.30 + 1.15 * easeOut(f)) * (i / 5))
    end
    -- the embers
    for _, e in ipairs(b.embers) do
      local r = b.R * (0.25 + e.sp * easeOut(math.min(1, f * 1.7)))
      local x = b.x + math.cos(e.a) * r
      local y = b.y + math.sin(e.a) * r * 0.78 - b.R * 0.38 * f
      local a = (1 - f)
      G.setColor(1.0, 0.50 + 0.30 * e.w, 0.34, 0.68 * a)
      G.circle("fill", x, y, e.sz * (1 - f * 0.5))
    end
    G.pop()
  end

  mod.exports.battleSceneDynamaxField = F
  if mod.log then mod.log:info("g9_Battle_Scene: dynamax field FX loaded") end
end
