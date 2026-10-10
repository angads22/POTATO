extends Node2D
class_name GameplayController

# Main gameplay orchestrator: builds each stage's potato sequence from the
# data tables, runs the matching minigame, and draws the HUD, quality
# popups, stage banners, fever overlay and screen shake on top.
#
# The kitchen runs on the music. Each stage has its own procedurally
# composed song (AudioManager / SongComposer) whose tempo climbs with the
# stage; potatoes land on bar lines, the cut cursor crosses the centre on
# beat 3 (the snare), FEVER fades in an extra layer of the song, and the
# boss strikes on the kick and snare. The beat clock keeps running with the
# sound off, so the game plays the same either way.

const POTATO_POS = Vector2(640, 330)
const POPUP_LIFE = 1.2
const BASE_BPM = 132.0
const FALL_SEC = 0.3          # PotatoVisual's drop-in before it lands
const MIN_GAP_BEATS = 0.75    # breathing room after a cut before the next landing
const INTRO_BEATS = 4.0       # a bar of music before a stage's first potato
const FEVER_BEATS = 16.0      # FEVER lasts four bars

# one musical style per championship venue (Endless cycles through them)
const STAGE_STYLES = ["lofi", "jazz", "funky", "disco", "gameshow", "epic"]

var current_minigame: MinigameBase
var stage_potatoes: Array[Dictionary] = []
var current_potato_index: int = 0
var potato_visual: PotatoVisual
var knife: KnifeVisual
var kitchen: KitchenBackground
var hud: GameHUD
var rng := RandomNumberGenerator.new()
var stage_misses: int = 0      # for the "Surgical" (clean-stage) achievement

# beat scheduling: the next thing that happens, on which beat of the song
var pending_action: String = ""   # "", "spawn", "stage_clear"
var pending_beat: float = 0.0
var pause_overlay: PauseOverlay

# feedback state
var popups: Array = []           # {text, color, age}
var banner_text: String = ""
var banner_age: float = 99.0
var shake: float = 0.0

func _ready():
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.fever_deactivated.connect(_on_fever_end)

	# kitchen backdrop behind everything (z_index = -1); its grandeur climbs
	# with the stage, so the venue visibly escalates toward the world final
	kitchen = KitchenBackground.new()
	kitchen.tier = _kitchen_tier()
	kitchen.beat_sync = true
	add_child(kitchen)

	# Multiplayer: host chose a seed and pushed it to the client, so both
	# sides generate the same potato sequence independently.
	if MultiplayerManager.is_in_multiplayer:
		rng.seed = MultiplayerManager.session_seed
	else:
		rng.randomize()

	potato_visual = PotatoVisual.new()
	potato_visual.position = POTATO_POS
	potato_visual.beat_sync = true
	add_child(potato_visual)

	knife = KnifeVisual.new()
	knife.position = POTATO_POS
	knife.beat_sync = true
	add_child(knife)

	# HUD on its own CanvasLayer: above everything, immune to screen shake
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud = GameHUD.new()
	hud.ctrl = self
	hud_layer.add_child(hud)
	add_child(hud_layer)

	_start_stage_music()
	_show_banner(_intro_banner())
	_load_stage_potatoes()
	_schedule("spawn", INTRO_BEATS)

func _exit_tree():
	if get_tree():
		get_tree().paused = false
	AudioManager.resume_music()

func _input(event: InputEvent):
	# ESC opens the pause menu (the run is only abandoned from there)
	if event.is_action_pressed("ui_cancel") and pause_overlay == null:
		_open_pause()
		get_viewport().set_input_as_handled()

func _notification(what):
	# a rhythm game shouldn't keep playing while you're in another window
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_overlay == null \
			and GameManager.current_state.is_running and not MultiplayerManager.is_in_multiplayer \
			and DisplayServer.get_name() != "headless":
		_open_pause()

func _process(delta):
	# screen shake decay — shaking this node moves the whole playfield
	if shake > 0.0:
		shake = maxf(0.0, shake - 40.0 * delta)
		position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		position = Vector2.ZERO

	_run_schedule()

	banner_age += delta
	for p in popups:
		p.age += delta
	popups = popups.filter(func(p): return p.age < POPUP_LIFE)

	hud.queue_redraw()

func add_shake(amount: float):
	if SaveDataManager.settings.get("screen_shake", true):
		shake = maxf(shake, amount)

# ────────────────────────────────────────────────────────
#  Music + beat scheduling
# ────────────────────────────────────────────────────────

func stage_bpm(stage: int = -1) -> float:
	if stage < 0:
		stage = GameManager.current_state.stage
	return snappedf(BASE_BPM * minf(1.5, 1.0 + (stage - 1) * 0.08), 0.5)

func stage_song(stage: int = -1) -> Dictionary:
	if stage < 0:
		stage = GameManager.current_state.stage
	return {"style": STAGE_STYLES[(stage - 1) % STAGE_STYLES.size()], "bpm": stage_bpm(stage), "seed": 100 + stage}

func boss_song() -> Dictionary:
	return {"style": "boss", "bpm": stage_bpm(), "seed": 666}

func _start_stage_music():
	var s = GameManager.current_state
	AudioManager.play_song(stage_song(), 0.6)
	if s.fever_active:
		AudioManager.set_layer("fever", true, 0.1)
	# get what comes next rendering in the background
	AudioManager.prefetch(stage_song(s.stage + 1))
	if s.mode == "championship" and s.stage >= 5:
		AudioManager.prefetch(boss_song())

func _fall_beats() -> float:
	return FALL_SEC / AudioManager.beat_sec()

# Queue the next potato/stage-clear on the first bar line at least
# `min_gap` beats from now.
func _schedule(action: String, min_gap: float = MIN_GAP_BEATS):
	pending_action = action
	pending_beat = AudioManager.next_bar(AudioManager.music_beat() + min_gap)

func _run_schedule():
	if pending_action == "" or not GameManager.current_state.is_running:
		return
	var now := AudioManager.music_beat()
	match pending_action:
		"spawn":
			# start the drop-in early so the potato lands right on the bar line
			if now >= pending_beat - _fall_beats():
				pending_action = ""
				_spawn_next_potato(pending_beat)
		"stage_clear":
			if now >= pending_beat:
				pending_action = ""
				_complete_stage()

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

	# Endless sweetens the pot: golden odds climb with every wave survived.
	# The "Lucky Spuds" research line raises the base odds in every mode.
	var golden_chance: float = golden.get("chance", 0.07) + SaveDataManager.research_bonus("golden_luck")
	if GameManager.current_state.mode == "endless":
		golden_chance += 0.01 * GameManager.current_state.stage
	golden_chance = minf(0.35, golden_chance)

	for i in range(count):
		if i > 0 and i % 4 == 0 and not rotten.is_empty():
			stage_potatoes.append(rotten.duplicate())
		elif not golden.is_empty() and rng.randf() < golden_chance:
			stage_potatoes.append(golden.duplicate())
		else:
			stage_potatoes.append(pool[rng.randi() % pool.size()].duplicate())
	current_potato_index = 0
	stage_misses = 0

func _spawn_next_potato(land_beat: float = -1.0e9):
	if not GameManager.current_state.is_running:
		return
	if current_potato_index >= stage_potatoes.size():
		_complete_stage()
		return

	var potato = stage_potatoes[current_potato_index]
	current_potato_index += 1
	potato_visual.setup(potato)
	AudioManager.play_sfx("potato_drop", -4.0)
	if potato.get("rare", false):
		AudioManager.play_sfx("golden", -3.0)
	_create_minigame(potato, land_beat)

func _create_minigame(potato: Dictionary, land_beat: float = -1.0e9):
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
	current_minigame.start_minigame(potato, land_beat)

func _on_minigame_completed(result: Dictionary):
	var quality: String = result["quality"]
	var potato = stage_potatoes[current_potato_index - 1]

	var fx_on: bool = SaveDataManager.settings.get("particle_effects", true)

	if potato.get("rotten", false):
		if quality == "PERFECT":
			potato_visual.bin()
			GameManager.add_combo()
			GameManager.record_cut("PERFECT")
			_popup("BINNED!", Color.LIGHT_GREEN)
			AudioManager.play_sfx("bin")
		else:
			knife.chop()
			potato_visual.split()
			if fx_on:
				Fx.splat(self, POTATO_POS)
			GameManager.lose_life()
			GameManager.reset_combo()
			GameManager.record_cut("FAIL")
			stage_misses += 1
			_popup("ROTTEN!  -1 LIFE", Color.ORANGE_RED)
			add_shake(14.0)
			AudioManager.play_sfx("splat")
			AudioManager.play_sfx("cut_miss", -6.0)
	elif quality == "MISS" or quality == "FAIL":
		GameManager.lose_life()
		GameManager.reset_combo()
		GameManager.record_cut(quality)
		stage_misses += 1
		_popup("MISS", Color.ORANGE_RED)
		add_shake(10.0)
		AudioManager.play_sfx("cut_miss")
	else:
		knife.chop()
		potato_visual.split()
		if fx_on:
			Fx.burst(self, POTATO_POS, potato_visual.body_color)
		var base = int(potato.get("base_points", 100) * result["multiplier"])
		var points = GameManager.add_score(base, quality)
		GameManager.add_combo()
		GameManager.record_cut(quality)
		_popup("%s  +%d" % [quality, points], _quality_color(quality))
		if quality == "PERFECT" and fx_on:
			Fx.ring(self, POTATO_POS)
		AudioManager.play_sfx_varied("cut_great" if quality == "PERFECT" else "cut_good", 0.04)
		_award("first_cut")
		# combo milestones
		var combo = GameManager.current_state.combo
		if combo >= 50:
			_award("combo_50")
		elif combo >= 25:
			_award("combo_25")
		if combo > 0 and combo % 10 == 0:
			AudioManager.play_sfx("combo_up")
		if potato.get("rare", false):
			var coins = int(potato.get("coin_bonus", 15))
			GameManager.current_state.coins_earned += coins
			if fx_on:
				Fx.sparkle(self, POTATO_POS)
			_popup("GOLDEN!  +%d coins" % coins, Color.GOLD)
			AudioManager.play_sfx("coin_collect")
			_award("golden_touch")

	if GameManager.current_state.combo >= 20 and not GameManager.current_state.fever_active:
		GameManager.activate_fever(FEVER_BEATS * AudioManager.beat_sec())
		AudioManager.set_layer("fever", true, 0.25)
		_popup("FEVER!", Color.MAGENTA)
		AudioManager.play_sfx("fever_start")
		_award("feeling_heat")

	# Keep opponent in sync (no-op outside of multiplayer sessions)
	if MultiplayerManager.is_in_multiplayer:
		MultiplayerManager.broadcast_score(
			GameManager.current_state.score,
			GameManager.current_state.lives
		)

	if not GameManager.current_state.is_running:
		return
	if current_potato_index >= stage_potatoes.size():
		_schedule("stage_clear", 1.5)
	else:
		_schedule("spawn")

func _on_fever_end():
	AudioManager.set_layer("fever", false, 1.0)

func _complete_stage():
	var s = GameManager.current_state
	# Clean-stage achievement for the stage we just finished
	if stage_misses == 0:
		_award("surgical")
	match s.mode:
		"championship":
			if s.stage >= 6:
				_spawn_boss()
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
				kitchen.tier = _kitchen_tier()
				AudioManager.play_sfx("level_complete")
				_show_banner("%s" % _stage_name(s.stage))
				_next_stage()
		"endless":
			# Wave bonus grows the deeper you go — survival pays
			var bonus = s.stage * 50
			s.score += bonus
			GameManager.score_changed.emit(s.score)
			_popup("WAVE CLEAR  +%d" % bonus, Color.GOLD)
			GameManager.progress_stage()
			kitchen.tier = _kitchen_tier()
			AudioManager.play_sfx("level_complete")
			_show_banner("WAVE %d" % s.stage)
			_next_stage()
		_:
			GameManager.end_game(true)

# New stage: new venue, new song (faster), a bar of intro, then potatoes.
func _next_stage():
	_start_stage_music()
	_load_stage_potatoes()
	_schedule("spawn", INTRO_BEATS)

func _on_game_ended(_final_score: int, victory: bool):
	GameManager.current_state.last_victory = victory
	pending_action = ""
	_show_banner("VICTORY!" if victory else "GAME OVER")
	AudioManager.stop_music(1.2)
	AudioManager.play_sfx("victory" if victory else "game_over")
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")

# ────────────────────────────────────────────────────────
#  Pause menu
# ────────────────────────────────────────────────────────

func _open_pause():
	if not GameManager.current_state.is_running:
		return
	pause_overlay = PauseOverlay.new()
	pause_overlay.freeze_tree = not MultiplayerManager.is_in_multiplayer
	if MultiplayerManager.is_in_multiplayer:
		pause_overlay.subtitle = "The match keeps going for your opponent!"
	pause_overlay.options = [
		{"id": "resume", "label": "Resume  [ESC]", "key": KEY_ESCAPE},
		{"id": "restart", "label": "Restart run  [R]", "key": KEY_R},
		{"id": "end", "label": "End run & bank coins  [E]", "key": KEY_E},
		{"id": "quit", "label": "Quit to menu  [Q]", "key": KEY_Q},
	]
	if MultiplayerManager.is_in_multiplayer:
		pause_overlay.options.remove_at(1)  # no restarts mid-duel
	pause_overlay.chosen.connect(_on_pause_choice)
	add_child(pause_overlay)

func _on_pause_choice(id: String):
	var overlay := pause_overlay
	pause_overlay = null
	overlay.close()
	match id:
		"restart":
			var mode: String = GameManager.current_state.mode
			GameManager.current_state.is_running = false
			GameManager.start_game(mode)
			get_tree().reload_current_scene()
		"end":
			# finish the run properly: the results screen banks the coins
			GameManager.end_game(false)
		"quit":
			GameManager.current_state.is_running = false
			AudioManager.stop_music(0.4)
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

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
#  Progression: themed venues, achievements, the boss
# ────────────────────────────────────────────────────────

const STAGE_NAMES = [
	"TRAINING KITCHEN", "DINNER PARTY", "STREET FOOD STALL",
	"RESTAURANT KITCHEN", "TV COOK-OFF", "WORLD CHAMPIONSHIP",
]

func _stage_name(stage: int) -> String:
	if stage >= 1 and stage <= STAGE_NAMES.size():
		return STAGE_NAMES[stage - 1]
	return "STAGE %d" % stage

func _intro_banner() -> String:
	var s = GameManager.current_state
	if s.mode == "endless":
		return "WAVE %d" % s.stage
	return _stage_name(s.stage)

# Backdrop grandeur tier (1..6) from the current stage.
func _kitchen_tier() -> int:
	return clampi(GameManager.current_state.stage, 1, 6)

# Unlock an achievement once and toast it on the HUD.
func _award(id: String):
	if SaveDataManager.unlock_achievement(id):
		var a = GameData.achievement_by_id(id)
		if hud:
			hud.achievement_toast(a.get("name", id))
		AudioManager.play_sfx("achievement")

# The championship finale: a multi-hit Colossal Spud with an HP bar. Replaces
# the old instant end_game(true). Boss handles its own swings and life loss;
# we just react to its single completion. It gets its own theme at the final
# stage's tempo, a bar of growling intro, then strikes on the kick and snare.
func _spawn_boss():
	if current_minigame:
		current_minigame.queue_free()
	pending_action = ""
	potato_visual.visible = false
	kitchen.tier = 6
	_show_banner("FINAL BOSS — COLOSSAL SPUD")
	AudioManager.play_song(boss_song(), 0.3)
	if GameManager.current_state.fever_active:
		AudioManager.set_layer("fever", true, 0.1)
	AudioManager.play_sfx("boss_roar")
	var boss := BossMinigame.new()
	boss.ctrl = self
	current_minigame = boss
	add_child(boss)
	boss.minigame_completed.connect(_on_boss_completed)
	boss.start_minigame({"base_points": 200}, INTRO_BEATS)

func _on_boss_completed(_result: Dictionary):
	if not GameManager.current_state.is_running:
		return
	_award("boss_slayer")
	GameManager.end_game(true)
