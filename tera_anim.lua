-- g9-Battle-Scene -- the TERASTALLIZATION animation.
--
-- WHAT THIS OWNS.  A once-per-battle, full-screen transformation sequence,
-- staged on the battle field around the Pokemon that is crystallising.
-- battle_forms performs the ACTUAL change (the Tera type, and with it the
-- crystal film g9-battle-sprites bakes into the sheet); battle_screen hides
-- that film behind a `__g9TeraHold` flag and clears it on this clip's REVEAL
-- beat (see that file's TERA block).  So everything here is costuming: it owns
-- WHEN the film is shown and what the show looks like, never what it does.
--
-- WHAT IT IS INSPIRED BY.  The reference clip's language, in order: translucent
-- diamond SHARDS materialise around the creature and gather; the shards fly
-- inward and lock together into a faceted crystal COCOON that encloses it;
-- light BEAMS rake in from the upper corners; the cocoon flares into a solid
-- white-cyan FLASH; the SHARDS it is made of fly back outward and dissolve; and
-- the creature stands revealed with the crystal film it keeps.  The clip's
-- crystal crown is NOT drawn here -- the persistent look is g9-battle-sprites'
-- voronoi film, which lands on the creature the frame this clip BREAKS the
-- construct.
--
-- THE COCOON IS THE SHARDS.  There is no separate shell geometry: the same blue
-- crystal points that gather are the ones that assemble into the cocoon and the
-- ones that shatter.  Every shard is a pointed hexagonal BIPYRAMID -- a long
-- crystal point -- drawn as a bright lit half, a shadowed half and a white
-- specular spine and a tip glint, and each carries a HOME on an ellipsoid around
-- the creature (a Fibonacci distribution, so the surface is covered evenly)
-- where it lands, turned to lie along the surface.  The shards on the far side
-- of that ellipsoid draw behind the creature and the near ones in front, so the
-- assembled swarm reads as a closed crystal shell with real depth -- and at the
-- break those same shards fly back outward.
--
-- THE SEQUENCE, beat by beat (seconds from the clip's start):
--
--   0.00 - 1.50  GATHER   crystal shards fade in around the creature, a few at
--                          a time then in a swirl, riding a slowly turning
--                          cylinder; a pale ground glow builds.
--   1.50 - 2.90  COCOON   the shards fly inward onto the cocoon ellipsoid and
--                          lock together, enclosing the creature; the creature
--                          WHITENS to a bright shape inside it; beams rake in
--                          from above.
--   2.90 - 3.90  HOLD     the shard cocoon stands complete and lit, the
--                          creature a white shape inside.--   1.50 - 2.90  SHELL    the faceted dome rises from the ground, enclosing the
--                          creature; the creature WHITENS to a bright shape
--                          inside it; beams rake in from above.
--   2.90 - 3.90  HOLD     the dome stands complete and lit, the creature a
--                          white shape inside.
--   3.90 - 4.22  FLASH IN a cyan-white wash ramps up into the white window.
--   4.22 - 4.44  FLASH    the screen is at its white PEAK (capped at
--                          FLASH_ALPHA, 0.30 -- a 30%-opaque white, never a
--                          solid flash-bang).  REVEAL_T = 4.32 sits inside this
--                          window, so the crystal film is placed on a frame
--                          with nothing else on it.
--   4.42 - 5.40  BREAK    the cocoon bursts: its own shards fly outward from the
--                          shell, spinning, drifting down and dissolving, while
--                          the white falls away -- the construct breaking to
--                          reveal the transformed creature.--   4.42 - 5.40  BREAK    the dome fractures: its own triangles fly outward,
--                          spinning, drifting down and dissolving, while the
--                          white falls away -- the construct breaking to reveal
--                          the transformed creature.
--   5.40 - 6.00  SETTLE   the last shards thin to a drift of pale sparkles and
--                          are gone; the creature keeps only its own film.
--
-- The whole thing is drawn in the scene's DESIGN space (320x180, DS=3 to the
-- canvas), so a "pixel" here is the same 3x3 canvas block the rest of the
-- scene's art lands on.
--
-- NEVER FATAL.  Every entry point degrades to "draws nothing" on a nil field or
-- a stub love.graphics; battle_screen.lua additionally pcall's the whole draw.
-- A costume must never abort a turn.
return function(mod)
  local E = {}

  -- The timeline.  REVEAL_T is load-bearing: battle_screen clears the sprite
  -- mod's `__g9TeraHold` here, so the crystal film is placed inside the
  -- white flash window and the BREAK that follows is what the player sees the
  -- construct do.
  local REVEAL_T = 4.32
  local END_T = 6.00
  local SHELL_T = 1.50          -- the dome starts rising
  local SHELL_FULL = 2.90       -- the dome is complete
  local FLASH_START, FLASH_IN, FLASH_OUT, FLASH_END = 3.90, 4.22, 4.44, 4.82
  local BREAK_T = 4.42          -- the dome begins to fracture

  -- How opaque the full-screen flash may get at its peak.  It used to reach a
  -- SOLID white (1.0), a flash-bang on a large screen; it is fixed at 0.30
  -- (70% transparent) so the sequence is easy on the eyes.  The whole curve --
  -- the cyan wash in, the white window, the fade -- scales by this, so the
  -- beat is dimmer throughout, never just at its peak.
  local FLASH_ALPHA = 0.30

  E.REVEAL_T = REVEAL_T
  E.END_T = END_T
  E.SHELL_T = SHELL_T
  E.SHELL_FULL = SHELL_FULL
  E.FLASH_START = FLASH_START
  E.FLASH_IN = FLASH_IN
  E.FLASH_OUT = FLASH_OUT
  E.FLASH_END = FLASH_END
  E.FLASH_ALPHA = FLASH_ALPHA
  E.BREAK_T = BREAK_T

  ----------------------------------------------------------------------
  -- small math
  ----------------------------------------------------------------------
  local function lerp(a, b, t) return a + (b - a) * t end
  local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end
  local function easeOut(t) local u = 1 - t return 1 - u * u * u end
  local function easeIn(t) return t * t end
  local function smooth(t) return t * t * (3 - 2 * t) end

  -- atan2 spelled out: Lua 5.1/LuaJIT expose math.atan2, Lua 5.3+ only
  -- math.atan(y, x) -- a local keeps this working on whichever build boots.
  local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi * 0.5 end
    if y < 0 then return -math.pi * 0.5 end
    return 0
  end

  -- A tiny deterministic LCG, so the shard field and the facet jitter are
  -- stable frame to frame and the harness replays exactly what the game draws.
  local function rng(seed)
    local s = (seed or 1) % 2147483648
    if s <= 0 then s = s + 2147483647 end
    return function()
      s = (s * 1103515245 + 12345) % 2147483648
      return s / 2147483648
    end
  end

  ----------------------------------------------------------------------
  -- the crystal's palette
  ----------------------------------------------------------------------
  -- Pale Galar crystal: deep teal shadow through ice blue to a white heart.
  local ICE_DEEP  = { 0.05, 0.18, 0.46 }
  local ICE_MID   = { 0.22, 0.56, 0.92 }
  local ICE_LIGHT = { 0.68, 0.90, 1.00 }
  local ICE_WHITE = { 0.97, 1.00, 1.00 }

  -- One light direction for every facet in the show (upper-left), so the shards
  -- and the shell are lit from the same place.
  local LIGHT_X, LIGHT_Y = -0.55, -0.72
  do
    local len = math.sqrt(LIGHT_X * LIGHT_X + LIGHT_Y * LIGHT_Y)
    LIGHT_X, LIGHT_Y = LIGHT_X / len, LIGHT_Y / len
  end

  local function mix(a, b, t)
    return lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)
  end

  ----------------------------------------------------------------------
  -- a cut crystal shard
  ----------------------------------------------------------------------
  -- A pointed hexagonal BIPYRAMID: a sharp top point, a sharp bottom point and
  -- a waist, drawn as a shadowed left half and a lit right half that meet at a
  -- hard edge, plus a white specular spine.  The hard
  -- light/dark split is what makes it read as a solid gem rather than a flat
  -- rhombus at these sizes.
  local function shard(G, x, y, w, h, rot, a)
    if a <= 0.02 or w <= 0.05 then return end
    local c, s = math.cos(rot), math.sin(rot)
    local function tx(px, py) return x + px * c - py * s, y + px * s + py * c end
    -- local anchors
    local ax, ay = tx(0, -h)                 -- top point
    local bx, by = tx(w, -h * 0.28)          -- upper right
    local cx2, cy2 = tx(w * 0.74, h * 0.46)  -- lower right
    local dx, dy = tx(0, h)                  -- bottom point
    local ex, ey = tx(-w * 0.74, h * 0.46)   -- lower left
    local fx, fy = tx(-w, -h * 0.28)         -- upper left
    local mx, my = tx(0, 0)                  -- waist centre
    -- the solid DEEP body: this is the shard's back, and it is what gives the
    -- point a dark mass against the sky
    G.setColor(ICE_DEEP[1], ICE_DEEP[2], ICE_DEEP[3], a)
    G.polygon("fill", { ax, ay, bx, by, cx2, cy2, dx, dy, ex, ey, fx, fy })
    -- the shadow half (left), a step up from the back
    G.setColor(ICE_DEEP[1] * 1.5, ICE_DEEP[2] * 1.5, ICE_DEEP[3] * 1.5, a)
    G.polygon("fill", { ax, ay, mx, my, dx, dy, ex, ey, fx, fy })
    -- the lit half (right): bright but SHEER, so the dark back shows through it
    -- and the point reads as translucent crystal, not a white paper cutout
    G.setColor(ICE_LIGHT[1], ICE_LIGHT[2], ICE_LIGHT[3], a * 0.62)
    G.polygon("fill", { ax, ay, bx, by, cx2, cy2, dx, dy, mx, my })
    -- the top-right facet catches the light hardest, so the point has one hot
    -- corner and a darker lower half
    G.setColor(ICE_WHITE[1], ICE_WHITE[2], ICE_WHITE[3], a * 0.50)
    G.polygon("fill", { ax, ay, bx, by, mx, my })
    -- a dark OUTLINE around the whole point, so it separates from the sky
    G.setColor(ICE_DEEP[1], ICE_DEEP[2], ICE_DEEP[3], a * 0.9)
    G.setLineWidth(0.6)
    G.polygon("line", { ax, ay, bx, by, cx2, cy2, dx, dy, ex, ey, fx, fy })
    G.setColor(ICE_WHITE[1], ICE_WHITE[2], ICE_WHITE[3], a)
    G.setLineWidth(0.6)
    G.line(ax, ay, dx, dy)
    -- the specular spine (a slim highlight down the long axis).  The two waist
    -- points are hoisted into locals instead of being called inside the vertex
    -- table: a call in a table constructor's LAST field expands to every value
    -- it returns, so `{ top, ..., tx(...) }` handed love.graphics.polygon SEVEN
    -- components -- and LOVE refuses an odd component count outright ("Number
    -- of vertex components must be a multiple of two").  That threw out of this
    -- shard, out of drawShards, and into the caller's pcall (which only warns)
    -- on every frame, leaving drawShards' own push on the graphics stack each
    -- time -- see the `part` guard below for why that can never happen again.
    local sx1, sy1 = tx(w * 0.16, 0)
    local sx2, sy2 = tx(-w * 0.16, 0)
    G.setColor(ICE_WHITE[1], ICE_WHITE[2], ICE_WHITE[3], a * 0.9)
    G.polygon("fill", { ax, ay, sx1, sy1, dx, dy, sx2, sy2 })
  end

  ----------------------------------------------------------------------
  -- the cocoon is built from the SHARDS themselves
  ----------------------------------------------------------------------
  -- There is no separate shell geometry any more.  The same blue crystal
  -- shards that gather around the creature ARE the cocoon: each one is given a
  -- home on an ellipsoid around it (a Fibonacci distribution over the unit
  -- sphere, mapped onto the ellipsoid), and from SHELL_T to SHELL_FULL they fly
  -- inward and lock onto that surface, turned to lie along it.  At the break
  -- the identical shards fly back outward.  Nothing else forms the construct,
  -- so removing the old triangulated dome removed the only part of the show
  -- that was not a blue shard (see drawShards).

  ----------------------------------------------------------------------
  -- clip construction
  ----------------------------------------------------------------------
  -- opts: x (the sprite anchor's centre-x), cx (optional: where the show is
  --       drawn -- battle_screen passes the centre of the pixels the sprite
  --       really paints, see that file's artShift), top, feet, w, h, side,
  --       seed, vw/vh (canvas size, default 320x180).
  local function newClip(opts)
    opts = opts or {}
    local rnd = rng(opts.seed or 20261020)
    local clip = {
      t = 0, done = false, revealed = false, onReveal = nil,
      x = opts.x or 160, top = opts.top or 60, feet = opts.feet or 120,
      w = opts.w or 48, h = opts.h or 48,
      side = opts.side or "player",
      vw = opts.vw or 320, vh = opts.vh or 180,
      rnd = rnd, shards = {}, sparks = {}, dust = {},
    }
    -- `x` is the anchor the sprite is drawn on; `cx` is where the show is
    -- drawn.  They differ only when the art sits off-centre in its own frame.
    clip.cx = opts.cx or clip.x
    clip.hy = clip.top + clip.h * 0.42
    -- Radii are ratios of the DRAWN sprite box, so a small mon and a hulking
    -- one get a proportionally sized show.
    clip.R = clamp(math.max(clip.w, clip.h), 22, 90)
    -- The cocoon: an ellipsoid around the creature's own drawn box, sized so
    -- the shards that land on it enclose the mon from just above its head down
    -- to the ground it stands on.  The domeRx/domeBaseY names are kept -- the
    -- ground glow, the inner light and the break's shockwave are all sized off
    -- them -- but the 'dome' they describe is now the SHARD cocoon.
    clip.cocoRx = math.max(clip.w * 0.60, 14)
    clip.cocoRy = math.max(clip.h * 0.60, 16)
    clip.cocoCy = clip.hy
    clip.domeRx = clip.cocoRx
    clip.domeBaseY = clip.feet
    -- The shards: a cylinder around the creature, from the ground to above
    -- its head.  Each is frozen here so the swirl is motion, not reshuffling.
    local NS = 54
    local GA = math.pi * (3 - math.sqrt(5))   -- golden angle
    for i = 1, NS do
      local a = rnd() * 6.283
      local rr = 0.40 + rnd() * 0.78
      local hh = rnd()
      local sz = 0.62 + rnd() * 1.25
      -- its HOME on the cocoon: a Fibonacci point on the unit sphere
      -- (fx/fy/fz; fz is the depth) plus the tangent angle it lies at once
      -- it lands there.
      local z = 1 - 2 * (i - 0.5) / NS
      local rxy = math.sqrt(math.max(0, 1 - z * z))
      local phi = i * GA
      local fx, fy = rxy * math.cos(phi), rxy * math.sin(phi)
      clip.shards[i] = {
        a = a, rr = rr, hh = hh, sz = sz,
        spin = (rnd() - 0.5) * 2.4,
        rise = 0.35 + rnd() * 0.85,
        appear = 0.03 + rnd() * 1.30,       -- when it fades in
        shape = 0.62 + rnd() * 0.85,
        wob = 0.80 + rnd() * 0.45,
        back = math.sin(a) < 0,
        -- the cocoon home (see the cocoon build above)
        fx = fx, fy = fy, fz = z,
        tang = atan2(fy, fx) + math.pi * 0.5,
        hsz = 0.72 + rnd() * 0.85,
        breakSpd = 0.55 + rnd() * 0.95,
      }
    end    -- The settling sparkles (after the break).
    local NK = 26
    for i = 1, NK do
      clip.sparks[i] = {
        a = rnd() * 6.283, rr = 0.30 + rnd() * 0.80, hh = rnd(),
        sz = 1.1 + rnd() * 1.5, fall = 0.18 + rnd() * 0.40,
        ph = rnd() * 6.283, back = rnd() < 0.5,
      }
    end
    -- Fine crystal dust thrown out at the break.
    local ND = 34
    for i = 1, ND do
      clip.dust[i] = {
        a = rnd() * 6.283, rr = 0.25 + rnd() * 0.95,
        sz = 0.6 + rnd() * 1.3, spd = 0.6 + rnd() * 1.4,
        ph = rnd() * 6.283,
      }
    end
    return clip
  end
  E.new = newClip

  ----------------------------------------------------------------------
  -- driving
  ----------------------------------------------------------------------
  function E.step(clip, dt, hold)
    if clip.done then return end
    if hold then return end
    clip.t = clip.t + (dt or 0)
    if not clip.revealed and clip.t >= REVEAL_T then
      clip.t = REVEAL_T
      clip.revealed = true
      local cb = clip.onReveal
      if cb then cb(clip) end
    end
    if clip.t >= END_T then clip.done = true end
  end

  -- 0..1: how bright/white the sprite should be drawn inside the shell.
  -- Released after the flash so the transformed creature's own colours (under
  -- the film) come back as the construct breaks.
  function E.whiten(clip)
    local t = clip.t
    if t < 1.60 then return 0 end
    if t < 3.90 then return (t - 1.60) / 2.30 * 0.95 end
    if t < FLASH_OUT then return 0.95 end
    if t < 4.90 then return 0.95 * (1 - (t - FLASH_OUT) / (4.90 - FLASH_OUT)) end
    return 0
  end

  -- 0..FLASH_ALPHA: the full-screen flash's opacity.  It peaks across
  -- FLASH_IN..FLASH_OUT -- the window the reveal sits inside -- with a cyan wash
  -- on the way in, and the whole curve is scaled by FLASH_ALPHA so the peak is
  -- a 30%-opaque white rather than a solid one.
  function E.flashAlpha(clip)
    local t = clip.t
    if t < FLASH_START or t >= FLASH_END then return 0 end
    local a
    if t < FLASH_IN then
      local u = (t - FLASH_START) / (FLASH_IN - FLASH_START)
      a = smooth(u)
    elseif t <= FLASH_OUT then
      a = 1
    else
      a = 1 - (t - FLASH_OUT) / (FLASH_END - FLASH_OUT)
    end
    return a * FLASH_ALPHA
  end

  -- The flash's colour: icy blue on the way in, white across the solid
  -- window, pale cyan as it falls away.
  function E.flashColor(clip)
    local t = clip.t
    if t < FLASH_IN then return 0.55, 0.82, 1.00 end
    if t < FLASH_OUT then return 1, 1, 1 end
    return 0.80, 0.94, 1.00
  end

  ----------------------------------------------------------------------
  -- the drawing
  ----------------------------------------------------------------------
  -- The pale ground glow: an icy pool where the creature stands, a bright
  -- core, and a fine ring.  Drawn in the BACK layer.
  local function drawGroundGlow(clip)
    local t = clip.t
    local k = clamp(t / 1.10, 0, 1) * (1 - clamp((t - 4.20) / 0.70, 0, 1))
    if k <= 0.01 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("add")
    local rx = clip.domeRx * 1.45
    local ry = clip.R * 0.30
    for i = 5, 1, -1 do
      local f = i / 5
      G.setColor(0.24, 0.62, 0.98, 0.050 * f * k)
      G.ellipse("fill", clip.cx, clip.domeBaseY, rx * f, ry * f)
    end
    G.setColor(0.62, 0.88, 1.00, 0.10 * k)
    G.ellipse("fill", clip.cx, clip.domeBaseY, rx * 0.32, ry * 0.32)
    G.setColor(0.55, 0.85, 1.00, 0.30 * k)
    G.setLineWidth(1.0)
    G.ellipse("line", clip.cx, clip.domeBaseY, rx * 0.90, ry * 0.90)
    G.setColor(0.85, 0.97, 1.00, 0.22 * k)
    G.setLineWidth(0.7)
    G.ellipse("line", clip.cx, clip.domeBaseY, rx * 1.10, ry * 1.10)
    G.pop()
  end

  -- The shards -- the whole show.  Each one fades in on its own beat and rides
  -- a slowly turning cylinder (GATHER); from SHELL_T it flies inward onto its
  -- home on the cocoon ellipsoid and turns to lie along the surface (COCOON);
  -- and at BREAK_T the identical shards fly back outward, tumbling, arcing down
  -- and dissolving.  `wantBack` splits the swarm so the shards on the far side
  -- of the cocoon draw behind the creature and the near ones in front of it --
  -- the clip's own depth cue, and what makes the assembled shards read as a
  -- closed crystal shell rather than a flat ring.
  local function drawShards(clip, wantBack)
    local t = clip.t
    local G = love.graphics
    local assemble = smooth(clamp((t - SHELL_T) / (SHELL_FULL - SHELL_T), 0, 1))
    local breakK = clamp((t - BREAK_T) / 1.55, 0, 1)
    if breakK >= 1 then return end
    G.push("all")
    G.setBlendMode("alpha")
    for _, sh in ipairs(clip.shards) do
      local depth = lerp(sh.back and -1 or 1, sh.fz, assemble)
      if (depth < 0) == wantBack then
        local age = t - sh.appear
        if age > 0 then
          local a = smooth(clamp(age / 0.35, 0, 1))
          if a > 0.02 then
            -- GATHER: the swirl it comes in on.
            local ang = sh.a + t * (0.30 + sh.spin * 0.10)
            local rr = clip.R * (0.36 + 0.64 * sh.rr) * (1 - 0.16 * clamp(t / 1.5, 0, 1))
            local hh = (sh.hh - 0.10) + t * sh.rise * 0.24
            local gx = clip.cx + math.cos(ang) * rr
            local gy = clip.feet - hh * clip.h * 1.18 - clip.R * 0.06
            -- COCOON: its home on the ellipsoid.
            local hx = clip.cx + sh.fx * clip.cocoRx
            local hy = clip.cocoCy + sh.fy * clip.cocoRy
            local x = lerp(gx, hx, assemble)
            local y = lerp(gy, hy, assemble)
            local rot = lerp(sh.a + t * sh.spin, sh.tang, assemble)
            local pulse = 1.0 + 0.26 * math.sin(t * 3 + sh.a) * (1 - assemble)
            local w = clip.R * 0.075 * sh.sz * lerp(pulse * sh.wob, sh.hsz, assemble)
            local hgt = clip.R * 0.205 * sh.sz * lerp(pulse * sh.shape, sh.hsz, assemble)
            if breakK > 0 then
              local dl = math.sqrt(sh.fx * sh.fx + sh.fy * sh.fy)
              local dirx, diry = 0, -1
              if dl > 0.001 then dirx, diry = sh.fx / dl, sh.fy / dl end
              local off = easeOut(breakK) * clip.R * 2.00 * sh.breakSpd
              x = x + dirx * off
              y = y + diry * off * 0.55 - breakK * clip.R * 0.70 + breakK * breakK * clip.R * 5.50
              rot = rot + breakK * sh.spin * 6.0
              a = a * (1 - breakK * breakK)
              w, hgt = w * (1 - 0.25 * breakK), hgt * (1 - 0.25 * breakK)
            end
            shard(G, x, y, w, hgt, rot, a)
          end
        end
      end
    end
    G.pop()
  end
  -- The light beams raking in from the upper corners: thin, soft wedges, kept
  -- pale so they never read as flat cards over the shell.
  local function drawBeams(clip)
    local t = clip.t
    local k = clamp((t - 1.75) / 0.70, 0, 1) * (1 - clamp((t - FLASH_IN) / 0.30, 0, 1))
    if k <= 0.01 then return end
    local G = love.graphics
    local cx, cy = clip.cx, clip.hy
    G.push("all")
    G.setBlendMode("add")
    local beams = {
      { -0.62, -0.72, 1.00 }, { 0.62, -0.72, 1.00 },
      { -0.86, -0.30, 0.66 }, { 0.86, -0.30, 0.66 },
    }
    for _, b in ipairs(beams) do
      local sx = cx + b[1] * clip.vw * 0.62
      local sy = cy + b[2] * clip.vh * 0.80
      local w = clip.R * 0.13 * b[3]
      G.setColor(0.62, 0.88, 1.00, 0.09 * k)
      G.polygon("fill", { sx - w, sy, sx + w, sy, cx + 1.5, cy, cx - 1.5, cy })
      G.setColor(1, 1, 1, 0.07 * k)
      G.polygon("fill", { sx - w * 0.24, sy, sx + w * 0.24, sy, cx + 0.8, cy, cx - 0.8, cy })
    end
    G.pop()
  end

  -- The glow building INSIDE the shell (drawn over the creature but under the
  -- flash).
  local function drawShellGlow(clip)
    local t = clip.t
    local k = clamp((t - 1.80) / 0.80, 0, 1)
    if k <= 0.01 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("add")
    local R = clip.domeRx * (0.55 + 0.45 * k)
    local tail = 1 - clamp((t - 4.42) / 0.40, 0, 1)
    if tail <= 0.01 then G.pop() return end
    -- a very soft core, kept dim so the whitened creature's SILHOUETTE still
    -- reads through the shell instead of being washed into a white ball
    for i = 7, 1, -1 do
      local f = i / 7
      G.setColor(lerp(0.30, 0.70, 1 - f), lerp(0.66, 0.92, 1 - f), 1.0,
        0.022 * k * (1 - 0.45 * f) * tail)
      G.ellipse("fill", clip.cx, clip.hy, R * f, R * f * 0.86)
    end
    G.pop()
  end

  -- The shatter: a hot burst + shockwave rings + the fine crystal dust.
  local function drawBreak(clip)
    local age = clip.t - BREAK_T
    if age < 0 then return end
    local life = 1.55
    if age > life then return end
    local f = clamp(age / life, 0, 1)
    local G = love.graphics
    local base = clip.domeRx * 1.15
    G.push("all")
    G.setBlendMode("add")
    -- the hot pop at the moment of the break
    local pop = 1 - clamp(age / 0.20, 0, 1)
    if pop > 0.01 then
      G.setColor(0.85, 0.96, 1.00, 0.50 * pop)
      G.circle("fill", clip.cx, clip.hy, clip.R * (0.30 + 0.55 * (1 - pop)))
      G.setColor(1, 1, 1, 0.70 * pop)
      G.circle("fill", clip.cx, clip.hy, clip.R * (0.12 + 0.30 * (1 - pop)))
    end
    -- the shockwave rings, squashed to the ground plane so they read as a wave
    -- rolling out along the field rather than a UI circle
    for i = 1, 3 do
      local fa = clamp((age - (i - 1) * 0.09) / life, 0, 1)
      if fa > 0 and fa < 1 then
        local r = base * (0.20 + 1.45 * easeOut(fa))
        local a = (1 - fa) * (1 - fa) * 0.42
        local ry = r * 0.42
        G.setColor(0.68, 0.90, 1.00, a)
        G.setLineWidth(2.6 * (1 - fa) + 0.4)
        G.ellipse("line", clip.cx, clip.domeBaseY, r, ry)
        G.setColor(1, 1, 1, a * 0.8)
        G.setLineWidth(1.0 * (1 - fa) + 0.3)
        G.ellipse("line", clip.cx, clip.domeBaseY, math.max(0.6, r - 1.6), math.max(0.6, ry - 0.8))
      end
    end
    -- the dust: fine crystal specks blown outward and drifting down
    G.setBlendMode("alpha")
    for _, d in ipairs(clip.dust) do
      local df = clamp(age / (life * 0.95), 0, 1)
      local rr = base * (0.20 + d.spd * easeOut(df) * 1.7) * d.rr
      local x = clip.cx + math.cos(d.a) * rr
      local y = clip.hy + math.sin(d.a) * rr * 0.62 + df * df * clip.R * 0.85
      local a = (1 - df) * 0.85
      if a > 0.02 then
        G.setColor(ICE_LIGHT[1], ICE_LIGHT[2], ICE_LIGHT[3], a)
        G.polygon("fill", { x, y - d.sz, x + d.sz * 0.55, y, x, y + d.sz, x - d.sz * 0.55, y })
        G.setColor(ICE_WHITE[1], ICE_WHITE[2], ICE_WHITE[3], a * 0.7)
        G.circle("fill", x, y, d.sz * 0.34)
      end
    end
    G.pop()
  end

  -- The settling sparkles: pale four-point stars drifting down after the
  -- break, the tail the reference clip ends on.
  local function drawSparks(clip)
    local t = clip.t
    local k = clamp((t - 4.50) / 0.55, 0, 1) * (1 - clamp((t - 5.60) / 0.40, 0, 1))
    if k <= 0.01 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("add")
    local function star(x, y, s, ang)
      local c, sn = math.cos(ang or 0), math.sin(ang or 0)
      local long, short = s, s * 0.16
      G.polygon("fill", {
        x + long * c, y + long * sn,
        x - short * sn, y + short * c,
        x - short * c, y - short * sn,
        x + short * sn, y - short * c })
      G.polygon("fill", {
        x - long * c, y - long * sn,
        x + short * sn, y - short * c,
        x + short * c, y + short * sn,
        x - short * sn, y + short * c })
    end
    for _, sp in ipairs(clip.sparks) do
      local fall = (t - 4.50) * sp.fall
      local x = clip.cx + math.cos(sp.a + t * 0.5) * clip.R * (0.35 + 0.75 * sp.rr)
      local y = clip.hy + sp.hh * clip.h * 0.9 + fall * clip.h * 1.4
      local tw = 0.5 + 0.5 * math.sin(t * 6 + sp.ph)
      G.setColor(0.78, 0.93, 1.00, 0.60 * k * tw)
      star(x, y, sp.sz * (1.3 + 0.7 * tw), t * 0.8 + sp.ph)
    end
    G.pop()
  end

  -- The full-screen flash, with radial rays raking out of the creature so the
  -- white is a burst rather than a flat card.
  local function drawFlash(clip)
    local a = E.flashAlpha(clip)
    if a <= 0 then return end
    local G = love.graphics
    local rr, gg, bb = E.flashColor(clip)
    G.push("all")
    G.setBlendMode("alpha")
    G.setColor(rr, gg, bb, a)
    G.rectangle("fill", 0, 0, clip.vw, clip.vh)
    -- rays, only while the white has not fully taken over
    local ray = 1 - clamp((clip.t - FLASH_START) / (FLASH_IN - FLASH_START), 0, 1)
    if ray > 0.01 then
      G.setBlendMode("add")
      local cx, cy = clip.cx, clip.hy
      local NR = 16
      for i = 0, NR - 1 do
        local ang = (i / NR) * 6.283 + clip.t * 0.35
        local w = clip.R * 0.10
        local sx = cx + math.cos(ang) * clip.R * 1.9
        local sy = cy + math.sin(ang) * clip.R * 1.9
        G.setColor(1, 1, 1, 0.28 * ray)
        G.polygon("fill", { sx + math.cos(ang + 1.57) * w, sy + math.sin(ang + 1.57) * w,
                            sx - math.cos(ang + 1.57) * w, sy - math.sin(ang + 1.57) * w,
                            cx, cy })
      end
    end
    G.pop()
  end

  ----------------------------------------------------------------------
  -- draw
  ----------------------------------------------------------------------
  -- One piece of the show, drawn so that a failure in it can never take the
  -- rest of the frame -- or the session -- with it.
  --
  -- A draw that throws half-way through its own push/pop pair leaves that push
  -- on love.graphics' stack for good: the caller's pcall only sees the error,
  -- and the depth then climbs by one per frame until every push in the game
  -- throws "Maximum stack depth reached (more pushes than pops?)" -- which is
  -- exactly how a single bad vertex table in one shard took the whole game down
  -- (see shard's own note).  So every piece runs inside its own pcall AND the
  -- graphics stack is put back on the depth it had before the piece ran.
  -- love.graphics.getStackDepth is LOVE 11+; where it is missing this is the
  -- plain pcall it replaces, and a failed piece still draws nothing.
  local function part(fn, ...)
    local G = love and love.graphics
    local depth
    if G and G.getStackDepth then
      local okd, d = pcall(G.getStackDepth)
      if okd and type(d) == "number" then depth = d end
    end
    local ok = pcall(fn, ...)
    if depth and G and G.pop and G.getStackDepth then
      local guard = 0
      while guard < 128 do
        local okd, d = pcall(G.getStackDepth)
        if not (okd and type(d) == "number") or d <= depth then break end
        pcall(G.pop)
        guard = guard + 1
      end
    end
    return ok
  end

  -- The BACK layer: everything that has to be BEHIND the creature -- the
  -- ground glow and the far half of the shard swarm.  battle_screen draws
  -- this before its sprite pass and E.draw after it.
  function E.drawBack(clip)
    local G = love and love.graphics
    if not (G and G.push) then return end
    part(drawGroundGlow, clip)
    part(drawShards, clip, true)
  end

  -- The FRONT layer: the near shards, the dome, the beams, the inner glow,
  -- the break and the flash -- everything that belongs over the creature.
  function E.draw(clip)
    local G = love and love.graphics
    if not (G and G.push) then return end
    part(drawShards, clip, false)
    part(drawShellGlow, clip)
    part(drawBeams, clip)
    part(drawBreak, clip)
    part(drawFlash, clip)
    part(drawSparks, clip)
  end

  mod.exports.battleSceneTeraAnim = E
  if mod.log then mod.log:info("g9_Battle_Scene: tera animation loaded") end
end
