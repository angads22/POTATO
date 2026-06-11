extends Node2D
class_name GameplayController

# Main gameplay orchestrator
# Manages potato spawning, minigame flow, UI updates, and game progression

var current_minigame: MinigameBase
var potato_queue: Array[Dictionary] = []
var current_potato_index: int = 0
var stage_potatoes: Array[Dictionary] = []

func _ready():
	GameManager.game_started.connect(_on_game_started)
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.lives_changed.connect(_on_lives_changed)
	GameManager.combo_changed.connect(_on_combo_changed)

	_load_stage_potatoes()
	_spawn_next_potato()

func _load_stage_potatoes():
	# Load potato sequence for current stage/mode
	# For now, create a simple test sequence
	stage_potatoes = [
		{"type": "russet", "mechanic": "slice", "base_points": 100},
		{"type": "yukon_gold", "mechanic": "slice", "base_points": 120},
		{"type": "purple", "mechanic": "peel", "base_points": 150},
		{"type": "fingerling", "mechanic": "speed_cut", "base_points": 180},
		{"type": "king_edward", "mechanic": "julienne", "base_points": 200},
		{"type": "rotten", "mechanic": "dodge", "base_points": 0},
	]

func _spawn_next_potato():
	if current_potato_index >= stage_potatoes.size():
		_complete_stage()
		return

	var potato = stage_potatoes[current_potato_index]
	current_potato_index += 1

	# Instantiate appropriate minigame based on mechanic
	_create_minigame(potato)

func _create_minigame(potato: Dictionary):
	# Remove previous minigame
	if current_minigame:
		current_minigame.queue_free()

	# Create appropriate minigame based on potato mechanic
	match potato["mechanic"]:
		"slice":
			current_minigame = SliceMinigame.new()
		"peel":
			current_minigame = PeelMinigame.new()
		"speed_cut":
			current_minigame = SpeedCutMinigame.new()
		"julienne":
			current_minigame = JulienneMinigame.new()
		"dodge":
			current_minigame = DodgeMinigame.new()

	add_child(current_minigame)
	current_minigame.minigame_completed.connect(_on_minigame_completed)
	current_minigame.start_minigame(potato)

func _on_minigame_completed(result: Dictionary):
	var quality = result["quality"]
	var multiplier = result["multiplier"]
	var current_potato = stage_potatoes[current_potato_index - 1]

	# Handle rotten potato (dodge minigame)
	if current_potato["mechanic"] == "dodge":
		if quality == "PERFECT":  # Successfully dodged
			GameManager.add_combo()
		else:  # Hit the rotten potato
			GameManager.lose_life()
			GameManager.reset_combo()

	else:
		# Normal potato scoring
		if quality == "MISS" or quality == "FAIL":
			GameManager.lose_life()
			GameManager.reset_combo()
		else:
			var base_points = current_potato["base_points"]
			var points = GameManager.add_score(base_points, quality)
			GameManager.add_combo()

			# Golden potato (7% chance) - 500 points + 15 coins
			if randf() < 0.07:
				GameManager.add_score(500, "GOLDEN")

	# Check for combo milestone (20+ for fever)
	if GameManager.current_state.combo >= 20:
		GameManager.activate_fever()

	await get_tree().create_timer(1.0).timeout
	_spawn_next_potato()

func _complete_stage():
	if GameManager.current_state.mode == "championship":
		if GameManager.current_state.stage >= 6:
			# Boss fight or victory
			GameManager.end_game(true)
		else:
			GameManager.progress_stage()
	else:
		GameManager.end_game(true)

func _on_game_started():
	print("Game started: %s" % GameManager.current_state.mode)

func _on_score_changed(new_score: int):
	queue_redraw()

func _on_lives_changed(lives: int):
	queue_redraw()

func _on_combo_changed(combo: int):
	queue_redraw()

func _draw():
	# Draw HUD: lives, score, combo, stage info
	var ui_color = Color.WHITE

	# Draw lives
	draw_string(get_theme_font("default"), Vector2(20, 30), "Lives: %d" % GameManager.current_state.lives, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ui_color)

	# Draw score
	draw_string(get_theme_font("default"), Vector2(1280 - 300, 30), "Score: %d" % GameManager.current_state.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ui_color)

	# Draw combo
	if GameManager.current_state.combo > 0:
		draw_string(get_theme_font("default"), Vector2(640 - 100, 30), "Combo: x%d" % GameManager.current_state.combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ui_color)

	# Draw stage/mode info
	draw_string(get_theme_font("default"), Vector2(20, 70), "Stage %d" % GameManager.current_state.stage, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ui_color)
