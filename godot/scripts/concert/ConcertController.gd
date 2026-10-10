extends Node2D
class_name ConcertController

# CONCERT — the rhythm mode. Pick a song (today's Daily Song, the setlist,
# or a Random Jam whose seed you can share), pick a difficulty, and chop the
# potatoes as the conveyor carries them under the knife — each one arrives
# exactly on a note of the procedurally composed song.
#
#   SPACE / left-click   chop   (hold it through a sweet-potato ribbon)
#   X / right-click      bin a rotten potato (never chop one!)
#
# Misses drain the crowd's HYPE (empty = booed off stage) and make the melody
# stumble; streaks raise the multiplier up to x4, then FEVER doubles it and
# fades a sparkle layer into the song. Songs and charts come from
# ConcertChart + SongComposer, so a seed is the same song for everyone.

enum Phase { SELECT, PLAY, DONE }

const CHOP_X := 300.0
const BELT_Y := 476.0
const POTATO_Y := 452.0
# timing windows (seconds, either side of the beat)
const WIN_PERFECT := 0.045
const WIN_GREAT := 0.09
const WIN_GOOD := 0.135
const QUALITY_POINTS := {"PERFECT": 1.0, "GREAT": 0.8, "GOOD": 0.5}
const QUALITY_HYPE := {"PERFECT": 0.03, "GREAT": 0.02, "GOOD": 0.01}

var phase: Phase = Phase.SELECT

# ── select ──
var songs: Array = []          # [{spec, label}]
var sel: int = 0
var diff_i: int = 1
var random_seed: int = 0
var _preview_at: float = 0.0
var _preview_key := ""

# ── play ──
var spec: Dictionary = {}
var difficulty := "normal"
var rules: Dictionary = {}
var notes: Array = []          # chart notes + runtime state
var next_note: int = 0         # first note not yet judged/missed
var holding = null             # the hold note currently being held
var hype: float = 0.5
var fever: bool = false
var end_beat: float = 128.0
var loop_beats: float = 32.0
var _last_count := 99
var _section := ""
var _lead_target := 0.0
var _duck_until := 0.0
var _finish_at := -1.0
var cleared := false
var popups: Array = []         # {text, color, age}
var banner := ""
var banner_age := 99.0

var bg: KitchenBackground
var knife: KnifeVisual
var pause_overlay: PauseOverlay
var font: Font

func _ready():
	font = ThemeDB.fallback_font
	bg = KitchenBackground.new()
	bg.show_board = false
	bg.show_window = false
	bg.beat_sync = true
	bg.show_pot = false
	bg.tier = 5
	add_child(bg)
	knife = KnifeVisual.new()
	knife.position = Vector2(CHOP_X, POTATO_Y)
	knife.beat_sync = true
	knife.visible = false
	add_child(knife)

	var daily := ConcertChart.daily_seed()
	songs.append({"spec": ConcertChart.spec_for_seed(daily), "label": "★ DAILY SONG"})
	for s in ConcertChart.SETLIST:
		songs.append({"spec": ConcertChart.spec_for_seed(s), "label": ""})
	random_seed = randi_range(1000, 999999)
	songs.append({"spec": ConcertChart.spec_for_seed(random_seed), "label": "RANDOM JAM"})
	_preview_at = 0.2

# ────────────────────────────────────────────────────────
#  Song select
# ────────────────────────────────────────────────────────

func _difficulty() -> String:
	return ConcertChart.DIFFICULTIES[diff_i]

func _best_key(s: Dictionary, d: String) -> String:
	return "%d:%s" % [int(s["seed"]), d]

func _select_input(event: InputEventKey):
	match event.keycode:
		KEY_UP, KEY_W:
			sel = posmod(sel - 1, songs.size())
			_preview_at = 0.35
			AudioManager.play_sfx("menu_move")
		KEY_DOWN, KEY_S:
			sel = posmod(sel + 1, songs.size())
			_preview_at = 0.35
			AudioManager.play_sfx("menu_move")
		KEY_LEFT, KEY_A:
			diff_i = posmod(diff_i - 1, 3)
			AudioManager.play_sfx("menu_move")
		KEY_RIGHT, KEY_D:
			diff_i = posmod(diff_i + 1, 3)
			AudioManager.play_sfx("menu_move")
		KEY_R:
			# reroll the random jam
			random_seed = randi_range(1000, 999999)
			songs[songs.size() - 1]["spec"] = ConcertChart.spec_for_seed(random_seed)
			sel = songs.size() - 1
			_preview_at = 0.35
			AudioManager.play_sfx("menu_select")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			start_song(songs[sel]["spec"], _difficulty())
		KEY_ESCAPE:
			AudioManager.play_sfx("menu_back")
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# Begin playing a song. Public so the smoke test can start one directly.
func start_song(s: Dictionary, diff: String):
	spec = s
	difficulty = diff
	rules = ConcertChart.RULES[diff]
	phase = Phase.PLAY
	knife.visible = true
	bg.tier = {"easy": 4, "normal": 5, "hard": 6}[diff]
	GameManager.start_game("concert")
	GameManager.current_state.lives = 1
	GameManager.current_state.song_title = str(s.get("title", "?"))
	GameManager.current_state.difficulty = diff
	AudioManager.play_sfx("menu_select")
	AudioManager.play_song(s, 0.02, ConcertChart.COUNT_IN, true)
	AudioManager.set_layer_gain("lead", 0.0, 0.01)
	_lead_target = 0.0
	loop_beats = float(AudioManager.song["loop_beats"])
	end_beat = loop_beats * ConcertChart.LOOPS
	notes = []
	for n in ConcertChart.build(AudioManager.song, diff):
		var nn: Dictionary = n.duplicate()
		nn["done"] = false
		nn["result"] = ""
		notes.append(nn)
	next_note = 0
	hype = 0.5
	fever = false
	holding = null
	_last_count = 99
	_section = ""
	_finish_at = -1.0
	cleared = false

# ────────────────────────────────────────────────────────
#  Play
# ────────────────────────────────────────────────────────

func _win_beats(sec: float) -> float:
	var widen := 1.15 if difficulty == "easy" else 1.0
	return sec * widen / AudioManager.beat_sec()

func _input(event: InputEvent):
	if phase == Phase.SELECT:
		if event is InputEventKey and event.pressed and not event.echo:
			_select_input(event)
		return
	if phase != Phase.PLAY:
		return
	if event is InputEventKey and not event.echo:
		if event.pressed and event.keycode == KEY_ESCAPE:
			_open_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			if event.pressed:
				_chop()
			else:
				_release()
		elif event.pressed and event.keycode == KEY_X:
			_bin()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_chop()
			else:
				_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_bin()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase == Phase.PLAY and pause_overlay == null \
			and DisplayServer.get_name() != "headless":
		_open_pause()

# nearest unjudged note within the GOOD window, optionally of given kinds
func _candidate(kinds: Array):
	var now := AudioManager.music_beat()
	var win := _win_beats(WIN_GOOD)
	var best = null
	var best_d := INF
	for i in range(next_note, notes.size()):
		var n: Dictionary = notes[i]
		if n["beat"] - now > win:
			break
		if n["done"] or not (n["kind"] in kinds):
			continue
		var d := absf(n["beat"] - now)
		if d <= win and d < best_d:
			best = n
			best_d = d
	return best

func _quality(n: Dictionary) -> String:
	var d := absf(n["beat"] - AudioManager.music_beat())
	if d <= _win_beats(WIN_PERFECT):
		return "PERFECT"
	if d <= _win_beats(WIN_GREAT):
		return "GREAT"
	return "GOOD"

func _chop():
	knife.chop()
	var n = _candidate(["chop", "hold", "golden", "rotten"])
	if n == null:
		AudioManager.play_sfx_varied("cut_good", 0.08, -10.0)  # chopping air: free, but quiet
		return
	if n["kind"] == "rotten":
		_judge(n, "MISS", "CHOPPED THE ROT!")
		AudioManager.play_sfx("splat")
		if SaveDataManager.settings.get("particle_effects", true):
			Fx.splat(self, Vector2(CHOP_X, POTATO_Y))
		return
	var q := _quality(n)
	_judge(n, q)
	if n["kind"] == "hold":
		holding = n
		n["holding"] = true

func _release():
	if holding == null:
		return
	var n: Dictionary = holding
	holding = null
	n["holding"] = false
	var tail: float = n["beat"] + n["len"]
	var now := AudioManager.music_beat()
	if now >= tail - _win_beats(WIN_GOOD):
		_hold_complete(n)
	else:
		# let go early: keeps the head's points, breaks the streak
		_popup("DROPPED", Color.ORANGE_RED)
		GameManager.reset_combo()
		_set_fever(false)
		n["peeled_to"] = now

func _bin():
	var n = _candidate(["rotten"])
	if n == null:
		return
	_judge(n, "PERFECT", "BINNED!")
	AudioManager.play_sfx("bin")

func _hold_complete(n: Dictionary):
	n["peeled_to"] = n["beat"] + n["len"]
	var pts := _add_points(60.0 * n["len"])
	_popup("PEELED!  +%d" % pts, Color(1.0, 0.65, 0.3))
	AudioManager.play_sfx("cut_great", -4.0)

func _multiplier() -> int:
	return 1 + mini(GameManager.current_state.combo, 30) / 10

func _add_points(base: float) -> int:
	var pts := int(base * _multiplier() * (2.0 if fever else 1.0))
	GameManager.current_state.score += pts
	GameManager.score_changed.emit(GameManager.current_state.score)
	return pts

func _judge(n: Dictionary, q: String, label: String = ""):
	n["done"] = true
	n["result"] = q
	n["judged_at"] = AudioManager.music_beat()
	GameManager.record_cut(q)
	var fx_on: bool = SaveDataManager.settings.get("particle_effects", true)
	if q == "MISS":
		GameManager.reset_combo()
		_set_fever(false)
		hype = maxf(0.0, hype - float(rules["miss_hype"]))
		_popup(label if label != "" else "MISS", Color.ORANGE_RED)
		AudioManager.play_sfx("cut_miss", -3.0)
		# the band stumbles: the melody ducks for a beat
		if _lead_target > 0.0:
			AudioManager.set_layer_gain("lead", 0.15, 0.03)
			_duck_until = AudioManager.music_beat() + 1.0
		if hype <= 0.0:
			_fail()
		return
	GameManager.add_combo()
	hype = minf(1.0, hype + float(QUALITY_HYPE[q]))
	var base: float = 100.0 * float(QUALITY_POINTS[q])
	if n["kind"] == "golden":
		base *= 3.0
		GameManager.current_state.coins_earned += 5
		AudioManager.play_sfx("coin_collect", -4.0)
		if fx_on:
			Fx.sparkle(self, Vector2(CHOP_X, POTATO_Y))
	var pts := _add_points(base)
	if n["kind"] != "rotten":
		AudioManager.play_sfx_varied("cut_great" if q == "PERFECT" else "cut_good", 0.03, -2.0)
		if fx_on:
			Fx.burst(self, Vector2(CHOP_X, POTATO_Y), _note_color(n), 10, 200.0)
	_popup(label if label != "" else "%s  +%d" % [q, pts], _quality_color(q))
	var combo: int = GameManager.current_state.combo
	if combo > 0 and combo % 10 == 0:
		AudioManager.play_sfx("combo_up")
		_popup("x%d MULTIPLIER" % _multiplier(), Color(1.0, 0.8, 0.3))
	if combo >= 30 and not fever:
		_set_fever(true)

func _set_fever(on: bool):
	if fever == on:
		return
	fever = on
	AudioManager.set_layer("fever", on, 0.3 if on else 0.8)
	if on:
		AudioManager.play_sfx("fever_start")
		_show_banner("FEVER!  x2")

func _fail():
	if phase != Phase.PLAY:
		return
	phase = Phase.DONE
	cleared = false
	_show_banner("BOOED OFF STAGE")
	AudioManager.stop_music(0.6)
	AudioManager.play_sfx("game_over")
	_finish(false)

func _process(delta):
	banner_age += delta
	for p in popups:
		p.age += delta
	popups = popups.filter(func(p): return p.age < 1.0)

	if phase == Phase.SELECT:
		_preview_at -= delta
		if _preview_at <= 0.0 and _preview_at > -1.0:
			_preview_at = -2.0
			var s: Dictionary = songs[sel]["spec"]
			if AudioManager.song_key(s) != _preview_key:
				_preview_key = AudioManager.song_key(s)
				AudioManager.play_song(s, 0.8)
		queue_redraw()
		return
	if phase == Phase.PLAY:
		_tick_play()
	queue_redraw()

func _tick_play():
	var now := AudioManager.music_beat()
	# count-in: 3, 2, 1 on the last three beats before the song
	if now < 0.0:
		var c := int(ceil(-now))
		if c != _last_count and c <= 3:
			_last_count = c
			AudioManager.play_sfx("countdown")
		return
	if _last_count != 0:
		_last_count = 0
		AudioManager.play_sfx("countdown_go", -4.0)
	# arrangement: the melody enters after the intro loop
	var sect := ConcertChart.section_name(now, loop_beats)
	if sect != _section:
		_section = sect
		_show_banner(sect)
		_lead_target = 0.0 if sect == "INTRO" else 1.0
		AudioManager.set_layer_gain("lead", _lead_target, 0.6)
	if _duck_until > 0.0 and now >= _duck_until:
		_duck_until = 0.0
		AudioManager.set_layer_gain("lead", _lead_target, 0.25)
	# notes that slid past the knife unjudged are misses
	var win := _win_beats(WIN_GOOD)
	while next_note < notes.size():
		var n: Dictionary = notes[next_note]
		if n["done"]:
			next_note += 1
			continue
		if now > n["beat"] + win:
			_judge(n, "MISS", "LET THE ROT THROUGH!" if n["kind"] == "rotten" else "MISS")
			if phase != Phase.PLAY:
				return
			next_note += 1
			continue
		break
	# a held ribbon pays out as it peels, and completes itself at its tail
	if holding != null:
		var h: Dictionary = holding
		h["peeled_to"] = now
		if now >= h["beat"] + h["len"]:
			holding = null
			h["holding"] = false
			_hold_complete(h)
	# the song is over
	if now >= end_beat and _finish_at < 0.0:
		_finish_at = now
		cleared = true
		AudioManager.stop_music(1.5)
		AudioManager.play_sfx("victory" if GameManager.current_state.miss == 0 else "level_complete")
		_show_banner("SONG CLEAR!")
		phase = Phase.DONE
		_finish(true)

func _finish(victory: bool):
	var s = GameManager.current_state
	s.last_victory = victory
	s.lives = 1 if victory else 0
	GameManager.end_game(victory)
	var grade := GameManager.grade()
	# per-song bests
	var bests: Dictionary = SaveDataManager.settings.get("concert_bests", {})
	var key := _best_key(spec, difficulty)
	if s.score > int(bests.get(key, {}).get("score", 0)):
		bests[key] = {"score": s.score, "grade": grade if victory else "-"}
		SaveDataManager.update_setting("concert_bests", bests)
	if victory:
		_award("encore")
		if int(spec["seed"]) == ConcertChart.daily_seed():
			_award("daily_chef")
		if difficulty == "hard" and grade == "S":
			_award("perfect_pitch")
		if s.miss == 0:
			_award("full_combo")
	await get_tree().create_timer(2.6).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

func _award(id: String):
	if SaveDataManager.unlock_achievement(id):
		_popup("★ " + GameData.achievement_by_id(id).get("name", id), Color(1.0, 0.85, 0.35))
		AudioManager.play_sfx("achievement")

# ────────────────────────────────────────────────────────
#  Pause
# ────────────────────────────────────────────────────────

func _open_pause():
	pause_overlay = PauseOverlay.new()
	pause_overlay.subtitle = "\"%s\" · %s" % [spec.get("title", ""), difficulty.capitalize()]
	pause_overlay.options = [
		{"id": "resume", "label": "Resume  [ESC]", "key": KEY_ESCAPE},
		{"id": "restart", "label": "Restart song  [R]", "key": KEY_R},
		{"id": "songs", "label": "Song select  [S]", "key": KEY_S},
		{"id": "quit", "label": "Quit to menu  [Q]", "key": KEY_Q},
	]
	pause_overlay.chosen.connect(_on_pause_choice)
	add_child(pause_overlay)
	if holding != null:
		_release()

func _on_pause_choice(id: String):
	var overlay := pause_overlay
	pause_overlay = null
	overlay.close()
	match id:
		"restart":
			GameManager.current_state.is_running = false
			start_song(spec, difficulty)
		"songs":
			GameManager.current_state.is_running = false
			phase = Phase.SELECT
			knife.visible = false
			_preview_key = ""
			_preview_at = 0.1
		"quit":
			GameManager.current_state.is_running = false
			AudioManager.stop_music(0.4)
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ────────────────────────────────────────────────────────
#  Feedback
# ────────────────────────────────────────────────────────

func _popup(text: String, color: Color):
	popups.append({"text": text, "color": color, "age": 0.0})
	if popups.size() > 4:
		popups.pop_front()

func _show_banner(text: String):
	banner = text
	banner_age = 0.0

func _quality_color(q: String) -> Color:
	match q:
		"PERFECT": return Color.GOLD
		"GREAT": return Color.LIGHT_GREEN
		"GOOD": return Color.WHITE
	return Color.ORANGE_RED

func _note_color(n: Dictionary) -> Color:
	match n["kind"]:
		"rotten": return Color(0.35, 0.47, 0.22)
		"golden": return Color(1.0, 0.82, 0.2)
		"hold": return Color(0.86, 0.45, 0.18)
	return Color(0.76, 0.52, 0.27)

# ────────────────────────────────────────────────────────
#  Drawing
# ────────────────────────────────────────────────────────

func _text(s: String, cx: float, y: float, size: int, col: Color):
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(font, Vector2(cx - w / 2, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw():
	if phase == Phase.SELECT:
		_draw_select()
	else:
		_draw_stage()

func _draw_select():
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.02, 0.06, 0.55))
	var bounce := MinigameBase.beat_pulse(6.0)
	_text("CONCERT", 640, 82, int(52 + bounce * 4), Color.GOLD)
	_text("Every song is composed live from its seed — chop on the notes as they reach the knife",
			640, 114, 16, Color(0.85, 0.78, 0.65))
	var panel := Rect2(140, 140, 1000, 64 + songs.size() * 50)
	GameHUD.panel_style(Color(0.12, 0.07, 0.12, 0.92)).draw(get_canvas_item(), panel)
	var y := panel.position.y + 46.0
	for i in songs.size():
		var s: Dictionary = songs[i]["spec"]
		var active := i == sel
		var r := Rect2(panel.position.x + 14, y - 32, panel.size.x - 28, 46)
		if active:
			draw_rect(r, Color(0.95, 0.7, 0.3, 0.16 + 0.05 * bounce))
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(1.0, 0.8, 0.3))
		var label: String = songs[i]["label"]
		var x := r.position.x + 22
		if label != "":
			draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.75, 0.35))
			x += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14
		draw_string(font, Vector2(x, y), "\"%s\"" % s["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, 21,
				Color.GOLD if active else Color(0.96, 0.92, 0.84))
		var meta := "%s · %d BPM" % [s["style_name"], int(s["bpm"])]
		if label.begins_with("RANDOM"):
			meta += " · seed %d" % int(s["seed"])
		draw_string(font, Vector2(r.position.x + 560, y), meta, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.68, 0.6))
		var best: Dictionary = SaveDataManager.settings.get("concert_bests", {}).get(_best_key(s, _difficulty()), {})
		if not best.is_empty():
			var bt := "%s  %d" % [best.get("grade", "-"), int(best.get("score", 0))]
			var bw := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(font, Vector2(r.end.x - 18 - bw, y), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.85, 0.4))
		y += 50.0
	# difficulty selector
	var dy := panel.end.y + 44.0
	for i in 3:
		var d: String = ConcertChart.DIFFICULTIES[i]
		var dx := 640.0 + (i - 1) * 170.0
		var on := i == diff_i
		var box := Rect2(dx - 70, dy - 28, 140, 40)
		GameHUD.panel_style(Color(0.35, 0.22, 0.08, 0.95) if on else Color(0.12, 0.08, 0.06, 0.8)).draw(get_canvas_item(), box)
		_text(d.to_upper(), dx, dy, 20, Color.GOLD if on else Color(0.7, 0.65, 0.58))
	var preview := ""
	if AudioManager.track == AudioManager.song_key(songs[sel]["spec"]) and not AudioManager.music_live() \
			and SaveDataManager.settings.get("sound_enabled", true):
		preview = "♪ composing preview…   "
	_text(preview + "↑↓ song · ←→ difficulty · ENTER play · R new random jam · ESC back", 640, 700, 15,
			Color(0.75, 0.7, 0.62))

func _draw_stage():
	var now := AudioManager.music_beat()
	var speed: float = rules.get("speed", 240.0)
	var s = GameManager.current_state
	# dim the venue, light the stage
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.03, 0.02, 0.05, 0.35))
	if fever:
		var fp := MinigameBase.beat_pulse(4.0)
		draw_rect(Rect2(0, 0, 1280, 720), Color(1.0, 0.25, 0.9, 0.05 + 0.06 * fp))

	# ── the conveyor ──
	draw_rect(Rect2(0, BELT_Y - 8, 1280, 62), Color(0.16, 0.15, 0.17))
	draw_rect(Rect2(0, BELT_Y - 8, 1280, 6), Color(0.45, 0.45, 0.5))
	draw_rect(Rect2(0, BELT_Y + 48, 1280, 6), Color(0.3, 0.3, 0.34))
	var spacing := speed / 2.0   # a slat every half beat — the belt ticks in time
	var off := fposmod(now * speed, spacing)
	var x := -off
	while x < 1280.0:
		draw_rect(Rect2(x, BELT_Y - 2, 4, 50), Color(0.24, 0.23, 0.26))
		x += spacing
	# beat lines on the belt: every bar line is brighter
	var first := ceilf(now)
	for k in 8:
		var b := first + k
		var bx := CHOP_X + (b - now) * speed
		if bx > 1280.0:
			break
		var bar := posmod(int(b), 4) == 0
		draw_line(Vector2(bx, BELT_Y - 6), Vector2(bx, BELT_Y + 46), Color(1, 1, 1, 0.16 if bar else 0.06), 2.0)

	# ── the chopping block + target ──
	draw_rect(Rect2(CHOP_X - 70, BELT_Y - 10, 140, 70), Color(0.62, 0.42, 0.24))
	draw_rect(Rect2(CHOP_X - 70, BELT_Y - 10, 140, 8), Color(0.75, 0.55, 0.32))
	var pulse := MinigameBase.beat_pulse(5.0)
	var win_px := _win_beats(WIN_GOOD) * speed
	draw_rect(Rect2(CHOP_X - win_px, BELT_Y - 30, win_px * 2.0, 4), Color(1, 1, 1, 0.12))
	draw_arc(Vector2(CHOP_X, POTATO_Y), 40.0 + pulse * 5.0, 0.0, TAU, 36, Color(1.0, 0.85, 0.35, 0.35 + 0.4 * pulse), 3.0)

	# ── notes (draw back to front) ──
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		var hx: float = CHOP_X + (float(n["beat"]) - now) * speed
		if n["kind"] == "hold":
			var tail_x: float = CHOP_X + (float(n["beat"]) + float(n["len"]) - now) * speed
			if tail_x < -40.0 or hx > 1340.0:
				continue
			_draw_hold(n, hx, tail_x, now, speed)
			continue
		if hx < -60.0 or hx > 1340.0:
			continue
		if n["done"]:
			_draw_done(n, now)
			continue
		_draw_spud(Vector2(hx, POTATO_Y), n)

	_draw_hud(now, s)

func _draw_spud(p: Vector2, n: Dictionary, scale_v: float = 1.0, alpha: float = 1.0):
	var col := _note_color(n)
	col.a = alpha
	if n["kind"] == "golden":
		draw_circle(p, 44.0 * scale_v, Color(1.0, 0.85, 0.25, 0.18 * alpha))
	draw_set_transform(p, 0.0, Vector2(scale_v, scale_v * 0.78))
	draw_circle(Vector2.ZERO, 32.0, col)
	draw_arc(Vector2.ZERO, 32.0, 0.0, TAU, 28, Color(col.darkened(0.45), alpha), 3.0)
	draw_circle(Vector2(-10, -10), 8.0, Color(1, 1, 1, 0.18 * alpha))
	for e in [Vector2(12, -6), Vector2(-6, 10), Vector2(16, 12)]:
		draw_circle(e, 3.0, Color(col.darkened(0.4), alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if n["kind"] == "rotten":
		for k in 3:
			var sx := p.x - 14.0 + k * 14.0
			draw_arc(Vector2(sx, p.y - 36.0), 6.0, PI, TAU, 8, Color(0.55, 0.75, 0.3, 0.8 * alpha), 2.0)
		draw_string(font, Vector2(p.x - 6, p.y + 7), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 1.0, 0.7, alpha))

func _draw_hold(n: Dictionary, hx: float, tail_x: float, now: float, speed: float):
	var start_x := hx
	if n.has("peeled_to"):
		start_x = maxf(hx, CHOP_X + (float(n["peeled_to"]) - now) * speed)
	if n["done"] and n["result"] == "MISS":
		start_x = hx
	if tail_x > start_x:
		var col := _note_color(n)
		if n["done"] and n["result"] == "MISS":
			col = col.darkened(0.5)
		draw_rect(Rect2(start_x, POTATO_Y - 14, tail_x - start_x, 28), col)
		draw_rect(Rect2(start_x, POTATO_Y - 14, tail_x - start_x, 6), col.lightened(0.25))
		draw_circle(Vector2(tail_x, POTATO_Y), 14.0, col)
	if not n["done"]:
		_draw_spud(Vector2(hx, POTATO_Y), n)
	elif n.get("holding", false):
		draw_circle(Vector2(CHOP_X, POTATO_Y), 18.0 + MinigameBase.beat_pulse(8.0) * 6.0, Color(1.0, 0.75, 0.35, 0.5))

# judged notes: chopped halves fly apart, binned rot drops away, misses fade
func _draw_done(n: Dictionary, now: float):
	var age := (now - float(n.get("judged_at", now))) * AudioManager.beat_sec()
	if age > 0.6:
		return
	var p := Vector2(CHOP_X, POTATO_Y)
	if n["result"] == "MISS":
		_draw_spud(p + Vector2(-age * 260.0, age * age * 900.0), n, 1.0, 1.0 - age / 0.6)
	elif n["kind"] == "rotten":
		_draw_spud(p + Vector2(age * 120.0, -age * 400.0 + age * age * 1600.0), n, 1.0 - age, 1.0 - age / 0.6)
	else:
		var sep := age * 220.0
		var drop := age * age * 700.0
		_draw_spud(p + Vector2(-sep, drop), n, 0.75, 1.0 - age / 0.6)
		_draw_spud(p + Vector2(sep, drop), n, 0.75, 1.0 - age / 0.6)

func _draw_hud(now: float, s):
	# a dark band behind the HUD so it reads over the bunting
	draw_rect(Rect2(0, 0, 1280, 86), Color(0.04, 0.02, 0.05, 0.6))
	# song + difficulty
	draw_string(font, Vector2(24, 44), "\"%s\"" % spec.get("title", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.GOLD)
	draw_string(font, Vector2(24, 70), "%s · %d BPM · %s" % [spec.get("style_name", ""), int(spec.get("bpm", 0)),
			difficulty.to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.78, 0.65))
	# score
	GameHUD.panel_style().draw(get_canvas_item(), Rect2(1040, 14, 226, 62))
	draw_string(font, Vector2(1054, 40), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.68, 0.3))
	var sc: String = "%d" % s.score
	var sw := font.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(font, Vector2(1252 - sw, 64), sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	# hype meter
	var hx := 440.0
	draw_string(font, Vector2(hx, 34), "HYPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.68, 0.3))
	draw_rect(Rect2(hx, 42, 400, 14), Color(0.1, 0.07, 0.05, 0.85))
	var hcol := Color(0.9, 0.3, 0.2).lerp(Color(0.4, 0.9, 0.35), hype)
	if hype < 0.25:
		hcol = hcol.lerp(Color.WHITE, MinigameBase.beat_pulse(4.0) * 0.5)
	draw_rect(Rect2(hx, 42, 400 * hype, 14), hcol)
	# combo + multiplier
	if s.combo > 1:
		var ct: String = "%d COMBO" % s.combo
		_text(ct, CHOP_X, 300, 22 + mini(s.combo, 30) / 3, Color(1.0, 0.82, 0.3))
		_text("x%d%s" % [_multiplier(), "  FEVER x2" if fever else ""], CHOP_X, 326, 16,
				Color(1.0, 0.5, 1.0) if fever else Color(0.95, 0.9, 0.8))
	# judgement popups rise from the knife
	for p in popups:
		var a: float = 1.0 - p.age
		var c: Color = p.color
		c.a = a
		_text(p.text, CHOP_X + 160, 380 - p.age * 50.0 - popups.find(p) * 4.0, 24, c)
	# count-in
	if now < 0.0:
		var c := int(ceil(-now))
		var txt := "READY" if c > 3 else str(c)
		_text(txt, 640, 300, 72, Color(1.0, 0.85, 0.35, 0.4 + 0.6 * MinigameBase.beat_pulse(3.0)))
		_text("SPACE chop · hold through ribbons · X bins rotten spuds", 640, 350, 18, Color(0.95, 0.9, 0.8))
	# section banner
	if banner_age < 1.4:
		var a := 1.0 if banner_age < 1.0 else (1.4 - banner_age) / 0.4
		_text(banner, 640, 220, 44, Color(1.0, 0.85, 0.35, a))
	# progress bar with section ticks
	var pw := 900.0
	var px := 640.0 - pw / 2
	draw_rect(Rect2(px, 676, pw, 8), Color(0.1, 0.07, 0.05, 0.8))
	draw_rect(Rect2(px, 676, pw * clampf(now / end_beat, 0.0, 1.0), 8), Color(0.95, 0.75, 0.3))
	for k in range(1, ConcertChart.LOOPS):
		draw_rect(Rect2(px + pw * k / ConcertChart.LOOPS - 1, 672, 2, 16), Color(1, 1, 1, 0.4))
	draw_string(font, Vector2(px, 704), _section if _section != "" else "COUNT-IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.8, 0.72, 0.6))
	draw_string(font, Vector2(px + pw - 120, 704), "[ESC] Pause", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.72, 0.6, 0.6))
