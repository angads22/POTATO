# SLICE IT! — Visual Design Plan

The game's look: a **warm cartoon kitchen**. Chunky flat-shaded shapes, soft
shadows, gold accents. Everything is drawn procedurally (polygons, gradients,
StyleBox panels) so the game looks finished from a clean clone with zero
binary assets — and any sprite can later replace its procedural stand-in
without touching game logic.

## Art direction

- **Palette:** cream tile wall, walnut counter, butcher-block cutting board,
  potato golds and browns. UI panels are dark walnut with gold text.
- **Shapes:** rounded, lumpy, friendly. No hard pixel edges.
- **Motion is the polish:** idle bobs, knife chops, popups, screen shake and
  particles do the work that static art normally would.

## Scene composition (gameplay)

```
┌──────────────────────────────────────────────┐
│ ♥♥♥   Championship · Stage 2     Score 4 200 │  ← HUD (CanvasLayer, panels)
│                COMBO x7                      │
│   cream tile wall                            │
│                  ╔═ cleaver ═╗               │  ← KnifeVisual: hovers, chops
│   ──────────────╨────────────╨─────────────  │
│   walnut counter                             │
│        ╭──── cutting board ────╮             │
│        │       (potato)        │             │  ← PotatoVisual + particles
│        ╰───────────────────────╯             │
│      [========= timing track =========]      │  ← minigame visuals
│            [SPACE] Slice at the centre!      │
└──────────────────────────────────────────────┘
```

## Layering rules

- `KitchenBackground` is added with `z_index = -1` so it always sits behind
  the owning scene's own `_draw()`.
- The HUD lives on a `CanvasLayer` (layer 10) so it renders above everything
  and is immune to the playfield screen shake.
- Minigames are ordinary children between the two.

## Phase 1 — implemented

- **KitchenBackground** — gradient tile wall, plank counter, rounded
  butcher-block board with drop shadow (StyleBoxFlat). Shared by menu,
  gameplay and game-over scenes.
- **KnifeVisual** — procedural cleaver (blade, edge highlight, rivets,
  wooden handle) hovering above the potato in counter-phase to its bob;
  `chop()` swings it down through the cut and back.
- **Fx** — one-shot CPUParticles2D bursts: potato-coloured chunks on a cut,
  gold sparkles on a golden, sickly green puff for rotten outcomes.
  Respects the particles setting.
- **GameHUD** — HUD moved off the playfield onto a CanvasLayer with
  walnut/gold panels: hearts, score+coins panel, growing combo, fever
  banner, time-attack clock, popups, stage banners.
- **Title screen** — kitchen backdrop, drop-shadowed title, mascot potato
  with cleaver, menu in a panel.
- Potato gets a ground shadow and outline so it sits *on* the board.

## Phase 2 — implemented

- **Squash-and-stretch** — potatoes drop in from above, land with a squash
  spring, and the ground shadow grows to meet them.
- **PERFECT ring flash** — `RingFx` expanding shock ring on perfect cuts.
- **FEVER pulse** — the wash now breathes, with a pulsing magenta edge
  vignette around the whole screen.
- **Living kitchen** — a garden window with drifting clouds and rolling
  hills, a swaying utensil rail (spatula, ladle, whisk), and a pot
  simmering steam on the counter.

## Phase 2.5 — Spudling Acres and the town (implemented)

Two walkable maps in `scripts/world/` share a `WorldController` (movement,
camera, input routing, prompts, popups) and a `WorldHUD` (everything drawn on
screen). Same procedural-first rules as the kitchen, in a sunnier palette.
Every visual reads the farm through `FarmEconomy` / `FarmView`, so a balance
change in `farm.json` (prices, grow times, plots per field, the field layout)
never needs an art change.

### Layering

- World (`Node2D`, follows the camera): the backdrop (`FarmBackground` /
  `TownBackground`, `z_index = -1`) → the field nodes (`FarmField`) → the
  player (`FarmerVisual`, `z_index = 2`) → critters and fireflies
  (`FarmCritters`, `z_index = 3`).
- Night tint: a `CanvasLayer` (layer 5) between the world and the HUD.
- HUD: a `CanvasLayer` (layer 10) holding `FarmHud` / `WorldHUD`, which also
  draws the Farm Book drawer (`FarmBook`), the knife stand and Pip's note.
- Every clickable thing registers a `HitRegions` target while it is drawn,
  padded to at least 44 px (the trackpad rule: nothing needs a drag,
  double-click, right-click or hover). The last one drawn wins, so draw order
  is click order.

### The farm

- **FarmBackground** — a farmyard strip across the top (the farmhouse, the
  well, the pond with lily pads and fireflies at night, a kitchen garden, hay
  bales, a tree line), one dirt path dividing the yard from the fenced fields,
  and the east gate signposted to town. The farmhouse has four art tiers
  (Cabin, Cottage, House, Manor) that follow the farmhouse upgrade, and Prize
  Strain ribbons hang on its wall. The fence sockets and their sprinklers
  (tripods with sweeping spray arcs) sit in the gaps between fields. Field,
  Greenhouse and socket geometry come from `farm.json` through `FarmView`.
- **FarmField** — one node per field slot (six fields and the Greenhouse):
  the fence, the plots from `FarmEconomy.field_view` (empty soil, growing
  stages, ripe potatoes that bob with a "harvest me" ring), the Greenhouse
  glass, FOR SALE stakes on an unowned slot, the hut with its Spudling's name
  (and "z z" while they nap), a droplet on a watered field and a star on a
  crop planted on its Market Favorite day. It redraws only when its stage
  bucket changes; the ripe potatoes and ring are child layers moved by their
  transform, so a ripe field costs no redraws while it bobs.
- **FarmCritters** — the butterfly (flutters over its field, lands on plots so
  a trackpad can catch it, a gold trail and a countdown ring), the Spudlings
  at their hut doors (waving while you're here, hopping about their field
  while they work, out of sight while they nap) and the coin pops that float
  up from each plot after a tend (stars are drawn, the font has none).
- **FarmerVisual** — a potato in a chef's toque: a walk hop, idle breathing,
  a direction flip, and a little hoe swing whenever it tends, catches or
  clicks something, so a click at any distance still reads as the farmer
  doing it.
- **FarmHud** — the wallet (rolling) with "here ~X/min · away ~Y/min", the
  Next Goal card (label, progress bar, ETA, a Q hint; click to buy), chips
  for the Market Favorite, an active Bumper and a "Butterfly!" target with
  its countdown ring, four drawn icon buttons (sound, zoom, book, menu), the
  bottom bar (Tend All, which reads "Collect" after "Change plans first",
  Farm Book, Zoom, Sound, Menu), and a screen-space sign over every field
  (crop and time left, a bouncing RIPE!, "+ plant", FOR SALE and its price,
  the hut badge, the Favorite star, the droplet). The butterfly gets a catch
  target, or an edge arrow while it is off screen; neither ever covers the
  drawer, the prompt or the bottom bar. Sprinkler arrange mode dims the goal,
  the Book and Tend All and draws a target on every fence socket.
- **Pip's note** — the only modal: a parchment card after an absence (who
  picked how many baskets, a coin line that counts up, the shift and the nap,
  what is ripe, the Catalog page), with [Collect] and [Change plans first].
- **FarmBook** — the right-hand drawer: the Farm Book (Land, Helpers, Tools,
  Soil & Strains, Catalog, Stats; every row shows its cost, "+X/min here ·
  +Y/min away" and a payback, with [Buy] and [Pin]) and the field card (the
  plan picker with each crop's "ready at" time, the Spudling line, the
  sprinkler line, Tend and Replant now, whose first click turns it into a
  full-width orange "Uproot …? Click again" button).
- **Zoom** — overview (the whole farm) and follow (close on the farmer),
  eased; Z, the wheel, a two-finger scroll or a pinch switch between them.
- **Redraw on change** — the HUD repaints when its signature changes, at the
  rate an animation needs, and otherwise at a low idle rate; while you're
  away the backdrop, the Spudling chores and rare-crop sparkles slow down
  further. A farm left open in class stays cheap.

### The town

- **TownBackground** — a cobbled plaza with an animated fountain, the
  championship kitchen at the head of the square, the seed stall and the tool
  shed (storefronts that open the Farm Book on its Catalog and Tools tabs;
  they sell nothing extra), the knife stand, two cottages, lamp posts that
  glow at night, the Concert Hall bandstand (marquee bulbs chasing and a
  potato band bobbing in time with the town's music) and the farm gate in the
  west hedge.
- **Town HUD** — the wallet, the icon buttons and the bottom bar (Farm Book,
  Zoom, Sound, Menu); in overview the stalls get readable tags (Seeds ·
  Catalog, Knife stand, Tool shed) that act like a click on the stall; the
  knife stand overlay lists every knife with its score multiplier and its
  price, Chef-XP gate, owned or EQUIPPED state.

### Shared

- **Night** — the real local clock drives `night01`: a capped tint (the farm
  never goes dark), warm windows and lamps at dusk, and fireflies by the
  farm pond.
- **Popups and banners** — popups rise in fixed slots (refusals in orange
  with a soft buzz; a repeat restarts instead of stacking) and a banner marks
  a Catalog page, the Greenhouse or a farmhouse upgrade.

## Phase 3 — implemented

- **Boss fight** — the Colossal Spud: oversized potato with an HP bar and
  cracked-skin states.
- **Motion on the beat** — the potato's bob, the hovering cleaver, the
  utensil rail and the menu title all move with the music's beat clock;
  the timing track's frame breathes on each beat and four beat lamps under it
  mark the bar (the gold one is the beat to cut on).
- **The concert stage** — Concert mode reuses the tier-6 kitchen (bunting,
  crowd, spotlights) as a venue, with a conveyor belt whose slats tick past
  in time and potatoes, sweet-potato ribbons and rotten spuds drawn in code.
- **Results** — a score count-up and a stamped S–D grade.

## Phase 4 — next

- A farm palette that follows the real month.
- Weather on the farm (purely visual unless the design adds a rule for it).
- Decorate-your-farm unlocks (scarecrow, gnome, fancy fences).
- More town buildings (the Concert Hall is the template).

## Phase 5 — asset swap (optional)

Every visual is one node class. To move to drawn sprites later, replace the
`_draw()` body of that class with a `Sprite2D`/`AnimatedSprite2D` — call
sites and game logic don't change.

## Status checklist

- [x] Kitchen backdrop, knife, FX, HUD, title screen (Phase 1)
- [x] Squash-and-stretch, PERFECT ring, FEVER pulse, living kitchen (Phase 2)
- [x] Spudling Acres: farmyard backdrop with the four farmhouse tiers and
      Strain ribbons, six fenced fields and the Greenhouse, huts and
      Spudlings, sprinklers on fence sockets, butterflies, coin pops
- [x] Farm HUD: wallet with here/away rates, Next Goal card and chips, icon
      buttons, bottom bar, field signs, butterfly target and edge arrow,
      sprinkler arrange mode
- [x] Pip's note, the Farm Book drawer and the field card
- [x] Overview / follow zoom by key, wheel, two-finger scroll and pinch
- [x] Town: plaza, kitchen, seed stall and tool shed storefronts, knife stand
      overlay, Concert Hall bandstand, overview stall tags
- [x] Real-clock night on both maps; low-power redraws while idle or away
- [x] Boss, motion on the beat, the concert stage, results (Phase 3)
- [ ] Farm palette that follows the real month (design pillar; not built)
- [ ] Weather on the farm
- [ ] Decorate-your-farm unlocks (scarecrow, gnome, fancy fences)
- [ ] More town buildings (the Concert Hall is the template)
- [ ] Optional sprite swap (Phase 5)
