-- g9-Battle-Scene -- the DYNAMAX / GIGANTAMAX animation.
--
-- WHAT THIS OWNS.  A once-per-battle, full-screen transformation sequence,
-- staged on the battle field around the Pokemon that is growing.  battle_forms
-- (the engine-side form-change mod) performs the ACTUAL change, and
-- battle_screen.lua defers that activation to this clip's reveal beat (see
-- that file's DYNAMAX block).  So everything here is costuming: it owns WHEN
-- the change is shown and what it looks like, never what it does.  The SIZE
-- ladder (x1 -> 1.05 -> 1.10 -> 1.20 -> 1.50, in phases) belongs to
-- g9-battle-sprites, which starts it the instant the change lands -- this clip
-- only has to hold the player's attention across that half-second reveal.
--
-- WHY IT IS ITS OWN FILE.  Like evolution_anim.lua it needs not one engine
-- call: battle_screen hands it a screen position and a sprite box and drives
-- it with step/draw, so the fengari harness in scratch/sim can replay it with
-- only love.graphics mocked.
--
-- WHAT IT IS INSPIRED BY, and what it is not.  The reference clip's language
-- is: the creature going to a solid BLACK SILHOUETTE, dark red and brighter
-- red energy GATHERING inward, and churning dark clouds -- so those three are
-- what this draws.  The clip's red orb held in front of the creature, and the
-- iridescent DNA orb that floats off at the end, are deliberately ABSENT: the
-- user asked for the silhouette/energy/cloud language only.
--
-- THE SEQUENCE, beat by beat (times in seconds from the clip's start):
--
--   0.00 - 0.95  GATHER     the field sinks into a deep maroon dim; ribbons of
--                            dark-red energy spiral INWARD from off-screen and
--                            sink into the mon, and a few embers rise.  The
--                            ribbons are dark maroon with a brighter red
--                            running down their middle -- "dark red and
--                            shinier red energy gathering".
--   0.30 - 1.05  DARKEN     the mon fades to a black silhouette (E.darken),
--                            which is what makes the clouds read against it.
--   0.78 - 1.34  GATHER     cumulus puffs build over and around the head,
--                            dark maroon at the back thickening to brighter
--                            red at the front.
--   1.24 - 1.34  FLASH IN   a deep red wash ramps up into the white window.
--   1.34 - 1.52  FLASH HOLD the screen is at its white PEAK.  REVEAL_T = 1.38
--                            sits inside this window, so the form change -- and
--                            the first phase of the size ladder -- happen on
--                            the same frame.  The whole flash is capped at
--                            FLASH_ALPHA (0.30): a white screen at 30% opacity
--                            rather than a solid one, so the sequence never
--                            flash-bangs the viewer.  The creature is held as a
--                            black silhouette under it, which is what keeps the
--                            form swap hidden at the lower opacity.
--   1.52 - 2.30  BURST      the cloud mass punches outward as a ring of puffs
--                            while the white falls away, and the silhouette
--                            releases back to full colour.
--   2.30 - 3.20  SETTLE     the burst thins to a slow drift of embers; by the
--                            end nothing of this clip is left on screen but
--                            the crown g9-battle-sprites bakes into the sheet.
--
-- The whole thing is drawn in the scene's DESIGN space (320x180, DS=3 to the
-- canvas), so a "pixel" here is the same 3x3 canvas block the rest of the
-- scene's art lands on.
--
-- NEVER FATAL.  Every entry point degrades to "draws nothing" on a missing
-- image, a nil field or a stub love.graphics; battle_screen.lua additionally
-- pcall's the whole draw.  A costume must never abort a turn.
return function(mod)
  local E = {}

  -- The timeline.  REVEAL_T is load-bearing: battle_screen performs the real
  -- activation (and the size ladder starts) the frame this clip reports
  -- `revealed`, which is inside the solid-white flash window.
  local REVEAL_T = 1.38
  local END_T = 3.10

  -- The flash's own beats.  FLASH_IN..FLASH_OUT bound the WHITE window the
  -- reveal sits inside; REVEAL_T is between them by construction, and the
  -- harness asserts exactly that.
  local FLASH_START, FLASH_IN, FLASH_OUT, FLASH_END = 1.06, 1.34, 1.52, 1.95

  -- How opaque the full-screen flash may get at its peak.  It used to reach a
  -- SOLID white (1.0), a flash-bang on a large screen; it is fixed at 0.30
  -- (70% transparent) so the transformation is easy on the eyes.  The whole
  -- curve -- the crimson wash in, the white window, the fade -- scales by
  -- this, so the beat is dimmer throughout, never just at its peak.
  local FLASH_ALPHA = 0.30

  E.REVEAL_T = REVEAL_T
  E.END_T = END_T
  E.FLASH_START = FLASH_START
  E.FLASH_IN = FLASH_IN
  E.FLASH_OUT = FLASH_OUT
  E.FLASH_END = FLASH_END
  E.FLASH_ALPHA = FLASH_ALPHA

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

  -- A tiny deterministic LCG, so the ribbon/ember field is stable frame to
  -- frame and the harness replays exactly what the game draws.
  local function rng(seed)
    local s = (seed or 1) % 2147483648
    if s <= 0 then s = s + 2147483647 end
    return function()
      s = (s * 1103515245 + 12345) % 2147483648
      return s / 2147483648
    end
  end

  ----------------------------------------------------------------------
  -- the cloud puff
  ----------------------------------------------------------------------
  -- One cumulus puff, built from four overlapping lobes so it reads as a
  -- billow rather than a dot.  `bright` runs the maroon-to-red ramp: the
  -- cloud's far side is drawn at 0 (dark maroon) and its near side at 1
  -- (brighter, shinier red), which is how the clip's cloud has depth even
  -- before g9-battle-sprites bakes the real crown.
  local function lobe(G, x, y, r, cr, cg, cb, a)
    G.setColor(cr * 0.42, cg * 0.42, cb * 0.42, a * 0.85)
    G.circle("fill", x, y + r * 0.12, r * 1.04)
    G.setColor(cr, cg, cb, a)
    G.circle("fill", x, y, r)
    G.setColor(lerp(cr, 1, 0.40), lerp(cg, 1, 0.30), lerp(cb, 1, 0.30), a * 0.50)
    G.circle("fill", x - r * 0.24, y - r * 0.28, r * 0.54)
  end
  local function puff(G, x, y, r, a, bright)
    if r < 0.6 or a <= 0.01 then return end
    local cr, cg, cb = 0.55 + bright * 0.32, 0.11 + bright * 0.10, 0.15 + bright * 0.10
    lobe(G, x - r * 0.58, y + r * 0.14, r * 0.68, cr, cg, cb, a)
    lobe(G, x + r * 0.58, y + r * 0.14, r * 0.64, cr, cg, cb, a)
    lobe(G, x, y - r * 0.20, r * 0.86, cr, cg, cb, a)
    lobe(G, x, y - r * 0.56, r * 0.50, cr, cg, cb, a)
  end

  ----------------------------------------------------------------------
  -- clip construction
  ----------------------------------------------------------------------
  -- opts: x (the sprite anchor's centre-x), cx (optional: where the show is
  --       drawn -- battle_screen passes the centre of the pixels the sprite
  --       really paints, see that file's artShift), top, feet, w, h, side,
  --       seed, vw/vh (canvas size, default 320x180).
  local function newClip(opts)
    opts = opts or {}
    local rnd = rng(opts.seed or 20261010)
    local clip = {
      t = 0, done = false, revealed = false, onReveal = nil,
      x = opts.x or 160, top = opts.top or 60, feet = opts.feet or 120,
      w = opts.w or 48, h = opts.h or 48,
      side = opts.side or "player",
      vw = opts.vw or 320, vh = opts.vh or 180,
      rnd = rnd, ribbons = {}, embers = {}, puffs = {},
    }
    -- `x` is the anchor the sprite is drawn on; `cx` is where the show is
    -- drawn.  They differ only when the art sits off-centre in its own frame.
    clip.cx = opts.cx or clip.x
    -- The mass of the show sits on the creature's upper half -- the head and
    -- shoulders, which is where the clip's clouds gather and where the crown
    -- will be.
    clip.hx = clip.cx
    clip.hy = clip.top + clip.h * 0.34
    -- Radii are ratios of the DRAWN sprite box, so a small mon and a hulking
    -- one get a proportionally sized show.
    clip.gatherR = clamp(math.max(clip.w, clip.h) * 0.95, 26, 84)
    clip.cloudR = clamp(math.max(clip.w, clip.h) * 0.42, 12, 40)
    -- The cloud ring's own radius: everything gathers OUTSIDE this, so the
    -- creature is never buried under its own transformation cloud.
    clip.cloudMin = 0.46 * math.sqrt(clip.w * clip.w + clip.h * clip.h)
    -- Ribbons: they all start off-screen and converge on the creature.
    for i = 1, 22 do
      local a = (i / 22) * 2 * math.pi + rnd() * 0.35
      clip.ribbons[i] = {
        a = a,
        a2 = a + (rnd() - 0.5) * 1.6,
        r0 = clip.gatherR * (1.05 + rnd() * 0.75),
        d = 0.45 + rnd() * 0.55,
        sp = 0.55 + rnd() * 0.65,
        off = rnd(),
        wdt = 0.45 + rnd() * 0.75,
        bright = rnd(),
      }
    end
    for i = 1, 26 do
      clip.embers[i] = { a = rnd() * 6.283, r = rnd(),
                         sp = 0.45 + rnd() * 0.85, ph = rnd() * 6.283,
                         sz = 0.8 + rnd() * 1.9 }
    end
    -- The cloud mass: puffs laid out around the head on a shallow ring, with
    -- a few further out and lower.  Frozen per clip so the churn is motion,
    -- never reshuffling.
    for i = 1, 16 do
      local a = (i / 16) * 2 * math.pi + (rnd() - 0.5) * 0.30
      local back = math.sin(a) < 0
      clip.puffs[i] = {
        a = a,
        back = back,
        r = clip.cloudR * (0.62 + rnd() * 0.60),
        d = 0.55 + rnd() * 0.55,
        ph = rnd() * 6.283,
        rise = 0.25 + rnd() * 0.75,
      }
    end
    return clip
  end
  E.new = newClip

  ----------------------------------------------------------------------
  -- driving
  ----------------------------------------------------------------------
  -- One tick.  `hold` freezes the clock (raised by battle_screen while the
  -- screen is held solid white waiting for the new form's art); the reveal
  -- beat SNAPS the clock to REVEAL_T so the white the change hides under is
  -- the same on every machine.
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

  -- 0..1: how BLACK the sprite should be drawn right now (battle_screen
  -- multiplies the sprite's colour by 1 - this).  1 is a solid silhouette.
  -- It is already at 1 before the flash, so the swap happens on a shape with
  -- no colour of its own, and it is fully released before the clip ends.
  function E.darken(clip)
    local t = clip.t
    if t < 0.30 then return 0 end
    if t < 1.05 then return (t - 0.30) / 0.75 end
    if t < FLASH_OUT then return 1 end
    if t < 2.30 then return 1 - (t - FLASH_OUT) / (2.30 - FLASH_OUT) end
    return 0
  end

  -- 0..FLASH_ALPHA: the full-screen flash's opacity.  It peaks across
  -- FLASH_IN..FLASH_OUT -- the window the reveal sits inside -- with a deep-red
  -- ramp in (the clip's own crimson wash) and a linear fade out, and the whole
  -- curve is scaled by FLASH_ALPHA so the peak is a 30%-opaque white rather
  -- than a solid one.  Published so the harness can assert the reveal really
  -- is under the flash window.
  function E.flashAlpha(clip)
    local t = clip.t
    if t < FLASH_START or t >= FLASH_END then return 0 end
    local a
    if t < FLASH_IN then
      local u = (t - FLASH_START) / (FLASH_IN - FLASH_START)
      -- smoothstep, so the crimson wash builds evenly out of the dark before
      -- the white window rather than jumping
      a = u * u * (3 - 2 * u)
    elseif t <= FLASH_OUT then
      a = 1
    else
      a = 1 - (t - FLASH_OUT) / (FLASH_END - FLASH_OUT)
    end
    return a * FLASH_ALPHA
  end

  -- The flash's COLOUR: deep crimson on the way in (the clip's transformation
  -- red), white across the solid window, and crimson again as it falls away.
  function E.flashColor(clip)
    local t = clip.t
    if t < FLASH_IN then return 0.62, 0.05, 0.08 end
    if t < FLASH_OUT then return 1, 1, 1 end
    return 0.85, 0.30, 0.28
  end

  ----------------------------------------------------------------------
  -- the pieces
  ----------------------------------------------------------------------
  -- THE FURNACE: the light the silhouette is seen AGAINST.  The reference's
  -- dark shape is only legible because bright red light is pouring out from
  -- behind it, so this is drawn in the clip's BACK layer -- before the sprite
  -- pass -- where it can fill the whole area the creature stands in.  The
  -- creature is then blitted on top, and it reads as a black shape inside a
  -- furnace rather than as a black shape on a dark field.
  --
  -- Drawn from the outside in, each disc over the last, so the centre is the
  -- brightest: dark maroon at the rim through red to a near-white-hot core.
  local function drawFurnace(clip)
    local t = clip.t
    local k = clamp((t - 0.35) / 0.60, 0, 1) * (1 - clamp((t - 1.62) / 0.45, 0, 1))
    if k <= 0.01 then return end
    local G = love.graphics
    local R = clip.gatherR * 1.40
    G.push("all")
    G.setBlendMode("alpha")
    local N = 14
    for i = N, 1, -1 do
      local f = i / N                                  -- 1 = rim, 1/N = core
      local r = R * (0.16 + 0.84 * f)
      local cr = lerp(0.98, 0.30, f)
      local cg = lerp(0.30, 0.02, f)
      local cb = lerp(0.22, 0.04, f)
      G.setColor(cr, cg, cb, 0.30 * (1 - 0.40 * f) * k)
      G.circle("fill", clip.cx, clip.hy, r)
    end
    G.pop()
  end

  -- The field sinking into the clip's dark maroon.  Deepest just before the
  -- flash, gone by the time the burst has cleared.
  local function drawDim(clip)
    local t = clip.t
    local a = clamp((t - 0.15) / 0.70, 0, 1) * (1 - clamp((t - 1.95) / 0.55, 0, 1))
    a = a * 0.52
    if a <= 0 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("alpha")
    G.setColor(0.09, 0.005, 0.02, a)
    G.rectangle("fill", 0, 0, clip.vw, clip.vh)
    G.pop()
  end

  -- The energy gathering: ribbons that start off-screen and spiral INWARD,
  -- sinking into the creature.  Each is drawn as a trail of small discs along
  -- its own spiral -- a dark maroon skirt with a brighter red core running
  -- down the middle, so the strand reads as a glowing thread rather than a
  -- flat line, and the whole field reads as dark red with shinier red.
  local function drawRibbons(clip)
    local t = clip.t
    local k = clamp((t - 0.10) / 0.55, 0, 1) * (1 - clamp((t - 1.60) / 0.55, 0, 1))
    if k <= 0 then return end
    local G = love.graphics
    local cx, cy = clip.cx, clip.hy
    local R0 = clip.gatherR
    -- The strands never reach the creature: they wind around it, so the black
    -- silhouette they are pouring energy into stays a readable shape.  (An
    -- energy that runs THROUGH the mon just paints over the very thing the
    -- shot is about.)
    local hole = 0.5 * math.sqrt(clip.w * clip.w + clip.h * clip.h)
    G.push("all")
    G.setBlendMode("add")
    local SEG = 34
    for _, rb in ipairs(clip.ribbons) do
      -- progress 0 = at the rim, 1 = at the creature; each ribbon is offset in
      -- time so they do not all arrive at once.
      local prog = ((t * rb.sp + rb.off) % 1)
      local fade = math.sin(prog * math.pi)              -- in then out
      if fade > 0.01 then
        for s = 0, SEG - 1 do
          local u = s / SEG
          -- A long comet tail (0.6 of the inward sweep), so the strand reads as
          -- one continuous ribbon of energy rather than a scatter of dots.
          local f = prog * 1.60 - u * 0.60
          if f > 0 and f < 1 then
            -- radius shrinks inward, and the angle winds as it comes: that is
            -- what makes it a spiral rather than a straight spoke.
            local rad = R0 * (1 - f) * (0.45 + 0.55 * rb.d)
            if rad < hole then rad = hole + (rad / math.max(0.001, hole)) * 3 end
            local ang = lerp(rb.a, rb.a2, f) + f * 3.1
            local x = cx + math.cos(ang) * rad
            local y = cy + math.sin(ang) * rad * 0.72
            local tail = (1 - u) * fade
            local w = rb.wdt * (0.6 + 0.9 * (1 - f))
            local bright = 0.25 + 0.75 * rb.bright
            -- dark maroon skirt
            G.setColor(0.34 + 0.20 * bright, 0.03, 0.06, 0.34 * tail * k * w)
            G.circle("fill", x, y, 1.9 * w)
            -- shinier red core
            G.setColor(lerp(0.88, 1.0, bright), 0.10 + 0.26 * bright,
              0.10 + 0.22 * bright, 0.55 * tail * k * w)
            G.circle("fill", x, y, 0.95 * w)
          end
        end
      end
    end
    -- the convergence: a small rising core of red where the strands sink in.
    -- Deliberately SMALL: the creature has to stay a readable black silhouette
    -- until the flash, so this is a knot at the chest, not a screen-filling
    -- blob.
    local core = clamp((t - 0.35) / 0.85, 0, 1) * (1 - clamp((t - 1.42) / 0.30, 0, 1))
    for i = 6, 1, -1 do
      local f = i / 6
      G.setColor(0.55 + 0.45 * (1 - f), 0.06, 0.09, 0.10 * core * f)
      G.circle("fill", cx, cy, clip.cloudR * (0.35 + 0.75 * f) * (0.5 + 0.5 * core))
    end
    G.pop()
  end

  -- The embers: dark-red sparks drifting UP past the creature, brightest at
  -- the flash.
  local function drawEmbers(clip)
    local t = clip.t
    local k = clamp((t - 0.25) / 0.50, 0, 1) * (1 - clamp((t - 2.45) / 0.60, 0, 1))
    if k <= 0 then return end
    local G = love.graphics
    G.push("all")
    G.setBlendMode("add")
    for _, e in ipairs(clip.embers) do
      local prog = (e.r + t * e.sp * 0.5) % 1
      local y = clip.feet - prog * clip.h * 1.7
      local x = clip.cx + math.cos(e.a + t * 0.7 + prog * 2.4) * clip.w * 0.62
      local tw = 0.6 + 0.4 * math.sin(t * 9 * e.sp + e.ph)
      local a = (1 - prog) * k * tw
      G.setColor(0.95, 0.16, 0.14, 0.42 * a)
      G.circle("fill", x, y, e.sz)
      G.setColor(1.0, 0.62, 0.45, 0.34 * a)
      G.circle("fill", x, y, e.sz * 0.45)
    end
    G.pop()
  end

  -- The gathering cloud mass.  Two passes, back then front, so the dark
  -- maroon puffs sit behind the brighter ones -- the clip's own depth cue.
  -- `growT` swells them in; `burst` pushes them OUT once the flash has gone.
  local function drawClouds(clip, wantBack, growT, spread, burst, alpha)
    if alpha <= 0.01 then return end
    local G = love.graphics
    local t = clip.t
    G.push("all")
    G.setBlendMode("alpha")
    for _, p in ipairs(clip.puffs) do
      if p.back == wantBack then
        local ang = p.a + t * 0.22
        -- The ring's centre is pushed out past the creature, so even the
        -- gathered (pre-flash) cloud rings AROUND it rather than sitting on
        -- its face; the burst then throws it further out and upward.
        local rad = clip.cloudMin + clip.cloudR * (0.55 + 1.25 * p.d) * spread
        local sway = math.sin(t * 1.6 + p.ph) * clip.cloudR * 0.16
        local x = clip.cx + math.cos(ang) * rad
        local y = clip.hy + math.sin(ang) * rad * 0.52 - clip.h * 0.10 * p.rise + sway
        local gr = 1 + (growT - 1) * (0.4 + 0.6 * p.d)
        if burst > 0 then
          -- out and slightly up, the shape the clip's cloud takes as it
          -- punches clear of the creature
          x = x + (x - clip.cx) * burst * 0.85
          y = y + (y - clip.hy) * burst * 0.55 - clip.h * 0.14 * burst
          gr = gr * (1 + burst * 0.35)
        end
        local bright = p.back and 0.10 or (0.55 + 0.45 * (0.5 + 0.5 * math.sin(p.ph)))
        local a = alpha * (p.back and 0.72 or 0.92)
        puff(G, x, y, p.r * gr, a, bright)
      end
    end
    G.pop()
  end

  -- The cloud mass's shared schedule, so both layers agree: how far it has
  -- gathered, how far it has burst, how far the ring is spread, and how
  -- opaque it is right now.
  local function cloudParams(clip)
    local t = clip.t
    local pre = 1 - clamp((t - FLASH_OUT) / 0.25, 0, 1)
    local gather = clamp((t - 0.78) / 0.52, 0, 1)
    local burst = clamp((t - FLASH_OUT) / 0.42, 0, 1)
    local spread = 0.50 + (1 - pre) * 0.50 + burst * 0.85
    local a = gather * (0.42 + 0.50 * (1 - pre)) * (1 - clamp((t - 2.30) / 0.70, 0, 1))
    return 0.55 + 0.45 * easeIn(gather), spread, burst, a
  end

  -- The shockwave: three expanding rings plus a haze disc, in the transformation
  -- reds rather than the mega clip's whites.
  local function drawShock(clip)
    local age = clip.t - FLASH_OUT
    local life = 0.85
    if age < 0 or age > life then return end
    local f = age / life
    local G = love.graphics
    local base = clip.gatherR * 0.9
    G.push("all")
    G.setBlendMode("add")
    for i = 1, 3 do
      local fa = clamp((age - (i - 1) * 0.06) / life, 0, 1)
      if fa > 0 and fa < 1 then
        local r = base * (0.20 + 1.45 * easeOut(fa))
        local a = (1 - fa) * (1 - fa) * 0.60
        G.setColor(0.95, 0.22, 0.20, a)
        G.setLineWidth(3.0 * (1 - fa) + 0.5)
        G.circle("line", clip.cx, clip.hy, r)
        G.setColor(1.0, 0.72, 0.62, a * 0.75)
        G.setLineWidth(1.1 * (1 - fa) + 0.3)
        G.circle("line", clip.cx, clip.hy, math.max(0.6, r - 1.6))
      end
    end
    for i = 1, 6 do
      G.setColor(0.62, 0.08, 0.10, (1 - f) * 0.055 * (1 - i / 7))
      G.circle("fill", clip.cx, clip.hy, base * (0.3 + 0.95 * easeOut(f)) * (i / 6))
    end
    G.pop()
  end

  local function drawFlash(clip)
    local a = E.flashAlpha(clip)
    if a <= 0 then return end
    local G = love.graphics
    local rr, gg, bb = E.flashColor(clip)
    G.push("all")
    G.setBlendMode("alpha")
    G.setColor(rr, gg, bb, a)
    G.rectangle("fill", 0, 0, clip.vw, clip.vh)
    G.pop()
  end

  ----------------------------------------------------------------------
  -- draw
  ----------------------------------------------------------------------
  -- The BACK layer: everything that has to be BEHIND the creature, i.e. the
  -- dim and the furnace glow.  battle_screen draws this before its sprite pass
  -- and E.draw after it (see that file's DYNAMAX block) -- the split exists
  -- purely so the light can be behind the mon, which the clip cannot do once
  -- the sprites are already on the screen.
  function E.drawBack(clip)
    local G = love and love.graphics
    if not (G and G.push) then return end
    drawDim(clip)
    drawFurnace(clip)
    local growT, spread, burst, cloudA = cloudParams(clip)
    if cloudA > 0.01 then drawClouds(clip, true, growT, spread, burst, cloudA) end
  end

  -- The FRONT layer: the energy, the near half of the cloud, the embers and
  -- the flash -- everything that belongs over the creature.
  function E.draw(clip)
    local G = love and love.graphics
    if not (G and G.push) then return end
    local t = clip.t
    if t < 1.60 then drawRibbons(clip) end
    local growT, spread, burst, cloudA = cloudParams(clip)
    if cloudA > 0.01 then drawClouds(clip, false, growT, spread, burst, cloudA) end
    if t < 3.06 then drawEmbers(clip) end
    drawFlash(clip)
    if t >= FLASH_OUT then drawShock(clip) end
  end

  mod.exports.battleSceneDynamaxAnim = E
  if mod.log then mod.log:info("g9_Battle_Scene: dynamax animation loaded") end
end
