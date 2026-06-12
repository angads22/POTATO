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
var knife: KnifeVisual
var hud: GameHUD
var rng := RandomNumberGenerator.new()

# feedback state
var popups: Array = []           # {text, color, age}
var banner_text: String = ""
var banner_age: float = 99.0
var shake: float = 0.0

func _ready():
	GameManager.game_ended.connect(_on_game_ended)

	# kitchen backdrop behind everything (z_index = -1)
	add_child(KitchenBackground.new())

	# Multiplayer: host chose a seed and pushed it to the client, so both
	# sides generate the same potato sequence independently.
	if MultiplayerManager.is_in_multiplayer:
		rng.seed = MultiplayerManager.session_seed
	else:
		rng.randomize()

	potato_visual = PotatoVisual.new()
	potato_visual.position = POTATO_POS
	add_child(potato_visual)

	knife = KnifeVisual.new()
	knife.position = POTATO_POS
	add_child(knife)

	# HUD on its own CanvasLayer: above everything, immune to screen shake
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud = GameHUD.new()
	hud.ctrl = self
	hud_layer.add_child(hud)
	add_child(hud_layer)

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

	hud.queue_redraw()

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

	# Endless sweetens the pot: golden odds climb with every wave survived
	var golden_chance: float = golden.get("chance", 0.07)
	if GameManager.current_state.mode == "endless":
		golden_chance = minf(0.25, golden_chance + 0.01 * GameManager.current_state.stage)

	for i in range(count):
		if i > 0 and i % 4 == 0 and not rotten.is_empty():
			stage_potatoes.append(rotten.duplicate())
		elif not golden.is_empty() and rng.randf() < golden_chance:
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

	var fx_on: bool = SaveDataManager.settings.get("particle_effects", true)

	if potato.get("rotten", false):
		if quality == "PERFECT":
			potato_visual.bin()
			GameManager.add_combo()
			_popup("BINNED!", Color.LIGHT_GREEN)
			AudioManager.play_sfx("cut_great")
		else:
			knife.chop()
			potato_visual.split()
			if fx_on:
				Fx.splat(self, POTATO_POS)
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
		knife.chop()
		potato_visual.split()
		if fx_on:
			Fx.burst(self, POTATO_POS, potato_visual.body_color)
		var base = int(potato.get("base_points", 100) * result["multiplier"])
		var points = GameManager.add_score(base, quality)
		GameManager.add_combo()
		_popup("%s  +%d" % [quality, points], _quality_color(quality))
		if quality == "PERFECT" and fx_on:
			Fx.ring(self, POTATO_POS)
		AudioManager.play_sfx("cut_great" if quality == "PERFECT" else "cut_good")
		if potato.get("rare", false):
			var coins = int(potato.get("coin_bonus", 15))
			GameManager.current_state.coins_earned += coins
			if fx_on:
				Fx.sparkle(self, POTATO_POS)
			_popup("GOLDEN!  +%d coins" % coins, Color.GOLD)

	if GameManager.current_state.combo >= 20 and not GameManager.current_state.fever_active:
		GameManager.activate_fever()
		_popup("FEVER!", Color.MAGENTA)
		AudioManager.play_sfx("fever_start")

	# Keep opponent in sync (no-op outside of multiplayer sessions)
	if MultiplayerManager.is_in_multiplayer:
		MultiplayerManager.broadcast_score(
			GameManager.current_state.score,
			GameManager.current_state.lives
		)

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
				# Stage-clear bonus scales with the stage; every other
				# stage also restores a lost life, so a stumble in stage 2
				# doesn't doom the stage-6 finale.
				var bonus = s.stage * 100
				s.score += bonus
				GameManager.score_changed.emit(s.score)
				var clear_text = "STAGE CLEAR  +%d" % bonus
				if s.stage % 2 == 0 and s.lives < 3:
					s.lives += 1
					GameManager.lives_changed.emit(s.lives)
					clear_text += "  +1 LIFE"
				_popup(clear_text, Color.GOLD)
				GameManager.progress_stage()
				AudioManager.play_sfx("level_complete")
				_show_banner("STAGE %d" % s.stage)
				_load_stage_potatoes()
				_spawn_next_potato()
		"endless":
			# Wave bonus grows the deeper you go — survival pays
			var bonus = s.stage * 50
			s.score += bonus
			GameManager.score_changed.emit(s.score)
			_popup("WAVE CLEAR  +%d" % bonus, Color.GOLD)
			GameManager.progress_stage()
			_show_banner("WAVE %d" % s.stage)
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

