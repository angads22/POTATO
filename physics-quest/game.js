/* Physics Quest 12 — the game: title, world map, battles, shop, codex, saves.
 * Questions come from questions.js (window.PQ). Everything is drawn in code. */
(function () {
  "use strict";
  const PQ = window.PQ;
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const rnd = (a, b) => a + Math.random() * (b - a);
  const wait = (ms) => new Promise((res) => setTimeout(res, ms));
  const UNIT = Object.fromEntries(PQ.UNITS.map((u) => [u.id, u]));

  // ================================================================ data
  const TILE = 40, ZW = 24, ZH = 18, MW = ZW * 3, MH = ZH * 2;
  const T_GROUND = 0, T_PROP = 1, T_WATER = 2, T_PATH = 3, T_WALL = 4, T_BUILD = 5, T_GATE = 10;
  const ZONES = [
    { id: "hub", unit: null, name: "Newton's Academy", gx: 0, gy: 0, lv: [1, 1], prop: "tree",
      pal: { g1: "#8fd06f", g2: "#84c564", path: "#e8cf98", wall: "#2e7d3a", water: "#4fa3e0", sky: ["#7ec8f5", "#c9ecff"] } },
    { id: "dyn", unit: "dyn", name: "Dynamo Dunes", gx: 1, gy: 0, lv: [1, 4], prop: "cactus", boss: { name: "The Unbalanced Force", lv: 5, tx: 12, ty: 3 },
      pal: { g1: "#f1d39a", g2: "#ebca88", path: "#d9ab6a", wall: "#b5793b", water: "#3fb0c9", sky: ["#ffb26b", "#ffe3b0"] } },
    { id: "enm", unit: "enm", name: "Momentum Mines", gx: 2, gy: 0, lv: [5, 8], prop: "rock", boss: { name: "The Kinetic Kraken", lv: 9, tx: 19, ty: 4 },
      pal: { g1: "#b99c7c", g2: "#b09272", path: "#8d6d4e", wall: "#5b4433", water: "#3b7fa8", sky: ["#5b4433", "#c9a57d"] } },
    { id: "fld", unit: "fld", name: "Field Fortress", gx: 2, gy: 1, lv: [9, 12], prop: "crystal", boss: { name: "The Magnetar Matriarch", lv: 13, tx: 18, ty: 13 },
      pal: { g1: "#7d70b2", g2: "#7467a8", path: "#a99ad8", wall: "#3b2e72", water: "#5b49c9", sky: ["#2c1f66", "#8c7bd8"] } },
    { id: "wav", unit: "wav", name: "Prism Peaks", gx: 1, gy: 1, lv: [13, 16], prop: "prism", boss: { name: "The Diffraction Dragon", lv: 17, tx: 12, ty: 14 },
      pal: { g1: "#dbeff8", g2: "#d0e7f3", path: "#aad0e2", wall: "#6aa6c4", water: "#6fc3ec", sky: ["#8fd3ff", "#f4fbff"] } },
    { id: "mod", unit: "mod", name: "Quantum Quasar", gx: 0, gy: 1, lv: [17, 20], prop: "asteroid", boss: { name: "Schrödinger's Cat-astrophe", lv: 21, tx: 5, ty: 9 },
      pal: { g1: "#221e42", g2: "#28234e", path: "#40397a", wall: "#0d0b1f", water: "#4b2a7a", sky: ["#05040f", "#2d2366"] } },
  ];
  const FINAL = { name: "Dr. Entropy", lv: 24 };
  const GATES = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]];
  const SPAWN = { tx: 12, ty: 9 };
  const NPCS = [
    { id: "guide", tx: 9, ty: 10, r: 46, label: "Talk to Professor Vector" },
    { id: "shop", tx: 5, ty: 4, r: 64, label: "Enter the Shop", solid: 2 },
    { id: "fountain", tx: 12, ty: 4, r: 56, label: "Drink from the Fountain (full heal)", solid: 1 },
    { id: "library", tx: 19, ty: 4, r: 64, label: "Open the Library (practice & unit tests)", solid: 2 },
    { id: "academy", tx: 19, ty: 14, r: 68, label: "Climb the Academy Tower", solid: 2 },
  ];
  const SPECIES = {
    dyn: [{ name: "Inertia Imp", shape: "blob", color: "#ff8c42" }, { name: "Friction Fiend", shape: "spiky", color: "#d1495b" }, { name: "Vector Viper", shape: "ghost", color: "#f6ae2d" }],
    enm: [{ name: "Joule Ghoul", shape: "ghost", color: "#2bb673" }, { name: "Impulse Golem", shape: "crystal", color: "#a0785a" }, { name: "Spring Sprite", shape: "blob", color: "#7bd389" }],
    fld: [{ name: "Coulomb Crab", shape: "spiky", color: "#ffd23f" }, { name: "Flux Phantom", shape: "ghost", color: "#b28dff" }, { name: "Gravi-Toad", shape: "blob", color: "#5e60ce" }],
    wav: [{ name: "Fringe Wisp", shape: "orb", color: "#4cc9f0" }, { name: "Refracto Ray", shape: "crystal", color: "#f72585" }, { name: "Lambda Lynx", shape: "spiky", color: "#9d4edd" }],
    mod: [{ name: "Photon Phantom", shape: "orb", color: "#fee440" }, { name: "Muon Moth", shape: "ghost", color: "#00f5d4" }, { name: "Quark Gremlin", shape: "blob", color: "#f15bb5" }],
  };
  const BOSS_LOOK = {
    dyn: { shape: "spiky", color: "#e85d04" }, enm: { shape: "blob", color: "#1b9e5a" }, fld: { shape: "crystal", color: "#7b2cbf" },
    wav: { shape: "orb", color: "#00b4d8" }, mod: { shape: "ghost", color: "#ff4fa3" }, final: { shape: "orb", color: "#3a0ca3" },
  };
  const SPELLS = [
    { id: "dyn1", unit: "dyn", name: "Net Force Bolt", power: 1.0 },
    { id: "dyn2", unit: "dyn", name: "Newton's Hammer", power: 1.7, mastery: true },
    { id: "enm1", unit: "enm", name: "Momentum Crash", power: 1.0 },
    { id: "enm2", unit: "enm", name: "Elastic Rebound", power: 1.7, mastery: true },
    { id: "fld1", unit: "fld", name: "Coulomb Spark", power: 1.0 },
    { id: "fld2", unit: "fld", name: "Magnetar Storm", power: 1.7, mastery: true },
    { id: "wav1", unit: "wav", name: "Prism Beam", power: 1.0 },
    { id: "wav2", unit: "wav", name: "Interference Lance", power: 1.7, mastery: true },
    { id: "mod1", unit: "mod", name: "Photon Burst", power: 1.0 },
    { id: "mod2", unit: "mod", name: "Quantum Tunnel", power: 1.7, mastery: true },
  ];
  const PETS = {
    newtie: { name: "Newtie", unit: "dyn", color: "#e63946", desc: "A tiny apple that never stops falling." },
    bouncy: { name: "Bouncy", unit: "enm", color: "#2bb673", desc: "A perfectly elastic ball. Loses no energy, ever." },
    sparky: { name: "Sparky", unit: "fld", color: "#ffd23f", desc: "A cheerful electron with a negative attitude." },
    prism: { name: "Prism", unit: "wav", color: "#4cc9f0", desc: "A photon that splits into rainbows when happy." },
    quarky: { name: "Quarky", unit: "mod", color: "#f15bb5", desc: "An up quark looking for its two friends." },
    neutrino: { name: "Neutrino", unit: null, color: "#b8c0ff", desc: "Barely interacts with anything. Very shy." },
  };
  const BOSS_PET = { dyn: "newtie", enm: "bouncy", fld: "sparky", wav: "prism", mod: "quarky" };
  const SHOP = [
    { id: "potion", kind: "item", name: "Energy Drink", desc: "Restores 50 HP.", price: 15 },
    { id: "mega", kind: "item", name: "Mega Battery", desc: "Restores all HP.", price: 45 },
    { id: "goggles", kind: "hat", name: "Lab Goggles", desc: "+10 max HP", hp: 10, price: 40 },
    { id: "wig", kind: "hat", name: "Wild Physicist Wig", desc: "+25 max HP", hp: 25, price: 120 },
    { id: "crown", kind: "hat", name: "Tesla Coil Crown", desc: "+45 max HP", hp: 45, price: 260 },
    { id: "halo", kind: "hat", name: "Electron Cloud Halo", desc: "+70 max HP", hp: 70, price: 450 },
    { id: "labcoat", kind: "robe", name: "Lab Coat", desc: "+8% spell damage", dmg: 0.08, price: 60, color: "#f4f4f4" },
    { id: "faraday", kind: "robe", name: "Faraday Cloak", desc: "+16% spell damage", dmg: 0.16, price: 180, color: "#8d99ae" },
    { id: "spacetime", kind: "robe", name: "Spacetime Robe", desc: "+25% spell damage", dmg: 0.25, price: 380, color: "#2b2d63" },
    { id: "neutrino", kind: "pet", name: "Neutrino (pet)", desc: "A companion. Pets strike after every correct answer.", price: 150 },
  ];
  const SHOP_ITEM = Object.fromEntries(SHOP.map((s) => [s.id, s]));
  const ROBE_COLORS = ["#6a5cff", "#e8455b", "#23a866", "#f08a24", "#1aa7ec", "#2b2d42"];
  const HAT_COLORS = ["#3d2c8d", "#ffb627", "#e8458b", "#1b9e5a", "#0b7ec2", "#7a1f2b"];
  const SKIN = ["#f6d2b0", "#e0ac7e", "#b67b52", "#7a4b2e"];

  // ================================================================ save
  const SAVE_KEY = "physicsQuest12.save.v1";
  const lsGet = (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const lsSet = (k, v) => { try { localStorage.setItem(k, v); return true; } catch (e) { return false; } };
  const lsDel = (k) => { try { localStorage.removeItem(k); } catch (e) { /* storage off */ } };
  function newSave(name, look) {
    return {
      v: 1, name, look, level: 1, xp: 0, hp: 100, coins: 25, unlocked: 1, bosses: {}, finalBeaten: false,
      items: { potion: 2, mega: 0 }, owned: [], hat: null, robe: null, pets: [], pet: null,
      mastery: {}, journal: [], qn: 0, pos: null, tests: {},
      settings: { mode: "mc", sound: true, allTopics: false },
      stats: { answered: 0, correct: 0, won: 0, bestStreak: 0, playSec: 0 },
    };
  }
  let save = null;
  function loadSave() {
    const raw = lsGet(SAVE_KEY);
    if (!raw) return null;
    try {
      const s = JSON.parse(raw);
      if (!s || s.v !== 1 || typeof s.name !== "string") return null;
      const base = newSave(s.name, s.look || {});
      for (const k of Object.keys(base)) if (s[k] === undefined) s[k] = base[k];
      s.settings = Object.assign(base.settings, s.settings);
      s.stats = Object.assign(base.stats, s.stats);
      s.items = Object.assign(base.items, s.items);
      return s;
    } catch (e) { return null; }
  }
  function persist() { if (save) lsSet(SAVE_KEY, JSON.stringify(save)); }

  // ================================================================ derived stats
  const xpNeed = (L) => 30 + 20 * L;
  const gearHp = () => (save.hat && SHOP_ITEM[save.hat] ? SHOP_ITEM[save.hat].hp : 0);
  const gearDmg = () => (save.robe && SHOP_ITEM[save.robe] ? SHOP_ITEM[save.robe].dmg : 0);
  const maxHp = () => 100 + 12 * (save.level - 1) + gearHp();
  const baseDmg = () => (18 + 5 * save.level) * (1 + gearDmg());
  function spellUnlocked(sp) {
    const zi = ZONES.findIndex((z) => z.unit === sp.unit);
    if (sp.mastery) return !!save.bosses[sp.unit];
    return save.unlocked >= zi || save.settings.allTopics;
  }

  // ================================================================ sound
  const Sound = {
    ctx: null,
    ensure() {
      if (this.ctx || !save || !save.settings.sound) return this.ctx;
      try { const AC = window.AudioContext || window.webkitAudioContext; if (AC) this.ctx = new AC(); } catch (e) { this.ctx = null; }
      return this.ctx;
    },
    tone(freq, start, dur, type = "square", vol = 0.06) {
      const c = this.ctx; if (!c) return;
      const o = c.createOscillator(), g = c.createGain();
      o.type = type; o.frequency.value = freq;
      g.gain.setValueAtTime(0, c.currentTime + start);
      g.gain.linearRampToValueAtTime(vol, c.currentTime + start + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + start + dur);
      o.connect(g).connect(c.destination); o.start(c.currentTime + start); o.stop(c.currentTime + start + dur + 0.02);
    },
    noise(start, dur, vol = 0.08) {
      const c = this.ctx; if (!c) return;
      const n = Math.floor(c.sampleRate * dur), buf = c.createBuffer(1, n, c.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / n);
      const s = c.createBufferSource(), g = c.createGain(); g.gain.value = vol; s.buffer = buf;
      s.connect(g).connect(c.destination); s.start(c.currentTime + start);
    },
    play(name) {
      if (!save || !save.settings.sound || !this.ensure()) return;
      if (this.ctx.state === "suspended") this.ctx.resume();
      const T = (f, s, d, t, v) => this.tone(f, s, d, t, v);
      switch (name) {
        case "select": T(660, 0, 0.06, "square", 0.04); break;
        case "correct": T(523, 0, 0.1, "triangle", 0.09); T(659, 0.08, 0.1, "triangle", 0.09); T(784, 0.16, 0.18, "triangle", 0.09); break;
        case "wrong": T(330, 0, 0.14, "sawtooth", 0.05); T(247, 0.12, 0.22, "sawtooth", 0.05); break;
        case "hit": this.noise(0, 0.18, 0.12); T(140, 0, 0.12, "square", 0.05); break;
        case "hurt": T(220, 0, 0.1, "square", 0.06); T(150, 0.08, 0.16, "square", 0.06); break;
        case "coin": T(988, 0, 0.07, "square", 0.04); T(1319, 0.06, 0.12, "square", 0.04); break;
        case "level": [523, 659, 784, 1047].forEach((f, i) => T(f, i * 0.09, 0.16, "triangle", 0.09)); break;
        case "win": [392, 523, 659, 784, 659, 784].forEach((f, i) => T(f, i * 0.1, 0.16, "triangle", 0.08)); break;
        case "heal": [440, 554, 659, 880].forEach((f, i) => T(f, i * 0.06, 0.14, "sine", 0.08)); break;
        case "encounter": T(196, 0, 0.12, "square", 0.05); T(262, 0.1, 0.12, "square", 0.05); T(392, 0.2, 0.2, "square", 0.05); break;
      }
    },
  };

  // ================================================================ map
  function hash2(x, y, s = 0) { let h = Math.imul(x * 374761393 + y * 668265263 + s * 2246822519, 3266489917) >>> 0; h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0; return ((h ^ (h >>> 16)) >>> 0) / 4294967296; }
  const map = new Uint8Array(MW * MH);
  const tget = (x, y) => (x < 0 || y < 0 || x >= MW || y >= MH ? T_WALL : map[y * MW + x]);
  const tset = (x, y, v) => { if (x >= 0 && y >= 0 && x < MW && y < MH) map[y * MW + x] = v; };
  const zoneIndexAtTile = (tx, ty) => ZONES.findIndex((z) => z.gx === Math.floor(tx / ZW) && z.gy === Math.floor(ty / ZH));
  const gateTiles = [];

  function buildMap() {
    const protectedCells = new Set();
    const protect = (x, y, r) => { for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) protectedCells.add((x + dx) + "," + (y + dy)); };
    ZONES.forEach((z) => {
      const ox = z.gx * ZW, oy = z.gy * ZH;
      for (let y = 0; y < ZH; y++) for (let x = 0; x < ZW; x++)
        tset(ox + x, oy + y, x === 0 || y === 0 || x === ZW - 1 || y === ZH - 1 ? T_WALL : T_GROUND);
    });
    const anchors = ZONES.map(() => []);
    GATES.forEach(([a, b]) => {
      const za = ZONES[a], zb = ZONES[b];
      const add = (x, y) => { tset(x, y, T_GATE + b); gateTiles.push({ x, y, target: b }); protect(x, y, 1); };
      if (za.gy === zb.gy) {
        const left = Math.min(za.gx, zb.gx), xL = left * ZW + ZW - 1;
        for (let y = za.gy * ZH + 8; y <= za.gy * ZH + 10; y++) { add(xL, y); add(xL + 1, y); }
        const mid = za.gy * ZH + 9;
        const leftZ = za.gx < zb.gx ? a : b, rightZ = za.gx < zb.gx ? b : a;
        anchors[leftZ].push([xL - 1, mid]); anchors[rightZ].push([xL + 2, mid]);
      } else {
        const top = Math.min(za.gy, zb.gy), yT = top * ZH + ZH - 1;
        for (let x = za.gx * ZW + 11; x <= za.gx * ZW + 13; x++) { add(x, yT); add(x, yT + 1); }
        const mid = za.gx * ZW + 12;
        const topZ = za.gy < zb.gy ? a : b, botZ = za.gy < zb.gy ? b : a;
        anchors[topZ].push([mid, yT - 1]); anchors[botZ].push([mid, yT + 2]);
      }
    });
    ZONES.forEach((z, zi) => {
      const ox = z.gx * ZW, oy = z.gy * ZH;
      anchors[zi].unshift([ox + 12, oy + 9]);
      if (z.boss) anchors[zi].push([ox + z.boss.tx, oy + z.boss.ty + 1]);
    });
    NPCS.forEach((n) => { anchors[0].push([n.tx, n.ty + 1]); protect(n.tx, n.ty, 2); });
    anchors.forEach((list) => list.forEach(([x, y]) => protect(x, y, 1)));
    ZONES.forEach((z) => { if (z.boss) protect(z.gx * ZW + z.boss.tx, z.gy * ZH + z.boss.ty, 2); });
    protect(SPAWN.tx, SPAWN.ty, 2);
    // ponds and props
    ZONES.forEach((z, zi) => {
      const ox = z.gx * ZW, oy = z.gy * ZH;
      const ponds = zi === 0 ? 1 : 2;
      for (let p = 0; p < ponds; p++) {
        const cx = ox + 3 + Math.floor(hash2(zi, p, 7) * (ZW - 6)), cy = oy + 3 + Math.floor(hash2(zi, p, 8) * (ZH - 6));
        const rx = 1.6 + hash2(zi, p, 9) * 1.4, ry = 1.2 + hash2(zi, p, 10) * 1.0;
        for (let y = cy - 3; y <= cy + 3; y++) for (let x = cx - 4; x <= cx + 4; x++)
          if (sqr((x - cx) / rx) + sqr((y - cy) / ry) <= 1 && tget(x, y) === T_GROUND && !protectedCells.has(x + "," + y)) tset(x, y, T_WATER);
      }
      for (let y = oy + 1; y < oy + ZH - 1; y++) for (let x = ox + 1; x < ox + ZW - 1; x++)
        if (tget(x, y) === T_GROUND && !protectedCells.has(x + "," + y) && hash2(x, y, 3) < (zi === 0 ? 0.07 : 0.11)) tset(x, y, T_PROP);
    });
    // paths: L-shaped from each zone's centre to its anchors
    anchors.forEach((list) => {
      const [cx, cy] = list[0];
      for (const [ax, ay] of list.slice(1)) {
        for (let y = Math.min(cy, ay); y <= Math.max(cy, ay); y++) pathAt(cx, y);
        for (let x = Math.min(cx, ax); x <= Math.max(cx, ax); x++) pathAt(x, ay);
      }
      pathAt(cx, cy);
    });
    // buildings
    NPCS.forEach((n) => {
      if (!n.solid) return;
      if (n.solid === 1) tset(n.tx, n.ty, T_BUILD);
      else for (let y = n.ty - 1; y <= n.ty; y++) for (let x = n.tx - 1; x <= n.tx + 1; x++) tset(x, y, T_BUILD);
    });
    // anything unreachable from spawn becomes scenery so monsters never spawn inside walls
    const seen = new Uint8Array(MW * MH), stack = [[SPAWN.tx, SPAWN.ty]];
    while (stack.length) {
      const [x, y] = stack.pop(); const i = y * MW + x;
      if (seen[i]) continue; seen[i] = 1;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy, t = tget(nx, ny);
        if ((t === T_GROUND || t === T_PATH || t >= T_GATE) && !seen[ny * MW + nx]) stack.push([nx, ny]);
      }
    }
    for (let y = 0; y < MH; y++) for (let x = 0; x < MW; x++) if (tget(x, y) === T_GROUND && !seen[y * MW + x]) tset(x, y, T_PROP);
  }
  function pathAt(x, y) { const t = tget(x, y); if (t === T_GROUND || t === T_PROP || t === T_WATER) tset(x, y, T_PATH); }
  const sqr = (x) => x * x;

  function passableTile(tx, ty) {
    const t = tget(tx, ty);
    if (t === T_GROUND || t === T_PATH) return true;
    if (t >= T_GATE) return save.unlocked >= t - T_GATE;
    return false;
  }
  function blockedAt(px, py, r) {
    const pts = [[px - r, py - r], [px + r, py - r], [px - r, py + r], [px + r, py + r]];
    for (const [x, y] of pts) if (!passableTile(Math.floor(x / TILE), Math.floor(y / TILE))) return true;
    return false;
  }

  // ================================================================ drawing: sprites
  function roundRect(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
  function shade(hex, f) {
    const n = parseInt(hex.slice(1), 16); let r = n >> 16, g = (n >> 8) & 255, b = n & 255;
    if (f < 0) { r *= 1 + f; g *= 1 + f; b *= 1 + f; } else { r += (255 - r) * f; g += (255 - g) * f; b += (255 - b) * f; }
    return "rgb(" + (r | 0) + "," + (g | 0) + "," + (b | 0) + ")";
  }

  function drawProp(c, kind, x, y, s, seed) {
    const v = hash2(x | 0, y | 0, 11);
    c.save(); c.translate(x, y);
    if (kind === "tree") {
      c.fillStyle = "rgba(0,0,0,.18)"; c.beginPath(); c.ellipse(0, s * 0.42, s * 0.36, s * 0.12, 0, 0, 7); c.fill();
      c.fillStyle = "#7a4a26"; c.fillRect(-s * 0.07, s * 0.05, s * 0.14, s * 0.36);
      c.fillStyle = v < 0.5 ? "#2f8f3e" : "#3a9a46";
      for (const [dx, dy, r] of [[-0.18, -0.02, 0.24], [0.17, -0.04, 0.24], [0, -0.22, 0.27]]) { c.beginPath(); c.arc(dx * s, dy * s, r * s, 0, 7); c.fill(); }
      c.fillStyle = "rgba(255,255,255,.18)"; c.beginPath(); c.arc(-s * 0.06, -s * 0.3, s * 0.09, 0, 7); c.fill();
      if (v > 0.8) { c.fillStyle = "#e63946"; c.beginPath(); c.arc(s * 0.12, -s * 0.12, s * 0.05, 0, 7); c.fill(); }
    } else if (kind === "cactus") {
      c.fillStyle = "rgba(0,0,0,.15)"; c.beginPath(); c.ellipse(0, s * 0.42, s * 0.25, s * 0.09, 0, 0, 7); c.fill();
      c.fillStyle = "#3f9b4f"; roundRect(c, -s * 0.1, -s * 0.38, s * 0.2, s * 0.8, s * 0.1); c.fill();
      roundRect(c, -s * 0.3, -s * 0.12, s * 0.1, s * 0.28, s * 0.05); c.fill(); c.fillRect(-s * 0.3, s * 0.08, s * 0.22, s * 0.08);
      if (v > 0.4) { roundRect(c, s * 0.2, -s * 0.24, s * 0.1, s * 0.26, s * 0.05); c.fill(); c.fillRect(s * 0.08, -s * 0.04, s * 0.22, s * 0.08); }
      c.fillStyle = "rgba(255,255,255,.25)"; c.fillRect(-s * 0.05, -s * 0.32, s * 0.04, s * 0.6);
      if (v > 0.85) { c.fillStyle = "#ff6fa8"; c.beginPath(); c.arc(0, -s * 0.4, s * 0.06, 0, 7); c.fill(); }
    } else if (kind === "rock") {
      c.fillStyle = "rgba(0,0,0,.2)"; c.beginPath(); c.ellipse(0, s * 0.36, s * 0.38, s * 0.1, 0, 0, 7); c.fill();
      c.fillStyle = v < 0.5 ? "#7b6a5a" : "#6c5c4e";
      c.beginPath(); c.moveTo(-s * 0.38, s * 0.34); c.lineTo(-s * 0.3, -s * 0.12); c.lineTo(-s * 0.05, -s * 0.32); c.lineTo(s * 0.26, -s * 0.2); c.lineTo(s * 0.38, s * 0.34); c.closePath(); c.fill();
      c.fillStyle = "rgba(255,255,255,.15)"; c.beginPath(); c.moveTo(-s * 0.28, -s * 0.1); c.lineTo(-s * 0.05, -s * 0.28); c.lineTo(0, -s * 0.05); c.closePath(); c.fill();
      if (v > 0.6) { c.fillStyle = "#ffd23f"; c.fillRect(s * 0.08, s * 0.02, s * 0.07, s * 0.07); c.fillRect(-s * 0.14, s * 0.16, s * 0.05, s * 0.05); }
    } else if (kind === "crystal") {
      c.fillStyle = "rgba(0,0,0,.2)"; c.beginPath(); c.ellipse(0, s * 0.38, s * 0.32, s * 0.1, 0, 0, 7); c.fill();
      const cols = ["#c77dff", "#9d4edd", "#e0aaff"];
      [[-0.16, 0.36, 0.12, 0.62], [0.05, 0.38, 0.14, 0.8], [0.22, 0.38, 0.1, 0.5]].forEach(([dx, by, w, h], i) => {
        c.fillStyle = cols[i]; c.beginPath(); c.moveTo((dx - w) * s, by * s); c.lineTo((dx - w) * s, (by - h * 0.75) * s); c.lineTo(dx * s, (by - h) * s); c.lineTo((dx + w) * s, (by - h * 0.75) * s); c.lineTo((dx + w) * s, by * s); c.closePath(); c.fill();
        c.fillStyle = "rgba(255,255,255,.3)"; c.fillRect((dx - w * 0.6) * s, (by - h * 0.7) * s, w * 0.4 * s, h * 0.6 * s);
      });
    } else if (kind === "prism") {
      c.fillStyle = "rgba(0,0,0,.12)"; c.beginPath(); c.ellipse(0, s * 0.38, s * 0.32, s * 0.1, 0, 0, 7); c.fill();
      c.fillStyle = "rgba(190,235,255,.9)"; c.strokeStyle = "#7cc2e0"; c.lineWidth = 2;
      c.beginPath(); c.moveTo(0, -s * 0.4); c.lineTo(s * 0.32, s * 0.34); c.lineTo(-s * 0.32, s * 0.34); c.closePath(); c.fill(); c.stroke();
      const rb = ["#ff595e", "#ffca3a", "#8ac926", "#1982c4", "#6a4c93"];
      rb.forEach((col, i) => { c.strokeStyle = col; c.lineWidth = 1.5; c.beginPath(); c.moveTo(s * 0.06, s * 0.0); c.lineTo(s * 0.42, s * (0.06 + i * 0.05)); c.stroke(); });
    } else if (kind === "asteroid") {
      c.fillStyle = "rgba(98,240,255,.12)"; c.beginPath(); c.arc(0, 0, s * 0.44, 0, 7); c.fill();
      c.fillStyle = v < 0.5 ? "#4a4470" : "#3d385e"; c.beginPath();
      for (let i = 0; i < 9; i++) { const a = (i / 9) * Math.PI * 2, rr = s * (0.28 + 0.08 * hash2(x | 0, y | 0, i)); c.lineTo(Math.cos(a) * rr, Math.sin(a) * rr); }
      c.closePath(); c.fill();
      c.fillStyle = "rgba(0,0,0,.3)"; c.beginPath(); c.arc(-s * 0.08, -s * 0.05, s * 0.07, 0, 7); c.arc(s * 0.1, s * 0.09, s * 0.05, 0, 7); c.fill();
    }
    c.restore();
  }

  function drawPlayer(c, x, y, s, look, t, moving, facing, opts = {}) {
    const bob = moving ? Math.abs(Math.sin(t * 10)) * s * 0.06 : Math.sin(t * 2) * s * 0.015;
    const robe = save && save.robe && SHOP_ITEM[save.robe] && !opts.ignoreGear ? SHOP_ITEM[save.robe].color : look.robe || ROBE_COLORS[0];
    const hatGear = opts.ignoreGear ? null : save && save.hat;
    c.save(); c.translate(x, y - bob); if (facing < 0) c.scale(-1, 1);
    c.fillStyle = "rgba(0,0,0,.22)"; c.beginPath(); c.ellipse(0, s * 0.5 + bob, s * 0.34, s * 0.1, 0, 0, 7); c.fill();
    // robe
    c.fillStyle = robe; c.beginPath(); c.moveTo(-s * 0.2, -s * 0.1); c.lineTo(s * 0.2, -s * 0.1); c.lineTo(s * 0.34, s * 0.48); c.lineTo(-s * 0.34, s * 0.48); c.closePath(); c.fill();
    c.fillStyle = "rgba(255,255,255,.18)"; c.fillRect(-s * 0.03, -s * 0.08, s * 0.06, s * 0.55);
    c.fillStyle = shade(robe.length === 7 ? robe : "#6a5cff", -0.25); c.fillRect(-s * 0.3, s * 0.38, s * 0.6, s * 0.1);
    // wand arm
    c.strokeStyle = "#6b3e1f"; c.lineWidth = Math.max(2, s * 0.05); c.beginPath(); c.moveTo(s * 0.18, s * 0.12); c.lineTo(s * 0.46, -s * 0.12); c.stroke();
    c.fillStyle = opts.wandColor || "#ffe66d"; c.shadowColor = opts.wandColor || "#ffe66d"; c.shadowBlur = s * 0.25;
    c.beginPath(); c.arc(s * 0.48, -s * 0.15, s * 0.06 + Math.sin(t * 6) * s * 0.01, 0, 7); c.fill(); c.shadowBlur = 0;
    // head
    c.fillStyle = look.skin || SKIN[0]; c.beginPath(); c.arc(0, -s * 0.28, s * 0.2, 0, 7); c.fill();
    c.fillStyle = "#1d1840"; c.beginPath(); c.arc(s * 0.07, -s * 0.3, s * 0.03, 0, 7); c.arc(-s * 0.04, -s * 0.3, s * 0.03, 0, 7); c.fill();
    c.strokeStyle = "#1d1840"; c.lineWidth = Math.max(1, s * 0.02); c.beginPath(); c.arc(s * 0.02, -s * 0.22, s * 0.06, 0.2, Math.PI - 0.2); c.stroke();
    // hat
    const hc = look.hat || HAT_COLORS[0];
    if (hatGear === "wig") {
      c.fillStyle = "#f5f5f5"; for (const [dx, dy] of [[-0.2, -0.38], [0.2, -0.38], [-0.12, -0.5], [0.12, -0.5], [0, -0.54]]) { c.beginPath(); c.arc(dx * s, dy * s, s * 0.11, 0, 7); c.fill(); }
    }
    c.fillStyle = hc; c.beginPath(); c.ellipse(0, -s * 0.42, s * 0.3, s * 0.07, 0, 0, 7); c.fill();
    c.beginPath(); c.moveTo(-s * 0.18, -s * 0.44); c.lineTo(s * 0.18, -s * 0.44); c.lineTo(s * 0.04, -s * 0.95); c.closePath(); c.fill();
    c.fillStyle = "#ffe66d"; star(c, s * 0.02, -s * 0.62, s * 0.06);
    if (hatGear === "goggles") {
      c.fillStyle = "#7fdbff"; c.strokeStyle = "#333"; c.lineWidth = 2;
      for (const dx of [-0.08, 0.1]) { c.beginPath(); c.arc(dx * s, -s * 0.31, s * 0.065, 0, 7); c.fill(); c.stroke(); }
    } else if (hatGear === "crown") {
      c.fillStyle = "#ffd23f"; c.beginPath(); c.moveTo(-s * 0.16, -s * 0.48); for (let i = 0; i < 5; i++) { c.lineTo(-s * 0.16 + i * s * 0.08, -s * (i % 2 ? 0.52 : 0.64)); } c.lineTo(s * 0.16, -s * 0.48); c.closePath(); c.fill();
      c.strokeStyle = "#7ce8ff"; c.lineWidth = 1.5; c.beginPath(); c.moveTo(0, -s * 0.64); for (let i = 1; i < 5; i++) c.lineTo((i % 2 ? 1 : -1) * s * 0.05, -s * (0.64 + i * 0.05)); c.stroke();
    } else if (hatGear === "halo") {
      c.strokeStyle = "rgba(178,141,255,.9)"; c.lineWidth = 2; c.beginPath(); c.ellipse(0, -s * 0.98, s * 0.22, s * 0.06, 0, 0, 7); c.stroke();
      c.fillStyle = "#62f0ff"; for (let i = 0; i < 3; i++) { const a = t * 3 + i * 2.1; c.beginPath(); c.arc(Math.cos(a) * s * 0.22, -s * 0.98 + Math.sin(a) * s * 0.06, s * 0.03, 0, 7); c.fill(); }
    }
    c.restore();
  }
  function star(c, x, y, r) { c.beginPath(); for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + (i * Math.PI) / 5, rr = i % 2 ? r * 0.45 : r; c.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr); } c.closePath(); c.fill(); }

  function drawMonster(c, x, y, s, look, t, opts = {}) {
    const col = look.color, dark = shade(col, -0.3), light = shade(col, 0.35);
    const bob = Math.sin(t * 3 + (opts.phase || 0)) * s * 0.04;
    c.save(); c.translate(x, y + bob); if (opts.flip) c.scale(-1, 1);
    if (opts.hurt) c.globalAlpha = 0.55 + 0.45 * Math.abs(Math.sin(t * 40));
    c.fillStyle = "rgba(0,0,0,.22)"; c.beginPath(); c.ellipse(0, s * 0.48 - bob, s * 0.4, s * 0.1, 0, 0, 7); c.fill();
    if (opts.boss) { c.shadowColor = col; c.shadowBlur = s * 0.4; }
    c.fillStyle = col;
    const shape = look.shape;
    if (shape === "blob") {
      c.beginPath(); c.ellipse(0, s * 0.08, s * 0.44, s * 0.38, 0, 0, 7); c.fill();
      c.fillStyle = dark; c.beginPath(); c.ellipse(-s * 0.22, s * 0.44, s * 0.1, s * 0.06, 0, 0, 7); c.ellipse(s * 0.22, s * 0.44, s * 0.1, s * 0.06, 0, 0, 7); c.fill();
    } else if (shape === "spiky") {
      c.beginPath(); for (let i = 0; i < 18; i++) { const a = (i / 18) * Math.PI * 2 + t * 0.4, rr = i % 2 ? s * 0.36 : s * 0.5; c.lineTo(Math.cos(a) * rr, s * 0.05 + Math.sin(a) * rr); } c.closePath(); c.fill();
    } else if (shape === "ghost") {
      c.beginPath(); c.arc(0, -s * 0.02, s * 0.38, Math.PI, 0); c.lineTo(s * 0.38, s * 0.42);
      for (let i = 0; i <= 6; i++) c.lineTo(s * 0.38 - (i * s * 0.76) / 6, s * 0.42 + (i % 2 ? -s * 0.1 : 0) + Math.sin(t * 6 + i) * s * 0.02);
      c.closePath(); c.fill();
    } else if (shape === "crystal") {
      c.beginPath(); c.moveTo(0, -s * 0.48); c.lineTo(s * 0.38, -s * 0.05); c.lineTo(s * 0.22, s * 0.44); c.lineTo(-s * 0.22, s * 0.44); c.lineTo(-s * 0.38, -s * 0.05); c.closePath(); c.fill();
      c.fillStyle = light; c.beginPath(); c.moveTo(0, -s * 0.48); c.lineTo(-s * 0.38, -s * 0.05); c.lineTo(-s * 0.1, -s * 0.02); c.closePath(); c.fill();
    } else {
      c.beginPath(); c.arc(0, 0, s * 0.36, 0, 7); c.fill();
      c.strokeStyle = light; c.lineWidth = Math.max(2, s * 0.04);
      c.beginPath(); c.ellipse(0, 0, s * 0.56, s * 0.16, t * 0.8, 0, 7); c.stroke();
      c.fillStyle = "#fff"; const a = t * 2.4; c.beginPath(); c.arc(Math.cos(a) * s * 0.56 * Math.cos(t * 0.8) - Math.sin(a) * s * 0.16 * Math.sin(t * 0.8), Math.cos(a) * s * 0.56 * Math.sin(t * 0.8) + Math.sin(a) * s * 0.16 * Math.cos(t * 0.8), s * 0.05, 0, 7); c.fill();
    }
    c.shadowBlur = 0;
    c.fillStyle = "rgba(255,255,255,.22)"; c.beginPath(); c.ellipse(-s * 0.14, -s * 0.12, s * 0.1, s * 0.06, -0.5, 0, 7); c.fill();
    // face
    const eyes = opts.final ? [[-0.15, -0.02], [0.15, -0.02], [0, -0.18]] : [[-0.13, 0], [0.13, 0]];
    for (const [ex, ey] of eyes) {
      c.fillStyle = "#fff"; c.beginPath(); c.arc(ex * s, ey * s, s * 0.09, 0, 7); c.fill();
      c.fillStyle = opts.final ? "#ff1744" : "#1d1840"; c.beginPath(); c.arc(ex * s - s * 0.02, ey * s + s * 0.01, s * 0.045, 0, 7); c.fill();
    }
    if (opts.boss || opts.final) {
      c.strokeStyle = "#1d1840"; c.lineWidth = Math.max(2, s * 0.035);
      c.beginPath(); c.moveTo(-s * 0.24, -s * 0.12); c.lineTo(-s * 0.06, -s * 0.07); c.moveTo(s * 0.24, -s * 0.12); c.lineTo(s * 0.06, -s * 0.07); c.stroke();
    }
    c.fillStyle = "#1d1840"; c.beginPath(); c.ellipse(0, s * 0.16, s * 0.12, s * (shape === "spiky" || opts.boss ? 0.07 : 0.04), 0, 0, Math.PI); c.fill();
    if (shape === "spiky" || opts.boss) { c.fillStyle = "#fff"; c.beginPath(); c.moveTo(-s * 0.08, s * 0.16); c.lineTo(-s * 0.05, s * 0.21); c.lineTo(-s * 0.02, s * 0.16); c.moveTo(s * 0.08, s * 0.16); c.lineTo(s * 0.05, s * 0.21); c.lineTo(s * 0.02, s * 0.16); c.fill(); }
    if (opts.boss && !opts.final) {
      c.fillStyle = "#ffd23f"; c.beginPath(); c.moveTo(-s * 0.2, -s * 0.36); c.lineTo(-s * 0.22, -s * 0.58); c.lineTo(-s * 0.1, -s * 0.46); c.lineTo(0, -s * 0.62); c.lineTo(s * 0.1, -s * 0.46); c.lineTo(s * 0.22, -s * 0.58); c.lineTo(s * 0.2, -s * 0.36); c.closePath(); c.fill();
      c.fillStyle = "#e63946"; c.beginPath(); c.arc(0, -s * 0.44, s * 0.035, 0, 7); c.fill();
    }
    if (opts.final) {
      for (let i = 0; i < 7; i++) { const a = t * 1.5 + i * 0.9; c.fillStyle = i % 2 ? "#ff1744" : "#7c4dff"; c.beginPath(); c.arc(Math.cos(a) * s * 0.62, Math.sin(a) * s * 0.42, s * 0.04, 0, 7); c.fill(); }
    }
    c.restore();
  }

  function drawPet(c, id, x, y, s, t) {
    const p = PETS[id]; if (!p) return;
    const bob = Math.sin(t * 5) * s * 0.12;
    c.save(); c.translate(x, y + bob);
    c.fillStyle = "rgba(0,0,0,.18)"; c.beginPath(); c.ellipse(0, s * 0.55 - bob, s * 0.3, s * 0.08, 0, 0, 7); c.fill();
    c.fillStyle = p.color;
    if (id === "prism") { c.beginPath(); c.moveTo(0, -s * 0.4); c.lineTo(s * 0.38, s * 0.3); c.lineTo(-s * 0.38, s * 0.3); c.closePath(); c.fill(); }
    else { c.beginPath(); c.arc(0, 0, s * 0.36, 0, 7); c.fill(); }
    if (id === "newtie") { c.fillStyle = "#2f8f3e"; c.beginPath(); c.ellipse(s * 0.1, -s * 0.42, s * 0.12, s * 0.06, -0.6, 0, 7); c.fill(); c.strokeStyle = "#6b3e1f"; c.lineWidth = 2; c.beginPath(); c.moveTo(0, -s * 0.34); c.lineTo(0, -s * 0.48); c.stroke(); }
    if (id === "sparky") { c.strokeStyle = "rgba(255,210,63,.7)"; c.lineWidth = 1.5; c.beginPath(); c.ellipse(0, 0, s * 0.6, s * 0.2, t, 0, 7); c.stroke(); }
    if (id === "neutrino") { c.globalAlpha = 0.6; }
    c.fillStyle = "#fff"; c.beginPath(); c.arc(-s * 0.11, -s * 0.03, s * 0.08, 0, 7); c.arc(s * 0.11, -s * 0.03, s * 0.08, 0, 7); c.fill();
    c.fillStyle = "#1d1840"; c.beginPath(); c.arc(-s * 0.1, -s * 0.02, s * 0.04, 0, 7); c.arc(s * 0.12, -s * 0.02, s * 0.04, 0, 7); c.fill();
    c.fillStyle = "#1d1840"; c.font = `bold ${Math.round(s * 0.26)}px sans-serif`; c.textAlign = "center";
    const glyph = { sparky: "−", quarky: "u", neutrino: "ν", bouncy: "", newtie: "", prism: "" }[id];
    if (glyph) c.fillText(glyph, 0, s * 0.26);
    c.restore();
  }

  function drawBuilding(c, id, x, y) {
    c.save(); c.translate(x, y);
    const label = (txt, yy) => { c.font = "bold 12px sans-serif"; c.textAlign = "center"; const w = c.measureText(txt).width + 12; c.fillStyle = "rgba(29,24,64,.85)"; roundRect(c, -w / 2, yy - 11, w, 16, 6); c.fill(); c.fillStyle = "#fff"; c.fillText(txt, 0, yy + 1); };
    if (id === "shop") {
      c.fillStyle = "#f3d9a4"; c.fillRect(-58, -40, 116, 70); c.fillStyle = "#d1495b"; c.beginPath(); c.moveTo(-66, -38); c.lineTo(0, -82); c.lineTo(66, -38); c.closePath(); c.fill();
      for (let i = -54; i < 54; i += 18) { c.fillStyle = i / 18 % 2 ? "#fff" : "#d1495b"; c.fillRect(i, -40, 18, 10); }
      c.fillStyle = "#7a4a26"; c.fillRect(-12, -2, 24, 32); c.fillStyle = "#8fd3ff"; c.fillRect(-46, -18, 22, 18); c.fillRect(24, -18, 22, 18);
      label("SHOP", -52);
    } else if (id === "library") {
      c.fillStyle = "#cfd8ff"; c.fillRect(-58, -44, 116, 74); c.fillStyle = "#4a5bc4"; c.beginPath(); c.moveTo(-66, -42); c.lineTo(0, -76); c.lineTo(66, -42); c.closePath(); c.fill();
      c.fillStyle = "#fff"; for (let i = -48; i <= 40; i += 22) c.fillRect(i, -36, 8, 62);
      c.fillStyle = "#3d2c8d"; c.fillRect(-12, 0, 24, 30);
      c.fillStyle = "#ffb627"; c.fillRect(-14, -30, 12, 16); c.fillStyle = "#e8458b"; c.fillRect(2, -30, 12, 16);
      label("LIBRARY", -54);
    } else if (id === "academy") {
      c.fillStyle = "#6a5cff"; c.fillRect(-56, -40, 112, 70); c.fillStyle = "#4b3fd1"; c.fillRect(-24, -110, 48, 74);
      c.fillStyle = "#ffb627"; c.beginPath(); c.moveTo(-32, -108); c.lineTo(0, -146); c.lineTo(32, -108); c.closePath(); c.fill();
      c.fillStyle = "#ffe66d"; star(c, 0, -152, 10);
      c.fillStyle = "#1d1840"; c.beginPath(); c.arc(0, 10, 14, Math.PI, 0); c.fillRect(-14, 10, 28, 20); c.fill();
      c.fillStyle = "#8fd3ff"; for (const yy of [-92, -64]) c.fillRect(-8, yy, 16, 16);
      label("ACADEMY", -30);
    } else if (id === "fountain") {
      c.fillStyle = "#b8b3c9"; c.beginPath(); c.ellipse(0, 6, 26, 14, 0, 0, 7); c.fill(); c.fillStyle = "#4fa3e0"; c.beginPath(); c.ellipse(0, 4, 20, 9, 0, 0, 7); c.fill();
      c.fillStyle = "#b8b3c9"; c.fillRect(-4, -22, 8, 26); c.fillStyle = "#8fd3ff"; c.beginPath(); c.arc(0, -24, 8, 0, 7); c.fill();
    }
    c.restore();
  }

  // ================================================================ drawing: the world
  let mapCanvas = null;
  function prerenderMap() {
    mapCanvas = document.createElement("canvas");
    mapCanvas.width = MW * TILE; mapCanvas.height = MH * TILE;
    const c = mapCanvas.getContext("2d");
    for (let ty = 0; ty < MH; ty++) for (let tx = 0; tx < MW; tx++) {
      const zi = zoneIndexAtTile(tx, ty), z = ZONES[zi], p = z.pal, t = tget(tx, ty);
      const x = tx * TILE, y = ty * TILE, v = hash2(tx, ty, 1);
      c.fillStyle = v < 0.5 ? p.g1 : p.g2; c.fillRect(x, y, TILE, TILE);
      if (z.id === "mod") { c.fillStyle = "rgba(255,255,255," + (0.3 + v * 0.6) + ")"; if (v > 0.55) c.fillRect(x + v * 30, y + hash2(tx, ty, 2) * 30, 2, 2); }
      else if (v > 0.7) { c.fillStyle = shade(p.g1, -0.12); c.fillRect(x + v * 28, y + hash2(tx, ty, 2) * 28, 3, 6); c.fillRect(x + v * 28 + 4, y + hash2(tx, ty, 2) * 28 + 2, 3, 4); }
      if (t === T_PATH || t >= T_GATE) {
        c.fillStyle = p.path; c.fillRect(x, y, TILE, TILE);
        c.fillStyle = "rgba(0,0,0,.06)"; if (v > 0.4) c.fillRect(x + v * 30, y + hash2(tx, ty, 4) * 30, 5, 3);
      } else if (t === T_WATER) {
        c.fillStyle = p.water; c.fillRect(x, y, TILE, TILE);
        c.strokeStyle = "rgba(255,255,255,.35)"; c.lineWidth = 2; c.beginPath(); c.arc(x + 12 + v * 10, y + 16, 6, Math.PI * 1.1, Math.PI * 1.9); c.stroke();
      } else if (t === T_WALL) {
        c.fillStyle = p.wall; c.fillRect(x, y, TILE, TILE);
        c.fillStyle = "rgba(255,255,255,.08)"; c.fillRect(x, y, TILE, 4);
      }
    }
    for (let ty = 0; ty < MH; ty++) for (let tx = 0; tx < MW; tx++) {
      const t = tget(tx, ty), z = ZONES[zoneIndexAtTile(tx, ty)];
      if (t === T_PROP || t === T_WALL) drawProp(c, z.prop, tx * TILE + TILE / 2, ty * TILE + TILE / 2 - 2, TILE * (t === T_WALL ? 1.05 : 0.95));
    }
    for (const n of NPCS) if (n.id !== "guide") drawBuilding(c, n.id, n.tx * TILE + TILE / 2, n.solid === 2 ? (n.ty + 1) * TILE - 30 : n.ty * TILE + 16);
  }

  // ================================================================ canvas + loop
  const cv = $("#game"), ctx = cv.getContext("2d");
  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = Math.min(2, window.devicePixelRatio || 1); W = window.innerWidth; H = window.innerHeight;
    cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR); cv.style.width = W + "px"; cv.style.height = H + "px";
  }
  window.addEventListener("resize", resize);

  let state = "title";             // title | world | battle
  let modalOpen = null;            // name of the open sheet, or null
  let clock = 0, lastT = 0;
  const player = { x: 0, y: 0, facing: 1, moving: false, petX: 0, petY: 0 };
  const keys = {};
  let moveTarget = null, encounterCooldown = 0, currentZone = -1, zoneLabelTimer = 0;
  let monsters = [];
  const respawnQueue = [];

  function placeAtSpawn() { player.x = SPAWN.tx * TILE + TILE / 2; player.y = SPAWN.ty * TILE + TILE / 2; player.petX = player.x - 30; player.petY = player.y; }

  function randomFreeSpot(zi, avoidPlayer) {
    const z = ZONES[zi];
    for (let tries = 0; tries < 200; tries++) {
      const tx = z.gx * ZW + 2 + Math.floor(Math.random() * (ZW - 4)), ty = z.gy * ZH + 2 + Math.floor(Math.random() * (ZH - 4));
      if (tget(tx, ty) !== T_GROUND) continue;
      const x = tx * TILE + TILE / 2, y = ty * TILE + TILE / 2;
      if (avoidPlayer && Math.hypot(x - player.x, y - player.y) < TILE * 6) continue;
      if (z.boss && Math.hypot(tx - (z.gx * ZW + z.boss.tx), ty - (z.gy * ZH + z.boss.ty)) < 3) continue;
      return { x, y };
    }
    return null;
  }
  function spawnMonster(zi, avoidPlayer = true) {
    const z = ZONES[zi], spot = randomFreeSpot(zi, avoidPlayer); if (!spot) return;
    const sp = SPECIES[z.unit][Math.floor(Math.random() * 3)];
    monsters.push({ zi, x: spot.x, y: spot.y, lv: z.lv[0] + Math.floor(Math.random() * (z.lv[1] - z.lv[0] + 1)), look: sp, name: sp.name, dir: Math.random() * 7, turn: rnd(1, 3), phase: Math.random() * 7 });
  }
  function populateMonsters() { monsters = []; for (let zi = 1; zi < ZONES.length; zi++) for (let i = 0; i < 5; i++) spawnMonster(zi, true); }

  function nearbyInteraction() {
    const hubZ = zoneIndexAtTile(Math.floor(player.x / TILE), Math.floor(player.y / TILE));
    for (const n of NPCS) {
      const cx = n.tx * TILE + TILE / 2, cy = n.solid === 2 ? (n.ty + 1) * TILE : n.ty * TILE + TILE / 2;
      if (Math.hypot(player.x - cx, player.y - cy) < n.r + 14) return { kind: "npc", id: n.id, label: n.label };
    }
    if (hubZ > 0) {
      const z = ZONES[hubZ];
      if (z.boss && !save.bosses[z.unit]) {
        const bx = (z.gx * ZW + z.boss.tx) * TILE + TILE / 2, by = (z.gy * ZH + z.boss.ty) * TILE + TILE / 2;
        if (Math.hypot(player.x - bx, player.y - by) < 72) return { kind: "boss", zi: hubZ, label: `Challenge ${z.boss.name} (Lv ${z.boss.lv})` };
      }
    }
    for (const g of gateTiles) {
      if (save.unlocked >= g.target) continue;
      if (Math.hypot(player.x - (g.x * TILE + TILE / 2), player.y - (g.y * TILE + TILE / 2)) < 60) {
        const prev = ZONES[g.target - 1];
        return { kind: "gate", label: `🔒 Sealed. Defeat ${prev.boss ? prev.boss.name : "the guardian"} to open the way to ${ZONES[g.target].name}.` };
      }
    }
    return null;
  }
  let lastPromptKey = "";
  function updatePrompt() {
    const el = $("#prompt");
    const it = state === "world" && !modalOpen ? nearbyInteraction() : null;
    const key = it ? it.label : "";
    if (key === lastPromptKey) return;
    lastPromptKey = key;
    if (!it) { el.classList.add("hidden"); el.onclick = null; return; }
    el.classList.remove("hidden");
    el.textContent = it.kind === "gate" ? it.label : (matchMedia("(pointer: coarse)").matches ? "" : "[E] ") + it.label;
    el.disabled = it.kind === "gate";
    el.onclick = () => interact();
  }
  function interact() {
    const it = nearbyInteraction(); if (!it || modalOpen || state !== "world") return;
    Sound.play("select");
    if (it.kind === "boss") return startBattle(makeEnemy({ boss: true, zi: it.zi }));
    if (it.kind !== "npc") return;
    if (it.id === "shop") openShop();
    else if (it.id === "library") openCodex("mastery");
    else if (it.id === "fountain") { save.hp = maxHp(); Sound.play("heal"); toast("You feel refreshed. HP fully restored!"); persist(); renderHud(); }
    else if (it.id === "guide") talkGuide();
    else if (it.id === "academy") {
      const all = PQ.UNITS.every((u) => save.bosses[u.id]);
      if (!all) dialog("Academy Tower", [`The tower's top floor is sealed by Dr. Entropy. Defeat all five region guardians first. (${PQ.UNITS.filter((u) => save.bosses[u.id]).length} of 5 defeated)`]);
      else dialog("Academy Tower", [save.finalBeaten ? "Dr. Entropy has re-formed from the chaos! A rematch is a great mixed review of the whole course." : "Dr. Entropy waits at the top. Every spell you know will be needed. This is the final exam!"], () => startBattle(makeEnemy({ final: true })), "Fight Dr. Entropy");
    }
  }

  function update(dt) {
    clock += dt;
    if (save && state !== "title") save.stats.playSec += dt;
    if (state !== "world" || modalOpen) { player.moving = false; return; }
    encounterCooldown = Math.max(0, encounterCooldown - dt);
    let dx = 0, dy = 0;
    if (keys.ArrowLeft || keys.KeyA) dx -= 1; if (keys.ArrowRight || keys.KeyD) dx += 1;
    if (keys.ArrowUp || keys.KeyW) dy -= 1; if (keys.ArrowDown || keys.KeyS) dy += 1;
    if (dx || dy) moveTarget = null;
    else if (moveTarget) {
      const tx = moveTarget.x - player.x, ty = moveTarget.y - player.y, d = Math.hypot(tx, ty);
      if (d < 6) moveTarget = null; else { dx = tx / d; dy = ty / d; }
    }
    const len = Math.hypot(dx, dy);
    player.moving = len > 0;
    if (len > 0) {
      const sp = 190 * dt, mx = (dx / len) * sp, my = (dy / len) * sp, r = 12;
      const bx = blockedAt(player.x + mx, player.y, r), by = blockedAt(player.x, player.y + my, r);
      if (!bx) player.x += mx; if (!by) player.y += my;
      if (bx && by && moveTarget) moveTarget = null;
      if (Math.abs(mx) > 0.01) player.facing = mx > 0 ? 1 : -1;
    }
    // pet follows with lag
    const pd = Math.hypot(player.x - player.petX, player.y - player.petY);
    if (pd > 34) { player.petX = lerp(player.petX, player.x - player.facing * 26, Math.min(1, dt * 4)); player.petY = lerp(player.petY, player.y + 6, Math.min(1, dt * 4)); }
    // zone banner
    const zi = zoneIndexAtTile(Math.floor(player.x / TILE), Math.floor(player.y / TILE));
    if (zi !== currentZone && zi >= 0) {
      currentZone = zi; const z = ZONES[zi];
      const lbl = $("#zoneLabel");
      lbl.innerHTML = esc(z.name) + "<small>" + (z.unit ? esc(UNIT[z.unit].name) + " · Lv " + z.lv[0] + "–" + z.lv[1] : "Safe zone") + "</small>";
      lbl.style.opacity = 1; zoneLabelTimer = 2.6;
    }
    if (zoneLabelTimer > 0) { zoneLabelTimer -= dt; if (zoneLabelTimer <= 0) $("#zoneLabel").style.opacity = 0; }
    // monsters wander and chase
    for (const m of monsters) {
      m.turn -= dt;
      const d = Math.hypot(player.x - m.x, player.y - m.y), sameZone = m.zi === zi;
      let ang = m.dir, speed = 34;
      if (sameZone && d < TILE * 3.2 && encounterCooldown <= 0) { ang = Math.atan2(player.y - m.y, player.x - m.x); speed = 70; }
      else if (m.turn <= 0) { m.dir = Math.random() * Math.PI * 2; m.turn = rnd(1.2, 3); ang = m.dir; }
      const nx = m.x + Math.cos(ang) * speed * dt, ny = m.y + Math.sin(ang) * speed * dt;
      const ntx = Math.floor(nx / TILE), nty = Math.floor(ny / TILE);
      if (!blockedAt(nx, ny, 14) && zoneIndexAtTile(ntx, nty) === m.zi && tget(ntx, nty) < T_GATE) { m.x = nx; m.y = ny; } else m.turn = 0;
      if (d < 30 && encounterCooldown <= 0) { startBattle(makeEnemy({ monster: m })); return; }
    }
    for (let i = respawnQueue.length - 1; i >= 0; i--) { respawnQueue[i].t -= dt; if (respawnQueue[i].t <= 0) { spawnMonster(respawnQueue[i].zi); respawnQueue.splice(i, 1); } }
    if (save) { save.pos = { x: Math.round(player.x), y: Math.round(player.y) }; }
    updatePrompt();
  }

  function camera() {
    const mw = MW * TILE, mh = MH * TILE;
    return { x: mw <= W ? (mw - W) / 2 : clamp(player.x - W / 2, 0, mw - W), y: mh <= H ? (mh - H) / 2 : clamp(player.y - H / 2, 0, mh - H) };
  }
  function renderWorld() {
    const cam = camera();
    ctx.fillStyle = "#0d0b22"; ctx.fillRect(0, 0, W, H);
    ctx.drawImage(mapCanvas, cam.x, cam.y, W, H, 0, 0, W, H);
    ctx.save(); ctx.translate(-cam.x, -cam.y);
    // sealed gates
    for (const g of gateTiles) {
      if (save.unlocked >= g.target) continue;
      const x = g.x * TILE, y = g.y * TILE;
      if (x + TILE < cam.x || x > cam.x + W || y + TILE < cam.y || y > cam.y + H) continue;
      ctx.fillStyle = "rgba(232,69,139,.55)"; ctx.fillRect(x, y, TILE, TILE);
      ctx.strokeStyle = "rgba(255,255,255,.55)"; ctx.lineWidth = 2;
      for (let k = 0; k < 3; k++) { const o = ((clock * 30 + k * 14) % 42) - 2; ctx.beginPath(); ctx.moveTo(x, y + o); ctx.lineTo(x + TILE, y + o - 10); ctx.stroke(); }
    }
    // sprites sorted by y
    const sprites = [];
    for (const m of monsters) sprites.push({ y: m.y, draw: () => { drawMonster(ctx, m.x, m.y - 10, 34, m.look, clock, { phase: m.phase, flip: Math.cos(m.dir) < 0 }); tag(m.x, m.y - 40, "Lv " + m.lv); } });
    ZONES.forEach((z) => {
      if (!z.boss || save.bosses[z.unit]) return;
      const bx = (z.gx * ZW + z.boss.tx) * TILE + TILE / 2, by = (z.gy * ZH + z.boss.ty) * TILE + TILE / 2;
      sprites.push({ y: by, draw: () => { drawMonster(ctx, bx, by - 18, 62, BOSS_LOOK[z.unit], clock, { boss: true }); tag(bx, by - 66, "BOSS · Lv " + z.boss.lv); } });
    });
    const gd = NPCS[0];
    sprites.push({ y: gd.ty * TILE + TILE / 2, draw: () => { drawPlayer(ctx, gd.tx * TILE + TILE / 2, gd.ty * TILE + TILE / 2 - 6, 40, { robe: "#5a189a", hat: "#9d4edd", skin: SKIN[1] }, clock, false, 1, { ignoreGear: true, wandColor: "#c77dff" }); tag(gd.tx * TILE + TILE / 2, gd.ty * TILE - 34, "Prof. Vector"); } });
    if (save.pet) sprites.push({ y: player.petY, draw: () => drawPet(ctx, save.pet, player.petX, player.petY - 6, 22, clock) });
    sprites.push({ y: player.y, draw: () => drawPlayer(ctx, player.x, player.y - 8, 42, save.look, clock, player.moving, player.facing) });
    sprites.sort((a, b) => a.y - b.y).forEach((s) => s.draw());
    if (moveTarget) { ctx.strokeStyle = "rgba(255,255,255,.7)"; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(moveTarget.x, moveTarget.y, 8 + Math.sin(clock * 8) * 2, 0, 7); ctx.stroke(); }
    ctx.restore();
  }
  function tag(x, y, text) {
    ctx.font = "bold 11px sans-serif"; ctx.textAlign = "center";
    const w = ctx.measureText(text).width + 10;
    ctx.fillStyle = "rgba(29,24,64,.78)"; roundRect(ctx, x - w / 2, y - 10, w, 15, 6); ctx.fill();
    ctx.fillStyle = "#fff"; ctx.fillText(text, x, y + 1);
  }

  function frame(ts) {
    const dt = Math.min(0.05, (ts - lastT) / 1000 || 0); lastT = ts;
    update(dt);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    if (state === "world") renderWorld();
    else if (state === "battle") renderBattle(dt);
    else renderTitleBackdrop();
    requestAnimationFrame(frame);
  }
  function renderTitleBackdrop() {
    ctx.fillStyle = "#14122b"; ctx.fillRect(0, 0, W, H);
  }

  // ================================================================ HUD + toasts
  function renderHud() {
    if (!save) return;
    const mh = maxHp(); save.hp = clamp(save.hp, 0, mh);
    $("#hudStats").innerHTML =
      `<div class="name">${esc(save.name)} · Lv ${save.level}</div>` +
      `<div class="bar"><i style="width:${(100 * save.hp) / mh}%"></i><span>HP ${Math.ceil(save.hp)}/${mh}</span></div>` +
      `<div class="bar xp"><i style="width:${(100 * save.xp) / xpNeed(save.level)}%"></i><span>XP ${save.xp}/${xpNeed(save.level)}</span></div>` +
      `<div>🪙 ${save.coins} · ✅ ${save.stats.correct}/${save.stats.answered}</div>`;
  }
  function toast(msg, ms = 2600) {
    const el = document.createElement("div"); el.className = "toast"; el.textContent = msg;
    $("#toasts").appendChild(el); setTimeout(() => el.remove(), ms);
  }

  // ================================================================ mastery + question picking
  const accOf = (id) => { const m = save.mastery[id]; return m && m.r.length ? m.r.reduce((a, b) => a + b, 0) / m.r.length : null; };
  const starsOf = (id) => { const m = save.mastery[id]; if (!m || m.r.length < 3) return 0; const a = accOf(id); return a >= 0.85 ? 3 : a >= 0.6 ? 2 : 1; };
  const tierStars = (t) => '<span class="stars" title="Difficulty ' + t + ' of 3">' + "★".repeat(t) + '<span class="off">' + "★".repeat(3 - t) + "</span></span>";
  let lastSkill = null;
  function pickSkill(unit, maxTier, minTier = 1) {
    let pool = PQ.SKILLS.filter((s) => s.unit === unit && s.tier <= maxTier && s.tier >= minTier);
    if (!pool.length) pool = PQ.SKILLS.filter((s) => s.unit === unit);
    const w = pool.map((s) => { const a = accOf(s.id); let x = a === null ? 2.2 : 1 + 2.2 * (1 - a); if (s.concept) x *= 0.7; if (s.id === lastSkill) x *= 0.08; return x; });
    let r = Math.random() * w.reduce((a, b) => a + b, 0);
    for (let i = 0; i < pool.length; i++) { r -= w[i]; if (r <= 0) return (lastSkill = pool[i].id); }
    return (lastSkill = pool[pool.length - 1].id);
  }
  function newQuestion(skillId) {
    save.qn = (save.qn + 1) | 0;
    return PQ.makeQuestion(skillId, (Date.now() ^ Math.imul(save.qn, 2654435761)) >>> 0);
  }
  function record(q, ok) {
    save.stats.answered++; if (ok) save.stats.correct++;
    const m = save.mastery[q.skill] || (save.mastery[q.skill] = { n: 0, c: 0, r: [] });
    m.n++; if (ok) m.c++; m.r.push(ok ? 1 : 0); if (m.r.length > 8) m.r.shift();
    if (!ok) {
      save.journal.unshift({ skill: q.skill, prompt: q.prompt, answer: q.answerText, steps: q.steps, formula: q.formula, t: Date.now() });
      if (save.journal.length > 40) save.journal.length = 40;
    }
    persist();
  }
  const useTyped = (q) => q.kind === "num" && (save.settings.mode === "type" || (save.settings.mode === "mixed" && q.tier >= 2));
  const constTable = () => '<table class="consts">' + PQ.CONSTANTS.map(([s, v, d]) => `<tr><td><b>${esc(s)}</b></td><td>${esc(v)}</td><td class="muted">${esc(d)}</td></tr>`).join("") + "</table>";

  // ================================================================ the question sheet
  let curQ = null, qPhase = null, qHandlers = null;
  function openQuestion(q, opts = {}) {
    return new Promise((resolve) => {
      curQ = q; qPhase = "ask";
      const typed = useTyped(q), sk = PQ.SKILL[q.skill], u = UNIT[q.unit];
      let hint = false, done = false;
      const el = $("#qSheet");
      el.innerHTML =
        `<div class="qhead"><span class="chip" style="background:${u.color}">${esc(u.short)}</span><b>${esc(sk.name)}</b>${tierStars(q.tier)}<span class="spacer"></span>${opts.header ? `<span class="muted">${esc(opts.header)}</span>` : ""}</div>` +
        `<div class="qprompt">${esc(q.prompt)}</div>` +
        (typed
          ? `<div class="qtyped"><input id="typedInput" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="e.g. 3.42e-19" aria-label="Your answer"><span class="unit">${esc(q.unitLabel || "")}</span><button id="typedSubmit" class="good">${esc(opts.cta || "Submit")}</button></div>` +
            `<div class="muted" style="font-size:12px;margin-top:5px">Within 2% counts. Write powers of ten as 3.4e-19 or 3.4 x 10^-19, or type an expression like 2*9.8*15.</div>`
          : `<div class="qchoices">${q.choices.map((c, i) => `<button class="choice" data-i="${i}"><b>${"ABCD"[i]}</b>${esc(c)}</button>`).join("")}</div>`) +
        `<div class="qtools">${q.formula ? `<button id="qHint">💡 Formula hint${opts.hintCost ? " (spell is weaker)" : ""}</button>` : ""}<button id="qCalcBtn">🧮 Calculator</button><button id="qConstBtn">📘 Constants</button></div>` +
        `<div id="qHintBox" class="qbox hidden"></div>` +
        `<div id="qCalcBox" class="qbox hidden"><div class="row"><input id="calcIn" style="flex:1;min-width:150px" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="e.g. 6.63e-34*3e8/(500e-9)" aria-label="Calculator">${typed ? '<button id="calcUse" class="small">Use as answer</button>' : ""}</div><div id="calcOut" class="muted">Trig uses degrees. sqrt( ) ^ pi asin( ) log( ) ln( ) work.</div>` +
        `<div class="calc-keys">${["×10^", "^", "√(", "sin(", "cos(", "tan(", "asin(", "atan(", "π", "(", ")"].map((k) => `<button class="small" data-k="${k}">${k}</button>`).join("")}<button class="small" data-k="C">Clear</button></div></div>` +
        `<div id="qConstBox" class="qbox hidden">${constTable()}</div><div id="qFeedback"></div>`;
      $("#qModal").classList.remove("hidden");
      const toggle = (id) => $(id).classList.toggle("hidden");
      if ($("#qHint")) $("#qHint").onclick = () => { hint = true; const b = $("#qHintBox"); b.classList.remove("hidden"); b.innerHTML = "Key formula: <b>" + esc(q.formula) + "</b>"; $("#qHint").disabled = true; };
      $("#qCalcBtn").onclick = () => { toggle("#qCalcBox"); if (!$("#qCalcBox").classList.contains("hidden")) $("#calcIn").focus(); };
      $("#qConstBtn").onclick = () => toggle("#qConstBox");
      const calcIn = $("#calcIn");
      const evalCalc = () => {
        const src = calcIn.value.trim(); if (!src) { $("#calcOut").textContent = ""; return null; }
        try { const v = PQ.calc(src); $("#calcOut").textContent = isFinite(v) ? "= " + PQ.fmt(v, 4) + (Math.abs(v) >= 1e5 || (Math.abs(v) < 1e-3 && v !== 0) ? "   (" + v.toExponential(3) + ")" : "") : "= " + v; return v; }
        catch (err) { $("#calcOut").textContent = "…"; return null; }
      };
      calcIn.oninput = evalCalc;
      el.querySelectorAll(".calc-keys button").forEach((b) => b.onclick = () => {
        const k = b.dataset.k;
        if (k === "C") calcIn.value = ""; else calcIn.value += { "×10^": "*10^", "√(": "sqrt(", "π": "pi" }[k] || k;
        calcIn.focus(); evalCalc();
      });
      if ($("#calcUse")) $("#calcUse").onclick = () => { const v = evalCalc(); if (v !== null && isFinite(v)) { $("#typedInput").value = Math.abs(v) >= 1e5 || (Math.abs(v) < 1e-3 && v !== 0) ? v.toExponential(4) : String(Number(v.toPrecision(6))); $("#typedInput").focus(); } };

      function finish(ok, chosen, typedText) {
        if (done) return; done = true; qPhase = "feedback";
        Sound.play(ok ? "correct" : "wrong");
        el.querySelectorAll(".choice").forEach((b, i) => { b.disabled = true; if (i === q.correct) b.classList.add("right"); else if (i === chosen) b.classList.add("wrong"); });
        if ($("#typedInput")) { $("#typedInput").disabled = true; $("#typedSubmit").disabled = true; }
        const steps = `<ol>${q.steps.map((s) => `<li>${esc(s)}</li>`).join("")}</ol>`;
        const btns = `<div class="row" style="margin-top:8px">${(opts.buttons || [{ id: "continue", label: "Continue" }]).map((b, i) => `<button class="${i ? "ghost" : "good"} qbtn" data-a="${b.id}" ${i === 0 ? 'id="qContinue"' : ""}>${esc(b.label)}</button>`).join("")}</div>`;
        $("#qFeedback").innerHTML = ok
          ? `<div class="feedback ok"><h3>✔ Correct!</h3>${q.kind === "num" ? `<div>Answer: <b>${esc(q.answerText)}</b></div>` : ""}<details><summary>Show the solution</summary>${steps}</details>${btns}</div>`
          : `<div class="feedback no"><h3>✘ Not quite</h3>${typedText !== undefined ? `<div>You entered: <b>${esc(typedText || "(nothing)")}</b></div>` : ""}<div>Correct answer: <b>${esc(q.answerText)}</b></div>${steps}${q.formula ? `<div class="muted">Key formula: ${esc(q.formula)}</div>` : ""}<div class="muted" style="font-size:12px">Saved to your Codex mistake journal.</div>${btns}</div>`;
        el.querySelectorAll(".qbtn").forEach((b) => b.onclick = () => close(b.dataset.a));
        const fb = $("#qFeedback"); if (fb.scrollIntoView) fb.scrollIntoView({ block: "nearest" });
        setTimeout(() => { const c = $("#qContinue"); if (c) c.focus({ preventScroll: true }); }, 30);
        function close(action) { $("#qModal").classList.add("hidden"); curQ = null; qPhase = null; qHandlers = null; resolve({ correct: ok, hint, action }); }
        qHandlers = { cont: () => close((opts.buttons || [{ id: "continue" }])[0].id) };
      }
      el.querySelectorAll(".choice").forEach((b) => b.onclick = () => finish(+b.dataset.i === q.correct, +b.dataset.i));
      if (typed) {
        const submit = () => { const v = $("#typedInput").value; if (!v.trim()) { $("#typedInput").focus(); return; } finish(PQ.checkTyped(q, v), -1, v); };
        $("#typedSubmit").onclick = submit;
        $("#typedInput").onkeydown = (ev) => { if (ev.key === "Enter") { ev.preventDefault(); ev.stopPropagation(); submit(); } };
        setTimeout(() => { const t = $("#typedInput"); if (t && !matchMedia("(pointer: coarse)").matches) t.focus(); }, 30);
      }
      qHandlers = { choose: (i) => { if (!typed && !done) finish(i === q.correct, i); } };
    });
  }

  // ================================================================ battle
  let battle = null;
  function makeEnemy({ monster, boss, zi, final }) {
    if (final) { const lv = FINAL.lv; return { name: FINAL.name, lv, hp: Math.round((30 + 14 * lv) * 3), atk: Math.round((5 + 2.6 * lv) * 1.25), unit: null, look: BOSS_LOOK.final, boss: true, final: true, zi: 0 }; }
    if (boss) { const z = ZONES[zi], lv = z.boss.lv; return { name: z.boss.name, lv, hp: Math.round((30 + 14 * lv) * 2.4), atk: Math.round((5 + 2.6 * lv) * 1.2), unit: z.unit, look: BOSS_LOOK[z.unit], boss: true, zi }; }
    const z = ZONES[monster.zi];
    return { name: monster.name, lv: monster.lv, hp: 30 + 14 * monster.lv, atk: Math.round(5 + 2.6 * monster.lv), unit: z.unit, look: monster.look, zi: monster.zi, ref: monster };
  }
  function startBattle(enemy) {
    enemy.max = enemy.hp;
    battle = { enemy, phase: "menu", streak: 0, fx: [], parts: [], floaters: [], shake: 0, enemyHurt: 0, playerHurt: 0, lunge: 0, dying: 0, sub: null };
    state = "battle"; moveTarget = null; for (const k in keys) keys[k] = false;
    $("#hud").classList.add("hidden"); $("#prompt").classList.add("hidden"); lastPromptKey = "\u0000";
    $("#zoneLabel").style.opacity = 0;
    $("#battleUI").classList.remove("hidden");
    Sound.play("encounter");
    setMsg(enemy.final ? "Dr. Entropy: “All order decays. Prove me wrong!”" : enemy.boss ? `${enemy.name} blocks your path!` : `A wild ${enemy.name} appears!`);
    renderBattleBars(); renderBattleMenu();
  }
  function setMsg(t) { $("#bMsg").textContent = t; }
  function renderBattleBars() {
    if (!battle) return;
    const e = battle.enemy, mh = maxHp();
    const mom = battle.streak > 1 ? ` · Momentum ×${(1 + Math.min(0.5, 0.1 * (battle.streak - 1))).toFixed(1)}` : "";
    $("#bPlayer").innerHTML = `<b>${esc(save.name)} · Lv ${save.level}</b><div class="bar"><i style="width:${(100 * save.hp) / mh}%"></i><span>${Math.ceil(save.hp)}/${mh}</span></div><div class="muted" style="font-size:12px">Streak ${battle.streak}${mom}</div>`;
    $("#bEnemy").innerHTML = `<b>${esc(e.name)} · Lv ${e.lv}</b><div class="bar enemy"><i style="width:${(100 * e.hp) / e.max}%"></i><span>${Math.ceil(e.hp)}/${e.max}</span></div><div class="muted" style="font-size:12px">${e.unit ? "Weak to " + esc(UNIT[e.unit].short) + " spells" : "Weak to everything you know"}</div>`;
  }
  function renderBattleMenu() {
    const box = $("#bMenuInner"); if (!battle) return;
    if (battle.phase === "over") return;
    if (battle.phase !== "menu") { box.innerHTML = ""; return; }
    if (battle.sub === "items") {
      box.innerHTML = `<div class="spells">${["potion", "mega"].map((id) => `<button class="spell-btn item-btn" data-id="${id}" style="background:#23a866" ${save.items[id] ? "" : "disabled"}>${esc(SHOP_ITEM[id].name)} ×${save.items[id] || 0}<small>${esc(SHOP_ITEM[id].desc)} Uses your turn.</small></button>`).join("")}</div><div class="actions"><button class="ghost" id="bBack">Back</button></div>`;
      box.querySelectorAll(".item-btn").forEach((b) => b.onclick = () => useItem(b.dataset.id));
      $("#bBack").onclick = () => { battle.sub = null; renderBattleMenu(); };
      return;
    }
    const spells = SPELLS.filter(spellUnlocked), e = battle.enemy;
    box.innerHTML = `<div class="spells">${spells.map((sp, i) => {
      const eff = e.unit === sp.unit;
      return `<button class="spell-btn" data-i="${i}" style="background:${UNIT[sp.unit].color}">${eff ? '<span class="eff">SUPER EFFECTIVE</span>' : ""}<span>${i < 9 ? i + 1 + ". " : ""}${esc(sp.name)}</span><small>${esc(UNIT[sp.unit].short)} · ${sp.mastery ? "hard questions · " : ""}power ${sp.power}</small></button>`;
    }).join("")}</div><div class="actions"><button class="ghost" id="bItems">🧃 Items (${(save.items.potion || 0) + (save.items.mega || 0)})</button>${e.boss ? "" : '<button class="ghost" id="bRun">🏃 Run away</button>'}</div>`;
    box.querySelectorAll(".spell-btn").forEach((b) => b.onclick = () => castSpell(spells[+b.dataset.i]));
    $("#bItems").onclick = () => { battle.sub = "items"; renderBattleMenu(); };
    if ($("#bRun")) $("#bRun").onclick = flee;
  }
  async function castSpell(sp) {
    if (!battle || battle.phase !== "menu") return;
    battle.phase = "question"; renderBattleMenu();
    const e = battle.enemy;
    let maxTier, minTier = 1;
    if (sp.mastery) { minTier = 2; maxTier = 3; }
    else if (e.boss) maxTier = 3;
    else if (e.unit === sp.unit) maxTier = e.lv - ZONES[e.zi].lv[0] >= 2 ? 2 : 1;
    else maxTier = save.bosses[sp.unit] ? 3 : 2;
    const q = newQuestion(pickSkill(sp.unit, maxTier, minTier));
    const res = await openQuestion(q, { header: "Casting " + sp.name, hintCost: true, cta: "Cast!" });
    record(q, res.correct);
    if (!battle) return;
    if (res.correct) {
      battle.streak++; save.stats.bestStreak = Math.max(save.stats.bestStreak, battle.streak);
      const eff = e.unit === sp.unit ? 1.5 : e.final ? 1.2 : 1;
      const mult = 1 + Math.min(0.5, 0.1 * (battle.streak - 1));
      const dmg = Math.max(1, Math.round(baseDmg() * sp.power * eff * mult * (res.hint ? 0.6 : 1) * rnd(0.9, 1.1)));
      await playerAttack(sp, dmg, eff > 1.4);
      if (battle && save.pet && e.hp > 0) await petAttack(Math.max(1, Math.round(dmg * 0.2)));
      if (battle && e.hp <= 0) return victory();
    } else {
      battle.streak = 0; renderBattleBars();
      setMsg(sp.name + " fizzled!");
      battle.fx.push({ type: "fizzle", t0: clock, dur: 0.6 });
      await wait(550);
    }
    await enemyTurn();
  }
  function battleLayout() {
    const menuH = $("#bMenu").offsetHeight || 170, top = 96, bottom = Math.max(top + 140, H - menuH - 6);
    const s = clamp(Math.min(W * 0.2, (bottom - top) * 0.5), 46, 160);
    return { px: W * 0.27, py: top + (bottom - top) * 0.7, ex: W * 0.72, ey: top + (bottom - top) * 0.48, s, top, bottom };
  }
  function burst(x, y, color, n) { for (let i = 0; i < n; i++) { const a = Math.random() * 7, sp = rnd(60, 260); battle.parts.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 60, life: rnd(0.4, 0.9), max: 0.9, color, size: rnd(2, 5) }); } }
  function floater(x, y, text, color) { battle.floaters.push({ x, y, text, color, life: 1.1 }); }
  async function playerAttack(sp, dmg, superEff) {
    const col = UNIT[sp.unit].color;
    battle.fx.push({ type: "proj", from: "player", t0: clock, dur: 0.45, color: col, unit: sp.unit, big: !!sp.mastery });
    Sound.play("select");
    await wait(450); if (!battle) return;
    const L = battleLayout();
    battle.enemy.hp = Math.max(0, battle.enemy.hp - dmg);
    battle.enemyHurt = 0.5; battle.shake = sp.mastery ? 11 : 6;
    burst(L.ex, L.ey, col, sp.mastery ? 40 : 24); floater(L.ex, L.ey - L.s * 0.6, "-" + dmg, "#fff");
    Sound.play("hit");
    setMsg((superEff ? "Super effective! " : "") + `${sp.name} hits for ${dmg}.`);
    renderBattleBars();
    await wait(420);
  }
  async function petAttack(dmg) {
    const p = PETS[save.pet];
    battle.fx.push({ type: "proj", from: "pet", t0: clock, dur: 0.35, color: p.color, unit: p.unit || "mod" });
    await wait(350); if (!battle) return;
    const L = battleLayout();
    battle.enemy.hp = Math.max(0, battle.enemy.hp - dmg);
    battle.enemyHurt = 0.3; burst(L.ex, L.ey, p.color, 10); floater(L.ex + 30, L.ey - L.s * 0.4, "-" + dmg, p.color);
    setMsg(`${p.name} joins in for ${dmg}!`); renderBattleBars();
    await wait(300);
  }
  async function enemyTurn() {
    if (!battle) return;
    battle.phase = "enemy"; renderBattleMenu();
    await wait(300); if (!battle) return;
    battle.lunge = 0.4;
    await wait(200); if (!battle) return;
    const e = battle.enemy, dmg = Math.max(1, Math.round(e.atk * rnd(0.85, 1.15)));
    save.hp = Math.max(0, save.hp - dmg);
    const L = battleLayout();
    battle.playerHurt = 0.5; battle.shake = 7; burst(L.px, L.py, "#ff5a5f", 16); floater(L.px, L.py - L.s * 0.75, "-" + dmg, "#ffd6d6");
    Sound.play("hurt"); setMsg(`${e.name} attacks for ${dmg}!`); renderBattleBars();
    await wait(480); if (!battle) return;
    if (save.hp <= 0) return defeat();
    battle.phase = "menu"; battle.sub = null; renderBattleMenu();
    setMsg("Your turn. Choose a spell!");
  }
  async function useItem(id) {
    if (!battle || battle.phase !== "menu" || !save.items[id]) return;
    battle.phase = "item"; battle.sub = null; renderBattleMenu();
    save.items[id]--;
    const before = save.hp; save.hp = Math.min(maxHp(), save.hp + (id === "mega" ? maxHp() : 50));
    const L = battleLayout(); floater(L.px, L.py - L.s * 0.75, "+" + Math.round(save.hp - before), "#b9ffcf"); burst(L.px, L.py, "#7bffb0", 14);
    Sound.play("heal"); setMsg(`You use the ${SHOP_ITEM[id].name}.`); renderBattleBars(); persist();
    await wait(500); await enemyTurn();
  }
  function flee() {
    if (!battle || battle.phase !== "menu" || battle.enemy.boss) return;
    const m = battle.enemy.ref; if (m) { m.dir = Math.atan2(m.y - player.y, m.x - player.x); m.turn = 2; }
    endBattle(false); toast("You got away safely.");
  }
  function gainXp(n) {
    save.xp += n; let lv = 0;
    while (save.xp >= xpNeed(save.level)) { save.xp -= xpNeed(save.level); save.level++; lv++; }
    if (lv) { save.hp = maxHp(); Sound.play("level"); }
    return lv;
  }
  async function victory() {
    const e = battle.enemy; battle.phase = "over"; battle.dying = 1;
    Sound.play("win");
    const xp = (10 + 6 * e.lv) * (e.final ? 6 : e.boss ? 4 : 1), coins = (4 + 2 * e.lv) * (e.final ? 8 : e.boss ? 5 : 1);
    save.coins += coins; save.stats.won++;
    const lines = [`+${xp} XP`, `+${coins} coins`];
    if (gainXp(xp)) lines.push(`Level up! You are now level ${save.level} (max HP ${maxHp()}).`);
    let ending = false;
    if (e.boss && !e.final && !save.bosses[e.unit]) {
      save.bosses[e.unit] = true; save.unlocked = Math.max(save.unlocked, e.zi + 1);
      const pet = BOSS_PET[e.unit]; if (!save.pets.includes(pet)) { save.pets.push(pet); if (!save.pet) save.pet = pet; }
      const msp = SPELLS.find((s) => s.unit === e.unit && s.mastery);
      lines.push(`New mastery spell: ${msp.name} (power ${msp.power}, harder questions).`, `New pet: ${PETS[pet].name}! Pets strike after every correct answer.`);
      lines.push(e.zi + 1 < ZONES.length ? `The gate to ${ZONES[e.zi + 1].name} is open.` : "All five regions are free. The Academy Tower awaits!");
    }
    if (e.final) { ending = !save.finalBeaten; save.finalBeaten = true; lines.push(ending ? "You defeated Dr. Entropy and restored the laws of physics!" : "Dr. Entropy is defeated again!"); }
    if (e.ref && monsters.includes(e.ref)) { monsters = monsters.filter((m) => m !== e.ref); respawnQueue.push({ zi: e.zi, t: 10 }); }
    persist();
    await wait(500);
    showBattleResult("Victory!", lines, ending);
  }
  async function defeat() {
    battle.phase = "over";
    await wait(300);
    showBattleResult("Knocked out!", ["Professor Vector carries you back to the Academy and patches you up.", "Your mistakes are saved in the Codex journal with worked solutions. Review them and try again!"], false, true);
  }
  function showBattleResult(title, lines, ending, home) {
    $("#bMenuInner").innerHTML = `<div class="card" id="bResult" style="max-width:520px;margin:0 auto"><h2>${esc(title)}</h2><ul style="margin:6px 0 10px;padding-left:20px;line-height:1.6">${lines.map((l) => `<li>${esc(l)}</li>`).join("")}</ul><button class="good" id="bContinue">Continue</button></div>`;
    $("#bContinue").onclick = () => { endBattle(!!home); if (ending) showEnding(); };
    setTimeout(() => { const b = $("#bContinue"); if (b) b.focus({ preventScroll: true }); }, 30);
  }
  function endBattle(home) {
    battle = null; state = "world"; encounterCooldown = 2.5; currentZone = -1;
    $("#battleUI").classList.add("hidden"); $("#hud").classList.remove("hidden"); lastPromptKey = "\u0000";
    if (home) { placeAtSpawn(); save.hp = maxHp(); }
    renderHud(); persist();
  }

  function renderBattle(dt) {
    const b = battle; if (!b) return;
    const e = b.enemy, z = ZONES[e.zi], L = battleLayout();
    b.shake = Math.max(0, b.shake - dt * 30); b.enemyHurt = Math.max(0, b.enemyHurt - dt); b.playerHurt = Math.max(0, b.playerHurt - dt); b.lunge = Math.max(0, b.lunge - dt);
    if (b.dying > 0 && b.phase === "over") b.dying = Math.max(0, b.dying - dt * 1.4);
    const sky = e.final ? ["#0b0420", "#3a0ca3"] : z.pal.sky;
    const gr = ctx.createLinearGradient(0, 0, 0, H); gr.addColorStop(0, sky[0]); gr.addColorStop(1, sky[1]);
    ctx.fillStyle = gr; ctx.fillRect(0, 0, W, H);
    if (z.id === "mod" || e.final) { for (let i = 0; i < 60; i++) { ctx.fillStyle = "rgba(255,255,255," + (0.3 + 0.5 * hash2(i, 1)) + ")"; ctx.fillRect(hash2(i, 2) * W, hash2(i, 3) * H * 0.7, 2, 2); } }
    ctx.fillStyle = e.final ? "#2d2366" : z.pal.g1; ctx.fillRect(0, L.bottom - (L.bottom - L.top) * 0.12, W, H);
    ctx.save();
    if (b.shake > 0) ctx.translate(rnd(-b.shake, b.shake), rnd(-b.shake, b.shake));
    ctx.fillStyle = "rgba(0,0,0,.18)";
    ctx.beginPath(); ctx.ellipse(L.px, L.py + L.s * 0.5, L.s * 0.75, L.s * 0.18, 0, 0, 7); ctx.fill();
    ctx.beginPath(); ctx.ellipse(L.ex, L.ey + L.s * 0.55, L.s * 0.85, L.s * 0.2, 0, 0, 7); ctx.fill();
    const lungeX = b.lunge > 0 ? -Math.sin((b.lunge / 0.4) * Math.PI) * W * 0.18 : 0;
    const es = L.s * (e.boss ? 1.25 : 1);
    if (b.phase !== "over" || b.dying > 0 || save.hp <= 0) {
      ctx.globalAlpha = b.phase === "over" && save.hp > 0 ? b.dying : 1;
      drawMonster(ctx, L.ex + lungeX, L.ey, es, e.look, clock, { boss: e.boss, final: e.final, hurt: b.enemyHurt > 0, flip: true });
      ctx.globalAlpha = 1;
    }
    ctx.globalAlpha = b.playerHurt > 0 ? 0.5 + 0.5 * Math.abs(Math.sin(clock * 40)) : 1;
    drawPlayer(ctx, L.px, L.py, L.s, save.look, clock, false, 1);
    ctx.globalAlpha = 1;
    if (save.pet) drawPet(ctx, save.pet, L.px - L.s * 0.75, L.py + L.s * 0.25, L.s * 0.38, clock);
    // spell effects
    for (let i = b.fx.length - 1; i >= 0; i--) {
      const f = b.fx[i], k = (clock - f.t0) / f.dur;
      if (k >= 1) { b.fx.splice(i, 1); continue; }
      if (f.type === "fizzle") { ctx.fillStyle = "rgba(200,200,220," + (1 - k) + ")"; for (let j = 0; j < 6; j++) { ctx.beginPath(); ctx.arc(L.px + L.s * 0.5 + j * 6, L.py - L.s * 0.2 - k * 40 - j * 4, 5 + j, 0, 7); ctx.fill(); } continue; }
      const sx = f.from === "pet" ? L.px - L.s * 0.75 : L.px + L.s * 0.48, sy = f.from === "pet" ? L.py + L.s * 0.25 : L.py - L.s * 0.15;
      const x = lerp(sx, L.ex, k), y = lerp(sy, L.ey, k) - Math.sin(k * Math.PI) * (f.unit === "enm" ? 60 : 20);
      ctx.save(); ctx.shadowColor = f.color; ctx.shadowBlur = 20; ctx.fillStyle = f.color; ctx.strokeStyle = f.color;
      const r = (f.big ? 16 : 10) * (f.from === "pet" ? 0.6 : 1);
      if (f.unit === "wav") { ctx.lineWidth = r * 0.8; ctx.globalAlpha = 0.85; ["#ff595e", "#ffca3a", "#8ac926", "#1982c4", "#6a4c93"].forEach((c, j) => { ctx.strokeStyle = c; ctx.beginPath(); ctx.moveTo(sx, sy + (j - 2) * 3); ctx.lineTo(x, y + (j - 2) * 3); ctx.stroke(); }); }
      else if (f.unit === "fld") { ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(sx, sy); for (let j = 1; j <= 8; j++) { const kk = (k * j) / 8; ctx.lineTo(lerp(sx, L.ex, kk) + rnd(-10, 10), lerp(sy, L.ey, kk) + rnd(-14, 14)); } ctx.stroke(); ctx.beginPath(); ctx.arc(x, y, r * 0.7, 0, 7); ctx.fill(); }
      else if (f.unit === "dyn") { const ang = Math.atan2(L.ey - sy, L.ex - sx); ctx.translate(x, y); ctx.rotate(ang); ctx.beginPath(); ctx.moveTo(r * 1.6, 0); ctx.lineTo(-r, -r * 0.8); ctx.lineTo(-r * 0.4, 0); ctx.lineTo(-r, r * 0.8); ctx.closePath(); ctx.fill(); ctx.fillRect(-r * 3, -2, r * 2.4, 4); }
      else if (f.unit === "mod") { for (let j = 0; j < 5; j++) { const a = clock * 12 + j * 1.25; ctx.beginPath(); ctx.arc(x + Math.cos(a) * r, y + Math.sin(a) * r, r * 0.35, 0, 7); ctx.fill(); } }
      else { ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.fillStyle = "rgba(255,255,255,.6)"; ctx.beginPath(); ctx.arc(x - r * 0.3, y - r * 0.3, r * 0.35, 0, 7); ctx.fill(); }
      ctx.restore();
    }
    for (let i = b.parts.length - 1; i >= 0; i--) {
      const p = b.parts[i]; p.life -= dt; if (p.life <= 0) { b.parts.splice(i, 1); continue; }
      p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 300 * dt;
      ctx.globalAlpha = clamp(p.life / p.max, 0, 1); ctx.fillStyle = p.color; ctx.fillRect(p.x, p.y, p.size, p.size);
    }
    ctx.globalAlpha = 1;
    for (let i = b.floaters.length - 1; i >= 0; i--) {
      const f = b.floaters[i]; f.life -= dt; if (f.life <= 0) { b.floaters.splice(i, 1); continue; }
      f.y -= 40 * dt; ctx.globalAlpha = clamp(f.life, 0, 1);
      ctx.font = "bold 28px 'Trebuchet MS', sans-serif"; ctx.textAlign = "center"; ctx.lineWidth = 5; ctx.strokeStyle = "rgba(29,24,64,.85)";
      ctx.strokeText(f.text, f.x, f.y); ctx.fillStyle = f.color; ctx.fillText(f.text, f.x, f.y);
    }
    ctx.globalAlpha = 1; ctx.restore();
  }

  // ================================================================ sheets: dialog, shop, bag
  let sheetOnClose = null;
  function openSheet(name, html, onClose) {
    modalOpen = name; sheetOnClose = onClose || null; moveTarget = null;
    $("#sheet").innerHTML = `<button class="ghost small close" id="sheetClose" aria-label="Close">✕</button>` + html;
    $("#modal").classList.remove("hidden"); $("#sheetClose").onclick = () => closeSheet();
    $("#sheet").scrollTop = 0; lastPromptKey = "\u0000"; updatePromptHidden();
  }
  function closeSheet() {
    $("#modal").classList.add("hidden"); modalOpen = null;
    const f = sheetOnClose; sheetOnClose = null; renderHud(); persist(); if (f) f();
  }
  function updatePromptHidden() { $("#prompt").classList.add("hidden"); }
  $("#modal").addEventListener("pointerdown", (ev) => { if (ev.target === $("#modal") && modalOpen !== "dialog") closeSheet(); });

  function dialog(speaker, lines, onDone, doneLabel) {
    let i = 0;
    const show = () => {
      const last = i === lines.length - 1;
      openSheet("dialog", `<h3>${esc(speaker)}</h3><p style="font-size:17px;line-height:1.5;margin:4px 0 14px">${esc(lines[i])}</p>` +
        `<div class="row"><span class="muted">${lines.length > 1 ? i + 1 + " / " + lines.length : ""}</span><span class="spacer"></span>${last && onDone ? '<button class="ghost" id="dlgCancel">Not yet</button>' : ""}<button class="good" id="dlgNext">${last ? esc(doneLabel || "OK") : "Next ›"}</button></div>`);
      $("#dlgNext").onclick = () => { if (!last) { i++; show(); } else { closeSheet(); if (onDone) onDone(); } };
      if ($("#dlgCancel")) $("#dlgCancel").onclick = () => closeSheet();
      setTimeout(() => { const b = $("#dlgNext"); if (b) b.focus({ preventScroll: true }); }, 20);
    };
    show();
  }
  const TIPS = [
    "Convert to SI units before you substitute: cm → m, g → kg, nm → m, μC → C, km → m.",
    "List your givens with units, write the unknown, then choose the formula that links them.",
    "'Centripetal force' is never a new force. It is whatever force points to the centre: tension, friction, gravity or a normal force.",
    "Momentum is conserved in every collision. Kinetic energy is conserved only in elastic ones.",
    "In gravitation and Coulomb problems, r is measured centre to centre, not from the surface.",
    "Field questions love inverse-square laws: double r, quarter the force.",
    "Thin films: count the phase inversions first. Each reflection off a higher-n medium flips the wave.",
    "In relativity, the proper time or proper length is measured in the frame where the object is at rest.",
    "Photoelectric effect: brighter light means more electrons. Higher-frequency light means faster electrons.",
    "Keep three significant figures in your answers unless the question says otherwise.",
    "Draw a free-body diagram for every dynamics problem. It is the fastest way to avoid sign mistakes.",
  ];
  function talkGuide() {
    const next = ZONES.find((z) => z.boss && !save.bosses[z.unit] && save.unlocked >= ZONES.indexOf(z));
    const lines = [];
    if (next) lines.push(`Your next challenge: ${next.boss.name} in ${next.name}. Monsters there test ${UNIT[next.unit].name}. I'd suggest level ${next.boss.lv - 1} or higher.`);
    else if (!save.finalBeaten) lines.push("All five guardians have fallen! Dr. Entropy waits atop the Academy Tower. Make sure your potions are stocked.");
    else lines.push("You've restored the laws of physics! Keep sharpening your mastery stars, or take unit tests in the Library before your real exams.");
    lines.push("Study tip: " + TIPS[Math.floor(Math.random() * TIPS.length)]);
    dialog("Professor Vector", lines);
  }
  function introDialog() {
    dialog("Professor Vector", [
      `Welcome to Newton's Academy, ${save.name}! I'm Professor Vector.`,
      "The villain Dr. Entropy has scrambled the laws of physics across the five regions of the realm.",
      "Monsters roam the land. In battle, pick a spell and solve the physics problem to cast it. Right answers hit hard. Wrong answers fizzle, but you'll see a worked solution so you learn from it.",
      "Each region covers one unit of Grade 12 physics. Defeat its guardian to open the next gate and earn a mastery spell and a pet.",
      "Visit the Library to practise and take unit tests, the Shop for gear, and the Fountain to heal. The Dynamo Dunes are through the east gate. Good luck!",
    ]);
  }

  function openShop() {
    const rows = SHOP.map((it) => {
      const have = it.kind === "item" ? `Have ${save.items[it.id] || 0}` : (it.kind === "pet" ? save.pets.includes(it.id) : save.owned.includes(it.id)) ? "Owned" : "";
      const can = save.coins >= it.price && have !== "Owned";
      return `<div class="tile"><h4>${esc(it.name)}</h4><div class="muted">${esc(it.desc)}</div><div class="row" style="margin-top:8px"><b>🪙 ${it.price}</b><span class="spacer"></span><span class="muted">${have}</span><button class="small buy" data-id="${it.id}" ${can ? "" : "disabled"}>Buy</button></div></div>`;
    }).join("");
    openSheet("shop", `<h2>Quinn's Quanta Shop</h2><p class="muted">You have 🪙 ${save.coins}. Hats raise max HP. Robes boost spell damage. Equip gear from your Bag.</p><div class="grid2">${rows}</div>`);
    $("#sheet").querySelectorAll(".buy").forEach((b) => b.onclick = () => buy(b.dataset.id));
  }
  function buy(id) {
    const it = SHOP_ITEM[id]; if (!it || save.coins < it.price) return;
    save.coins -= it.price;
    if (it.kind === "item") save.items[id] = (save.items[id] || 0) + 1;
    else if (it.kind === "pet") { if (!save.pets.includes(id)) save.pets.push(id); save.pet = id; }
    else { if (!save.owned.includes(id)) save.owned.push(id); save[it.kind] = id; }
    Sound.play("coin"); toast(`Bought ${it.name}!`); persist(); renderHud(); openShop();
  }
  function openBag() {
    const gear = (kind) => {
      const own = save.owned.filter((id) => SHOP_ITEM[id].kind === kind);
      if (!own.length) return `<p class="muted">None yet. Visit the Shop in the Academy.</p>`;
      return `<div class="grid2">${own.map((id) => `<div class="tile"><h4>${esc(SHOP_ITEM[id].name)}</h4><div class="muted">${esc(SHOP_ITEM[id].desc)}</div><div style="margin-top:6px">${save[kind] === id ? `<button class="small ghost equip" data-k="${kind}" data-id="">Unequip</button>` : `<button class="small equip" data-k="${kind}" data-id="${id}">Equip</button>`}</div></div>`).join("")}</div>`;
    };
    const pets = save.pets.length ? `<div class="grid2">${save.pets.map((id) => `<div class="tile"><h4>${esc(PETS[id].name)}</h4><div class="muted">${esc(PETS[id].desc)}</div><div style="margin-top:6px">${save.pet === id ? '<b>Following you</b>' : `<button class="small petpick" data-id="${id}">Choose</button>`}</div></div>`).join("")}</div>` : '<p class="muted">Defeat a region guardian to earn a pet.</p>';
    openSheet("bag", `<h2>Bag</h2>
      <p>Max HP <b>${maxHp()}</b> · Spell power <b>${Math.round(baseDmg())}</b> · Coins <b>🪙 ${save.coins}</b></p>
      <h3>Items</h3><div class="row">${["potion", "mega"].map((id) => `<button class="small useitem" data-id="${id}" ${save.items[id] && save.hp < maxHp() ? "" : "disabled"}>Use ${esc(SHOP_ITEM[id].name)} (×${save.items[id] || 0})</button>`).join("")}</div>
      <h3 style="margin-top:14px">Hats</h3>${gear("hat")}<h3 style="margin-top:14px">Robes</h3>${gear("robe")}<h3 style="margin-top:14px">Pets</h3>${pets}`);
    const s = $("#sheet");
    s.querySelectorAll(".equip").forEach((b) => b.onclick = () => { save[b.dataset.k] = b.dataset.id || null; save.hp = Math.min(save.hp, maxHp()); openBag(); });
    s.querySelectorAll(".petpick").forEach((b) => b.onclick = () => { save.pet = b.dataset.id; openBag(); });
    s.querySelectorAll(".useitem").forEach((b) => b.onclick = () => { const id = b.dataset.id; if (!save.items[id]) return; save.items[id]--; save.hp = Math.min(maxHp(), save.hp + (id === "mega" ? maxHp() : 50)); Sound.play("heal"); openBag(); });
  }

  // ================================================================ codex, practice, unit tests
  function openCodex(tab) {
    tab = tab || "mastery";
    const tabs = [["mastery", "Mastery & practice"], ["tests", "Unit tests"], ["formulas", "Formula sheet"], ["journal", `Mistake journal (${save.journal.length})`], ["stats", "Stats"]];
    let body = "";
    if (tab === "mastery") {
      const here = ZONES[zoneIndexAtTile(Math.floor(player.x / TILE), Math.floor(player.y / TILE))];
      const nextBoss = ZONES.find((z) => z.boss && !save.bosses[z.unit] && save.unlocked >= ZONES.indexOf(z));
      const focus = (here && here.unit) || (nextBoss && nextBoss.unit) || "dyn";
      body = `<p class="muted">Practise any skill here, even ones from regions you haven't reached. Stars show your accuracy over your last 8 tries (3 tries needed).</p>` + PQ.UNITS.map((u) => {
        const skills = PQ.SKILLS.filter((s) => s.unit === u.id), mastered = skills.filter((s) => starsOf(s.id) === 3).length;
        return `<details ${u.id === focus ? "open" : ""} style="margin-bottom:8px"><summary style="cursor:pointer;padding:6px 0"><span class="chip" style="background:${u.color}">${esc(u.short)}</span> <b>${esc(u.name)}</b> <span class="muted">· ${mastered}/${skills.length} mastered</span></summary>` +
          skills.map((s) => { const m = save.mastery[s.id], st = starsOf(s.id); return `<div class="skill-row"><div class="nm"><div>${esc(s.name)}</div><div class="meta">${s.concept ? "Concepts" : "Difficulty " + s.tier + " of 3"} · ${m ? `${m.c}/${m.n} correct` : "not tried yet"}</div></div><span class="stars" title="Mastery">${m && m.r.length >= 3 ? "★".repeat(st) + '<span class="off">' + "★".repeat(3 - st) + "</span>" : '<span class="off">☆☆☆</span>'}</span><button class="small practice" data-id="${s.id}">Practise</button></div>`; }).join("") + "</details>";
      }).join("");
    } else if (tab === "tests") {
      body = `<p class="muted">Ten mixed questions from one unit, like a quiz. Earn 3 coins per correct answer.</p><div class="grid2">` + PQ.UNITS.map((u) => {
        const best = save.tests[u.id];
        return `<div class="tile"><span class="chip" style="background:${u.color}">${esc(u.short)}</span><h4 style="margin-top:6px">${esc(u.name)}</h4><div class="muted">${best !== undefined ? `Best score: ${best}/10` : "Not taken yet"}</div><button class="small runtest" data-u="${u.id}" style="margin-top:8px">Start test</button></div>`;
      }).join("") + "</div>";
    } else if (tab === "formulas") {
      body = PQ.UNITS.map((u) => `<h3><span class="chip" style="background:${u.color}">${esc(u.short)}</span> ${esc(u.name)}</h3><ul class="formulas">${PQ.FORMULAS[u.id].map((f) => `<li>${esc(f)}</li>`).join("")}</ul>`).join("") + `<h3>Constants</h3>${constTable()}`;
    } else if (tab === "journal") {
      body = save.journal.length ? `<div class="row"><span class="muted">Your most recent mistakes, with worked solutions.</span><span class="spacer"></span><button class="small ghost" id="clearJournal">Clear journal</button></div>` + save.journal.map((j) => {
        const s = PQ.SKILL[j.skill];
        return `<div class="journal-item"><div class="row"><span class="chip" style="background:${UNIT[s.unit].color}">${esc(s.name)}</span><span class="spacer"></span><button class="small practice" data-id="${s.id}">Try a similar one</button></div><p style="margin:6px 0">${esc(j.prompt)}</p><div>Answer: <b>${esc(j.answer)}</b></div><details><summary>Solution</summary><ol>${j.steps.map((x) => `<li>${esc(x)}</li>`).join("")}</ol></details></div>`;
      }).join("") : '<p class="muted">No mistakes recorded yet. When you miss a question, it lands here with its worked solution.</p>';
    } else {
      const st = save.stats, acc = st.answered ? Math.round((100 * st.correct) / st.answered) : 0;
      const mins = Math.round(st.playSec / 60);
      body = `<table class="consts"><tr><td>Questions answered</td><td><b>${st.answered}</b></td></tr><tr><td>Correct</td><td><b>${st.correct}</b> (${acc}%)</td></tr><tr><td>Battles won</td><td><b>${st.won}</b></td></tr><tr><td>Best streak</td><td><b>${st.bestStreak}</b></td></tr><tr><td>Guardians defeated</td><td><b>${Object.keys(save.bosses).length}/5</b>${save.finalBeaten ? " + Dr. Entropy" : ""}</td></tr><tr><td>Level</td><td><b>${save.level}</b></td></tr><tr><td>Time played</td><td><b>${mins} min</b></td></tr></table>` +
        "<h3 style='margin-top:14px'>Accuracy by unit</h3>" + PQ.UNITS.map((u) => { let n = 0, c = 0; for (const s of PQ.SKILLS) if (s.unit === u.id && save.mastery[s.id]) { n += save.mastery[s.id].n; c += save.mastery[s.id].c; } return `<div class="row" style="margin:4px 0"><span style="width:150px">${esc(u.short)}</span><div class="bar" style="flex:1"><i style="width:${n ? (100 * c) / n : 0}%;background:${u.color}"></i><span>${n ? Math.round((100 * c) / n) + "%" : "—"}</span></div><span class="muted" style="width:60px;text-align:right">${c}/${n}</span></div>`; }).join("");
    }
    openSheet("codex", `<h2>📖 Codex</h2><div class="tabs">${tabs.map(([id, l]) => `<button class="tab ${id === tab ? "on" : ""}" data-t="${id}">${esc(l)}</button>`).join("")}</div>${body}`);
    const s = $("#sheet");
    s.querySelectorAll(".tab").forEach((b) => b.onclick = () => openCodex(b.dataset.t));
    s.querySelectorAll(".practice").forEach((b) => b.onclick = () => practice(b.dataset.id, tab));
    s.querySelectorAll(".runtest").forEach((b) => b.onclick = () => unitTest(b.dataset.u));
    if ($("#clearJournal")) $("#clearJournal").onclick = () => { save.journal = []; openCodex("journal"); };
  }
  async function practice(skillId, backTab) {
    closeSheet(); modalOpen = "practice";
    for (;;) {
      const q = newQuestion(skillId);
      const res = await openQuestion(q, { header: "Practice", buttons: [{ id: "next", label: "Another one" }, { id: "done", label: "Back to Codex" }] });
      record(q, res.correct);
      if (res.correct) { save.coins += 1; }
      if (res.action !== "next") break;
    }
    modalOpen = null; openCodex(backTab || "mastery");
  }
  async function unitTest(unit) {
    closeSheet(); modalOpen = "test";
    const results = []; let quit = false;
    for (let i = 0; i < 10 && !quit; i++) {
      const q = newQuestion(pickSkill(unit, 3));
      const res = await openQuestion(q, { header: `Unit test · ${i + 1} of 10`, buttons: [{ id: "next", label: i < 9 ? "Next question" : "See results" }, { id: "quit", label: "Quit test" }] });
      record(q, res.correct); results.push({ skill: q.skill, ok: res.correct });
      if (res.action === "quit") quit = true;
    }
    modalOpen = null;
    const score = results.filter((r) => r.ok).length;
    if (!quit) { save.coins += 3 * score; save.tests[unit] = Math.max(save.tests[unit] || 0, score); }
    const weak = results.filter((r) => !r.ok).map((r) => r.skill);
    openSheet("testresult", `<h2>${quit ? "Test stopped" : `Score: ${score}/10`}</h2><p class="muted">${quit ? "Quitting doesn't record a score." : `+${3 * score} coins. ${score >= 9 ? "Outstanding!" : score >= 7 ? "Solid work!" : "Keep practising. The journal has every solution."}`}</p>` +
      `<ul style="line-height:1.7">${results.map((r) => `<li>${r.ok ? "✅" : "❌"} ${esc(PQ.SKILL[r.skill].name)}</li>`).join("")}</ul>` +
      `<div class="row">${weak.length ? `<button class="practice" data-id="${weak[0]}">Practise: ${esc(PQ.SKILL[weak[0]].name)}</button>` : ""}<button class="ghost" id="backTests">Back to unit tests</button></div>`);
    $("#backTests").onclick = () => openCodex("tests");
    $("#sheet").querySelectorAll(".practice").forEach((b) => b.onclick = () => practice(b.dataset.id, "tests"));
  }

  // ================================================================ settings, ending
  function openSettings() {
    const s = save.settings;
    const radio = (v, label, desc) => `<label class="tile" style="display:block;cursor:pointer;margin-bottom:6px"><input type="radio" name="amode" value="${v}" ${s.mode === v ? "checked" : ""}> <b>${label}</b><div class="muted" style="margin-left:24px">${desc}</div></label>`;
    openSheet("settings", `<h2>⚙️ Settings</h2>
      <h3>Answer style</h3>
      ${radio("mc", "Multiple choice", "Pick from four answers. The wrong ones come from common mistakes.")}
      ${radio("mixed", "Mixed", "Easy questions are multiple choice. Harder numeric ones make you type the answer.")}
      ${radio("type", "Type every number", "Exam practice: type each numeric answer (within 2%).")}
      <h3 style="margin-top:12px">Options</h3>
      <label style="display:flex;gap:8px;align-items:flex-start;margin-bottom:8px"><input type="checkbox" id="setSound" ${s.sound ? "checked" : ""}><span>Sound effects</span></label>
      <label style="display:flex;gap:8px;align-items:flex-start"><input type="checkbox" id="setAll" ${s.allTopics ? "checked" : ""}><span>Study mode: battle with spells from every unit. Useful when your class is ahead of your game progress.</span></label>
      <h3 style="margin-top:14px">Your save</h3>
      <p class="muted">Progress is saved in this browser. Copy a save code to move to another device.</p>
      <div class="row"><button class="small ghost" id="exportBtn">Show save code</button><button class="small ghost" id="importBtn">Load a save code</button><button class="small bad" id="resetBtn">Delete save</button></div>
      <div id="saveBox"></div>
      <h3 style="margin-top:14px">Controls</h3>
      <p class="muted">Move with WASD or the arrow keys, or tap/click where you want to go. Press E or Space to interact. In battle, press 1–9 to cast and 1–4 to answer. C opens the Codex, B the Bag, H teleports home.</p>`);
    const sh = $("#sheet");
    sh.querySelectorAll('input[name="amode"]').forEach((r) => r.onchange = () => { s.mode = r.value; persist(); });
    $("#setSound").onchange = (ev) => { s.sound = ev.target.checked; persist(); if (s.sound) Sound.play("select"); };
    $("#setAll").onchange = (ev) => { s.allTopics = ev.target.checked; persist(); };
    $("#exportBtn").onclick = () => { $("#saveBox").innerHTML = `<textarea readonly style="width:100%;height:90px;margin-top:8px">${esc(btoa(unescape(encodeURIComponent(JSON.stringify(save)))))}</textarea>`; $("#saveBox textarea").select(); };
    $("#importBtn").onclick = () => {
      $("#saveBox").innerHTML = `<textarea id="importText" style="width:100%;height:90px;margin-top:8px" placeholder="Paste a save code"></textarea><button class="small" id="importGo">Load</button>`;
      $("#importGo").onclick = () => {
        try {
          const obj = JSON.parse(decodeURIComponent(escape(atob($("#importText").value.trim()))));
          if (!obj || obj.v !== 1 || typeof obj.name !== "string") throw new Error("bad");
          lsSet(SAVE_KEY, JSON.stringify(obj)); const s2 = loadSave(); if (!s2) throw new Error("bad");
          closeSheet(); startGame(s2, false); toast("Save loaded. Welcome back, " + s2.name + "!");
        } catch (e) { toast("That save code didn't work. Check that you copied all of it."); }
      };
    };
    let armed = false;
    $("#resetBtn").onclick = () => {
      if (!armed) { armed = true; $("#resetBtn").textContent = "Really delete? Click again"; return; }
      lsDel(SAVE_KEY); closeSheet(); save = null; showTitle();
    };
  }
  function showEnding() {
    const st = save.stats, acc = st.answered ? Math.round((100 * st.correct) / st.answered) : 0;
    openSheet("ending", `<h2>🎓 The laws of physics are restored!</h2><p style="font-size:17px;line-height:1.5">Dr. Entropy dissolves into a cloud of perfectly ordered particles. Professor Vector beams: "${esc(save.name)}, you've mastered Grade 12 physics!"</p>
      <p>You answered <b>${st.correct}</b> of <b>${st.answered}</b> questions correctly (${acc}%) and won <b>${st.won}</b> battles.</p>
      <p class="muted">Keep playing to earn three stars on every skill, take unit tests in the Library, or rematch Dr. Entropy at the Academy for a full-course review.</p>`);
  }

  // ================================================================ title + start
  function showTitle() {
    state = "title"; $("#title").classList.remove("hidden"); $("#hud").classList.add("hidden"); $("#battleUI").classList.add("hidden"); $("#prompt").classList.add("hidden");
    const existing = loadSave();
    if (!existing) return showCreator(null);
    $("#titlePanel").innerHTML = `<p style="margin-top:0">Welcome back, <b>${esc(existing.name)}</b>! Level ${existing.level} · ${Object.keys(existing.bosses).length}/5 guardians defeated.</p>
      <div class="row"><button class="good" id="btnContinue">▶ Continue</button><button class="ghost" id="btnNew">New game</button></div>`;
    $("#btnContinue").onclick = () => startGame(existing, false);
    $("#btnNew").onclick = () => showCreator(existing);
  }
  function showCreator(existing) {
    const look = { robe: ROBE_COLORS[0], hat: HAT_COLORS[0], skin: SKIN[0] };
    const sw = (key, list) => `<div class="swatches">${list.map((c) => `<button class="swatch ${look[key] === c ? "on" : ""}" data-k="${key}" data-c="${c}" style="background:${c}" aria-label="${key} colour ${c}"></button>`).join("")}</div>`;
    const draw = () => {
      const c = $("#lookPreview"); if (!c) return; const g = c.getContext("2d"), d = Math.min(2, window.devicePixelRatio || 1);
      c.width = 120 * d; c.height = 130 * d; c.style.width = "120px"; c.style.height = "130px";
      g.setTransform(d, 0, 0, d, 0, 0); g.clearRect(0, 0, 120, 130); drawPlayer(g, 60, 82, 90, look, 0.4, false, 1, { ignoreGear: true });
    };
    const render = () => {
      const name = $("#nameInput") ? $("#nameInput").value : "";
      $("#titlePanel").innerHTML = `<div class="row" style="align-items:flex-start;gap:14px"><canvas id="lookPreview" width="120" height="130"></canvas><div style="flex:1;min-width:200px">
        <label><b>Wizard name</b><br><input id="nameInput" maxlength="16" placeholder="Your name" style="width:100%;margin:4px 0 8px" value="${esc(name)}"></label>
        <b>Robe</b>${sw("robe", ROBE_COLORS)}<b>Hat</b>${sw("hat", HAT_COLORS)}<b>Skin</b>${sw("skin", SKIN)}</div></div>
        ${existing ? '<p class="muted" style="margin:6px 0">Starting over replaces your current save.</p>' : ""}
        <div class="row" style="margin-top:6px"><button class="good" id="btnStart">Begin adventure</button>${existing ? '<button class="ghost" id="btnBackTitle">Back</button>' : ""}</div>`;
      $("#titlePanel").querySelectorAll(".swatch").forEach((b) => b.onclick = () => { look[b.dataset.k] = b.dataset.c; render(); });
      $("#btnStart").onclick = () => { const nm = ($("#nameInput").value || "").trim().slice(0, 16) || "Wizard"; startGame(newSave(nm, Object.assign({}, look)), true); };
      if ($("#btnBackTitle")) $("#btnBackTitle").onclick = showTitle;
      draw();
    };
    render();
  }
  function startGame(s, isNew) {
    save = s; persist();
    $("#title").classList.add("hidden"); $("#hud").classList.remove("hidden");
    state = "world"; battle = null; modalOpen = null; currentZone = -1; encounterCooldown = 2;
    placeAtSpawn();
    if (save.pos && !blockedAt(save.pos.x, save.pos.y, 12)) { player.x = save.pos.x; player.y = save.pos.y; player.petX = player.x - 30; player.petY = player.y; }
    populateMonsters(); renderHud(); lastPromptKey = "\u0000";
    if (isNew) introDialog();
  }
  function goHome() {
    if (state !== "world" || modalOpen) return;
    placeAtSpawn(); moveTarget = null; encounterCooldown = 2; toast("Teleported to Newton's Academy.");
  }

  // ================================================================ input
  window.addEventListener("keydown", (ev) => {
    const tag = ev.target && ev.target.tagName, typing = tag === "INPUT" || tag === "TEXTAREA";
    if (!$("#qModal").classList.contains("hidden")) {
      if (qPhase === "ask" && qHandlers && qHandlers.choose && !typing && ev.key.length === 1) {
        let i = "1234".indexOf(ev.key); if (i < 0) i = "abcd".indexOf(ev.key.toLowerCase());
        if (i >= 0) { ev.preventDefault(); qHandlers.choose(i); }
      } else if (qPhase === "feedback" && ev.key === "Enter" && qHandlers && qHandlers.cont && !(document.activeElement && document.activeElement.tagName === "BUTTON")) { ev.preventDefault(); qHandlers.cont(); }
      return;
    }
    if (typing) return;
    if (modalOpen) { if (ev.key === "Escape" && modalOpen !== "practice" && modalOpen !== "test") closeSheet(); return; }
    if (state === "world") {
      keys[ev.code] = true;
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space"].includes(ev.code)) ev.preventDefault();
      if (!ev.repeat && (ev.code === "KeyE" || ev.code === "Space" || ev.code === "Enter")) interact();
      if (ev.code === "KeyC") openCodex("mastery");
      if (ev.code === "KeyB") openBag();
      if (ev.code === "KeyH") goHome();
    } else if (state === "battle" && battle && battle.phase === "menu" && !battle.sub) {
      const n = parseInt(ev.key, 10), spells = SPELLS.filter(spellUnlocked);
      if (n >= 1 && n <= spells.length) castSpell(spells[n - 1]);
    }
  });
  window.addEventListener("keyup", (ev) => { keys[ev.code] = false; });
  window.addEventListener("blur", () => { for (const k in keys) keys[k] = false; });
  let pointerDown = false;
  const setTargetFrom = (ev) => { const cam = camera(); moveTarget = { x: ev.clientX + cam.x, y: ev.clientY + cam.y }; };
  cv.addEventListener("pointerdown", (ev) => { Sound.ensure(); if (state !== "world" || modalOpen) return; pointerDown = true; setTargetFrom(ev); });
  cv.addEventListener("pointermove", (ev) => { if (pointerDown && state === "world" && !modalOpen) setTargetFrom(ev); });
  window.addEventListener("pointerup", () => { pointerDown = false; });
  document.addEventListener("pointerdown", () => Sound.ensure(), { once: true });
  $("#btnCodex").onclick = () => { if (state === "world" && !modalOpen) openCodex("mastery"); };
  $("#btnBag").onclick = () => { if (state === "world" && !modalOpen) openBag(); };
  $("#btnHome").onclick = goHome;
  $("#btnSettings").onclick = () => { if (state === "world" && !modalOpen) openSettings(); };
  setInterval(() => { if (save && state === "world") persist(); }, 5000);
  window.addEventListener("pagehide", persist);

  // ================================================================ test hooks (read-only probe + debug helpers)
  window.__pq = () => ({
    state, modal: modalOpen, qOpen: !$("#qModal").classList.contains("hidden"),
    hp: save && save.hp, maxHp: save && maxHp(), level: save && save.level, xp: save && save.xp, coins: save && save.coins,
    unlocked: save && save.unlocked, bosses: save ? Object.keys(save.bosses) : [], pets: save ? save.pets.slice() : [], pet: save && save.pet,
    pos: { x: Math.round(player.x), y: Math.round(player.y) }, zone: currentZone, monsters: monsters.length,
    battle: battle && { phase: battle.phase, enemy: battle.enemy.name, enemyHp: battle.enemy.hp, enemyMax: battle.enemy.max, boss: !!battle.enemy.boss, streak: battle.streak },
    question: curQ && { skill: curQ.skill, kind: curQ.kind, correct: curQ.correct, answerText: curQ.answerText, value: curQ.value, typed: useTyped(curQ), phase: qPhase },
    answered: save ? save.stats.answered : 0, correctCount: save ? save.stats.correct : 0, journal: save ? save.journal.length : 0,
    settings: save ? Object.assign({}, save.settings) : null,
  });
  window.__pqDebug = {
    battle(zi, boss) {
      if (state !== "world" || modalOpen) return false;
      if (boss) startBattle(makeEnemy({ boss: true, zi }));
      else { const z = ZONES[zi], sp = SPECIES[z.unit][0]; startBattle(makeEnemy({ monster: { zi, lv: z.lv[0], look: sp, name: sp.name } })); }
      return true;
    },
    final() { if (state === "world" && !modalOpen) startBattle(makeEnemy({ final: true })); },
    set(o) { Object.assign(save, o); renderHud(); persist(); },
    teleport(tx, ty) { player.x = tx * TILE + TILE / 2; player.y = ty * TILE + TILE / 2; },
    tile: (tx, ty) => tget(tx, ty),
    reachable(tx, ty) { return passableTile(tx, ty); },
    // With every gate open: is every boss, building door and zone reachable from the spawn point?
    mapCheck() {
      const seen = new Uint8Array(MW * MH), stack = [[SPAWN.tx, SPAWN.ty]], problems = [];
      const open = (x, y) => { const t = tget(x, y); return t === T_GROUND || t === T_PATH || t >= T_GATE; };
      while (stack.length) {
        const [x, y] = stack.pop(); if (seen[y * MW + x]) continue; seen[y * MW + x] = 1;
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) if (open(x + dx, y + dy) && !seen[(y + dy) * MW + x + dx]) stack.push([x + dx, y + dy]);
      }
      ZONES.forEach((z, zi) => {
        if (z.boss && !seen[(z.gy * ZH + z.boss.ty) * MW + z.gx * ZW + z.boss.tx]) problems.push("boss unreachable in " + z.id);
        let n = 0; for (let y = 0; y < ZH; y++) for (let x = 0; x < ZW; x++) if (seen[(z.gy * ZH + y) * MW + z.gx * ZW + x]) n++;
        if (n < 120) problems.push(`only ${n} reachable tiles in ${z.id}`);
      });
      NPCS.forEach((n) => { if (!seen[(n.ty + 1) * MW + n.tx]) problems.push("npc unreachable: " + n.id); });
      return problems;
    },
  };

  // ================================================================ boot
  resize(); buildMap(); prerenderMap(); showTitle();
  requestAnimationFrame((ts) => { lastT = ts; requestAnimationFrame(frame); });
})();
