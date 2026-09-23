-- fantasy_combat.lua -- the FANTASY COMBAT modernized GUI.
--
-- One on/off option (options.lua's FANTASY COMBAT, read through
-- F.enabled()) swaps the bottom band this scene has always drawn -- the
-- native tile-font F (message/move) box beside the E (FIGHT/BAG/PKMN/RUN)
-- menu, permanently framed -- for a translucent panel GUI in the style of
-- FINAL FANTASY XII: THE ZODIAC AGE, the same look g9-gui gives the
-- overworld menus.  Nothing here touches the engine's tile Font or its
-- draw order: battle_screen.lua still owns what is on screen and WHEN,
-- and this file only draws the surfaces that replace F/E plus the two
-- field extras (the move readout above the field and the target arrow).
--
-- WHAT THE OPTION CHANGES
--
--   * The old F space -- the band's wide left half -- becomes the ALLY
--     PARTY STATUS list: FOUR fixed row slots, each its own small panel,
--     top row = party placement 1, then 2, 3, 4.  A slot draws NOTHING at
--     all unless a Pokemon is actually standing in it -- no placeholder,
--     no hole-filling: an absent slot simply leaves its band of the list
--     empty, and the rows below it do NOT slide up (the slot positions
--     are fixed, so the list never re-flows).  Each present row is
--     `name`, a dim HP label, an HP bar carrying current/max over it,
--     `Lv N`, a dim EXP label, a (shorter) exp bar with no number, and
--     the major status word (Paralyzed, Burned, ...).  The ally sprites
--     lose their over-the-head HP/exp readout entirely -- the party list
--     now carries that.
--   * Box E (the action box) keeps its own original place -- the band's
--     right, the native 12-tile column -- and is now the ONLY panel: every
--     menu (FIGHT/BAG/PKMN/RUN list or grid, the move list, the FORMS
--     picker, a prompt's question and choices) AND every message the
--     battle sends to the screen are drawn there.  Neither F nor E is a
--     permanent frame any more: the panel appears only while there is
--     something to put in it.  Long narration wraps inside E at the
--     largest of the panel's faces that fits, so no message can overflow
--     the panel's own border.
--   * The move readout (PP cur/max, power, accuracy, effect) floats over
--     the top-left of the field while a move is being chosen.
--   * The target-selection arrow becomes a modern pointer (and the swap
--     cue's owner keeps its hollow-outline form).
--   * Battle messages are set in the panel face instead of the tile font,
--     and the engine's `{PROMPT}`/`{DONE}` control tokens are stripped
--     before they are drawn (see F.sanitize) -- the native drawWrapped
--     does the same for the tile-font path.
--
-- CHROME.  The look is deliberately the g9-gui one, primitive for
-- primitive: a translucent dark-navy fill with a 1px steel-blue border and
-- L-shaped corner brackets, a slim header band with an all-caps accent
-- title over a divider rule, selection read as a lit row bar plus the
-- double-chevron cursor, and bars drawn as a dark rounded track with a
-- lighter fill carrying its own top highlight.  Labels are all-caps and
-- dim; values are the brighter ink (gold for the numbers the reference
-- weights gold).  The one deliberate departure the option asks for is the
-- panel fill: g9-gui's own panels sit near 88% opaque, this GUI runs them
-- at ~62% so the field reads through the band.
--
-- GEOMETRY.  battle_screen.lua authors the field in a 320x180 DESIGN space
-- and the scene draws that through one scale(DS) transform onto its
-- 960x540 canvas (DS=3).  Everything below is written in CANVAS pixels
-- (the same space g9-gui's own screens draw in, so the panel metrics and
-- the font sizes read the same way) and F.draw scales by 1/DS for the
-- duration of the draw, which lands canvas pixels on the canvas 1:1 and
-- keeps text at canvas resolution instead of rendering glyphs at 1/3 size
-- and blowing them back up.  BAND/PARTY/EBOX below are the NATIVE box
-- rects: design y 128..180 is canvas y 384..540, and the 28/12-tile F/E
-- split is canvas x 0..672 / 672..960.
--
-- FONTS.  Saira (SIL OFL 1.1 -- assets/fonts/OFL.txt) is the face g9-gui
-- picked to stand in for the Zodiac Age menu type; this mod now ships the
-- same two static cuts (Regular + SemiBold) under assets/fonts/ so the two
-- mods look like one product without either depending on the other.  The
-- files are read through the mod's own sandboxed reader exactly the way
-- g9-gui's ui/theme.lua reads its own; if they cannot be opened the module
-- still works, falling back to love's built-in font, so a broken/missing
-- asset can never take a battle down.
return function(mod)
  local F = {}
  mod.exports.fantasyCombat = F

  local DS_FALLBACK = 3

  -- ------------------------------------------------------------------ options

  -- The same defensive read every sibling uses: pcall'd, string-only, with
  -- a fallback so a harness (or a disabled mod) sees the feature off.
  function F.enabled()
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(function() return options:get("fantasy_combat") end)
      if ok and type(value) == "string" then return value == "on" end
    end
    return false
  end

  -- WHITE ROW (options.lua's own row): when on, each party row's own
  -- BACKGROUND panel is drawn as a translucent white panel (white at 40%
  -- opacity) instead of the usual dark surface, so the field reads through
  -- the row.  Only the row's background changes -- the name, HP bar, level,
  -- exp bar and status tag inside it all keep their own colours.  Read per
  -- draw, defensively, so a harness (or a disabled mod) keeps the dark row.
  function F.whiteRow()
    local options = mod and mod.options
    if options and type(options.get) == "function" then
      local ok, value = pcall(function() return options:get("white_row") end)
      if ok and type(value) == "string" then return value == "on" end
    end
    return false
  end

  -- ------------------------------------------------------------------ palette

  -- The g9-gui palette, unchanged, so a screen from either mod reads as the
  -- same design.  The panel fills are the one deliberate departure: the
  -- option calls for a ~60% translucent surface (g9-gui's own panels sit at
  -- 88%), so panel/panelDeep/panelLit run a little lighter here.  `row` and
  -- `rowLit` are g9-gui's own roster-row colours, used for the menu
  -- selection bar and for highlighting the row of the mon being commanded.
  local COL = {
    void      = { 0.043, 0.055, 0.086, 1.00 },
    voidDeep  = { 0.016, 0.022, 0.038, 1.00 },
    panel     = { 0.070, 0.092, 0.133, 0.62 },
    panelDeep = { 0.036, 0.050, 0.078, 0.70 },
    panelLit  = { 0.125, 0.165, 0.240, 0.66 },
    row       = { 0.115, 0.150, 0.220, 0.52 },
    rowLit    = { 0.220, 0.330, 0.460, 0.62 },
    border    = { 0.290, 0.380, 0.520, 0.75 },
    borderLit = { 0.520, 0.690, 0.900, 0.95 },
    shine     = { 1.000, 1.000, 1.000, 0.09 },
    ink       = { 0.930, 0.950, 0.990, 1.00 },
    inkDim    = { 0.620, 0.680, 0.790, 1.00 },
    inkFaint  = { 0.360, 0.420, 0.530, 1.00 },
    accent    = { 0.470, 0.800, 1.000, 1.00 },
    accentDim = { 0.210, 0.400, 0.560, 1.00 },
    gold      = { 0.960, 0.800, 0.360, 1.00 },
    goldDim   = { 0.480, 0.400, 0.200, 1.00 },
    -- The HP bar's three state colours (v4.0.8).  The old trio were bright
    -- pastels (a neon green / yellow / red stoplight); these are the same
    -- three states carried at ONE shared depth, anchored on the user's
    -- #00A36D -- the yellow and red are darkened to that same saturation and
    -- value, so the bar reads as a single muted family instead of a bright
    -- one, without losing the state the colour is there to show.
    good      = { 0.000, 0.639, 0.427, 1.00 },  -- #00A36D
    warn      = { 0.639, 0.561, 0.000, 1.00 },  -- #A38F00
    bad       = { 0.639, 0.000, 0.000, 1.00 },  -- #A30000
    shadow    = { 0.000, 0.000, 0.000, 0.55 },
    white     = { 1.000, 1.000, 1.000, 1.00 },
    -- The WHITE ROW option's fill: white, 40% transparent (60% opaque), in
    -- place of a party row's usual dark background panel.
    whiteRow  = { 1.000, 1.000, 1.000, 0.60 },
  }
  F.col = COL

  -- ------------------------------------------------------------------ fonts

  local FONT_REGULAR = "assets/fonts/Saira-Regular.ttf"
  local FONT_BOLD = "assets/fonts/Saira-SemiBold.ttf"
  -- The g9-gui size ladder (body 22 / small 13 / tiny 10) plus the two
  -- rungs this GUI needs and g9-gui's menu-only screens do not: `big` (18)
  -- for the party-row name and the readout's move name, and `mid` (15) for
  -- the message body and the readout's values.  Everything here is drawn in
  -- canvas pixels, so these are the same sizes g9-gui uses for the same
  -- roles.
  local SIZE = { body = 22, big = 18, mid = 15, small = 13, tiny = 11 }

  local fonts

  local function toFileData(bytes, name)
    local fn = (love.data and love.data.newFileData)
      or (love.filesystem and love.filesystem.newFileData)
    if not fn then return nil end
    local ok, fd = pcall(fn, bytes, name)
    if not ok then ok, fd = pcall(fn, bytes) end
    return (ok and fd) or nil
  end

  -- Read one of this mod's own assets through the sandboxed reader first,
  -- then through mod.assets' path helper (the two routes the mod is
  -- actually promised), then give up -- the caller falls back to love's
  -- built-in face.
  local function buildFont(rel, size)
    local name = tostring(rel or ""):match("[^/\\]+$") or "font.ttf"
    local bytes
    if mod and type(mod.read) == "function" then
      local ok, data = pcall(mod.read, mod, rel)
      if ok and type(data) == "string" and #data > 0 then bytes = data end
    end
    if bytes then
      local fd = toFileData(bytes, name)
      if fd then
        local ok, font = pcall(love.graphics.newFont, fd, size)
        if ok and font and font.getWidth then return font end
      end
    end
    if mod and mod.assets and type(mod.assets.path) == "function" then
      local ok, path = pcall(mod.assets.path, mod.assets, rel)
      if ok and type(path) == "string" then
        local ok2, font = pcall(love.graphics.newFont, path, size)
        if ok2 and font and font.getWidth then return font end
      end
    end
    return nil
  end

  -- Built once and kept: a battle allocates a Font per call otherwise.
  -- `game` is unused for now (the Saira bake is generation-independent) but
  -- kept in the signature so a later per-game tweak has somewhere to land.
  function F.fonts()
    if fonts then return fonts end
    local function face(rel, size)
      return buildFont(rel, size) or buildFont(FONT_REGULAR, size)
        or love.graphics.newFont(size)
    end
    fonts = {
      body = face(FONT_REGULAR, SIZE.body),
      bold = face(FONT_BOLD, SIZE.body),
      big = face(FONT_REGULAR, SIZE.big),
      bigBold = face(FONT_BOLD, SIZE.big),
      mid = face(FONT_REGULAR, SIZE.mid),
      midBold = face(FONT_BOLD, SIZE.mid),
      small = face(FONT_REGULAR, SIZE.small),
      smallBold = face(FONT_BOLD, SIZE.small),
      tiny = face(FONT_REGULAR, SIZE.tiny),
      tinyBold = face(FONT_BOLD, SIZE.tiny),
    }
    return fonts
  end

  -- A font's line box in canvas pixels.  love Font:getHeight is the real
  -- answer; the arithmetic fallback only matters for a stub face in a test
  -- harness, which is also why it reads a plain `.size` field.
  local function lineH(font)
    if font and type(font.getHeight) == "function" then
      local ok, h = pcall(font.getHeight, font)
      if ok and type(h) == "number" and h > 0 then return h end
    end
    if font and type(font.size) == "number" then return font.size end
    return SIZE.mid
  end

  -- ------------------------------------------------------------------ text utils

  -- Battle text coming out of the engine/ROM keeps trailing {PROMPT}/{DONE}
  -- control tokens (core/RomText.lua preserves them; render/TextBox.lua
  -- strips them; the tile-font path is drawn through Font directly, so this
  -- scene's own drawWrapped strips them by hand).  The fantasy panels print
  -- the engine's strings too, so they need exactly the same scrub: a
  -- flinched mon read "... flinched!{PROMPT}" before this existed.  Token
  -- (any case), then any truly standalone "prompt" word, then collapse the
  -- whitespace the removals leave behind.
  function F.sanitize(text)
    text = tostring(text or "")
    text = text:gsub("{%s*[Pp][Rr][Oo][Mm][Pp][Tt]%s*}", " ")
    text = text:gsub("{%s*[Dd][Oo][Nn][Ee]%s*}", " ")
    text = text:gsub("%f[%a][Pp][Rr][Oo][Mm][Pp][Tt]%f[%A]", " ")
    text = text:gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
  end

  local ELLIPSIS = "\xe2\x80\xa6"

  -- Truncate to a pixel budget through the real font, never cutting a UTF-8
  -- sequence in half (love's print rejects malformed UTF-8).  Used for the
  -- party row's name column, where a long species name must not run into
  -- the HP label beside it.
  local function fit(str, font, maxw)
    str = tostring(str or "")
    if maxw <= 0 then return "" end
    if font:getWidth(str) <= maxw then return str end
    local budget = maxw - font:getWidth(ELLIPSIS)
    local lo, hi = 0, #str
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if font:getWidth(str:sub(1, mid)) <= budget then lo = mid else hi = mid - 1 end
    end
    while lo > 0 do
      local b = str:byte(lo + 1)
      if b and b >= 0x80 and b < 0xC0 then lo = lo - 1 else break end
    end
    if lo <= 0 then return ELLIPSIS end
    return str:sub(1, lo) .. ELLIPSIS
  end

  -- ------------------------------------------------------------------ primitives

  local function set(c, a)
    if not c then love.graphics.setColor(1, 1, 1, 1) return end
    love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
  end
  F.set = set

  -- Rounded rects are LOVE 11 only: try the rounded call, fall back to a
  -- square one so an older build degrades instead of erroring.
  local function rect(mode, x, y, w, h, r)
    w = w < 0 and 0 or w
    h = h < 0 and 0 or h
    if r and r > 0 then
      local ok = pcall(love.graphics.rectangle, mode, x, y, w, h, r, r)
      if ok then return end
    end
    love.graphics.rectangle(mode, x, y, w, h)
  end
  F.rect = rect

  -- Corner brackets: g9-gui's own frame embellishment (Theme.brackets), the
  -- single detail that reads "this is a Zodiac Age menu" at a glance.  Eight
  -- 1px L arms, `len` long, inset from each corner.
  local function brackets(x, y, w, h, len, color)
    set(color or COL.accentDim)
    local function arm(px, py, bw, bh) rect("fill", px, py, bw, bh, 0) end
    arm(x, y, len, 1) arm(x, y, 1, len)
    arm(x + w - len, y, len, 1) arm(x + w - 1, y, 1, len)
    arm(x, y + h - 1, len, 1) arm(x, y + h - len, 1, len)
    arm(x + w - len, y + h - 1, len, 1) arm(x + w - 1, y + h - len, 1, len)
  end
  F.brackets = brackets

  -- The panel: drop shadow, translucent fill, 1px border, a 1px top shine
  -- and the corner brackets.  opts = { color, border, radius, shadow,
  -- highlight, highlightColor, brackets (len or nil), bracketColor }.
  local function panel(x, y, w, h, opts)
    opts = opts or {}
    local r = opts.radius or 5
    local sh = opts.shadow
    if sh and sh > 0 then
      set(COL.shadow)
      rect("fill", x + sh, y + sh, w, h, r)
    end
    set(opts.color or COL.panel)
    rect("fill", x, y, w, h, r)
    set(opts.border or COL.border)
    rect("line", x + 0.5, y + 0.5, w - 1, h - 1, math.max(0, r - 1))
    if opts.highlight ~= false then
      set(opts.highlightColor or COL.shine)
      rect("fill", x + 5, y + 1, math.max(0, w - 10), 1, 0)
    end
    if opts.brackets then
      local len = type(opts.brackets) == "number" and opts.brackets or 10
      brackets(x, y, w, h, len, opts.bracketColor)
    end
  end
  F.panel = panel

  -- A bar: dark rounded track, optional lit fill, optional border.  The fill
  -- gets its own 1px top highlight, which is what stops it reading as a
  -- flat rectangle.  frac 0..1.
  local function bar(x, y, w, h, frac, color, opts)
    opts = opts or {}
    frac = frac or 0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local r = opts.radius or math.floor(h * 0.5)
    set(opts.bg or COL.panelDeep)
    rect("fill", x, y, w, h, r)
    if frac > 0 then
      local fw = math.max(1, w * frac)
      set(color or COL.good)
      rect("fill", x, y, fw, h, r)
      if h >= 8 then
        set(opts.shine or COL.shine)
        rect("fill", x + 2, y + 1, math.max(1, fw - 4), 1, 0)
      end
    end
    set(opts.border or COL.border)
    rect("line", x + 0.5, y + 0.5, w - 1, h - 1, math.max(0, r - 1))
  end
  F.bar = bar

  -- Text, in canvas pixels, with `y` the top of the line (not an ink
  -- baseline) -- simpler than g9-gui's ink-anchored helper and safe here
  -- because every row in this file is placed with the room it needs.
  -- align: nil/"left" | "right" | "center" -- x is then the right edge or
  -- the centre.  `shadow` (a colour) lays a 1px dark offset copy under the
  -- ink, which is what keeps a number legible where it sits ON a lit bar.
  -- Returns the drawn width.
  local function text(str, x, y, font, align, color, shadow)
    str = F.sanitize(str)
    font = font or F.fonts().body
    local w = font:getWidth(str)
    local dx = x
    if align == "right" then dx = x - w
    elseif align == "center" then dx = x - w * 0.5 end
    dx = math.floor(dx + 0.5)
    y = math.floor(y + 0.5)
    if shadow then
      set(shadow)
      love.graphics.setFont(font)
      love.graphics.print(str, dx + 1, y + 1)
    end
    if color then set(color) end
    love.graphics.setFont(font)
    love.graphics.print(str, dx, y)
    return w
  end
  F.text = text

  -- Greedy word wrap to a pixel budget, honouring explicit newlines.  A
  -- single word longer than the budget is placed anyway rather than
  -- looping forever, which is what keeps a malformed message from hanging
  -- the frame.
  local function wrap(str, font, maxw)
    font = font or F.fonts().small
    local out = {}
    for paragraph in tostring(str):gmatch("[^\n]*") do
      if paragraph == "" then
        out[#out + 1] = ""
      else
        local line = ""
        for word in paragraph:gmatch("%S+") do
          local candidate = line == "" and word or (line .. " " .. word)
          if font:getWidth(candidate) <= maxw or line == "" then
            line = candidate
          else
            out[#out + 1] = line
            line = word
          end
        end
        out[#out + 1] = line
      end
    end
    if #out == 0 then out[1] = "" end
    return out
  end
  F.wrap = wrap

  -- Pick the largest of the panel's faces that lets `str` fit `maxh` tall
  -- inside `maxw`, and hand back the wrapped lines with it.  The message
  -- panel is one narrow column now (E is 288px, not the old full band), so a
  -- long resolve line -- "X used Y! It's super effective! Critical hit!"
  -- -- has to step down instead of running out of the panel's bottom edge.
  local function fitBlock(str, maxw, maxh, sizes)
    local f = F.fonts()
    str = F.sanitize(str)
    local order = sizes or { f.mid, f.small, f.tiny }
    local last
    for _, font in ipairs(order) do
      local lines = wrap(str, font, maxw)
      local lh = lineH(font)
      last = { font = font, lines = lines, lh = lh }
      if #lines * lh <= maxh then return last end
    end
    return last
  end
  F.fitBlock = fitBlock

  -- A modern selection cursor: g9-gui's own double chevron
  -- (Theme.chevrons) -- two solid triangles, the second nudged by a slow
  -- pulse so the marker breathes without moving its anchor.  (x, y) is the
  -- first triangle's left edge / vertical top.
  local function chevrons(x, y, size, color, pulse)
    local s = size or 9
    local off = (pulse or 0) * 1.6
    set(color or COL.accent)
    local function tri(ox)
      love.graphics.polygon("fill", ox, y, ox + s * 0.60, y + s * 0.5, ox, y + s)
    end
    tri(x)
    tri(x + s * 0.62 + off)
  end
  F.chevrons = chevrons
  F.chevron = chevrons

  local function pulse()
    if love.timer and love.timer.getTime then
      local ok, t = pcall(love.timer.getTime)
      if ok and type(t) == "number" then return (math.sin(t * 5.0) + 1) * 0.5 end
    end
    return 0
  end

  -- The selection cursor, in ONE place so every menu marks its row the same
  -- way.  It is the double chevron ALONE: a brighter vertical bar used to sit
  -- at the lit row's left edge, but at this size the bar and the chevron
  -- fused into a single blob that read as a stray line stuck to the arrow
  -- (g9-gui's roster dropped the same bar for the same reason).
  --
  -- The chevron is centred on the label's own LINE BOX, which is also the
  -- bar's centre -- so it rides the middle of the row whatever metrics the
  -- face has, instead of the ad-hoc `y + 1`/`y + 2` offsets that left it
  -- hanging above the text -- and it is held CURSOR_GAP clear of the label,
  -- so no amount of the pulse can put its tip on the first glyph.
  --
  -- `x`/`y` are the LABEL's left edge and line-box top (the caller draws the
  -- text itself, at the same y, so the two always agree on the row's middle).
  -- `right` is where the lit bar must END: the bar grows LEFTWARDS to
  -- enclose the cursor, so moving the cursor can never move the text.
  -- `pitch` is the row-to-row spacing -- Saira's line box is 1.57x its size,
  -- taller than the tight rhythms these lists pack rows at, and an unfitted
  -- bar would overlap its neighbour.
  local CURSOR_S = 9
  local CURSOR_REACH = CURSOR_S * 1.22 + 2   -- the pulsed pair's rightmost px
  local CURSOR_GAP = 6                       -- clear air before the label
  local CURSOR_PAD = 5                       -- bar inset before the chevron

  local function selectCursor(x, y, right, pitch, font, color)
    font = font or F.fonts().mid
    local lh = lineH(font)
    local bh = math.min(lh + 6, (pitch or lh + 10) - 6)
    if bh < CURSOR_S + 4 then bh = CURSOR_S + 4 end
    local left = x - CURSOR_GAP - CURSOR_REACH - CURSOR_PAD
    local top = y + lh * 0.5 - bh * 0.5
    set(color or COL.rowLit)
    rect("fill", left, top, math.max(8, right - left), bh, 4)
    chevrons(left + CURSOR_PAD, top + (bh - CURSOR_S) * 0.5, CURSOR_S,
      COL.accent, pulse())
  end
  F.selectCursor = selectCursor
  F.CURSOR_S = CURSOR_S

  -- A dim all-caps field label ("HP", "LV", "EXP", "EFF", "PP", ...), the
  -- way every g9-gui screen labels a value.
  local function label(str, x, y, font, color)
    return text(str, x, y, font or F.fonts().tiny, "left", color or COL.inkFaint)
  end

  -- ------------------------------------------------------------------ layout

  -- The native bottom band: design x 0..320, y 128..180 -> canvas
  -- 0..960 x 384..540.  The 28/12-tile F/E split is 0..672 / 672..960, so
  -- box E really does keep its original place and width.
  local BAND_X, BAND_Y, BAND_W, BAND_H = 0, 384, 960, 156
  local PARTY = { x = 0, y = BAND_Y, w = 658, h = BAND_H }
  local EBOX = { x = 672, y = BAND_Y, w = 288, h = BAND_H }
  -- The move readout's floating panel, over the top-left of the field.
  -- ROUND 83 (2026-09-10 user request): its TOP EDGE is now flush with the
  -- canvas's own top (y=0, "roof its roof to the canvas roof") and it is one
  -- ROW tall (h=40, down from 58) rather than a tall box with a pocket of
  -- empty space above the name -- see drawMoveInfo, which centres every
  -- string on the panel's own middle. It floats over the field, so nothing
  -- else has to move for it.
  local INFO = { x = 12, y = 0, w = 600, h = 40 }

  -- One party row's own slot geometry.  Four literal slots, fixed: an absent
  -- Pokemon leaves its band of the list empty rather than letting the rows
  -- below slide up, which is what makes the list read as "party placement
  -- 1..4" instead of "the mons that happen to be out, stacked".
  local ROW_TOP = BAND_Y + 4
  local ROW_H = 34
  local ROW_GAP = 4
  -- Column x offsets are measured from PARTY.x, and the widths are chosen so
  -- the exp bar stays clearly SHORTER than the HP bar (option's own rule).
  -- The HP bar is tall enough to carry its current/max number INSIDE it.
  local C_NAME = 14
  local NAME_W = 116
  local C_HP_LBL = 138
  local C_HP = 160
  local W_HP = 128
  local H_HP = 16
  local C_LV_LBL = 300
  local C_LV = 316
  local C_EXP_LBL = 372
  local C_EXP = 404
  local W_EXP = 84
  local H_EXP = 6
  local C_EFF_LBL = 500
  local C_EFF = 526

  -- E's own interior: a slim header band (title + divider) over the content.
  local E_PAD = 12
  local E_HEAD = 24

  -- What each phase calls itself in the panel header.
  local HEAD = {
    actionMenu = "ACTION", moveSelect = "MOVES", gimmickSelect = "FORMS",
    targetSelect = "TARGET", swapSelect = "SWITCH", prompt = "RESPONSE",
  }

  local STATUS_WORD = {
    PSN = "Poisoned", TOX = "Badly Pois.", BRN = "Burned",
    FRZ = "Frozen", PAR = "Paralyzed", SLP = "Asleep", FNT = "Fainted",
  }

  -- Exposed for the harness (and for any sibling that ever wants to line a
  -- native element up with these panels).
  F.geom = {
    band = { x = BAND_X, y = BAND_Y, w = BAND_W, h = BAND_H },
    party = { x = PARTY.x, y = PARTY.y, w = PARTY.w, h = PARTY.h },
    ebox = { x = EBOX.x, y = EBOX.y, w = EBOX.w, h = EBOX.h },
    info = { x = INFO.x, y = INFO.y, w = INFO.w, h = INFO.h },
    rowTop = ROW_TOP, rowH = ROW_H, rowGap = ROW_GAP,
    wHp = W_HP, wExp = W_EXP, hHp = H_HP, hExp = H_EXP,
  }

  -- ------------------------------------------------------------------ pieces

  -- The panel header: a dim subtitle rule with the section's own all-caps
  -- title over it, then a divider closing the band off from the content.
  local function header(x, y, w, title)
    local f = F.fonts()
    set(COL.accent)
    love.graphics.polygon("fill", x + 11, y + 11, x + 16, y + 15, x + 11, y + 19, x + 6, y + 15)
    text(title, x + 24, y + 8, f.tinyBold, "left", COL.accent)
    set(COL.border)
    rect("fill", x + 6, y + E_HEAD - 1, w - 12, 1, 0)
  end

  -- One party row, as its own panel.  `lit` marks the row of the battler
  -- whose command is being chosen this turn.
  --
  -- No corner brackets on a row: g9-gui reserves those for a WINDOW, and
  -- repeats them on every row of its own roster only to look busy.  The row
  -- is its own rounded surface with a border and a top shine -- enough to
  -- read as one of four fixed spaces -- while the whole party list stays
  -- visually quiet next to the bracketed E window beside it.
  local function drawPartyRow(row, index, lit)
    local ry = ROW_TOP + (index - 1) * (ROW_H + ROW_GAP)
    local f = F.fonts()
    -- WHITE ROW (options.lua's row): when on, the row's own BACKGROUND is a
    -- translucent white panel instead of the usual dark surface.  Nothing
    -- inside the row changes -- the name, HP bar (below), level, exp bar and
    -- status tag all keep their colours.  The lit row keeps its brighter
    -- border so the active mon is still readable.
    panel(PARTY.x, ry, PARTY.w, ROW_H, {
      shadow = 0, radius = 4,
      color = F.whiteRow() and COL.whiteRow or (lit and COL.panelLit or COL.panel),
      border = lit and COL.borderLit or COL.border,
    })
    local midY = ry + ROW_H * 0.5
    local nameCol = row.alive and COL.ink or COL.inkFaint
    text(fit(row.name or "?", f.bigBold, NAME_W), PARTY.x + C_NAME, midY - 11,
      f.bigBold, "left", nameCol)

    label("HP", PARTY.x + C_HP_LBL, midY - 5, f.tiny)
    local hx = PARTY.x + C_HP
    local hy = midY - H_HP * 0.5
    local hpFrac = (row.maxHp and row.maxHp > 0) and (row.hp / row.maxHp) or 0
    -- The HP bar's state colour, always on (v4.0.8).  COL.good/warn/bad are
    -- the one shared depth described at the palette above -- NOT affected by
    -- the WHITE ROW option, which repaints only the row background behind
    -- this bar.  The exp bar below keeps its own colour either way.
    local hpCol = hpFrac > 0.5 and COL.good or (hpFrac > 0.2 and COL.warn or COL.bad)
    bar(hx, hy, W_HP, H_HP, hpFrac, hpCol, { radius = 4 })
    local hpText = string.format("%d/%d", math.max(0, row.hp or 0), math.max(0, row.maxHp or 0))
    text(hpText, hx + W_HP * 0.5, midY - 7, f.tinyBold, "center", COL.ink, COL.shadow)

    label("LV", PARTY.x + C_LV_LBL, midY - 5, f.tiny)
    text(tostring(row.level or 1), PARTY.x + C_LV, midY - 8, f.midBold, "left", COL.ink)

    label("EXP", PARTY.x + C_EXP_LBL, midY - 5, f.tiny)
    bar(PARTY.x + C_EXP, midY - H_EXP * 0.5, W_EXP, H_EXP, row.expFrac or 0, COL.accent,
      { radius = 3 })

    label("EFF", PARTY.x + C_EFF_LBL, midY - 5, f.tiny)
    if row.eff then
      local word = STATUS_WORD[row.eff] or row.eff
      text(word, PARTY.x + C_EFF, midY - 6, f.smallBold, "left", COL.gold)
    end
  end

  -- The ally party status list: four fixed slots, an absent Pokemon drawing
  -- NOTHING at all at its own slot (the option's own rule).
  local function drawParty(data)
    local rows = data.party or {}
    local lit = data.activeSlot
    for i = 1, 4 do
      local row = rows[i]
      if row then drawPartyRow(row, i, lit == i) end
    end
  end

  -- The move readout: a floating panel over the top-left of the field, the
  -- move's name beside its four figures (PP cur/max, PWR, ACC, EFF).
  --
  -- ROUND 83: every string is placed from the panel's OWN vertical middle
  -- (`midY`) through its own line box, instead of the old fixed y+21/y+24/
  -- y+27 offsets. The panel shrank to one row and was roofed to the canvas
  -- top, so the name, the tiny labels and the values now all share one
  -- optical centreline with even air above and below, whatever metrics the
  -- running face has. The label and its value still sit on a shared BASELINE
  -- (the label is the shorter face, so its top is pushed down by the
  -- difference), which is what makes "PP 10/10" read as one field rather
  -- than two stacked tokens.
  local function drawMoveInfo(data)
    local info = data.moveInfo
    if not info then return end
    panel(INFO.x, INFO.y, INFO.w, INFO.h, { shadow = 3, brackets = 10 })
    local f = F.fonts()
    local nameBudget = 200
    local midY = INFO.y + INFO.h * 0.5
    local nameH = lineH(f.bigBold)
    text(fit(info.name or "???", f.bigBold, nameBudget), INFO.x + 16,
      midY - nameH * 0.5, f.bigBold, "left", COL.ink)
    -- A vertical divider splits the name off from the figures, the way the
    -- reference screen sets a move's name apart from its stats.
    set(COL.border)
    rect("fill", INFO.x + 232, INFO.y + 8, 1, INFO.h - 16, 0)
    local pen = INFO.x + 248
    local valH = lineH(f.midBold)
    local lblH = lineH(f.tiny)
    local valTop = midY - valH * 0.5
    local lblTop = valTop + valH - lblH
    local function field(lbl, value, valueColor)
      pen = pen + label(lbl, pen, lblTop, f.tiny)
      pen = pen + 7
      pen = pen + text(value, pen, valTop, f.midBold, "left", valueColor or COL.ink)
      pen = pen + 22
    end
    field("PP", string.format("%d/%d", info.pp or 0, info.maxPp or 0), COL.ink)
    field("PWR", (info.power and info.power > 0) and tostring(info.power) or "--", COL.gold)
    field("ACC", (info.accuracy and info.accuracy > 0) and tostring(info.accuracy) or "--", COL.gold)
    if info.eff then field("EFF", info.eff, COL.ink) end
  end

  -- The message panel: E's own rect, the wrapped message filling it.  The
  -- face steps down until the text fits, so a long resolve line can never
  -- run past the panel's border.
  local function drawMessage(data, message)
    panel(EBOX.x, EBOX.y, EBOX.w, EBOX.h, { shadow = 4, brackets = 12 })
    local maxw = EBOX.w - E_PAD * 2
    local maxh = EBOX.h - 20
    local block = fitBlock(message or "", maxw, maxh)
    local rows = math.min(#block.lines, math.max(1, math.floor(maxh / block.lh)))
    local ty = EBOX.y + 12
    -- The accent rule down the message's own left edge, as tall as the text
    -- it belongs to -- the quiet marker that says "this is the line the
    -- battle is speaking right now".
    local ruleH = math.max(6, block.lh * rows - 6)
    set(COL.accent)
    rect("fill", EBOX.x + E_PAD - 8, ty + 1, 2, ruleH, 1)
    for i = 1, rows do
      text(block.lines[i], EBOX.x + E_PAD, ty, block.font, "left", COL.ink)
      ty = ty + block.lh
    end
  end

  -- A menu row: the lit row under the label, plus the cursor.  `opts.right`
  -- is the lit row's right edge and `opts.pitch` the row-to-row spacing (see
  -- selectCursor); both default to a sane single-column list.  Returns the
  -- label's drawn width.
  local function menuRow(textStr, x, y, selected, opts)
    opts = opts or {}
    local f = opts.font or F.fonts().mid
    textStr = tostring(textStr)
    if selected then
      selectCursor(x, y, opts.right or (EBOX.x + EBOX.w - 8), opts.pitch or 24, f)
    end
    local col = opts.dim and COL.inkFaint or (selected and COL.accent or COL.ink)
    return text(textStr, x, y, f, "left", col)
  end

  -- The action menu (FIGHT/BAG/PKMN/RUN[/custom]): E's own list or 2x3 grid,
  -- over a message strip when the screen has one to show at the same time.
  local function drawActionMenu(data)
    local menu = data.menu
    if not menu then return end
    local f = F.fonts()
    panel(EBOX.x, EBOX.y, EBOX.w, EBOX.h, { shadow = 4, brackets = 12 })
    local top = EBOX.y
    -- A refusal/failed-item line and the menu can be live at once (the native
    -- screen showed the line in F beside the menu in E).  When that happens
    -- the line takes the header's place, so E never has to grow.
    if data.message then
      local block = fitBlock(data.message, EBOX.w - E_PAD * 2, 40, { f.small, f.tiny })
      local rows = math.min(#block.lines, 2)
      local ty = EBOX.y + 8
      for i = 1, rows do
        text(block.lines[i], EBOX.x + E_PAD, ty, block.font, "left", COL.ink)
        ty = ty + block.lh
      end
      set(COL.border)
      rect("fill", EBOX.x + 6, ty + 3, EBOX.w - 12, 1, 0)
      top = ty + 4
    else
      header(EBOX.x, EBOX.y, EBOX.w, HEAD.actionMenu)
      top = EBOX.y + E_HEAD
    end
    local cursor = menu.cursor
    local function labelFor(id)
      if id == "CUSTOM" then return menu.customLabel or "FORM"
      end
      return (menu.labels and menu.labels[id]) or id
    end
    if menu.layout == "list" and menu.order then
      local y = top + 8
      for _, id in ipairs(menu.order) do
        menuRow(tostring(labelFor(id)), EBOX.x + 30, y, id == cursor,
          { right = EBOX.x + EBOX.w - 8, pitch = 22 })
        y = y + 22
      end
    else
      local rows = menu.rows or {}
      local colX = { EBOX.x + 34, EBOX.x + 158 }
      for r = 1, math.min(#rows, 3) do
        local rowY = top + 7 + (r - 1) * 32
        for c = 1, 2 do
          local id = rows[r] and rows[r][c]
          if id then
            menuRow(tostring(labelFor(id)), colX[c], rowY, id == cursor,
              { right = colX[c] + 82, pitch = 32 })
          end
        end
      end
    end
  end

  -- The move list, in E.  A refusal line replaces the list until it is
  -- acknowledged, exactly as the native box does; a queued positional swap
  -- is tagged, and a move with no PP left is dimmed (bar and all).
  local function drawMoveList(data)
    local rows = data.moves or {}
    local f = F.fonts()
    if data.message then
      drawMessage(data, data.message)
      return
    end
    panel(EBOX.x, EBOX.y, EBOX.w, EBOX.h, { shadow = 4, brackets = 12 })
    header(EBOX.x, EBOX.y, EBOX.w, HEAD.moveSelect)
    local rowH = 24
    local startY = EBOX.y + E_HEAD + 6
    for i, mv in ipairs(rows) do
      local rowY = startY + (i - 1) * rowH
      local selected = (i == data.moveCursor)
      local dim = mv.usable == false
      if selected then
        selectCursor(EBOX.x + 32, rowY, EBOX.x + EBOX.w - 8, rowH, f.mid)
      end
      local nameCol = dim and COL.inkFaint or (selected and COL.accent or COL.ink)
      text(fit(mv.name or "???", f.mid, 150), EBOX.x + 32, rowY, f.mid, "left", nameCol)
      if mv.swap then
        text("[SWAP]", EBOX.x + 32 + 96, rowY + 2, f.tiny, "left", COL.gold)
      end
      text(string.format("%d/%d", mv.pp or 0, mv.maxPp or 0), EBOX.x + EBOX.w - 14, rowY + 1,
        f.smallBold, "right", dim and COL.inkFaint or COL.inkDim)
    end
  end

  -- The transform (FORMS) picker, in E -- the native 2x2 gimmick grid at E's
  -- own width.
  local function drawGimmick(data)
    local rows = data.gimmick or {}
    local f = F.fonts()
    panel(EBOX.x, EBOX.y, EBOX.w, EBOX.h, { shadow = 4, brackets = 12 })
    header(EBOX.x, EBOX.y, EBOX.w, HEAD.gimmickSelect)
    local colX = { EBOX.x + 40, EBOX.x + 164 }
    for i = 1, 4 do
      local g = rows[i]
      if g then
        local row = math.floor((i - 1) / 2) + 1
        local col = (i - 1) % 2 + 1
        local gx = colX[col]
        local gy = EBOX.y + E_HEAD + 16 + (row - 1) * 34
        if g.selected then
          selectCursor(gx + 4, gy, gx + 96, 34, f.mid)
        end
        text(fit(g.label or "?", f.mid, 88), gx + 4, gy, f.mid, "left",
          g.selected and COL.accent or COL.ink)
      end
    end
  end

  -- A two-option prompt, entirely inside E: the question wrapped under the
  -- header, the two choices beneath it with the selection bar and cursor.
  local function drawPrompt(data)
    local ask = data.prompt
    if not ask then return end
    local f = F.fonts()
    panel(EBOX.x, EBOX.y, EBOX.w, EBOX.h, { shadow = 4, brackets = 12 })
    header(EBOX.x, EBOX.y, EBOX.w, HEAD.prompt)
    local y = EBOX.y + E_HEAD + 8
    local block = fitBlock(ask.text or "", EBOX.w - E_PAD * 2, 44, { f.mid, f.small, f.tiny })
    for i = 1, math.min(#block.lines, 2) do
      text(block.lines[i], EBOX.x + E_PAD, y, block.font, "left", COL.ink)
      y = y + block.lh
    end
    y = y + 8
    for i = 1, 2 do
      local selected = (ask.index == i)
      menuRow(tostring(ask.choices and ask.choices[i] or ""), EBOX.x + 30, y, selected,
        { right = EBOX.x + EBOX.w - 8, pitch = 28 })
      y = y + 28
    end
  end

  -- ------------------------------------------------------------------ target arrow

  -- The modern target pointer: a translucent accent lozenge riding above a
  -- downward chevron, drawn from vector geometry so it is the same on both
  -- generations.  `mark` is the candidate's OWN readout/sprite anchor in
  -- DESIGN px ({x = centre, top = top edge}); the arrow hangs just above
  -- `top`, so it tracks the mon it belongs to exactly like the tile glyph
  -- it replaces.  A slow bob keeps the eye on it.
  --
  -- `opts.hollow` draws the swap cue's OWNER form -- the same silhouette,
  -- outlined rather than filled -- so drawSwapMark can keep its
  -- filled-target/hollow-owner pair; `opts.color` overrides the fill.
  function F.drawTargetArrow(mark, ds, opts)
    if not mark then return end
    opts = opts or {}
    ds = ds or DS_FALLBACK
    local bob = 0
    if love.timer and love.timer.getTime then
      bob = math.floor(love.timer.getTime() * 4) % 2
    end
    love.graphics.push()
    love.graphics.scale(1 / ds, 1 / ds)
    local cx = (mark.x or 0) * ds
    -- The 34 floor keeps the WHOLE pointer on the canvas: the body reaches
    -- 30px above tipY, so a mon whose head sits near the top of the field
    -- gets its arrow pinned under the edge instead of drawn off-screen.
    local tipY = math.max(34, (mark.top or 0) * ds - 26 - bob * 3)
    local w = 22
    if opts.hollow then
      set(opts.color or COL.accentDim)
      love.graphics.polygon("fill", cx - w * 0.5, tipY - 30, cx + w * 0.5, tipY - 30, cx, tipY)
      set(COL.accent)
      love.graphics.polygon("line", cx - w * 0.5, tipY - 30, cx + w * 0.5, tipY - 30, cx, tipY)
      love.graphics.pop()
      return
    end
    local body = opts.color or COL.accent
    -- glow
    set(COL.accentDim)
    love.graphics.polygon("fill", cx - w * 0.5 - 3, tipY - 26 - 3, cx + w * 0.5 + 3, tipY - 26 - 3, cx, tipY + 3)
    -- body
    set(body)
    love.graphics.polygon("fill", cx - w * 0.5, tipY - 30, cx + w * 0.5, tipY - 30, cx, tipY)
    set(COL.void)
    love.graphics.polygon("fill", cx - w * 0.28, tipY - 26, cx + w * 0.28, tipY - 26, cx, tipY - 8)
    love.graphics.pop()
  end

  -- ------------------------------------------------------------------ driver

  -- Wrap the whole draw in a 1/DS scale so canvas pixels land on the canvas
  -- 1:1 (see the header).  Safe to nest inside the scene's own transform.
  --
  -- THE PARTY LIST IS ALWAYS UP.  It is the option's persistent surface --
  -- the readout the ally sprites gave up -- and every message now goes to
  -- E's own column, so nothing is ever drawn over it.
  function F.draw(data)
    if not data then return end
    local ds = data.ds or DS_FALLBACK
    love.graphics.push()
    love.graphics.scale(1 / ds, 1 / ds)
    love.graphics.setColor(1, 1, 1, 1)

    local phase = data.phase
    drawParty(data)

    if phase == "actionMenu" then
      drawActionMenu(data)
    elseif phase == "moveSelect" then
      drawMoveList(data)
    elseif phase == "gimmickSelect" then
      drawGimmick(data)
    elseif phase == "prompt" then
      drawPrompt(data)
    elseif phase == "targetSelect" then
      drawMessage(data, data.message or "Choose a target:")
    elseif phase == "swapSelect" then
      drawMessage(data, data.message or "Switch with whom?")
    elseif data.message then
      -- intro / resolving / over: the narration itself.  All of it in E.
      drawMessage(data, data.message)
    end

    if phase == "moveSelect" or phase == "targetSelect" then
      drawMoveInfo(data)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
  end

  -- The effect word for a move, from whatever the registered record carries.
  -- The engine's records are Showdown-derived, so a move's secondary is
  -- spelled out either as a full `status` field, a `secondary.status`, or
  -- only inside the effect tag ("EFFECT_..."); this checks all three and
  -- leaves the field blank when the move genuinely has no rider.
  local EFFECT_WORDS = {
    { "PARALYZE", "Paralyze" }, { "PARALYSIS", "Paralyze" },
    { "POISON", "Poison" }, { "TOXIC", "Badly Poison" },
    { "BURN", "Burn" }, { "FREEZE", "Freeze" }, { "FROST", "Freeze" },
    { "SLEEP", "Sleep" }, { "FLINCH", "Flinch" }, { "CONFUS", "Confuse" },
    { "TAUNT", "Taunt" }, { "ENCORE", "Encore" }, { "LEECH", "Leech" },
    { "RECOIL", "Recoil" }, { "HEAL", "Heal" }, { "RECOVER", "Heal" },
    { "DRAIN", "Drain" }, { "PROTECT", "Protect" }, { "REFLECT", "Reflect" },
    { "LIGHTSCREEN", "Light Screen" }, { "HAZE", "Haze" }, { "MIST", "Mist" },
    { "WEATHER", "Weather" }, { "HAZARD", "Hazard" }, { "STAT", "Stat" },
    { "OHKO", "One-Hit KO" }, { "MULTI", "Multi-hit" }, { "SWITCH", "Switch" },
    { "STEAL", "Steal" },
  }
  function F.moveEffect(def)
    if type(def) ~= "table" then return nil end
    local status = def.status
      or (type(def.secondary) == "table" and def.secondary.status)
      or (type(def.secondaries) == "table" and def.secondaries[1]
        and def.secondaries[1].status)
    if type(status) == "string" and status ~= "" then
      local up = status:upper()
      local word = STATUS_WORD[up]
      if word then return word end
      return up
    end
    local hay = table.concat({
      tostring(def.effect or ""),
      tostring(def.flags or ""),
      tostring(def.effectChance or ""),
    }, " "):upper()
    if hay ~= "" then
      for _, pair in ipairs(EFFECT_WORDS) do
        if hay:find(pair[1], 1, true) then return pair[2] end
      end
    end
    return nil
  end

  return F
end
