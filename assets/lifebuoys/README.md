# assets/lifebuoys

The circular **life ring** a battler wears when a fight happens **on water** —
`background.lua` draws it (a **tilted ellipse**, to match the water plane) for
every mon that neither swims, flies, hovers nor passes through (so a Charmander
on the open sea is held up by a buoy instead of standing on
it).

"On water" means the water actually **on the field**, not merely the fight's
tag: a static/scripted wild fight resolves to `fated` (it has no encounter roll
behind it) and then borrows the map's own water art, and a fight standing on
water must float its mons whichever of the two said so — so the rings key off
the tag's art *or* the map terrain its art falls back to. See `fieldTag` in
`background.lua`. **This folder ships EMPTY of art.** Nothing is bundled and
nothing third-party is redistributed: with no file here the ring is drawn from
primitives (an orange-and-white eight-segment torus), so the feature works on a
stock install. Drop in your own PNG to replace that primitive ring.

## The drop-in name

A file is used when its stem (the name before its extension, lower-cased, `_`
treated as `-`) is one of:

| stem | |
|---|---|
| `lifebuoy` | the canonical name |
| `buoy` | |
| `lifering` | |
| `life-ring` | |
| `life-buoy` | |

So `assets/lifebuoys/lifebuoy.png` is the normal choice. Extensions `.png`,
`.jpg`, `.jpeg` and `.webp` are accepted (PNG with transparency is the only one
that looks right). `README.md` and any dot-file are ignored.

### Multiple files (variants)

A file may carry a variant suffix after a dash — `lifebuoy-2.png`,
`lifebuoy-23.png` — meaning "another buoy". When several files match, **one is
rolled at random per battle and kept for that whole fight** (two files = 50/50,
N files = 1/N). The number is only a disambiguator, not a weight.

```
assets/lifebuoys/lifebuoy.png      -> the only one
assets/lifebuoys/lifebuoy-2.png    -> second of two (50/50)
assets/lifebuoys/buoy.png          -> another name for the same pool
```

The folder `assets/` itself is also scanned (same stems), so a buoy dropped at
the top level still works.

## How it is drawn

A ring is **worn on the mon's lower body**, not laid beside it. Its far half is
painted in the background pass (behind the sprite) and its near half is painted
after the sprite pass (over the mon's feet/legs), so the front rim crosses the
mon and it reads as a ring *around* it rather than a disc stuck behind it.

The ring **lies flat on the water**, so the battle's oblique overhead view turns
it into an **ellipse**: its height is **1/2.8** of its width (`BUOY_SQUASH` in
`background.lua`) — the same foreshortening the water plane itself has. Draw
your drop-in already at that tilt; the built-in primitive ring is squashed to
match it.

The scene is a **320x180 design field** on a 960x540 canvas. The ring's outer
**width** is **1.20 x** the sprite's larger drawn dimension, its centre sits
**0.08** of the sprite height above the feet (so the ring hugs the ankles and
its near rim dips a little onto the water), and its hole is **0.55** of the
outer width. The whole image is scaled so its width equals the outer width, so
the image's **own aspect ratio** sets the ring's visible height. Author a
**wide, flat** image (about 2.8:1, transparent background) with the ring
centred.

Who gets a ring (everyone else does not):

- **Water** types swim — no ring.
- **Ghost** types pass over water — no ring.
- **Flying** types fly — no ring, except the walkers that cannot actually fly
  (Doduo/Dodrio/Farfetch'd/Skarmory/Delibird/Hawlucha/Flamigo/Rowlet).
- Known **hoverers** (Levitate, Magnemite/Beldum/Klink/Porygon lines, the
  floating Ghosts, …) — no ring. The list mirrors `g9-battle-sprites`'
  `data/dbk_float.lua`.
- A battler with **no type data at all** is left alone rather than guessed at.
- **`BUOY_CURATED`** (also exposed at runtime as `battleSceneBackground.buoyCurated`)
  overrides all of the above per species: `FORBID` never gets a ring, `FORCE`
  always does. Both are empty by default.

**A missing or unreadable file is never fatal** — `background.lua` logs one
warning and falls back to the built-in primitive ring.

## Adding your own buoy

1. Save a **wide, flat** PNG in here named `lifebuoy.png` (`buoy.png`,
   `life-ring-2.png` … all work) — about **2.8:1**, ring centred, transparent
   background, drawn at the tilt shown above.
2. That's it — it is picked up for every water battle. Restart the game (the
   folder is scanned once at load).

Do **not** add art ripped from a commercial game — this project's static gate
rejects ROM-derived content. Keep any third-party art's author and licence
recorded alongside it.
