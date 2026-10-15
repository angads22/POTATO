# Physics Quest 12

A Prodigy-style role-playing game for **Grade 12 Physics in Canada**, built around the
Ontario **SPH4U** course. You explore a world map, run into monsters, and cast spells by
solving physics problems. Right answers hit hard. Wrong answers fizzle, but you always see
a worked, step-by-step solution, and the mistake is saved to a journal you can review.

It is a separate app from the potato game in this repository and shares no code with it.
It runs in any modern browser, on phones too, with no install, no account and no network.

## Play

- **Single file:** run `python3 physics-quest/build.py`, then open
  `physics-quest/dist/PhysicsQuest12.html` in a browser. It works offline.
- **From source:** open `physics-quest/index.html` directly.

Progress saves in the browser. Settings can export a save code to move to another device.

## How it plays

- **Five regions, one per course unit.** Each region has wandering monsters and a guardian
  boss. Beating the guardian opens the gate to the next region, unlocks a stronger
  *mastery spell* for that unit, and gives you a pet that strikes after each correct answer.
- **Battles.** Pick a spell, then answer its question. Spells from the region's own unit
  are super effective. A streak of correct answers builds *Momentum* for extra damage.
  Using the formula hint makes a spell weaker.
- **Questions are generated, not memorised.** Every numeric question draws fresh values,
  so retrying a skill gives a new problem. Wrong choices come from real mistakes, such as
  forgetting to convert cm to m, using the surface radius instead of the orbital radius,
  or dropping the square root.
- **Built-in calculator and constants.** Trig works in degrees. Typed answers accept
  `3.4e-19`, `3.4 x 10^-19` or an expression like `2*9.8*15`.
- **Answer styles.** Multiple choice, typed answers within 2%, or a mix where harder
  numeric questions must be typed.
- **Adaptive practice.** Questions favour the skills you get wrong most.
- **The Library (Codex).** Practise any single skill, take 10-question unit tests, read the
  formula sheet, review your mistake journal, and see accuracy per unit. You can practise
  any unit at any time, even one you haven't reached in the game.
- **Study mode.** A setting lets you battle with every unit's spells from the start, for
  students whose class is ahead of their game progress.

## Curriculum coverage

There are 74 randomized numeric skills and 60 concept questions.

| Unit (SPH4U strand) | Region | Skills |
|---|---|---|
| Dynamics | Dynamo Dunes | Kinematics, projectiles, Newton's laws with friction, inclines, Atwood machines, apparent weight, centripetal force and acceleration, vertical loops, banked and flat curves, relative velocity, forces in two dimensions |
| Energy and Momentum | Momentum Mines | Work, kinetic and potential energy, Hooke's law, springs, power, momentum, impulse, inelastic, elastic and two-dimensional collisions, ballistic pendulum, friction losses |
| Gravitational, Electric and Magnetic Fields | Field Fortress | Universal gravitation, field strength, orbits, Kepler's third law, escape speed, gravitational potential energy, Coulomb's law, electric fields, parallel plates, accelerating charges, Millikan's experiment, magnetic forces on wires and charges, circular paths, fields around wires, velocity selectors |
| The Wave Nature of Light | Prism Peaks | c = fλ, refraction and critical angle, two-source interference, Young's double slit, gratings, single slits, thin films, anti-reflection coatings, air wedges, polarization |
| Revolutions in Modern Physics | Quantum Quasar | Photon energy and momentum, photoelectric effect, threshold frequency, stopping potential, de Broglie wavelength, time dilation, length contraction, mass–energy, muon decay, relativistic momentum, photon counts, the Standard Model |

Notation follows Ontario textbooks, including ε for electric field strength. Constants are
given to three significant figures, for example g = 9.80 m/s² and e = 1.60 × 10⁻¹⁹ C.

## Development

No build step and no dependencies. `questions.js` holds every question generator and the
calculator and loads in Node and the browser. `game.js` is the game. `index.html` holds
the layout and styles.

```sh
node physics-quest/tools/check_questions.js          # -> QUESTIONS OK
python3 physics-quest/build.py                       # -> physics-quest/dist/PhysicsQuest12.html
node physics-quest/tools/smoke.js physics-quest/dist/PhysicsQuest12.html   # -> PHYSICS QUEST SMOKE OK
```

- **`check_questions.js`** generates 400 instances of every skill. It checks each answer
  against a separately written reference formula and a few textbook results. It also checks
  that the four choices are distinct, that typing the answer is accepted, and that typing
  any wrong choice is rejected.
- **`smoke.js`** plays the game in headless Chromium, in a landscape and a phone viewport.
  It needs `npm i playwright`. It covers a won battle, a wrong answer, typed answers, a
  boss and its gate, Codex practice, a unit test, the shop and reloading a save.

To add a skill, add an `S(id, unit, tier, name, gen)` entry in `questions.js`. The
generator returns the givens, the answer, wrong answers from real mistakes, and solution
steps. Then add its reference formula to `REF` in `tools/check_questions.js`. Concept
questions are rows in `CONCEPTS`.

The `physics-quest.yml` workflow runs all three steps on every change under `physics-quest/`.
