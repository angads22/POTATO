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
	var mode: String  # "championship" or "endless"
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
	var last_xp_gain: int = 0  # chef XP earned by the last run
	var ranked_up: bool = false  # did that XP cross into a new chef rank?

var current_state: GameState = GameState.new()
var game_modes = {}  # Will be populated with mode configurations

func _ready():
	# Initialize game modes and load saved data
	_init_game_modes()
	SaveDataManager.load_game()
	_apply_window_icon()

func _apply_window_icon():
	# Use the potato as the window / taskbar icon (no-op on the headless CI
	# server, which has no window).
	if DisplayServer.get_name() == "headless":
		return
	var tex = load("res://icon.svg")
	if tex is Texture2D:
		var img: Image = tex.get_image()
		if img:
			get_window().set_icon(img)

func _init_game_modes():
	game_modes = {
		"championship": {
			"name": "Championship",
			"stages": 6,
			"has_boss": true,
			"description": "6-stage campaign: stage-clear bonuses, a life back every other stage"
		},
		"endless": {
			"name": "Endless",
			"stages": -1,  # infinite
			"boss_every": 5,
			"description": "Infinite waves with rising stakes and golden odds"
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
	current_state.last_xp_gain = 0
	current_state.ranked_up = false
	current_state.is_running = true

	game_started.emit()

func end_game(victory: bool):
	current_state.is_running = false
	current_state.last_payout = current_state.coins_earned + current_state.score / 20
	if current_state.last_payout > 0:
		SaveDataManager.add_coins(current_state.last_payout)
	# Chef XP from the run feeds the career rank ladder.
	current_state.last_xp_gain = current_state.score / 100
	current_state.ranked_up = SaveDataManager.add_career_xp(current_state.last_xp_gain)
	# End-of-run achievements
	if victory and current_state.mode == "championship":
		SaveDataManager.unlock_achievement("champion")
	if current_state.score >= 10000:
		SaveDataManager.unlock_achievement("five_figures")
	# "Field Research" turns championship scores into research points
	var champ_rp = int(current_state.score * SaveDataManager.research_bonus("champ_rp_per"))
	if champ_rp > 0:
		SaveDataManager.add_research_points(champ_rp)
	# Submit to global leaderboard (no-op when Supabase isn't configured)
	var knife_id: String = SaveDataManager.farm.get("equipped_knife", "butter")
	var player_name: String = SaveDataManager.settings.get("player_name", "Chef")
	OnlineLeaderboard.submit_score(player_name, current_state.score, current_state.mode, knife_id)
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

# Difficulty ramp: minigame cursors sweep faster the deeper you climb. Stage 1
# is exactly 1.0 so the early stages (all the smoke test reaches) are unchanged;
# capped so the late stages stay humanly playable.
func difficulty_scale() -> float:
	return minf(1.5, 1.0 + (current_state.stage - 1) * 0.08)

func pause_game():
	current_state.is_paused = true
	get_tree().paused = true

func resume_game():
	current_state.is_paused = false
	get_tree().paused = false
