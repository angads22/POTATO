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

## Phase 2.5 — the farm (implemented)

A second biome: the **open-world potato farm** (`scripts/world/`). Same
procedural-first rules, sunnier palette:

- **FarmBackground** — 2560×1440 pasture with mown stripes, swaying grass
  tufts, flowers, dirt paths, a fenced plot field, farmhouse with chimney
  smoke, the championship kitchen building, market/seed/knife stands with
  scalloped awnings, a stone well, and a shimmering pond with lily pads.
  Geometry constants double as the collision/interaction source of truth.
- **Day-night cycle** — `FarmController.day_t` drives a tint overlay
  (CanvasLayer between world and HUD), building windows that warm up at
  dusk, and fireflies by the pond at night. The HUD has a sun/moon dial.
- **FarmerVisual** — chef-potato player: walk hop, direction flip, idle
  breathing, watering can in hand when it's filled.
- **FarmPlot** — soil bed (darker when watered), sprout→bush growth stages,
  pulsing harvest ring, variety-coloured potatoes peeking out; golden crops
  glint.
- **FarmHUD** — wallet + water panel, seed/spud inventory, interaction
  prompt, shop overlays (seeds, market, knives, plant picker).

## Phase 3 — next

- Shop scene in the kitchen: knife rack on the wall from `knives.json`.
- Boss fight: oversized potato with HP bar and cracked-skin states.
- Weather on the farm (rain that waters every plot).
- Decorate-your-farm unlocks (scarecrow, gnome, fancy fences).

## Phase 4 — asset swap (optional)

Every visual is one node class. To move to drawn sprites later, replace the
`_draw()` body of that class with a `Sprite2D`/`AnimatedSprite2D` — call
sites and game logic don't change.
