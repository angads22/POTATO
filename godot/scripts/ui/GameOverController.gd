extends Node2D

# Results screen. The final score counts up, the run's letter grade stamps
# down, and the cut breakdown (PERFECT / GREAT / GOOD / MISS), accuracy and
# max combo explain how it was earned. Name entry banks the score on the
# leaderboard (the last name used is remembered), then [R] plays again or
# [SPACE] returns to the menu.

const Fmt = preload("res://scripts/utils/NumFmt.gd")
const COUNT_TIME = 1.1    # score count-up
const STAMP_AT = 1.25     # grade stamp lands
const GRADE_COLORS = {
	"S": Color(1.0, 0.84, 0.25), "A": Color(0.55, 0.95, 0.45), "B": Color(0.45, 0.8, 1.0),
	"C": Color(0.95, 0.75, 0.45), "D": Color(0.95, 0.45, 0.35),
}

var name_entry: String = ""
var submitted: bool = false
var earned_rank: int = -1
var t: float = 0.0
var _ticked: int = 0
var _stamped := false
var _best_sfx := false

func _ready():
	var bg = KitchenBackground.new()
	bg.show_board = false
	add_child(bg)
	AudioManager.play_music("results", 1.5)
	name_entry = str(SaveDataManager.settings.get("player_name", ""))
	if name_entry == "Chef":
		name_entry = ""
	queue_redraw()

func _process(delta):
	t += delta
	# score count-up ticks, then the stamp
	var ticks := int(clampf(t / COUNT_TIME, 0.0, 1.0) * 14.0)
	if ticks > _ticked and t < COUNT_TIME:
		_ticked = ticks
		AudioManager.play_sfx("menu_move", -6.0, 1.0 + ticks * 0.04)
	if t >= STAMP_AT and not _stamped:
		_stamped = true
		AudioManager.play_sfx("boss_hit", -4.0)
		if _grade() == "S":
			AudioManager.play_sfx("rank_up")
	if t >= STAMP_AT + 0.4 and not _best_sfx:
		_best_sfx = true
		if _new_best():
			AudioManager.play_sfx("achievement")
	queue_redraw()

func _grade() -> String:
	return GameManager.grade()

func _new_best() -> bool:
	var s = GameManager.current_state
	return s.score > 0 and s.score > s.prev_best

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed):
		return
	# skip the count-up animation on the first key
	if t < STAMP_AT:
		t = STAMP_AT
		return
	if submitted:
		match event.keycode:
			KEY_R:
				_play_again()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
				_return_to_menu()
		return

	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_submit_score()
		KEY_BACKSPACE:
			name_entry = name_entry.substr(0, max(0, name_entry.length() - 1))
			AudioManager.play_sfx("type", 0.0, 0.8)
		KEY_ESCAPE:
			_return_to_menu()
		_:
			# Accept printable name characters, cap at 12
			var ch := char(event.unicode)
			if ch.length() == 1 and ch.strip_edges() != "" and name_entry.length() < 12:
				name_entry += ch
				AudioManager.play_sfx_varied("type", 0.1)

func _submit_score():
	var player_name := name_entry.strip_edges() if name_entry.strip_edges() != "" else "CHEF"
	SaveDataManager.update_setting("player_name", player_name)
	earned_rank = SaveDataManager.add_to_leaderboard(
		player_name,
		GameManager.current_state.score,
		GameManager.current_state.mode
	)
	submitted = true
	AudioManager.play_sfx("coin_collect")

func _play_again():
	var mode: String = GameManager.current_state.mode
	AudioManager.play_sfx("menu_select")
	if mode == "concert":
		var s = GameManager.current_state
		if not s.concert_spec.is_empty():
			ConcertController.replay = {"spec": s.concert_spec, "difficulty": s.difficulty}
		get_tree().change_scene_to_file("res://scenes/Concert/ConcertScene.tscn")
		return
	GameManager.start_game(mode)
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func _return_to_menu():
	AudioManager.play_sfx("menu_back")
	var dest := "res://scenes/MainMenu.tscn"
	if GameManager.current_state.mode == "concert":
		# a concert started at the town's Concert Hall walks you back out there
		dest = ConcertController.return_scene
		ConcertController.return_scene = "res://scenes/MainMenu.tscn"
	get_tree().change_scene_to_file(dest)

# ────────────────────────────────────────────────────────
#  Drawing
# ────────────────────────────────────────────────────────

func _text(font: Font, s: String, cx: float, y: float, size: int, col: Color):
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(font, Vector2(cx - w / 2, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw():
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var cx := vp.x / 2
	var s = GameManager.current_state

	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.03, 0.0, 0.72))
	var panel := Rect2(cx - 400, 40, 800, 640)
	GameHUD.panel_style(Color(0.16, 0.1, 0.06, 0.95)).draw(get_canvas_item(), panel)

	# Headline reflects victory vs. defeat
	var headline := "VICTORY!" if s.last_victory else "GAME OVER"
	if s.mode == "concert":
		headline = "SONG CLEAR!" if s.last_victory else "BOOED OFF STAGE"
	var head_color := Color.GOLD if s.last_victory else Color.ORANGE_RED
	_text(font, headline, cx, 100, 44, head_color)
	var sub := "%s · reached Stage %d" % [s.mode.capitalize().replace("_", " "), s.stage]
	if s.mode == "concert":
		sub = "Concert · \"%s\" · %s" % [s.song_title, s.difficulty.capitalize()]
	_text(font, sub, cx, 132, 17, Color(0.72, 0.66, 0.56))

	# ── left column: score + stats ──
	var lx := cx - 360.0
	var shown := int(s.score * clampf(t / COUNT_TIME, 0.0, 1.0))
	draw_string(font, Vector2(lx, 180), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.68, 0.3))
	draw_string(font, Vector2(lx, 228), "%d" % shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color.WHITE)
	if _new_best() and t >= STAMP_AT + 0.4:
		var pulse := 0.75 + 0.25 * sin(t * 7.0)
		draw_string(font, Vector2(lx, 256), "★ NEW BEST! (was %d)" % s.prev_best, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color(1.0, 0.85, 0.3, pulse))

	var rows := [
		["PERFECT", s.perfect, Color.GOLD], ["GREAT", s.great, Color.LIGHT_GREEN],
		["GOOD", s.good, Color(0.9, 0.9, 0.9)], ["MISS", s.miss, Color.ORANGE_RED],
	]
	var total := maxi(1, GameManager.cuts_judged())
	var y := 296.0
	for r in rows:
		draw_string(font, Vector2(lx, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, r[2])
		draw_string(font, Vector2(lx + 110, y), "%d" % r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		# proportion bar
		var bw := 200.0 * float(r[1]) / total * clampf((t - 0.3) / 0.8, 0.0, 1.0)
		draw_rect(Rect2(lx + 160, y - 13, 200, 12), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(lx + 160, y - 13, bw, 12), Color(r[2].r, r[2].g, r[2].b, 0.75))
		y += 30.0
	draw_string(font, Vector2(lx, y + 8), "Accuracy  %.1f%%" % (GameManager.accuracy() * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.8))
	draw_string(font, Vector2(lx + 200, y + 8), "Max combo  %d" % s.max_combo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.8))

	# ── right column: the grade stamp ──
	var gx := cx + 230.0
	var gy := 300.0
	draw_string(font, Vector2(gx - 40, 180), "GRADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.68, 0.3))
	if t >= STAMP_AT - 0.25:
		var k := clampf((t - (STAMP_AT - 0.25)) / 0.25, 0.0, 1.0)
		var sc := lerpf(3.2, 1.0, k * k)
		var alpha := k
		var g := _grade()
		var col: Color = GRADE_COLORS.get(g, Color.WHITE)
		draw_set_transform(Vector2(gx, gy), -0.12 * (1.0 - k) - 0.08, Vector2(sc, sc))
		draw_circle(Vector2.ZERO, 78.0, Color(col.r, col.g, col.b, 0.14 * alpha))
		draw_arc(Vector2.ZERO, 78.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.85 * alpha), 5.0)
		draw_arc(Vector2.ZERO, 66.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.4 * alpha), 2.0)
		var gs := font.get_string_size(g, HORIZONTAL_ALIGNMENT_CENTER, -1, 110)
		draw_string(font, Vector2(-gs.x / 2, 38), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 110, Color(col.r, col.g, col.b, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# ── rewards ──
	var ry := 470.0
	if s.last_payout > 0:
		var pay := "+%s c" % Fmt.coins(s.last_payout)
		if s.last_picnic > 0:
			# the Farm Picnic: minutes of the farm's output on top (design §8)
			pay += " · Farm Picnic +%s (%s farm-min)" % [Fmt.coins(s.last_picnic), Fmt.compact(s.picnic_min)]
		else:
			pay += " banked to your farm"
		_text(font, "%s  ·  wallet %s" % [pay, Fmt.coins(SaveDataManager.wallet())], cx, ry, 18, Color.GOLD)
		ry += 26.0
	var rank := SaveDataManager.career_rank()
	_text(font, "+%d Chef XP  ·  %s" % [s.last_xp_gain, rank["name"]], cx, ry, 17, Color(0.85, 0.7, 0.3))
	if s.ranked_up:
		var pulse2 := 0.7 + 0.3 * sin(t * 4.0)
		_text(font, "★ RANK UP — %s! ★" % rank["name"], cx, ry + 26, 20, Color(1.0, 0.85, 0.35, pulse2))

	# ── name entry / next steps ──
	if submitted:
		var rank_text := ("Banked at #%d on the leaderboard!" % (earned_rank + 1)) if earned_rank >= 0 else "Score saved!"
		_text(font, rank_text, cx, 580, 21, Color.LIGHT_GREEN)
		_text(font, "[R] Play again      [SPACE] Back to menu", cx, 630, 18, Color(0.75, 0.7, 0.62))
	else:
		_text(font, "Sign the scoreboard:", cx, 560, 18, Color.WHITE)
		var caret := "_" if fmod(t, 1.0) < 0.55 else " "
		_text(font, name_entry + caret, cx, 600, 28, Color.GOLD)
		_text(font, "[ENTER] Submit    [ESC] Skip", cx, 640, 15, Color.GRAY)
