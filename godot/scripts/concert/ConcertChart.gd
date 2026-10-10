extends RefCounted
class_name ConcertChart

# Concert mode's song + chart rules, kept free of scene code so they stay
# deterministic and portable: a seed always gives the same song (style,
# tempo, title, notes) and the same chart, here and in the web edition
# (web/index.html ports this file and SongComposer 1:1).
#
# A concert song is the composer's 8-bar loop played four times, arranged
# by fading stems in and out:
#   loop 0  INTRO   drums + harmony; the chart follows the kick and snare
#   loop 1  VERSE   the melody enters; the chart follows it, thinned out
#   loop 2  CHORUS  the full melody
#   loop 3  FINALE  melody + snare accents, more golden spuds
#
# Note kinds: "chop" (SPACE on the beat), "hold" (a sweet-potato ribbon —
# hold SPACE until its tail), "rotten" (press X to bin it, never chop it)
# and "golden" (a chop worth triple, plus coins).

const LOOPS := 4
const COUNT_IN := 4.0           # beats of count-in before beat 0
const DIFFICULTIES := ["easy", "normal", "hard"]

# per difficulty: note grid (steps), minimum gap between notes (steps),
# rotten rate, the shortest melody note that becomes a hold (steps), the
# belt speed (px per beat) and how hard a miss hits the crowd's hype
const RULES := {
	"easy":   {"grid": 4, "gap": 8, "rotten": 0.06, "hold_min": 8, "speed": 200.0, "miss_hype": 0.06},
	"normal": {"grid": 2, "gap": 4, "rotten": 0.1, "hold_min": 8, "speed": 240.0, "miss_hype": 0.08},
	"hard":   {"grid": 1, "gap": 2, "rotten": 0.13, "hold_min": 6, "speed": 290.0, "miss_hype": 0.1},
}

const STYLE_NAMES := {
	"funky_live": "Street Funk", "dance": "Disco Inferno", "town": "Polka Plaza", "menu": "Kitchen Groove",
	"arena": "Spud Metal", "farm": "Country Mash",
}
# tempo range per concert style
const STYLE_BPM := {
	"funky_live": [108, 122], "dance": [118, 128], "town": [112, 124], "menu": [98, 108],
	"arena": [128, 142], "farm": [92, 104],
}

# The fixed setlist: one seed per style (seed % 6 picks the style), ordered
# roughly by tempo — country, kitchen groove, polka, funk, disco, metal.
const SETLIST := [11, 3, 8, 24, 13, 40]

# Song identity from a seed: style, tempo and title.
static func spec_for_seed(seed_v: int) -> Dictionary:
	var r := SongComposer.Rng.new(seed_v ^ 0x2c1b3c6d)
	var styles: Array = SongComposer.CONCERT_STYLES
	var style: String = styles[posmod(seed_v, styles.size())]
	var rng_bpm: Array = STYLE_BPM.get(style, [110, 124])
	var bpm := float(r.range_i(int(rng_bpm[0]), int(rng_bpm[1])))
	return {"style": style, "bpm": bpm, "seed": seed_v, "title": SongComposer.song_title(seed_v),
			"style_name": STYLE_NAMES.get(style, style.capitalize())}

# Today's song: the same for every player on the same (UTC) date.
static func daily_seed() -> int:
	var d := Time.get_date_dict_from_system(true)
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])

static func section_name(beat: float, loop_beats: float) -> String:
	if beat < 0.0:
		return "COUNT-IN"
	match int(beat / loop_beats):
		0: return "INTRO"
		1: return "VERSE"
		2: return "CHORUS"
		_: return "FINALE"

# Build the chart for a composed song (SongComposer.compose output).
# Returns notes sorted by beat: {beat, kind, len (beats, holds only)}.
static func build(song: Dictionary, difficulty: String) -> Array:
	var rules: Dictionary = RULES.get(difficulty, RULES["normal"])
	var salt := DIFFICULTIES.find(difficulty) + 1
	var rng := SongComposer.Rng.new(int(song["seed"]) * 31 + salt)
	var loop_steps: int = int(song["bars"]) * SongComposer.STEPS
	var notes := []
	var last_kind := ""
	for loop_i in LOOPS:
		var grid: int = rules["grid"]
		var cands := []
		if loop_i == 0:
			for d in song["drums"]:
				if d[1] in ["kick", "snare", "clap"] and float(d[2]) >= 0.5:
					cands.append([int(d[0]), 0, "drum"])
		else:
			if loop_i == 1:
				grid = mini(grid * 2, 8)   # the verse eases you into the melody
			for l in song["lead"]:
				cands.append([int(l[0]), int(l[1]), "lead"])
			if loop_i == 3:
				for d in song["drums"]:
					if d[1] in ["snare", "clap"] and float(d[2]) >= 0.8:
						cands.append([int(d[0]), 0, "drum"])
		cands.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1]))
		var next_free := -999
		for c in cands:
			var st: int = c[0]
			if st % grid != 0 or st < next_free:
				continue
			var beat := loop_i * loop_steps / 4.0 + st / 4.0
			var kind := "chop"
			var length := 0.0
			var occupied := st
			if c[2] == "lead" and int(c[1]) >= int(rules["hold_min"]) and last_kind != "hold" \
					and rng.chance(0.7):
				kind = "hold"
				length = int(c[1]) / 4.0
				occupied = st + int(c[1])
			elif notes.size() > 2 and last_kind != "rotten" and rng.chance(rules["rotten"]):
				kind = "rotten"
			elif rng.chance(0.09 if loop_i == 3 else 0.05):
				kind = "golden"
			# a hold mustn't run past the end of its loop
			if kind == "hold" and occupied > loop_steps:
				kind = "chop"
				length = 0.0
				occupied = st
			notes.append({"beat": beat, "kind": kind, "len": length})
			last_kind = kind
			next_free = occupied + int(rules["gap"])
	return notes
