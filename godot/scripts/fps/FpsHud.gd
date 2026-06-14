extends Control
class_name FpsHud

# Procedural heads-up display for the SPUD BLASTER arena: crosshair + hitmarker,
# health, ammo + weapon slots, reload bar, map name, scoreboard, match timer,
# pause overlay and the coins/starch payout results screen. Drawn the same way
# as the rest of the game's UI — immediate-mode _draw with the fallback font.

var arena  # FpsArena

var _hitmarker_until := 0.0
var _hitmarker_head := false
var _notify_text := ""
var _notify_until := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

# called by the arena when a local shot connects
func hitmarker(headshot: bool) -> void:
	_hitmarker_until = _now() + 0.18
	_hitmarker_head = headshot

# called by pickups / events for a short floating message
func notify(text: String) -> void:
	_notify_text = text
	_notify_until = _now() + 2.0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _draw() -> void:
	if arena == null:
		return
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	var cx := vp.x / 2.0

	if not arena.match_over:
		_draw_crosshair(vp)
		_draw_hitmarker(vp)
		_draw_health(font, vp)
		_draw_ammo(font, vp)
		_draw_weapon_slots(font, vp)
		_draw_reload(font, vp)
		_draw_map_name(font)
		_draw_scoreboard(font, vp, false)
		_draw_timer(font, cx)
		_draw_notify(font, vp)
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
	var p = arena.get_local_player()
	# bloom the crosshair to the current weapon's hipfire spread
	if p != null and is_instance_valid(p):
		gap += p.current_spread() * 1.6
	draw_line(c + Vector2(-gap - len, 0), c + Vector2(-gap, 0), col, 2.0)
	draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 2.0)
	draw_line(c + Vector2(0, -gap - len), c + Vector2(0, -gap), col, 2.0)
	draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 2.0)
	draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.4, 0.3, 0.9))

func _draw_hitmarker(vp: Vector2) -> void:
	if _now() > _hitmarker_until:
		return
	var c := vp / 2.0
	var col := Color(1.0, 0.85, 0.3) if _hitmarker_head else Color(1, 1, 1, 0.95)
	var a := 7.0
	var b := 14.0
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_line(c + s * a, c + s * b, col, 2.0)

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

func _draw_ammo(font: Font, vp: Vector2) -> void:
	var p = arena.get_local_player()
	if p == null or not is_instance_valid(p):
		return
	var w := str(p.current_weapon_def().get("name", ""))
	var ammo := "%d / %d" % [p.mag_ammo(), p.reserve_ammo()]
	var x := vp.x - 230.0
	var y := vp.y - 88.0
	# big magazine readout
	var low: bool = p.mag_ammo() <= maxi(1, int(p.current_weapon_def().get("mag", 10)) / 5)
	var col: Color = Color(1.0, 0.5, 0.35) if low else Color(1, 0.95, 0.8)
	var as_ := font.get_string_size(ammo, HORIZONTAL_ALIGNMENT_RIGHT, -1, 34)
	draw_string(font, Vector2(vp.x - 36 - as_.x, y + 30), ammo,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, col)
	var ws := font.get_string_size(w, HORIZONTAL_ALIGNMENT_RIGHT, -1, 16)
	draw_string(font, Vector2(vp.x - 36 - ws.x, y + 2), w,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.78, 0.74, 0.66))

func _draw_weapon_slots(font: Font, vp: Vector2) -> void:
	var p = arena.get_local_player()
	if p == null or not is_instance_valid(p):
		return
	var x := vp.x - 230.0
	var y := vp.y - 132.0
	for i in range(p.loadout.size()):
		var id := str(p.loadout[i])
		var sel: bool = i == p.current_slot
		var label := "%d %s" % [i + 1, FpsWeapons.display_name(id)]
		var bg: Color = Color(0.9, 0.7, 0.25, 0.85) if sel else Color(0, 0, 0, 0.4)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_RIGHT, -1, 15)
		var bx := vp.x - 36 - tw.x - 12
		draw_rect(Rect2(bx, y - 14, tw.x + 16, 20), bg)
		var fg: Color = Color(0.15, 0.1, 0.03) if sel else Color(0.85, 0.83, 0.78)
		draw_string(font, Vector2(bx + 8, y + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, fg)
		y -= 24.0

func _draw_reload(font: Font, vp: Vector2) -> void:
	var p = arena.get_local_player()
	if p == null or not is_instance_valid(p) or not p.reloading:
		return
	var c := vp / 2.0
	var w := 160.0
	var x := c.x - w / 2.0
	var y := c.y + 40.0
	draw_rect(Rect2(x, y, w, 12), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(x + 2, y + 2, (w - 4) * p.reload_progress(), 8), Color(0.95, 0.8, 0.3))
	draw_string(font, Vector2(x, y - 6), "RELOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0.95, 0.9, 0.75))

func _draw_map_name(font: Font) -> void:
	draw_string(font, Vector2(36, 38), str(arena.map_name).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.85, 0.5))
	draw_string(font, Vector2(36, 56), "SPUD BLASTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(0.7, 0.66, 0.55))

func _draw_notify(font: Font, vp: Vector2) -> void:
	if _now() > _notify_until or _notify_text == "":
		return
	var alpha := clampf((_notify_until - _now()) / 2.0, 0.0, 1.0)
	var ts := font.get_string_size(_notify_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(font, Vector2(vp.x / 2.0 - ts.x / 2.0, vp.y * 0.62), _notify_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.92, 0.8, alpha))

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
	var y := 92.0
	draw_string(font, Vector2(x, y), "SCORES", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GOLD)
	y += 26.0
	for row in rows:
		var me: bool = row["pid"] == FpsNetwork.local_id()
		var col: Color = Color(1, 0.95, 0.6) if me else Color(0.9, 0.88, 0.82)
		var line := "%-14s %d" % [str(row["name"]).left(14), row["frags"]]
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
		y += 22.0

func _draw_controls(font: Font, vp: Vector2) -> void:
	draw_string(font, Vector2(vp.x / 2.0 - 320, vp.y - 18),
			"WASD move · MOUSE look · LMB/F shoot · RMB aim · 1-5/Q/scroll swap · R reload · SPACE jump · ESC pause",
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
	draw_string(font, Vector2(cx - tsz.x / 2.0, 110), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color.GOLD)

	var win_name := _name_for(arena.winner_id)
	var won := "%s wins!" % win_name if arena.winner_id != -1 else "Time!"
	if arena.winner_id == FpsNetwork.local_id():
		won = "You win!"
	var ws := font.get_string_size(won, HORIZONTAL_ALIGNMENT_CENTER, -1, 30)
	draw_string(font, Vector2(cx - ws.x / 2.0, 158), won,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.95, 0.75))

	var y := 210.0
	var rank := 1
	for row in _ranked():
		var line := "#%d   %-16s   %d frags" % [rank, str(row["name"]).left(16), row["frags"]]
		var me: bool = row["pid"] == FpsNetwork.local_id()
		draw_string(font, Vector2(cx - 180, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				Color(1, 0.95, 0.6) if me else Color.WHITE)
		y += 30.0
		rank += 1

	_draw_payout(font, vp, cx, y + 8.0)

	draw_string(font, Vector2(cx - 130, vp.y - 60), "[ENTER] Back to menu",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.78, 0.7))

func _draw_payout(font: Font, vp: Vector2, cx: float, y: float) -> void:
	var pay: Dictionary = arena.payout
	if pay.is_empty():
		return
	var box_w := 360.0
	var box_h := 110.0
	var bx := cx - box_w / 2.0
	draw_rect(Rect2(bx, y, box_w, box_h), Color(0.12, 0.1, 0.06, 0.95))
	draw_rect(Rect2(bx, y, box_w, box_h), Color(0.85, 0.68, 0.3, 0.6), false, 2.0)
	draw_string(font, Vector2(bx + 16, y + 26), "PAYOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.95, 0.85, 0.5))
	var coins := int(pay.get("coins", 0))
	var starch := int(pay.get("starch", 0))
	draw_string(font, Vector2(bx + 16, y + 56), "Coins  +%d" % coins,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.35))
	var st_col: Color = Color(0.6, 0.95, 0.85) if starch > 0 else Color(0.55, 0.55, 0.5)
	draw_string(font, Vector2(bx + 16, y + 84), "Starch +%d" % starch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, st_col)
	if starch == 0:
		draw_string(font, Vector2(bx + 150, y + 84), "(win to earn starch)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.58, 0.5))
	# running totals
	draw_string(font, Vector2(bx + 200, y + 56), "Wallet: %d" % SaveDataManager.wallet(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.8, 0.75, 0.6))
	draw_string(font, Vector2(bx + 200, y + 84), "Starch: %d" % SaveDataManager.starch(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.85, 0.8))

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
