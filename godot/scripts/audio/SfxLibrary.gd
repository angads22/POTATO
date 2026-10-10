extends RefCounted
class_name SfxLibrary

# Recipes for every sound effect in the game, built from Synth primitives at
# boot (~50 ms for the whole set). Names are the keys AudioManager.play_sfx()
# takes; add a sound by adding one entry to build().
#
# Design notes: chops are a noise transient + a woody body, so they read as
# "knife on board" rather than "beep"; UI blips are short, soft and pitched in
# the same key (C major) so menu navigation never sounds out of tune; the big
# moments (fever, fanfares) are little arpeggios with an echo tail.

const RATE := 44100

static func build() -> Dictionary:
	var s := Synth.new(RATE, 1234)
	var out := {}

	# ── kitchen: cuts ──
	out["cut_good"] = _chop(s, 1.0, false)
	out["cut_great"] = _chop(s, 1.15, true)
	out["cut_miss"] = _miss(s)
	out["potato_land"] = _thud(s, 0.5)
	out["potato_drop"] = s.tone(520.0, 0.18, {"wave": "sine", "a": 0.002, "d": 0.18, "s": 0.0, "r": 0.02,
			"slide": -14.0, "vol": 0.18})
	out["bin"] = _bin(s)
	out["splat"] = _splat(s)
	out["golden"] = _arp(s, [84, 88, 91, 96, 100], 0.045, {"wave": "square", "duty": 0.25, "a": 0.002, "d": 0.12,
			"s": 0.2, "r": 0.15, "vol": 0.16}, 0.12, 0.35)
	out["peel_start"] = s.tone(Synth.midi_hz(67), 0.06, {"wave": "tri", "a": 0.002, "d": 0.06, "s": 0.0, "r": 0.02,
			"slide": 5.0, "vol": 0.3})
	out["beat_tick"] = s.tone(Synth.midi_hz(96), 0.01, {"wave": "sine", "a": 0.0005, "d": 0.03, "s": 0.0, "r": 0.01, "vol": 0.18})
	out["zone_tick"] = s.tone(Synth.midi_hz(91), 0.01, {"wave": "square", "duty": 0.5, "a": 0.0005, "d": 0.025, "s": 0.0,
			"r": 0.01, "lp": 3000.0, "vol": 0.12})

	# ── kitchen: combo / fever / stage flow ──
	out["fever_start"] = _fever(s)
	out["combo_up"] = _arp(s, [79, 84], 0.05, {"wave": "square", "duty": 0.25, "a": 0.002, "d": 0.06, "s": 0.3,
			"r": 0.06, "vol": 0.14}, 0.0, 0.0)
	out["level_complete"] = _arp(s, [72, 76, 79, 84], 0.09, {"wave": "square", "duty": 0.25, "a": 0.003,
			"d": 0.1, "s": 0.5, "r": 0.2, "vol": 0.17}, 0.14, 0.3, 0.42)
	out["victory"] = _victory(s)
	out["game_over"] = _sad_trombone(s)
	out["countdown"] = s.tone(Synth.midi_hz(72), 0.08, {"wave": "square", "duty": 0.5, "a": 0.002, "d": 0.08, "s": 0.3,
			"r": 0.05, "lp": 2500.0, "vol": 0.2})
	out["countdown_go"] = s.tone(Synth.midi_hz(84), 0.22, {"wave": "square", "duty": 0.5, "a": 0.002, "d": 0.1, "s": 0.5,
			"r": 0.12, "lp": 3500.0, "vol": 0.2})

	# ── boss ──
	out["boss_roar"] = _roar(s)
	out["boss_hit"] = _boss_hit(s)
	out["boss_down"] = _explosion(s, 1.4)

	# ── menus / meta ──
	out["menu_move"] = s.tone(Synth.midi_hz(81), 0.012, {"wave": "tri", "a": 0.001, "d": 0.03, "s": 0.0, "r": 0.015, "vol": 0.22})
	out["menu_select"] = _arp(s, [76, 83], 0.055, {"wave": "square", "duty": 0.25, "a": 0.002, "d": 0.05,
			"s": 0.3, "r": 0.05, "lp": 4000.0, "vol": 0.14}, 0.0, 0.0)
	out["menu_back"] = _arp(s, [79, 72], 0.055, {"wave": "square", "duty": 0.25, "a": 0.002, "d": 0.05,
			"s": 0.3, "r": 0.05, "lp": 3000.0, "vol": 0.12}, 0.0, 0.0)
	out["type"] = s.tone(Synth.midi_hz(88), 0.006, {"wave": "square", "duty": 0.5, "a": 0.0005, "d": 0.015, "s": 0.0,
			"r": 0.01, "lp": 2500.0, "vol": 0.1})
	out["pause"] = _arp(s, [79, 74], 0.06, {"wave": "tri", "a": 0.002, "d": 0.08, "s": 0.3, "r": 0.08, "vol": 0.25}, 0.0, 0.0)
	out["unpause"] = _arp(s, [74, 79], 0.06, {"wave": "tri", "a": 0.002, "d": 0.08, "s": 0.3, "r": 0.08, "vol": 0.25}, 0.0, 0.0)
	out["achievement"] = _bell_pair(s, 88, 95)
	out["rank_up"] = _arp(s, [72, 76, 79, 84, 88, 91, 96], 0.05, {"wave": "fm", "fm_ratio": 3.0, "fm_index": 1.2,
			"fm_decay": 0.2, "a": 0.002, "d": 0.2, "s": 0.2, "r": 0.3, "vol": 0.2}, 0.16, 0.35)
	out["error"] = _arp(s, [45, 45], 0.09, {"wave": "square", "duty": 0.5, "a": 0.002, "d": 0.02, "s": 0.8,
			"r": 0.02, "lp": 900.0, "vol": 0.16}, 0.0, 0.0)

	# ── economy ──
	out["coin_collect"] = _coin(s)
	out["coin"] = out["coin_collect"]
	out["purchase"] = _cash_register(s)
	out["research"] = _arp(s, [72, 79, 84, 91], 0.07, {"wave": "fm", "fm_ratio": 2.0, "fm_index": 1.0,
			"fm_decay": 0.15, "a": 0.002, "d": 0.15, "s": 0.3, "r": 0.25, "vol": 0.2}, 0.18, 0.3)

	# ── farm ──
	out["plow"] = _scrape(s)
	out["plant"] = s.tone(220.0, 0.05, {"wave": "sine", "a": 0.001, "d": 0.07, "s": 0.0, "r": 0.03,
			"slide": 14.0, "vol": 0.4})
	out["water"] = _splash(s)
	out["harvest"] = _harvest(s)
	out["sprinkler"] = _hiss(s)
	out["fertilize"] = _sprinkle(s)
	out["truck_horn"] = _horn(s)
	out["cover"] = _scrape(s, 0.6)
	out["footstep"] = s.hat(0.12, 0.012, 1800.0)
	out["gate"] = _whoosh(s, 0.35)

	# ── SPUD BLASTER ──
	out["fps_shot"] = _gunshot(s, 1.0)
	out["fps_shot_heavy"] = _gunshot(s, 0.6)
	out["fps_launcher"] = _launcher(s)
	out["fps_hit"] = s.tone(1900.0, 0.012, {"wave": "square", "duty": 0.5, "a": 0.0005, "d": 0.04, "s": 0.0,
			"r": 0.02, "lp": 6000.0, "vol": 0.16})
	out["fps_headshot"] = _arp(s, [98, 103], 0.035, {"wave": "square", "duty": 0.5, "a": 0.0005, "d": 0.04,
			"s": 0.0, "r": 0.03, "lp": 7000.0, "vol": 0.15}, 0.0, 0.0)
	out["fps_frag"] = _bell_pair(s, 84, 91)
	out["fps_hurt"] = _thud(s, 0.9)
	out["fps_jump"] = s.tone(260.0, 0.07, {"wave": "tri", "a": 0.002, "d": 0.08, "s": 0.0, "r": 0.03,
			"slide": 9.0, "vol": 0.18})
	out["fps_pickup"] = _arp(s, [76, 81, 88], 0.04, {"wave": "square", "duty": 0.25, "a": 0.002, "d": 0.05,
			"s": 0.3, "r": 0.06, "vol": 0.14}, 0.0, 0.0)
	out["fps_explosion"] = _explosion(s, 0.8)
	out["fps_reload"] = _arp(s, [55, 62], 0.12, {"wave": "square", "duty": 0.5, "a": 0.001, "d": 0.03, "s": 0.0,
			"r": 0.01, "lp": 1800.0, "noise": 0.4, "vol": 0.3}, 0.0, 0.0)
	out["fps_death"] = _miss(s)

	var waves := {}
	for k in out:
		var buf: PackedFloat32Array = out[k]
		_level(buf, LOUDNESS.get(k, 0.08))
		s.declick(buf, 0.002)
		waves[k] = s.to_wav(buf)
	return waves

# Target RMS loudness per sound (default 0.08), so a chop, a coin and a menu
# blip sit at sensible relative levels no matter how each recipe was built.
# Measured over the loud part of the sound; peaks are capped at 0.9.
const LOUDNESS := {
	"cut_good": 0.15, "cut_great": 0.15, "cut_miss": 0.12, "boss_hit": 0.16,
	"potato_land": 0.07, "potato_drop": 0.03, "bin": 0.09, "splat": 0.11,
	"beat_tick": 0.03, "zone_tick": 0.035, "peel_start": 0.06,
	"menu_move": 0.035, "menu_select": 0.05, "menu_back": 0.045, "type": 0.03,
	"pause": 0.05, "unpause": 0.05, "error": 0.06,
	"coin": 0.06, "coin_collect": 0.06, "purchase": 0.08, "research": 0.08,
	"fever_start": 0.11, "level_complete": 0.09, "victory": 0.1, "game_over": 0.09,
	"achievement": 0.08, "rank_up": 0.09, "golden": 0.08, "combo_up": 0.05,
	"countdown": 0.07, "countdown_go": 0.08,
	"boss_roar": 0.14, "boss_down": 0.15,
	"plow": 0.07, "cover": 0.05, "plant": 0.06, "water": 0.07, "harvest": 0.08,
	"sprinkler": 0.04, "fertilize": 0.05, "truck_horn": 0.09, "footstep": 0.02, "gate": 0.05,
	"fps_shot": 0.12, "fps_shot_heavy": 0.13, "fps_launcher": 0.13, "fps_hit": 0.05,
	"fps_headshot": 0.06, "fps_frag": 0.08, "fps_hurt": 0.12, "fps_jump": 0.04,
	"fps_pickup": 0.06, "fps_explosion": 0.15, "fps_death": 0.11, "fps_reload": 0.05,
}

static func _level(buf: PackedFloat32Array, target_rms: float):
	# RMS over the samples above -40 dB of the peak (ignore the silent tail)
	var pk := Synth.peak(buf)
	if pk < 0.00001:
		return
	var floor_v := pk * 0.01
	var acc := 0.0
	var cnt := 0
	for v in buf:
		if absf(v) > floor_v:
			acc += v * v
			cnt += 1
	var rms := sqrt(acc / maxi(1, cnt))
	var g := target_rms / maxf(rms, 0.00001)
	g = minf(g, 0.9 / pk)
	Synth.gain(buf, g)

# ────────────────────────────────────────────────────────
#  Recipes
# ────────────────────────────────────────────────────────

# Knife through spud onto wood: a bright noise "shk", a woody knock and a
# low thunk. `bright` adds the metallic "shing" of a perfect cut.
static func _chop(s: Synth, pitch: float, bright: bool) -> PackedFloat32Array:
	var shk := s.tone(1.0, 0.03, {"wave": "noise", "a": 0.0008, "d": 0.035, "s": 0.0, "r": 0.02,
			"hp": 2200.0, "lp": 9000.0, "vol": 0.55})
	var knock := s.tone(640.0 * pitch, 0.01, {"wave": "sine", "a": 0.0005, "d": 0.05, "s": 0.0, "r": 0.02,
			"pdrop": 5.0, "pdecay": 0.01, "vol": 0.45})
	var thunk := s.tone(130.0 * pitch, 0.02, {"wave": "sine", "a": 0.0008, "d": 0.09, "s": 0.0, "r": 0.04,
			"pdrop": 10.0, "pdecay": 0.015, "vol": 0.7})
	var out := s.concat(shk, knock, 0.004)
	out = s.concat(out, thunk, 0.0)
	if bright:
		var shing := s.tone(2637.0, 0.02, {"wave": "fm", "fm_ratio": 1.41, "fm_index": 2.0, "fm_decay": 0.08,
				"a": 0.001, "d": 0.3, "s": 0.0, "r": 0.15, "vol": 0.16})
		var shing2 := s.tone(3951.0, 0.02, {"wave": "sine", "a": 0.001, "d": 0.22, "s": 0.0, "r": 0.1, "vol": 0.08})
		out = s.concat(out, shing, 0.006)
		out = s.concat(out, shing2, 0.012)
	return out

static func _miss(s: Synth) -> PackedFloat32Array:
	var thud := _thud(s, 0.7)
	var bwoop := s.tone(420.0, 0.28, {"wave": "tri", "a": 0.004, "d": 0.1, "s": 0.7, "r": 0.08,
			"slide": -19.0, "vib": 0.4, "vib_rate": 14.0, "vib_delay": 0.0, "vol": 0.32})
	return s.concat(thud, bwoop, 0.02)

static func _thud(s: Synth, vol: float) -> PackedFloat32Array:
	var body := s.tone(95.0, 0.03, {"wave": "sine", "a": 0.001, "d": 0.12, "s": 0.0, "r": 0.05,
			"pdrop": 9.0, "pdecay": 0.02, "vol": vol})
	var dust := s.tone(1.0, 0.02, {"wave": "noise", "a": 0.001, "d": 0.04, "s": 0.0, "r": 0.02,
			"lp": 1400.0, "vol": vol * 0.4})
	Synth.mix(body, dust, 0)
	return body

static func _bin(s: Synth) -> PackedFloat32Array:
	var whoosh := _whoosh(s, 0.22)
	var clang := PackedFloat32Array()
	clang.resize(s.n_samples(0.6))
	for ratio in [1.0, 2.76, 5.4, 8.93]:
		var part := s.tone(330.0 * ratio, 0.01, {"wave": "sine", "a": 0.0008, "d": 0.45 / ratio, "s": 0.0,
				"r": 0.05, "vol": 0.18 / sqrt(ratio)})
		Synth.mix(clang, part, 0)
	return s.concat(whoosh, clang, 0.16)

static func _splat(s: Synth) -> PackedFloat32Array:
	var squish := s.tone(1.0, 0.18, {"wave": "noise", "a": 0.004, "d": 0.2, "s": 0.0, "r": 0.06,
			"lp": 700.0, "lp_env": 1600.0, "lp_decay": 0.05, "trem": 0.8, "trem_rate": 34.0, "vol": 0.9})
	var blub := s.tone(160.0, 0.12, {"wave": "sine", "a": 0.003, "d": 0.12, "s": 0.0, "r": 0.04,
			"slide": -10.0, "vol": 0.35})
	Synth.mix(squish, blub, s.n_samples(0.03))
	return squish

static func _whoosh(s: Synth, dur: float) -> PackedFloat32Array:
	return s.tone(1.0, dur, {"wave": "noise", "a": dur * 0.5, "d": dur * 0.5, "s": 0.0, "r": 0.05,
			"lp": 500.0, "lp_env": 2500.0, "lp_decay": dur, "hp": 200.0, "vol": 0.35})

# Notes strung together; optional echo (delay seconds, feedback) and a final
# held note (`last_hold`) for fanfares.
static func _arp(s: Synth, notes: Array, step: float, p: Dictionary, delay: float, fb: float,
		last_hold: float = 0.0) -> PackedFloat32Array:
	var total := step * notes.size() + last_hold + 0.4 + (delay * 4.0 if delay > 0.0 else 0.0)
	var out := s.silence(total)
	for i in notes.size():
		var dur := step
		if i == notes.size() - 1 and last_hold > 0.0:
			dur = last_hold
		var n := s.tone(Synth.midi_hz(notes[i]), dur, p)
		Synth.mix(out, n, s.n_samples(step * i))
	if delay > 0.0:
		Synth.echo(out, s.n_samples(delay), fb, 0.5)
	return _trim(out)

static func _fever(s: Synth) -> PackedFloat32Array:
	var sweep := s.tone(110.0, 0.5, {"wave": "saw", "a": 0.02, "d": 0.3, "s": 0.8, "r": 0.1,
			"slide": 24.0, "lp": 300.0, "lp_env": 0.0, "detune": 12.0, "vol": 0.22})
	# open the filter across the riser
	var chord := s.silence(1.2)
	for m in [72, 76, 79, 84]:
		var n := s.tone(Synth.midi_hz(m), 0.35, {"wave": "saw", "a": 0.005, "d": 0.2, "s": 0.5, "r": 0.3,
				"lp": 2200.0, "lp_env": 4000.0, "lp_decay": 0.12, "detune": 9.0, "vol": 0.1})
		Synth.mix(chord, n, 0)
	var out := s.concat(sweep, chord, 0.48)
	Synth.echo(out, s.n_samples(0.15), 0.3, 0.35)
	return _trim(out)

static func _victory(s: Synth) -> PackedFloat32Array:
	var lead := {"wave": "square", "duty": 0.25, "a": 0.003, "d": 0.1, "s": 0.6, "r": 0.15, "vol": 0.16,
			"vib": 0.15, "vib_delay": 0.1}
	var out := s.silence(2.4)
	var seq := [[72, 0.0, 0.12], [72, 0.15, 0.12], [72, 0.3, 0.12], [76, 0.45, 0.3], [74, 0.8, 0.12],
			[76, 0.95, 0.12], [79, 1.1, 0.7]]
	for e in seq:
		Synth.mix(out, s.tone(Synth.midi_hz(e[0]), e[2], lead), s.n_samples(e[1]))
	var bass := {"wave": "tri", "a": 0.003, "d": 0.1, "s": 0.7, "r": 0.1, "vol": 0.3}
	for e in [[48, 0.0, 0.4], [53, 0.45, 0.3], [55, 0.8, 0.25], [48, 1.1, 0.7]]:
		Synth.mix(out, s.tone(Synth.midi_hz(e[0]), e[2], bass), s.n_samples(e[1]))
	Synth.echo(out, s.n_samples(0.18), 0.25, 0.3)
	return _trim(out)

# The "wah wah wah wahhh" of a sad trombone — the only correct game over.
static func _sad_trombone(s: Synth) -> PackedFloat32Array:
	var p := {"wave": "saw", "a": 0.02, "d": 0.1, "s": 0.8, "r": 0.12, "lp": 700.0, "lp_env": 900.0,
			"lp_decay": 0.12, "poles": 2, "vol": 0.2, "vib": 0.0}
	var out := s.silence(2.6)
	var notes := [[67, 0.0, 0.32], [66, 0.4, 0.32], [65, 0.8, 0.32]]
	for e in notes:
		Synth.mix(out, s.tone(Synth.midi_hz(e[0]), e[2], p), s.n_samples(e[1]))
	var last := p.duplicate()
	last["vib"] = 0.35
	last["vib_rate"] = 6.0
	last["vib_delay"] = 0.15
	Synth.mix(out, s.tone(Synth.midi_hz(64), 0.95, last), s.n_samples(1.2))
	return _trim(out)

static func _roar(s: Synth) -> PackedFloat32Array:
	var growl := s.tone(55.0, 0.7, {"wave": "saw", "a": 0.05, "d": 0.3, "s": 0.8, "r": 0.25,
			"slide": -5.0, "lp": 500.0, "lp_env": 700.0, "lp_decay": 0.3, "trem": 0.5, "trem_rate": 23.0,
			"detune": 25.0, "sub": 0.5, "vol": 0.45})
	var breath := s.tone(1.0, 0.7, {"wave": "noise", "a": 0.08, "d": 0.4, "s": 0.4, "r": 0.2, "lp": 900.0, "vol": 0.18})
	Synth.mix(growl, breath, 0)
	return growl

static func _boss_hit(s: Synth) -> PackedFloat32Array:
	var c := _chop(s, 0.7, false)
	var crunch := s.tone(1.0, 0.08, {"wave": "noise", "a": 0.001, "d": 0.12, "s": 0.0, "r": 0.04,
			"lp": 2400.0, "trem": 0.9, "trem_rate": 60.0, "vol": 0.5})
	return s.concat(c, crunch, 0.01)

static func _explosion(s: Synth, dur: float) -> PackedFloat32Array:
	var boom := s.tone(1.0, 0.05, {"wave": "noise", "a": 0.002, "d": dur, "s": 0.0, "r": 0.2,
			"lp": 300.0, "lp_env": 3000.0, "lp_decay": 0.15, "vol": 0.95})
	var sub := s.tone(70.0, 0.05, {"wave": "sine", "a": 0.002, "d": dur * 0.6, "s": 0.0, "r": 0.1,
			"pdrop": 12.0, "pdecay": 0.05, "vol": 0.7})
	Synth.mix(boom, sub, 0)
	return boom

static func _bell_pair(s: Synth, m1: int, m2: int) -> PackedFloat32Array:
	var p := {"wave": "fm", "fm_ratio": 3.5, "fm_index": 2.2, "fm_decay": 0.25, "a": 0.001, "d": 0.7,
			"s": 0.0, "r": 0.2, "vol": 0.2}
	var out := s.silence(1.3)
	Synth.mix(out, s.tone(Synth.midi_hz(m1), 0.05, p), 0)
	Synth.mix(out, s.tone(Synth.midi_hz(m2), 0.05, p), s.n_samples(0.11))
	return _trim(out)

static func _coin(s: Synth) -> PackedFloat32Array:
	var p := {"wave": "square", "duty": 0.5, "a": 0.001, "d": 0.05, "s": 0.6, "r": 0.18, "lp": 6000.0, "vol": 0.13}
	var a := s.tone(987.77, 0.06, p)
	var b := s.tone(1318.5, 0.22, p)
	return s.concat(a, b, 0.06)

static func _cash_register(s: Synth) -> PackedFloat32Array:
	var click := s.tone(1.0, 0.01, {"wave": "noise", "a": 0.0005, "d": 0.02, "s": 0.0, "r": 0.01,
			"hp": 3000.0, "vol": 0.4})
	var ding := _bell_pair(s, 96, 100)
	return s.concat(click, ding, 0.04)

static func _scrape(s: Synth, vol: float = 1.0) -> PackedFloat32Array:
	return s.tone(1.0, 0.22, {"wave": "noise", "a": 0.02, "d": 0.2, "s": 0.2, "r": 0.06,
			"lp": 900.0, "hp": 180.0, "trem": 0.7, "trem_rate": 41.0, "vol": 0.6 * vol})

static func _splash(s: Synth) -> PackedFloat32Array:
	var out := s.tone(1.0, 0.3, {"wave": "noise", "a": 0.01, "d": 0.3, "s": 0.0, "r": 0.1,
			"lp": 1800.0, "lp_env": 3500.0, "lp_decay": 0.08, "hp": 300.0, "vol": 0.45})
	for i in 4:
		var drop := s.tone(900.0 + i * 260.0, 0.02, {"wave": "sine", "a": 0.001, "d": 0.04, "s": 0.0,
				"r": 0.02, "slide": 9.0, "vol": 0.1})
		Synth.mix(out, drop, s.n_samples(0.06 + i * 0.05))
	return out

static func _harvest(s: Synth) -> PackedFloat32Array:
	var rustle := s.tone(1.0, 0.12, {"wave": "noise", "a": 0.01, "d": 0.12, "s": 0.0, "r": 0.04,
			"hp": 1500.0, "lp": 6000.0, "vol": 0.25})
	var pop := s.tone(300.0, 0.04, {"wave": "sine", "a": 0.001, "d": 0.06, "s": 0.0, "r": 0.03,
			"slide": 12.0, "vol": 0.45})
	return s.concat(rustle, pop, 0.07)

static func _hiss(s: Synth) -> PackedFloat32Array:
	return s.tone(1.0, 0.3, {"wave": "noise", "a": 0.04, "d": 0.2, "s": 0.4, "r": 0.1,
			"hp": 4000.0, "trem": 0.6, "trem_rate": 12.0, "vol": 0.22})

static func _sprinkle(s: Synth) -> PackedFloat32Array:
	var out := s.silence(0.5)
	for i in 7:
		var g := s.hat(0.14, 0.015, 3000.0 + i * 400.0)
		Synth.mix(out, g, s.n_samples(i * 0.035 + s.rng.randf() * 0.01))
	return _trim(out)

static func _horn(s: Synth) -> PackedFloat32Array:
	var p := {"wave": "square", "duty": 0.4, "a": 0.01, "d": 0.05, "s": 0.9, "r": 0.05, "lp": 1400.0,
			"detune": 18.0, "vol": 0.2}
	var out := s.silence(0.8)
	Synth.mix(out, s.tone(349.0, 0.16, p), 0)
	Synth.mix(out, s.tone(440.0, 0.16, p), 0)
	Synth.mix(out, s.tone(349.0, 0.3, p), s.n_samples(0.22))
	Synth.mix(out, s.tone(440.0, 0.3, p), s.n_samples(0.22))
	return _trim(out)

static func _gunshot(s: Synth, pitch: float) -> PackedFloat32Array:
	var crack := s.tone(1.0, 0.02, {"wave": "noise", "a": 0.0005, "d": 0.09 / pitch, "s": 0.0, "r": 0.04,
			"lp": 2500.0 * pitch, "lp_env": 6000.0, "lp_decay": 0.02, "vol": 0.6})
	var pop := s.tone(180.0 * pitch, 0.02, {"wave": "sine", "a": 0.0005, "d": 0.07, "s": 0.0, "r": 0.03,
			"pdrop": 12.0, "pdecay": 0.012, "vol": 0.6})
	Synth.mix(crack, pop, 0)
	return crack

static func _launcher(s: Synth) -> PackedFloat32Array:
	var thump := s.tone(90.0, 0.05, {"wave": "sine", "a": 0.001, "d": 0.18, "s": 0.0, "r": 0.06,
			"pdrop": 14.0, "pdecay": 0.03, "vol": 0.7})
	return s.concat(thump, _whoosh(s, 0.25), 0.0)

# Drop trailing near-silence so short SFX don't hold a voice for nothing.
static func _trim(buf: PackedFloat32Array) -> PackedFloat32Array:
	var end := buf.size()
	while end > 1 and absf(buf[end - 1]) < 0.0005:
		end -= 1
	return buf.slice(0, mini(buf.size(), end + 64))
