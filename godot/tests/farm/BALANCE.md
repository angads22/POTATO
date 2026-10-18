# Spudling Acres balance report (phase B1)

This is the evidence behind `resources/game_data/farm.json`. Every number below comes from the balance
simulator, which plays the real `scripts/farm/FarmEconomy.gd` on the shipped `farm.json` with the
profile players of design §6.1 (`tests/farm/FarmBot.gd`). `tests/FarmBalanceTest.gd` is the CI gate.

**Status:** `FarmBalanceTest` prints `FARM BALANCE OK` in 57.6 s locally (budget 90 s). The full-length
report (`farm_sim --all`) passes everything except two diversity assertions that knob tuning cannot
reach, SD3's full clause and SD9. See [Open items](#open-items-for-the-lead).

## How to re-run the simulator

All commands run from `godot/`. The autoloads still start, so point `XDG_DATA_HOME` at a scratch
directory if you don't want a `user://` folder created.

```sh
# CI gate: tables, then "FARM BALANCE OK" or "FARM BALANCE FAIL: <n> failures" (exit code 1)
godot --headless --path . res://tests/FarmBalanceTest.tscn --quit-after 6000

# Full report: §6.3 milestones at full length (active 22 sessions, class 24 days, casual 22 days),
# the time-to-each-upgrade table, per-day tables, §6.2 feel, FEEL+, SD1-SD9 (SD3 is 5 x 4 x 14 days),
# invariants, bankroll, veteran, 60-day magnitudes. About 95 s.
godot --headless --path . -s tests/farm/farm_sim.gd -- --all [--only main,feel,feelplus,sdfix,sd4,sd3,sd5,sd8,sd9,inv,bank,vet,mag]

# One player, with a purchase log (payback, here/away gain, typical absence) and a per-day table
godot --headless --path . -s tests/farm/farm_sim.gd -- --profile class --days 14 --log [--strategy roi|s1|s2|s3|s4|h1|tutorial] [--planting greedy|naive|fixed:<crop>] [--wallet 10000]

# Try a knob without editing farm.json (deep-merged; arrays replace whole)
godot --headless --path . -s tests/farm/farm_sim.gd -- --all --override '{"soil": {"growth": 1.30}}'
```

`--ci` prints exactly the FarmBalanceTest set. Each run is deterministic: stars, butterflies and the
Market Favorite come from the farm's own xorshift seed, which is fixed by the start time.

## What changed in phase B (every knob, old → new, and why)

Knobs inside the design §5.15 ranges:

| Knob | Design | Now | Range | Why |
|---|---|---|---|---|
| `deeds[0]` (Field 2) | 100 | **50** | ×0.5–×2 | First-session rhythm: Field 2 lands at 0:45 alongside Pip, so the tutorial trace has a buy every 1–3 min (B1 WIP). |
| `huts.costs[1]` (Hut 2) | 200 | **100** | ×0.5–×2 | Same: Hut 2 at 2–5 min instead of ~7 min (B1 WIP). |
| `strains.mult` | 1.5 | **1.25** | 1.25–1.5 | Lead ruling 3, the Strain feedback loop. At ×1.5, Spudlings cycling Yukon on Strain III owned the active night (hand share 41% against 89% calibrated). At ×1.25, with Strain rows priced from the harvest mix, active late-game hand share is 85–87% (B1 WIP). |
| `soil.growth` / `soil.mult` | 1.32 / 1.05 | **1.28 / 1.045** | 1.25–1.40 / 1.03–1.06 | Soil comes in smaller, more frequent steps on the same value-per-coin curve: the exponent ln(mult)/ln(growth) is 0.178 against 0.176. Over 22–24 days that is 5–7 more purchases per profile, no purchase-free calendar day before day 14 on any profile (there was one on each), and unchanged income (±2%) and milestones. Soil levels read higher than the calibration's (L43/L47 against L40/L44 at d14/d21) because each level is worth a little less. Tested and rejected: 1.30/1.05 and 1.25/1.04 (the first active half hour gets a 7½-minute gap), and 1.36, 1.40 or base 200 (income −25% to −35%, and SD9 does not move). |
| `house.costs[1]` (Cottage 4 h) | 800 | **500** | ×0.5–×2 | The Cottage was the only 8× price jump in the first active half hour. Saving for it cost two to three harvests (5–7 min gaps on 2 of 5 start days). At 500 c the longest gap is ≤ 5:30 on 5 starts and 4:57 on the CI start. |

Structural changes (outside §5.15, each the smallest change that met a ruling or target):

| Change | Where | Why |
|---|---|---|
| **Your-crop grace** (`clock.your_crop_grace_s` = 600) | `_settle_hut`, `_away_eval`, FarmBot | Phase-B task, design D3/D5: class should be hand-led by day. Without it, a class player's 14 m Red planted at a check-in was picked by the Spudlings 0–60 s before the next bell, and the field then ran as a Spudling chain all day. Now a crop that was in the ground when you left waits **min(grace, its grow time)** after it ripens before the Spudlings pick it; their own replants have no grace. Effects: class by day is hand-harvested at every bell (class hand share at d14 is 86%, up from 26%). The design's Pip demo is intact (+102 c at 08:15, design ≈ +96), because Russet's grace is only its 40 s grow time; a flat 600 s grace for every crop gave +42 c. Every invariant still passes (bulk == stepped, shift cap, hut safety worst +0.000, plus the new check 5b). The grace is closed form (`p1 = max(ripe + min(grace, grow), w0) + P`) and depends only on the stored field and the last input. |
| Grace is min(grace, grow) and covers every standing crop, not only `by == "you"` | `_settle_hut` | First tried as the lead suggested: a flat 600 s, `by == "you"` only. The flat grace stalled Spudling cycling of short crops in the 14-minute class gaps. Pip's demo fell to +42 c, class page 2 slipped to 11:00 (the window edge) and 24-day class income fell 10% (85.3M against 95.6M). Both changes were then made together: capping the grace at the crop's grow time keeps short crops cycling, and covering Spudling crops that grew through your visit keeps a field with you after a missed bell (the A3 wage rule already treats those crops as yours). Result: 95.1M, page 2 at 09:15, demo +102 c. |
| First pick of a crop in the ground when you left pays full value **× your star EV** (A3 paid 1.0 × gross) | `_settle_hut`, `_away_params` (B1 WIP) | SD4 casual −7%. Pip picked the overnight Golden at 13:01, two hours before the 15:00 check-in, and the stars were lost (−4,800 c per Golden). With EV, a hut can never pay less than leaving the crop to you, so §5.12.5's design bound (−0.06 of a hand harvest) holds for every crop again; worst case is +0.000. |
| Deeds gated by Catalog pages (`deed_pages` [0, 2, 3, 4, 5]) | `_lock_reason` (B1 WIP) | Lead ruling 1 (bankroll). Land grants arrive with pages, so kitchen money buys land no faster than the Catalog grows. |
| Farm Book priced for your logged schedule | `_schedule`, `_field_away_sched`, `book` (B1 WIP) | Lead ruling 2a/b. Away gain is the length-weighted value over the last 7 days' absences, each with the best crop for that gap. Fewer than 3 logged → `log.default_schedule`; a log younger than 20 h gets one assumed 12 h night. |
| Presence excludes the 120 s clock-in tail | `_note_input` (B1 WIP) | Ruling 2c. Class "here" read 6–7% instead of ≈2%. |
| Strain rows priced from your harvest mix | `_mix_add`, `_mix_rates`, `_strain_gain` (B1 WIP) | Ruling 2 / design D10 (a Strain is worth (mult − 1) × f_c of income). New schema key `mix` (today's and yesterday's per-crop harvest milli-coins, `[you, spud]`). |

Test-side changes (not economy):
- FarmBot models the grace in its planner (`forward_rate`, `_depart_plans`).
- FarmSuite adds invariant 5b (grace), shares the 14-day ROI runs between SD3, SD5 and FEEL+, and runs
  bankroll only as long as page 6 needs (8/7/7 days). Bankroll now *fails* when a page is not reached;
  it used to skip silently.
- `farm_sim --all` prints a time-to-each-upgrade table.

## Milestones (design §6.3), full length

`farm_sim --all`: ROI buyer, greedy crop-for-the-gap planting, fresh start, wallet 50. Active times
show played hours; class and casual show the check-in number.

| Milestone | Active target | Active | Class target | Class | Casual target | Casual |
|---|---|---|---|---|---|---|
| Field 2 | ≤ 5 m | 1 m ✔ | #1–#2 | #1 ✔ | #1–#2 | #1 ✔ |
| First hut (Pip) | ≤ 3 m | 0 m ✔ | #1 | #1 ✔ | #1 | #1 ✔ |
| Page 1, Yukon | 3–10 m | 5 m ✔ | d1 ≤ 09:00 | 08:15 ✔ | d1 ≤ 15:00 | 12:00 ✔ |
| Page 2, Red | 20–60 m | 41 m ✔ | d1 ≤ 11:00 | 09:15 ✔ | d1 | 15:00 ✔ |
| Page 3, Purple | 4–10 h | 4.0 h (d2) ✔ | d1–d2 | d1 12:45 ✔ | d1–d2 | d1 21:00 ✔ |
| Page 4, Fingerling | d2–d4 | d3 ✔ | d2–d4 | d2 ✔ | d2–d3 | d2 ✔ |
| Page 5, King | d3–d6 | d5 ✔ | d3–d5 | d3 ✔ | d2–d5 | d3 ✔ |
| **Page 6, Golden** | 15–30 h | 24 h (d7) ✔ | d3–d7 | d4 ✔ | d3–d7 | d4 ✔ |
| 6th field | d7–d14 | d11 ✔ | d7–d16 | d9 ✔ | d7–d14 | d10 ✔ |
| **Full farm** | d10–d20 | d14 (54 h) ✔ | d12–d24 | d12 ✔ | d10–d20 | d15 ✔ |
| Gold Hoe | d12–d22 | d17 ✔ | — | d16 | d12–d22 | d14 ✔ |
| Soil at d14 / d21 | cal L40/L44 | L43 / L47 | cal L40/L42 | L42 / L48 | cal L40/L44 | L44 / L47 |
| Income on the last day | cal 9.2M (d24) | 5.64M (d22) | cal 5.1M | 7.66M (d24) | cal 9.0M | 6.27M (d22) |
| Hand share, average d15+ | cal 89% | 85% | cal 86% | 54% | cal 61% | 29% |

The CI run is 10 active sessions and 14 days for class and casual, and every judged cell passes. In
that run, active's 6th field, full farm and Gold Hoe and casual's full farm are "open": their windows
run past the end of the run. At full length, active's full farm lands on d14.

## Time to each upgrade

From `farm_sim --all` (same runs as above). Each cell is when the ROI player first owns the item, with
its price.

| Upgrade | Active (played time) | Class (#check-in) | Casual (#check-in) |
|---|---|---|---|
| Field 2 | d1 17:00 (1m) 50 | d1 08:00 #1 50 | d1 09:01 #1 50 |
| Field 3 | d1 17:40 (41m) 1,000 | d1 09:15 #6 1,000 | d1 15:01 #3 1,000 |
| Field 4 | d2 (4.0h) 12.0K | d1 13:30 #23 12.0K | d2 09:01 #6 12.0K |
| Field 5 | d5 (16h) 250K | d4 08:00 #85 250K | d4 09:01 #16 250K |
| Field 6 | d11 (40h) 3.00M | d9 10:15 #234 3.00M | d10 09:01 #46 3.00M |
| Greenhouse | d14 (54h) 6.00M | d12 13:45 #332 6.00M | d15 15:01 #73 6.00M |
| Hut 1 (Pip) / 2 / 3 | 0m / 2m / 55m | #1 / #2 / #8 | #1 / #2 / #3 |
| Hut 4 / 5 | d2 (4h) 25K / d5 (16h) 300K | d2 #29 / d5 #113 | d2 #6 / d4 #18 |
| Hut 6 / 7 | d15 (56h) 3M / — | d14 #365 3M / — | d11 #53 3M / d19 #93 8M |
| Cottage 4h / House 8h / Manor 12h | 15m / 3.1h / d4 (12h) | #3 / #17 / d4 #85 | #2 / #5 / — |
| Share 60% / 70% | d2 (7h) 40K / — | d3 #57 / d13 #337 2M | d2 #8 / — |
| Quick Hands 30s | d4 (12h) 6,000 | d1 #27 | — |
| Copper / Iron / Gold Hoe | 10m / 6.4h / d17 (67h) | #3 / d2 #35 / d16 #444 | #3 / d2 #9 / d14 #66 |
| Sprinkler 1 / 2 / 3 | 7m / 4.5h / d7 (24h) | #3 / d2 #31 / d7 #169 | #2 / d3 #11 / d7 #31 |
| Soil L10 / L20 / L30 | 36m / 3.4h / 11.7h | #7 / #27 / d3 #66 | #4 / d2 #6 / d3 #14 |
| Soil L40 / L45 | d9 (34h) 1.51M / d18 (72h) 5.21M | d8 #202 / d17 #469 | d8 #36 / d16 #80 |
| Strain tiers 1 / 4 / 8 / 12 | 4h / 10h / 24h / 60h | d1 #20 / d3 / d5 / d22 | d1 #5 / d2 / d9 / — |

The paths differ in the later game. Casual automates (all 7 huts, never the Manor: its King chains
fit inside an 8 h shift) and never buys Quick Hands or the 70% share. Class buys the 70% share and
the Manor and stops at 6 huts. Active stops at 6 huts and is hand-led late (85%).

## Feel

§6.2 targets (CI):

| Target | Window | Result |
|---|---|---|
| First coins | ≤ 45 s | 0:45 ✔ |
| First Spudling (Pip) | ≤ 2 min | 0:45 ✔ |
| Purchases in the first 15 active minutes (tutorial player) | ≥ 6, no gap > 5 min | 7, max gap 4:31 ✔ (0:45 Pip, 0:45 Field 2, 2:15 Copper, 4:30 Hut 2, 7:28 Sprinkler, 10:28 Soil ×2) |
| Class day 1: check-ins with something useful affordable (payback < 1 day) | ≥ 75% | 22/28 = 79% ✔ |
| Class: first check-in after Pip shows Spudling coins | yes | 08:15, +102 c ✔ (design ≈ +96) |
| Active : away per field-minute (SD7) | 1.5–2.5× | active 2.43×, class 1.83× ✔ |

The lead's play-feel judgments (FEEL+):

| Judgment | Result |
|---|---|
| A purchase every 1–3 min in the first active half hour | 14 purchases, one per 2.1 min, longest wait 4:57 ✔ (asserted in CI) |
| Every class check-in on day 1 has something worth doing | 28/28 have a harvest, Pip's coins or a purchase ✔ (asserted) |
| No multi-day droughts | To d14: longest wait active 23 h, class 1 d 5 h, casual 1 d. No purchase-free calendar day on any profile ✔. After the farm is complete (d17+), only Soil and Strains are left; the longest waits are 1 d 20 h (active), 2 d (class) and 1 d 18 h (casual), one dry calendar day each (see [Open items](#open-items-for-the-lead)). |
| Income keeps rising late | No 4-day window below the previous 4 days on any profile. d16→d22: active 3.6M→5.6M, casual 4.8M→6.3M; class d18→d24: 6.5M→7.7M ✔ |
| No single crop dominates every profile | SD1 day crops Yukon / Red / Fingerling / Red. SD2: best single crop 77% of greedy (Fingerling, casual) ✔ |
| No single strategy dominates every profile | ✘ in substance: the Spudling-first build (S2) and the Book reader (S5) are within 0–8% of each other everywhere. See SD3. |
| Huts worth it for casual, not mandatory for class | Late game (SD4 "all", top tiers): casual **+28%**, class **+3%**, active +21% ✔. Over the first 14 days, holding the ROI buyer to one hut costs active −31%, class −27%, casual −28%: before Golden, Spudlings double every profile's night. |

## Diversity (design §6.4)

| ID | Assertion | Result |
|---|---|---|
| SD1 | Day crop differs (active / class / casual) | Yukon / Red / Fingerling (class+eve Red) ✔ |
| SD2 | No single crop ≥ 85% of greedy on 2+ profiles | max 77% ✔; Golden 67 / 58 / 68 / 58% |
| SD3 | Tournament: no strategy within 5% everywhere, winners differ | CI (ruling 4 form) ✔; full clause ✘. See below. |
| SD4 | Hut value ≥ −2% for every profile × stage × tier set | min +0% ✔ (all stage, top tiers: +21 / +3 / +28 / +22%) |
| SD5 | Smart beats naive by ≥ 10% on ≥ 2 profiles (14 days) | +43 / +26 / +37 / +18% ✔ |
| SD6 | Sprinkler value spread ≥ 10 pp | +8 / +0 / +19 / +0%, 19 pp ✔ |
| SD7 | Day:night per field-minute 1.5–2.5× | 2.43× / 1.83× ✔ |
| SD8 | Kitchen minute ≤ 0.5 farm minute, cap 15 | ✔ by formula |
| SD9 | Purchase order tau < 0.8 between profiles, first 3 days | 0.91 / 0.81 / 0.85 ✘ (`--all` only). See below. |

### SD3 in detail

Full tournament, 14 days, net coins earned (`farm_sim --all`):

| Strategy | Active | Class | Casual | Class+eve |
|---|---|---|---|---|
| S1 Hands-on (tools + Soil first, ≤ 1 hut) | 50% | 63% | 62% | 61% |
| S2 Spudling boss (huts, share, shift first) | **100%** | 92% | 100% | 97% |
| S3 Long-crop timer (sprinklers + GH first, ≤ 2 huts) | 57% | 71% | 59% | 64% |
| S4 Soil-only | 2% | 2% | 0% | 2% |
| S5 ROI buyer (reads the Farm Book) | 96% | **100%** | **100%** | **100%** |

CI runs 14 days, not the 7 of design §10.5. At 7 days, S2 scores 95 / 96 / 100% of S5 at the CI
start, so even ruling 4's reduced clause fails: the builds have not diverged yet. 14 days is the
design's own tournament length, and the CI tournament takes 20 s.

CI form (lead ruling 4: three main profiles, S5 out of the within-5% clause, winners asserted): S2 is
not within 5% everywhere (class 92%), and the winners are S2 / S5 / S5. Both clauses pass. In
`--all`, the full clause fails because S5 is within 5% everywhere.

Why S5 stays near the top and why the winner clause is fragile:
- S5 reads the Farm Book, which ruling 2 makes accurate for each player's own schedule, so it is
  near-optimal on every profile by construction. Tested: biasing S2 harder toward helper rows makes
  it *worse*. At weight 0.05 instead of 0.25 it loses on every profile, casual included (−7%); at
  0.1 casual stays within ±0.2%.
- S2's lead over S5 on casual is at most ±1.5%, and the sign changes with the start day. These three
  start days were measured with Soil 1.32, before this phase's Soil change:
  - S2 vs S5 on casual, 3 starts: +1.2 / −1.4 / +0.5%.
  - With S2 limited to huts and shift: +1.5 / +0.3 / +0.6%.
  - The active winner flips the same way: S5 +7% with Soil 1.32, S2 +4% with Soil 1.28.
- The Book-reading player already buys the Spudling build first on every profile. Huts and the cheap
  Cottage/House double every profile's night until Golden arrives (d4 class, d7 active). SD4 at the
  8 h tier, before Golden, is +46% to +360% for every profile.
- The hut caps on S1 and S3 therefore lose 30–50% on every profile in 14 days. A ROI buyer held to
  one hut loses 27–31% everywhere. S3 with greedy instead of naive planting still reaches only
  75–85%.

The design's split shows up in the late game: hand share 85% / 54% / 29%, and late hut value +21% /
+3% / +28% at top tiers. A 14-day tournament from a fresh start is mostly the early game.

### SD9 in detail

Each profile buys about 45 items in its first 3 days, and about 35 of them are Soil levels. The
non-Soil order is nearly identical across profiles: hut, deed, hut, sprinkler, Copper/Cottage,
deed, hut, House, Strain, deed, hut. Three things cause this:
- The cheap early rows are bought as soon as they are affordable, so price order decides the sequence.
- Deeds are page-gated, so they land at the same relative point for everyone.
- The first session (half of the active player's 3-day purchases) prices the Book with the default
  schedule, because active logs only one absence per day.

None of the knobs below moved tau by more than ±0.03:
- Soil growth 1.36 or 1.40, Soil base 200.
- `log.min_absences` 1.
- House ×2.

## Invariants (§5.12) and the rest

- 2 bulk == stepped (480 × 60 s with a JSON round trip): equal at shift 12 h and 2 h ✔.
- 3 shift cap ✔.
- 4 nothing lost ✔.
- 5 hut safety: worst +0.000 hand harvests, against the −0.06 bound ✔.
- 5b grace ✔:
  - A standing Red, Russet or Fingerling is left alone until min(grace, grow) past ripe.
  - The Spudlings' own replant has no grace.
  - A class Red is still yours at the next bell.
- 6 no deadlock ✔.
- 7 performance: 7-day settle 0.5 ms, `book()` 3.3 ms ✔.
- 8 determinism ✔.
- Bankroll (10K start, median of 3 starts; pages may land at most 25% earlier) ✔. Worst cells:
  - Active page 5 −23%: it completes in the d4 session instead of at the d5 arrival. Active pages land on session boundaries, so a one-session gain is 20–25% of the elapsed time.
  - Active page 6 −17%.
  - Casual page 5 −11%.
- Veteran (maxed v3 landing): full farm after 10 days (≥ 3) ✔.
- 60-day class magnitudes:
  - wallet 27.0M, lifetime 411M, last-day income 7.99M, Soil L56.
  - Strains red 2 / purple 3 / fingerling 2 / king 3 / golden 3.
  - No NaN, no overflow ✔.

## Open items for the lead

1. **SD3's full clause (`--all`) fails, and the CI "winners differ" pass rests on near-ties.** In CI,
   the winners are S2 on active by +3.9% and S5 on casual by +0.3%. A later knob change can flip
   either and fail CI with nothing really changed. Three ways to resolve it:
   - (a) Evaluate the clause among S1–S4 only, which also fails today since S2 wins everywhere, so it needs (b) or (c).
   - (b) Run the tournament from a mid-game fixture, where the hands/helpers split of D5 exists.
   - (c) Make early nights less Spudling-dependent. For example, a night crop before page 5. The shift ladder ×2 did not help: one-hut ROI still −23 to −30%.
2. **SD9** needs a structural change to the early purchase options, not knobs.
3. **Long tail.** Each Soil level costs 1.225× more relative to its gain than the last (it was 1.257×
   before this phase). Once the farm is complete (~d16) the only buys are Soil and Strains, and the
   gap between them grows: about 2 days per purchase at d24, and 6 levels between d24 and d60. Options:
   - a further infinite sink;
   - Strain thresholds ×0.5 (tested: class average hand share +3 pp, purchase count unchanged);
   - accept it as the designed long tail ("no prestige").
4. **Income ordering differs from the calibration.** Class (7.7M at d24) out-earns casual (6.3M) and
   active (5.6M at d22). The calibration had 5.1 / 9.0 / 9.2M.
   - Causes: class gets 7 hours of 15-minute cadence plus Spudling chains at night, and the Strain
     loop that carried active's calibration income is gone (ruling 3).
   - Per hand field, class already out-earns active in the design fixture: 34.6K against 29.9K per day.
5. **Hand shares against the calibration:** 85 / 54 / 29% against 89 / 86 / 61%.
   - Class is hand-led by day (86% at d14). Late-game class nights use King or Golden Spudling chains
     on watered fields. The A3 wage rule pays these at full value, which beats a hand Golden night by
     about 10% (40% with a sprinkler).
   - Casual runs King chains on every field all day.
