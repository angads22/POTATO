extends Node

# Headless smoke test: starts a championship run and auto-plays it by
# watching the active minigame — cutting when the cursor is centred,
# locking the peel inside the band, and binning rotten potatoes.
#
#   godot --headless res://tests/SmokeTest.tscn --quit-after 900
#
# Exits 0 with a SMOKE OK line if cuts scored and no unexpected lives were
# lost; exits 1 otherwise.

var frames := 0
var gameplay

func _ready():
	GameManager.start_game("championship")
	GameManager.current_state.lives = 99
	gameplay = load("res://scenes/Gameplay/GameplayScene.tscn").instantiate()
	add_child(gameplay)

func _process(_delta):
	frames += 1
	var mg = gameplay.current_minigame
	if mg and mg.is_active:
		_play(mg)

	if frames == 850:
		var s = GameManager.current_state
		if s.score > 0 and s.lives >= 97:
			print("SMOKE OK — score=%d lives=%d stage=%d combo=%d" % [s.score, s.lives, s.stage, s.combo])
			get_tree().quit(0)
		else:
			print("SMOKE FAIL — score=%d lives=%d stage=%d combo=%d" % [s.score, s.lives, s.stage, s.combo])
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
		if absf(mg.cursor - 0.5) < 0.02:
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
