extends Control
class_name FpsHud

# Procedural heads-up display for the SPUD BLASTER arena (crosshair, health,
# scoreboard, match timer, pause + results overlays). Drawn the same way as the
# rest of the game's UI — immediate-mode _draw with the fallback font.

var arena  # FpsArena

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if arena == null:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var cx := vp.x / 2.0

	if not arena.match_over:
		_draw_crosshair(vp)
		_draw_health(font, vp)
		_draw_scoreboard(font, vp, false)
		_draw_timer(font, cx)
		_draw_controls(font, vp)
		if arena.paused:
			_draw_pause(font, vp, cx)
	else:
		_draw_results(font, vp, cx)

func _draw_crosshair(vp: Vector2) -> void:
	var c := vp / 2.0
	var col := Color(1, 1, 1, 0.85)
	var gap := 4.0
	var len := 10.0
	draw_line(c + Vector2(-gap - len, 0), c + Vector2(-gap, 0), col, 2.0)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 2.0)
	draw_line(c + Vector2(0, -gap - len), c + Vector2(0, -gap), col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 2.0)
	draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.4, 0.3, 0.9))

func _draw_health(font: Font, vp: Vector2) -> void:
	var p = arena.get_local_player()
	var hp := 0
	if p != null and is_instance_valid(p):
		hp = p.health
	var x := 36.0
	var y := vp.y - 64.0
	var w := 280.0
	draw_rect(Rect2(x, y, w, 26), Color(0, 0, 0, 0.45))
	var frac := clampf(float(hp) / float(FpsPlayer.MAX_HEALTH), 0.0, 1.0)
	var bar_col := Color(0.3, 0.8, 0.35).lerp(Color(0.85, 0.2, 0.15), 1.0 - frac)
	draw_rect(Rect2(x + 3, y + 3, (w - 6) * frac, 20), bar_col)
	draw_string(font, Vector2(x + 10, y + 20), "HP %d" % hp,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	if p != null and is_instance_valid(p) and not p.alive:
		draw_string(font, Vector2(x, y - 16), "Sliced! Respawning…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.6, 0.4))

func _draw_timer(font: Font, cx: float) -> void:
	var t := int(ceil(arena.time_left))
	var txt := "%d:%02d" % [t / 60, t % 60]
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
	draw_string(font, Vector2(cx - ts.x / 2.0, 52), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.95, 0.8))
	var sub: String = "First to %d frags" % arena.frag_limit
	var ss := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2(cx - ss.x / 2.0, 70), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.78, 0.7))

func _draw_scoreboard(font: Font, vp: Vector2, _full: bool) -> void:
	var rows := _ranked()
	var x := vp.x - 240.0
	var y := 40.0
	draw_string(font, Vector2(x, y), "SCORES", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GOLD)
	y += 26.0
	for row in rows:
		var me: bool = row["pid"] == FpsNetwork.local_id()
		var col: Color = Color(1, 0.95, 0.6) if me else Color(0.9, 0.88, 0.82)
		var line := "%-14s %d" % [str(row["name"]).left(14), row["frags"]]
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		y += 22.0

func _draw_controls(font: Font, vp: Vector2) -> void:
	draw_string(font, Vector2(vp.x / 2.0 - 250, vp.y - 18),
			"WASD move · MOUSE look · LMB/F shoot · SPACE jump · ESC pause",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.85, 0.85, 0.7))

func _draw_pause(font: Font, vp: Vector2, cx: float) -> void:
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(cx - 70, vp.y / 2.0 - 20), "PAUSED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.GOLD)
	draw_string(font, Vector2(cx - 150, vp.y / 2.0 + 24),
			"[ESC] Resume     [Q] Quit to menu",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

func _draw_results(font: Font, vp: Vector2, cx: float) -> void:
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.05, 0.03, 0.92))
	var title := "MATCH OVER"
	var tsz := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 48)
	draw_string(font, Vector2(cx - tsz.x / 2.0, 130), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.GOLD)

	var win_name := _name_for(arena.winner_id)
	var won := "%s wins!" % win_name if arena.winner_id != -1 else "Time!"
	if arena.winner_id == FpsNetwork.local_id():
		won = "You win!"
	var ws := font.get_string_size(won, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
	draw_string(font, Vector2(cx - ws.x / 2.0, 184), won,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.95, 0.75))

	var y := 250.0
	var rank := 1
	for row in _ranked():
		var line := "#%d   %-16s   %d frags" % [rank, str(row["name"]).left(16), row["frags"]]
		var me: bool = row["pid"] == FpsNetwork.local_id()
		draw_string(font, Vector2(cx - 180, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				Color(1, 0.95, 0.6) if me else Color.WHITE)
		y += 34.0
		rank += 1

	draw_string(font, Vector2(cx - 130, vp.y - 70), "[ENTER] Back to menu",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.78, 0.7))

func _ranked() -> Array:
	var rows: Array = []
	for pid in arena.players.keys():
		rows.append({
			"pid": pid,
			"name": _name_for(pid),
			"frags": arena.scores.get(pid, 0),
		})
	rows.sort_custom(func(a, b): return a["frags"] > b["frags"])
	return rows

func _name_for(pid: int) -> String:
	return str(FpsNetwork.players.get(pid, {}).get("name", "Chef"))
