extends Node

# Headless smoke test: starts a championship run and auto-plays it by
# watching the active minigame — cutting when the cursor is centred,
# locking the peel inside the band, and binning rotten potatoes.
#
#   godot --headless res://tests/SmokeTest.tscn --quit-after 4000
#
# The kitchen runs on the (silent, headless) beat clock, sped up 3x so the
# test plays through two whole stages in seconds. Passes with SMOKE OK once
# the run has cleared stages 1 and 2 and hit FEVER (combo 20) with no lives
# lost to the auto-player; exits 1 otherwise (or after a 25 s budget).

const TIME_SCALE = 3.0
const BUDGET_MS = 25000

var gameplay
var t0 := 0
var saw_fever := false
var max_combo := 0

func _ready():
	AudioManager.debug_time_scale = TIME_SCALE
	GameManager.start_game("championship")
	GameManager.current_state.lives = 99
	gameplay = load("res://scenes/Gameplay/GameplayScene.tscn").instantiate()
	add_child(gameplay)
	t0 = Time.get_ticks_msec()

func _process(_delta):
	var mg = gameplay.current_minigame
	if mg and is_instance_valid(mg) and mg.is_active:
		_play(mg)

	var s = GameManager.current_state
	saw_fever = saw_fever or s.fever_active
	max_combo = maxi(max_combo, s.combo)
	var stats := "score=%d lives=%d stage=%d max_combo=%d cuts=%d fever=%s bpm=%.1f" % [
		s.score, s.lives, s.stage, max_combo, GameManager.cuts_judged(), saw_fever, AudioManager.bpm]

	if s.lives < 99 or not s.is_running:
		print("SMOKE FAIL (auto-player lost a life) — " + stats)
		get_tree().quit(1)
	elif s.stage >= 2 and saw_fever:
		# combo 20 (FEVER) arrives early in stage 3, after two stage clears
		if s.score > 0 and GameManager.cuts_judged() >= 20:
			print("SMOKE OK — " + stats)
			get_tree().quit(0)
		else:
			print("SMOKE FAIL — " + stats)
			get_tree().quit(1)
	elif Time.get_ticks_msec() - t0 > BUDGET_MS:
		print("SMOKE FAIL (timeout) — " + stats)
		get_tree().quit(1)

func _play(mg):
	if mg is DodgeMinigame:
		_tap(KEY_X)
	elif mg is PeelMinigame:
		if not mg.started:
			_tap(KEY_SPACE)
		elif absf(mg.fill - mg.band_centre) < 0.02:
			_tap(KEY_SPACE)
	elif "cursor" in mg:  # slice / speed cut / julienne
		if mg.landed() and absf(mg.cursor - 0.5) < 0.02:
			_tap(KEY_SPACE)

func _tap(key: Key):
	# push_input routes through the viewport even on the headless server,
	# where Input.parse_input_event events never reach _input handlers
	var down = InputEventKey.new()
	down.keycode = key
	down.pressed = true
	get_tree().root.push_input(down)
	var up = InputEventKey.new()
	up.keycode = key
	up.pressed = false
	get_tree().root.push_input(up)
