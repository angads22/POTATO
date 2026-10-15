/* Physics Quest 12 — question engine for the Ontario Grade 12 Physics course (SPH4U).
 *
 * Every numeric skill is a generator: it draws "nice" givens from a seeded RNG,
 * computes the answer from exactly the values shown to the student, and lists
 * wrong answers that come from real mistakes (wrong formula, missed unit
 * conversion, forgotten square root...). makeQuestion() turns that into a
 * four-choice question with a worked solution. Concept skills draw from a
 * hand-written bank. Loads in the browser (window.PQ) and in Node (require).
 */
(function (root) {
  "use strict";

  // ---------------------------------------------------------------- constants
  const C = {
    g: 9.80, G: 6.67e-11, k: 8.99e9, e: 1.60e-19, me: 9.11e-31, mp: 1.67e-27,
    h: 6.63e-34, c: 3.00e8, ME: 5.98e24, RE: 6.38e6, mu0: 4 * Math.PI * 1e-7,
  };
  const CONSTANTS = [
    ["g", "9.80 m/s²", "gravitational field strength at Earth's surface"],
    ["G", "6.67 × 10⁻¹¹ N·m²/kg²", "universal gravitation constant"],
    ["k", "8.99 × 10⁹ N·m²/C²", "Coulomb's constant"],
    ["e", "1.60 × 10⁻¹⁹ C", "elementary charge"],
    ["mₑ", "9.11 × 10⁻³¹ kg", "electron mass"],
    ["mₚ", "1.67 × 10⁻²⁷ kg", "proton mass"],
    ["h", "6.63 × 10⁻³⁴ J·s", "Planck's constant"],
    ["c", "3.00 × 10⁸ m/s", "speed of light"],
    ["μ₀", "4π × 10⁻⁷ T·m/A", "permeability of free space"],
    ["M_Earth", "5.98 × 10²⁴ kg", "mass of Earth"],
    ["r_Earth", "6.38 × 10⁶ m", "radius of Earth"],
    ["1 eV", "1.60 × 10⁻¹⁹ J", "electron-volt"],
  ];

  const UNITS = [
    { id: "dyn", name: "Dynamics", short: "Dynamics", color: "#f08a24" },
    { id: "enm", name: "Energy and Momentum", short: "Energy & Momentum", color: "#2bb673" },
    { id: "fld", name: "Gravitational, Electric and Magnetic Fields", short: "Fields", color: "#8c52ff" },
    { id: "wav", name: "The Wave Nature of Light", short: "Waves & Light", color: "#1aa7ec" },
    { id: "mod", name: "Revolutions in Modern Physics", short: "Modern Physics", color: "#e8458b" },
  ];

  const FORMULAS = {
    dyn: [
      "a = Δv / Δt", "Δd = v₁Δt + ½aΔt²", "v₂² = v₁² + 2aΔd", "Δd = ½(v₁ + v₂)Δt",
      "F_net = ma", "F_g = mg", "F_f = μF_N", "Incline: F_g∥ = mg sinθ,  F_N = mg cosθ",
      "Projectiles: Δx = vₓΔt,  Δy = v_y1Δt − ½gΔt²", "Level-ground range: R = v² sin2θ / g",
      "a_c = v²/r = 4π²r/T²", "F_c = mv²/r", "Banked curve (no friction): tanθ = v²/(rg)",
      "Top of a vertical loop (minimum speed): v = √(gr)",
    ],
    enm: [
      "W = FΔd cosθ", "E_k = ½mv²", "ΔE_g = mgΔh", "F = kx", "E_e = ½kx²", "P = W/Δt = ΔE/Δt",
      "p = mv", "J = FΔt = Δp", "m₁v₁ + m₂v₂ = m₁v₁′ + m₂v₂′",
      "Elastic: v₁′ = (m₁ − m₂)v₁/(m₁ + m₂),  v₂′ = 2m₁v₁/(m₁ + m₂)  (target at rest)",
      "Friction work: W_f = μmgΔd", "Ballistic pendulum: v′ = √(2gh)",
    ],
    fld: [
      "F_g = Gm₁m₂/r²", "g = GM/r²", "Orbit: v = √(GM/r),  T = 2π√(r³/GM)", "v_escape = √(2GM/r)",
      "E_g = −GMm/r", "F_e = kq₁q₂/r²", "ε = kq/r²", "Parallel plates: ε = ΔV/d", "ΔE = qΔV",
      "Millikan: q = mgd/ΔV = Ne", "F_M = qvB sinθ", "F_M = IlB sinθ", "Circular path: r = mv/(qB)",
      "Straight wire: B = μ₀I/(2πr)", "Velocity selector: v = ε/B",
    ],
    wav: [
      "c = fλ", "n = c/v,  λ_medium = λ/n", "n₁ sinθ₁ = n₂ sinθ₂", "Critical angle: sinθ_c = n₂/n₁",
      "Path difference: antinodes mλ,  nodal lines (n − ½)λ",
      "Double slit: Δy = λL/d,  d sinθ = mλ (bright)", "Grating: d sinθ = mλ,  d = 1/(lines per metre)",
      "Single slit: w sinθ = nλ (dark),  central max width = 2λL/w",
      "Thin film (one inversion): dark t = λ/(2n), bright t = λ/(4n)", "Air wedge: Δx = λL/(2t)",
      "Malus: I = I₀ cos²θ,  unpolarized through a filter: I₀/2",
    ],
    mod: [
      "E = hf = hc/λ", "E_k,max = hf − W", "f₀ = W/h", "E_k,max = eV_stop", "p = h/λ",
      "de Broglie: λ = h/(mv)", "γ = 1/√(1 − v²/c²)", "Δt = γΔt₀", "L = L₀/γ = L₀√(1 − v²/c²)",
      "E = mc²", "p = γmv", "Photons per second = P/E_photon",
    ],
  };

  // ---------------------------------------------------------------- helpers
  function hash32(x) {
    x = (x | 0) ^ 0x5bd1e995;
    x = Math.imul(x ^ (x >>> 16), 0x7feb352d);
    x = Math.imul(x ^ (x >>> 15), 0x846ca68b);
    return (x ^ (x >>> 16)) >>> 0;
  }
  function rng(seed) {
    let s = hash32(seed) || 0x2545f491;
    const next = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
    const r = {
      next,
      n(a, b, dp = 0) { const m = Math.pow(10, dp); return Math.round((a + (b - a) * next()) * m) / m; },
      i(a, b) { return a + Math.floor(next() * (b - a + 1)); },
      pick(arr) { return arr[Math.floor(next() * arr.length)]; },
      chance(p) { return next() < p; },
      shuffle(arr) { const a = arr.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(next() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; },
    };
    return r;
  }

  const SUP = { "-": "⁻", "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹" };
  const sup = (n) => String(n).split("").map((ch) => SUP[ch] || ch).join("");

  // A computed result, to `sig` significant figures (scientific notation when large/small).
  function fmt(x, sig = 3) {
    if (!isFinite(x)) return String(x);
    if (x === 0) return "0";
    const a = Math.abs(x);
    if (a >= 1e5 || a < 1e-3) {
      let ex = Math.floor(Math.log10(a));
      let ms = (x / Math.pow(10, ex)).toFixed(sig - 1);
      if (Math.abs(parseFloat(ms)) >= 10) { ex += 1; ms = (x / Math.pow(10, ex)).toFixed(sig - 1); }
      return ms + " × 10" + sup(ex);
    }
    if (a >= Math.pow(10, sig)) return String(Math.round(Number(x.toPrecision(sig))));
    return x.toPrecision(sig);
  }
  // A given value as it appears in a problem (no padding zeros).
  function sv(x) {
    if (x === 0) return "0";
    const a = Math.abs(x);
    if (a >= 1e5 || a < 1e-3) {
      let ex = Math.floor(Math.log10(a));
      let m = Number((x / Math.pow(10, ex)).toPrecision(3));
      if (Math.abs(m) >= 10) { ex += 1; m = Number((x / Math.pow(10, ex)).toPrecision(3)); }
      return String(m) + " × 10" + sup(ex);
    }
    return String(Number(x.toPrecision(6)));
  }
  const ord = (n) => n + (n % 10 === 1 && n % 100 !== 11 ? "st" : n % 10 === 2 && n % 100 !== 12 ? "nd" : n % 10 === 3 && n % 100 !== 13 ? "rd" : "th");
  const D = Math.PI / 180;
  const sind = (a) => Math.sin(a * D), cosd = (a) => Math.cos(a * D), tand = (a) => Math.tan(a * D);
  const asind = (x) => Math.asin(x) / D, atand = (x) => Math.atan(x) / D;
  const sq = (x) => x * x;
  const { sqrt, hypot, abs, PI } = Math;

  // ---------------------------------------------------------------- skills
  const SKILLS = [];
  const SKILL = {};
  function S(id, unit, tier, name, gen) {
    const s = { id, unit, tier, name, gen, concept: false };
    SKILLS.push(s); SKILL[id] = s;
  }

  // ===== Unit B: Dynamics =====================================================
  S("kin_accel", "dyn", 1, "Acceleration", (r) => {
    const v0 = r.i(0, 15), v = v0 + r.i(5, 25), t = r.n(2, 8, 1);
    const a = (v - v0) / t;
    return { p: { v0, v, t }, ans: a, unit: "m/s²", formula: "a = (v₂ − v₁)/Δt",
      prompt: `A cyclist speeds up uniformly from ${v0} m/s to ${v} m/s in ${t} s. What is the magnitude of the cyclist's acceleration?`,
      wrong: [v / t, (v + v0) / t, (v - v0) * t],
      steps: ["a = (v₂ − v₁)/Δt", `a = (${v} m/s − ${v0} m/s)/${t} s`, `a = ${fmt(a)} m/s²`] };
  });
  S("kin_disp", "dyn", 1, "Displacement with constant acceleration", (r) => {
    const v0 = r.i(2, 12), a = r.n(1, 4, 1), t = r.n(2, 6, 1);
    const d = v0 * t + 0.5 * a * t * t;
    return { p: { v0, a, t }, ans: d, unit: "m", formula: "Δd = v₁Δt + ½aΔt²",
      prompt: `A skateboarder moving at ${v0} m/s accelerates uniformly at ${a} m/s² for ${t} s. How far does the skateboarder travel in that time?`,
      wrong: [v0 * t + a * t * t, 0.5 * a * t * t, v0 * t + 0.5 * a * t],
      steps: ["Δd = v₁Δt + ½aΔt²", `Δd = (${v0})(${t}) + ½(${a})(${t})²`, `Δd = ${fmt(d)} m`] };
  });
  S("kin_stop", "dyn", 1, "Stopping distance", (r) => {
    const v0 = r.i(15, 30), a = r.n(3, 7, 1);
    const d = v0 * v0 / (2 * a);
    return { p: { v0, a }, ans: d, unit: "m", formula: "v₂² = v₁² + 2aΔd",
      prompt: `A car travelling at ${v0} m/s brakes with a constant deceleration of ${a} m/s². What is its stopping distance?`,
      wrong: [v0 * v0 / a, v0 / (2 * a), v0 / a],
      steps: ["v₂² = v₁² + 2aΔd, with v₂ = 0 and a negative", "Δd = v₁²/(2|a|)", `Δd = (${v0})²/(2 × ${a})`, `Δd = ${fmt(d)} m`] };
  });
  S("proj_horiz", "dyn", 2, "Horizontally launched projectile", (r) => {
    const h = r.n(1, 40, 1), vx = r.n(2, 15, 1);
    const t = sqrt(2 * h / C.g), dx = vx * t;
    return { p: { h, vx }, ans: dx, unit: "m", formula: "Δy = ½gΔt²,  Δx = vₓΔt",
      prompt: `A ball rolls off a ${h} m high cliff with a horizontal velocity of ${vx} m/s. How far from the base of the cliff does it land? (Ignore air resistance.)`,
      wrong: [vx * sqrt(h / C.g), vx * 2 * h / C.g, dx / 2],
      steps: ["Vertical: Δy = ½gΔt²  →  Δt = √(2Δy/g)", `Δt = √(2 × ${h}/9.80) = ${fmt(t)} s`, "Horizontal: Δx = vₓΔt (vₓ is constant)", `Δx = ${vx} × ${fmt(t)} = ${fmt(dx)} m`] };
  });
  S("proj_range", "dyn", 2, "Projectile launched at an angle", (r) => {
    const v = r.i(10, 30), th = r.pick([20, 25, 30, 35, 40, 50, 55, 60, 65, 70]), variant = r.pick(["R", "H", "T"]);
    const vy = v * sind(th), vx = v * cosd(th);
    const intro = `A ball is kicked from level ground at ${v} m/s, ${th}° above the horizontal.`;
    if (variant === "R") {
      const R = v * v * sind(2 * th) / C.g;
      return { p: { v, th, variant }, ans: R, unit: "m", formula: "R = v² sin2θ / g",
        prompt: `${intro} What is its horizontal range? (Ignore air resistance.)`,
        wrong: [v * v * sind(th) / C.g, R / 2, v * v / C.g],
        steps: [`vₓ = v cosθ = ${fmt(vx)} m/s,  v_y = v sinθ = ${fmt(vy)} m/s`, `Time of flight Δt = 2v_y/g = ${fmt(2 * vy / C.g)} s`, `R = vₓΔt = ${fmt(R)} m  (same as v² sin2θ / g)`] };
    }
    if (variant === "H") {
      const H = vy * vy / (2 * C.g);
      return { p: { v, th, variant }, ans: H, unit: "m", formula: "v_y2² = v_y1² − 2gΔy",
        prompt: `${intro} What maximum height does it reach? (Ignore air resistance.)`,
        wrong: [vy * vy / C.g, v * v / (2 * C.g), sq(vx) / (2 * C.g)],
        steps: [`v_y = v sinθ = ${v} sin${th}° = ${fmt(vy)} m/s`, "At the top v_y = 0:  Δy = v_y²/(2g)", `Δy = (${fmt(vy)})²/(2 × 9.80) = ${fmt(H)} m`] };
    }
    const T = 2 * vy / C.g;
    return { p: { v, th, variant }, ans: T, unit: "s", formula: "Δt = 2v_y/g",
      prompt: `${intro} How long is it in the air? (Ignore air resistance.)`,
      wrong: [vy / C.g, 2 * vx / C.g, 2 * v / C.g],
      steps: [`v_y = v sinθ = ${fmt(vy)} m/s`, "Up and back down to the same height: Δt = 2v_y/g", `Δt = 2 × ${fmt(vy)} / 9.80 = ${fmt(T)} s`] };
  });
  S("newton_friction", "dyn", 1, "Newton's second law with friction", (r) => {
    const m = r.i(5, 40), mu = r.pick([0.15, 0.20, 0.25, 0.30, 0.35]);
    const Ff = mu * m * C.g, F = Math.round(Ff * r.n(1.5, 3, 1));
    const a = (F - Ff) / m;
    return { p: { m, mu, F }, ans: a, unit: "m/s²", formula: "F_net = ma,  F_f = μmg",
      prompt: `A ${m} kg crate is pulled across a level floor by a horizontal force of ${F} N. The coefficient of kinetic friction is ${mu}. What is the crate's acceleration?`,
      wrong: [F / m, (F + Ff) / m, (F - mu * m) / m],
      steps: ["F_f = μF_N = μmg", `F_f = ${mu} × ${m} × 9.80 = ${fmt(Ff)} N`, "a = (F − F_f)/m", `a = (${F} − ${fmt(Ff)})/${m} = ${fmt(a)} m/s²`] };
  });
  S("incline", "dyn", 2, "Inclined planes", (r) => {
    const th = r.pick([20, 25, 30, 35, 40]), mu = r.chance(0.3) ? 0 : r.pick([0.10, 0.15, 0.20, 0.25, 0.30]);
    const a = C.g * (sind(th) - mu * cosd(th));
    return { p: { th, mu }, ans: a, unit: "m/s²", formula: "a = g(sinθ − μcosθ)",
      prompt: mu > 0
        ? `A block slides down a ${th}° incline. The coefficient of kinetic friction is ${mu}. What is the block's acceleration down the slope?`
        : `A block slides down a frictionless ${th}° incline. What is its acceleration down the slope?`,
      wrong: [C.g * (sind(th) + mu * cosd(th)), C.g * sind(th), C.g * cosd(th), C.g * (cosd(th) - mu * sind(th)), C.g * tand(th)],
      steps: ["Along the slope: F_net = mg sinθ − μmg cosθ", "a = g(sinθ − μcosθ)", `a = 9.80(sin${th}° − ${mu} cos${th}°)`, `a = ${fmt(a)} m/s²`] };
  });
  S("atwood", "dyn", 2, "Atwood machine", (r) => {
    const m2 = r.n(2, 6, 1), m1 = Math.round((m2 + r.n(0.5, 4, 1)) * 10) / 10, variant = r.pick(["a", "T"]);
    const a = (m1 - m2) * C.g / (m1 + m2), T = 2 * m1 * m2 * C.g / (m1 + m2);
    const intro = `In an Atwood machine, masses of ${m1} kg and ${m2} kg hang from a light rope over a frictionless pulley.`;
    const base = ["Treat both masses as one system: a = (m₁ − m₂)g/(m₁ + m₂)", `a = (${m1} − ${m2})(9.80)/(${m1} + ${m2}) = ${fmt(a)} m/s²`];
    if (variant === "a") return { p: { m1, m2, variant }, ans: a, unit: "m/s²", formula: "a = (m₁ − m₂)g/(m₁ + m₂)",
      prompt: `${intro} What is the magnitude of the acceleration of the masses?`,
      wrong: [(m1 - m2) * C.g / m1, (m1 - m2) * C.g / m2, C.g], steps: base };
    return { p: { m1, m2, variant }, ans: T, unit: "N", formula: "F_T − m₂g = m₂a",
      prompt: `${intro} What is the tension in the rope?`,
      wrong: [m1 * C.g, m2 * C.g, (m1 - m2) * C.g],
      steps: base.concat(["For the lighter mass: F_T − m₂g = m₂a  →  F_T = m₂(g + a)", `F_T = ${m2}(9.80 + ${fmt(a)}) = ${fmt(T)} N`]) };
  });
  S("elevator", "dyn", 1, "Apparent weight in an elevator", (r) => {
    const m = r.i(50, 90), a = r.n(0.5, 3, 1), up = r.chance(0.5);
    const Fn = m * (C.g + (up ? a : -a));
    return { p: { m, a, up }, ans: Fn, unit: "N", formula: "F_N − mg = ma (up positive)",
      prompt: `A ${m} kg student stands on a scale in an elevator that is accelerating ${up ? "upward" : "downward"} at ${a} m/s². What force does the scale exert on the student?`,
      wrong: [m * (C.g + (up ? -a : a)), m * C.g, m * a],
      steps: ["Take up as positive: F_N − mg = ma", `a = ${up ? "+" : "−"}${a} m/s²`, `F_N = m(g ${up ? "+" : "−"} a) = ${m}(9.80 ${up ? "+" : "−"} ${a})`, `F_N = ${fmt(Fn)} N`] };
  });
  S("centripetal_force", "dyn", 1, "Centripetal force", (r) => {
    const m = r.i(8, 16) * 100, v = r.i(10, 25), rad = r.i(30, 150);
    const F = m * v * v / rad;
    return { p: { m, v, rad }, ans: F, unit: "N", formula: "F_c = mv²/r",
      prompt: `A ${m} kg car rounds a flat curve of radius ${rad} m at ${v} m/s. What is the magnitude of the net (centripetal) force on the car?`,
      wrong: [m * v / rad, v * v / rad, m * v * v / (2 * rad)],
      steps: ["F_c = mv²/r", `F_c = ${m} × ${v}² / ${rad}`, `F_c = ${fmt(F)} N`] };
  });
  S("circ_period", "dyn", 2, "Centripetal acceleration from the period", (r) => {
    const rad = r.n(0.4, 2.0, 1), n = r.i(5, 30), t = r.i(4, 30);
    const T = t / n, a = 4 * PI * PI * rad / (T * T);
    return { p: { rad, n, t }, ans: a, unit: "m/s²", formula: "a_c = 4π²r/T²",
      prompt: `A ball on a string moves in a horizontal circle of radius ${rad} m, completing ${n} revolutions in ${t} s. What is the magnitude of its centripetal acceleration?`,
      wrong: [2 * PI * rad / T, 4 * PI * PI * rad / T, sq(2 * PI * rad / T)],
      steps: [`T = Δt/N = ${t}/${n} = ${fmt(T)} s`, "a_c = 4π²r/T²", `a_c = 4π²(${rad})/(${fmt(T)})² = ${fmt(a)} m/s²`] };
  });
  S("loop_top", "dyn", 2, "Vertical circles", (r) => {
    const rad = r.n(5, 25, 1);
    const v = sqrt(C.g * rad);
    return { p: { rad }, ans: v, unit: "m/s", formula: "mg = mv²/r at the minimum speed",
      prompt: `A roller-coaster loop has a radius of ${rad} m. What is the minimum speed a cart must have at the top of the loop to stay on the track?`,
      wrong: [sqrt(2 * C.g * rad), C.g * rad, sqrt(5 * C.g * rad)],
      steps: ["At the minimum speed the track pushes with zero force, so gravity alone is the centripetal force", "mg = mv²/r  →  v = √(gr)", `v = √(9.80 × ${rad}) = ${fmt(v)} m/s`] };
  });
  S("banked", "dyn", 3, "Banked curves", (r) => {
    const rad = r.i(50, 300), th = r.pick([10, 12, 15, 18, 20, 25, 30]);
    const v = sqrt(rad * C.g * tand(th));
    return { p: { rad, th }, ans: v, unit: "m/s", formula: "tanθ = v²/(rg)",
      prompt: `A curve of radius ${rad} m is banked at ${th}°. At what speed can a car take the curve with no friction needed?`,
      wrong: [sqrt(rad * C.g * sind(th)), sqrt(rad * C.g / tand(th)), rad * C.g * tand(th)],
      steps: ["The horizontal component of F_N provides F_c: F_N sinθ = mv²/r, and F_N cosθ = mg", "Divide: tanθ = v²/(rg)  →  v = √(rg tanθ)", `v = √(${rad} × 9.80 × tan${th}°) = ${fmt(v)} m/s`] };
  });
  S("flat_curve_mu", "dyn", 2, "Friction on a flat curve", (r) => {
    const v = r.i(12, 28), mut = r.n(0.25, 0.85, 2);
    const rad = Math.max(10, Math.round(v * v / (C.g * mut) / 5) * 5);
    const mu = v * v / (C.g * rad);
    return { p: { v, rad }, ans: mu, unit: "", formula: "μmg = mv²/r",
      prompt: `A car rounds an unbanked curve of radius ${rad} m at ${v} m/s. What is the minimum coefficient of static friction needed so the car does not skid?`,
      wrong: [v / (C.g * rad), v * v / rad, C.g * rad / (v * v)],
      steps: ["Static friction is the centripetal force: μmg = mv²/r", "μ = v²/(gr)", `μ = ${v}²/(9.80 × ${rad}) = ${fmt(mu)}`] };
  });
  S("river_boat", "dyn", 2, "Relative velocity (river crossing)", (r) => {
    const w = r.i(40, 200), vb = r.n(2, 6, 1), vw = r.n(1, 4, 1), variant = r.pick(["time", "drift"]);
    const t = w / vb, drift = vw * t;
    const intro = `A boat that moves at ${vb} m/s relative to the water heads straight across a ${w} m wide river. The current flows at ${vw} m/s.`;
    if (variant === "time") return { p: { w, vb, vw, variant }, ans: t, unit: "s", formula: "Δt = width / v_boat",
      prompt: `${intro} How long does the crossing take?`,
      wrong: [w / hypot(vb, vw), w / vw, w / (vb + vw)],
      steps: ["Only the boat's velocity across the river carries it across; the current is perpendicular", `Δt = ${w}/${vb} = ${fmt(t)} s`] };
    return { p: { w, vb, vw, variant }, ans: drift, unit: "m", formula: "Δt = width / v_boat,  drift = v_current Δt",
      prompt: `${intro} How far downstream of its starting point does the boat land?`,
      wrong: [t, vb * w / vw, vw * w / hypot(vb, vw)],
      steps: [`Crossing time Δt = ${w}/${vb} = ${fmt(t)} s`, `Drift = v_current Δt = ${vw} × ${fmt(t)} = ${fmt(drift)} m`] };
  });
  S("net_force_2d", "dyn", 1, "Forces in two dimensions", (r) => {
    const F1 = r.i(10, 80), F2 = r.i(10, 80), m = r.n(2, 20, 1);
    const a = hypot(F1, F2) / m;
    return { p: { F1, F2, m }, ans: a, unit: "m/s²", formula: "F_net = √(F₁² + F₂²),  a = F_net/m",
      prompt: `Two forces act on a ${m} kg object: ${F1} N east and ${F2} N north. What is the magnitude of its acceleration?`,
      wrong: [(F1 + F2) / m, abs(F1 - F2) / m, hypot(F1, F2)],
      steps: [`F_net = √(${F1}² + ${F2}²) = ${fmt(hypot(F1, F2))} N`, `a = F_net/m = ${fmt(hypot(F1, F2))}/${m} = ${fmt(a)} m/s²`] };
  });

  // ===== Unit C: Energy and Momentum ==========================================
  S("work", "enm", 1, "Work done by a force", (r) => {
    const F = r.i(20, 150), th = r.pick([15, 20, 25, 30, 35, 40, 50, 60]), d = r.n(2, 20, 1);
    const W = F * d * cosd(th);
    return { p: { F, th, d }, ans: W, unit: "J", formula: "W = FΔd cosθ",
      prompt: `A sled is pulled ${d} m across level snow by a rope at ${th}° above the ground. The tension in the rope is ${F} N. How much work does the rope do on the sled?`,
      wrong: [F * d, F * d * sind(th), W / 2],
      steps: ["Only the component of F along the motion does work", "W = FΔd cosθ", `W = ${F} × ${d} × cos${th}° = ${fmt(W)} J`] };
  });
  S("kinetic", "enm", 1, "Kinetic energy", (r) => {
    const m = r.i(8, 20) * 100, v = r.i(5, 30);
    const E = 0.5 * m * v * v;
    return { p: { m, v }, ans: E, unit: "J", formula: "E_k = ½mv²",
      prompt: `What is the kinetic energy of a ${m} kg car moving at ${v} m/s?`,
      wrong: [m * v * v, 0.5 * m * v, m * v],
      steps: ["E_k = ½mv²", `E_k = ½ × ${m} × ${v}²`, `E_k = ${fmt(E)} J`] };
  });
  S("coaster_speed", "enm", 2, "Conservation of mechanical energy", (r) => {
    const h1 = r.i(20, 60), h2 = r.i(5, h1 - 5);
    const v = sqrt(2 * C.g * (h1 - h2));
    return { p: { h1, h2 }, ans: v, unit: "m/s", formula: "mgh₁ = mgh₂ + ½mv²",
      prompt: `A roller-coaster car starts from rest at the top of a ${h1} m hill. Ignoring friction, how fast is it moving at the top of the next hill, which is ${h2} m high?`,
      wrong: [sqrt(2 * C.g * h1), 2 * C.g * (h1 - h2), sqrt(C.g * (h1 - h2))],
      steps: ["E_total is conserved: mgh₁ = mgh₂ + ½mv²  (mass cancels)", "v = √(2g(h₁ − h₂))", `v = √(2 × 9.80 × (${h1} − ${h2})) = ${fmt(v)} m/s`] };
  });
  S("hooke", "enm", 1, "Hooke's law", (r) => {
    const m = r.n(0.2, 3, 1), x = r.i(2, 25);
    const k = m * C.g / (x / 100);
    return { p: { m, x }, ans: k, unit: "N/m", formula: "F = kx",
      prompt: `A ${m} kg mass hung from a vertical spring stretches it by ${x} cm. What is the spring constant?`,
      wrong: [m * C.g / x, m * 100 / x, m * C.g * x / 100],
      steps: ["At rest the spring force balances gravity: kx = mg", `x = ${x} cm = ${sv(x / 100)} m`, `k = mg/x = (${m} × 9.80)/${sv(x / 100)} = ${fmt(k)} N/m`] };
  });
  S("spring_pe", "enm", 1, "Elastic potential energy", (r) => {
    const k = r.i(50, 800), x = r.n(0.05, 0.40, 2);
    const E = 0.5 * k * x * x;
    return { p: { k, x }, ans: E, unit: "J", formula: "E_e = ½kx²",
      prompt: `A spring with a spring constant of ${k} N/m is compressed ${x} m. How much elastic potential energy does it store?`,
      wrong: [k * x * x, 0.5 * k * x, k * x],
      steps: ["E_e = ½kx²", `E_e = ½ × ${k} × (${x})²`, `E_e = ${fmt(E)} J`] };
  });
  S("spring_launch", "enm", 2, "Springs and energy conservation", (r) => {
    const k = r.i(100, 900), x = r.n(0.05, 0.30, 2), m = r.n(0.1, 2.0, 1);
    const v = x * sqrt(k / m);
    return { p: { k, x, m }, ans: v, unit: "m/s", formula: "½kx² = ½mv²",
      prompt: `A ${m} kg block is pushed against a horizontal spring (k = ${k} N/m), compressing it ${x} m, and released on a frictionless surface. How fast is the block moving when it leaves the spring?`,
      wrong: [sqrt(k * x / m), x * k / m, x * sqrt(k / (2 * m))],
      steps: ["All the elastic energy becomes kinetic energy: ½kx² = ½mv²", "v = x√(k/m)", `v = ${x} × √(${k}/${m}) = ${fmt(v)} m/s`] };
  });
  S("power", "enm", 1, "Power", (r) => {
    const m = r.i(50, 90), h = r.n(3, 15, 1), t = r.n(3, 20, 1);
    const P = m * C.g * h / t;
    return { p: { m, h, t }, ans: P, unit: "W", formula: "P = ΔE/Δt = mgΔh/Δt",
      prompt: `A ${m} kg student runs up a flight of stairs ${h} m high in ${t} s. What average power does the student develop against gravity?`,
      wrong: [m * h / t, m * C.g * h * t, m * C.g * h],
      steps: [`ΔE_g = mgΔh = ${m} × 9.80 × ${h} = ${fmt(m * C.g * h)} J`, `P = ΔE/Δt = ${fmt(m * C.g * h)}/${t} = ${fmt(P)} W`] };
  });
  S("momentum", "enm", 1, "Momentum", (r) => {
    const m = r.n(0.05, 0.50, 2), v = r.i(10, 45);
    return { p: { m, v }, ans: m * v, unit: "kg·m/s", formula: "p = mv",
      prompt: `What is the magnitude of the momentum of a ${m} kg ball moving at ${v} m/s?`,
      wrong: [0.5 * m * v * v, m / v, m * v * v],
      steps: ["p = mv", `p = ${m} × ${v} = ${fmt(m * v)} kg·m/s`] };
  });
  S("impulse_force", "enm", 2, "Impulse and average force", (r) => {
    const m = r.n(0.05, 0.60, 2), v1 = r.i(5, 30), v2 = r.i(3, v1), dt = r.n(0.005, 0.050, 3);
    const F = m * (v1 + v2) / dt;
    return { p: { m, v1, v2, dt }, ans: F, unit: "N", formula: "FΔt = mΔv",
      prompt: `A ${m} kg ball hits a wall at ${v1} m/s and rebounds at ${v2} m/s. It is in contact with the wall for ${dt} s. What is the magnitude of the average force on the ball?`,
      wrong: [m * (v1 - v2) / dt, m * v1 / dt, m * (v1 + v2) * dt],
      steps: ["The velocity reverses, so Δv = v₂ − (−v₁) = v₁ + v₂", `Δp = ${m}(${v1} + ${v2}) = ${fmt(m * (v1 + v2))} kg·m/s`, `F = Δp/Δt = ${fmt(m * (v1 + v2))}/${dt} = ${fmt(F)} N`] };
  });
  S("inelastic_1d", "enm", 2, "Perfectly inelastic collisions", (r) => {
    let m1, v1, m2, v2, mode, v;
    do {
      m1 = r.i(8, 20) * 100; v1 = r.i(10, 25); m2 = r.i(8, 30) * 100; mode = r.pick(["rest", "same", "opp"]);
      v2 = mode === "rest" ? 0 : mode === "same" ? r.i(3, v1 - 2) : -r.i(3, 15);
      v = (m1 * v1 + m2 * v2) / (m1 + m2);
    } while (abs(v) < 0.5);
    const other = mode === "rest" ? "at rest" : mode === "same" ? `moving east at ${v2} m/s` : `moving west at ${-v2} m/s`;
    return { p: { m1, v1, m2, v2, mode }, ans: v, unit: "m/s", signed: mode === "opp", formula: "m₁v₁ + m₂v₂ = (m₁ + m₂)v′",
      prompt: `A ${m1} kg car moving east at ${v1} m/s collides with a ${m2} kg truck ${other}. The vehicles lock together. ${mode === "opp" ? "Taking east as positive, what is their velocity just after the collision?" : "How fast are they moving just after the collision?"}`,
      wrong: [(m1 * v1 - m2 * v2) / (m1 + m2), -v, (v1 + v2) / 2, m1 * v1 / (m1 + m2), m1 * v1 / m2],
      steps: ["Momentum is conserved: m₁v₁ + m₂v₂ = (m₁ + m₂)v′", `v′ = (${m1} × ${v1} + ${m2} × ${v2 < 0 ? "(" + v2 + ")" : v2})/(${m1} + ${m2})`, `v′ = ${fmt(v)} m/s${mode === "opp" ? (v > 0 ? " (east)" : " (west)") : ""}`] };
  });
  S("elastic_1d", "enm", 3, "Elastic collisions", (r) => {
    let m1, m2;
    do { m1 = r.n(1, 5, 1); m2 = r.n(1, 5, 1); } while (abs(m1 - m2) < 0.5);
    const v1 = r.n(2, 8, 1), variant = r.pick(["target", "proj"]);
    const intro = `A ${m1} kg cart moving at ${v1} m/s makes a perfectly elastic head-on collision with a ${m2} kg cart at rest.`;
    if (variant === "target") {
      const v = 2 * m1 * v1 / (m1 + m2);
      return { p: { m1, m2, v1, variant }, ans: v, unit: "m/s", formula: "v₂′ = 2m₁v₁/(m₁ + m₂)",
        prompt: `${intro} How fast is the ${m2} kg cart moving after the collision?`,
        wrong: [m1 * v1 / m2, m1 * v1 / (m1 + m2), v1],
        steps: ["Conserve both momentum and kinetic energy; for a target at rest this gives", "v₂′ = 2m₁v₁/(m₁ + m₂)", `v₂′ = 2(${m1})(${v1})/(${m1} + ${m2}) = ${fmt(v)} m/s`] };
    }
    const v = (m1 - m2) * v1 / (m1 + m2);
    return { p: { m1, m2, v1, variant }, ans: v, unit: "m/s", signed: true, formula: "v₁′ = (m₁ − m₂)v₁/(m₁ + m₂)",
      prompt: `${intro} Taking the original direction as positive, what is the velocity of the ${m1} kg cart after the collision?`,
      wrong: [-v, (m1 - m2) * v1 / m1, v1, 2 * m1 * v1 / (m1 + m2)],
      steps: ["Conserve both momentum and kinetic energy; for a target at rest this gives", "v₁′ = (m₁ − m₂)v₁/(m₁ + m₂)", `v₁′ = (${m1} − ${m2})(${v1})/(${m1} + ${m2}) = ${fmt(v)} m/s`, v < 0 ? "Negative: the cart bounces back." : "Positive: the cart keeps going forward, more slowly."] };
  });
  S("collision_2d", "enm", 3, "Collisions in two dimensions", (r) => {
    const m1 = r.n(1, 5, 1), v1 = r.n(2, 10, 1), m2 = r.n(1, 5, 1), v2 = r.n(2, 10, 1), variant = r.pick(["speed", "dir"]);
    const px = m1 * v1, py = m2 * v2, M = m1 + m2;
    const intro = `A ${m1} kg puck moving east at ${v1} m/s collides with a ${m2} kg puck moving north at ${v2} m/s. They stick together.`;
    const base = [`pₓ = ${m1} × ${v1} = ${fmt(px)} kg·m/s (east)`, `p_y = ${m2} × ${v2} = ${fmt(py)} kg·m/s (north)`];
    if (variant === "speed") {
      const v = hypot(px, py) / M;
      return { p: { m1, v1, m2, v2, variant }, ans: v, unit: "m/s", formula: "p′ = √(pₓ² + p_y²),  v′ = p′/(m₁ + m₂)",
        prompt: `${intro} What is their speed just after the collision?`,
        wrong: [(px + py) / M, hypot(v1, v2), hypot(px, py) / m1],
        steps: base.concat([`p′ = √(pₓ² + p_y²) = ${fmt(hypot(px, py))} kg·m/s`, `v′ = p′/(m₁ + m₂) = ${fmt(hypot(px, py))}/${fmt(M)} = ${fmt(v)} m/s`]) };
    }
    const th = atand(py / px);
    return { p: { m1, v1, m2, v2, variant }, ans: th, unit: "° N of E", formula: "θ = tan⁻¹(p_y/pₓ)",
      prompt: `${intro} In what direction do they move after the collision? (Give degrees north of east.)`,
      wrong: [atand(v2 / v1), 90 - th, atand(m2 / m1)],
      steps: base.concat([`θ = tan⁻¹(p_y/pₓ) = tan⁻¹(${fmt(py)}/${fmt(px)}) = ${fmt(th)}° N of E`]) };
  });
  S("ballistic", "enm", 3, "Ballistic pendulum", (r) => {
    const mg = r.i(5, 30), M = r.n(1, 5, 1), hh = r.n(0.05, 0.30, 2);
    const m = mg / 1000, vafter = sqrt(2 * C.g * hh), v = (m + M) / m * vafter;
    return { p: { mg, M, hh }, ans: v, unit: "m/s", formula: "mv = (m + M)v′,  v′ = √(2gh)",
      prompt: `A ${mg} g bullet is fired into a ${M} kg wooden block hanging as a pendulum and embeds in it. The block swings up ${hh} m. How fast was the bullet moving?`,
      wrong: [vafter, (m + M) / m * 2 * C.g * hh, (m + M) / m * sqrt(C.g * hh)],
      steps: ["After the collision, energy is conserved on the swing: v′ = √(2gh)", `v′ = √(2 × 9.80 × ${hh}) = ${fmt(vafter)} m/s`, "During the collision, momentum is conserved: mv = (m + M)v′", `v = (${sv(m)} + ${M}) × ${fmt(vafter)} / ${sv(m)} = ${fmt(v)} m/s`] };
  });
  S("friction_stop", "enm", 2, "Work done by friction", (r) => {
    const v = r.n(2, 12, 1), mu = r.pick([0.05, 0.08, 0.10, 0.15, 0.20, 0.25, 0.30]);
    const d = v * v / (2 * mu * C.g);
    return { p: { v, mu }, ans: d, unit: "m", formula: "½mv² = μmgΔd",
      prompt: `A hockey puck slides across a surface at ${v} m/s. If the coefficient of kinetic friction is ${mu}, how far does the puck slide before stopping?`,
      wrong: [v * v / (mu * C.g), v / (2 * mu * C.g), v * v / (2 * C.g)],
      steps: ["Friction does negative work equal to the lost kinetic energy: μmgΔd = ½mv²", "Δd = v²/(2μg)", `Δd = ${v}²/(2 × ${mu} × 9.80) = ${fmt(d)} m`] };
  });
  S("ke_lost", "enm", 3, "Kinetic energy lost in a collision", (r) => {
    const m1 = r.n(1, 6, 1), v1 = r.n(2, 10, 1), m2 = r.n(1, 6, 1);
    const vf = m1 * v1 / (m1 + m2), Ki = 0.5 * m1 * v1 * v1, Kf = 0.5 * (m1 + m2) * vf * vf;
    return { p: { m1, v1, m2 }, ans: Ki - Kf, unit: "J", formula: "ΔE_k = E_k,before − E_k,after",
      prompt: `A ${m1} kg cart moving at ${v1} m/s collides with and sticks to a ${m2} kg cart at rest. How much kinetic energy is lost in the collision?`,
      wrong: [Ki, Kf, 0.5 * m2 * vf * vf],
      steps: [`Momentum: v′ = m₁v₁/(m₁ + m₂) = ${fmt(vf)} m/s`, `E_k before = ½(${m1})(${v1})² = ${fmt(Ki)} J`, `E_k after = ½(${fmt(m1 + m2)})(${fmt(vf)})² = ${fmt(Kf)} J`, `Lost = ${fmt(Ki - Kf)} J`] };
  });

  // ===== Unit D: Gravitational, Electric and Magnetic Fields ==================
  const PLANETS = [
    { name: "Mars", M: 6.42e23, R: 3.39e6 }, { name: "the Moon", M: 7.35e22, R: 1.74e6 },
    { name: "Jupiter", M: 1.90e27, R: 7.15e7 }, { name: "Venus", M: 4.87e24, R: 6.05e6 },
    { name: "Mercury", M: 3.30e23, R: 2.44e6 }, { name: "Saturn", M: 5.68e26, R: 6.03e7 },
    { name: "Uranus", M: 8.68e25, R: 2.56e7 }, { name: "Neptune", M: 1.02e26, R: 2.48e7 },
  ];
  const ORBITS = [250, 300, 350, 400, 450, 500, 600, 800, 1000, 1200, 1500, 2000, 3000, 5000, 8000, 10000, 15000, 20200, 25000, 35800];
  S("grav_force", "fld", 1, "Universal gravitation", (r) => {
    const m = r.i(5, 50) * 100, hkm = r.pick(ORBITS);
    const rr = C.RE + hkm * 1e3, F = C.G * C.ME * m / (rr * rr);
    return { p: { m, hkm }, ans: F, unit: "N", formula: "F_g = GMm/r²",
      prompt: `A ${m} kg satellite orbits ${hkm} km above Earth's surface. What is the gravitational force Earth exerts on it?`,
      wrong: [C.G * C.ME * m / sq(hkm * 1e3), C.G * C.ME * m / rr, C.G * C.ME * m / sq(C.RE)],
      steps: ["r is measured from Earth's centre: r = r_Earth + h", `r = 6.38 × 10⁶ + ${sv(hkm * 1e3)} = ${fmt(rr)} m`, `F_g = GMm/r² = (6.67 × 10⁻¹¹)(5.98 × 10²⁴)(${m})/(${fmt(rr)})²`, `F_g = ${fmt(F)} N`] };
  });
  S("g_planet", "fld", 2, "Gravitational field strength", (r) => {
    if (r.chance(0.5)) {
      const P = r.pick(PLANETS), g = C.G * P.M / (P.R * P.R);
      return { p: { P: P.name, M: P.M, R: P.R, variant: "surface" }, ans: g, unit: "N/kg", formula: "g = GM/r²",
        prompt: `${P.name[0].toUpperCase() + P.name.slice(1)} has a mass of ${sv(P.M)} kg and a radius of ${sv(P.R)} m. What is the gravitational field strength at its surface?`,
        wrong: [C.G * P.M / P.R, C.g, sqrt(C.G * P.M / P.R)],
        steps: ["g = GM/r²", `g = (6.67 × 10⁻¹¹)(${sv(P.M)})/(${sv(P.R)})²`, `g = ${fmt(g)} N/kg`] };
    }
    const hkm = r.pick([500, 1000, 2000, 5000, 10000, 20000]), rr = C.RE + hkm * 1e3, g = C.G * C.ME / (rr * rr);
    return { p: { hkm, variant: "alt" }, ans: g, unit: "N/kg", formula: "g = GM/r²",
      prompt: `What is the gravitational field strength ${hkm} km above Earth's surface?`,
      wrong: [C.G * C.ME / sq(hkm * 1e3), C.g, C.G * C.ME / rr],
      steps: [`r = r_Earth + h = ${fmt(rr)} m`, `g = GM/r² = (6.67 × 10⁻¹¹)(5.98 × 10²⁴)/(${fmt(rr)})²`, `g = ${fmt(g)} N/kg`] };
  });
  S("orbit_speed", "fld", 2, "Orbital speed", (r) => {
    const hkm = r.pick(ORBITS), rr = C.RE + hkm * 1e3, v = sqrt(C.G * C.ME / rr);
    return { p: { hkm }, ans: v, unit: "m/s", formula: "v = √(GM/r)",
      prompt: `What speed does a satellite need for a circular orbit ${hkm} km above Earth's surface?`,
      wrong: [sqrt(C.G * C.ME / C.RE), sqrt(2 * C.G * C.ME / rr), sqrt(C.G * C.ME / (hkm * 1e3))],
      steps: ["Gravity is the centripetal force: GMm/r² = mv²/r  →  v = √(GM/r)", `r = r_Earth + h = ${fmt(rr)} m`, `v = √((6.67 × 10⁻¹¹)(5.98 × 10²⁴)/${fmt(rr)}) = ${fmt(v)} m/s`] };
  });
  S("orbit_period", "fld", 3, "Orbital period (Kepler's third law)", (r) => {
    const hkm = r.pick(ORBITS), rr = C.RE + hkm * 1e3, T = 2 * PI * sqrt(rr * rr * rr / (C.G * C.ME));
    return { p: { hkm }, ans: T / 3600, unit: "h", formula: "T = 2π√(r³/GM)",
      prompt: `What is the orbital period, in hours, of a satellite in a circular orbit ${hkm} km above Earth's surface?`,
      wrong: [2 * PI * sqrt(sq(hkm * 1e3) * hkm * 1e3 / (C.G * C.ME)) / 3600, T / 60, T / (2 * PI * 3600)],
      steps: [`r = r_Earth + h = ${fmt(rr)} m`, "GMm/r² = m·4π²r/T²  →  T = 2π√(r³/GM)", `T = ${fmt(T)} s`, `T = ${fmt(T)}/3600 = ${fmt(T / 3600)} h`] };
  });
  S("escape", "fld", 3, "Escape speed", (r) => {
    const P = r.pick(PLANETS.concat([{ name: "Earth", M: C.ME, R: C.RE }])), v = sqrt(2 * C.G * P.M / P.R);
    return { p: { M: P.M, R: P.R }, ans: v, unit: "m/s", formula: "½mv² − GMm/r = 0",
      prompt: `What is the escape speed from the surface of ${P.name} (M = ${sv(P.M)} kg, r = ${sv(P.R)} m)?`,
      wrong: [sqrt(C.G * P.M / P.R), 2 * C.G * P.M / P.R, sqrt(C.G * P.M / (2 * P.R))],
      steps: ["To just escape, total energy is zero: ½mv² − GMm/r = 0", "v = √(2GM/r)", `v = √(2(6.67 × 10⁻¹¹)(${sv(P.M)})/${sv(P.R)}) = ${fmt(v)} m/s`] };
  });
  S("grav_pe", "fld", 3, "Gravitational potential energy far from Earth", (r) => {
    const m = r.i(2, 20) * 100, hkm = r.pick([2000, 5000, 10000, 20000, 35800]), rr = C.RE + hkm * 1e3;
    const dE = C.G * C.ME * m * (1 / C.RE - 1 / rr);
    return { p: { m, hkm }, ans: dE, unit: "J", formula: "E_g = −GMm/r",
      prompt: `By how much does the gravitational potential energy of a ${m} kg satellite increase when it is raised from Earth's surface to an altitude of ${hkm} km?`,
      wrong: [m * C.g * hkm * 1e3, C.G * C.ME * m / rr, C.G * C.ME * m / C.RE],
      steps: ["mgh only works near the surface; use E_g = −GMm/r", "ΔE_g = GMm(1/r₁ − 1/r₂)", `r₁ = 6.38 × 10⁶ m,  r₂ = ${fmt(rr)} m`, `ΔE_g = ${fmt(dE)} J`] };
  });
  S("coulomb", "fld", 1, "Coulomb's law", (r) => {
    const q1 = r.n(1, 9, 1), q2 = r.n(1, 9, 1), rcm = r.i(2, 50);
    const F = C.k * q1 * 1e-6 * q2 * 1e-6 / sq(rcm / 100);
    return { p: { q1, q2, rcm }, ans: F, unit: "N", formula: "F = kq₁q₂/r²",
      prompt: `Two point charges of ${q1} μC and ${q2} μC are ${rcm} cm apart. What is the magnitude of the electric force between them?`,
      wrong: [C.k * q1 * q2 * 1e-12 / (rcm / 100), C.k * q1 * q2 * 1e-12 / sq(rcm), C.k * q1 * q2 * 1e-12 / sq(2 * rcm / 100)],
      steps: [`q₁ = ${sv(q1 * 1e-6)} C,  q₂ = ${sv(q2 * 1e-6)} C,  r = ${sv(rcm / 100)} m`, "F = kq₁q₂/r²", `F = (8.99 × 10⁹)(${sv(q1 * 1e-6)})(${sv(q2 * 1e-6)})/(${sv(rcm / 100)})²`, `F = ${fmt(F)} N`] };
  });
  S("e_field_point", "fld", 1, "Electric field of a point charge", (r) => {
    const q = r.n(1, 50, 1), d = r.n(0.05, 0.80, 2);
    const E = C.k * q * 1e-9 / (d * d);
    return { p: { q, d }, ans: E, unit: "N/C", formula: "ε = kq/r²",
      prompt: `What is the magnitude of the electric field ${d} m from a ${q} nC point charge?`,
      wrong: [C.k * q * 1e-9 / d, C.k * q * 1e-6 / (d * d), C.k * sq(q * 1e-9) / (d * d)],
      steps: [`q = ${q} nC = ${sv(q * 1e-9)} C`, "ε = kq/r²", `ε = (8.99 × 10⁹)(${sv(q * 1e-9)})/(${d})² = ${fmt(E)} N/C`] };
  });
  S("e_field_two", "fld", 3, "Net electric field of two charges", (r) => {
    const a = r.n(1, 9, 1), b = r.n(1, 9, 1), d = r.n(0.20, 1.00, 2);
    const E1 = C.k * a * 1e-6 / sq(d / 2), E2 = C.k * b * 1e-6 / sq(d / 2), E = E1 + E2;
    return { p: { a, b, d }, ans: E, unit: "N/C", formula: "ε = kq/r² for each charge, then add as vectors",
      prompt: `A +${a} μC charge and a −${b} μC charge are ${d} m apart. What is the magnitude of the net electric field at the point midway between them?`,
      wrong: [abs(E1 - E2), C.k * (a + b) * 1e-6 / (d * d), E1],
      steps: [`Each charge is r = ${sv(d / 2)} m from the midpoint`, `ε₊ = k(${sv(a * 1e-6)})/(${sv(d / 2)})² = ${fmt(E1)} N/C, pointing away from + (toward −)`, `ε₋ = k(${sv(b * 1e-6)})/(${sv(d / 2)})² = ${fmt(E2)} N/C, pointing toward −`, `Both point the same way, so they add: ε = ${fmt(E)} N/C`] };
  });
  S("plates", "fld", 1, "Parallel-plate fields", (r) => {
    const V = r.i(50, 1500), dmm = r.n(0.5, 5, 1), variant = r.pick(["E", "F"]);
    const d = dmm / 1000, E = V / d;
    const intro = `Two parallel plates ${dmm} mm apart have a potential difference of ${V} V.`;
    if (variant === "E") return { p: { V, dmm, variant }, ans: E, unit: "V/m", formula: "ε = ΔV/d",
      prompt: `${intro} What is the magnitude of the electric field between them?`,
      wrong: [V * d, V / dmm, V / (2 * d)],
      steps: [`d = ${dmm} mm = ${sv(d)} m`, `ε = ΔV/d = ${V}/${sv(d)} = ${fmt(E)} V/m`] };
    return { p: { V, dmm, variant }, ans: C.e * E, unit: "N", formula: "F = qε,  ε = ΔV/d",
      prompt: `${intro} What is the magnitude of the electric force on an electron between the plates?`,
      wrong: [C.e * V, E, C.e * V / dmm],
      steps: [`ε = ΔV/d = ${V}/${sv(d)} = ${fmt(E)} V/m`, `F = eε = (1.60 × 10⁻¹⁹)(${fmt(E)}) = ${fmt(C.e * E)} N`] };
  });
  S("accel_V", "fld", 2, "Charges accelerated through a potential difference", (r) => {
    const electron = r.chance(0.5), V = r.i(100, 5000);
    const m = electron ? C.me : C.mp, mOther = electron ? C.mp : C.me;
    const v = sqrt(2 * C.e * V / m);
    return { p: { electron, V }, ans: v, unit: "m/s", formula: "qΔV = ½mv²",
      prompt: `${electron ? "An electron" : "A proton"} starts from rest and is accelerated through a potential difference of ${V} V. What is its final speed?`,
      wrong: [sqrt(C.e * V / m), 2 * C.e * V / m, sqrt(2 * C.e * V / mOther)],
      steps: ["The lost electric potential energy becomes kinetic energy: qΔV = ½mv²", "v = √(2qΔV/m)", `v = √(2(1.60 × 10⁻¹⁹)(${V})/${electron ? "9.11 × 10⁻³¹" : "1.67 × 10⁻²⁷"}) = ${fmt(v)} m/s`] };
  });
  S("millikan", "fld", 2, "Millikan's oil drop", (r) => {
    const n = r.i(1, 12), m = r.n(1.0, 9.9, 1) * 1e-15, dmm = r.i(5, 20), d = dmm / 1000;
    const V = Number((m * C.g * d / (n * C.e)).toPrecision(3));
    const q = m * C.g * d / V;
    return { p: { n, m, dmm, V }, ans: n, int: true, unit: "electrons", formula: "qε = mg,  ε = ΔV/d,  q = Ne",
      prompt: `An oil drop of mass ${sv(m)} kg is held stationary between horizontal plates ${dmm} mm apart when the potential difference is ${sv(V)} V. How many excess electrons are on the drop?`,
      wrong: [n + 1, n > 1 ? n - 1 : n + 3, 2 * n, n + 2],
      steps: ["Balanced: qΔV/d = mg  →  q = mgd/ΔV", `q = (${sv(m)})(9.80)(${sv(d)})/${sv(V)} = ${fmt(q)} C`, `N = q/e = ${fmt(q)}/(1.60 × 10⁻¹⁹) = ${fmt(q / C.e)}  →  ${n} electrons`] };
  });
  S("wire_force", "fld", 1, "Magnetic force on a current-carrying wire", (r) => {
    const I = r.n(1, 20, 1), L = r.n(0.10, 2.00, 2), B = r.n(0.05, 1.50, 2), th = r.pick([30, 45, 60, 90]);
    const F = I * L * B * sind(th);
    return { p: { I, L, B, th }, ans: F, unit: "N", formula: "F = IlB sinθ",
      prompt: `A ${L} m wire carrying ${I} A lies in a ${B} T magnetic field at ${th}° to the field. What is the magnitude of the magnetic force on the wire?`,
      wrong: [I * L * B, I * L * B * cosd(th), I * B / L],
      steps: ["F = IlB sinθ", `F = ${I} × ${L} × ${B} × sin${th}° = ${fmt(F)} N`] };
  });
  S("charge_radius", "fld", 2, "Charged particles in magnetic fields", (r) => {
    const electron = r.chance(0.5);
    const v = r.n(1, 9, 1) * (electron ? 1e6 : 1e5), B = electron ? r.n(1, 9, 1) * 1e-3 : r.n(0.10, 1.00, 2);
    const m = electron ? C.me : C.mp, mOther = electron ? C.mp : C.me, rad = m * v / (C.e * B);
    return { p: { electron, v, B }, ans: rad, unit: "m", formula: "qvB = mv²/r  →  r = mv/(qB)",
      prompt: `${electron ? "An electron" : "A proton"} moving at ${sv(v)} m/s enters a uniform ${sv(B)} T magnetic field at right angles to the field. What is the radius of its circular path?`,
      wrong: [mOther * v / (C.e * B), m * v * v / (C.e * B), 2 * m * v / (C.e * B)],
      steps: ["The magnetic force is the centripetal force: qvB = mv²/r", "r = mv/(qB)", `r = (${electron ? "9.11 × 10⁻³¹" : "1.67 × 10⁻²⁷"})(${sv(v)})/((1.60 × 10⁻¹⁹)(${sv(B)})) = ${fmt(rad)} m`] };
  });
  S("moving_charge_force", "fld", 1, "Magnetic force on a moving charge", (r) => {
    const v = r.n(1, 9, 1) * 1e5, B = r.n(0.1, 2.0, 1), th = r.pick([30, 45, 60, 90]);
    const F = C.e * v * B * sind(th);
    return { p: { v, B, th }, ans: F, unit: "N", formula: "F = qvB sinθ",
      prompt: `A proton moves at ${sv(v)} m/s at ${th}° to a ${B} T magnetic field. What is the magnitude of the magnetic force on it?`,
      wrong: [C.e * v * B, C.e * v * B * cosd(th), C.e * v / B],
      steps: ["F = qvB sinθ", `F = (1.60 × 10⁻¹⁹)(${sv(v)})(${B}) sin${th}° = ${fmt(F)} N`] };
  });
  S("wire_field", "fld", 2, "Magnetic field around a straight wire", (r) => {
    const I = r.n(1, 50, 1), rcm = r.n(1, 20, 1), d = rcm / 100;
    const B = C.mu0 * I / (2 * PI * d);
    return { p: { I, rcm }, ans: B, unit: "T", formula: "B = μ₀I/(2πr)",
      prompt: `What is the magnetic field strength ${rcm} cm from a long straight wire carrying ${I} A?`,
      wrong: [C.mu0 * I / (2 * PI * rcm), C.mu0 * I / d, C.mu0 * I / (2 * d)],
      steps: [`r = ${sv(d)} m`, "B = μ₀I/(2πr)", `B = (4π × 10⁻⁷)(${I})/(2π × ${sv(d)}) = ${fmt(B)} T`] };
  });
  S("velocity_selector", "fld", 2, "Velocity selector", (r) => {
    let V, dmm, B, v;
    do { V = r.i(100, 2000); dmm = r.n(1, 10, 1); B = r.n(0.01, 0.50, 2); v = V / (dmm / 1000) / B; } while (v > 3e7 || v < 1e3);
    const E = V / (dmm / 1000);
    return { p: { V, dmm, B }, ans: v, unit: "m/s", formula: "qε = qvB  →  v = ε/B",
      prompt: `In a velocity selector, parallel plates ${dmm} mm apart have a potential difference of ${V} V, and the magnetic field is ${B} T. At what speed do charged particles pass through undeflected?`,
      wrong: [E * B, B / E, V / B],
      steps: [`ε = ΔV/d = ${V}/${sv(dmm / 1000)} = ${fmt(E)} V/m`, "Undeflected when the forces balance: qε = qvB", `v = ε/B = ${fmt(E)}/${B} = ${fmt(v)} m/s`] };
  });

  // ===== Unit E: The Wave Nature of Light =====================================
  S("freq_light", "wav", 1, "c = fλ for light", (r) => {
    const lam = r.i(400, 700), f = C.c / (lam * 1e-9);
    return { p: { lam }, ans: f, unit: "Hz", formula: "c = fλ",
      prompt: `What is the frequency of light with a wavelength of ${lam} nm?`,
      wrong: [C.c / lam, lam * 1e-9 / C.c, C.c * lam * 1e-9],
      steps: [`λ = ${lam} nm = ${sv(lam * 1e-9)} m`, `f = c/λ = (3.00 × 10⁸)/(${sv(lam * 1e-9)}) = ${fmt(f)} Hz`] };
  });
  const MEDIA = [{ name: "water", n: 1.33 }, { name: "glass", n: 1.50 }, { name: "diamond", n: 2.42 }, { name: "acrylic", n: 1.49 }];
  S("index", "wav", 1, "Index of refraction", (r) => {
    const md = r.pick(MEDIA), lam = r.i(400, 700);
    if (r.chance(0.5)) {
      const ans = lam / md.n;
      return { p: { n: md.n, lam, variant: "lam" }, ans, unit: "nm", formula: "λ_medium = λ_vacuum/n",
        prompt: `Light with a wavelength of ${lam} nm in air enters ${md.name} (n = ${md.n}). What is its wavelength in the ${md.name}?`,
        wrong: [lam * md.n, lam, lam / (md.n * md.n)],
        steps: ["Frequency stays the same; speed and wavelength both drop by a factor of n", `λ = ${lam}/${md.n} = ${fmt(ans)} nm`] };
    }
    const v = C.c / md.n;
    return { p: { n: md.n, variant: "v" }, ans: v, unit: "m/s", formula: "n = c/v",
      prompt: `What is the speed of light in ${md.name} (n = ${md.n})?`,
      wrong: [C.c * md.n, C.c, C.c / (md.n * md.n)],
      steps: ["v = c/n", `v = (3.00 × 10⁸)/${md.n} = ${fmt(v)} m/s`] };
  });
  S("snell", "wav", 1, "Snell's law and total internal reflection", (r) => {
    const md = r.pick(MEDIA);
    if (r.chance(0.6)) {
      const th1 = r.i(15, 70), th2 = asind(sind(th1) / md.n);
      return { p: { n: md.n, th1, variant: "refract" }, ans: th2, unit: "°", formula: "n₁ sinθ₁ = n₂ sinθ₂",
        prompt: `Light in air strikes the surface of ${md.name} (n = ${md.n}) at ${th1}° to the normal. What is the angle of refraction?`,
        wrong: [th1 / md.n, th1, asind(sind(th1) * md.n), th1 * md.n, 90 - th2],
        steps: ["n₁ sinθ₁ = n₂ sinθ₂", `sinθ₂ = (1.00 × sin${th1}°)/${md.n} = ${fmt(sind(th1) / md.n)}`, `θ₂ = ${fmt(th2)}°`] };
    }
    const thc = asind(1 / md.n);
    return { p: { n: md.n, variant: "critical" }, ans: thc, unit: "°", formula: "sinθ_c = n₂/n₁",
      prompt: `What is the critical angle for light travelling from ${md.name} (n = ${md.n}) into air?`,
      wrong: [90 - thc, atand(1 / md.n), (1 / md.n) * 180 / PI],
      steps: ["At the critical angle the refracted ray is at 90°: n₁ sinθ_c = n₂ sin90°", `sinθ_c = 1.00/${md.n} = ${fmt(1 / md.n)}`, `θ_c = ${fmt(thc)}°`] };
  });
  S("path_diff", "wav", 2, "Interference of two point sources", (r) => {
    const lam = r.n(1, 5, 1), n = r.i(1, 4), nodal = r.chance(0.6);
    if (nodal) {
      const pd = (n - 0.5) * lam;
      return { p: { lam, n, nodal }, ans: pd, unit: "cm", formula: "PD = (n − ½)λ",
        prompt: `Two point sources vibrate in phase, producing waves with a wavelength of ${lam} cm. What is the path difference to any point on the ${ord(n)} nodal line?`,
        wrong: [n * lam, (n + 0.5) * lam, n > 1 ? (n - 1) * lam : 2 * lam],
        steps: ["Nodal lines: |PS₁ − PS₂| = (n − ½)λ", `PD = (${n} − ½)(${lam}) = ${fmt(pd)} cm`] };
    }
    const pd = n * lam;
    return { p: { lam, n, nodal }, ans: pd, unit: "cm", formula: "PD = mλ",
      prompt: `Two point sources vibrate in phase, producing waves with a wavelength of ${lam} cm. What is the path difference to any point on the ${ord(n)} antinodal line beside the central line?`,
      wrong: [(n - 0.5) * lam, (n + 0.5) * lam, n * lam / 2],
      steps: ["Antinodal lines: |PS₁ − PS₂| = mλ", `PD = ${n} × ${lam} = ${fmt(pd)} cm`] };
  });
  S("double_slit_spacing", "wav", 2, "Young's double slit: fringe spacing", (r) => {
    const lam = r.i(400, 700), L = r.n(0.5, 4, 1), dmm = r.n(0.05, 0.50, 2);
    const dy = lam * 1e-9 * L / (dmm * 1e-3) * 1000;
    return { p: { lam, L, dmm }, ans: dy, unit: "mm", formula: "Δy = λL/d",
      prompt: `Light of wavelength ${lam} nm passes through two slits ${dmm} mm apart onto a screen ${L} m away. What is the distance between adjacent bright fringes?`,
      wrong: [dy * 1000, dy / 2, lam * 1e-9 * (dmm * 1e-3) / L * 1000],
      steps: [`λ = ${sv(lam * 1e-9)} m,  d = ${sv(dmm * 1e-3)} m`, "Δy = λL/d", `Δy = (${sv(lam * 1e-9)})(${L})/(${sv(dmm * 1e-3)}) = ${fmt(dy / 1000)} m = ${fmt(dy)} mm`] };
  });
  S("double_slit_lambda", "wav", 2, "Young's double slit: finding λ", (r) => {
    const lamTrue = r.i(400, 700), L = r.n(1, 4, 1), dmm = r.n(0.10, 0.50, 2), k = r.chance(0.5) ? 1 : r.i(3, 6);
    const span = Number((lamTrue * 1e-9 * L / (dmm * 1e-3) * k * 1000).toPrecision(3)); // mm
    const lam = span / k * 1e-3 * (dmm * 1e-3) / L * 1e9;
    const desc = k === 1 ? `Adjacent bright fringes are ${span} mm apart` : `The distance from the 1st to the ${ord(k + 1)} bright fringe on one side is ${span} mm`;
    return { p: { span, k, L, dmm }, ans: lam, unit: "nm", formula: "λ = Δy·d/L",
      prompt: `Two slits ${dmm} mm apart are ${L} m from a screen. ${desc}. What is the wavelength of the light?`,
      wrong: k === 1 ? [lam / 2, lam * 1000, span * 1e-3 * L / (dmm * 1e-3) * 1e9 / 1e6] : [lam * k, lam * (k + 1) / k, lam / 2],
      steps: [k === 1 ? `Δy = ${span} mm` : `${k} fringe spacings span ${span} mm, so Δy = ${span}/${k} = ${fmt(span / k)} mm`, "λ = Δy·d/L", `λ = (${sv(span / k * 1e-3)})(${sv(dmm * 1e-3)})/${L} = ${fmt(lam * 1e-9)} m = ${fmt(lam)} nm`] };
  });
  S("double_slit_angle", "wav", 2, "Double-slit angles", (r) => {
    let lam, d, m;
    do { lam = r.i(400, 700); d = r.n(2, 20, 1); m = r.i(1, 3); } while (m * lam * 1e-3 / d > 0.95);
    const th = asind(m * lam * 1e-3 / d);
    return { p: { lam, d, m }, ans: th, unit: "°", formula: "d sinθ = mλ",
      prompt: `Light of wavelength ${lam} nm shines on two slits ${d} μm apart. At what angle from the central bright fringe is the ${ord(m)}-order bright fringe?`,
      wrong: [asind((m - 0.5) * lam * 1e-3 / d), m === 1 ? asind(Math.min(1, 2 * lam * 1e-3 / d)) : asind(lam * 1e-3 / d), asind(m * lam * 1e-3 / (2 * d))],
      steps: ["Bright fringes: d sinθ = mλ", `sinθ = ${m}(${sv(lam * 1e-9)})/(${sv(d * 1e-6)}) = ${fmt(m * lam * 1e-3 / d)}`, `θ = ${fmt(th)}°`] };
  });
  S("grating", "wav", 2, "Diffraction gratings", (r) => {
    let N, lam, m;
    do { N = r.pick([2000, 3000, 4000, 5000, 6000]); lam = r.i(400, 700); m = r.pick([1, 2]); } while (m * lam * 1e-9 * N * 100 > 0.95);
    const d = 0.01 / N, s = m * lam * 1e-9 / d, th = asind(s);
    return { p: { N, lam, m }, ans: th, unit: "°", formula: "d sinθ = mλ",
      prompt: `A diffraction grating has ${N} lines/cm. At what angle is the ${ord(m)}-order maximum for ${lam} nm light?`,
      wrong: [m === 1 ? asind(Math.min(1, 2 * s)) : asind(s / 2), asind(m * lam * 1e-9 * N), 90 - th],
      steps: [`d = 1/(${N} lines/cm) = ${sv(1 / N)} cm = ${sv(d)} m`, `sinθ = mλ/d = ${m}(${sv(lam * 1e-9)})/(${sv(d)}) = ${fmt(s)}`, `θ = ${fmt(th)}°`] };
  });
  S("single_slit", "wav", 2, "Single-slit diffraction", (r) => {
    const lam = r.i(400, 700), w = r.n(0.02, 0.50, 2), L = r.n(1, 4, 1);
    const W = 2 * lam * 1e-9 * L / (w * 1e-3) * 1000;
    return { p: { lam, w, L }, ans: W, unit: "mm", formula: "central max width = 2λL/w",
      prompt: `Light of wavelength ${lam} nm passes through a single slit ${w} mm wide onto a screen ${L} m away. How wide is the central bright maximum?`,
      wrong: [W / 2, 2 * W, 2 * lam * 1e-9 * (w * 1e-3) / L * 1000],
      steps: ["The first dark fringes are at y = ±λL/w, so the central max is 2λL/w wide", `width = 2(${sv(lam * 1e-9)})(${L})/(${sv(w * 1e-3)}) = ${fmt(W / 1000)} m = ${fmt(W)} mm`] };
  });
  S("thin_film", "wav", 3, "Thin films (soap bubbles)", (r) => {
    const n = r.pick([1.33, 1.35, 1.40]), lam = r.i(400, 700), dark = r.chance(0.5);
    const t = dark ? lam / (2 * n) : lam / (4 * n);
    return { p: { n, lam, dark }, ans: t, unit: "nm", formula: dark ? "dark: t = λ/(2n)" : "bright: t = λ/(4n)",
      prompt: `A soap film (n = ${n}) in air is lit by ${lam} nm light. What is the minimum non-zero thickness that makes the film appear ${dark ? "dark" : "bright"} in reflected light?`,
      wrong: dark ? [lam / (4 * n), lam / 2, lam / n] : [lam / (2 * n), lam / 4, 3 * lam / (4 * n)],
      steps: ["Only the top surface reflection is inverted (air → soap), so the two rays start ½λ out of phase", dark ? "For destructive interference the extra path 2t must be a whole wavelength in the film: 2t = λ/n" : "For constructive interference the extra path 2t must be half a wavelength in the film: 2t = λ/(2n)", `t = ${fmt(t)} nm`] };
  });
  S("antireflect", "wav", 3, "Anti-reflection coatings", (r) => {
    const nc = r.pick([1.38, 1.25, 1.30]), lam = r.i(450, 650);
    const t = lam / (4 * nc);
    return { p: { nc, lam }, ans: t, unit: "nm", formula: "t = λ/(4n_coating)",
      prompt: `A lens (n = 1.52) has a thin coating (n = ${nc}) to reduce reflection of ${lam} nm light. What is the minimum coating thickness?`,
      wrong: [lam / (2 * nc), lam / 4, lam / (4 * 1.52)],
      steps: ["Both reflections (air → coating, coating → glass) are inverted, so they start in phase", "For destructive interference: 2t = λ/(2n)  →  t = λ/(4n)", `t = ${lam}/(4 × ${nc}) = ${fmt(t)} nm`] };
  });
  S("air_wedge", "wav", 3, "Air wedges", (r) => {
    const Lcm = r.n(5, 15, 1), tum = r.i(20, 100), lam = r.i(400, 700);
    const dx = lam * 1e-9 * (Lcm / 100) / (2 * tum * 1e-6) * 1000;
    return { p: { Lcm, tum, lam }, ans: dx, unit: "mm", formula: "Δx = λL/(2t)",
      prompt: `Two glass plates ${Lcm} cm long touch at one end and are separated by a ${tum} μm fibre at the other, forming an air wedge. Light of wavelength ${lam} nm shines from above. What is the spacing between adjacent dark fringes?`,
      wrong: [2 * dx, dx / 2, lam * 1e-9 * (tum * 1e-6) / (2 * Lcm / 100) * 1000],
      steps: ["Each fringe is where the gap grows by λ/2 (the light crosses the gap twice)", "Δx = λL/(2t)", `Δx = (${sv(lam * 1e-9)})(${sv(Lcm / 100)})/(2 × ${sv(tum * 1e-6)}) = ${fmt(dx / 1000)} m = ${fmt(dx)} mm`] };
  });
  S("malus", "wav", 2, "Polarization", (r) => {
    const I0 = r.i(100, 900), th = r.pick([20, 30, 40, 50, 60, 70]), unpol = r.chance(0.5);
    const I = (unpol ? I0 / 2 : I0) * sq(cosd(th));
    if (unpol) return { p: { I0, th, unpol }, ans: I, unit: "W/m²", formula: "I = (I₀/2)cos²θ",
      prompt: `Unpolarized light of intensity ${I0} W/m² passes through two polarizing filters whose axes are ${th}° apart. What intensity emerges?`,
      wrong: [I0 * sq(cosd(th)), I0 / 2 * cosd(th), I0 / 2],
      steps: [`The first filter passes half: I₁ = ${I0}/2 = ${fmt(I0 / 2)} W/m²`, `Malus's law: I₂ = I₁cos²θ = ${fmt(I0 / 2)} × cos²${th}° = ${fmt(I)} W/m²`] };
    return { p: { I0, th, unpol }, ans: I, unit: "W/m²", formula: "I = I₀cos²θ",
      prompt: `Polarized light of intensity ${I0} W/m² passes through a filter whose axis is at ${th}° to the light's plane of polarization. What intensity is transmitted?`,
      wrong: [I0 * cosd(th), I0 * sq(sind(th)), I / 2],
      steps: ["Malus's law: I = I₀cos²θ", `I = ${I0} × cos²${th}° = ${fmt(I)} W/m²`] };
  });

  // ===== Unit F: Revolutions in Modern Physics ================================
  const METALS = [
    { name: "cesium", W: 2.10 }, { name: "potassium", W: 2.30 }, { name: "sodium", W: 2.28 },
    { name: "calcium", W: 2.87 }, { name: "lithium", W: 2.93 }, { name: "zinc", W: 4.31 },
    { name: "barium", W: 2.52 }, { name: "magnesium", W: 3.68 }, { name: "aluminum", W: 4.08 },
    { name: "iron", W: 4.50 }, { name: "copper", W: 4.70 },
  ];
  S("photon_energy", "mod", 1, "Photon energy", (r) => {
    const lam = r.i(200, 700), EJ = C.h * C.c / (lam * 1e-9), eV = r.chance(0.5);
    if (eV) return { p: { lam, eV }, ans: EJ / C.e, unit: "eV", formula: "E = hc/λ",
      prompt: `What is the energy, in electron-volts, of a photon with a wavelength of ${lam} nm?`,
      wrong: [EJ, C.h / (lam * 1e-9) / C.e, EJ / C.e / 2],
      steps: [`E = hc/λ = (6.63 × 10⁻³⁴)(3.00 × 10⁸)/(${sv(lam * 1e-9)}) = ${fmt(EJ)} J`, `E = ${fmt(EJ)}/(1.60 × 10⁻¹⁹) = ${fmt(EJ / C.e)} eV`] };
    return { p: { lam, eV }, ans: EJ, unit: "J", formula: "E = hc/λ",
      prompt: `What is the energy, in joules, of a photon with a wavelength of ${lam} nm?`,
      wrong: [C.h * C.c / lam, C.h * lam * 1e-9 / C.c, EJ / C.e],
      steps: [`λ = ${sv(lam * 1e-9)} m`, `E = hc/λ = (6.63 × 10⁻³⁴)(3.00 × 10⁸)/(${sv(lam * 1e-9)}) = ${fmt(EJ)} J`] };
  });
  S("photoelectric", "mod", 2, "The photoelectric effect", (r) => {
    const mt = r.pick(METALS), hcE = C.h * C.c / C.e * 1e9; // eV·nm
    const lam = r.i(150, Math.floor(hcE / (mt.W + 0.3)));
    const E = hcE / lam, K = E - mt.W;
    return { p: { lam, W: mt.W }, ans: K, unit: "eV", formula: "E_k,max = hf − W",
      prompt: `Light of wavelength ${lam} nm falls on ${mt.name}, which has a work function of ${mt.W} eV. What is the maximum kinetic energy of the emitted photoelectrons?`,
      wrong: [E + mt.W, E, mt.W],
      steps: [`E_photon = hc/λ = ${fmt(E * C.e)} J = ${fmt(E)} eV`, "E_k,max = E_photon − W", `E_k,max = ${fmt(E)} − ${mt.W} = ${fmt(K)} eV`] };
  });
  S("threshold", "mod", 1, "Threshold frequency", (r) => {
    const mt = r.pick(METALS), f0 = mt.W * C.e / C.h;
    if (r.chance(0.4)) {
      const lam0 = C.h * C.c / (mt.W * C.e) * 1e9;
      return { p: { W: mt.W, variant: "lam" }, ans: lam0, unit: "nm", formula: "λ₀ = hc/W",
        prompt: `The work function of ${mt.name} is ${mt.W} eV. What is the longest wavelength of light that can eject electrons from it?`,
        wrong: [C.h * C.c / mt.W * 1e9, lam0 / 2, C.h * C.c / (mt.W * C.e * 2) * 1e9 * 3],
        steps: [`W = ${mt.W} × 1.60 × 10⁻¹⁹ = ${fmt(mt.W * C.e)} J`, `λ₀ = hc/W = (6.63 × 10⁻³⁴)(3.00 × 10⁸)/(${fmt(mt.W * C.e)}) = ${fmt(lam0 * 1e-9)} m = ${fmt(lam0)} nm`] };
    }
    return { p: { W: mt.W, variant: "f" }, ans: f0, unit: "Hz", formula: "f₀ = W/h",
      prompt: `The work function of ${mt.name} is ${mt.W} eV. What is its threshold frequency?`,
      wrong: [mt.W / C.h, C.h / (mt.W * C.e), C.h * C.c / (mt.W * C.e)],
      steps: [`W = ${mt.W} eV × 1.60 × 10⁻¹⁹ J/eV = ${fmt(mt.W * C.e)} J`, `f₀ = W/h = ${fmt(mt.W * C.e)}/(6.63 × 10⁻³⁴) = ${fmt(f0)} Hz`] };
  });
  S("work_function", "mod", 2, "Stopping potential", (r) => {
    const fv = r.n(7.0, 15.0, 1) * 1e14, Eph = C.h * fv / C.e;
    const W = r.n(1.8, Math.min(4.5, Eph - 0.3), 2), Vs = Math.round((Eph - W) * 100) / 100, ans = Eph - Vs;
    return { p: { f: fv, Vs }, ans, unit: "eV", formula: "hf = W + eV_stop",
      prompt: `When light of frequency ${sv(fv)} Hz shines on a metal, the stopping potential is ${Vs} V. What is the work function of the metal?`,
      wrong: [Eph + Vs, Eph, Vs],
      steps: [`E_photon = hf = (6.63 × 10⁻³⁴)(${sv(fv)}) = ${fmt(C.h * fv)} J = ${fmt(Eph)} eV`, `E_k,max = eV_stop = ${Vs} eV`, `W = hf − E_k,max = ${fmt(Eph)} − ${Vs} = ${fmt(ans)} eV`] };
  });
  S("debroglie", "mod", 2, "de Broglie wavelength", (r) => {
    if (r.chance(0.7)) {
      const v = r.n(1, 9, 1) * 1e6, lam = C.h / (C.me * v) * 1e9;
      return { p: { v, variant: "e" }, ans: lam, unit: "nm", formula: "λ = h/(mv)",
        prompt: `What is the de Broglie wavelength of an electron moving at ${sv(v)} m/s?`,
        wrong: [C.h / (C.mp * v) * 1e9, C.h / (C.me * v * v) * 1e9, lam * 1000],
        steps: ["λ = h/(mv)", `λ = (6.63 × 10⁻³⁴)/((9.11 × 10⁻³¹)(${sv(v)})) = ${fmt(lam * 1e-9)} m = ${fmt(lam)} nm`] };
    }
    const m = r.pick([0.145, 0.057, 0.160, 0.046]), v = r.i(20, 45), lam = C.h / (m * v);
    return { p: { m, v, variant: "ball" }, ans: lam, unit: "m", formula: "λ = h/(mv)",
      prompt: `What is the de Broglie wavelength of a ${m} kg ball thrown at ${v} m/s? (This is why we never see a ball diffract!)`,
      wrong: [C.h * m * v, C.h / m, m * v / C.h],
      steps: ["λ = h/(mv)", `λ = (6.63 × 10⁻³⁴)/(${m} × ${v}) = ${fmt(lam)} m`] };
  });
  S("debroglie_V", "mod", 3, "Electron waves after acceleration", (r) => {
    const V = r.i(50, 5000), p = sqrt(2 * C.me * C.e * V), lam = C.h / p * 1e9;
    return { p: { V }, ans: lam, unit: "nm", formula: "p = √(2meV),  λ = h/p",
      prompt: `An electron is accelerated from rest through ${V} V. What is its de Broglie wavelength?`,
      wrong: [C.h / sqrt(2 * C.mp * C.e * V) * 1e9, C.h / sqrt(C.me * C.e * V) * 1e9, lam * 1000],
      steps: [`E_k = eV = ${fmt(C.e * V)} J`, `p = √(2mE_k) = ${fmt(p)} kg·m/s`, `λ = h/p = ${fmt(lam * 1e-9)} m = ${fmt(lam)} nm`] };
  });
  S("photon_momentum", "mod", 2, "Photon momentum", (r) => {
    const lam = r.i(100, 700), p = C.h / (lam * 1e-9);
    return { p: { lam }, ans: p, unit: "kg·m/s", formula: "p = h/λ",
      prompt: `What is the momentum of a photon with a wavelength of ${lam} nm?`,
      wrong: [C.h * lam * 1e-9, p / C.c, C.h * C.c / (lam * 1e-9)],
      steps: ["p = h/λ", `p = (6.63 × 10⁻³⁴)/(${sv(lam * 1e-9)}) = ${fmt(p)} kg·m/s`] };
  });
  const BETAS = [0.300, 0.400, 0.500, 0.600, 0.700, 0.750, 0.800, 0.866, 0.900, 0.950, 0.980, 0.990];
  const gam = (b) => 1 / sqrt(1 - b * b);
  S("time_dilation", "mod", 2, "Time dilation", (r) => {
    const b = r.pick(BETAS), t0 = r.n(1, 20, 1), t = t0 * gam(b);
    return { p: { b, t0 }, ans: t, unit: "h", formula: "Δt = Δt₀/√(1 − v²/c²)",
      prompt: `A clock on a spacecraft moving at ${b}c ticks off ${t0} h. How much time passes according to observers on Earth?`,
      wrong: [t0 * sqrt(1 - b * b), t0 / (1 - b * b), t0 / sqrt(1 - b)],
      steps: ["The ship's clock measures proper time Δt₀", `γ = 1/√(1 − ${b}²) = ${fmt(gam(b))}`, `Δt = γΔt₀ = ${fmt(gam(b))} × ${t0} = ${fmt(t)} h`] };
  });
  S("length_contraction", "mod", 2, "Length contraction", (r) => {
    const b = r.pick(BETAS), L0 = r.i(20, 500), L = L0 * sqrt(1 - b * b);
    return { p: { b, L0 }, ans: L, unit: "m", formula: "L = L₀√(1 − v²/c²)",
      prompt: `A spaceship is ${L0} m long when measured at rest. How long is it according to an observer it passes at ${b}c?`,
      wrong: [L0 * gam(b), L0 * (1 - b * b), L0 * sqrt(1 - b)],
      steps: ["The rest length is the proper length L₀; moving objects are shorter", `L = L₀√(1 − v²/c²) = ${L0}√(1 − ${b}²) = ${fmt(L)} m`] };
  });
  S("mass_energy", "mod", 1, "Mass–energy equivalence", (r) => {
    const mg = r.n(0.1, 10, 1), E = mg / 1000 * C.c * C.c;
    return { p: { mg }, ans: E, unit: "J", formula: "E = mc²",
      prompt: `How much energy is equivalent to ${mg} g of mass?`,
      wrong: [mg / 1000 * C.c, mg * C.c * C.c, 0.5 * mg / 1000 * C.c * C.c],
      steps: [`m = ${mg} g = ${sv(mg / 1000)} kg`, `E = mc² = (${sv(mg / 1000)})(3.00 × 10⁸)² = ${fmt(E)} J`] };
  });
  S("muon", "mod", 3, "Muon decay and time dilation", (r) => {
    const b = r.pick([0.950, 0.960, 0.970, 0.980, 0.985, 0.990, 0.993, 0.995, 0.998, 0.999]), tau = 2.20e-6, d = gam(b) * b * C.c * tau;
    return { p: { b }, ans: d, unit: "m", formula: "Δt = γΔt₀,  d = vΔt",
      prompt: `Muons have a mean lifetime of 2.20 μs in their own rest frame. On average, how far does a muon moving at ${b}c travel in Earth's frame before decaying?`,
      wrong: [b * C.c * tau, b * C.c * tau / gam(b), gam(b) * gam(b) * b * C.c * tau],
      steps: [`γ = 1/√(1 − ${b}²) = ${fmt(gam(b))}`, `Δt (Earth) = γ(2.20 × 10⁻⁶ s) = ${fmt(gam(b) * tau)} s`, `d = vΔt = (${b})(3.00 × 10⁸)(${fmt(gam(b) * tau)}) = ${fmt(d)} m`] };
  });
  S("rel_momentum", "mod", 3, "Relativistic momentum", (r) => {
    const b = r.pick(BETAS), p = gam(b) * C.me * b * C.c;
    return { p: { b }, ans: p, unit: "kg·m/s", formula: "p = γmv",
      prompt: `What is the momentum of an electron moving at ${b}c?`,
      wrong: [C.me * b * C.c, gam(b) * gam(b) * C.me * b * C.c, C.me * b * C.c / gam(b)],
      steps: [`γ = 1/√(1 − ${b}²) = ${fmt(gam(b))}`, `p = γmv = ${fmt(gam(b))} × (9.11 × 10⁻³¹) × ${b}(3.00 × 10⁸) = ${fmt(p)} kg·m/s`] };
  });
  S("photon_count", "mod", 2, "Photons per second", (r) => {
    const P = r.n(0.5, 5, 1), lam = r.i(400, 700), E = C.h * C.c / (lam * 1e-9), N = P * 1e-3 / E;
    return { p: { P, lam }, ans: N, unit: "photons/s", formula: "N = P/E_photon",
      prompt: `A ${P} mW laser emits ${lam} nm light. How many photons does it emit each second?`,
      wrong: [P / E, P * 1e-3 * E, P * 1e-3 / (C.h * lam * 1e-9)],
      steps: [`E_photon = hc/λ = ${fmt(E)} J`, `N = P/E = (${sv(P * 1e-3)} J/s)/(${fmt(E)} J) = ${fmt(N)} photons/s`] };
  });

  // ---------------------------------------------------------------- concepts
  // [prompt, correct, wrong, wrong, wrong, explanation]
  const CONCEPTS = {
    dyn: [
      ["A ball is thrown straight up. At the very top of its path, what is its acceleration?", "9.80 m/s² downward", "Zero", "9.80 m/s² upward", "It depends on the ball's mass", "Velocity is momentarily zero at the top, but gravity still acts, so a = g downward the whole flight."],
      ["A car turns left at a constant speed. Which way does the net force on it point?", "Toward the centre of the turn", "Forward, along the velocity", "Outward, away from the centre", "There is no net force because the speed is constant", "The direction of velocity changes, so the car accelerates toward the centre (centripetal acceleration)."],
      ["What best describes 'centrifugal force'?", "A fictitious force that appears only in a rotating frame of reference", "The real outward force on any object in circular motion", "The reaction force to gravity", "Another name for the normal force", "In an inertial frame, only the inward centripetal net force exists. 'Centrifugal force' is an apparent force in a non-inertial (rotating) frame."],
      ["One ball is dropped and another is launched horizontally at the same instant from the same height. Which lands first?", "They land at the same time", "The dropped ball", "The launched ball", "It depends on the launch speed", "Horizontal and vertical motions are independent. Both start with zero vertical velocity and fall with the same g."],
      ["Earth pulls an apple down with force F. By Newton's third law, what is the reaction force?", "The apple pulls Earth up with force F", "The table pushes the apple up with force F", "Air resistance pushes the apple up", "There is no reaction force on Earth", "Action–reaction pairs act on different objects and are the same type of force (here, gravity)."],
      ["A block rests on an incline without sliding. What is the magnitude of the static friction on it?", "mg sinθ", "μₛmg cosθ", "mg cosθ", "mg", "Static friction only grows as large as needed to balance the slope component of gravity. μₛmg cosθ is its maximum value."],
      ["Which frame of reference is inertial?", "One moving at constant velocity", "One on an accelerating car", "One on a merry-go-round", "Any frame attached to a moving object", "Newton's first law holds only in frames that are not accelerating."],
      ["A skydiver reaches terminal velocity. Which is true?", "Air resistance equals the skydiver's weight", "Air resistance is zero", "The net force is downward", "The skydiver's acceleration is 9.80 m/s²", "At terminal velocity the net force is zero, so the velocity stops changing."],
      ["A person stands on a scale in an elevator whose cable snaps (free fall). What does the scale read?", "Zero", "The person's normal weight", "Twice the normal weight", "Half the normal weight", "The scale and person fall together with acceleration g, so the normal force is zero (apparent weightlessness)."],
      ["A projectile is at the top of its arc (ignore air resistance). Which statement is true?", "Its velocity is horizontal", "Its velocity is zero", "Its acceleration is zero", "Its horizontal velocity is zero", "Only the vertical component is zero at the top; the horizontal component never changes."],
      ["Which launch angle gives the maximum range on level ground (no air resistance)?", "45°", "30°", "60°", "90°", "R = v² sin2θ / g is largest when sin2θ = 1, which is θ = 45°."],
    ],
    enm: [
      ["In a perfectly inelastic collision, what is conserved?", "Momentum only", "Kinetic energy only", "Both momentum and kinetic energy", "Neither", "Momentum is conserved in every collision with no outside net force; kinetic energy is lost when objects stick."],
      ["In an elastic collision, what is conserved?", "Both momentum and kinetic energy", "Momentum only", "Kinetic energy only", "Velocity of each object", "Elastic means no kinetic energy is converted to other forms."],
      ["Why do airbags reduce injuries?", "They increase the collision time, lowering the average force", "They reduce the change in momentum", "They reduce the impulse", "They increase the passenger's mass", "The impulse FΔt equals the fixed Δp, so a longer Δt means a smaller average force."],
      ["How much work does the centripetal force do on an object in uniform circular motion?", "Zero", "mv²", "F × 2πr", "It depends on the speed", "The force is always perpendicular to the motion, so cos90° = 0 and no work is done."],
      ["A spring's compression is doubled. Its elastic potential energy becomes:", "4 times as large", "2 times as large", "Half as large", "Unchanged", "E_e = ½kx², so doubling x quadruples the energy."],
      ["A ball either sticks to a wall or bounces straight back at the same speed. Which has the larger impulse?", "Bouncing back", "Sticking", "They are equal", "It depends on the wall", "Bouncing reverses the momentum, so Δp = 2mv, twice the change for sticking."],
      ["The area under a force–time graph represents:", "Impulse", "Work", "Power", "Kinetic energy", "Impulse = ∫F dt, the area under F vs t."],
      ["The area under a force–displacement graph represents:", "Work", "Impulse", "Momentum", "Power", "Work = ∫F dx, the area under F vs x."],
      ["Which is a non-conservative force?", "Kinetic friction", "Gravity", "An ideal spring force", "The electric force", "Work done by friction depends on the path, so it cannot be stored as potential energy."],
      ["A stationary firecracker explodes into pieces. The total momentum of the pieces just after is:", "Zero", "Equal to the energy released", "Greater than zero", "Impossible to know", "Internal forces cannot change the total momentum, which was zero."],
      ["An object's speed doubles. What happens to its kinetic energy and momentum?", "E_k ×4, p ×2", "E_k ×2, p ×2", "E_k ×2, p ×4", "E_k ×4, p ×4", "E_k = ½mv² goes with v², while p = mv goes with v."],
    ],
    fld: [
      ["The distance between two masses doubles. The gravitational force between them becomes:", "¼ as large", "½ as large", "2 times larger", "4 times larger", "Gravitation follows an inverse-square law: F ∝ 1/r²."],
      ["Why do astronauts on the International Space Station feel weightless?", "They and the station are in free fall around Earth", "There is no gravity in space", "They are beyond Earth's gravitational field", "The station's walls block gravity", "At ISS height g is still about 8.7 N/kg; everything falls together, so there is no normal force."],
      ["Electric field lines:", "Start on positive charges and end on negative charges", "Start on negative charges and end on positive charges", "Form closed loops", "Can cross each other", "Field lines show the force on a positive test charge."],
      ["What is the electric field inside a charged hollow metal sphere?", "Zero", "The same as at the surface", "Infinite", "Pointing outward", "In electrostatic equilibrium, charges arrange themselves on the outside so the inner field cancels (Faraday cage)."],
      ["Electric potential is best described as:", "Electric potential energy per unit charge (a scalar)", "Force per unit charge (a vector)", "The total charge on an object", "The current through a circuit", "V = E/q, measured in J/C (volts)."],
      ["An electron moves parallel to a uniform magnetic field. The magnetic force on it is:", "Zero", "Maximum", "Parallel to its velocity", "Equal to its weight", "F = qvB sinθ and sin0° = 0."],
      ["Why does a magnetic force never change a charged particle's speed?", "It is always perpendicular to the velocity, so it does no work", "Magnetic forces are too weak", "Charges have no mass", "It always points along the velocity", "A force perpendicular to motion changes direction only."],
      ["Two long parallel wires carry currents in the same direction. The wires:", "Attract each other", "Repel each other", "Feel no force", "Twist at right angles", "Each wire sits in the other's field; the right-hand rules give an attraction for parallel currents."],
      ["How are equipotential lines related to electric field lines?", "They are always perpendicular", "They are always parallel", "They are the same lines", "They meet at 45°", "No work is done moving along an equipotential, so the field has no component along it."],
      ["What is the period of a geostationary satellite?", "About 24 hours", "About 90 minutes", "About 12 hours", "About 27 days", "It orbits once per day so it stays above the same spot on the rotating Earth."],
      ["What did Millikan's oil-drop experiment show?", "Electric charge is quantized in multiples of e", "Electrons orbit the nucleus", "Light behaves as particles", "Charge is continuous", "Every measured charge was a whole-number multiple of 1.60 × 10⁻¹⁹ C."],
      ["A satellite moves to a higher circular orbit. Its orbital speed:", "Decreases", "Increases", "Stays the same", "Becomes zero", "v = √(GM/r): a larger radius means a lower speed (and a longer period)."],
    ],
    wav: [
      ["Young's double-slit experiment supported which model of light?", "The wave model", "The particle (corpuscular) model", "The photon model", "The ray model only", "An interference pattern can only be explained if light behaves as a wave."],
      ["Polarization of light shows that light is:", "A transverse wave", "A longitudinal wave", "Made of particles", "A sound wave", "Only transverse waves can be polarized."],
      ["In a double-slit experiment the slits are moved closer together. The bright fringes:", "Spread farther apart", "Move closer together", "Stay the same", "Disappear", "Δy = λL/d, so a smaller d makes Δy larger."],
      ["White light passes through a diffraction grating. Which colour is deflected most in the first order?", "Red", "Blue", "Green", "All colours equally", "sinθ = λ/d, so the longest wavelength (red) bends most."],
      ["When light reflects off a medium with a higher index of refraction, the reflected wave:", "Is inverted (half-wavelength phase shift)", "Is not changed", "Is absorbed completely", "Doubles its frequency", "Reflection from a slower (higher-n) medium inverts the wave."],
      ["A single slit is made narrower. The central bright maximum becomes:", "Wider", "Narrower", "Unchanged", "Dark", "The first minimum is at sinθ = λ/w, so a smaller w spreads the pattern."],
      ["Huygens' principle states that:", "Every point on a wavefront acts as a source of secondary wavelets", "Light always travels in straight lines", "Light is made of particles", "Waves cannot interfere", "The new wavefront is the envelope of all the wavelets."],
      ["Light travels from air into water. What happens?", "Speed and wavelength decrease; frequency stays the same", "Frequency decreases", "Speed increases", "Wavelength increases", "The source sets the frequency; v = c/n and λ = v/f both drop."],
      ["Compared with a double slit, a diffraction grating produces maxima that are:", "Sharper and brighter", "Wider and dimmer", "Identical", "Evenly spaced in angle", "Many slits make the constructive interference much more selective."],
      ["Why can't sound waves in air be polarized?", "They are longitudinal", "They are too slow", "They are transverse", "They have no wavelength", "Polarization restricts the direction of a transverse oscillation; longitudinal waves have only one."],
      ["Destructive interference from two in-phase sources happens where the path difference is:", "(n − ½)λ", "nλ", "2nλ", "Zero", "A half-wavelength offset puts crest on trough."],
      ["The bright spot at the centre of a circular object's shadow (Poisson's spot) is evidence of:", "Diffraction of light waves", "Light being made of particles", "Reflection", "The photoelectric effect", "Fresnel predicted the spot from wave theory, and Arago observed it."],
    ],
    mod: [
      ["In the photoelectric effect, increasing the intensity of light (above the threshold frequency):", "Increases the number of electrons, not their maximum E_k", "Increases the maximum E_k of the electrons", "Has no effect", "Lowers the work function", "Intensity means more photons; each photon's energy hf is unchanged."],
      ["Light below a metal's threshold frequency shines on it very brightly. What happens?", "No photoelectrons are emitted", "Electrons are emitted after a delay", "Many slow electrons are emitted", "The metal becomes positively charged", "Each photon has hf < W, so no single photon can free an electron."],
      ["Which pair are the two postulates of special relativity?", "The laws of physics are the same in all inertial frames, and c is the same for all observers", "Mass is conserved and energy is conserved", "Time is absolute and space is relative", "Nothing can move, and light has mass", "Einstein (1905) built relativity on these two postulates."],
      ["Proper time is measured by an observer who:", "Sees both events happen at the same place", "Is moving fastest", "Is on Earth", "Is at the midpoint between the events", "Proper time Δt₀ is the shortest interval and is measured in the frame where the events share a location."],
      ["The Compton effect gave strong evidence that photons:", "Carry momentum", "Have mass", "Travel slower than c", "Are longitudinal waves", "X-rays scattered off electrons lose momentum as if they were particles, so p = h/λ."],
      ["Electron diffraction (the Davisson–Germer experiment) showed that:", "Matter has wave properties", "Electrons have no mass", "Light is a particle", "Atoms are mostly empty", "Electrons formed a diffraction pattern with λ = h/p, confirming de Broglie."],
      ["Why can't a massive object reach the speed of light?", "Its relativistic momentum and energy would become infinite", "Air resistance prevents it", "Its mass becomes zero", "Time stops", "As v → c, γ → ∞, so infinite energy would be needed."],
      ["What are protons made of?", "Two up quarks and one down quark", "One up quark and two down quarks", "Three electrons", "Two leptons", "uud gives a charge of +⅔ + ⅔ − ⅓ = +1."],
      ["What are neutrons made of?", "One up quark and two down quarks", "Two up quarks and one down quark", "A proton and an electron", "Three down quarks", "udd gives a charge of +⅔ − ⅓ − ⅓ = 0."],
      ["Which particle carries (mediates) the electromagnetic force?", "The photon", "The gluon", "The W boson", "The Higgs boson", "Gluons carry the strong force, W and Z bosons the weak force."],
      ["Heisenberg's uncertainty principle says:", "Position and momentum cannot both be known exactly at the same time", "All measurements have random errors", "Electrons have no position", "Energy is not conserved", "Δx·Δp ≥ h/(4π) is a property of nature, not of the measuring tools."],
      ["Planck's explanation of blackbody radiation assumed that:", "Energy is emitted in quanta of E = hf", "Light is a longitudinal wave", "Atoms have no electrons", "Energy is continuous", "Quantizing energy fixed the 'ultraviolet catastrophe'."],
      ["Which of these is a lepton?", "Muon", "Proton", "Neutron", "Pion", "Leptons (electron, muon, tau, neutrinos) are not made of quarks."],
      ["Two events are simultaneous for one observer. For an observer moving relative to the first, they are:", "Possibly not simultaneous", "Always simultaneous", "Never possible", "Simultaneous only if the observer is fast", "Simultaneity is relative in special relativity."],
    ],
  };
  for (const u of UNITS) {
    const s = { id: u.id + "_concepts", unit: u.id, tier: 1, name: "Key concepts", gen: null, concept: true };
    SKILLS.push(s); SKILL[s.id] = s;
  }

  // ---------------------------------------------------------------- questions
  const relDiff = (a, b) => abs(a - b) / Math.max(abs(a), abs(b), 1e-300);

  function makeQuestion(skillId, seed) {
    const sk = SKILL[skillId];
    if (!sk) throw new Error("unknown skill " + skillId);
    const r = rng(seed);
    if (sk.concept) {
      const bank = CONCEPTS[sk.unit], item = bank[Math.floor(r.next() * bank.length)];
      const order = r.shuffle([0, 1, 2, 3]);
      return {
        skill: sk.id, unit: sk.unit, tier: sk.tier, kind: "mc", prompt: item[0],
        choices: order.map((i) => item[1 + i]), correct: order.indexOf(0),
        answerText: item[1], steps: [item[5]], formula: null, seed,
      };
    }
    const spec = sk.gen(r);
    const ansText = spec.int ? String(spec.ans) : fmt(spec.ans);
    const unitSuffix = spec.unit ? (spec.unit.startsWith("°") ? spec.unit : " " + spec.unit) : "";
    const picked = [];
    const okDistractor = (x) => {
      if (!isFinite(x) || x === 0) return false;
      if (spec.int && (x <= 0 || x !== Math.round(x))) return false;
      if (!spec.signed && spec.ans > 0 && x < 0) return false;
      if (relDiff(x, spec.ans) < 0.04) return false;
      const t = spec.int ? String(x) : fmt(x);
      if (t === ansText) return false;
      for (const p of picked) if (relDiff(p, x) < 0.03 || (spec.int ? String(p) : fmt(p)) === t) return false;
      return true;
    };
    for (const w of spec.wrong) if (picked.length < 3 && okDistractor(w)) picked.push(w);
    const mults = r.shuffle([2, 0.5, 10, 0.1, 1.5, 0.667, 4, 0.25, 3, 1.25, 0.8, 1.15]);
    for (const k of mults) if (picked.length < 3 && okDistractor(spec.int ? Math.round(spec.ans * k) : spec.ans * k)) picked.push(spec.int ? Math.round(spec.ans * k) : spec.ans * k);
    for (let k = 1; picked.length < 3 && k < 50; k++) if (okDistractor(spec.ans + k * (spec.int ? 1 : Math.max(abs(spec.ans) * 0.11, 0.01)))) picked.push(spec.ans + k * (spec.int ? 1 : Math.max(abs(spec.ans) * 0.11, 0.01)));
    const vals = [spec.ans].concat(picked);
    const order = r.shuffle([0, 1, 2, 3]);
    const text = (x) => (spec.int ? String(x) : fmt(x)) + unitSuffix;
    return {
      skill: sk.id, unit: sk.unit, tier: sk.tier, kind: "num", prompt: spec.prompt,
      choices: order.map((i) => text(vals[i])), correct: order.indexOf(0),
      value: spec.ans, unitLabel: spec.unit, int: !!spec.int, signed: !!spec.signed,
      answerText: text(spec.ans), steps: spec.steps, formula: spec.formula, params: spec.p, seed,
    };
  }

  // ---------------------------------------------------------------- calculator
  // A small safe expression evaluator (no eval). Trig works in degrees.
  const FUNCS = {
    sin: sind, cos: cosd, tan: tand, asin: asind, acos: (x) => Math.acos(x) / D, atan: atand,
    sqrt: Math.sqrt, ln: Math.log, log: Math.log10, abs: Math.abs, exp: Math.exp,
  };
  function calc(src) {
    const s = String(src).replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/π/g, "pi").replace(/√/g, "sqrt").replace(/\*\*/g, "^").replace(/,/g, "");
    let i = 0;
    const ws = () => { while (i < s.length && /\s/.test(s[i])) i++; };
    const peek = () => { ws(); return s[i]; };
    function expr() {
      let v = term();
      for (;;) { const c = peek(); if (c === "+") { i++; v += term(); } else if (c === "-") { i++; v -= term(); } else return v; }
    }
    function term() {
      let v = unary();
      for (;;) {
        const c = peek();
        if (c === "*") { i++; v *= unary(); }
        else if (c === "/") { i++; v /= unary(); }
        else if (c === "x" && /^x\s*10\s*\^/.test(s.slice(i))) { i++; v *= unary(); }
        else if (c === "(" ) { v *= unary(); }
        else return v;
      }
    }
    function unary() { const c = peek(); if (c === "-") { i++; return -unary(); } if (c === "+") { i++; return unary(); } return power(); }
    function power() { const b = primary(); if (peek() === "^") { i++; return Math.pow(b, unary()); } return b; }
    function primary() {
      const c = peek();
      if (c === "(") { i++; const v = expr(); if (peek() !== ")") throw new Error("missing )"); i++; return v; }
      const num = /^(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/.exec(s.slice(i));
      if (num) { i += num[0].length; return parseFloat(num[0]); }
      const id = /^[a-zA-Z]+/.exec(s.slice(i));
      if (id) {
        i += id[0].length;
        const name = id[0].toLowerCase();
        if (name === "pi") return Math.PI;
        if (FUNCS[name]) { if (peek() !== "(") throw new Error(name + " needs ( )"); return FUNCS[name](primary()); }
        throw new Error("unknown name " + id[0]);
      }
      throw new Error("unexpected " + (c === undefined ? "end" : "'" + c + "'"));
    }
    const v = expr();
    if (peek() !== undefined) throw new Error("unexpected '" + s[i] + "'");
    return v;
  }

  const SUPMAP = { "⁻": "-", "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9" };
  // Reads a typed answer: "3.4", "-2.5 m/s", "3.4e-19", "3.4 x 10^-19", "3.4×10⁻¹⁹ J", or a calculator expression.
  function parseAnswer(str) {
    if (str == null) return NaN;
    let s = String(str).trim().replace(/−/g, "-").replace(/,/g, "").replace(/×/g, "x")
      .replace(/10([⁻⁰¹²³⁴⁵⁶⁷⁸⁹]+)/g, (m, e) => "10^" + e.split("").map((ch) => SUPMAP[ch]).join(""));
    if (!s) return NaN;
    const m = /^([+-]?(?:\d+\.?\d*|\.\d+))\s*(?:[x*]\s*10\s*(?:\^|\*\*)\s*([+-]?\d+)|[eE]\s*([+-]?\d+))?\s*(.*)$/.exec(s);
    if (m && /^[a-zA-Zμ°%/·²³\s.-]*$/.test(m[4])) {
      const ex = m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : "0";
      return parseFloat(m[1]) * Math.pow(10, parseInt(ex, 10));
    }
    try { const v = calc(s); return typeof v === "number" ? v : NaN; } catch (e) { return NaN; }
  }

  function checkTyped(q, str) {
    if (q.kind !== "num") return false;
    const v = parseAnswer(str);
    if (!isFinite(v)) return false;
    if (q.int) return Math.round(v) === q.value && abs(v - q.value) < 0.01;
    return relDiff(v, q.value) <= 0.02;
  }

  const api = { C, CONSTANTS, UNITS, FORMULAS, SKILLS, SKILL, CONCEPTS, makeQuestion, rng, fmt, sv, calc, parseAnswer, checkTyped };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.PQ = api;
})(typeof window !== "undefined" ? window : globalThis);
