extends RefCounted
class_name Synth

# A tiny procedural synthesizer. Every sound in the game — knife chops, coins,
# the whole soundtrack — is generated here at runtime, so the project ships
# with zero audio assets (the same "procedural first" rule as the art).
#
# Buffers are PackedFloat32Array of mono samples at `rate`. Stereo is two
# buffers (L, R) mixed with a pan. Everything is plain arithmetic in typed
# GDScript; a few hundred thousand samples render in tens of milliseconds, and
# the music composer runs on a worker thread so nothing here blocks a frame.
#
# Voices are described by a parameter Dictionary (see `tone()`), which keeps
# instrument definitions as data — SfxLibrary and SongComposer are just
# recipes built from these primitives.

const TAU_F := TAU

var rate: int
var rng := RandomNumberGenerator.new()

func _init(sample_rate: int = 44100, seed_value: int = 7):
	rate = sample_rate
	rng.seed = seed_value

static func midi_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

func n_samples(sec: float) -> int:
	return maxi(1, int(sec * rate))

func silence(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n_samples(sec))
	b.fill(0.0)
	return b

# polyBLEP residual: rounds off the hard edges of saw/square waves so they
# don't alias into harsh whistles at high pitches.
static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0

# ────────────────────────────────────────────────────────
#  The general-purpose voice
# ────────────────────────────────────────────────────────
#
# Renders one note of `dur` seconds (gate length) plus its release tail.
# Recognised parameters (all optional):
#   wave      "sine" | "tri" | "square" | "saw" | "noise" | "fm"
#   duty      pulse width for "square" (0..1, default 0.5)
#   a d s r   ADSR in seconds; s is the sustain level (0..1)
#   vol       output gain
#   pdrop     start pitch offset in semitones, decaying with time-constant pdecay
#   slide     semitones glided linearly across the gate (pitch bends, sirens)
#   vib       vibrato depth (semitones), vib_rate (Hz), vib_delay (s)
#   lp        one-pole low-pass cutoff (Hz); lp_env adds cutoff that decays
#             with lp_decay (a "wah" / pluck brightness envelope); poles=2
#             runs it twice for a steeper 12 dB/oct slope
#   hp        one-pole high-pass cutoff (Hz)
#   detune    cents for a second, detuned oscillator (chorus / unison)
#   sub       level of a sine one octave down
#   fm_ratio, fm_index, fm_decay  — 2-operator FM ("fm" wave): electric
#             pianos and bells; index decays to 30% over fm_decay
#   noise     amount of white noise blended into the oscillator (breath/chiff)
#   trem      tremolo depth (0..1), trem_rate (Hz)
func tone(freq: float, dur: float, p: Dictionary) -> PackedFloat32Array:
	var a: float = p.get("a", 0.004)
	var d: float = p.get("d", 0.08)
	var s: float = p.get("s", 0.6)
	var r: float = p.get("r", 0.08)
	var vol: float = p.get("vol", 0.5)
	var pdrop: float = p.get("pdrop", 0.0)
	var slide: float = p.get("slide", 0.0)
	var vib: float = p.get("vib", 0.0)
	var detune: float = p.get("detune", 0.0)
	var sub: float = p.get("sub", 0.0)
	var noise_amt: float = p.get("noise", 0.0)
	var lp: float = p.get("lp", 0.0)
	var hp: float = p.get("hp", 0.0)
	var trem: float = p.get("trem", 0.0)

	var wcode := 0
	match p.get("wave", "square"):
		"sine": wcode = 0
		"tri": wcode = 1
		"square": wcode = 2
		"saw": wcode = 3
		"noise": wcode = 4
		"fm": wcode = 5

	# A percussive note (no sustain) rings out its full attack + decay no
	# matter how short the gate — `dur` only matters for sustained notes.
	var gate := n_samples(dur)
	if s <= 0.0:
		gate = maxi(gate, n_samples(a + d))
	var total := gate + n_samples(r)
	var out := PackedFloat32Array()
	out.resize(total)

	# Per-sample phase increment. Constant for plain notes (filled natively);
	# pitch drops, slides and vibrato modulate it.
	var dts := PackedFloat32Array()
	dts.resize(total)
	dts.fill(freq / rate)
	if pdrop != 0.0 or slide != 0.0 or vib != 0.0:
		_pitch_mod(dts, freq, dur, p)

	_osc(out, wcode, dts, 1.0, p)
	if detune != 0.0 and wcode != 4:
		var b := PackedFloat32Array()
		b.resize(total)
		_osc(b, wcode if wcode != 5 else 0, dts, pow(2.0, detune / 1200.0), p)
		for i in total:
			out[i] = (out[i] + b[i]) * 0.5
	if sub > 0.0:
		var ph := 0.0
		for i in total:
			out[i] += sub * sin(TAU_F * ph)
			ph += dts[i] * 0.5
			if ph >= 1.0:
				ph -= 1.0
	if noise_amt > 0.0:
		for i in total:
			out[i] += noise_amt * rng.randf_range(-1.0, 1.0)
	if lp > 0.0:
		lowpass(out, lp, p.get("lp_env", 0.0), p.get("lp_decay", 0.15))
		if int(p.get("poles", 1)) >= 2:  # 12 dB/oct for darker basses / brass
			lowpass(out, lp, p.get("lp_env", 0.0), p.get("lp_decay", 0.15))
	if hp > 0.0:
		highpass(out, hp)
	if trem > 0.0:
		var tr: float = TAU_F * p.get("trem_rate", 6.0) / rate
		for i in total:
			out[i] *= 1.0 - trem * (0.5 + 0.5 * sin(tr * i))
	_envelope(out, gate, a, d, s, r, vol)
	return out

func _pitch_mod(dts: PackedFloat32Array, freq: float, dur: float, p: Dictionary):
	var pdrop: float = p.get("pdrop", 0.0)
	var pdecay: float = maxf(0.0005, p.get("pdecay", 0.03))
	var slide: float = p.get("slide", 0.0)
	var vib: float = p.get("vib", 0.0)
	var vib_w: float = TAU_F * p.get("vib_rate", 5.5)
	var vib_delay: float = p.get("vib_delay", 0.12)
	var k := log(2.0) / 12.0
	var base := freq / rate
	var inv_rate := 1.0 / rate
	var inv_dur := 1.0 / maxf(dur, 0.0001)
	var drop := pdrop
	var drop_mul := exp(-inv_rate / pdecay)
	for i in dts.size():
		var t := i * inv_rate
		var semis := drop + slide * minf(1.0, t * inv_dur)
		drop *= drop_mul
		if t > vib_delay:
			semis += vib * sin(vib_w * (t - vib_delay))
		dts[i] = base * exp(semis * k)

# One oscillator per tight loop (no per-sample branching on the waveform).
func _osc(out: PackedFloat32Array, wcode: int, dts: PackedFloat32Array, mul: float, p: Dictionary):
	var n := out.size()
	var ph := 0.0
	match wcode:
		0:
			for i in n:
				out[i] = sin(TAU_F * ph)
				ph += dts[i] * mul
				if ph >= 1.0:
					ph -= 1.0
		1:
			for i in n:
				out[i] = 4.0 * absf(ph - 0.5) - 1.0
				ph += dts[i] * mul
				if ph >= 1.0:
					ph -= 1.0
		2:
			var duty: float = p.get("duty", 0.5)
			# polyBLEP inlined at both edges (a call per sample is the
			# expensive part of GDScript synthesis)
			for i in n:
				var dt := dts[i] * mul
				var v := 1.0 if ph < duty else -1.0
				if ph < dt:
					var t := ph / dt
					v += t + t - t * t - 1.0
				elif ph > 1.0 - dt:
					var t := (ph - 1.0) / dt
					v += t * t + t + t + 1.0
				var p2 := ph + 1.0 - duty
				if p2 >= 1.0:
					p2 -= 1.0
				if p2 < dt:
					var t := p2 / dt
					v -= t + t - t * t - 1.0
				elif p2 > 1.0 - dt:
					var t := (p2 - 1.0) / dt
					v -= t * t + t + t + 1.0
				out[i] = v
				ph += dt
				if ph >= 1.0:
					ph -= 1.0
		3:
			for i in n:
				var dt := dts[i] * mul
				var v := 2.0 * ph - 1.0
				if ph < dt:
					var t := ph / dt
					v -= t + t - t * t - 1.0
				elif ph > 1.0 - dt:
					var t := (ph - 1.0) / dt
					v -= t * t + t + t + 1.0
				out[i] = v
				ph += dt
				if ph >= 1.0:
					ph -= 1.0
		4:
			for i in n:
				out[i] = rng.randf_range(-1.0, 1.0)
		5:
			# 2-op FM: modulator index decays toward 30% (bright attack, mellow body)
			var ratio: float = p.get("fm_ratio", 1.0)
			var idx: float = p.get("fm_index", 1.5)
			var idx_mul := exp(-1.0 / (maxf(0.001, p.get("fm_decay", 0.4)) * rate))
			var dyn := idx * 0.7
			var pm := 0.0
			for i in n:
				var dt := dts[i] * mul
				out[i] = sin(TAU_F * ph + (idx * 0.3 + dyn) * sin(TAU_F * pm))
				dyn *= idx_mul
				ph += dt
				if ph >= 1.0:
					ph -= 1.0
				pm += dt * ratio
				if pm >= 1.0:
					pm -= floorf(pm)

# One-pole low-pass; `env` Hz of extra cutoff decays away with `decay` s.
func lowpass(buf: PackedFloat32Array, cutoff: float, env: float = 0.0, decay: float = 0.15):
	var y := 0.0
	var w := TAU_F / rate
	var e := env
	var e_mul := exp(-1.0 / (maxf(0.001, decay) * rate))
	for i in buf.size():
		var a := minf(1.0, (cutoff + e) * w)
		e *= e_mul
		y += a * (buf[i] - y)
		buf[i] = y

func highpass(buf: PackedFloat32Array, cutoff: float):
	var a := exp(-TAU_F * minf(cutoff, rate * 0.45) / rate)
	var y := 0.0
	var px := 0.0
	for i in buf.size():
		var x := buf[i]
		y = a * (y + x - px)
		px = x
		buf[i] = y

# ADSR applied in segments (attack / decay / sustain / release) with the
# release starting from whatever level the gate closed on.
func _envelope(buf: PackedFloat32Array, gate: int, a: float, d: float, s: float, r: float, vol: float):
	var total := buf.size()
	var na := mini(n_samples(a), gate)
	var nd := maxi(1, n_samples(d))
	var level := 0.0
	for i in na:
		level = float(i) / na
		buf[i] *= level * vol
	var dec_end := mini(na + nd, gate)
	for i in range(na, dec_end):
		level = 1.0 - (1.0 - s) * (float(i - na) / nd)
		buf[i] *= level * vol
	if dec_end < gate:
		level = s
		var sv := s * vol
		for i in range(dec_end, gate):
			buf[i] *= sv
	var nr := total - gate
	for i in range(gate, total):
		buf[i] *= level * (1.0 - float(i - gate) / nr) * vol

# ────────────────────────────────────────────────────────
#  Drum kit
# ────────────────────────────────────────────────────────

func kick(vol: float = 0.9, f0: float = 160.0, f1: float = 48.0, decay: float = 0.28) -> PackedFloat32Array:
	var n := n_samples(decay * 1.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := f1 + (f0 - f1) * exp(-t / 0.035)
		ph += f / rate
		var v := sin(TAU_F * ph) * exp(-t / decay)
		if i < 120:  # beater click
			v += rng.randf_range(-0.4, 0.4) * (1.0 - i / 120.0)
		out[i] = v * vol
	return out

func snare(vol: float = 0.6, tone_hz: float = 190.0, decay: float = 0.16) -> PackedFloat32Array:
	var n := n_samples(decay * 1.8)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var hp_y := 0.0
	var hp_x := 0.0
	var hp_a := exp(-TAU_F * 1200.0 / rate)
	for i in n:
		var t := float(i) / rate
		ph += tone_hz * (1.0 + 0.5 * exp(-t / 0.01)) / rate
		var body := sin(TAU_F * ph) * exp(-t / 0.05) * 0.55
		var x := rng.randf_range(-1.0, 1.0)
		var hy := hp_a * (hp_y + x - hp_x)
		hp_x = x
		hp_y = hy
		out[i] = (body + hy * exp(-t / decay) * 0.8) * vol
	return out

func hat(vol: float = 0.25, decay: float = 0.035, cutoff: float = 7000.0) -> PackedFloat32Array:
	var n := n_samples(decay * 4.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp_y := 0.0
	var hp_x := 0.0
	var hp_a := exp(-TAU_F * minf(cutoff, rate * 0.45) / rate)
	for i in n:
		var t := float(i) / rate
		var x := rng.randf_range(-1.0, 1.0)
		var hy := hp_a * (hp_y + x - hp_x)
		hp_x = x
		hp_y = hy
		out[i] = hy * exp(-t / decay) * vol
	return out

func clap(vol: float = 0.5) -> PackedFloat32Array:
	var n := n_samples(0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp_y := 0.0
	var hp_y := 0.0
	var hp_x := 0.0
	var hp_a := exp(-TAU_F * 900.0 / rate)
	var la := minf(1.0, TAU_F * 2600.0 / rate)
	for i in n:
		var t := float(i) / rate
		# three quick flams, then the room tail
		var env := 0.0
		for k in 3:
			var tk := t - k * 0.011
			if tk >= 0.0 and tk < 0.011:
				env = maxf(env, exp(-tk / 0.004))
		env = maxf(env, exp(-maxf(0.0, t - 0.022) / 0.09) * (1.0 if t >= 0.022 else 0.0))
		var x := rng.randf_range(-1.0, 1.0)
		lp_y += la * (x - lp_y)
		var hy := hp_a * (hp_y + lp_y - hp_x)
		hp_x = lp_y
		hp_y = hy
		out[i] = hy * env * vol * 2.2
	return out

func shaker(vol: float = 0.18) -> PackedFloat32Array:
	var n := n_samples(0.09)
	var out := PackedFloat32Array()
	out.resize(n)
	var hp_y := 0.0
	var hp_x := 0.0
	var hp_a := exp(-TAU_F * 5000.0 / rate)
	for i in n:
		var t := float(i) / rate
		var env := minf(1.0, t / 0.012) * exp(-t / 0.03)
		var x := rng.randf_range(-1.0, 1.0)
		var hy := hp_a * (hp_y + x - hp_x)
		hp_x = x
		hp_y = hy
		out[i] = hy * env * vol
	return out

func rim(vol: float = 0.3) -> PackedFloat32Array:
	var a := tone(1750.0, 0.01, {"wave": "sine", "a": 0.0005, "d": 0.03, "s": 0.0, "r": 0.02, "vol": vol})
	var b := tone(820.0, 0.01, {"wave": "tri", "a": 0.0005, "d": 0.04, "s": 0.0, "r": 0.02, "vol": vol * 0.6})
	mix(a, b, 0)
	return a

func tom(vol: float = 0.6, f: float = 120.0) -> PackedFloat32Array:
	return tone(f, 0.05, {"wave": "sine", "a": 0.001, "d": 0.22, "s": 0.0, "r": 0.1,
			"pdrop": 7.0, "pdecay": 0.06, "vol": vol})

# ────────────────────────────────────────────────────────
#  Buffer utilities
# ────────────────────────────────────────────────────────

# Add src into dst at `start` (samples). With wrap=true the overflow wraps to
# the beginning, so a looped stem's release tails and echoes flow seamlessly
# across the loop point.
static func mix(dst: PackedFloat32Array, src: PackedFloat32Array, start: int, gain: float = 1.0, wrap: bool = false):
	var n := dst.size()
	var m := src.size()
	if n == 0 or m == 0:
		return
	if wrap:
		start = posmod(start, n)
		# first run up to the end of dst, then wrap the rest to the start
		var first := mini(m, n - start)
		for i in first:
			dst[start + i] += src[i] * gain
		var j := 0
		for i in range(first, m):
			dst[j] += src[i] * gain
			j += 1
			if j >= n:
				j = 0
	else:
		var end := mini(m, n - start)
		var i0 := maxi(0, -start)
		for i in range(i0, end):
			dst[start + i] += src[i] * gain

# Stereo mix with an equal-power pan (-1 left .. +1 right).
static func mix_pan(dl: PackedFloat32Array, dr: PackedFloat32Array, src: PackedFloat32Array,
		start: int, gain: float, pan: float, wrap: bool = true):
	var ang := (clampf(pan, -1.0, 1.0) + 1.0) * PI * 0.25
	mix(dl, src, start, gain * cos(ang) * 1.41421356, wrap)
	mix(dr, src, start, gain * sin(ang) * 1.41421356, wrap)

# Append b after a with a gap (seconds) — used to string SFX notes together.
func concat(a: PackedFloat32Array, b: PackedFloat32Array, at_sec: float) -> PackedFloat32Array:
	var start := n_samples(at_sec)
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), start + b.size()))
	out.fill(0.0)
	mix(out, a, 0)
	mix(out, b, start)
	return out

# Feedback echo. Circular (wrap=true) for loops: a short warm-up pass over
# the end of the buffer seeds the delay line, so the echoes of the last bar
# ring into the first and the loop point is seamless.
static func echo(buf: PackedFloat32Array, delay_samples: int, feedback: float, wet: float, wrap: bool = false):
	var n := buf.size()
	if n == 0 or delay_samples <= 0:
		return
	var line := PackedFloat32Array()
	line.resize(n)
	line.fill(0.0)
	var warm_from := n
	if wrap:
		# enough repeats for the feedback to decay below ~1%
		var repeats := 1
		var lvl := feedback
		while lvl > 0.01 and repeats < 12:
			lvl *= feedback
			repeats += 1
		warm_from = maxi(0, n - delay_samples * (repeats + 1))
		for i in range(warm_from, n):
			var j := i - delay_samples
			line[i] = buf[i] + (line[j] * feedback if j >= warm_from else 0.0)
	for i in n:
		var j := i - delay_samples
		var delayed := 0.0
		if j >= 0:
			delayed = line[j]
		elif wrap and j + n >= warm_from:
			delayed = line[j + n]
		var x := buf[i]
		line[i] = x + delayed * feedback
		buf[i] = x + (line[i] - x) * wet

static func gain(buf: PackedFloat32Array, g: float):
	for i in buf.size():
		buf[i] *= g

# Gentle tanh-style saturation that keeps peaks under 1.0 without hard clips.
static func soft_clip(buf: PackedFloat32Array, drive: float = 1.0):
	for i in buf.size():
		var x := buf[i] * drive
		buf[i] = x / (1.0 + absf(x))

static func peak(buf: PackedFloat32Array) -> float:
	var m := 0.0
	for v in buf:
		m = maxf(m, absf(v))
	return m

# Scale so the loudest sample sits at `target`.
static func normalize(buf: PackedFloat32Array, target: float = 0.8):
	var p := peak(buf)
	if p > 0.0001:
		gain(buf, target / p)

# Short linear fade at both ends — kills clicks on one-shot SFX.
func declick(buf: PackedFloat32Array, fade_sec: float = 0.003):
	var f := mini(n_samples(fade_sec), buf.size() / 2)
	for i in f:
		var k := float(i) / f
		buf[i] *= k
		buf[buf.size() - 1 - i] *= k

# ────────────────────────────────────────────────────────
#  Encoding
# ────────────────────────────────────────────────────────

# Pack mono (or L/R stereo) float buffers into a 16-bit AudioStreamWAV.
# Two 16-bit samples are packed per int32 and converted natively — far
# cheaper than a per-sample encode call. `g` is an output gain folded in.
func to_wav(left: PackedFloat32Array, right: PackedFloat32Array = PackedFloat32Array(), loop: bool = false,
		g: float = 1.0) -> AudioStreamWAV:
	var stereo := right.size() == left.size() and right.size() > 0
	var frames := left.size()
	var ints := PackedInt32Array()
	var k := 32767.0 * g
	if stereo:
		ints.resize(frames)
		for i in frames:
			var a := int(clampf(left[i] * k, -32767.0, 32767.0))
			var b := int(clampf(right[i] * k, -32767.0, 32767.0))
			ints[i] = (a & 0xFFFF) | (b << 16)
	else:
		var pairs := (frames + 1) / 2
		ints.resize(pairs)
		for i in pairs:
			var a := int(clampf(left[2 * i] * k, -32767.0, 32767.0))
			var b := 0
			if 2 * i + 1 < frames:
				b = int(clampf(left[2 * i + 1] * k, -32767.0, 32767.0))
			ints[i] = (a & 0xFFFF) | (b << 16)
	var bytes := ints.to_byte_array()
	if not stereo and frames % 2 == 1:
		bytes.resize(frames * 2)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = stereo
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = frames
	return w
