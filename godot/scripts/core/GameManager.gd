extends Node

# Game state management and orchestration
# Handles game modes, stage progression, lives, score tracking

signal game_started
signal game_ended(final_score: int, victory: bool)
signal stage_changed(stage_number: int)
signal lives_changed(lives_remaining: int)
signal score_changed(new_score: int)
signal combo_changed(combo_count: int)
signal fever_activated
signal fever_deactivated

class GameState:
	var mode: String  # "championship", "endless", "time_attack", "daily_challenge"
	var stage: int = 1
	var lives: int = 3
	var score: int = 0
	var combo: int = 0
	var fever_active: bool = false
	var fever_multiplier: float = 1.0
	var coins_earned: int = 0
	var is_running: bool = false
	var is_paused: bool = false
	var last_victory: bool = false
	var last_payout: int = 0  # coins banked to the farm wallet by the last run

var current_state: GameState = GameState.new()
var game_modes = {}  # Will be populated with mode configurations

func _ready():
	# Initialize game modes and load saved data
	_init_game_modes()
	SaveDataManager.load_game()

func _init_game_modes():
	game_modes = {
		"championship": {
			"name": "Championship",
			"stages": 6,
			"has_boss": true,
			"description": "6-stage campaign to become champion"
		},
		"endless": {
			"name": "Endless",
			"stages": -1,  # infinite
			"boss_every": 5,
			"description": "Infinite potatoes, ever faster"
		},
		"time_attack": {
			"name": "Time Attack",
			"duration": 60,
			"description": "Score as much as you can in 60 seconds"
		},
		"daily_challenge": {
			"name": "Daily Challenge",
			"seed_based": true,
			"description": "Same challenge for everyone today"
		}
	}

func start_game(mode: String):
	current_state.mode = mode
	current_state.stage = 1
	current_state.lives = 3
	current_state.score = 0
	current_state.combo = 0
	current_state.coins_earned = 0
	current_state.fever_active = false
	current_state.fever_multiplier = 1.0
	current_state.last_payout = 0
	current_state.is_running = true

	game_started.emit()

func end_game(victory: bool):
	current_state.is_running = false
	# Bank the run into the farm wallet: golden-potato coins plus a cut of
	# the score. Abandoning a run via ESC skips end_game and pays nothing.
	current_state.last_payout = current_state.coins_earned + current_state.score / 20
	if current_state.last_payout > 0:
		SaveDataManager.add_coins(current_state.last_payout)
	game_ended.emit(current_state.score, victory)

func add_score(amount: int, cut_quality: String = "NORMAL"):
	var multiplier = 1.0

	# Combo multiplier
	multiplier *= (1.0 + (current_state.combo * 0.1))

	# Fever multiplier
	if current_state.fever_active:
		multiplier *= current_state.fever_multiplier

	# Equipped knife damage (bought with farm coins at the knife stand)
	multiplier *= SaveDataManager.equipped_knife().get("damage", 1.0)

	# Quick-cut bonus (25% for GOOD+ cuts under 1.5s)
	if cut_quality in ["GOOD", "GREAT", "PERFECT"]:
		multiplier *= 1.25

	var final_score = int(amount * multiplier)
	current_state.score += final_score
	score_changed.emit(current_state.score)

	return final_score

func add_combo():
	current_state.combo += 1
	combo_changed.emit(current_state.combo)

func reset_combo():
	current_state.combo = 0
	combo_changed.emit(0)

func lose_life():
	if current_state.lives > 0:
		current_state.lives -= 1
		lives_changed.emit(current_state.lives)

		if current_state.lives == 0:
			end_game(false)

func activate_fever(duration: float = 8.0, multiplier: float = 2.0):
	current_state.fever_active = true
	current_state.fever_multiplier = multiplier
	fever_activated.emit()

	await get_tree().create_timer(duration).timeout
	current_state.fever_active = false
	fever_deactivated.emit()

func progress_stage():
	current_state.stage += 1
	stage_changed.emit(current_state.stage)

func pause_game():
	current_state.is_paused = true
	get_tree().paused = true

func resume_game():
	current_state.is_paused = false
	get_tree().paused = false
