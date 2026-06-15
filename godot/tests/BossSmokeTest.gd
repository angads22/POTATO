extends Node

# Headless smoke test for the championship boss. Boots a championship run,
# jumps straight to the Colossal Spud, and auto-plays it by tapping SPACE when
# the cursor is centred until the boss falls. Prints BOSS SMOKE OK and exits 0
# once end_game reports victory; exits 1 if the boss isn't down in time.
#
#   godot --headless res://tests/BossSmokeTest.tscn --quit-after 600

var frames := 0
var gameplay
var started := false
var won := false

func _ready():
	GameManager.start_game("championship")
	GameManager.current_state.stage = 6
	GameManager.current_state.lives = 99
	GameManager.game_ended.connect(func(_score, victory): won = victory)
	gameplay = load("res://scenes/Gameplay/GameplayScene.tscn").instantiate()
	add_child(gameplay)

func _process(_delta):
	frames += 1

	# let the scene build its HUD/knife/kitchen, then drop into the boss fight
	if not started and frames > 5:
		started = true
		gameplay._spawn_boss()

	var mg = gameplay.current_minigame
	if started and mg is BossMinigame and mg.is_active:
		if absf(mg.cursor - 0.5) < 0.02:
			_tap(KEY_SPACE)

	if started and won:
		print("BOSS SMOKE OK — boss defeated, lives=%d score=%d" % [
			GameManager.current_state.lives, GameManager.current_state.score])
		get_tree().quit(0)

	if frames >= 560:
		print("BOSS SMOKE FAIL — defeated=%s lives=%d" % [won, GameManager.current_state.lives])
		get_tree().quit(1)

func _tap(key: Key):
	var down = InputEventKey.new()
	down.keycode = key
	down.pressed = true
	get_tree().root.push_input(down)
	var up = InputEventKey.new()
	up.keycode = key
	up.pressed = false
	get_tree().root.push_input(up)
