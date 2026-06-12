extends Node2D
class_name GameplayController

# Main gameplay orchestrator: builds each stage's potato sequence from the
# data tables, runs the matching minigame, and draws the HUD, quality
# popups, stage banners, fever overlay and screen shake on top.

const POTATO_POS = Vector2(640, 330)
const POPUP_LIFE = 1.2

var current_minigame: MinigameBase
var stage_potatoes: Array[Dictionary] = []
var current_potato_index: int = 0
var potato_visual: PotatoVisual
var rng := RandomNumberGenerator.new()

# feedback state
var popups: Array = []           # {text, color, age}
var banner_text: String = ""
var banner_age: float = 99.0
var shake: float = 0.0
var time_left: float = 0.0       # time-attack countdown

func _ready():
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.score_changed.connect(func(_s): queue_redraw())
	GameManager.lives_changed.connect(func(_l): queue_redraw())
	GameManager.combo_changed.connect(func(_c): queue_redraw())

	# Daily challenge plays the same sequence for everyone on a given day
	if GameManager.current_state.mode == "daily_challenge":
		var d = Time.get_date_dict_from_system()
		rng.seed = hash("%04d-%02d-%02d" % [d.year, d.month, d.day])
	else:
		rng.randomize()

	if GameManager.current_state.mode == "time_attack":
		time_left = GameManager.game_modes["time_attack"]["duration"]

	potato_visual = PotatoVisual.new()
	potato_visual.position = POTATO_POS
	add_child(potato_visual)

	_show_banner("STAGE %d" % GameManager.current_state.stage)
	_load_stage_potatoes()
	_spawn_next_potato()

func _input(event: InputEvent):
	# ESC abandons the run and returns to the menu
	if event.is_action_pressed("ui_cancel"):
		GameManager.current_state.is_running = false
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _process(delta):
	# screen shake decay — shaking this node moves the whole playfield
	if shake > 0.0:
		shake = maxf(0.0, shake - 40.0 * delta)
		position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		position = Vector2.ZERO

	banner_age += delta
	for p in popups:
		p.age += delta
	popups = popups.filter(func(p): return p.age < POPUP_LIFE)

	if GameManager.current_state.mode == "time_attack" and GameManager.current_state.is_running:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			GameManager.end_game(true)

	queue_redraw()

# ────────────────────────────────────────────────────────
#  Stage construction and potato flow
# ────────────────────────────────────────────────────────

func _load_stage_potatoes():
	# Sequence comes from the data tables; length scales with the stage.
	# Every 4th slot is a rotten hazard, and any normal slot can roll golden.
	stage_potatoes.clear()
	var pool = GameData.standard_potatoes()
	var rotten = GameData.potato_by_id("rotten")
	var golden = GameData.potato_by_id("golden")
	var count = 6 + GameManager.current_state.stage * 2

	for i in range(count):
		if i > 0 and i % 4 == 0 and not rotten.is_empty():
			stage_potatoes.append(rotten.duplicate())
		elif not golden.is_empty() and rng.randf() < golden.get("chance", 0.07):
			stage_potatoes.append(golden.duplicate())
		else:
			stage_potatoes.append(pool[rng.randi() % pool.size()].duplicate())
	current_potato_index = 0

func _spawn_next_potato():
	if not GameManager.current_state.is_running:
		return
	if current_potato_index >= stage_potatoes.size():
		_complete_stage()
		return

	var potato = stage_potatoes[current_potato_index]
	current_potato_index += 1
	potato_visual.setup(potato)
	_create_minigame(potato)

func _create_minigame(potato: Dictionary):
	if current_minigame:
		current_minigame.queue_free()

	match potato.get("mechanic", "slice"):
		"peel":
			current_minigame = PeelMinigame.new()
		"speed_cut":
			current_minigame = SpeedCutMinigame.new()
		"julienne":
			current_minigame = JulienneMinigame.new()
		"dodge":
			current_minigame = DodgeMinigame.new()
		_:
			current_minigame = SliceMinigame.new()

	add_child(current_minigame)
	current_minigame.minigame_completed.connect(_on_minigame_completed)
	current_minigame.start_minigame(potato)

func _on_minigame_completed(result: Dictionary):
	var quality: String = result["quality"]
	var potato = stage_potatoes[current_potato_index - 1]

	if potato.get("rotten", false):
		if quality == "PERFECT":
			potato_visual.bin()
			GameManager.add_combo()
			_popup("BINNED!", Color.LIGHT_GREEN)
			AudioManager.play_sfx("cut_great")
		else:
			potato_visual.split()
			GameManager.lose_life()
			GameManager.reset_combo()
			_popup("ROTTEN!  -1 LIFE", Color.ORANGE_RED)
			shake = 14.0
			AudioManager.play_sfx("cut_miss")
	elif quality == "MISS" or quality == "FAIL":
		GameManager.lose_life()
		GameManager.reset_combo()
		_popup("MISS", Color.ORANGE_RED)
		shake = 10.0
		AudioManager.play_sfx("cut_miss")
	else:
		potato_visual.split()
		var base = int(potato.get("base_points", 100) * result["multiplier"])
		var points = GameManager.add_score(base, quality)
		GameManager.add_combo()
		_popup("%s  +%d" % [quality, points], _quality_color(quality))
		AudioManager.play_sfx("cut_great" if quality == "PERFECT" else "cut_good")
		if potato.get("rare", false):
			var coins = int(potato.get("coin_bonus", 15))
			GameManager.current_state.coins_earned += coins
			_popup("GOLDEN!  +%d coins" % coins, Color.GOLD)

	if GameManager.current_state.combo >= 20 and not GameManager.current_state.fever_active:
		GameManager.activate_fever()
		_popup("FEVER!", Color.MAGENTA)
		AudioManager.play_sfx("fever_start")

	await get_tree().create_timer(1.0).timeout
	if GameManager.current_state.is_running:
		_spawn_next_potato()

func _complete_stage():
	var s = GameManager.current_state
	match s.mode:
		"championship":
			if s.stage >= 6:
				GameManager.end_game(true)
			else:
				GameManager.progress_stage()
				AudioManager.play_sfx("level_complete")
				_show_banner("STAGE %d" % s.stage)
				_load_stage_potatoes()
				_spawn_next_potato()
		"endless":
			GameManager.progress_stage()
			_show_banner("WAVE %d" % s.stage)
			_load_stage_potatoes()
			_spawn_next_potato()
		"time_attack":
			# keep the potatoes coming until the clock runs out
			_load_stage_potatoes()
			_spawn_next_potato()
		_:
			GameManager.end_game(true)

func _on_game_ended(_final_score: int, victory: bool):
	GameManager.current_state.last_victory = victory
	_show_banner("VICTORY!" if victory else "GAME OVER")
	AudioManager.play_sfx("level_complete" if victory else "game_over")
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

# ────────────────────────────────────────────────────────
#  Feedback helpers
# ────────────────────────────────────────────────────────

func _popup(text: String, color: Color):
	popups.append({"text": text, "color": color, "age": 0.0})

func _show_banner(text: String):
	banner_text = text
	banner_age = 0.0

func _quality_color(quality: String) -> Color:
	match quality:
		"PERFECT":
			return Color.GOLD
		"GREAT":
			return Color.LIGHT_GREEN
		"GOOD":
			return Color.WHITE
		_:
			return Color.ORANGE_RED

# ────────────────────────────────────────────────────────
#  HUD
# ────────────────────────────────────────────────────────

func _draw():
	var font = ThemeDB.fallback_font
	var s = GameManager.current_state

	# fever overlay
	if s.fever_active:
		draw_rect(Rect2(0, 0, 1280, 720), Color(1.0, 0.2, 1.0, 0.06))
		var fever = "FEVER x%.0f" % s.fever_multiplier
		var fs = font.get_string_size(fever, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
		draw_string(font, Vector2(640 - fs.x / 2, 690), fever, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.MAGENTA)

	# lives as hearts
	for i in range(3):
		var cx = 36.0 + i * 40.0
		var col = Color.CRIMSON if i < s.lives else Color(0.3, 0.3, 0.3)
		draw_circle(Vector2(cx - 6, 28), 8.0, col)
		draw_circle(Vector2(cx + 6, 28), 8.0, col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 13, 31), Vector2(cx + 13, 31), Vector2(cx, 48)
		]), col)

	# stage / mode
	draw_string(font, Vector2(20, 80), "%s · Stage %d" % [s.mode.capitalize().replace("_", " "), s.stage], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GRAY)

	# score / coins, top right
	var score_text = "Score: %d" % s.score
	var ss = font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
	draw_string(font, Vector2(1260 - ss.x, 36), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	var coin_text = "Coins: %d" % s.coins_earned
	var cs = font.get_string_size(coin_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(1260 - cs.x, 64), coin_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GOLD)

	# combo, centred — grows with the streak
	if s.combo > 1:
		var combo_text = "COMBO x%d" % s.combo
		var size = 20 + mini(s.combo, 20)
		var cbs = font.get_string_size(combo_text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
		draw_string(font, Vector2(640 - cbs.x / 2, 50), combo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.8, 0.2))

	# time-attack clock
	if s.mode == "time_attack":
		var t = "%0.1f" % time_left
		var ts = font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 34)
		var t_col = Color.ORANGE_RED if time_left < 10.0 else Color.WHITE
		draw_string(font, Vector2(640 - ts.x / 2, 100), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, t_col)

	# rising quality popups above the potato
	for p in popups:
		var frac = p.age / POPUP_LIFE
		var col = p.color
		col.a = 1.0 - frac
		var ps = font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
		draw_string(font, Vector2(640 - ps.x / 2, 210 - frac * 60.0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)

	# stage banner
	if banner_age < 1.5:
		var alpha = 1.0 if banner_age < 1.0 else (1.5 - banner_age) * 2.0
		var bs = font.get_string_size(banner_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 56)
		draw_rect(Rect2(0, 300, 1280, 110), Color(0, 0, 0, 0.55 * alpha))
		draw_string(font, Vector2(640 - bs.x / 2, 372), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.85, 0.3, alpha))

	# ESC hint
	draw_string(font, Vector2(20, 706), "[ESC] Quit to menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))
