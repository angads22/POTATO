// Verifies the question engine: every skill, many seeds.
//  - the answer matches an independently written reference formula (REF)
//  - four distinct choices, the correct index points at the answer
//  - no NaN / undefined / Infinity anywhere in the text
//  - typing the answer is accepted; typing any wrong choice is rejected
//  - a handful of textbook problems with known answers
// Prints "QUESTIONS OK".   node physics-quest/tools/check_questions.js
const path = require("path");
const PQ = require(path.join(__dirname, "..", "questions.js"));
const g = 9.8, G = 6.67e-11, k = 8.99e9, e = 1.6e-19, me = 9.11e-31, mp = 1.67e-27, h = 6.63e-34, c = 3e8, ME = 5.98e24, RE = 6.38e6;
const rad = (d) => (d * Math.PI) / 180, deg = (x) => (x * 180) / Math.PI;
const S = (d) => Math.sin(rad(d)), Co = (d) => Math.cos(rad(d)), T = (d) => Math.tan(rad(d));
const gamma = (b) => 1 / Math.sqrt(1 - b * b);

// Independent reference solutions, keyed by skill id, computed from the givens.
const REF = {
  kin_accel: (p) => (p.v - p.v0) / p.t,
  kin_disp: (p) => p.v0 * p.t + (p.a * p.t ** 2) / 2,
  kin_stop: (p) => p.v0 ** 2 / 2 / p.a,
  proj_horiz: (p) => p.vx * Math.sqrt((2 * p.h) / g),
  proj_range: (p) => (p.variant === "R" ? (2 * p.v * p.v * S(p.th) * Co(p.th)) / g : p.variant === "H" ? (p.v * S(p.th)) ** 2 / 2 / g : (2 * p.v * S(p.th)) / g),
  newton_friction: (p) => p.F / p.m - p.mu * g,
  incline: (p) => g * S(p.th) - p.mu * g * Co(p.th),
  atwood: (p) => { const a = ((p.m1 - p.m2) / (p.m1 + p.m2)) * g; return p.variant === "a" ? a : p.m2 * (g + a); },
  elevator: (p) => p.m * g + (p.up ? 1 : -1) * p.m * p.a,
  centripetal_force: (p) => (p.m * p.v ** 2) / p.rad,
  circ_period: (p) => { const v = (2 * Math.PI * p.rad * p.n) / p.t; return v * v / p.rad; },
  loop_top: (p) => Math.sqrt(p.rad * g),
  banked: (p) => Math.sqrt(p.rad * g * T(p.th)),
  flat_curve_mu: (p) => p.v ** 2 / (p.rad * g),
  river_boat: (p) => (p.variant === "time" ? p.w / p.vb : (p.w / p.vb) * p.vw),
  net_force_2d: (p) => Math.sqrt(p.F1 ** 2 + p.F2 ** 2) / p.m,
  work: (p) => p.F * Co(p.th) * p.d,
  kinetic: (p) => (p.m * p.v ** 2) / 2,
  coaster_speed: (p) => Math.sqrt(2 * g * p.h1 - 2 * g * p.h2),
  hooke: (p) => (p.m * g) / (p.x / 100),
  spring_pe: (p) => (p.k * p.x ** 2) / 2,
  spring_launch: (p) => Math.sqrt((p.k * p.x ** 2) / p.m),
  power: (p) => (p.m * g * p.h) / p.t,
  momentum: (p) => p.m * p.v,
  impulse_force: (p) => (p.m * p.v2 - p.m * -p.v1) / p.dt,
  inelastic_1d: (p) => (p.m1 * p.v1 + p.m2 * p.v2) / (p.m1 + p.m2),
  elastic_1d: (p) => {
    // solve momentum + energy directly: v2' from the quadratic, v1' from momentum
    const v2 = (2 * p.m1 * p.v1) / (p.m1 + p.m2), v1 = (p.m1 * p.v1 - p.m2 * v2) / p.m1;
    return p.variant === "target" ? v2 : v1;
  },
  collision_2d: (p) => { const px = p.m1 * p.v1, py = p.m2 * p.v2; return p.variant === "speed" ? Math.hypot(px, py) / (p.m1 + p.m2) : deg(Math.atan2(py, px)); },
  ballistic: (p) => (((p.mg / 1000 + p.M) * Math.sqrt(2 * g * p.hh)) / (p.mg / 1000)),
  friction_stop: (p) => (0.5 * p.v ** 2) / (p.mu * g),
  ke_lost: (p) => (0.5 * p.m1 * p.v1 ** 2 * p.m2) / (p.m1 + p.m2),
  grav_force: (p) => (G * ME * p.m) / (RE + p.hkm * 1000) ** 2,
  g_planet: (p) => (p.variant === "surface" ? (G * p.M) / p.R ** 2 : (G * ME) / (RE + p.hkm * 1000) ** 2),
  orbit_speed: (p) => Math.sqrt((G * ME) / (RE + p.hkm * 1000)),
  orbit_period: (p) => { const r = RE + p.hkm * 1000, v = Math.sqrt((G * ME) / r); return (2 * Math.PI * r) / v / 3600; },
  escape: (p) => Math.sqrt((2 * G * p.M) / p.R),
  grav_pe: (p) => (-G * ME * p.m) / (RE + p.hkm * 1000) + (G * ME * p.m) / RE,
  coulomb: (p) => (k * p.q1 * p.q2 * 1e-12) / (p.rcm / 100) ** 2,
  e_field_point: (p) => (k * p.q * 1e-9) / p.d ** 2,
  e_field_two: (p) => (4 * k * (p.a + p.b) * 1e-6) / p.d ** 2,
  plates: (p) => (p.variant === "E" ? p.V / (p.dmm / 1000) : (e * p.V) / (p.dmm / 1000)),
  accel_V: (p) => Math.sqrt((2 * e * p.V) / (p.electron ? me : mp)),
  millikan: (p) => Math.round((p.m * g * (p.dmm / 1000)) / p.V / e),
  wire_force: (p) => p.I * p.L * p.B * S(p.th),
  charge_radius: (p) => ((p.electron ? me : mp) * p.v) / (e * p.B),
  moving_charge_force: (p) => e * p.v * p.B * S(p.th),
  wire_field: (p) => (2e-7 * p.I) / (p.rcm / 100),
  velocity_selector: (p) => p.V / (p.dmm / 1000) / p.B,
  freq_light: (p) => c / (p.lam * 1e-9),
  index: (p) => (p.variant === "lam" ? p.lam / p.n : c / p.n),
  snell: (p) => (p.variant === "refract" ? deg(Math.asin(S(p.th1) / p.n)) : deg(Math.asin(1 / p.n))),
  path_diff: (p) => (p.nodal ? (p.n - 0.5) * p.lam : p.n * p.lam),
  double_slit_spacing: (p) => ((p.lam * 1e-9 * p.L) / (p.dmm * 1e-3)) * 1e3,
  double_slit_lambda: (p) => (((p.span / p.k) * 1e-3 * (p.dmm * 1e-3)) / p.L) * 1e9,
  double_slit_angle: (p) => deg(Math.asin((p.m * p.lam * 1e-9) / (p.d * 1e-6))),
  grating: (p) => deg(Math.asin((p.m * p.lam * 1e-9) / (1 / (p.N * 100)))),
  single_slit: (p) => ((2 * p.lam * 1e-9 * p.L) / (p.w * 1e-3)) * 1e3,
  thin_film: (p) => (p.dark ? p.lam / p.n / 2 : p.lam / p.n / 4),
  antireflect: (p) => p.lam / p.nc / 4,
  air_wedge: (p) => ((p.lam * 1e-9 * (p.Lcm / 100)) / (2 * p.tum * 1e-6)) * 1e3,
  malus: (p) => (p.unpol ? 0.5 : 1) * p.I0 * Co(p.th) ** 2,
  photon_energy: (p) => ((h * c) / (p.lam * 1e-9)) / (p.eV ? e : 1),
  photoelectric: (p) => (h * c) / (p.lam * 1e-9) / e - p.W,
  threshold: (p) => (p.variant === "lam" ? ((h * c) / (p.W * e)) * 1e9 : (p.W * e) / h),
  work_function: (p) => (h * p.f) / e - p.Vs,
  debroglie: (p) => (p.variant === "e" ? (h / (me * p.v)) * 1e9 : h / (p.m * p.v)),
  debroglie_V: (p) => (h / Math.sqrt(2 * me * e * p.V)) * 1e9,
  photon_momentum: (p) => h / (p.lam * 1e-9),
  time_dilation: (p) => p.t0 * gamma(p.b),
  length_contraction: (p) => p.L0 / gamma(p.b),
  mass_energy: (p) => (p.mg / 1000) * c * c,
  muon: (p) => gamma(p.b) * 2.2e-6 * p.b * c,
  rel_momentum: (p) => gamma(p.b) * me * p.b * c,
  photon_count: (p) => (p.P / 1000) / ((h * c) / (p.lam * 1e-9)),
};

// Textbook problems worked by hand (answer, tolerance).
const KNOWN = [
  ["Range 20 m/s at 30° on level ground", (2 * 20 * 20 * S(30) * Co(30)) / g, 35.3],
  ["Orbital period 35 800 km up ≈ 24 h", REF.orbit_period({ hkm: 35800 }), 23.9],
  ["Escape speed from Earth", REF.escape({ M: ME, R: RE }), 11200],
  ["Electron through 100 V: λ ≈ 0.123 nm", REF.debroglie_V({ V: 100 }), 0.1227],
  ["Photon at 500 nm ≈ 2.49 eV", REF.photon_energy({ lam: 500, eV: true }), 2.486],
  ["γ at 0.6c is 1.25", gamma(0.6), 1.25],
  ["B 1.0 cm from 10 A wire = 2.0e-4 T", REF.wire_field({ I: 10, rcm: 1 }), 2.0e-4],
  ["E 1.0 m from 1 nC = 8.99 N/C", REF.e_field_point({ q: 1, d: 1 }), 8.99],
];

let fails = 0, checked = 0;
const fail = (msg) => { fails++; if (fails <= 40) console.log("FAIL " + msg); };
for (const [name, got, want] of KNOWN) if (Math.abs(got - want) / want > 0.01) fail(`known: ${name}: got ${got}, want ${want}`);

const bad = /NaN|undefined|Infinity|null|\[object/;
for (const sk of PQ.SKILLS) {
  if (!sk.concept && !REF[sk.id]) fail(`no REF for ${sk.id}`);
  const seen = new Set();
  for (let seed = 1; seed <= 400; seed++) {
    const q = PQ.makeQuestion(sk.id, seed * 7919 + 13);
    checked++;
    const where = `${sk.id} seed ${seed}`;
    const blob = [q.prompt, q.answerText, ...q.choices, ...(q.steps || []), q.formula || ""].join(" | ");
    if (bad.test(blob)) fail(`${where}: bad text: ${blob}`);
    if (q.choices.length !== 4 || new Set(q.choices).size !== 4) fail(`${where}: choices ${JSON.stringify(q.choices)}`);
    if (!(q.correct >= 0 && q.correct < 4) || q.choices[q.correct] !== q.answerText) fail(`${where}: correct index`);
    if (!q.prompt || q.prompt.length < 20) fail(`${where}: prompt`);
    seen.add(q.prompt);
    if (q.kind !== "num") continue;
    const ref = REF[sk.id] && REF[sk.id](q.params);
    if (!(Math.abs(ref - q.value) <= 1e-6 * Math.abs(ref) + 1e-300)) fail(`${where}: answer ${q.value} vs reference ${ref} (${JSON.stringify(q.params)})`);
    if (!q.signed && q.value <= 0) fail(`${where}: non-positive answer ${q.value}`);
    if (!PQ.checkTyped(q, q.answerText)) fail(`${where}: typed answer "${q.answerText}" rejected`);
    if (!PQ.checkTyped(q, String(q.value))) fail(`${where}: exact value rejected`);
    q.choices.forEach((ch, i) => { if (i !== q.correct && PQ.checkTyped(q, ch)) fail(`${where}: wrong choice "${ch}" accepted (answer ${q.answerText})`); });
  }
  if (seen.size < 8) fail(`${sk.id}: only ${seen.size} distinct prompts over 400 seeds`);
}

// The calculator and parser.
const calcCases = [["2+3*4", 14], ["2^10", 1024], ["-2^2", -4], ["sqrt(2*9.8*20)", Math.sqrt(392)], ["sin(30)", 0.5], ["6.63e-34*3e8/(500e-9)", 3.978e-19], ["(1+2)(3+4)", 21], ["2*pi", 2 * Math.PI], ["10^-3", 0.001], ["asin(0.5)", 30]];
for (const [src, want] of calcCases) { const got = PQ.calc(src); if (Math.abs(got - want) > 1e-9 * Math.max(1, Math.abs(want))) fail(`calc ${src} = ${got}, want ${want}`); }
for (const src of ["2+", "foo(2)", "(1", "1)"]) { let threw = false; try { PQ.calc(src); } catch (err) { threw = true; } if (!threw) fail(`calc should reject ${src}`); }
const parseCases = [["3.4 x 10^-19", 3.4e-19], ["3.4×10⁻¹⁹ J", 3.4e-19], ["-2.5 m/s", -2.5], ["12 electrons", 12], ["4.5e3 N/C", 4500], ["1,200", 1200]];
for (const [src, want] of parseCases) { const got = PQ.parseAnswer(src); if (Math.abs(got - want) > 1e-9 * Math.abs(want)) fail(`parse ${src} = ${got}, want ${want}`); }

const units = new Set(PQ.SKILLS.map((s) => s.unit));
if (units.size !== 5) fail("expected skills in all five units");
console.log(`${PQ.SKILLS.length} skills, ${checked} questions checked, ${fails} failures`);
console.log(fails ? "QUESTIONS FAIL" : "QUESTIONS OK");
process.exit(fails ? 1 : 0);
