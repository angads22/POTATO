/*
 * SLICE IT! — web audio: the synthesizer, the SFX recipes and the song
 * renderer, ported from the Godot edition (Synth.gd, SfxLibrary.gd,
 * SongComposer.render). Everything is generated in the browser — the page
 * ships no audio files. Songs come out as four stereo stems (drums,
 * harmony, lead, fever) that WebAudio loops sample-accurately.
 */
(function (root) {
  "use strict";
  const TAU = Math.PI * 2;
  const midiHz = (m) => 440 * Math.pow(2, (m - 69) / 12);

  class Synth {
    constructor(rate) { this.rate = rate; }
    n(sec) { return Math.max(1, Math.floor(sec * this.rate)); }

    // One note: see the parameter list in godot/scripts/audio/Synth.gd tone()
    tone(freq, dur, p) {
      const rate = this.rate;
      const a = p.a ?? 0.004, d = p.d ?? 0.08, s = p.s ?? 0.6, r = p.r ?? 0.08, vol = p.vol ?? 0.5;
      const wave = p.wave || "square";
      let gate = this.n(dur);
      if (s <= 0) gate = Math.max(gate, this.n(a + d));
      const total = gate + this.n(r);
      const out = new Float32Array(total);
      // per-sample phase increment
      const dts = new Float32Array(total).fill(freq / rate);
      const pdrop = p.pdrop || 0, slide = p.slide || 0, vib = p.vib || 0;
      if (pdrop || slide || vib) {
        const pdecay = Math.max(0.0005, p.pdecay ?? 0.03);
        const vibW = TAU * (p.vib_rate ?? 5.5), vibDelay = p.vib_delay ?? 0.12;
        const k = Math.log(2) / 12, base = freq / rate, invDur = 1 / Math.max(dur, 0.0001);
        let drop = pdrop;
        const dropMul = Math.exp(-1 / rate / pdecay);
        for (let i = 0; i < total; i++) {
          const t = i / rate;
          let semis = drop + slide * Math.min(1, t * invDur);
          drop *= dropMul;
          if (t > vibDelay) semis += vib * Math.sin(vibW * (t - vibDelay));
          dts[i] = base * Math.exp(semis * k);
        }
      }
      this.osc(out, wave, dts, 1, p);
      if (p.detune && wave !== "noise") {
        const b = new Float32Array(total);
        this.osc(b, wave === "fm" ? "sine" : wave, dts, Math.pow(2, p.detune / 1200), p);
        for (let i = 0; i < total; i++) out[i] = (out[i] + b[i]) * 0.5;
      }
      if (p.sub) {
        let ph = 0;
        for (let i = 0; i < total; i++) { out[i] += p.sub * Math.sin(TAU * ph); ph += dts[i] * 0.5; if (ph >= 1) ph -= 1; }
      }
      if (p.noise) for (let i = 0; i < total; i++) out[i] += p.noise * (Math.random() * 2 - 1);
      if (p.lp) {
        this.lowpass(out, p.lp, p.lp_env || 0, p.lp_decay ?? 0.15);
        if ((p.poles || 1) >= 2) this.lowpass(out, p.lp, p.lp_env || 0, p.lp_decay ?? 0.15);
      }
      if (p.hp) this.highpass(out, p.hp);
      if (p.trem) {
        const tr = TAU * (p.trem_rate ?? 6) / rate;
        for (let i = 0; i < total; i++) out[i] *= 1 - p.trem * (0.5 + 0.5 * Math.sin(tr * i));
      }
      // ADSR in segments, release from wherever the gate closed
      const na = Math.min(this.n(a), gate), nd = Math.max(1, this.n(d));
      let level = 0;
      for (let i = 0; i < na; i++) { level = i / na; out[i] *= level * vol; }
      const decEnd = Math.min(na + nd, gate);
      for (let i = na; i < decEnd; i++) { level = 1 - (1 - s) * ((i - na) / nd); out[i] *= level * vol; }
      if (decEnd < gate) { level = s; for (let i = decEnd; i < gate; i++) out[i] *= s * vol; }
      const nr = total - gate;
      for (let i = gate; i < total; i++) out[i] *= level * (1 - (i - gate) / nr) * vol;
      return out;
    }

    osc(out, wave, dts, mul, p) {
      const n = out.length;
      let ph = 0;
      switch (wave) {
        case "sine":
          for (let i = 0; i < n; i++) { out[i] = Math.sin(TAU * ph); ph += dts[i] * mul; if (ph >= 1) ph -= 1; }
          break;
        case "tri":
          for (let i = 0; i < n; i++) { out[i] = 4 * Math.abs(ph - 0.5) - 1; ph += dts[i] * mul; if (ph >= 1) ph -= 1; }
          break;
        case "square": {
          const duty = p.duty ?? 0.5;
          for (let i = 0; i < n; i++) {
            const dt = dts[i] * mul;
            let v = ph < duty ? 1 : -1;
            if (ph < dt) { const t = ph / dt; v += t + t - t * t - 1; }
            else if (ph > 1 - dt) { const t = (ph - 1) / dt; v += t * t + t + t + 1; }
            let p2 = ph + 1 - duty; if (p2 >= 1) p2 -= 1;
            if (p2 < dt) { const t = p2 / dt; v -= t + t - t * t - 1; }
            else if (p2 > 1 - dt) { const t = (p2 - 1) / dt; v -= t * t + t + t + 1; }
            out[i] = v; ph += dt; if (ph >= 1) ph -= 1;
          }
          break;
        }
        case "saw":
          for (let i = 0; i < n; i++) {
            const dt = dts[i] * mul;
            let v = 2 * ph - 1;
            if (ph < dt) { const t = ph / dt; v -= t + t - t * t - 1; }
            else if (ph > 1 - dt) { const t = (ph - 1) / dt; v -= t * t + t + t + 1; }
            out[i] = v; ph += dt; if (ph >= 1) ph -= 1;
          }
          break;
        case "noise":
          for (let i = 0; i < n; i++) out[i] = Math.random() * 2 - 1;
          break;
        case "fm": {
          const ratio = p.fm_ratio ?? 1, idx = p.fm_index ?? 1.5;
          const idxMul = Math.exp(-1 / (Math.max(0.001, p.fm_decay ?? 0.4) * this.rate));
          let dyn = idx * 0.7, pm = 0;
          for (let i = 0; i < n; i++) {
            const dt = dts[i] * mul;
            out[i] = Math.sin(TAU * ph + (idx * 0.3 + dyn) * Math.sin(TAU * pm));
            dyn *= idxMul;
            ph += dt; if (ph >= 1) ph -= 1;
            pm += dt * ratio; if (pm >= 1) pm -= Math.floor(pm);
          }
          break;
        }
      }
    }

    lowpass(buf, cutoff, env, decay) {
      let y = 0, e = env;
      const w = TAU / this.rate, eMul = Math.exp(-1 / (Math.max(0.001, decay) * this.rate));
      for (let i = 0; i < buf.length; i++) {
        const a = Math.min(1, (cutoff + e) * w);
        e *= eMul; y += a * (buf[i] - y); buf[i] = y;
      }
    }

    highpass(buf, cutoff) {
      const a = Math.exp(-TAU * Math.min(cutoff, this.rate * 0.45) / this.rate);
      let y = 0, px = 0;
      for (let i = 0; i < buf.length; i++) { const x = buf[i]; y = a * (y + x - px); px = x; buf[i] = y; }
    }

    // ── drum kit ──
    kick(vol = 0.9, f0 = 160, f1 = 48, decay = 0.28) {
      const n = this.n(decay * 1.6), out = new Float32Array(n);
      let ph = 0;
      for (let i = 0; i < n; i++) {
        const t = i / this.rate;
        ph += (f1 + (f0 - f1) * Math.exp(-t / 0.035)) / this.rate;
        let v = Math.sin(TAU * ph) * Math.exp(-t / decay);
        if (i < 120) v += (Math.random() * 0.8 - 0.4) * (1 - i / 120);
        out[i] = v * vol;
      }
      return out;
    }
    snare(vol = 0.6, toneHz = 190, decay = 0.16) {
      const n = this.n(decay * 1.8), out = new Float32Array(n);
      const hpA = Math.exp(-TAU * 1200 / this.rate);
      let ph = 0, hy = 0, hx = 0;
      for (let i = 0; i < n; i++) {
        const t = i / this.rate;
        ph += toneHz * (1 + 0.5 * Math.exp(-t / 0.01)) / this.rate;
        const body = Math.sin(TAU * ph) * Math.exp(-t / 0.05) * 0.55;
        const x = Math.random() * 2 - 1;
        hy = hpA * (hy + x - hx); hx = x;
        out[i] = (body + hy * Math.exp(-t / decay) * 0.8) * vol;
      }
      return out;
    }
    hat(vol = 0.25, decay = 0.035, cutoff = 7000) {
      const n = this.n(decay * 4), out = new Float32Array(n);
      const hpA = Math.exp(-TAU * Math.min(cutoff, this.rate * 0.45) / this.rate);
      let hy = 0, hx = 0;
      for (let i = 0; i < n; i++) {
        const x = Math.random() * 2 - 1;
        hy = hpA * (hy + x - hx); hx = x;
        out[i] = hy * Math.exp(-(i / this.rate) / decay) * vol;
      }
      return out;
    }
    clap(vol = 0.5) {
      const n = this.n(0.3), out = new Float32Array(n);
      const hpA = Math.exp(-TAU * 900 / this.rate), la = Math.min(1, TAU * 2600 / this.rate);
      let ly = 0, hy = 0, hx = 0;
      for (let i = 0; i < n; i++) {
        const t = i / this.rate;
        let env = 0;
        for (let k = 0; k < 3; k++) { const tk = t - k * 0.011; if (tk >= 0 && tk < 0.011) env = Math.max(env, Math.exp(-tk / 0.004)); }
        if (t >= 0.022) env = Math.max(env, Math.exp(-(t - 0.022) / 0.09));
        const x = Math.random() * 2 - 1;
        ly += la * (x - ly);
        hy = hpA * (hy + ly - hx); hx = ly;
        out[i] = hy * env * vol * 2.2;
      }
      return out;
    }
    shaker(vol = 0.18) {
      const n = this.n(0.09), out = new Float32Array(n);
      const hpA = Math.exp(-TAU * 5000 / this.rate);
      let hy = 0, hx = 0;
      for (let i = 0; i < n; i++) {
        const t = i / this.rate;
        const x = Math.random() * 2 - 1;
        hy = hpA * (hy + x - hx); hx = x;
        out[i] = hy * Math.min(1, t / 0.012) * Math.exp(-t / 0.03) * vol;
      }
      return out;
    }
    rim(vol = 0.3) {
      const a = this.tone(1750, 0.01, { wave: "sine", a: 0.0005, d: 0.03, s: 0, r: 0.02, vol });
      const b = this.tone(820, 0.01, { wave: "tri", a: 0.0005, d: 0.04, s: 0, r: 0.02, vol: vol * 0.6 });
      return layer(a, b, 0);
    }
    tom(vol = 0.6, f = 120) {
      return this.tone(f, 0.05, { wave: "sine", a: 0.001, d: 0.22, s: 0, r: 0.1, pdrop: 7, pdecay: 0.06, vol });
    }
  }

  // ── buffer helpers ──
  function mix(dst, src, start, gain, wrap) {
    const n = dst.length, m = src.length;
    if (!n || !m) return;
    if (wrap) {
      start = ((start % n) + n) % n;
      const first = Math.min(m, n - start);
      for (let i = 0; i < first; i++) dst[start + i] += src[i] * gain;
      let j = 0;
      for (let i = first; i < m; i++) { dst[j] += src[i] * gain; if (++j >= n) j = 0; }
    } else {
      const end = Math.min(m, n - start);
      for (let i = Math.max(0, -start); i < end; i++) dst[start + i] += src[i] * gain;
    }
  }
  function mixPan(L, R, src, start, gain, pan) {
    const ang = (Math.min(1, Math.max(-1, pan)) + 1) * Math.PI * 0.25;
    mix(L, src, start, gain * Math.cos(ang) * Math.SQRT2, true);
    mix(R, src, start, gain * Math.sin(ang) * Math.SQRT2, true);
  }
  // a laid over b's start + at samples, growing the buffer as needed
  function layer(a, b, at) {
    const out = new Float32Array(Math.max(a.length, at + b.length));
    out.set(a);
    for (let i = 0; i < b.length; i++) out[at + i] += b[i];
    return out;
  }
  function echo(buf, delay, feedback, wet, wrap) {
    const n = buf.length;
    if (!n || delay <= 0) return;
    const line = new Float32Array(n);
    let warmFrom = n;
    if (wrap) {
      let repeats = 1, lvl = feedback;
      while (lvl > 0.01 && repeats < 12) { lvl *= feedback; repeats++; }
      warmFrom = Math.max(0, n - delay * (repeats + 1));
      for (let i = warmFrom; i < n; i++) { const j = i - delay; line[i] = buf[i] + (j >= warmFrom ? line[j] * feedback : 0); }
    }
    for (let i = 0; i < n; i++) {
      const j = i - delay;
      let dl = 0;
      if (j >= 0) dl = line[j];
      else if (wrap && j + n >= warmFrom) dl = line[j + n];
      const x = buf[i];
      line[i] = x + dl * feedback;
      buf[i] = x + (line[i] - x) * wet;
    }
  }
  function peak(buf) { let m = 0; for (let i = 0; i < buf.length; i++) { const v = Math.abs(buf[i]); if (v > m) m = v; } return m; }
  function trim(buf) {
    let end = buf.length;
    while (end > 1 && Math.abs(buf[end - 1]) < 0.0005) end--;
    return buf.slice(0, Math.min(buf.length, end + 64));
  }
  // loudness: RMS over the audible part, peaks capped at 0.9
  function level(buf, target) {
    const pk = peak(buf);
    if (pk < 1e-5) return buf;
    let acc = 0, cnt = 0;
    for (let i = 0; i < buf.length; i++) { const v = buf[i]; if (Math.abs(v) > pk * 0.01) { acc += v * v; cnt++; } }
    const g = Math.min(target / Math.max(Math.sqrt(acc / Math.max(1, cnt)), 1e-5), 0.9 / pk);
    for (let i = 0; i < buf.length; i++) buf[i] *= g;
    return buf;
  }

  // ── SFX (the subset the concert uses) ──
  function buildSfx(rate) {
    const s = new Synth(rate);
    const arp = (notes, step, p, delay = 0, fb = 0, hold = 0) => {
      let out = new Float32Array(s.n(step * notes.length + hold + 0.4 + (delay ? delay * 4 : 0)));
      notes.forEach((m, i) => {
        const dur = i === notes.length - 1 && hold ? hold : step;
        mix(out, s.tone(midiHz(m), dur, p), s.n(step * i), 1, false);
      });
      if (delay) echo(out, s.n(delay), fb, 0.5, false);
      return trim(out);
    };
    const thud = (vol) => layer(
      s.tone(95, 0.03, { wave: "sine", a: 0.001, d: 0.12, s: 0, r: 0.05, pdrop: 9, pdecay: 0.02, vol }),
      s.tone(1, 0.02, { wave: "noise", a: 0.001, d: 0.04, s: 0, r: 0.02, lp: 1400, vol: vol * 0.4 }), 0);
    const chop = (pitch, bright) => {
      let out = layer(s.tone(1, 0.03, { wave: "noise", a: 0.0008, d: 0.035, s: 0, r: 0.02, hp: 2200, lp: 9000, vol: 0.55 }),
        s.tone(640 * pitch, 0.01, { wave: "sine", a: 0.0005, d: 0.05, s: 0, r: 0.02, pdrop: 5, pdecay: 0.01, vol: 0.45 }), s.n(0.004));
      out = layer(out, s.tone(130 * pitch, 0.02, { wave: "sine", a: 0.0008, d: 0.09, s: 0, r: 0.04, pdrop: 10, pdecay: 0.015, vol: 0.7 }), 0);
      if (bright) {
        out = layer(out, s.tone(2637, 0.02, { wave: "fm", fm_ratio: 1.41, fm_index: 2, fm_decay: 0.08, a: 0.001, d: 0.3, s: 0, r: 0.15, vol: 0.16 }), s.n(0.006));
        out = layer(out, s.tone(3951, 0.02, { wave: "sine", a: 0.001, d: 0.22, s: 0, r: 0.1, vol: 0.08 }), s.n(0.012));
      }
      return out;
    };
    const whoosh = (dur) => s.tone(1, dur, { wave: "noise", a: dur * 0.5, d: dur * 0.5, s: 0, r: 0.05, lp: 500, lp_env: 2500, lp_decay: dur, hp: 200, vol: 0.35 });
    const bell2 = (m1, m2) => {
      const p = { wave: "fm", fm_ratio: 3.5, fm_index: 2.2, fm_decay: 0.25, a: 0.001, d: 0.7, s: 0, r: 0.2, vol: 0.2 };
      const out = new Float32Array(s.n(1.3));
      mix(out, s.tone(midiHz(m1), 0.05, p), 0, 1, false);
      mix(out, s.tone(midiHz(m2), 0.05, p), s.n(0.11), 1, false);
      return trim(out);
    };
    const lib = {};
    lib.cut_good = [chop(1, false), 0.15];
    lib.cut_great = [chop(1.15, true), 0.15];
    lib.cut_miss = [layer(thud(0.7), s.tone(420, 0.28, { wave: "tri", a: 0.004, d: 0.1, s: 0.7, r: 0.08, slide: -19, vib: 0.4, vib_rate: 14, vib_delay: 0, vol: 0.32 }), s.n(0.02)), 0.12];
    lib.bin = [(() => {
      const clang = new Float32Array(s.n(0.6));
      for (const ratio of [1, 2.76, 5.4, 8.93]) mix(clang, s.tone(330 * ratio, 0.01, { wave: "sine", a: 0.0008, d: 0.45 / ratio, s: 0, r: 0.05, vol: 0.18 / Math.sqrt(ratio) }), 0, 1, false);
      return layer(whoosh(0.22), clang, s.n(0.16));
    })(), 0.09];
    lib.splat = [layer(s.tone(1, 0.18, { wave: "noise", a: 0.004, d: 0.2, s: 0, r: 0.06, lp: 700, lp_env: 1600, lp_decay: 0.05, trem: 0.8, trem_rate: 34, vol: 0.9 }),
      s.tone(160, 0.12, { wave: "sine", a: 0.003, d: 0.12, s: 0, r: 0.04, slide: -10, vol: 0.35 }), s.n(0.03)), 0.11];
    lib.countdown = [s.tone(midiHz(72), 0.08, { wave: "square", duty: 0.5, a: 0.002, d: 0.08, s: 0.3, r: 0.05, lp: 2500, vol: 0.2 }), 0.07];
    lib.countdown_go = [s.tone(midiHz(84), 0.22, { wave: "square", duty: 0.5, a: 0.002, d: 0.1, s: 0.5, r: 0.12, lp: 3500, vol: 0.2 }), 0.08];
    lib.menu_move = [s.tone(midiHz(81), 0.012, { wave: "tri", a: 0.001, d: 0.03, s: 0, r: 0.015, vol: 0.22 }), 0.035];
    lib.menu_select = [arp([76, 83], 0.055, { wave: "square", duty: 0.25, a: 0.002, d: 0.05, s: 0.3, r: 0.05, lp: 4000, vol: 0.14 }), 0.05];
    lib.combo_up = [arp([79, 84], 0.05, { wave: "square", duty: 0.25, a: 0.002, d: 0.06, s: 0.3, r: 0.06, vol: 0.14 }), 0.05];
    lib.coin = [layer(s.tone(987.77, 0.06, { wave: "square", duty: 0.5, a: 0.001, d: 0.05, s: 0.6, r: 0.18, lp: 6000, vol: 0.13 }),
      s.tone(1318.5, 0.22, { wave: "square", duty: 0.5, a: 0.001, d: 0.05, s: 0.6, r: 0.18, lp: 6000, vol: 0.13 }), s.n(0.06)), 0.06];
    lib.achievement = [bell2(88, 95), 0.08];
    lib.fever = [(() => {
      const sweep = s.tone(110, 0.5, { wave: "saw", a: 0.02, d: 0.3, s: 0.8, r: 0.1, slide: 24, lp: 300, detune: 12, vol: 0.22 });
      const chord = new Float32Array(s.n(1.2));
      for (const m of [72, 76, 79, 84]) mix(chord, s.tone(midiHz(m), 0.35, { wave: "saw", a: 0.005, d: 0.2, s: 0.5, r: 0.3, lp: 2200, lp_env: 4000, lp_decay: 0.12, detune: 9, vol: 0.1 }), 0, 1, false);
      const out = layer(sweep, chord, s.n(0.48));
      echo(out, s.n(0.15), 0.3, 0.35, false);
      return trim(out);
    })(), 0.11];
    lib.victory = [(() => {
      const lead = { wave: "square", duty: 0.25, a: 0.003, d: 0.1, s: 0.6, r: 0.15, vol: 0.16, vib: 0.15, vib_delay: 0.1 };
      const out = new Float32Array(s.n(2.4));
      for (const e of [[72, 0, 0.12], [72, 0.15, 0.12], [72, 0.3, 0.12], [76, 0.45, 0.3], [74, 0.8, 0.12], [76, 0.95, 0.12], [79, 1.1, 0.7]]) mix(out, s.tone(midiHz(e[0]), e[2], lead), s.n(e[1]), 1, false);
      const bass = { wave: "tri", a: 0.003, d: 0.1, s: 0.7, r: 0.1, vol: 0.3 };
      for (const e of [[48, 0, 0.4], [53, 0.45, 0.3], [55, 0.8, 0.25], [48, 1.1, 0.7]]) mix(out, s.tone(midiHz(e[0]), e[2], bass), s.n(e[1]), 1, false);
      echo(out, s.n(0.18), 0.25, 0.3, false);
      return trim(out);
    })(), 0.1];
    lib.game_over = [(() => {
      const p = { wave: "saw", a: 0.02, d: 0.1, s: 0.8, r: 0.12, lp: 700, lp_env: 900, lp_decay: 0.12, poles: 2, vol: 0.2 };
      const out = new Float32Array(s.n(2.6));
      for (const e of [[67, 0, 0.32], [66, 0.4, 0.32], [65, 0.8, 0.32]]) mix(out, s.tone(midiHz(e[0]), e[2], p), s.n(e[1]), 1, false);
      mix(out, s.tone(midiHz(64), 0.95, { ...p, vib: 0.35, vib_rate: 6, vib_delay: 0.15 }), s.n(1.2), 1, false);
      return trim(out);
    })(), 0.09];
    const out = {};
    for (const k in lib) {
      const buf = level(lib[k][0], lib[k][1]);
      const f = Math.min(Math.floor(rate * 0.002), buf.length >> 1);
      for (let i = 0; i < f; i++) { const g = i / f; buf[i] *= g; buf[buf.length - 1 - i] *= g; }
      out[k] = buf;
    }
    return out;
  }

  // ── instruments + the stem renderer (SongComposer.render) ──
  const INST = {
    bass_round: { wave: "tri", sub: 0.35, a: 0.004, d: 0.18, s: 0.65, r: 0.06, lp: 1100, vol: 0.6 },
    bass_funk: { wave: "saw", a: 0.003, d: 0.12, s: 0.5, r: 0.05, lp: 380, lp_env: 1800, lp_decay: 0.07, poles: 2, sub: 0.3, vol: 0.55 },
    bass_disco: { wave: "square", duty: 0.5, a: 0.003, d: 0.09, s: 0.55, r: 0.04, lp: 600, lp_env: 1200, lp_decay: 0.05, poles: 2, vol: 0.5 },
    bass_tuba: { wave: "square", duty: 0.45, a: 0.02, d: 0.15, s: 0.6, r: 0.06, lp: 500, poles: 2, sub: 0.4, vol: 0.55 },
    bass_synth: { wave: "saw", detune: 9, a: 0.004, d: 0.2, s: 0.7, r: 0.08, lp: 500, lp_env: 900, lp_decay: 0.12, poles: 2, sub: 0.45, vol: 0.5 },
    ep: { wave: "fm", fm_ratio: 1, fm_index: 1.3, fm_decay: 0.25, a: 0.003, d: 0.7, s: 0.25, r: 0.25, vol: 0.32 },
    pluck: { wave: "square", duty: 0.3, a: 0.002, d: 0.22, s: 0, r: 0.05, lp: 700, lp_env: 3000, lp_decay: 0.04, vol: 0.3 },
    uke: { wave: "tri", a: 0.002, d: 0.35, s: 0, r: 0.06, lp: 2400, lp_env: 2500, lp_decay: 0.03, noise: 0.02, vol: 0.34 },
    pad: { wave: "saw", detune: 14, a: 0.25, d: 0.4, s: 0.75, r: 0.5, lp: 900, vol: 0.16 },
    accordion: { wave: "saw", detune: 16, a: 0.03, d: 0.1, s: 0.8, r: 0.06, lp: 2200, trem: 0.18, trem_rate: 6, vol: 0.18 },
    organ: { wave: "tri", detune: 6, sub: 0.25, a: 0.01, d: 0.05, s: 0.9, r: 0.06, trem: 0.12, trem_rate: 6.5, vol: 0.24 },
    lead_square: { wave: "square", duty: 0.25, a: 0.005, d: 0.12, s: 0.65, r: 0.08, lp: 3800, vib: 0.14, vib_rate: 5.5, vib_delay: 0.16, vol: 0.24 },
    whistle: { wave: "sine", a: 0.02, d: 0.08, s: 0.85, r: 0.08, vib: 0.22, vib_rate: 5.8, vib_delay: 0.08, vol: 0.3 },
    marimba: { wave: "fm", fm_ratio: 4, fm_index: 1.6, fm_decay: 0.05, a: 0.002, d: 0.4, s: 0, r: 0.1, vol: 0.34 },
    lead_saw: { wave: "saw", detune: 8, a: 0.01, d: 0.15, s: 0.7, r: 0.1, lp: 2600, poles: 2, vib: 0.15, vib_delay: 0.18, vol: 0.22 },
    bell: { wave: "fm", fm_ratio: 3.5, fm_index: 1.8, fm_decay: 0.1, a: 0.001, d: 0.25, s: 0, r: 0.08, vol: 0.2 },
    sparkle: { wave: "square", duty: 0.125, a: 0.002, d: 0.08, s: 0, r: 0.04, lp: 5000, vol: 0.16 },
  };
  INST.accordion_lead = { ...INST.accordion, vol: 0.26, vib: 0.1 };

  const SONG_RATE = 32000;
  const idle = () => new Promise((r) => setTimeout(r, 0));

  // Render a composed song to {L,R} stems. Async: yields between stems so
  // the page keeps animating while the browser composes.
  async function renderSong(song, styleOf) {
    const st = styleOf(song.style);
    const syn = new Synth(SONG_RATE);
    const stepSec = 60 / song.bpm / 4;
    const frames = Math.round(song.bars * 16 * stepSec * SONG_RATE);
    const stepSamples = frames / (song.bars * 16);
    const stems = {};
    for (const name of ["drums", "harmony", "lead", "fever"]) stems[name] = [new Float32Array(frames), new Float32Array(frames)];
    const at = (step) => Math.round(step * stepSamples);
    const cache = new Map();
    const note = (name, inst, midi, dur) => {
      const key = name + "|" + midi + "|" + Math.trunc(dur * 1000);
      let b = cache.get(key);
      if (!b) { b = syn.tone(midiHz(midi), dur, inst); cache.set(key, b); }
      return b;
    };

    const kit = {
      kick: syn.kick(0.9), snare: syn.snare(0.55, 190, 0.12), hat: syn.hat(0.22), ohat: syn.hat(0.2, 0.16, 6500),
      clap: syn.clap(0.55), shaker: syn.shaker(0.2), rim: syn.rim(0.35), tom: syn.tom(0.55, 110),
    };
    const drumPan = { kick: 0, snare: 0.05, hat: 0.35, ohat: 0.4, clap: -0.05, shaker: -0.35, rim: -0.2, tom: -0.15 };
    for (const e of song.drums) mixPan(stems.drums[0], stems.drums[1], kit[e[1]], at(e[0]), e[2], drumPan[e[1]] || 0);
    await idle();

    const H = stems.harmony;
    for (const e of song.bass) mixPan(H[0], H[1], note(st.bass_inst, INST[st.bass_inst], e[2], e[1] * stepSec * 0.92), at(e[0]), 1, 0);
    const compName = st.comp_inst, strum = compName === "uke" || compName === "pluck" ? 0.012 : 0;
    for (const e of song.comp) {
      const chord = e[2], dur = e[1] * stepSec * 0.95;
      chord.forEach((m, k) => {
        const pan = -0.45 + 0.9 * k / Math.max(1, chord.length - 1);
        mixPan(H[0], H[1], note(compName, INST[compName], m, dur), Math.round(e[0] * stepSamples + k * strum * SONG_RATE), 0.8 / Math.sqrt(chord.length), pan);
      });
    }
    for (const e of song.arp) mixPan(H[0], H[1], note("bell", INST.bell, e[2], e[1] * stepSec), at(e[0]), 0.55, -0.25);
    await idle();

    const leadInst = INST[st.lead] || INST.lead_square;
    const legato = st.lead === "marimba" ? 0.6 : 0.9;
    for (const e of song.lead) mixPan(stems.lead[0], stems.lead[1], note(st.lead, leadInst, e[2], e[1] * stepSec * legato), at(e[0]), 1, 0.1);
    if (st.lead_echo > 0) {
      const d = Math.round(stepSamples * 3);
      echo(stems.lead[0], d, st.lead_echo, 0.35, true);
      echo(stems.lead[1], d + Math.round(SONG_RATE * 0.011), st.lead_echo, 0.35, true);
    }
    await idle();

    let flip = 1;
    for (const e of song.fever) { mixPan(stems.fever[0], stems.fever[1], note("fever", INST.sparkle, e[2], e[1] * stepSec), at(e[0]), 1, 0.5 * flip); flip = -flip; }
    echo(stems.fever[0], Math.round(stepSamples * 3), 0.3, 0.3, true);
    echo(stems.fever[1], Math.round(stepSamples * 3) + Math.round(SONG_RATE * 0.009), 0.3, 0.3, true);

    const targets = { drums: 0.092, harmony: 0.068, lead: 0.062, fever: 0.04 };
    for (const name in stems) {
      const [L, R] = stems[name];
      let acc = 0, pk = 0, cnt = 0;
      for (let i = 0; i < frames; i += 3) { acc += L[i] * L[i] + R[i] * R[i]; pk = Math.max(pk, Math.abs(L[i]), Math.abs(R[i])); cnt += 2; }
      const rms = Math.sqrt(acc / Math.max(1, cnt));
      const g = rms < 1e-6 ? 1 : Math.min(targets[name] / rms, 0.95 / Math.max(pk, 1e-4));
      for (let i = 0; i < frames; i++) { L[i] *= g; R[i] *= g; }
    }
    return { stems, frames, rate: SONG_RATE, loopSec: frames / SONG_RATE };
  }

  const api = { Synth, buildSfx, renderSong, midiHz, SFX_RATE: 44100 };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.SliceAudio = api;
})(this);
