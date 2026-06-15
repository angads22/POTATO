extends MinigameBase
class_name BossMinigame

# The Colossal Spud — the championship finale. Unlike the one-cut minigames
# this one stays active across many swings: a sweeping cursor (so a human and
# the headless auto-player, which seeks `cursor` to 0.5, both drive it), an HP
# bar, and a giant cracked potato whose skin splits open as its health drains.
# It reports a single completion when the boss falls; mid-fight misses cost
# lives through GameManager (a death ends the run via the normal path).

const PERFECT_W = 0.03
const GREAT_W = 0.07
const GOOD_W = 0.13
const MAX_HP = 8
const BOSS_POS = Vector2(640, 300)
const BOSS_R = 150.0

var ctrl  # GameplayController — shared feedback (knife chop, popups, shake, Fx)
var cursor: float = 0.0
var dir: float = 1.0
var speed: float = 0.75
var boss_hp: int = MAX_HP
var hit_flash: float = 0.0
var defeated: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	cursor = 0.0
	dir = 1.0
	boss_hp = MAX_HP
	defeated = false
	speed = 0.75

func _process(delta):
	if not is_active or defeated or not GameManager.current_state.is_running:
		return
	cursor += dir * speed * delta
	if cursor >= 1.0:
		cursor = 1.0
		dir = -1.0
	elif cursor <= 0.0:
		cursor = 0.0
		dir = 1.0
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	queue_redraw()

func _on_primary_input():
	if defeated or not is_active or not GameManager.current_state.is_running:
		return
	var q = judge(abs(cursor - 0.5), PERFECT_W, GREAT_W, GOOD_W)
	if q == "MISS":
		GameManager.lose_life()
		GameManager.reset_combo()
		if ctrl:
			ctrl._popup("MISS", Color.ORANGE_RED)
			ctrl.shake = 12.0
		AudioManager.play_sfx("cut_miss")
		return  # a death flips is_running off; _process/_input then stand down
	var dmg = 2 if q == "PERFECT" else 1
	boss_hp = maxi(0, boss_hp - dmg)
	hit_flash = 1.0
	var pts = GameManager.add_score(int(potato_data.get("base_points", 200)), q)
	GameManager.add_combo()
	if ctrl:
		ctrl.knife.chop()
		ctrl._popup("%s  +%d" % [q, pts], Color.GOLD if q == "PERFECT" else Color.LIGHT_GREEN)
		ctrl.shake = 8.0
		if SaveDataManager.settings.get("particle_effects", true):
			Fx.burst(ctrl, BOSS_POS, Color(0.72, 0.52, 0.26))
	AudioManager.play_sfx("cut_great" if q == "PERFECT" else "cut_good")
	if boss_hp <= 0:
		defeated = true
		if ctrl:
			ctrl.shake = 22.0
		cut_result.quality = "PERFECT"
		cut_result.score_multiplier = 1.5
		end_minigame()

func _draw():
	if not is_active:
		return
	var hp_frac := float(boss_hp) / float(MAX_HP)

	# ── the Colossal Spud, cracking as its HP drops ──
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * hit_flash * 5.0
	var c := BOSS_POS + jitter
	var skin := Color(0.78, 0.6, 0.34).lerp(Color(0.55, 0.42, 0.22), 1.0 - hp_frac)
	if hit_flash > 0.0:
		skin = skin.lerp(Color.WHITE, hit_flash * 0.5)
	# body shadow + lumpy potato
	draw_circle(c + Vector2(0, BOSS_R * 0.78), BOSS_R * 0.9, Color(0, 0, 0, 0.22))
	draw_circle(c, BOSS_R, skin.darkened(0.12))
	draw_circle(c + Vector2(-18, -14), BOSS_R * 0.86, skin)
	# eyes + scowl — angrier as it weakens
	draw_circle(c + Vector2(-52, -36), 16.0, Color(0.1, 0.08, 0.05))
	draw_circle(c + Vector2(52, -36), 16.0, Color(0.1, 0.08, 0.05))
	draw_circle(c + Vector2(-46, -42), 5.0, Color.WHITE)
	draw_circle(c + Vector2(58, -42), 5.0, Color.WHITE)
	draw_line(c + Vector2(-74, -62), c + Vector2(-30, -48), Color(0.2, 0.13, 0.07), 5.0)
	draw_line(c + Vector2(74, -62), c + Vector2(30, -48), Color(0.2, 0.13, 0.07), 5.0)
	# cracks open up as health falls
	var cracks := int((1.0 - hp_frac) * 5.0)
	for i in range(cracks):
		var a := i * 1.7
		var p0 := c + Vector2(cos(a), sin(a)) * BOSS_R * 0.2
		var p1 := c + Vector2(cos(a + 0.3), sin(a + 0.3)) * BOSS_R * 0.95
		draw_line(p0, p1, Color(0.15, 0.08, 0.03, 0.8), 3.0)

	# ── HP bar (below the combo counter so they don't collide) ──
	var bw := 640.0
	var bx := 640.0 - bw * 0.5
	var by := 110.0
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(bx, by - 8), "COLOSSAL SPUD", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.85, 0.4))
	draw_rect(Rect2(bx - 3, by - 3, bw + 6, 26), Color(0.1, 0.07, 0.04))
	draw_rect(Rect2(bx, by, bw, 20), Color(0.25, 0.05, 0.05))
	var hp_col := Color(0.85, 0.2, 0.2).lerp(Color(0.95, 0.7, 0.2), hp_frac)
	draw_rect(Rect2(bx, by, bw * hp_frac, 20), hp_col)

	# shared timing track + hint
	draw_timing_track(cursor, PERFECT_W, GREAT_W, GOOD_W, false)
	draw_hint("[SPACE] Strike the Colossal Spud at the centre!")
