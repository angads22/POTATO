extends RefCounted
class_name SongComposer

# Procedural music: composes and renders a looping song from a style and a
# seed. Nothing is sampled — drums, bass, chords and melody are all generated
# here, then synthesized by Synth into four stereo stems:
#
#   drums    the groove (always on)
#   harmony  bass + chords (always on)
#   lead     the melody (Concert mode drops it on a miss)
#   fever    a 16th-note sparkle arpeggio, faded in during FEVER
#
# Composition is plain music theory: a key and mode, a 4-chord progression
# played twice over 8 bars, style-specific drum/bass/chord patterns, and a
# melody built from 2-bar rhythmic motifs (A A' B A'') whose strong beats are
# snapped to chord tones so it always sits on the harmony.
#
# compose() is deterministic for a (style, seed, bpm) and cheap; render() is
# the expensive synthesis step and runs on a worker thread (AudioManager).
# The note events compose() returns also drive Concert mode's charts — the
# web edition ports this file 1:1 (same PRNG) so a seed is the same song on
# every platform.

const RATE := 32000
const STEPS := 16  # sixteenth notes per bar
const BARS := 8

const SCALES := {
	"major": [0, 2, 4, 5, 7, 9, 11],
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"harmonic": [0, 2, 3, 5, 7, 8, 11],
}

# ── drum patterns: 16 steps, values are velocities ──
# "half" grooves put the snare on beat 3 (step 8): the kitchen's cut cursor
# crosses the centre exactly there, so every PERFECT lands on the snare.
const DRUMS := {
	"half": {
		"kick":  [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, .8, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
		"hat":   [.7, 0, .4, 0, .6, 0, .4, 0, .7, 0, .4, 0, .6, 0, .4, .3],
	},
	"half_funk": {
		"kick":  [1, 0, 0, .5, 0, 0, 0, 0, 0, 0, .9, 0, 0, .6, 0, 0],
		"snare": [0, 0, 0, 0, 0, 0, 0, .25, 1, 0, 0, 0, 0, .25, 0, 0],
		"hat":   [.7, .25, .45, .25, .6, .25, .45, .25, .7, .25, .45, .25, .6, .25, .45, .3],
	},
	"half_disco": {
		"kick":  [1, 0, 0, 0, .8, 0, 0, 0, 1, 0, 0, 0, .8, 0, 0, 0],
		"clap":  [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
		"ohat":  [0, 0, .6, 0, 0, 0, .6, 0, 0, 0, .6, 0, 0, 0, .6, 0],
		"shaker": [.5, .3, .5, .3, .5, .3, .5, .3, .5, .3, .5, .3, .5, .3, .5, .3],
	},
	"half_epic": {
		"kick":  [1, 0, 0, 0, 0, 0, .7, 0, 0, 0, .9, 0, 0, 0, .6, 0],
		"snare": [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
		"hat":   [.6, 0, .5, 0, .6, 0, .5, 0, .6, 0, .5, 0, .6, 0, .5, 0],
		"tom":   [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, .5, .6, .7],
	},
	"half_soft": {
		"kick":  [.8, 0, 0, 0, 0, 0, 0, 0, 0, 0, .6, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, 0, 0, 0, 0, .7, 0, 0, 0, 0, 0, 0, 0],
		"rim":   [0, 0, 0, 0, 0, 0, 0, .3, 0, 0, 0, 0, 0, 0, .4, 0],
		"shaker": [.5, .2, .4, .2, .5, .2, .4, .2, .5, .2, .4, .2, .5, .2, .4, .2],
	},
	"funk": {
		"kick":  [1, 0, 0, 0, 0, 0, 0, .6, 0, 0, .9, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, .3],
		"hat":   [.6, .2, .4, .2, .6, .2, .4, .2, .6, .2, .4, .2, .6, .2, .4, .2],
	},
	"four": {
		"kick":  [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
		"clap":  [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
		"ohat":  [0, 0, .7, 0, 0, 0, .7, 0, 0, 0, .7, 0, 0, 0, .7, 0],
		"hat":   [.3, .2, 0, .2, .3, .2, 0, .2, .3, .2, 0, .2, .3, .2, 0, .2],
	},
	"drive": {
		"kick":  [1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0],
		"snare": [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0],
		"hat":   [.7, .3, .5, .3, .7, .3, .5, .3, .7, .3, .5, .3, .7, .3, .5, .3],
	},
	"gentle": {
		"kick":  [.6, 0, 0, 0, 0, 0, 0, 0, .45, 0, 0, 0, 0, 0, 0, 0],
		"rim":   [0, 0, 0, 0, .5, 0, 0, 0, 0, 0, 0, 0, .5, 0, 0, .25],
		"shaker": [.4, .15, .3, .15, .4, .15, .3, .15, .4, .15, .3, .15, .4, .15, .3, .15],
	},
	"oompah": {
		"kick":  [1, 0, 0, 0, 0, 0, 0, 0, .9, 0, 0, 0, 0, 0, 0, 0],
		"snare": [0, 0, 0, 0, .45, 0, 0, 0, 0, 0, 0, 0, .45, 0, 0, 0],
		"hat":   [0, 0, .35, 0, 0, 0, .35, 0, 0, 0, .35, 0, 0, 0, .35, 0],
	},
}

# ── bass patterns: [step, length, tone] — tone 0 root, 1 third, 2 fifth,
#    3 octave, 4 seventh, 5 approach (step toward next bar's root), 6 low fifth
const BASS := {
	"half": [[0, 6, 0], [10, 2, 0], [12, 2, 2], [14, 2, 3]],
	"funk": [[0, 3, 0], [3, 1, 0], [6, 2, 3], [10, 2, 2], [12, 1, 0], [14, 2, 5]],
	"octave": [[0, 2, 0], [2, 2, 3], [4, 2, 0], [6, 2, 3], [8, 2, 0], [10, 2, 3], [12, 2, 0], [14, 2, 3]],
	"root8": [[0, 2, 0], [2, 2, 0], [4, 2, 0], [6, 2, 0], [8, 2, 0], [10, 2, 0], [12, 2, 2], [14, 2, 3]],
	"walk": [[0, 4, 0], [4, 4, 1], [8, 4, 2], [12, 4, 5]],
	"sparse": [[0, 7, 0], [8, 6, 6], [14, 2, 5]],
	"oompah": [[0, 3, 0], [8, 3, 6]],
	"epic": [[0, 8, 0], [8, 4, 0], [12, 4, 6]],
}

# ── chord comping: [step, length] stabs; "pad" holds the bar; "arp" 8ths ──
const COMP := {
	"stab24": [[4, 2], [12, 2]],
	"offbeat": [[2, 1], [6, 1], [10, 1], [14, 1]],
	"push": [[0, 3], [3, 3], [10, 2], [14, 2]],
	"lofi": [[0, 6], [6, 10]],
	"pad": [[0, 16]],
	"oompah": [[4, 2], [12, 2]],
	"strum": [[0, 3], [6, 2], [8, 3], [12, 2], [14, 2]],
}

# ── 2-bar melody rhythms: [step, length] over 32 steps ──
const RHYTHMS := {
	"low": [
		[[0, 6], [8, 4], [12, 4], [16, 8], [24, 8]],
		[[0, 4], [4, 4], [8, 8], [16, 4], [20, 4], [24, 8]],
		[[2, 2], [4, 4], [8, 8], [18, 2], [20, 4], [24, 8]],
		[[0, 8], [10, 2], [12, 4], [16, 6], [22, 2], [24, 8]],
	],
	"mid": [
		[[0, 3], [3, 3], [6, 2], [8, 4], [12, 2], [14, 2], [16, 3], [19, 3], [22, 2], [24, 8]],
		[[0, 2], [2, 2], [4, 4], [8, 2], [10, 2], [12, 4], [16, 2], [18, 2], [20, 4], [24, 6], [30, 2]],
		[[0, 4], [6, 2], [8, 2], [10, 2], [12, 4], [16, 4], [22, 2], [24, 4], [28, 4]],
		[[2, 2], [4, 2], [6, 4], [10, 2], [12, 4], [18, 2], [20, 2], [22, 2], [24, 8]],
	],
	"high": [
		[[0, 2], [2, 2], [4, 1], [5, 1], [6, 2], [8, 2], [10, 2], [12, 2], [14, 2], [16, 2], [18, 1], [19, 1], [20, 2], [22, 2], [24, 4], [28, 2], [30, 2]],
		[[0, 1], [1, 1], [2, 2], [4, 2], [6, 2], [8, 3], [11, 1], [12, 4], [16, 1], [17, 1], [18, 2], [20, 2], [22, 2], [24, 6], [30, 2]],
		[[0, 2], [2, 1], [3, 1], [4, 2], [6, 2], [8, 2], [10, 2], [12, 4], [16, 2], [18, 2], [20, 1], [21, 1], [22, 2], [24, 8]],
	],
}

# ── instruments (Synth.tone parameter sets) ──
const INST := {
	"bass_round": {"wave": "tri", "sub": 0.35, "a": 0.004, "d": 0.18, "s": 0.65, "r": 0.06, "lp": 1100.0, "vol": 0.6},
	"bass_funk": {"wave": "saw", "a": 0.003, "d": 0.12, "s": 0.5, "r": 0.05, "lp": 380.0, "lp_env": 1800.0,
			"lp_decay": 0.07, "poles": 2, "sub": 0.3, "vol": 0.55},
	"bass_disco": {"wave": "square", "duty": 0.5, "a": 0.003, "d": 0.09, "s": 0.55, "r": 0.04, "lp": 600.0,
			"lp_env": 1200.0, "lp_decay": 0.05, "poles": 2, "vol": 0.5},
	"bass_tuba": {"wave": "square", "duty": 0.45, "a": 0.02, "d": 0.15, "s": 0.6, "r": 0.06, "lp": 500.0,
			"poles": 2, "sub": 0.4, "vol": 0.55},
	"bass_synth": {"wave": "saw", "detune": 9.0, "a": 0.004, "d": 0.2, "s": 0.7, "r": 0.08, "lp": 500.0,
			"lp_env": 900.0, "lp_decay": 0.12, "poles": 2, "sub": 0.45, "vol": 0.5},
	"ep": {"wave": "fm", "fm_ratio": 1.0, "fm_index": 1.3, "fm_decay": 0.25, "a": 0.003, "d": 0.7, "s": 0.25,
			"r": 0.25, "vol": 0.32},
	"ep_soft": {"wave": "fm", "fm_ratio": 1.0, "fm_index": 0.8, "fm_decay": 0.4, "a": 0.01, "d": 1.0, "s": 0.3,
			"r": 0.4, "trem": 0.15, "trem_rate": 4.5, "vol": 0.3},
	"pluck": {"wave": "square", "duty": 0.3, "a": 0.002, "d": 0.22, "s": 0.0, "r": 0.05, "lp": 700.0,
			"lp_env": 3000.0, "lp_decay": 0.04, "vol": 0.3},
	"uke": {"wave": "tri", "a": 0.002, "d": 0.35, "s": 0.0, "r": 0.06, "lp": 2400.0, "lp_env": 2500.0,
			"lp_decay": 0.03, "noise": 0.02, "vol": 0.34},
	"brass": {"wave": "saw", "detune": 10.0, "a": 0.02, "d": 0.15, "s": 0.6, "r": 0.08, "lp": 900.0,
			"lp_env": 2200.0, "lp_decay": 0.08, "poles": 2, "vol": 0.24},
	"pad": {"wave": "saw", "detune": 14.0, "a": 0.25, "d": 0.4, "s": 0.75, "r": 0.5, "lp": 900.0,
			"vol": 0.16},
	"accordion": {"wave": "saw", "detune": 16.0, "a": 0.03, "d": 0.1, "s": 0.8, "r": 0.06, "lp": 2200.0,
			"trem": 0.18, "trem_rate": 6.0, "vol": 0.18},
	"organ": {"wave": "tri", "detune": 6.0, "sub": 0.25, "a": 0.01, "d": 0.05, "s": 0.9, "r": 0.06,
			"trem": 0.12, "trem_rate": 6.5, "vol": 0.24},
	"lead_square": {"wave": "square", "duty": 0.25, "a": 0.005, "d": 0.12, "s": 0.65, "r": 0.08, "lp": 3800.0,
			"vib": 0.14, "vib_rate": 5.5, "vib_delay": 0.16, "vol": 0.24},
	"lead_soft": {"wave": "square", "duty": 0.5, "a": 0.008, "d": 0.15, "s": 0.55, "r": 0.1, "lp": 1800.0,
			"vib": 0.12, "vib_delay": 0.2, "vol": 0.24},
	"flute": {"wave": "sine", "noise": 0.03, "a": 0.035, "d": 0.1, "s": 0.8, "r": 0.1, "lp": 5000.0,
			"vib": 0.18, "vib_rate": 5.0, "vib_delay": 0.15, "vol": 0.34},
	"whistle": {"wave": "sine", "a": 0.02, "d": 0.08, "s": 0.85, "r": 0.08, "vib": 0.22, "vib_rate": 5.8,
			"vib_delay": 0.08, "vol": 0.3},
	"marimba": {"wave": "fm", "fm_ratio": 4.0, "fm_index": 1.6, "fm_decay": 0.05, "a": 0.002, "d": 0.4,
			"s": 0.0, "r": 0.1, "vol": 0.34},
	"lead_saw": {"wave": "saw", "detune": 8.0, "a": 0.01, "d": 0.15, "s": 0.7, "r": 0.1, "lp": 2600.0,
			"poles": 2, "vib": 0.15, "vib_delay": 0.18, "vol": 0.22},
	"bell": {"wave": "fm", "fm_ratio": 3.5, "fm_index": 1.8, "fm_decay": 0.1, "a": 0.001, "d": 0.25,
			"s": 0.0, "r": 0.08, "vol": 0.2},
	"sparkle": {"wave": "square", "duty": 0.125, "a": 0.002, "d": 0.08, "s": 0.0, "r": 0.04, "lp": 5000.0,
			"vol": 0.16},
}

# ── styles: everything that makes a song sound like a place ──
#   half=true marks grooves whose backbeat is beat 3 (kitchen / boss songs)
const STYLES := {
	"menu": {"scales": ["dorian", "mixolydian"], "root": [55, 60], "drums": "funk", "bass": "funk",
			"bass_inst": "bass_funk", "comp": "push", "comp_inst": "ep", "lead": "marimba", "density": "low",
			"progs": [[0, 3, 0, 3], [0, 3, 6, 4], [0, 5, 3, 4]], "sevenths": true, "lead_echo": 0.3},
	"lofi": {"scales": ["major"], "root": [55, 62], "drums": "half_soft", "bass": "half",
			"bass_inst": "bass_round", "comp": "lofi", "comp_inst": "ep_soft", "lead": "lead_soft",
			"density": "low", "progs": [[3, 2, 1, 0], [0, 5, 3, 4], [1, 4, 0, 5]], "sevenths": true,
			"lead_echo": 0.35, "half": true},
	"jazz": {"scales": ["major"], "root": [53, 58], "drums": "half", "bass": "walk", "bass_inst": "bass_round",
			"comp": "stab24", "comp_inst": "ep", "lead": "flute", "density": "mid",
			"progs": [[1, 4, 0, 5], [0, 5, 1, 4], [2, 5, 1, 4]], "sevenths": true, "lead_echo": 0.2, "half": true},
	"funky": {"scales": ["mixolydian", "dorian"], "root": [52, 57], "drums": "half_funk", "bass": "funk",
			"bass_inst": "bass_funk", "comp": "offbeat", "comp_inst": "pluck", "lead": "lead_square",
			"density": "mid", "progs": [[0, 3, 0, 4], [0, 6, 3, 0], [0, 3, 6, 3]], "sevenths": true,
			"lead_echo": 0.25, "half": true},
	"disco": {"scales": ["dorian", "minor"], "root": [52, 57], "drums": "half_disco", "bass": "octave",
			"bass_inst": "bass_disco", "comp": "pad", "comp_inst": "pad", "lead": "lead_square", "density": "mid",
			"progs": [[0, 5, 3, 4], [0, 3, 4, 3], [0, 6, 5, 6]], "sevenths": false, "lead_echo": 0.3,
			"half": true, "arp": true},
	"gameshow": {"scales": ["major"], "root": [55, 60], "drums": "half_funk", "bass": "root8",
			"bass_inst": "bass_disco", "comp": "push", "comp_inst": "brass", "lead": "lead_square",
			"density": "high", "progs": [[0, 3, 4, 0], [0, 5, 3, 4], [0, 4, 5, 3]], "sevenths": false,
			"lead_echo": 0.2, "half": true},
	"epic": {"scales": ["minor", "harmonic"], "root": [50, 55], "drums": "half_epic", "bass": "epic",
			"bass_inst": "bass_synth", "comp": "pad", "comp_inst": "pad", "lead": "lead_saw", "density": "mid",
			"progs": [[0, 5, 2, 6], [0, 3, 6, 5], [0, 5, 3, 4]], "sevenths": false, "lead_echo": 0.35,
			"half": true, "arp": true},
	"boss": {"scales": ["harmonic", "minor"], "root": [48, 53], "drums": "half_epic", "bass": "octave",
			"bass_inst": "bass_synth", "comp": "push", "comp_inst": "brass", "lead": "lead_saw", "density": "high",
			"progs": [[0, 5, 4, 4], [0, 6, 5, 4], [0, 3, 4, 0]], "sevenths": false, "lead_echo": 0.25,
			"half": true, "arp": true},
	"farm": {"scales": ["major"], "root": [57, 62], "drums": "gentle", "bass": "sparse",
			"bass_inst": "bass_round", "comp": "strum", "comp_inst": "uke", "lead": "whistle", "density": "low",
			"progs": [[0, 3, 0, 4], [0, 5, 3, 4], [3, 4, 0, 0]], "sevenths": false, "lead_echo": 0.25},
	"town": {"scales": ["major"], "root": [55, 60], "drums": "oompah", "bass": "oompah",
			"bass_inst": "bass_tuba", "comp": "oompah", "comp_inst": "accordion", "lead": "accordion_lead",
			"density": "high", "progs": [[0, 4, 4, 0], [0, 3, 4, 0], [0, 0, 4, 4]], "sevenths": false,
			"lead_echo": 0.0},
	"arena": {"scales": ["minor", "dorian"], "root": [50, 55], "drums": "drive", "bass": "root8",
			"bass_inst": "bass_synth", "comp": "pad", "comp_inst": "pad", "lead": "lead_saw", "density": "mid",
			"progs": [[0, 5, 6, 4], [0, 6, 5, 6], [0, 3, 5, 4]], "sevenths": false, "lead_echo": 0.3, "arp": true},
	"results": {"scales": ["major"], "root": [55, 60], "drums": "half_soft", "bass": "half",
			"bass_inst": "bass_round", "comp": "lofi", "comp_inst": "ep_soft", "lead": "marimba", "density": "low",
			"progs": [[0, 5, 3, 4], [3, 4, 0, 0]], "sevenths": true, "lead_echo": 0.35},
	"dance": {"scales": ["minor", "dorian"], "root": [52, 57], "drums": "four", "bass": "octave",
			"bass_inst": "bass_disco", "comp": "offbeat", "comp_inst": "organ", "lead": "lead_square",
			"density": "mid", "progs": [[0, 5, 3, 4], [0, 6, 5, 6], [0, 3, 4, 3]], "sevenths": false,
			"lead_echo": 0.3, "arp": true},
}

# Concert-mode song pool (normal backbeat grooves)
const CONCERT_STYLES := ["funky_live", "dance", "town", "menu", "arena", "farm"]

# ── song titles ──
const TITLE_A := ["Hash Brown", "Mashed", "Tater Tot", "Spudnik", "Chip Shop", "Golden Fry", "Wedge",
		"Gratin", "Rosti", "Jacket", "Starchy", "Peel-Good", "Couch Potato", "Hot Potato", "Russet",
		"Fingerling", "Sweet Potato", "Duchess", "Croquette", "Latke"]
const TITLE_B := ["Hustle", "Boogie", "Shuffle", "Tango", "Groove", "Stomp", "Serenade", "Funk",
		"Waltz", "Breakdown", "Fever", "Jam", "Strut", "Express", "Anthem", "Bounce", "Blues", "Fiesta"]

# ────────────────────────────────────────────────────────
#  Deterministic PRNG (xorshift32) — identical in the web edition, so a seed
#  composes the same song in Godot and in the browser.
# ────────────────────────────────────────────────────────
class Rng:
	var s: int
	func _init(seed_v: int):
		# scramble the seed (integer hash) so neighbouring seeds diverge
		var x := seed_v & 0xFFFFFFFF
		x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
		x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
		x = (x >> 16) ^ x
		s = x
		if s == 0:
			s = 0x9E3779B9
		for i in 4:
			next_u32()
	func next_u32() -> int:
		var x := s
		x ^= (x << 13) & 0xFFFFFFFF
		x ^= x >> 17
		x ^= (x << 5) & 0xFFFFFFFF
		s = x & 0xFFFFFFFF
		return s
	func randf() -> float:
		return float(next_u32()) / 4294967296.0
	func range_i(lo: int, hi: int) -> int:  # inclusive
		return lo + int(randf() * float(hi - lo + 1))
	func pick(arr: Array):
		return arr[int(randf() * arr.size())]
	func chance(p: float) -> bool:
		return randf() < p

static func song_title(seed_v: int) -> String:
	var r := Rng.new(seed_v ^ 0x5bd1e995)
	return "%s %s" % [r.pick(TITLE_A), r.pick(TITLE_B)]

# ────────────────────────────────────────────────────────
#  Composition
# ────────────────────────────────────────────────────────
#
# Returns the song as data:
#   bpm, bars, loop_beats, root, scale, title, style
#   chords   per bar: Array of midi notes
#   drums    Array of [step_abs, kind, velocity]  (step_abs = bar*16 + step)
#   bass     Array of [step_abs, len_steps, midi]
#   comp     Array of [step_abs, len_steps, Array(midi)]
#   arp      Array of [step_abs, len_steps, midi]   (pad styles' 8th-note arpeggio)
#   lead     Array of [step_abs, len_steps, midi]
#   fever    Array of [step_abs, len_steps, midi]
static func compose(style_id: String, seed_v: int, bpm: float) -> Dictionary:
	var st: Dictionary = _style(style_id)
	var rng := Rng.new(seed_v)
	var scale: Array = SCALES[rng.pick(st["scales"])]
	var root: int = rng.range_i(st["root"][0], st["root"][1])
	var prog: Array = rng.pick(st["progs"])
	var sevenths: bool = st.get("sevenths", false)

	var song := {
		"style": style_id, "seed": seed_v, "bpm": bpm, "bars": BARS, "loop_beats": BARS * 4,
		"root": root, "scale": scale, "title": song_title(seed_v),
		"chords": [], "chord_degs": [], "drums": [], "bass": [], "comp": [], "arp": [], "lead": [], "fever": [],
		"half": st.get("half", false),
	}

	# chord per bar (the 4-chord progression, twice)
	for bar in BARS:
		var deg: int = prog[bar % 4]
		song["chord_degs"].append(deg)
		var tones := [deg, deg + 2, deg + 4]
		if sevenths:
			tones.append(deg + 6)
		var midis := []
		for t in tones:
			midis.append(_deg_midi(root, scale, t))
		song["chords"].append(midis)

	_compose_drums(song, st, rng)
	_compose_bass(song, st, rng, scale, root)
	_compose_comp(song, st, rng)
	_compose_lead(song, st, rng, scale, root)
	_compose_fever(song, st, scale, root)
	return song

static func _style(style_id: String) -> Dictionary:
	if style_id == "funky_live":
		# the funky kitchen groove with a normal 2-and-4 backbeat for Concert
		var s: Dictionary = STYLES["funky"].duplicate(true)
		s["drums"] = "funk"
		s["half"] = false
		return s
	return STYLES.get(style_id, STYLES["menu"])

static func _deg_midi(root: int, scale: Array, deg: int) -> int:
	var oct := floori(deg / 7.0)
	var idx := posmod(deg, 7)
	return root + 12 * oct + int(scale[idx])

static func _compose_drums(song: Dictionary, st: Dictionary, rng: Rng):
	var pat: Dictionary = DRUMS[st["drums"]]
	for bar in BARS:
		for kind in pat:
			var row: Array = pat[kind]
			for step in STEPS:
				var v: float = row[step]
				if kind == "tom" and bar % 4 != 3:
					continue  # tom fills only at phrase ends
				if v > 0.0:
					# a touch of velocity humanisation on the hats
					if kind in ["hat", "shaker"]:
						v *= 0.85 + 0.3 * rng.randf()
					song["drums"].append([bar * STEPS + step, kind, v])
		# fill into the loop point: a snare roll over the last beat
		if bar == BARS - 1 and pat.has("snare") and not st.get("half", false):
			for k in [13, 14, 15]:
				song["drums"].append([bar * STEPS + k, "snare", 0.35 + 0.15 * (k - 13)])
		if bar == BARS - 1 and st.get("half", false):
			for k in [12, 14]:
				song["drums"].append([bar * STEPS + k, "snare" if pat.has("snare") else "clap", 0.4])

static func _compose_bass(song: Dictionary, st: Dictionary, rng: Rng, scale: Array, root: int):
	var pat: Array = BASS[st["bass"]]
	var degs: Array = song["chord_degs"]
	for bar in BARS:
		var d: int = degs[bar]
		var next_d: int = degs[(bar + 1) % BARS]
		for e in pat:
			var tone_kind: int = e[2]
			var deg := d
			match tone_kind:
				1: deg = d + 2
				2: deg = d + 4
				3: deg = d + 7
				4: deg = d + 6
				5: deg = next_d + (1 if rng.chance(0.5) else -1)
				6: deg = d - 3
			# bass lives an octave or two under the key root
			var m := _deg_midi(root - 24, scale, deg)
			while m < 28:
				m += 12
			while m > 52:
				m -= 12
			song["bass"].append([bar * STEPS + int(e[0]), int(e[1]), m])

static func _compose_comp(song: Dictionary, st: Dictionary, rng: Rng):
	var pat: Array = COMP[st["comp"]]
	for bar in BARS:
		var chord: Array = song["chords"][bar]
		# voice the chord into a comfortable middle register
		var voiced := []
		for m in chord:
			var v: int = m
			while v < 55:
				v += 12
			while v > 76:
				v -= 12
			voiced.append(v)
		voiced.sort()
		for e in pat:
			song["comp"].append([bar * STEPS + int(e[0]), int(e[1]), voiced])
		if st.get("arp", false):
			# 8th-note arpeggio an octave up, adds motion under pads
			for k in 8:
				var m: int = voiced[k % voiced.size()] + 12
				song["arp"].append([bar * STEPS + k * 2, 2, m])

static func _compose_lead(song: Dictionary, st: Dictionary, rng: Rng, scale: Array, root: int):
	var density: String = st.get("density", "mid")
	var pool: Array = RHYTHMS[density]
	var rhythm_a: Array = _mutate_rhythm(rng.pick(pool), rng)
	var rhythm_b: Array = _mutate_rhythm(rng.pick(pool), rng)
	# centre the tune near midi ~74 whatever the key (a tonic degree, so the
	# final resolution lands home), well clear of the pads below it
	var center := 7
	while _deg_midi(root, scale, center) < 69:
		center += 7
	while _deg_midi(root, scale, center) > 80:
		center -= 7
	var contours := ["arch", "rise", "fall", "valley"]
	var ca: String = rng.pick(contours)
	var cb: String = rng.pick(contours)
	while cb == ca:
		cb = rng.pick(contours)
	var amp_a := rng.range_i(3, 5)
	var amp_b := rng.range_i(3, 6)

	# A (bars 1-2): the motif
	var a_degs := _phrase_degrees(rng, rhythm_a, ca, center, amp_a, song, 0)
	# A' (bars 3-4): same motif over the next chords, new tail
	var a2_degs := []
	for i in a_degs.size():
		a2_degs.append(_resnap(a_degs[i], rhythm_a[i], song, 2))
	var tail := _phrase_degrees(rng, rhythm_a, "fall", center + 1, amp_a, song, 2)
	for i in range(maxi(0, a2_degs.size() - 3), a2_degs.size()):
		a2_degs[i] = tail[i]
	# B (bars 5-6): contrasting rhythm and contour, a little higher
	var b_degs := _phrase_degrees(rng, rhythm_b, cb, center + 2, amp_b, song, 4)
	# A'' (bars 7-8): the motif returns and resolves to the tonic
	var a3_degs := []
	for i in a_degs.size():
		a3_degs.append(_resnap(a_degs[i], rhythm_a[i], song, 6))
	a3_degs[a3_degs.size() - 1] = center

	for ph in [[rhythm_a, a_degs, 0], [rhythm_a, a2_degs, 2], [rhythm_b, b_degs, 4], [rhythm_a, a3_degs, 6]]:
		var rhythm: Array = ph[0]
		var degs: Array = ph[1]
		var bar0: int = ph[2]
		for i in rhythm.size():
			song["lead"].append([bar0 * STEPS + int(rhythm[i][0]), int(rhythm[i][1]),
					_deg_midi(root, scale, int(degs[i]))])

# Melodic shape across a 2-bar phrase, x in 0..1 -> -1..1
static func _shape(contour: String, x: float) -> float:
	match contour:
		"arch": return sin(PI * x) * 1.6 - 0.6
		"rise": return x * 2.0 - 1.0
		"fall": return 1.0 - x * 2.0
		"valley": return 0.6 - sin(PI * x) * 1.6
	return 0.0

# Scale degrees for one phrase: strong notes (downbeats, long notes) land on
# the chord tone nearest the contour; the notes between walk toward it by
# step, with the odd neighbour tone or repeat, so lines sing instead of jump.
static func _phrase_degrees(rng: Rng, rhythm: Array, contour: String, center: int, amp: int,
		song: Dictionary, bar0: int) -> Array:
	var out := []
	var prev := center
	for i in rhythm.size():
		var step: int = rhythm[i][0]
		var ln: int = rhythm[i][1]
		var target := float(center) + amp * _shape(contour, float(step) / 32.0)
		var cd: int = song["chord_degs"][bar0 + step / STEPS]
		var strong := step % 8 == 0 or ln >= 4
		var deg := prev
		if strong or i == 0:
			deg = _nearest_chord_tone(int(round(target)), cd)
		else:
			var dir := signi(int(round(target)) - prev)
			if dir == 0:
				dir = 1 if rng.chance(0.5) else -1
			var r := rng.randf()
			if r < 0.62:
				deg = prev + dir
			elif r < 0.82:
				deg = prev + 2 * dir
			elif r < 0.92:
				deg = prev - dir
			else:
				deg = prev
		deg = clampi(deg, center - 6, center + 8)
		prev = deg
		out.append(deg)
	return out

# Re-harmonise a reused motif note over the chord of a later phrase.
static func _resnap(deg: int, note: Array, song: Dictionary, bar0: int) -> int:
	var step: int = note[0]
	var strong := step % 8 == 0 or int(note[1]) >= 4
	if not strong:
		return deg
	return _nearest_chord_tone(deg, song["chord_degs"][bar0 + step / STEPS])

static func _mutate_rhythm(base: Array, rng: Rng) -> Array:
	var out := []
	for e in base:
		out.append([int(e[0]), int(e[1])])
	# occasionally split a long note, or merge a short pair, for variety
	var i := 0
	while i < out.size():
		var ln: int = out[i][1]
		if ln >= 4 and rng.chance(0.18):
			var half := ln / 2
			out[i][1] = half
			out.insert(i + 1, [out[i][0] + half, ln - half])
			i += 2
			continue
		if ln <= 2 and i + 1 < out.size() and rng.chance(0.1) and out[i][0] % 4 == 0:
			out[i][1] = ln + int(out[i + 1][1])
			out.remove_at(i + 1)
		i += 1
	return out

static func _nearest_chord_tone(deg: int, chord_deg: int) -> int:
	var best := deg
	var best_d := 99
	for oct in [-14, -7, 0, 7, 14]:
		for t in [0, 2, 4]:
			var c: int = chord_deg + t + oct
			var dd := absi(c - deg)
			if dd < best_d:
				best_d = dd
				best = c
	return best

static func _compose_fever(song: Dictionary, st: Dictionary, scale: Array, root: int):
	# a 16th-note sparkle: chord tones up two octaves, rising then falling
	var shape := [0, 1, 2, 3, 2, 1, 2, 3]
	for bar in BARS:
		var cd: int = song["chord_degs"][bar]
		var tones := [cd + 14, cd + 16, cd + 18, cd + 21]
		for k in STEPS:
			var deg: int = tones[shape[k % shape.size()]]
			song["fever"].append([bar * STEPS + k, 1, _deg_midi(root, scale, deg)])

# ────────────────────────────────────────────────────────
#  Rendering (worker thread)
# ────────────────────────────────────────────────────────
#
# Returns {"stems": {name: AudioStreamWAV}, "loop_sec": float, "song": Dictionary}
static func render(song: Dictionary) -> Dictionary:
	var st: Dictionary = _style(song["style"])
	var synth := Synth.new(RATE, int(song["seed"]) & 0x7FFFFFFF)
	var bpm: float = song["bpm"]
	var step_sec := 60.0 / bpm / 4.0
	var frames := int(round(BARS * STEPS * step_sec * RATE))
	var step_samples := float(frames) / float(BARS * STEPS)

	var stems := {}
	for name in ["drums", "harmony", "lead", "fever"]:
		var l := PackedFloat32Array()
		l.resize(frames)
		l.fill(0.0)
		var r := l.duplicate()
		stems[name] = [l, r]

	# ── drums: render each voice once, then place copies ──
	var kit := {
		"kick": synth.kick(0.9),
		"snare": synth.snare(0.55, 190.0, 0.12),
		"hat": synth.hat(0.22),
		"ohat": synth.hat(0.2, 0.16, 6500.0),
		"clap": synth.clap(0.55),
		"shaker": synth.shaker(0.2),
		"rim": synth.rim(0.35),
		"tom": synth.tom(0.55, 110.0),
	}
	var drum_pan := {"kick": 0.0, "snare": 0.05, "hat": 0.35, "ohat": 0.4, "clap": -0.05,
			"shaker": -0.35, "rim": -0.2, "tom": -0.15}
	for e in song["drums"]:
		var kind: String = e[1]
		var start := int(round(int(e[0]) * step_samples))
		Synth.mix_pan(stems["drums"][0], stems["drums"][1], kit[kind], start, float(e[2]), drum_pan.get(kind, 0.0))

	var cache := {}
	# ── bass ──
	var bass_inst: Dictionary = INST[st["bass_inst"]]
	for e in song["bass"]:
		var buf := _note(synth, cache, st["bass_inst"], bass_inst, int(e[2]), int(e[1]) * step_sec * 0.92)
		Synth.mix_pan(stems["harmony"][0], stems["harmony"][1], buf, int(round(int(e[0]) * step_samples)), 1.0, 0.0)
	# ── chords (strummed slightly, spread across the stereo field) ──
	var comp_name: String = st["comp_inst"]
	var comp_inst: Dictionary = INST[comp_name]
	var strum := 0.012 if comp_name in ["uke", "pluck"] else 0.0
	for e in song["comp"]:
		var chord: Array = e[2]
		var dur := int(e[1]) * step_sec * 0.95
		for k in chord.size():
			var buf := _note(synth, cache, comp_name, comp_inst, int(chord[k]), dur)
			var pan := -0.45 + 0.9 * float(k) / maxf(1.0, chord.size() - 1.0)
			var start := int(round(int(e[0]) * step_samples + k * strum * RATE))
			Synth.mix_pan(stems["harmony"][0], stems["harmony"][1], buf, start, 0.8 / sqrt(chord.size()), pan)
	# ── lead ──
	var lead_name: String = st["lead"]
	var lead_inst: Dictionary = _lead_inst(lead_name)
	var legato := 0.6 if lead_name == "marimba" else 0.9
	for e in song["lead"]:
		var buf := _note(synth, cache, lead_name, lead_inst, int(e[2]), int(e[1]) * step_sec * legato)
		Synth.mix_pan(stems["lead"][0], stems["lead"][1], buf, int(round(int(e[0]) * step_samples)), 1.0, 0.1)
	var lead_echo: float = st.get("lead_echo", 0.0)
	if lead_echo > 0.0:
		var d := int(round(step_samples * 3.0))  # dotted-8th delay
		Synth.echo(stems["lead"][0], d, lead_echo, 0.35, true)
		Synth.echo(stems["lead"][1], d + int(RATE * 0.011), lead_echo, 0.35, true)
	# ── arpeggio under pads (part of the always-on harmony) ──
	for e in song["arp"]:
		var buf := _note(synth, cache, "bell", INST["bell"], int(e[2]), int(e[1]) * step_sec)
		Synth.mix_pan(stems["harmony"][0], stems["harmony"][1], buf, int(round(int(e[0]) * step_samples)), 0.55, -0.25)
	# ── fever sparkle (ping-pong across the field) ──
	var fever_inst: Dictionary = INST["sparkle"]
	var flip := 1.0
	for e in song["fever"]:
		var buf := _note(synth, cache, "fever", fever_inst, int(e[2]), int(e[1]) * step_sec)
		Synth.mix_pan(stems["fever"][0], stems["fever"][1], buf, int(round(int(e[0]) * step_samples)), 1.0, 0.5 * flip)
		flip = -flip
	Synth.echo(stems["fever"][0], int(round(step_samples * 3.0)), 0.3, 0.3, true)
	Synth.echo(stems["fever"][1], int(round(step_samples * 3.0)) + int(RATE * 0.009), 0.3, 0.3, true)

	# ── level each stem to a fixed loudness, then encode ──
	var targets := {"drums": 0.092, "harmony": 0.068, "lead": 0.062, "fever": 0.04}
	var out := {}
	for name in stems:
		var l: PackedFloat32Array = stems[name][0]
		var r: PackedFloat32Array = stems[name][1]
		out[name] = synth.to_wav(l, r, true, _level_gain(l, r, targets[name]))
	return {"stems": out, "loop_sec": float(frames) / RATE, "song": song}

static func _lead_inst(name: String) -> Dictionary:
	if name == "accordion_lead":
		var d: Dictionary = INST["accordion"].duplicate()
		d["vol"] = 0.26
		d["vib"] = 0.1
		return d
	return INST.get(name, INST["lead_square"])

# Notes repeat constantly in a loop (same chord, same bass note) — render
# each (instrument, pitch, length) once and reuse the buffer.
static func _note(synth: Synth, cache: Dictionary, inst_name: String, inst: Dictionary, midi: int,
		dur: float) -> PackedFloat32Array:
	var key := "%s|%d|%d" % [inst_name, midi, int(dur * 1000.0)]
	if cache.has(key):
		return cache[key]
	var buf := synth.tone(Synth.midi_hz(midi), dur, inst)
	cache[key] = buf
	return buf

# Gain that brings a stereo stem to `target_rms` (measured on a stride —
# plenty accurate for a whole loop) without letting peaks pass 0.95.
static func _level_gain(l: PackedFloat32Array, r: PackedFloat32Array, target_rms: float) -> float:
	var acc := 0.0
	var pk := 0.0
	var n := l.size()
	var cnt := 0
	var i := 0
	while i < n:
		var a := l[i]
		var b := r[i]
		acc += a * a + b * b
		pk = maxf(pk, maxf(absf(a), absf(b)))
		cnt += 2
		i += 3
	var rms := sqrt(acc / maxf(1.0, cnt))
	if rms < 0.000001:
		return 1.0
	return minf(target_rms / rms, 0.95 / maxf(pk, 0.0001))
