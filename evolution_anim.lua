-- g9-Battle-Scene -- the MEGA EVOLUTION animation.
--
-- WHAT THIS OWNS.  A once-per-battle, full-screen transformation sequence,
-- staged on the battle field around the Pokemon that is megaing.  battle_forms
-- (the engine-side form-change mod) performs the ACTUAL transformation at
-- battle.turn_started -- this mod's own action-menu FORMS cell arms the choice
-- and battle_screen.lua defers that activation to this animation's reveal beat
-- (see that file's MEGA EVOLUTION block).  So everything here is costuming: it
-- owns WHEN the change is shown and what it looks like, never what it does.
--
-- WHY IT IS ITS OWN FILE.  The sequence is ~2,900 frames of layered additive
-- drawing (an orb, a DNA helix, a spherical glass shell that breaks apart, a
-- shockwave and a star burst) and none of it needs a single engine call, so it
-- is kept a pure visitor: battle_screen.lua hands it a screen position and a
-- sprite box and drives it with step/draw.  That also means the fengari
-- harness in scratch/sim can replay it with only love.graphics mocked.
--
-- THE SEQUENCE, beat by beat (times in seconds from the clip's own start):
--
--   0.00 - 1.25  CHARGE      helical rainbow energy spirals up out of the
--                            ground and around the mon; a ground glow builds.
--   0.40 - 3.40  AURA        an additive rainbow halo pulses and swells
--                            around the whole sprite -- the "overloading
--                            magic fume" -- peaking with the orb.
--   0.65 - 2.12  GLASS       a faceted glass sphere closes around the mon (the
--                            near hemisphere only, so it reads as a bubble).
--   0.45 - 2.20  ORB         the rainbow DNA sphere: it scales up in front of
--                            the chest with a slight overshoot, a two-strand
--                            helix turning inside it, lavender-to-teal body,
--                            white rim and a 4-point sparkle.
--   0.95 - 2.12  STAR        eight pointed rays breathe out of the orb -- four
--                            CARDINAL (up/down/left/right) and four SUBCARDINAL
--                            (the diagonals) -- with the two families OUT OF
--                            PHASE: the cardinals extend while the diagonals
--                            retract, and then the reverse.  Each ray is a
--                            SHARP spike (a waist just off the orb, then a true
--                            point), and behind them a soft WASH of colour --
--                            near-solid at the sphere, fading with no straight
--                            edges to a true transparent 0 past the longest the
--                            points reach -- light propagating outward and
--                            dimming with distance.
--   0.80 - 3.10  PIXELS      square pixel sparkles (the cart's own chunky
--                            scale) drift and twinkle around everything.
--   1.70 - 2.45  FLASH       a full-screen white bloom.  It peaks at FLASH_IN
--                            (1.86) and HOLDS to 2.06, so the
--   1.95  REVEAL             REVEAL beat sits INSIDE the white window.  The
--                            peak is capped at FLASH_ALPHA (0.30) -- a white
--                            screen at 30% opacity rather than a solid one --
--                            so the sequence never flash-bangs the viewer;
--                            battle_screen performs the form change there,
--                            with the sprite itself held as a solid white
--                            silhouette (E.whiten), which is what keeps the
--                            old art and the new art from being told apart.
--                            battle_screen also FREEZES this clip on
--                            that beat (E.step's `hold`) until the new form's
--                            own art is ready to draw, so a sheet that is still
--                            baking cannot pop in after the flash has gone --
--                            the screen stays in the window until the
--                            replacement can actually be made, and only then
--                            blooms open on the new sprite.
--   2.12 - 3.20  SHATTER     the glass sphere breaks: every facet flies
--                            outward along its own normal, tumbling and
--                            spreading, white-edged and iridescent.
--   2.30 - 3.25  SHOCK       the air release -- three pale expanding rings
--                            plus a spherical haze disc -- and with it the
--                            rainbow star burst (4-point stars, hue-cycled).
--   2.95 - 3.60  SETTLE      the aura dies down; a small rainbow DNA sphere
--                            lifts off the mon's head and fades out.
--
-- The whole thing is drawn in the scene's DESIGN space (320x180, DS=3 to the
-- canvas), so a "pixel" here is the same 3x3 canvas block the rest of the
-- scene's art lands on.
--
-- NEVER FATAL.  Every entry point is written so a missing image, a nil field
-- or a stub love.graphics degrades to "draws nothing"; battle_screen.lua
-- additionally pcall's the whole draw.  A costume must never abort a turn.
return function(mod)
  local E = {}

  -- The timeline.  REVEAL_T is load-bearing: battle_screen.lua performs the
  -- actual form change the frame this clip reports `revealed`, which is where
  -- the flash is at its peak.
  local REVEAL_T = 1.95
  local SHATTER_T = 2.12
  local SHOCK_T = 2.30
  local SETTLE_T = 2.95
  local END_T = 3.60

  -- The full-screen flash's own beats (see E.flashAlpha).  FLASH_IN/FLASH_OUT
  -- bound the white window the reveal is hidden inside, and REVEAL_T is between
  -- them by construction -- that is the whole property this sequence exists to
  -- keep (a swap the player can see is a swap that reads as a glitch), so both
  -- are published and asserted by the harness rather than left implicit.
  local FLASH_START, FLASH_IN, FLASH_OUT, FLASH_END = 1.70, 1.86, 2.06, 2.45

  -- How opaque the full-screen flash may get at its peak.  It used to reach a
  -- SOLID white (1.0), a flash-bang on a large screen; it is fixed at 0.30
  -- (70% transparent) so the sequence is easy on the eyes.  The whole curve --
  -- the ramp in, the white window, the fade -- scales by this, so the beat is
  -- dimmer throughout, never just at its peak.  The swap stays hidden because
  -- the sprite is held as a solid white silhouette (E.whiten) across the
  -- reveal, not because the screen is opaque.
  local FLASH_ALPHA = 0.30

  E.REVEAL_T = REVEAL_T
  E.END_T = END_T
  E.FLASH_START = FLASH_START
  E.FLASH_IN = FLASH_IN
  E.FLASH_OUT = FLASH_OUT
  E.FLASH_END = FLASH_END
  E.FLASH_ALPHA = FLASH_ALPHA

  ----------------------------------------------------------------------
  -- small math / colour helpers
  ----------------------------------------------------------------------
  local function lerp(a, b, t) return a + (b - a) * t end
  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end
  local function easeOut(t) local u = 1 - t; return 1 - u * u * u end
  local function easeIn(t) return t * t end

  -- hsv -> rgb, all channels 0..1.  The rainbow the clip is built out of is
  -- this one function: every coloured element cycles its hue through here.
  local function hsv(h, s, v)
    h = h - math.floor(h)
    if s <= 0 then return v, v, v end
    h = h * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    i = i % 6
    if i == 0 then return v, t, p end
    if i == 1 then return q, v, p end
    if i == 2 then return p, v, t end
    if i == 3 then return p, q, v end
    if i == 4 then return t, p, v end
    return v, p, q
  end

  -- A tiny deterministic LCG.  Deterministic matters twice over: the particle
  -- field must not reshuffle every frame, and the harness has to be able to
  -- replay the exact clip the game draws.
  local function rng(seed)
    local s = (seed or 1) % 2147483648
    if s <= 0 then s = s + 2147483647 end
    return function()
      s = (s * 1103515245 + 12345) % 2147483648
      return s / 2147483648
    end
  end

  ----------------------------------------------------------------------
  -- geometry: the spherical shell
  ----------------------------------------------------------------------
  -- The glass sphere is a lat/long grid of quads on the unit sphere.  Each
  -- facet keeps its four corner vectors, its own outward normal, and a little
  -- per-facet personality (tumble rate, outward speed, hue, start delay) so
  -- the shatter is a thousand-piece break rather than one uniform inflate.
  local function unit(lon, lat)
    local cl = math.cos(lat)
    return { x = cl * math.cos(lon), y = math.sin(lat), z = cl * math.sin(lon) }
  end

  local function buildShards(rnd)
    local NLON, NLAT = 10, 6
    local out = {}
    for i = 0, NLON - 1 do
      for j = 0, NLAT - 1 do
        local lon0 = (i / NLON) * 2 * math.pi
        local lon1 = ((i + 1) / NLON) * 2 * math.pi
        local lat0 = -math.pi / 2 + (j / NLAT) * math.pi
        local lat1 = -math.pi / 2 + ((j + 1) / NLAT) * math.pi
        local c = {
          unit(lon0, lat0), unit(lon1, lat0), unit(lon1, lat1), unit(lon0, lat1),
        }
        local nx, ny, nz = 0, 0, 0
        for k = 1, 4 do nx, ny, nz = nx + c[k].x, ny + c[k].y, nz + c[k].z end
        local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
        if nl > 0 then nx, ny, nz = nx / nl, ny / nl, nz / nl end
        out[#out + 1] = {
          c = c, n = { x = nx, y = ny, z = nz },
          spin = (rnd() - 0.5) * 7,
          speed = 0.55 + rnd() * 1.10,
          delay = rnd() * 0.12,
          hue = rnd(),
        }
      end
    end
    return out
  end

  -- Rotate a unit vector by the shell's tilt (about x) then its spin (about y)
  -- and hand back screen-space x/y (in units of the shell radius) plus depth.
  local function rotv(clip, v)
    local ct, st = math.cos(clip.tilt), math.sin(clip.tilt)
    local cr, sr = math.cos(clip.shellRot), math.sin(clip.shellRot)
    local y1 = v.y * ct - v.z * st
    local z1 = v.y * st + v.z * ct
    local x2 = v.x * cr + z1 * sr
    local z2 = -v.x * sr + z1 * cr
    return x2, y1, z2
  end

  local function projOf(clip, v, R)
    local x2, y1, z2 = rotv(clip, v)
    return clip.cx + x2 * R, clip.cy + y1 * R, z2
  end

  ----------------------------------------------------------------------
  -- clip construction
  ----------------------------------------------------------------------
  -- opts:  x (the sprite's anchor: its centre-x, design px)
  --        cx (optional: where to DRAW the sequence.  battle_screen passes
  --            the centre of the pixels the sprite really paints, which is the
  --            same as `x` unless the art sits off-centre inside the frame it
  --            was baked into -- see that file's Ev.artShiftX)
  --        top  feet  w  h  side  seed (optional)  vw/vh (optional canvas
  --        size, default 320x180)
  local function newClip(opts)
    opts = opts or {}
    local rnd = rng(opts.seed or 20260919)
    local clip = {
      t = 0, done = false, revealed = false, onReveal = nil,
      x = opts.x or 160, top = opts.top or 60, feet = opts.feet or 120,
      w = opts.w or 48, h = opts.h or 48,
      side = opts.side or "player",
      hue = opts.hue or 0,
      vw = opts.vw or 320, vh = opts.vh or 180,
      rnd = rnd,
      shellRot = 0, tilt = 0.26,
      shards = buildShards(rnd),
      wisps = {}, pixels = {}, stars = {},
    }
    -- `x` is the anchor the sprite itself is drawn on; `cx` is where the show
    -- is drawn.  They are the same number unless the caller measured the art
    -- and found it off-centre in its own frame, in which case every spherical
    -- element here -- orb, ring, shell, aura, beams, shockwave, stars -- moves
    -- with `cx` and lands on the creature rather than on the frame's edge.
    clip.cx = opts.cx or clip.x
    clip.artShift = clip.cx - clip.x
    -- The orb sits at the chest, a little above the sprite's own centre, which
    -- is where the clip puts it (and where "in front of the heart" reads).
    clip.cy = clip.top + clip.h * 0.42
    -- Radii are ratios of the DRAWN sprite box, so a small mon and a hulking
    -- one get a proportionally sized show.  The orb is deliberately smaller
    -- than the mon (the clip's is about a third of the body) and the shell
    -- deliberately larger than it (it has to enclose the creature).
    clip.sphereR = clamp(math.min(clip.w, clip.h) * 0.30, 6, 22)
    clip.shellR = clamp(math.max(clip.w, clip.h) * 0.62, 20, 60)
    clip.auraR = clamp(math.max(clip.w, clip.h) * 0.80, 26, 76)
    for i = 1, 16 do
      clip.wisps[i] = { a0 = rnd() * 6.283, r = rnd(), sp = 0.55 + rnd() * 0.75,
                        y0 = rnd(), hue = rnd() }
    end
    for i = 1, 30 do
      clip.pixels[i] = { a = rnd() * 6.283, d = 0.30 + rnd() * 1.05,
                         s = 0.8 + rnd() * 1.8, ph = rnd() * 6.283, hue = rnd() }
    end
    for i = 1, 34 do
      clip.stars[i] = { a = rnd() * 6.283, d = 0.25 + rnd() * 1.15,
                        sp = 0.55 + rnd() * 0.95, ph = rnd() * 6.283,
                        hue = rnd(), sz = 1.5 + rnd() * 2.6 }
    end
    return clip
  end
  E.new = newClip

  ----------------------------------------------------------------------
  -- driving
  ----------------------------------------------------------------------
  -- One tick.  `hold` FREEZES the clock -- battle_screen raises it while the
  -- screen is being held solid white (see FLASH above), which is how a frame
  -- the player must not see can be kept off the screen for as long as the art
  -- behind it needs.  The reveal beat SNAPS the clock to REVEAL_T, so the white
  -- the form change hides under is the same on every machine whatever frame
  -- time got there (and so a hold that starts on that beat starts from the
  -- flash's own solid window rather than a frame past it).
  function E.step(clip, dt, hold)
    if clip.done then return end
    if hold then return end
    dt = dt or 0
    clip.t = clip.t + dt
    clip.shellRot = clip.shellRot + dt * 0.85
    if not clip.revealed and clip.t >= REVEAL_T then
      clip.t = REVEAL_T
      clip.revealed = true
      local cb = clip.onReveal
      if cb then cb(clip) end
    end
    if clip.t >= END_T then clip.done = true end
  end

  -- 0..1: "how white the sprite is right now", which battle_screen multiplies
  -- its sprite draw's colour by (0 is the ordinary art, 1 a solid white
  -- silhouette).  The shape is the clip's own: a shimmer from 0.45s, a hard
  -- ramp into the reveal, held through the shatter, released over the new form
  -- so its colour blooms back in.  It is already at 1 by FLASH_IN -- i.e.
  -- before the reveal beat -- so the frame the form changes on is both a solid
  -- silhouette and under a solid flash.
  function E.whiten(clip)
    local t = clip.t
    if t < 0.45 then return 0 end
    if t < 1.35 then return 0.30 * ((t - 0.45) / 0.90) end
    if t < FLASH_IN then return lerp(0.30, 1.0, (t - 1.35) / (FLASH_IN - 1.35)) end
    if t < SHATTER_T then return 1.0 end
    if t < 2.62 then return 1.0 - ((t - SHATTER_T) / (2.62 - SHATTER_T)) end
    return 0
  end

  -- 0..FLASH_ALPHA: how opaque the FULL-SCREEN flash is right now.  It peaks
  -- across FLASH_IN..FLASH_OUT -- the window the reveal beat sits inside -- with
  -- a quadratic ramp in and a linear fade out, and the whole curve is scaled by
  -- FLASH_ALPHA so the peak is a 30%-opaque white rather than a solid one.
  -- Published (rather than buried in the draw) because the one property this
  -- sequence must keep is "the swap is under the flash window", and a harness
  -- can only assert that if the number is askable.
  function E.flashAlpha(clip)
    local t = clip.t
    if t < FLASH_START or t >= FLASH_END then return 0 end
    local a
    if t < FLASH_IN then
      local u = (t - FLASH_START) / (FLASH_IN - FLASH_START)
      a = u * u
    elseif t <= FLASH_OUT then
      a = 1
    else
      a = 1 - (t - FLASH_OUT) / (FLASH_END - FLASH_OUT)
    end
    return a * FLASH_ALPHA
  end

  -- A short size pop on the frame the new form lands (the clip's "power
  -- surge"), easing back to exactly 1 so nothing is left rescaled.
  function E.scaleMul(clip)
    local t = clip.t
    if t < REVEAL_T then return 1 end
    local a = (t - REVEAL_T) / 0.32
    if a >= 1 then return 1 end
    local u = 1 - a
    return 1 + 0.13 * u * u
  end

  ----------------------------------------------------------------------
  -- the particles
  ----------------------------------------------------------------------
  -- The clip darkens the whole field the instant the transformation starts,
  -- which is what lets a rainbow read against a bright sky.  Fades in before
  -- the orb and out under the shockwave, so the battle is back to normal by
  -- the time the new form settles.
  local function drawDim(clip)
    local t = clip.t
    local a = clamp((t - 0.50) / 0.55, 0, 1) * (1 - clamp((t - 2.55) / 0.60, 0, 1))
    a = a * 0.42
    if a <= 0 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("alpha")
    G.setColor(0.02, 0.02, 0.07, a)
    G.rectangle("fill", 0, 0, clip.vw, clip.vh)
    G.pop()
  end

  local function drawCharge(clip)
    local G = love.graphics
    local t, cx, feet, h = clip.t, clip.cx, clip.feet, clip.h
    local fade = 1 - clamp((t - 0.80) / 0.45, 0, 1)
    if fade <= 0 then return end
    G.push("all")
    G.setBlendMode("add")
    for i = 1, 4 do
      local rr, gg, bb = hsv(clip.hue + i * 0.07 + t * 0.25, 0.55, 1)
      G.setColor(rr, gg, bb, (0.15 - i * 0.024) * fade)
      G.circle("fill", cx, feet, 6 + i * 4)
    end
    for _, w in ipairs(clip.wisps) do
      local prog = (w.y0 + t * w.sp) % 1
      local y = feet - prog * h * 1.30
      local ang = w.a0 + t * 2.1 + prog * 3.4
      local rad = (9 + 13 * w.r) * (1 - prog * 0.35)
      local x = cx + math.cos(ang) * rad
      local a = (1 - prog) * 0.80 * fade
      local rr, gg, bb = hsv(w.hue + t * 0.30, 0.72, 1)
      G.setColor(rr, gg, bb, a * 0.55)
      G.circle("fill", x, y, 2.7)
      G.setColor(1, 1, 1, a * 0.70)
      G.circle("fill", x, y, 1.2)
    end
    G.pop()
  end

  local function drawAura(clip)
    local G = love.graphics
    local t, cx, cy, R = clip.t, clip.cx, clip.cy, clip.auraR
    local k = math.min(clamp((t - 0.40) / 0.55, 0, 1),
                      1 - clamp((t - 3.00) / 0.42, 0, 1))
    if k <= 0 then return end
    k = k * (1 + 0.10 * math.sin(t * 11.0))
    G.push("all")
    G.setBlendMode("add")
    for i = 12, 1, -1 do
      local f = i / 12
      local rr, gg, bb = hsv(clip.hue + f * 0.75 + t * 0.26, 0.92, 1)
      G.setColor(rr, gg, bb, 0.065 * k * (1 - f * 0.40))
      G.circle("fill", cx, cy, R * (0.28 + 0.72 * f))
    end
    -- a churning rainbow band that turns around the mon, so the aura reads as
    -- "overloading" energy rather than a static glow
    for i = 0, 20 do
      local a = (i / 21) * 2 * math.pi + t * 0.55
      local rr, gg, bb = hsv(i / 21 + t * 0.30, 0.90, 1)
      G.setColor(rr, gg, bb, 0.24 * k)
      G.circle("fill", cx + math.cos(a) * R * 0.72,
        cy + math.sin(a) * R * 0.60, 2.0)
    end
    -- the fume: bright motes rising through the halo, hue-cycled
    for i, w in ipairs(clip.wisps) do
      local prog = (w.y0 + t * 0.42) % 1
      local y = clip.feet - prog * clip.h * 1.55
      local x = cx + math.sin(w.a0 + t * 0.9 + prog * 4.0) * R * 0.55
      local rr, gg, bb = hsv(w.hue + t * 0.35 + prog * 0.3, 0.60, 1)
      G.setColor(rr, gg, bb, (1 - prog) * 0.16 * k)
      G.circle("fill", x, y, 2.4)
    end
    G.pop()
  end

  local function drawShell(clip)
    local G = love.graphics
    local t = clip.t
    local R = clip.shellR * (1 + 0.03 * math.sin(t * 9.0))
    local age = t - SHATTER_T
    G.push("all")
    if age < 0 then
      local inA = clamp((t - 0.65) / 0.75, 0, 1)
      G.setBlendMode("alpha")
      for i = 6, 1, -1 do
        local f = i / 6
        local rr, gg, bb = hsv(clip.hue + 0.15 + f * 0.40 + t * 0.10, 0.50, 1)
        G.setColor(rr, gg, bb, 0.030 * inA)
        G.circle("fill", clip.cx, clip.cy, R * f)
      end
      G.setBlendMode("add")
      G.setLineWidth(0.7)
      for _, s in ipairs(clip.shards) do
        local _, _, nz = rotv(clip, s.n)
        if nz > -0.05 then
          local pts = {}
          for k = 1, 4 do
            local px, py = projOf(clip, s.c[k], R)
            pts[#pts + 1] = px
            pts[#pts + 1] = py
          end
          local rr, gg, bb = hsv(s.hue + t * 0.14 + nz * 0.30, 0.55, 1)
          G.setColor(rr, gg, bb, (0.07 + 0.10 * nz) * inA)
          G.polygon("fill", pts)
          G.setColor(0.88, 0.96, 1.0, (0.20 + 0.34 * nz) * inA)
          G.polygon("line", pts)
          -- a specular glint on the facets nearest the viewer
          if nz > 0.72 then
            G.setColor(1, 1, 1, (nz - 0.72) * 1.1 * inA)
            G.circle("fill", (pts[1] + pts[3]) / 2, (pts[2] + pts[4]) / 2, 0.7)
          end
        end
      end
    elseif age < 1.35 then
      G.setBlendMode("add")
      G.setLineWidth(1)
      for _, s in ipairs(clip.shards) do
        local a0 = clamp((age - s.delay) / 1.20, 0, 1)
        if a0 > 0 and a0 < 1 then
          local _, _, nz = rotv(clip, s.n)
          local sx0, sy0 = projOf(clip, s.n, R)
          local dx, dy = sx0 - clip.cx, sy0 - clip.cy
          -- EXPLOSIVE: a shard leaves the shell at several times the sphere's
          -- own radius, so the break reads as a burst rather than an inflate.
          local grow = 1 + a0 * (1.9 + s.speed * 1.7)
          local ex, ey = clip.cx + dx * grow, clip.cy + dy * grow
          local cs = math.cos(s.spin * age)
          local sn = math.sin(s.spin * age)
          local sc = 1 + age * 0.35
          local pts = {}
          for k = 1, 4 do
            local px, py = projOf(clip, s.c[k], R)
            local ox, oy = (px - sx0) * sc, (py - sy0) * sc
            pts[#pts + 1] = ex + ox * cs - oy * sn
            pts[#pts + 1] = ey + ox * sn + oy * cs
          end
          local fade = 1 - a0
          fade = fade * fade
          local rr, gg, bb = hsv(s.hue + age * 0.75, 0.32 * fade, 1)
          -- translucent GLASS, not a solid plate: a low-alpha body with a
          -- bright edge is what makes a facet read as a pane
          G.setColor(rr, gg, bb, 0.18 * fade)
          G.polygon("fill", pts)
          G.setColor(1, 1, 1, 0.95 * fade)
          G.setLineWidth(0.7)
          G.polygon("line", pts)
          G.setColor(0.72, 0.92, 1.0, 0.60 * fade)
          G.setLineWidth(0.4)
          G.polygon("line", pts)
        end
      end
    end
    G.pop()
  end

  ----------------------------------------------------------------------
  -- the rainbow DNA sphere (shared by the main orb and the farewell orb)
  ----------------------------------------------------------------------
  local function drawOrbAt(clip, cx, cy, R, alpha, phase)
    local G = love.graphics
    if R < 0.6 or alpha <= 0.02 then return end
    alpha = clamp(alpha, 0, 1)
    -- body: a lavender-to-teal radial gradient with the highlight pulled up
    -- and to the left, so the orb reads as lit rather than flat.
    G.setBlendMode("alpha")
    local K = 12
    for i = 0, K - 1 do
      local f = i / K
      local ox = -R * 0.20 * f
      local oy = -R * 0.20 * f
      local rr = lerp(0.86, 0.28, f)
      local gg = lerp(0.68, 0.86, f)
      local bb = lerp(0.96, 0.80, f)
      G.setColor(rr, gg, bb, 0.88 * alpha)
      G.circle("fill", cx + ox, cy + oy, R * (1 - f * 0.92))
    end
    -- the double helix, turning inside
    local H = R * 1.52
    local A = R * 0.42
    local turns = 1.5
    local N = 18
    local segs = {}
    local function strandPoint(s, f)
      local ang = f * turns * 2 * math.pi + s * math.pi + phase
      return math.sin(ang) * A, cy - H / 2 + H * f, math.cos(ang) * A
    end
    for s = 0, 1 do
      for i = 0, N - 1 do
        local f0, f1 = i / N, (i + 1) / N
        local x0, y0, z0 = strandPoint(s, f0)
        local x1, y1, z1 = strandPoint(s, f1)
        segs[#segs + 1] = { x0 = cx + x0, y0 = y0, x1 = cx + x1, y1 = y1,
                            z = (z0 + z1) / 2, kind = "strand", r = A }
      end
    end
    for i = 0, N - 1, 3 do
      local f = i / N
      local xa, ya, za = strandPoint(0, f)
      local xb, yb, zb = strandPoint(1, f)
      segs[#segs + 1] = { x0 = cx + xa, y0 = ya, x1 = cx + xb, y1 = yb,
                          z = (za + zb) / 2, kind = (i % 2 == 0) and "rungA" or "rungB",
                          r = A }
    end
    table.sort(segs, function(a, b) return a.z < b.z end)
    for _, sg in ipairs(segs) do
      local depth = 0.5 + 0.5 * ((sg.z / math.max(0.001, sg.r) + 1) / 2)
      if sg.kind == "strand" then
        G.setColor(0.06, 0.16, 0.34, 0.85 * alpha)
        G.setLineWidth(2.6 * depth)
        G.line(sg.x0, sg.y0, sg.x1, sg.y1)
        G.setColor(0.50, 0.90, 1.0, alpha)
        G.setLineWidth(1.2 * depth)
        G.line(sg.x0, sg.y0, sg.x1, sg.y1)
      else
        local rr, gg, bb
        if sg.kind == "rungA" then rr, gg, bb = 0.96, 0.35, 0.72 else rr, gg, bb = 1.0, 0.85, 0.28 end
        G.setColor(0.08, 0.10, 0.22, 0.80 * alpha)
        G.setLineWidth(2.4 * depth)
        G.line(sg.x0, sg.y0, sg.x1, sg.y1)
        G.setColor(rr, gg, bb, alpha)
        G.setLineWidth(1.1 * depth)
        G.line(sg.x0, sg.y0, sg.x1, sg.y1)
      end
    end
    -- RIM: a genuine RAINBOW ring -- the hue runs all the way round the
    -- circumference and turns with the clip, which is the single strongest
    -- "rainbow DNA sphere" read in the whole sequence.  Two hard-won details:
    -- (1) an arc cannot be hue-swept, so the ring is built from fat overlapping
    -- line segments; (2) it is drawn in ALPHA, not additive -- additive hues
    -- on top of the orb's own bright body (and on a bright sky) all sum to
    -- white, which is exactly how the first two cuts of this read.
    G.setBlendMode("alpha")
    local SEG = 30
    local thick = math.max(1.4, R * 0.20)
    for i = 0, SEG - 1 do
      local a0 = (i / SEG) * 2 * math.pi + phase * 0.16
      local a1 = a0 + (2 * math.pi / SEG) * 1.45
      local rr, gg, bb = hsv(i / SEG + phase * 0.08, 1.0, 1)
      G.setLineWidth(thick)
      G.setColor(0, 0, 0, 0.30 * alpha)
      G.line(cx + math.cos(a0) * R, cy + math.sin(a0) * R,
             cx + math.cos(a1) * R, cy + math.sin(a1) * R)
      G.setLineWidth(thick * 0.72)
      G.setColor(rr, gg, bb, alpha)
      G.line(cx + math.cos(a0) * R, cy + math.sin(a0) * R,
             cx + math.cos(a1) * R, cy + math.sin(a1) * R)
    end
    -- a faint hue halo just outside, also in alpha so it survives a bright
    -- background rather than summing to white
    local SEG2 = 20
    local R2 = R * 1.62
    for i = 0, SEG2 - 1 do
      local a = (i / SEG2) * 2 * math.pi - phase * 0.32
      local rr, gg, bb = hsv(i / SEG2 + phase * 0.22, 0.95, 1)
      G.setColor(rr, gg, bb, 0.45 * alpha * (0.6 + 0.4 * math.sin(i * 1.7 + phase * 2)))
      G.circle("fill", cx + math.cos(a) * R2, cy + math.sin(a) * R2 * 0.92,
        math.max(0.8, R * 0.085))
    end
    -- then the glass: a thin white edge and a small additive glint, kept
    -- deliberately small so they accent the rainbow instead of erasing it
    G.setBlendMode("add")
    G.setLineWidth(0.6)
    G.setColor(1, 1, 1, 0.55 * alpha)
    G.circle("line", cx, cy, R + math.max(1.1, R * 0.14))
    for i = 1, 3 do
      G.setColor(1, 1, 1, 0.030 * alpha)
      G.circle("fill", cx, cy, R + i * 2.6)
    end
    -- one 4-point sparkle riding the lower-right of the orb
    local sp = 1.6 + 0.5 * math.sin(phase * 4.4)
    local sxp = cx + R * 0.52
    local syp = cy + R * 0.50
    local pts = {}
    for k = 0, 7 do
      local ang = phase * 0.5 + k * math.pi / 4
      local rad = (k % 2 == 0) and sp or sp * 0.18
      pts[#pts + 1] = sxp + math.cos(ang) * rad
      pts[#pts + 1] = syp + math.sin(ang) * rad
    end
    G.setColor(1, 1, 1, 0.85 * alpha)
    G.polygon("fill", pts)
  end

  local function drawOrb(clip)
    local t = clip.t
    local R
    if t < REVEAL_T then
      R = clip.sphereR * (0.05 + 0.95 * easeOut(clamp((t - 0.45) / 0.55, 0, 1)))
      R = R * (1 + 0.34 * easeIn(clamp((t - 1.60) / (REVEAL_T - 1.60), 0, 1)))
    else
      R = clip.sphereR * 1.34 * (1 - clamp((t - REVEAL_T) / 0.42, 0, 1))
    end
    drawOrbAt(clip, clip.cx, clip.cy, R, 1, t * 1.35)
  end

  -- THE LIGHT STAR.  Eight pointed rays radiate out of the orb -- four
  -- CARDINAL (up/down/left/right) and four SUBCARDINAL (the diagonals) -- and
  -- the two families breathe OUT OF PHASE: the cardinals extend while the
  -- diagonals retract, and then the reverse, so the star pulses like a living
  -- thing instead of inflating on one waveform.  Each ray is a SHARP spike: it
  -- swells to a waist just off the orb and then tapers to a true POINT -- a
  -- flat far edge is what made the old four-beam cross read as truncated.
  --
  -- Behind them sits the WASH: a radial glow of colour that is near-solid at
  -- the sphere and fades, progressively and with NO straight edges, to a true
  -- transparent 0 by a radius past the longest the points ever get -- the light
  -- between the bars, reading as light propagating outward and dimming with
  -- distance.
  local function drawBeams(clip)
    local G = love.graphics
    local t = clip.t
    local k = clamp((t - 0.95) / 0.40, 0, 1) * (1 - clamp((t - 1.86) / 0.26, 0, 1))
    if k <= 0 then return end
    local cx, cy = clip.cx, clip.cy
    local R = clip.sphereR

    local BASE, AMP = 92, 0.24                -- the star's length and its breath
    local b = math.sin(t * 4.0)               -- the two families share one wave
    local lenCard = BASE * (1 + AMP * b)
    local lenSub = BASE * (1 - AMP * b)
    -- The wash reaches well past the longest the points ever get, and is
    -- exactly transparent by then, so its outgrowth is visible rather than a
    -- fade that lands right on the tips.
    local washR = BASE * (1 + AMP) * 1.38

    local CARD = { 0, math.pi * 0.5, math.pi, math.pi * 1.5 }
    local SUBC = { math.pi * 0.25, math.pi * 0.75, math.pi * 1.25, math.pi * 1.75 }
    local function hueOf(i) return i / 8 + t * 0.20 end

    G.push("all")

    -- The wash: light propagating outward from the sphere and dimming with
    -- distance.  Concentric discs whose alphas are SOLVED so the composited
    -- result is exactly A(r) = WASH_A * (1 - r/washR)^1.5 -- solid colour at
    -- the sphere, fading progressively to a true 0 at washR.  The gentle
    -- exponent (rather than a squared one) keeps a visible trace of light out
    -- past the longest points before it dies, so the glow is seen to outgrow
    -- them.  Discs rather than wedges or a ray-shaped lobe: a radial glow has
    -- no straight edges anywhere, so none of it can read as a rectangular band,
    -- and it is the light seen between the bars.  (Many rings: each disc is a
    -- single flat colour, so the composited alpha is a step function, and too
    -- few steps read as visible concentric rings -- 64 keeps the steps finer
    -- than the eye picks out.)
    local WASH_A = 0.60 * k
    local NR = 64
    local function profile(r) return WASH_A * (1 - r / washR) ^ 1.5 end
    local function wash()
      G.setBlendMode("alpha")
      for i = NR, 1, -1 do
        local r0 = washR * ((i - 1) / NR)
        local r1 = washR * (i / NR)
        local aa = 1 - (1 - profile(r0)) / (1 - profile(r1))
        if aa > 0.004 then
          local s = i / NR
          local rr, gg, bb = hsv(0.58 + s * 0.30 + t * 0.16, 0.60, 1)
          G.setColor(rr, gg, bb, aa)
          G.circle("fill", cx, cy, r1)
        end
      end
    end

    -- The ray itself: every layer is the SAME pointed spike, NESTED one inside
    -- another with the longest giving the silhouette.  Because each layer ends
    -- in a single vertex and the longest is the outline, the ray's tip is one
    -- clean point -- no stroke cap (flat) and no miter join at that acute apex
    -- (which a clipped miter turns into a blunt end) ever sits there.  A
    -- coloured body, a warmer mid spike, and an additive white core, all sharing
    -- the same waist fraction and tapering together to the point.
    local function spike(ang, far, hue)
      local ux, uy = math.cos(ang), math.sin(ang)
      local px, py = -uy, ux
      local rr, gg, bb = hsv(hue, 0.72, 1)
      local W0, WM = R * 0.16, R * 0.60
      local function layer(len, w0, wm, r, g, bl, a)
        local wx, wy = cx + ux * len * 0.34, cy + uy * len * 0.34
        G.setColor(r, g, bl, a)
        G.polygon("fill", {
          cx + px * w0, cy + py * w0,
          wx + px * wm, wy + py * wm,
          cx + ux * len, cy + uy * len,
          wx - px * wm, wy - py * wm,
          cx - px * w0, cy - py * w0,
        })
      end
      G.setBlendMode("alpha")
      layer(far, W0, WM, rr, gg, bb, 0.34 * k)
      layer(far * 0.90, W0 * 0.80, WM * 0.66,
        0.42 + rr * 0.58, 0.42 + gg * 0.58, 0.42 + bb * 0.58, 0.30 * k)
      G.setBlendMode("add")
      layer(far * 0.78, W0 * 0.34, WM * 0.20, 1, 1, 1, 0.45 * k)
    end

    wash()
    for i = 1, 4 do spike(CARD[i], lenCard, hueOf(i - 1)) end
    for i = 1, 4 do spike(SUBC[i], lenSub, hueOf(i + 3)) end
    G.pop()
  end

  local function drawPixels(clip)
    local G = love.graphics
    local t = clip.t
    local k = clamp((t - 0.80) / 0.40, 0, 1) * (1 - clamp((t - 2.72) / 0.40, 0, 1))
    if k <= 0 then return end
    local list = {}
    for _, p in ipairs(clip.pixels) do
      local d = p.d * clip.auraR
      local x = clip.cx + math.cos(p.a + t * 0.25) * d
      local y = clip.cy + math.sin(p.a * 1.7 + t * 0.35) * d * 0.8
        - math.sin(t * 0.6 + p.ph) * 3
      local tw = 0.5 + 0.5 * math.sin(t * 7 * p.s + p.ph)
      list[#list + 1] = { x = math.floor(x), y = math.floor(y),
                          s = 0.7 + p.s * 0.5, tw = tw, k = k,
                          hue = (p.hue + t * 0.20) % 1 }
    end
    -- Same two-pass reason as the star burst: the body must survive a bright
    -- background, so it is plain alpha in a saturated hue and only the hot
    -- centre is additive.
    G.push("all")
    G.setBlendMode("alpha")
    for _, e in ipairs(list) do
      local rr, gg, bb = hsv(e.hue, 0.70, 1)
      G.setColor(rr, gg, bb, 0.62 * e.k * (0.35 + 0.65 * e.tw))
      G.rectangle("fill", e.x, e.y, e.s, e.s)
    end
    G.setBlendMode("add")
    for _, e in ipairs(list) do
      if e.tw > 0.82 then
        G.setColor(1, 1, 1, 0.45 * e.k * (e.tw - 0.82) / 0.18)
        G.rectangle("fill", e.x - 1, e.y - 1, e.s + 2, e.s + 2)
      end
    end
    G.pop()
  end

  -- The FULL-SCREEN white.  Its curve lives in E.flashAlpha (see there): a
  -- quadratic ramp in from FLASH_START, the white peak across the reveal
  -- window, and a linear fade out -- scaled throughout by FLASH_ALPHA, so the
  -- beat the form changes on is a 30%-opaque white rather than a solid one.
  local function drawFlash(clip)
    local a = E.flashAlpha(clip)
    if a <= 0 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("alpha")
    G.setColor(1, 1, 1, a)
    G.rectangle("fill", 0, 0, clip.vw, clip.vh)
    G.pop()
  end

  local function drawShock(clip)
    local G = love.graphics
    local age = clip.t - SHOCK_T
    local life = 1.05
    if age < 0 or age > life then return end
    local f = age / life
    local base = clip.auraR
    G.push("all")
    G.setBlendMode("add")
    for i = 1, 3 do
      local fa = clamp((age - (i - 1) * 0.075) / life, 0, 1)
      if fa > 0 and fa < 1 then
        local r = base * (0.22 + 1.55 * easeOut(fa))
        local a = (1 - fa) * (1 - fa) * 0.72
        G.setColor(1.0, 0.97, 0.80, a)
        G.setLineWidth(3.4 * (1 - fa) + 0.5)
        G.circle("line", clip.cx, clip.cy, r)
        G.setColor(1, 1, 1, a * 0.75)
        G.setLineWidth(1.2 * (1 - fa) + 0.3)
        G.circle("line", clip.cx, clip.cy, math.max(0.6, r - 1.6))
        G.setColor(0.78, 0.92, 1.0, a * 0.55)
        G.setLineWidth(0.7)
        G.circle("line", clip.cx, clip.cy, r + 2.4)
        -- a rainbow echo just behind the leading edge
        local rr, gg, bb = hsv(i / 4 + age * 0.5, 0.8, 1)
        G.setColor(rr, gg, bb, a * 0.30)
        G.setLineWidth(0.8)
        G.circle("line", clip.cx, clip.cy, math.max(0.6, r - 4.0))
      end
    end
    -- the spherical haze behind the rings
    local rr = base * (0.30 + 1.00 * easeOut(f))
    for i = 1, 6 do
      G.setColor(1.0, 0.98, 0.86, (1 - f) * 0.050 * (1 - i / 7))
      G.circle("fill", clip.cx, clip.cy, rr * (i / 6))
    end
    G.pop()
  end

  local function drawStars(clip)
    local G = love.graphics
    local t = clip.t
    local age0 = t - SHOCK_T + 0.06
    if age0 < 0 then return end
    -- Two passes: the star BODY is drawn in plain alpha, in a saturated hue,
    -- so the rainbow survives over the white shockwave haze (an additive star
    -- over a near-white field just adds to white and vanishes -- which is
    -- exactly what the first cut of this did).  Only the tiny core is added,
    -- so each sparkle is a coloured star with a hot centre.
    local list = {}
    for _, s in ipairs(clip.stars) do
      local age = age0 * s.sp
      local life = clamp(1 - age / 1.45, 0, 1)
      if life > 0 then
        local d = (0.20 + age * 1.75) * s.d * clip.auraR
        local x = clip.cx + math.cos(s.a) * d
        local y = clip.cy + math.sin(s.a) * d * 0.85
        local tw = 0.62 + 0.38 * math.sin(t * 12 + s.ph)
        local sz = s.sz * life * (0.55 + 0.45 * tw) * 1.45
        list[#list + 1] = { x = x, y = y, sz = sz, life = life, tw = tw,
                            hue = (s.hue + age * 0.40) % 1,
                            rot = s.a + age * 0.8 }
      end
    end
    if #list == 0 then return end
    G.push("all")
    G.setBlendMode("alpha")
    for _, e in ipairs(list) do
      local rr, gg, bb = hsv(e.hue, 0.85, 1)
      local pts = {}
      for k = 0, 7 do
        local ang = e.rot + k * math.pi / 4
        local rad = (k % 2 == 0) and e.sz or e.sz * 0.18
        pts[#pts + 1] = e.x + math.cos(ang) * rad
        pts[#pts + 1] = e.y + math.sin(ang) * rad
      end
      G.setColor(rr, gg, bb, 0.90 * e.life)
      G.polygon("fill", pts)
      -- a thin dark seat so a pale star still reads on a pale flash
      G.setColor(0.05, 0.02, 0.15, 0.35 * e.life)
      G.setLineWidth(0.5)
      G.polygon("line", pts)
    end
    G.setBlendMode("add")
    for _, e in ipairs(list) do
      G.setColor(1, 1, 1, 0.95 * e.life * e.tw)
      G.circle("fill", e.x, e.y, math.max(0.35, e.sz * 0.22))
    end
    G.pop()
  end

  -- The farewell: a small rainbow DNA sphere lifts off the head and fades,
  -- the clip's own last beat.
  local function drawFarewell(clip)
    local age = clip.t - SETTLE_T
    local life = clamp(1 - age / 0.62, 0, 1)
    if life <= 0 then return end
    local y = clip.top - 6 - age * 16
    local R = clip.sphereR * 0.40 * (0.35 + 0.65 * easeOut(clamp(age / 0.25, 0, 1)))
    drawOrbAt(clip, clip.cx, y, R, life, -clip.t * 1.8)
  end

  ----------------------------------------------------------------------
  -- draw
  ----------------------------------------------------------------------
  function E.draw(clip)
    local G = love and love.graphics
    if not (G and G.push) then return end
    local t = clip.t
    drawDim(clip)
    if t < 1.25 then drawCharge(clip) end
    if t < 3.40 then drawAura(clip) end
    if t >= 0.65 and t < SHATTER_T + 1.60 then drawShell(clip) end
    -- Beams BEFORE the orb: an alpha wedge drawn over the orb veils its own
    -- rainbow ring and helix into white (which is exactly how this read before
    -- the order was fixed).  Behind it, the orb reads as the source of them.
    if t >= 0.95 and t < SHATTER_T then drawBeams(clip) end
    if t >= 0.45 and t < 2.20 then drawOrb(clip) end
    if t >= 0.80 and t < 3.12 then drawPixels(clip) end
    drawFlash(clip)
    if t >= SHOCK_T then drawShock(clip) end
    if t >= SHOCK_T - 0.06 then drawStars(clip) end
    if t >= SETTLE_T then drawFarewell(clip) end
  end

  mod.exports.battleSceneEvolutionAnim = E
  if mod.log then mod.log:info("g9_Battle_Scene: mega evolution animation loaded") end
end
