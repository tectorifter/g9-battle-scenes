# assets/backgrounds

The ground plane behind the battle sprites (the Mod Manager's **BACKGROUND**
row — `background.lua` reads it). **One example ships with the mod:
`cave.png`** (an original, AI-generated backdrop — see "The bundled example"
below). Nothing third-party or ROM-derived is redistributed; drop in your own
PNGs alongside it and name them by the fight they are for. **AUTO** (the
default) reads each battle and draws the matching file; **OFF** draws none of
this and the field stays the plain white it has always been.

## The tags

A file's name (before its extension) is the **tag** — the fight it plays for:

| tag | used for |
|---|---|
| `grass` | a wild encounter in grass |
| `water` | a wild encounter on water (surfing or fishing) |
| `cave` | a wild encounter in a cave / an indoor encounter |
| `gym1` … `gym16` | gyms 1 through 16, in badge order (see below) |
| `elitefour1` … `elitefour4` | the four Elite Four members, in league order |
| `champion` | the Champion |
| `red` | Red |
| `rival` | a rival battle |
| `rocket` | any Team Rocket fight |
| `ho-oh` | Ho-Oh |
| `lugia` | Lugia |
| `suicune` | Suicune |
| `fated` | any other legendary, or a scripted/static encounter |

Extensions `.png`, `.jpg`, `.jpeg` and `.webp` are accepted (PNG is safest).
`README.md` and any dot-file are ignored.

### Multiple files for one tag (variants)

A file may carry a variant suffix after a dash — `gym1-2.png`, `gym1-23.png`,
`grass-2.png`, `ho-oh-2.png` — meaning "another asset for the tag **before**
the dash". When several files share a tag, **one is rolled at random per
battle and kept for that whole fight**:

- two files for a tag → **50/50**
- N files for a tag → 1/N each

The number after the dash is only a **disambiguator**, not a weight — `gym1-2`
and `gym1-23` are equally likely members of `gym1`. Mixing a bare `gym1.png`
with `gym1-2.png` is the same 50/50.

```
assets/backgrounds/grass.png        -> grass, the only one
assets/backgrounds/grass-2.png      -> grass, second of two (50/50)
assets/backgrounds/gym1.png         -> gym 1
assets/backgrounds/gym1-2.png       -> gym 1, second file
assets/backgrounds/gym10-3.png      -> gym 10 (longest tag name wins)
assets/backgrounds/ho-oh-2.png      -> ho-oh, second file
```

### Gym numbering

Badge order, per generation.

- **Gen 1:** 1 Pewter, 2 Cerulean, 3 Vermilion, 4 Celadon, 5 Fuchsia,
  6 Saffron, 7 Cinnabar, 8 Viridian.
- **Gen 2:** 1–8 are the **Johto** gyms in badge order (Violet … Blackthorn);
  9–16 are the **Kanto** gyms in badge order (Pewter … Viridian) — matching
  the sixteen badges Gold/Silver actually hands out.

## How the tag is chosen

`background.lua` tags a battle in this priority order:

1. **Trainer class** — a gym leader → `gym1`..`gym16`; an Elite Four member →
   `elitefour1`..`elitefour4`; the Champion → `champion`; Red → `red`; a rival
   → `rival`; any Team Rocket trainer → `rocket`. (Gen 1's `OPP_*` class names
   and Gen 2's bare names are both recognised; Giovanni counts as `gym8` on
   Viridian Gym and `rocket` everywhere else.)
2. **Opposing species** — Ho-Oh / Lugia / Suicune by name; any other legendary
   → `fated`.
3. **Wild terrain** — the engine's own encounter roll supplies
   `"grass"` / `"water"` / `"indoor"` (`background.lua` hooks `encounter.roll`,
   `encounter.species` and `encounter.fishing`), so a grass/water/indoor
   wild battle maps straight to `grass` / `water` / `cave`. Gen 2 rolls only
   `"grass"` / `"water"` and keeps the cave fact in the map's `environment`
   byte, so a `"grass"` roll on a `CAVE` / `DUNGEON` / `INDOOR` / `GATE` map
   is `cave`.
4. **Static / scripted encounter** — a wild battle with no encounter roll
   behind it (a scripted fight, a legendary, a static overworld mon) →
   `fated`.
5. **Map fallback** — a gym map with no class match still gives its gym
   number; otherwise the map/player decides (`water` while surfing on either
   generation — Gen 1's `player.surfing`, Gen 2's `playerState`, or the water
   tile underfoot — `cave` for `CAVERN`/`CAVE` tilesets or a cave/dungeon/
   indoor map environment, else `grass`).

**A tag with no art falls back to the map's terrain tag** when it is not
itself a terrain tag — so a missing `gym1.png` still shows the gym's ground
rather than white.

## How it is drawn

The scene is authored in a **320x180 design field** on a 960x540 canvas
(`battle_screen.lua`'s `VW`/`VH`/`DS`). The backdrop is drawn with **nearest**
filtering, hung from the field's **top edge** — its ROOF flush with the screen's
roof, so no white ever shows above it — and scaled to **cover** the band from
there down to the **middle of the F/E box** (the bottom message +
FIGHT/BAG/PKMN/RUN band, which owns the field's last 52 design px): design
**y = 154**. In numbers, `s = max(320 / imageWidth, 154 / imageHeight)` and the
image is drawn at `x = (320 - imageWidth*s)/2, y = 0`. It is drawn as the first
thing `Screen:drawContent` does, so every sprite, HUD readout and F/E box then
paints on top, exactly as the old white fill did.

- A source at least as **broad** as the band (~2.08:1 or wider) is zoomed until
  its bottom (feet) edge lands on the F/E box's middle line (design y=154); its
  sides are centred and cropped, and the top of the screen is always covered.
- A **taller** source (16:9 or narrower) keeps its full width, is drawn from the
  top edge, and simply runs its lower overflow behind the F/E box.

The art should be authored **near-top-down** (ground fills the frame, scenery
only in a thin top band) so it reads as a ground plane rather than a side-on
landscape. The ground should reach up past the enemy's feet line (design y=64)
so up to four combatants a side stand on solid ground, and the scene covers the
rest. A soft **contact shadow** is drawn under each sprite (an ellipse ~0.36 x
0.085 of the sprite height, at its feet) so the mons read as standing on the
ground.

**A missing or corrupt file is never fatal** — `background.lua` logs one
warning and the field falls back to white.

## The bundled example (`cave.png`)

`cave.png` is an original, AI-generated 960x540 (16:9) cave backdrop, bundled
so a fresh install draws a cave backdrop for cave / indoor fights instead of
white. It is painted in the same **soft, richly-shaded style** as the drop-in
`grass` / `water` art this project is used with — mottled, gently-lit rock with
blended brushwork, muted grey-brown and cool blue-green tones, and no hard
cartoon outlines. It is authored to the composition above: the cave **wall and
ceiling are a thin band across the top ~15%** of the PNG, fading softly into
the floor, and the rocky **ground fills the bottom ~85%**, so the ground reaches
well past the enemy's feet line (design y=64) and up to four combatants a side
stand on solid rock. It is a normal tag file — delete it, swap it, or add
`cave-2.png` / `cave-3.png` for cave variants exactly like any other.

## Adding your own backdrop

1. Save a 16:9 PNG in here, named with a tag from the table above (optionally
   with a `-<n>` variant suffix).
2. That's it — `AUTO` will pick it up for the matching fight. Restart the game
   (the folder is scanned once at load).

Do **not** add art ripped from a commercial game — this project's static gate
rejects ROM-derived content. Keep any third-party art's author and licence
recorded alongside it.
