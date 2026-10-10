/*
 * SLICE IT! — deterministic music + chart core (web edition).
 *
 * A line-for-line port of the Godot edition's SongComposer.compose() and
 * ConcertChart (godot/scripts/audio/SongComposer.gd,
 * godot/scripts/concert/ConcertChart.gd). Same xorshift32 PRNG, same tables,
 * same decisions in the same order — so a seed composes the same song and
 * the same chart in the browser as in the desktop game. Keep the two in
 * lockstep; tools/check_web_parity.py diffs them.
 *
 * This file is inlined into index.html by web/build.py; it also runs under
 * Node for the parity check (module.exports at the bottom).
 */
(function (root) {
  "use strict";

  const STEPS = 16;   // sixteenth notes per bar
  const BARS = 8;

  const SCALES = {
    major: [0, 2, 4, 5, 7, 9, 11],
    minor: [0, 2, 3, 5, 7, 8, 10],
    dorian: [0, 2, 3, 5, 7, 9, 10],
    mixolydian: [0, 2, 4, 5, 7, 9, 10],
    harmonic: [0, 2, 3, 5, 7, 8, 11],
  };

  // drum patterns: 16 steps of velocity. Key order matters (it is the order
  // the composer walks them, and hats draw from the PRNG) — keep it identical
  // to the GDScript dictionaries.
  const DRUMS = {
    half: {
      kick: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, .8, 0, 0, 0, 0, 0],
      snare: [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
      hat: [.7, 0, .4, 0, .6, 0, .4, 0, .7, 0, .4, 0, .6, 0, .4, .3],
    },
    half_funk: {
      kick: [1, 0, 0, .5, 0, 0, 0, 0, 0, 0, .9, 0, 0, .6, 0, 0],
      snare: [0, 0, 0, 0, 0, 0, 0, .25, 1, 0, 0, 0, 0, .25, 0, 0],
      hat: [.7, .25, .45, .25, .6, .25, .45, .25, .7, .25, .45, .25, .6, .25, .45, .3],
    },
    half_disco: {
      kick: [1, 0, 0, 0, .8, 0, 0, 0, 1, 0, 0, 0, .8, 0, 0, 0],
      clap: [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
      ohat: [0, 0, .6, 0, 0, 0, .6, 0, 0, 0, .6, 0, 0, 0, .6, 0],
      shaker: [.5, .3, .5, .3, .5, .3, .5, .3, .5, .3, .5, .3, .5, .3, .5, .3],
    },
    half_epic: {
      kick: [1, 0, 0, 0, 0, 0, .7, 0, 0, 0, .9, 0, 0, 0, .6, 0],
      snare: [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
      hat: [.6, 0, .5, 0, .6, 0, .5, 0, .6, 0, .5, 0, .6, 0, .5, 0],
      tom: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, .5, .6, .7],
    },
    half_soft: {
      kick: [.8, 0, 0, 0, 0, 0, 0, 0, 0, 0, .6, 0, 0, 0, 0, 0],
      snare: [0, 0, 0, 0, 0, 0, 0, 0, .7, 0, 0, 0, 0, 0, 0, 0],
      rim: [0, 0, 0, 0, 0, 0, 0, .3, 0, 0, 0, 0, 0, 0, .4, 0],
      shaker: [.5, .2, .4, .2, .5, .2, .4, .2, .5, .2, .4, .2, .5, .2, .4, .2],
    },
    funk: {
      kick: [1, 0, 0, 0, 0, 0, 0, .6, 0, 0, .9, 0, 0, 0, 0, 0],
      snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, .3],
      hat: [.6, .2, .4, .2, .6, .2, .4, .2, .6, .2, .4, .2, .6, .2, .4, .2],
    },
    four: {
      kick: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
      clap: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
      ohat: [0, 0, .7, 0, 0, 0, .7, 0, 0, 0, .7, 0, 0, 0, .7, 0],
      hat: [.3, .2, 0, .2, .3, .2, 0, .2, .3, .2, 0, .2, .3, .2, 0, .2],
    },
    drive: {
      kick: [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0],
      snare: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
      hat: [.7, .3, .5, .3, .7, .3, .5, .3, .7, .3, .5, .3, .7, .3, .5, .3],
    },
    gentle: {
      kick: [.6, 0, 0, 0, 0, 0, 0, 0, .45, 0, 0, 0, 0, 0, 0, 0],
      rim: [0, 0, 0, 0, .5, 0, 0, 0, 0, 0, 0, 0, .5, 0, 0, .25],
      shaker: [.4, .15, .3, .15, .4, .15, .3, .15, .4, .15, .3, .15, .4, .15, .3, .15],
    },
    oompah: {
      kick: [1, 0, 0, 0, 0, 0, 0, 0, .9, 0, 0, 0, 0, 0, 0, 0],
      snare: [0, 0, 0, 0, .45, 0, 0, 0, 0, 0, 0, 0, .45, 0, 0, 0],
      hat: [0, 0, .35, 0, 0, 0, .35, 0, 0, 0, .35, 0, 0, 0, .35, 0],
    },
  };

  // bass: [step, length, tone] — 0 root, 1 third, 2 fifth, 3 octave,
  // 4 seventh, 5 approach the next bar's root, 6 low fifth
  const BASS = {
    half: [[0, 6, 0], [10, 2, 0], [12, 2, 2], [14, 2, 3]],
    funk: [[0, 3, 0], [3, 1, 0], [6, 2, 3], [10, 2, 2], [12, 1, 0], [14, 2, 5]],
    octave: [[0, 2, 0], [2, 2, 3], [4, 2, 0], [6, 2, 3], [8, 2, 0], [10, 2, 3], [12, 2, 0], [14, 2, 3]],
    root8: [[0, 2, 0], [2, 2, 0], [4, 2, 0], [6, 2, 0], [8, 2, 0], [10, 2, 0], [12, 2, 2], [14, 2, 3]],
    walk: [[0, 4, 0], [4, 4, 1], [8, 4, 2], [12, 4, 5]],
    sparse: [[0, 7, 0], [8, 6, 6], [14, 2, 5]],
    oompah: [[0, 3, 0], [8, 3, 6]],
    epic: [[0, 8, 0], [8, 4, 0], [12, 4, 6]],
  };

  const COMP = {
    stab24: [[4, 2], [12, 2]],
    offbeat: [[2, 1], [6, 1], [10, 1], [14, 1]],
    push: [[0, 3], [3, 3], [10, 2], [14, 2]],
    lofi: [[0, 6], [6, 10]],
    pad: [[0, 16]],
    oompah: [[4, 2], [12, 2]],
    strum: [[0, 3], [6, 2], [8, 3], [12, 2], [14, 2]],
  };

  const RHYTHMS = {
    low: [
      [[0, 6], [8, 4], [12, 4], [16, 8], [24, 8]],
      [[0, 4], [4, 4], [8, 8], [16, 4], [20, 4], [24, 8]],
      [[2, 2], [4, 4], [8, 8], [18, 2], [20, 4], [24, 8]],
      [[0, 8], [10, 2], [12, 4], [16, 6], [22, 2], [24, 8]],
    ],
    mid: [
      [[0, 3], [3, 3], [6, 2], [8, 4], [12, 2], [14, 2], [16, 3], [19, 3], [22, 2], [24, 8]],
      [[0, 2], [2, 2], [4, 4], [8, 2], [10, 2], [12, 4], [16, 2], [18, 2], [20, 4], [24, 6], [30, 2]],
      [[0, 4], [6, 2], [8, 2], [10, 2], [12, 4], [16, 4], [22, 2], [24, 4], [28, 4]],
      [[2, 2], [4, 2], [6, 4], [10, 2], [12, 4], [18, 2], [20, 2], [22, 2], [24, 8]],
    ],
    high: [
      [[0, 2], [2, 2], [4, 1], [5, 1], [6, 2], [8, 2], [10, 2], [12, 2], [14, 2], [16, 2], [18, 1], [19, 1], [20, 2], [22, 2], [24, 4], [28, 2], [30, 2]],
      [[0, 1], [1, 1], [2, 2], [4, 2], [6, 2], [8, 3], [11, 1], [12, 4], [16, 1], [17, 1], [18, 2], [20, 2], [22, 2], [24, 6], [30, 2]],
      [[0, 2], [2, 1], [3, 1], [4, 2], [6, 2], [8, 2], [10, 2], [12, 4], [16, 2], [18, 2], [20, 1], [21, 1], [22, 2], [24, 8]],
    ],
  };

  const STYLES = {
    menu: { scales: ["dorian", "mixolydian"], root: [55, 60], drums: "funk", bass: "funk", bass_inst: "bass_funk", comp: "push", comp_inst: "ep", lead: "marimba", density: "low", progs: [[0, 3, 0, 3], [0, 3, 6, 4], [0, 5, 3, 4]], sevenths: true, lead_echo: 0.3 },
    funky: { scales: ["mixolydian", "dorian"], root: [52, 57], drums: "half_funk", bass: "funk", bass_inst: "bass_funk", comp: "offbeat", comp_inst: "pluck", lead: "lead_square", density: "mid", progs: [[0, 3, 0, 4], [0, 6, 3, 0], [0, 3, 6, 3]], sevenths: true, lead_echo: 0.25, half: true },
    farm: { scales: ["major"], root: [57, 62], drums: "gentle", bass: "sparse", bass_inst: "bass_round", comp: "strum", comp_inst: "uke", lead: "whistle", density: "low", progs: [[0, 3, 0, 4], [0, 5, 3, 4], [3, 4, 0, 0]], sevenths: false, lead_echo: 0.25 },
    town: { scales: ["major"], root: [55, 60], drums: "oompah", bass: "oompah", bass_inst: "bass_tuba", comp: "oompah", comp_inst: "accordion", lead: "accordion_lead", density: "high", progs: [[0, 4, 4, 0], [0, 3, 4, 0], [0, 0, 4, 4]], sevenths: false, lead_echo: 0.0 },
    arena: { scales: ["minor", "dorian"], root: [50, 55], drums: "drive", bass: "root8", bass_inst: "bass_synth", comp: "pad", comp_inst: "pad", lead: "lead_saw", density: "mid", progs: [[0, 5, 6, 4], [0, 6, 5, 6], [0, 3, 5, 4]], sevenths: false, lead_echo: 0.3, arp: true },
    dance: { scales: ["minor", "dorian"], root: [52, 57], drums: "four", bass: "octave", bass_inst: "bass_disco", comp: "offbeat", comp_inst: "organ", lead: "lead_square", density: "mid", progs: [[0, 5, 3, 4], [0, 6, 5, 6], [0, 3, 4, 3]], sevenths: false, lead_echo: 0.3, arp: true },
  };

  const CONCERT_STYLES = ["funky_live", "dance", "town", "menu", "arena", "farm"];

  const TITLE_A = ["Hash Brown", "Mashed", "Tater Tot", "Spudnik", "Chip Shop", "Golden Fry", "Wedge",
    "Gratin", "Rosti", "Jacket", "Starchy", "Peel-Good", "Couch Potato", "Hot Potato", "Russet",
    "Fingerling", "Sweet Potato", "Duchess", "Croquette", "Latke"];
  const TITLE_B = ["Hustle", "Boogie", "Shuffle", "Tango", "Groove", "Stomp", "Serenade", "Funk",
    "Waltz", "Breakdown", "Fever", "Jam", "Strut", "Express", "Anthem", "Bounce", "Blues", "Fiesta"];

  // ── xorshift32, seeded through an integer hash (identical to SongComposer.Rng) ──
  class Rng {
    constructor(seed) {
      let x = seed >>> 0;
      x = Math.imul((x >>> 16) ^ x, 0x45d9f3b) >>> 0;
      x = Math.imul((x >>> 16) ^ x, 0x45d9f3b) >>> 0;
      x = ((x >>> 16) ^ x) >>> 0;
      this.s = x === 0 ? 0x9E3779B9 : x;
      for (let i = 0; i < 4; i++) this.next();
    }
    next() {
      let x = this.s;
      x = (x ^ (x << 13)) >>> 0;
      x = (x ^ (x >>> 17)) >>> 0;
      x = (x ^ (x << 5)) >>> 0;
      this.s = x;
      return x;
    }
    unit() { return this.next() / 4294967296; }
    range(lo, hi) { return lo + Math.trunc(this.unit() * (hi - lo + 1)); }
    pick(arr) { return arr[Math.trunc(this.unit() * arr.length)]; }
    chance(p) { return this.unit() < p; }
  }

  const posmod = (a, n) => ((a % n) + n) % n;

  function songTitle(seed) {
    const r = new Rng((seed ^ 0x5bd1e995) >>> 0);
    return r.pick(TITLE_A) + " " + r.pick(TITLE_B);
  }

  function styleOf(id) {
    if (id === "funky_live") {
      const s = JSON.parse(JSON.stringify(STYLES.funky));
      s.drums = "funk";
      s.half = false;
      return s;
    }
    return STYLES[id] || STYLES.menu;
  }

  function degMidi(root, scale, deg) {
    const oct = Math.floor(deg / 7);
    return root + 12 * oct + scale[posmod(deg, 7)];
  }

  function compose(styleId, seed, bpm) {
    const st = styleOf(styleId);
    const rng = new Rng(seed);
    const scale = SCALES[rng.pick(st.scales)];
    const root = rng.range(st.root[0], st.root[1]);
    const prog = rng.pick(st.progs);
    const song = {
      style: styleId, seed, bpm, bars: BARS, loop_beats: BARS * 4, root, scale, title: songTitle(seed),
      chords: [], chord_degs: [], drums: [], bass: [], comp: [], arp: [], lead: [], fever: [], half: !!st.half,
    };
    for (let bar = 0; bar < BARS; bar++) {
      const deg = prog[bar % 4];
      song.chord_degs.push(deg);
      const tones = [deg, deg + 2, deg + 4];
      if (st.sevenths) tones.push(deg + 6);
      song.chords.push(tones.map((t) => degMidi(root, scale, t)));
    }
    composeDrums(song, st, rng);
    composeBass(song, st, rng, scale, root);
    composeComp(song, st, rng);
    composeLead(song, st, rng, scale, root);
    composeFever(song, st, scale, root);
    return song;
  }

  function composeDrums(song, st, rng) {
    const pat = DRUMS[st.drums];
    for (let bar = 0; bar < BARS; bar++) {
      for (const kind of Object.keys(pat)) {
        const row = pat[kind];
        for (let step = 0; step < STEPS; step++) {
          let v = row[step];
          if (kind === "tom" && bar % 4 !== 3) continue;
          if (v > 0) {
            if (kind === "hat" || kind === "shaker") v *= 0.85 + 0.3 * rng.unit();
            song.drums.push([bar * STEPS + step, kind, v]);
          }
        }
      }
      if (bar === BARS - 1 && pat.snare && !st.half) {
        for (const k of [13, 14, 15]) song.drums.push([bar * STEPS + k, "snare", 0.35 + 0.15 * (k - 13)]);
      }
      if (bar === BARS - 1 && st.half) {
        for (const k of [12, 14]) song.drums.push([bar * STEPS + k, pat.snare ? "snare" : "clap", 0.4]);
      }
    }
  }

  function composeBass(song, st, rng, scale, root) {
    const pat = BASS[st.bass];
    const degs = song.chord_degs;
    for (let bar = 0; bar < BARS; bar++) {
      const d = degs[bar];
      const nextD = degs[(bar + 1) % BARS];
      for (const e of pat) {
        let deg = d;
        switch (e[2]) {
          case 1: deg = d + 2; break;
          case 2: deg = d + 4; break;
          case 3: deg = d + 7; break;
          case 4: deg = d + 6; break;
          case 5: deg = nextD + (rng.chance(0.5) ? 1 : -1); break;
          case 6: deg = d - 3; break;
        }
        let m = degMidi(root - 24, scale, deg);
        while (m < 28) m += 12;
        while (m > 52) m -= 12;
        song.bass.push([bar * STEPS + e[0], e[1], m]);
      }
    }
  }

  function composeComp(song, st, rng) {
    const pat = COMP[st.comp];
    for (let bar = 0; bar < BARS; bar++) {
      const voiced = song.chords[bar].map((m) => {
        let v = m;
        while (v < 55) v += 12;
        while (v > 76) v -= 12;
        return v;
      }).sort((a, b) => a - b);
      for (const e of pat) song.comp.push([bar * STEPS + e[0], e[1], voiced]);
      if (st.arp) {
        for (let k = 0; k < 8; k++) song.arp.push([bar * STEPS + k * 2, 2, voiced[k % voiced.length] + 12]);
      }
    }
  }

  function mutateRhythm(base, rng) {
    const out = base.map((e) => [e[0], e[1]]);
    let i = 0;
    while (i < out.length) {
      const ln = out[i][1];
      if (ln >= 4 && rng.chance(0.18)) {
        const half = Math.trunc(ln / 2);
        out[i][1] = half;
        out.splice(i + 1, 0, [out[i][0] + half, ln - half]);
        i += 2;
        continue;
      }
      if (ln <= 2 && i + 1 < out.length && rng.chance(0.1) && out[i][0] % 4 === 0) {
        out[i][1] = ln + out[i + 1][1];
        out.splice(i + 1, 1);
      }
      i += 1;
    }
    return out;
  }

  function shape(contour, x) {
    switch (contour) {
      case "arch": return Math.sin(Math.PI * x) * 1.6 - 0.6;
      case "rise": return x * 2 - 1;
      case "fall": return 1 - x * 2;
      case "valley": return 0.6 - Math.sin(Math.PI * x) * 1.6;
    }
    return 0;
  }

  function nearestChordTone(deg, chordDeg) {
    let best = deg, bestD = 99;
    for (const oct of [-14, -7, 0, 7, 14]) {
      for (const t of [0, 2, 4]) {
        const c = chordDeg + t + oct;
        const dd = Math.abs(c - deg);
        if (dd < bestD) { bestD = dd; best = c; }
      }
    }
    return best;
  }

  // GDScript round() rounds halves away from zero (Math.round goes up)
  const roundHalfAway = (x) => (x < 0 ? -Math.round(-x) : Math.round(x));

  function phraseDegrees(rng, rhythm, contour, center, amp, song, bar0) {
    const out = [];
    let prev = center;
    for (let i = 0; i < rhythm.length; i++) {
      const step = rhythm[i][0];
      const ln = rhythm[i][1];
      const target = center + amp * shape(contour, step / 32);
      const cd = song.chord_degs[bar0 + Math.trunc(step / STEPS)];
      const strong = step % 8 === 0 || ln >= 4;
      let deg = prev;
      if (strong || i === 0) {
        deg = nearestChordTone(roundHalfAway(target), cd);
      } else {
        let dir = Math.sign(roundHalfAway(target) - prev);
        if (dir === 0) dir = rng.chance(0.5) ? 1 : -1;
        const r = rng.unit();
        if (r < 0.62) deg = prev + dir;
        else if (r < 0.82) deg = prev + 2 * dir;
        else if (r < 0.92) deg = prev - dir;
        else deg = prev;
      }
      deg = Math.min(Math.max(deg, center - 6), center + 8);
      prev = deg;
      out.push(deg);
    }
    return out;
  }

  function resnap(deg, note, song, bar0) {
    const step = note[0];
    const strong = step % 8 === 0 || note[1] >= 4;
    if (!strong) return deg;
    return nearestChordTone(deg, song.chord_degs[bar0 + Math.trunc(step / STEPS)]);
  }

  function composeLead(song, st, rng, scale, root) {
    const pool = RHYTHMS[st.density || "mid"];
    const rhythmA = mutateRhythm(rng.pick(pool), rng);
    const rhythmB = mutateRhythm(rng.pick(pool), rng);
    let center = 7;
    while (degMidi(root, scale, center) < 69) center += 7;
    while (degMidi(root, scale, center) > 80) center -= 7;
    const contours = ["arch", "rise", "fall", "valley"];
    const ca = rng.pick(contours);
    let cb = rng.pick(contours);
    while (cb === ca) cb = rng.pick(contours);
    const ampA = rng.range(3, 5);
    const ampB = rng.range(3, 6);
    const aDegs = phraseDegrees(rng, rhythmA, ca, center, ampA, song, 0);
    const a2 = aDegs.map((d, i) => resnap(d, rhythmA[i], song, 2));
    const tail = phraseDegrees(rng, rhythmA, "fall", center + 1, ampA, song, 2);
    for (let i = Math.max(0, a2.length - 3); i < a2.length; i++) a2[i] = tail[i];
    const bDegs = phraseDegrees(rng, rhythmB, cb, center + 2, ampB, song, 4);
    const a3 = aDegs.map((d, i) => resnap(d, rhythmA[i], song, 6));
    a3[a3.length - 1] = center;
    for (const [rhythm, degs, bar0] of [[rhythmA, aDegs, 0], [rhythmA, a2, 2], [rhythmB, bDegs, 4], [rhythmA, a3, 6]]) {
      for (let i = 0; i < rhythm.length; i++) {
        song.lead.push([bar0 * STEPS + rhythm[i][0], rhythm[i][1], degMidi(root, scale, degs[i])]);
      }
    }
  }

  function composeFever(song, st, scale, root) {
    const shapeIdx = [0, 1, 2, 3, 2, 1, 2, 3];
    for (let bar = 0; bar < BARS; bar++) {
      const cd = song.chord_degs[bar];
      const tones = [cd + 14, cd + 16, cd + 18, cd + 21];
      for (let k = 0; k < STEPS; k++) {
        song.fever.push([bar * STEPS + k, 1, degMidi(root, scale, tones[shapeIdx[k % shapeIdx.length]])]);
      }
    }
  }

  // ───────────────────────── ConcertChart ─────────────────────────

  const LOOPS = 4;
  const COUNT_IN = 4;
  const DIFFICULTIES = ["easy", "normal", "hard"];
  const RULES = {
    easy: { grid: 4, gap: 8, rotten: 0.06, hold_min: 8, speed: 200, miss_hype: 0.06 },
    normal: { grid: 2, gap: 4, rotten: 0.1, hold_min: 8, speed: 240, miss_hype: 0.08 },
    hard: { grid: 1, gap: 2, rotten: 0.13, hold_min: 6, speed: 290, miss_hype: 0.1 },
  };
  const STYLE_NAMES = {
    funky_live: "Street Funk", dance: "Disco Inferno", town: "Polka Plaza", menu: "Kitchen Groove",
    arena: "Spud Metal", farm: "Country Mash",
  };
  const STYLE_BPM = {
    funky_live: [108, 122], dance: [118, 128], town: [112, 124], menu: [98, 108],
    arena: [128, 142], farm: [92, 104],
  };
  const SETLIST = [11, 3, 8, 24, 13, 40];

  function specForSeed(seed) {
    const r = new Rng((seed ^ 0x2c1b3c6d) >>> 0);
    const style = CONCERT_STYLES[posmod(seed, CONCERT_STYLES.length)];
    const range = STYLE_BPM[style] || [110, 124];
    const bpm = r.range(range[0], range[1]);
    return { style, bpm, seed, title: songTitle(seed), style_name: STYLE_NAMES[style] || style };
  }

  function dailySeed(date) {
    const d = date || new Date();
    return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate();
  }

  function sectionName(beat, loopBeats) {
    if (beat < 0) return "COUNT-IN";
    return ["INTRO", "VERSE", "CHORUS"][Math.trunc(beat / loopBeats)] || "FINALE";
  }

  function buildChart(song, difficulty) {
    const rules = RULES[difficulty] || RULES.normal;
    const salt = DIFFICULTIES.indexOf(difficulty) + 1;
    const rng = new Rng(song.seed * 31 + salt);
    const loopSteps = song.bars * STEPS;
    const notes = [];
    let lastKind = "";
    for (let loopI = 0; loopI < LOOPS; loopI++) {
      let grid = rules.grid;
      const cands = [];
      if (loopI === 0) {
        for (const d of song.drums) {
          if ((d[1] === "kick" || d[1] === "snare" || d[1] === "clap") && d[2] >= 0.5) cands.push([d[0], 0, "drum"]);
        }
      } else {
        if (loopI === 1) grid = Math.min(grid * 2, 8);
        for (const l of song.lead) cands.push([l[0], l[1], "lead"]);
        if (loopI === 3) {
          for (const d of song.drums) {
            if ((d[1] === "snare" || d[1] === "clap") && d[2] >= 0.8) cands.push([d[0], 0, "drum"]);
          }
        }
      }
      cands.sort((a, b) => a[0] - b[0] || b[1] - a[1]);
      let nextFree = -999;
      for (const c of cands) {
        const st = c[0];
        if (st % grid !== 0 || st < nextFree) continue;
        const beat = loopI * loopSteps / 4 + st / 4;
        let kind = "chop";
        let length = 0;
        let occupied = st;
        if (c[2] === "lead" && c[1] >= rules.hold_min && lastKind !== "hold" && rng.chance(0.7)) {
          kind = "hold";
          length = c[1] / 4;
          occupied = st + c[1];
        } else if (notes.length > 2 && lastKind !== "rotten" && rng.chance(rules.rotten)) {
          kind = "rotten";
        } else if (rng.chance(loopI === 3 ? 0.09 : 0.05)) {
          kind = "golden";
        }
        if (kind === "hold" && occupied > loopSteps) {
          kind = "chop";
          length = 0;
          occupied = st;
        }
        notes.push({ beat, kind, len: length });
        lastKind = kind;
        nextFree = occupied + rules.gap;
      }
    }
    return notes;
  }

  const api = {
    STEPS, BARS, STYLES, DRUMS, Rng, compose, songTitle, styleOf,
    LOOPS, COUNT_IN, DIFFICULTIES, RULES, SETLIST, specForSeed, dailySeed, sectionName, buildChart,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.SliceCore = api;
})(this);
