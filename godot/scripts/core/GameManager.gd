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
	# run stats for the results screen
	var perfect: int = 0
	var great: int = 0
	var good: int = 0
	var miss: int = 0
	var max_combo: int = 0
	var prev_best: int = 0      # best score in this mode before the run
	var song_title: String = "" # Concert mode: the song that was played
	var difficulty: String = "" # Concert mode: easy / normal / hard

var current_state: GameState = GameState.new()
var game_modes = {}  # Will be populated with mode configurations

func _ready():
	# Initialize game modes and load saved data
	_init_game_modes()
	SaveDataManager.load_game()
	_apply_window_icon()
	apply_fullscreen()

# F11 toggles fullscreen anywhere in the game.
func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		SaveDataManager.update_setting("fullscreen", not SaveDataManager.settings.get("fullscreen", false))
		apply_fullscreen()

func apply_fullscreen():
	if DisplayServer.get_name() == "headless":
		return
	var full: bool = SaveDataManager.settings.get("fullscreen", false)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_window_icon():
	# Use the potato as the window / taskbar icon (no-op on the headless CI
	# server, which has no window).
	if DisplayServer.get_name() == "headless":
		return
	var tex = load("res://icon.svg")
	if tex is Texture2D:
		var img: Image = tex.get_image()
		if img:
			# Window has no set_icon in Godot 4.2 — the icon lives on the
			# display server (calling it on Window raised a SCRIPT ERROR on
			# every desktop launch).
			DisplayServer.set_icon(img)

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
		},
		"concert": {
			"name": "Concert",
			"stages": 1,
			"description": "Play a procedurally composed song on the conveyor"
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
	current_state.perfect = 0
	current_state.great = 0
	current_state.good = 0
	current_state.miss = 0
	current_state.max_combo = 0
	current_state.song_title = ""
	current_state.difficulty = ""
	current_state.prev_best = best_score(mode)
	current_state.is_running = true

	game_started.emit()

func end_game(victory: bool):
	if not current_state.is_running:
		return  # already ended (e.g. a death landing on the same frame as the last cut)
	current_state.is_running = false
	# personal best per mode, kept even if the player skips the leaderboard
	var bests: Dictionary = SaveDataManager.settings.get("best_scores", {})
	if current_state.score > int(bests.get(current_state.mode, 0)):
		bests[current_state.mode] = current_state.score
		SaveDataManager.update_setting("best_scores", bests)
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
	var player_name: String = str(SaveDataManager.settings.get("player_name", "")).strip_edges()
	if player_name == "":
		player_name = "Chef"
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
	current_state.max_combo = maxi(current_state.max_combo, current_state.combo)
	combo_changed.emit(current_state.combo)

# Tally one judged cut for the results screen (MISS and FAIL count as misses).
func record_cut(quality: String):
	match quality:
		"PERFECT": current_state.perfect += 1
		"GREAT": current_state.great += 1
		"GOOD": current_state.good += 1
		_: current_state.miss += 1

func cuts_judged() -> int:
	var s := current_state
	return s.perfect + s.great + s.good + s.miss

# Weighted accuracy 0..1: PERFECT 100%, GREAT 70%, GOOD 40%, MISS 0%.
func accuracy() -> float:
	var n := cuts_judged()
	if n == 0:
		return 0.0
	var s := current_state
	return (s.perfect * 1.0 + s.great * 0.7 + s.good * 0.4) / float(n)

# Letter grade for the run: accuracy first, with S reserved for no misses.
func grade() -> String:
	var acc := accuracy()
	if cuts_judged() == 0:
		return "D"
	if acc >= 0.95 and current_state.miss == 0:
		return "S"
	if acc >= 0.85:
		return "A"
	if acc >= 0.7:
		return "B"
	if acc >= 0.5:
		return "C"
	return "D"

# Best score so far in a mode (0 if none): the saved personal best, or the
# local leaderboard for saves that predate it.
func best_score(mode: String) -> int:
	var best := int(SaveDataManager.settings.get("best_scores", {}).get(mode, 0))
	for e in SaveDataManager.leaderboard:
		if e.get("mode", "") == mode:
			best = maxi(best, int(e.get("score", 0)))
	return best

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

	# process_always=false: FEVER doesn't drain while the game is paused
	await get_tree().create_timer(duration, false).timeout
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
